-- ai-judge 5단계: 증거 제출 수락, 속도전 판정 기록, 증거 비공개(Storage 정책 교체).
--
-- 근거: docs/specs/ai-judge/design.md "흐름 5", "Storage", "RPC — 서버 전용", decisions 5·6·7·53·55·60·65.
--
-- 핵심 규칙
--   - 증거는 앱 카메라로 찍은 사진만이다. 촬영 시각은 서버가 수신 시각과 대조하는 데만 쓰고
--     승부 기준 시각은 언제나 서버 `submitted_at`이다(클라이언트 시간을 믿지 않는다).
--   - 거부된 사진(매칭 전 촬영, 10분 이상 차이, 마감 후)은 행을 만들지 않는다. 그래서 어떤 횟수에도
--     들어가지 않는다. 업로드된 오브젝트는 Edge Function이 service 롤로 지운다.
--   - 속도전 판정은 참가자당 대결마다 5회(passed + failed)다. AI 실패(error)는 세지 않는다.
--   - 진행 중에는 상대의 사진도 판정 사유도 서버가 내주지 않는다. 종결된 뒤에만 열린다.
--
-- 권한 구조
--   accept_submission / record_speed_verdict: Edge Function(service_role)만 부른다. 사용자 id는
--   Edge가 JWT로 확인한 값을 p_user_id로 넘긴다. 그래서 CLAUDE.md의 `auth.uid()` 로그인 가드 대신
--   authenticated까지 EXECUTE를 회수한다(service 롤·cron에는 uid가 없어 가드를 두면 항상 실패한다 —
--   기존 settle_expired_battles·begin_criteria_call과 같은 예외다).
--   sweep_stale_submissions: cron 전용. 같은 이유로 가드 없이 EXECUTE를 전부 회수한다.

-- ---------------------------------------------------------------------------
-- Storage(battle_evidence) 정책 전면 교체
-- ---------------------------------------------------------------------------
-- 상호 승인 시절 정책은 "참가자면 상대 사진도 언제든 읽기"였다. 새 규칙에서는 판정 전 상대 사진을
-- 베껴 더 잘 찍는 것을 막아야 하므로(결정 20) 종결 전에는 서명 URL 발급 자체가 실패해야 한다.
-- createSignedUrl도 이 select 정책을 거치므로 정책 하나로 "화면에 안 보임"이 아니라 "서버가 안 줌"이 된다.
drop policy "participants can upload own evidence" on storage.objects;
drop policy "participants can update own evidence" on storage.objects;
drop policy "participants can read battle evidence" on storage.objects;
drop policy "participants can delete own evidence" on storage.objects;

-- 업로드: 본인 폴더({battle_id}/{user_id}/...)에, 진행 중이고 마감 전인 내 대결에만.
-- 참가자 비교를 `auth.uid() in (...)`처럼 쓰지 않고 등호 두 개로 쓴다. 비로그인이면 두 비교가 모두
-- null이라 정책이 통과하지 않는다(`not in`이 null에서 통과하던 함정의 반대 방향이라 안전하다).
create policy "participants can upload evidence to own folder"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'battle_evidence'
    and (storage.foldername(name))[2] = auth.uid()::text
    and exists (
      select 1 from public.battles b
      where b.id::text = (storage.foldername(name))[1]
        and (auth.uid() = b.creator_id or auth.uid() = b.opponent_id)
        and b.status = 'active'
        and b.deadline_at > now()
    )
  );

-- 덮어쓰기(update) 정책은 두지 않는다. 제출마다 새 파일을 올려 속도전 시도 이력의 사진을 보존한다.

-- 조회: 내 사진은 언제든, 상대 사진은 대결이 종결된 뒤에만.
create policy "users can read own evidence or finished battle evidence"
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'battle_evidence'
    and (
      (storage.foldername(name))[2] = auth.uid()::text
      or exists (
        select 1 from public.battles b
        where b.id::text = (storage.foldername(name))[1]
          and b.status in ('finished', 'draw', 'voided', 'cancelled', 'disputed')
          and (auth.uid() = b.creator_id or auth.uid() = b.opponent_id)
      )
    )
  );

-- 삭제: 본인 폴더만(탈퇴 직전 앱이 자기 사진을 지우는 경로, 기존 유지).
-- 거부된 업로드는 Edge Function이 service 롤로 지운다(RLS 우회).
create policy "participants can delete own evidence"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'battle_evidence'
    and (storage.foldername(name))[2] = auth.uid()::text
  );

-- ---------------------------------------------------------------------------
-- accept_submission: 사진 한 장을 제출로 받아들일지 판단하고 제출 행을 만든다
-- ---------------------------------------------------------------------------
-- 거부는 전부 예외로 끝나고 행을 만들지 않는다. 힌트 코드로 Edge Function이 사용자 문구를 고른다.
-- submitted_at을 여기서 now()로 찍는다 — 이 값이 속도전 승부 기준 시각이다.
create function public.accept_submission(
  p_user_id uuid,
  p_battle_id uuid,
  p_object_path text,
  p_captured_at timestamptz
)
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_battle public.battles%rowtype;
  v_now timestamptz := now();
  v_attempts integer;
  v_status text;
  v_submission public.battle_submissions%rowtype;
  v_both_submitted boolean := false;
begin
  if p_user_id is null then
    raise exception '사용자가 필요합니다.';
  end if;

  if p_object_path is null or length(btrim(p_object_path)) = 0 then
    raise exception '사진 경로가 필요합니다.';
  end if;

  if p_captured_at is null then
    raise exception '촬영 시각이 필요합니다.';
  end if;

  select * into v_battle from public.battles where id = p_battle_id for update;

  if v_battle is null then
    raise exception '대결을 찾을 수 없습니다.';
  end if;

  -- null에 안전한 형태. 비로그인(=null)이 통과하던 `not in` 함정을 피한다.
  if p_user_id is distinct from v_battle.creator_id
     and p_user_id is distinct from v_battle.opponent_id then
    raise exception '이 대결의 참가자가 아닙니다.';
  end if;

  -- 참가할 때 확인했지만 그 사이 철회했을 수 있다. 동의 없이 사진이 AI로 나가면 안 된다.
  perform 1 from public.ai_consents where user_id = p_user_id;
  if not found then
    raise exception using message = 'AI 데이터 제공 동의가 필요합니다.', hint = 'CONSENT_REQUIRED';
  end if;

  -- 종결됐거나 품질전 판정 중이면 더 낼 수 없다. 마감만 지난 경우는 아래에서 따로 구분해 알린다.
  if v_battle.status <> 'active' then
    raise exception using message = '제출할 수 있는 상태가 아닙니다.', hint = 'SUBMISSION_LOCKED';
  end if;

  if v_battle.deadline_at is null or v_battle.deadline_at <= v_now then
    raise exception using message = '마감이 지났습니다.', hint = 'DEADLINE_PASSED';
  end if;

  -- 경로 위조 차단. Storage 정책과 같은 규칙을 서버에서 한 번 더 본다.
  if p_object_path not like (p_battle_id::text || '/' || p_user_id::text || '/%') then
    raise exception '사진 경로가 올바르지 않습니다.';
  end if;

  -- 대결이 시작되기 전에 찍어 둔 사진은 이 대결의 증거가 아니다(결정 53).
  if v_battle.started_at is not null and p_captured_at < v_battle.started_at then
    raise exception using message = '대결 시작 전에 찍은 사진입니다.', hint = 'CAPTURED_BEFORE_START';
  end if;

  -- 촬영과 수신이 10분 이상 벌어지면 거부한다. 기기 시계가 앞선 경우도 같으므로 절댓값으로 본다.
  if abs(extract(epoch from (v_now - p_captured_at))) >= 600 then
    raise exception using message = '촬영 시각과 수신 시각이 너무 벌어졌습니다.', hint = 'CAPTURE_TIME_MISMATCH';
  end if;

  if v_battle.type = 'speed' then
    -- 통과하면 그 참가자의 제출은 잠긴다(통과 시각이 바뀌지 않는다).
    perform 1 from public.battle_submissions
    where battle_id = p_battle_id and user_id = p_user_id and status = 'passed';
    if found then
      raise exception using message = '이미 기준을 통과했습니다.', hint = 'SUBMISSION_LOCKED';
    end if;

    perform 1 from public.battle_submissions
    where battle_id = p_battle_id and user_id = p_user_id and status = 'judging';
    if found then
      raise exception using message = '앞선 제출을 판정하는 중입니다.', hint = 'JUDGING_IN_PROGRESS';
    end if;

    -- 판정 5회(passed + failed). AI 실패(error)는 세지 않는다(결정 60).
    select count(*) into v_attempts
    from public.battle_submissions
    where battle_id = p_battle_id and user_id = p_user_id and status in ('passed', 'failed');

    if v_attempts >= 5 then
      raise exception using message = '판정 횟수를 모두 썼습니다.', hint = 'ATTEMPTS_EXHAUSTED';
    end if;

    v_status := 'judging';
  else
    -- 품질전은 한 번만 낼 수 있다. 판정 잡 생성과 judging 전환은 6단계에서 이 함수에 더한다.
    perform 1 from public.battle_submissions
    where battle_id = p_battle_id and user_id = p_user_id and status = 'submitted';
    if found then
      raise exception using message = '이미 제출했습니다.', hint = 'SUBMISSION_LOCKED';
    end if;

    v_status := 'submitted';
  end if;

  insert into public.battle_submissions (
    battle_id, user_id, object_path, captured_at, submitted_at, status, judging_started_at
  )
  values (
    p_battle_id, p_user_id, p_object_path, p_captured_at, v_now, v_status,
    case when v_status = 'judging' then v_now else null end
  )
  returning * into v_submission;

  -- "상대가 제출했어요"를 알리는 요약. 사유도 경로도 담지 않으므로 상대에게 보여도 된다.
  update public.battle_participants
  set first_submitted_at = coalesce(first_submitted_at, v_now)
  where battle_id = p_battle_id and user_id = p_user_id;

  if v_battle.type = 'quality' then
    select count(distinct user_id) = 2 into v_both_submitted
    from public.battle_submissions
    where battle_id = p_battle_id and status = 'submitted';
  end if;

  return jsonb_build_object(
    'submission_id', v_submission.id,
    'type', v_battle.type,
    'status', v_submission.status,
    'both_submitted', v_both_submitted
  );
end;
$$;

comment on function public.accept_submission is
  '증거 사진 제출 수락(서버 전용). 거부는 행을 만들지 않아 어떤 횟수에도 들어가지 않는다. submitted_at이 속도전 승부 기준 시각이다.';

-- ---------------------------------------------------------------------------
-- record_speed_verdict: 속도전 AI 판정 결과를 제출 행에 기록하고 종결 여부를 본다
-- ---------------------------------------------------------------------------
-- judging 상태인 행만 갱신한다. sweep이 먼저 error로 바꿨거나 대결이 이미 끝났으면 늦게 도착한
-- 판정은 버린다(applied=false). 승패 계산은 resolve_battle -> speed_outcome이 한다.
create function public.record_speed_verdict(
  p_submission_id bigint,
  p_verdict text,
  p_reason text,
  p_model text
)
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_submission public.battle_submissions%rowtype;
  v_battle_status text;
begin
  if p_verdict not in ('passed', 'failed', 'error') then
    raise exception '판정 값이 올바르지 않습니다.';
  end if;

  update public.battle_submissions
  set status = p_verdict,
      -- AI 실패에는 사유가 없다. 합격/불합격 사유는 자르지 않고 그대로 남긴다.
      reason = case when p_verdict = 'error' then null else nullif(btrim(p_reason), '') end,
      meets_criteria = case
        when p_verdict = 'passed' then true
        when p_verdict = 'failed' then false
        else null
      end,
      ai_model = p_model
  where id = p_submission_id and status = 'judging'
  returning * into v_submission;

  if not found then
    select b.status into v_battle_status
    from public.battle_submissions s
    join public.battles b on b.id = s.battle_id
    where s.id = p_submission_id;

    return jsonb_build_object('applied', false, 'battle_status', v_battle_status);
  end if;

  -- 진행 중에도 상대에게 보여도 되는 요약(합격/불합격, 사용 횟수, 통과 시각)만 갱신한다.
  if p_verdict in ('passed', 'failed') then
    update public.battle_participants p
    set attempts_used = (
          select count(*)
          from public.battle_submissions s
          where s.battle_id = v_submission.battle_id
            and s.user_id = v_submission.user_id
            and s.status in ('passed', 'failed')
        ),
        last_verdict = p_verdict,
        passed_at = case when p_verdict = 'passed' then v_submission.submitted_at else p.passed_at end
    where p.battle_id = v_submission.battle_id and p.user_id = v_submission.user_id;
  end if;

  v_battle_status := public.resolve_battle(v_submission.battle_id);

  return jsonb_build_object(
    'applied', true,
    'submission_id', v_submission.id,
    'battle_status', v_battle_status
  );
end;
$$;

comment on function public.record_speed_verdict is
  '속도전 판정 사실 기록(서버 전용). 승패·점수는 resolve_battle/finalize_battle이 정한다.';

-- ---------------------------------------------------------------------------
-- sweep_stale_submissions: 끊긴 판정 정리 (cron 1분)
-- ---------------------------------------------------------------------------
-- Edge 프로세스가 죽으면 judging 행이 남아 그 참가자의 다음 제출을 영원히 막는다.
-- Gemini 타임아웃 30초 + 이미지 전송 여유의 여러 배인 3분을 넘기면 error로 내린다
-- (error는 5회 상한에 세지 않으므로 사용자는 손해 없이 다시 낼 수 있다).
-- 함께 정리: 2분 넘게 in_progress인 기준 생성 호출(3단계에서 이 함수로 미뤄 둔 몫).
create function public.sweep_stale_submissions()
returns integer
language plpgsql
security definer set search_path = public
as $$
declare
  v_row record;
  v_swept integer := 0;
begin
  for v_row in
    select id, battle_id
    from public.battle_submissions
    where status = 'judging'
      and judging_started_at is not null
      and judging_started_at <= now() - interval '3 minutes'
    order by id
    for update skip locked
  loop
    update public.battle_submissions
    set status = 'error', reason = null
    where id = v_row.id;

    -- 이 제출이 사라져 결과가 확정될 수 있다(상대의 통과가 더는 역전당하지 않는 경우).
    perform public.resolve_battle(v_row.battle_id);

    v_swept := v_swept + 1;
  end loop;

  update public.ai_criteria_calls
  set status = 'failed'
  where status = 'in_progress'
    and created_at <= now() - interval '2 minutes';

  return v_swept;
end;
$$;

comment on function public.sweep_stale_submissions is
  '3분 넘게 판정 중인 제출을 error로 내리고(횟수 미산입) 종결 여부를 다시 본다. 2분 넘은 기준 호출도 failed로 정리한다. cron 전용.';

revoke execute on function public.accept_submission(uuid, uuid, text, timestamptz) from public, anon, authenticated;
revoke execute on function public.record_speed_verdict(bigint, text, text, text) from public, anon, authenticated;
revoke execute on function public.sweep_stale_submissions() from public, anon, authenticated;
grant execute on function public.accept_submission(uuid, uuid, text, timestamptz) to service_role;
grant execute on function public.record_speed_verdict(bigint, text, text, text) to service_role;
-- sweep은 pg_cron(소유자 postgres)이 부른다. service_role에는 주지 않는다.

-- ---------------------------------------------------------------------------
-- cron: ai-judge-tick (1분)
-- ---------------------------------------------------------------------------
-- 6단계에서 dispatch_quality_judgments()가 이 작업에 함께 붙는다. 지금은 sweep만 돈다.
-- 마감 정산(settle-expired-battles, 5분)은 기존 작업 그대로 둔다.
select cron.schedule(
  'ai-judge-tick',
  '* * * * *',
  $$select public.sweep_stale_submissions()$$
);
