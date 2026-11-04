-- push-notification 3단계: 대결 사건에서 알림 원장 적재.
--
-- 근거: docs/specs/push-notification/design.md "mutual-judge 반영"(2026-11-03 오너 결정)이
-- 대체한 사건 지점 표, spec.md "mutual-judge 반영", plan.md 3단계.
--
-- 핵심 규칙
--   - 알림은 이미 확정된 사실의 사본이다. 이 마이그레이션은 판정·점수·상태 전이를 한 줄도 바꾸지
--     않는다. 각 함수가 **이미 계산한 값**(outcome·score_delta_applied·status·제출 여부)을 읽어
--     원장에 담을 뿐이고, 규칙 판단을 새로 하는 곳은 하나도 없다.
--   - 사건 트랜잭션에서는 HTTP를 부르지 않는다. insert 한 행뿐이고, 그 insert조차
--     enqueue_notification 안의 예외 블록이 삼킨다(1단계 주석 참고). 알림이 판정을 되돌리지 못한다.
--   - 한 사건은 한 번만. unique (recipient_id, dedup_key) + on conflict do nothing이 물리적으로 막는다.
--   - 잠금화면에 나가도 되는 것만 payload에 담는다. 판정 사유(reason)·사진 경로(object_path)·
--     상대 표시 이름(display_name)은 어느 payload에도 넣지 않는다.
--
-- **설계 문서와 달라진 지점(2026-11-03 오너 결정, 문서에 함께 반영함)**
--   - N4(속도전 합격/불합격)의 발생 지점 record_speed_verdict는 20260922120000_judging_window.sql이
--     삭제했다(제출 즉시 AI 판정이 사라졌다). 그 자리를 **N4' "판정할 차례"**가 대신한다 —
--     판정 창을 여는 유일한 지점인 open_judging_window에서, 판정할 증거가 있는 쪽에 보낸다.
--     미판정은 승인으로 간주되므로(CLAUDE.md 도메인 규칙) 모르고 지나가면 손해가 확정된다.
--   - N3(상대가 사진을 냈다)은 **두 유형 공통**이 된다. 속도전을 뺐던 근거(제출 즉시 판정이
--     뒤따라 두 줄이 쌓인다)가 사라졌고, 지금은 속도전에서도 상대가 내는 순간 내 교체가 잠긴다.
--   - kind 두 개의 이름을 바꾼다(quality_submitted -> submitted, speed_verdict -> judge_turn).
--     3단계 전에는 아무도 원장에 넣지 않으므로 기존 행이 없다.
--   - claim_notifications에 judge_turn 폐기 조건을 더한다(아래 주석 참고).
--
-- 함수 본문은 전부 **가장 늦은 정의를 그대로 복사한 뒤** enqueue 호출만 끼워 넣었다. 기준이 된
-- 파일: join_battle=20260921120100, finalize_battle=20260915120300, open_judging_window·
-- accept_submission=20260922120000, void_battle·delete_account=20261029120000,
-- claim_notifications=20260920120000. 전부 create or replace이므로 GRANT는 그대로 남는다.

-- ---------------------------------------------------------------------------
-- kind 목록 교체
-- ---------------------------------------------------------------------------
-- 기존 행이 있으면 이 ALTER가 실패한다. 그 경우는 "3단계 전에 아무도 넣지 않는다"는 전제가 깨진
-- 것이므로 조용히 넘어가지 않고 멈추는 것이 맞다(원격 적용 전에 0행을 확인한다).
alter table public.notification_outbox
  drop constraint notification_outbox_kind_check;

alter table public.notification_outbox
  add constraint notification_outbox_kind_check
    check (kind in ('matched', 'finished', 'voided', 'submitted',
                    'judge_turn', 'cancelled', 'deadline_soon'));

-- ---------------------------------------------------------------------------
-- N1 — join_battle: 모집에 상대가 참가(매칭)
-- ---------------------------------------------------------------------------
-- 마감이 이 순간부터 흐르므로 생성자가 가장 늦게 알면 안 되는 사건이다.
-- 기준: 20260921120100_custom_duration.sql. 바뀐 것은 deadline_at을 returning으로 받는 것과
-- 맨 끝 enqueue 한 번뿐이다.
create or replace function public.join_battle(p_battle_id uuid, p_criteria_version integer)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_battle public.battles%rowtype;
  v_today date := (now() at time zone 'Asia/Seoul')::date;
  v_deadline_at timestamptz;
begin
  if auth.uid() is null then
    raise exception '로그인이 필요합니다.';
  end if;

  -- 잠금 순서는 "내 동의 행 -> 대결"이다(withdraw_ai_consent와 같은 순서라 교착이 없다).
  perform 1 from public.ai_consents where user_id = auth.uid() for share;
  if not found then
    raise exception using message = 'AI 데이터 제공 동의가 필요합니다.', hint = 'CONSENT_REQUIRED';
  end if;

  select * into v_battle from public.battles where id = p_battle_id for update;

  if v_battle is null then
    raise exception '대결을 찾을 수 없습니다.';
  end if;

  if v_battle.status <> 'pending' or v_battle.opponent_id is not null then
    raise exception using message = '이미 매칭되었거나 종료된 모집입니다.', hint = 'ALREADY_MATCHED';
  end if;

  if auth.uid() = v_battle.creator_id then
    raise exception '본인이 등록한 모집에는 참가할 수 없습니다.';
  end if;

  -- 참가자가 본 기준과 지금 기준이 다르면 참가가 성립하지 않는다(결정 46).
  if v_battle.criteria_version is distinct from p_criteria_version then
    raise exception using message = '기준이 바뀌었습니다.', hint = 'CRITERIA_CHANGED';
  end if;

  perform 1 from public.daily_battle_slots where user_id = auth.uid() and kst_date = v_today;
  if found then
    raise exception using message = '오늘 한도를 이미 썼습니다.', hint = 'MY_DAILY_LIMIT';
  end if;

  perform 1 from public.daily_battle_slots where user_id = v_battle.creator_id and kst_date = v_today;
  if found then
    raise exception using message = '모집한 사람이 오늘 한도를 다 썼습니다.', hint = 'CREATOR_DAILY_LIMIT';
  end if;

  -- 한 행씩 따로 넣어, 동시 참가 경합으로 PK에 걸렸을 때 누구의 한도인지 구분해 알린다.
  begin
    insert into public.daily_battle_slots (user_id, kst_date, battle_id)
    values (auth.uid(), v_today, p_battle_id);
  exception when unique_violation then
    raise exception using message = '오늘 한도를 이미 썼습니다.', hint = 'MY_DAILY_LIMIT';
  end;

  begin
    insert into public.daily_battle_slots (user_id, kst_date, battle_id)
    values (v_battle.creator_id, v_today, p_battle_id);
  exception when unique_violation then
    raise exception using message = '모집한 사람이 오늘 한도를 다 썼습니다.', hint = 'CREATOR_DAILY_LIMIT';
  end;

  update public.battles
  set opponent_id = auth.uid(),
      status = 'active',
      started_at = now(),
      deadline_at = now() + make_interval(mins => v_battle.duration_minutes)
  where id = p_battle_id
  returning deadline_at into v_deadline_at;

  insert into public.battle_participants (battle_id, user_id)
  values (p_battle_id, auth.uid());

  -- N1. 참가한 본인에게는 보내지 않는다(내 행동의 결과라 알릴 것이 없다).
  -- 참가자 이름을 담지 않는다 - 표시 이름은 소셜 로그인에서 온 실명일 수 있다.
  perform public.enqueue_notification(
    v_battle.creator_id,
    'matched',
    p_battle_id,
    'matched:' || p_battle_id::text,
    jsonb_build_object(
      'title', v_battle.title,
      'battle_type', v_battle.type,
      'deadline_at', v_deadline_at
    )
  );
end;
$$;

comment on function public.join_battle(uuid, integer) is
  '모집 참가. 내가 확인한 기준 버전으로만 참가하며, 매칭되는 순간 양쪽의 그날 한도를 소진하고 '
  '제출 창 마감(duration_minutes 분 뒤)이 걸린다. 생성자에게 매칭 알림을 적재한다.';

-- ---------------------------------------------------------------------------
-- N2 — finalize_battle: 승패가 있는 종결과 점수 변화
-- ---------------------------------------------------------------------------
-- 종결 세 경로(상호 판정·포기/동의 철회·마감 정산)가 모두 이 함수를 지나므로 발송 지점도 한 곳이다.
-- 기준: 20260915120300_ai_judge_transitions.sql. 바뀐 것은 루프 끝의 enqueue 한 번뿐이다.
create or replace function public.finalize_battle(
  p_battle_id uuid,
  p_status text,
  p_winner_id uuid,
  p_creator_outcome text,
  p_opponent_outcome text
)
returns void
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_battle public.battles%rowtype;
  v_participant record;
  v_delta integer;
  v_old_score integer;
  v_new_score integer;
begin
  select * into v_battle from public.battles where id = p_battle_id for update;

  if v_battle is null then
    raise exception '대결을 찾을 수 없습니다.';
  end if;

  if v_battle.status not in ('active', 'judging') then
    raise exception '진행 중인 대결만 종결할 수 있습니다. (현재: %)', v_battle.status;
  end if;

  if v_battle.opponent_id is null then
    raise exception '상대가 없는 대결은 종결할 수 없습니다.';
  end if;

  -- 호출부 실수로 규칙과 어긋난 결과가 기록되지 않게 모양을 검사한다.
  -- outcome이 null이면 점수 계산이 null -> greatest(null, 0) = 0이 되어 점수가 날아가므로 먼저 막는다.
  if p_creator_outcome is null or p_opponent_outcome is null then
    raise exception '종결 결과 값이 비어 있습니다.';
  end if;

  if p_status = 'finished' then
    if p_winner_id is null
       or (p_winner_id is distinct from v_battle.creator_id
           and p_winner_id is distinct from v_battle.opponent_id) then
      raise exception '승자가 이 대결의 참가자가 아닙니다.';
    end if;
    if (p_winner_id = v_battle.creator_id and (p_creator_outcome <> 'win'
          or p_opponent_outcome not in ('completed_loss', 'loss', 'forfeit')))
       or (p_winner_id = v_battle.opponent_id and (p_opponent_outcome <> 'win'
          or p_creator_outcome not in ('completed_loss', 'loss', 'forfeit'))) then
      raise exception '승자와 결과 값이 맞지 않습니다.';
    end if;
  elsif p_status = 'draw' then
    if p_winner_id is not null or p_creator_outcome <> 'draw' or p_opponent_outcome <> 'draw' then
      raise exception '무승부에는 승자가 없고 양쪽 결과가 draw여야 합니다.';
    end if;
  else
    raise exception '종결 상태가 올바르지 않습니다: %', p_status;
  end if;

  update public.battles
  set status = p_status,
      winner_id = p_winner_id,
      finished_at = now()
  where id = p_battle_id;

  for v_participant in
    select v_battle.creator_id as user_id, p_creator_outcome as outcome
    union all
    select v_battle.opponent_id, p_opponent_outcome
  loop
    v_delta := public.outcome_score_delta(v_participant.outcome);

    -- 가입 트리거·백필로 행이 있어야 하지만, 없으면 0점에서 시작한다.
    insert into public.player_stats (user_id)
    values (v_participant.user_id)
    on conflict (user_id) do nothing;

    select score into v_old_score
    from public.player_stats
    where user_id = v_participant.user_id
    for update;

    v_new_score := greatest(v_old_score + v_delta, 0);

    update public.player_stats
    set score = v_new_score,
        wins = wins + case when v_participant.outcome = 'win' then 1 else 0 end,
        losses = losses + case when v_participant.outcome in ('completed_loss', 'loss', 'forfeit') then 1 else 0 end,
        draws = draws + case when v_participant.outcome = 'draw' then 1 else 0 end
    where user_id = v_participant.user_id;

    update public.battle_participants
    set outcome = v_participant.outcome,
        score_delta_applied = v_new_score - v_old_score
    where battle_id = p_battle_id and user_id = v_participant.user_id;

    -- N2. 포기한 본인에게는 보내지 않는다 - 내 행동의 결과라 알릴 것이 없다.
    -- forfeited_by는 forfeit_battle이 이 함수를 부르기 전에 기록하므로 위 select가 이미 본다.
    -- 점수는 '이번 변화'(하한 0에 걸리면 0)만 담는다. 누적 점수·승패 카운터는 담지 않는다(spec).
    if v_battle.forfeited_by is distinct from v_participant.user_id then
      perform public.enqueue_notification(
        v_participant.user_id,
        'finished',
        p_battle_id,
        'finished:' || p_battle_id::text,
        jsonb_build_object(
          'title', v_battle.title,
          'battle_type', v_battle.type,
          'outcome', v_participant.outcome,
          'score_delta', v_new_score - v_old_score
        )
      );
    end if;
  end loop;
end;
$$;

comment on function public.finalize_battle is
  '승패가 있는 종결의 유일한 적용 지점(상태·승자·outcome·점수 하한 0·카운터). 양쪽에 종결 알림을 '
  '적재한다(포기한 본인 제외). 내부 전용.';

-- ---------------------------------------------------------------------------
-- N4' — open_judging_window: 판정할 차례다
-- ---------------------------------------------------------------------------
-- 판정 창을 여는 지점은 이 함수 하나뿐이다(accept_submission의 양쪽 제출, settle_expired_battles의
-- 마감). 그래서 "내 차례"를 알리는 지점도 한 곳이다.
--
-- 받는 사람이 "상대가 제출한 쪽"인 이유: 2인 대결이라 판정 대상은 언제나 상대의 증거다. 상대가
-- 내지 않았으면 판정할 것이 없어 판정 화면도 열리지 않는다(앱의 battleErrorNothingToJudge).
-- 속도전이 한쪽만 제출한 채 마감되면 제출하지 않은 쪽만 받는다.
--
-- 이 알림이 중요한 이유: 판정 기한은 마감과 별개로 24시간 고정이고 **미판정은 승인으로 간주**된다.
-- 모르고 지나가면 상대의 증거를 그대로 승인한 것이 되므로, 손해가 시간으로 확정되는 경우다.
--
-- 기준: 20260922120000_judging_window.sql. update에 returning을 붙이고 enqueue를 더했다.
create or replace function public.open_judging_window(p_battle_id uuid)
returns void
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_battle public.battles%rowtype;
  v_creator_submitted boolean;
  v_opponent_submitted boolean;
  v_payload jsonb;
begin
  update public.battles
  set status = 'judging',
      judging_opened_at = now(),
      judge_deadline_at = now() + interval '24 hours'
  where id = p_battle_id
  returning * into v_battle;

  if v_battle.id is null or v_battle.opponent_id is null then
    return;
  end if;

  select exists (
    select 1 from public.battle_submissions
    where battle_id = p_battle_id and user_id = v_battle.creator_id
  ) into v_creator_submitted;

  select exists (
    select 1 from public.battle_submissions
    where battle_id = p_battle_id and user_id = v_battle.opponent_id
  ) into v_opponent_submitted;

  -- 상대의 제출 시각·사진·판정 내용은 담지 않는다. "판정할 것이 있다"와 기한만 담는다.
  v_payload := jsonb_build_object(
    'title', v_battle.title,
    'battle_type', v_battle.type,
    'judge_deadline_at', v_battle.judge_deadline_at
  );

  -- 생성자는 상대가 냈을 때, 상대는 생성자가 냈을 때 판정할 것이 생긴다.
  if v_opponent_submitted then
    perform public.enqueue_notification(
      v_battle.creator_id, 'judge_turn', p_battle_id,
      'judge:' || p_battle_id::text, v_payload
    );
  end if;

  if v_creator_submitted then
    perform public.enqueue_notification(
      v_battle.opponent_id, 'judge_turn', p_battle_id,
      'judge:' || p_battle_id::text, v_payload
    );
  end if;
end;
$$;

comment on function public.open_judging_window is
  '판정 창을 연다(서버 시각 + 24시간 고정). accept_submission·settle_expired_battles만 부른다. '
  '판정할 증거가 있는 참가자에게 "판정할 차례" 알림을 적재한다. 내부 전용.';

-- ---------------------------------------------------------------------------
-- N3 — accept_submission: 상대가 사진을 냈다 (두 유형 공통)
-- ---------------------------------------------------------------------------
-- **인자 시그니처를 유지한다.** 배포된 submit-evidence Edge Function이 이 시그니처로 부르므로
-- 바꾸면 옛 오버로드를 계속 부르게 된다(2단계 함정 주석 그대로).
--
-- 판정 창이 열리는 제출에는 N3를 보내지 않는다: 같은 순간에 "상대가 냈어요"와 "판정할 차례예요"가
-- 잠금화면에 두 줄로 쌓인다. N4'가 두 사실을 모두 담으므로 정보량이 더 크다(design 결정 1·2와 같은 처리).
-- 속도전 교체 제출은 dedup_key가 같아 두 번째부터 무시된다 - "상대가 냈다"는 사실은 한 번만 알린다.
--
-- 기준: 20260922120000_judging_window.sql. 바뀐 것은 gate 분기의 else 한 줄뿐이다.
create or replace function public.accept_submission(
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
  v_opponent_id uuid;
  v_my_submission public.battle_submissions%rowtype;
  v_opponent_submitted boolean;
  v_submission public.battle_submissions%rowtype;
  v_replaced_path text;
  v_gate text;
  v_judging_opened boolean := false;
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

  if p_user_id is distinct from v_battle.creator_id
     and p_user_id is distinct from v_battle.opponent_id then
    raise exception '이 대결의 참가자가 아닙니다.';
  end if;

  -- 참가할 때 확인했지만 그 사이 철회했을 수 있다. 동의 없이 사진이 AI로 나가면 안 된다.
  perform 1 from public.ai_consents where user_id = p_user_id;
  if not found then
    raise exception using message = 'AI 데이터 제공 동의가 필요합니다.', hint = 'CONSENT_REQUIRED';
  end if;

  -- 판정 창이 열렸거나 종결됐으면 더 낼 수 없다. 마감만 지난 경우는 아래에서 따로 구분해 알린다.
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

  -- 대결이 시작되기 전에 찍어 둔 사진은 이 대결의 증거가 아니다.
  if v_battle.started_at is not null and p_captured_at < v_battle.started_at then
    raise exception using message = '대결 시작 전에 찍은 사진입니다.', hint = 'CAPTURED_BEFORE_START';
  end if;

  -- 촬영과 수신이 10분 이상 벌어지면 거부한다. 기기 시계가 앞선 경우도 같으므로 절댓값으로 본다.
  if abs(extract(epoch from (v_now - p_captured_at))) >= 600 then
    raise exception using message = '촬영 시각과 수신 시각이 너무 벌어졌습니다.', hint = 'CAPTURE_TIME_MISMATCH';
  end if;

  v_opponent_id := case
    when p_user_id = v_battle.creator_id then v_battle.opponent_id
    else v_battle.creator_id
  end;

  select * into v_my_submission from public.battle_submissions
  where battle_id = p_battle_id and user_id = p_user_id
  for update;

  select exists (
    select 1 from public.battle_submissions where battle_id = p_battle_id and user_id = v_opponent_id
  ) into v_opponent_submitted;

  if v_my_submission.id is not null then
    -- 이미 냈다. status가 여전히 active이므로 상대는 아직 내지 않았다(위 불변식).
    if v_battle.type <> 'speed' then
      raise exception using message = '이미 제출했습니다.', hint = 'SUBMISSION_LOCKED';
    end if;

    v_replaced_path := v_my_submission.object_path;

    update public.battle_submissions
    set object_path = p_object_path,
        captured_at = p_captured_at,
        submitted_at = v_now,
        meets_criteria = null,
        verdict_source = null,
        reason = null,
        ai_model = null
    where id = v_my_submission.id
    returning * into v_submission;
  else
    insert into public.battle_submissions (battle_id, user_id, object_path, captured_at, submitted_at)
    values (p_battle_id, p_user_id, p_object_path, p_captured_at, v_now)
    returning * into v_submission;

    update public.battle_participants
    set has_submitted = true
    where battle_id = p_battle_id and user_id = p_user_id;
  end if;

  v_gate := public.judging_gate(v_battle.type, true, v_opponent_submitted, false);

  if v_gate = 'open' then
    perform public.open_judging_window(p_battle_id);
    v_judging_opened := true;
  else
    -- N3. 상대에게 "냈다"는 사실 하나만. 사진 경로도, 제출 시각도, 몇 번 교체했는지도 담지 않는다
    -- (마감 전에 상대에게 보이는 것은 제출 사실뿐이라는 도메인 규칙 그대로다).
    perform public.enqueue_notification(
      v_opponent_id,
      'submitted',
      p_battle_id,
      'sub:' || p_battle_id::text,
      jsonb_build_object('title', v_battle.title, 'battle_type', v_battle.type)
    );
  end if;

  return jsonb_build_object(
    'submission_id', v_submission.id,
    'replaced_object_path', v_replaced_path,
    'judging_opened', v_judging_opened,
    'battle_status', case when v_judging_opened then 'judging' else v_battle.status end
  );
end;
$$;

comment on function public.accept_submission is
  '증거 사진 제출(서버 전용). status=active인 동안 내 행이 있으면 교체(속도전만)로 덮어쓰고, '
  '없으면 새로 만든다. 양쪽이 모두 내면 같은 트랜잭션에서 판정 창을 연다. 창이 열리지 않는 제출은 '
  '상대에게 제출 알림을 적재한다. 시그니처 유지(배포된 submit-evidence가 이 시그니처로 부른다).';

-- ---------------------------------------------------------------------------
-- N2' — void_battle: 무효 종결
-- ---------------------------------------------------------------------------
-- 기준: 20261029120000_ai_rejudgment.sql. 바뀐 것은 끝의 enqueue 두 번뿐이다.
create or replace function public.void_battle(p_battle_id uuid)
returns void
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_battle public.battles%rowtype;
  v_payload jsonb;
begin
  select * into v_battle from public.battles where id = p_battle_id for update;

  if v_battle is null then
    raise exception '대결을 찾을 수 없습니다.';
  end if;

  if v_battle.status not in ('active', 'judging') then
    raise exception '진행 중인 대결만 무효로 만들 수 있습니다. (현재: %)', v_battle.status;
  end if;

  update public.battles
  set status = 'voided',
      finished_at = now()
  where id = p_battle_id;

  delete from public.ai_judgment_jobs where battle_id = p_battle_id;

  delete from public.daily_battle_slots
  where battle_id = p_battle_id
    and kst_date = (now() at time zone 'Asia/Seoul')::date;

  -- N2'. 실패 원인·사유는 담지 않는다("판정이 무효가 됐다"와 "점수·전적에 반영되지 않는다"까지만).
  -- opponent_id가 null이면 enqueue_notification이 조용히 지나간다.
  v_payload := jsonb_build_object('title', v_battle.title, 'battle_type', v_battle.type);

  perform public.enqueue_notification(
    v_battle.creator_id, 'voided', p_battle_id,
    'voided:' || p_battle_id::text, v_payload
  );
  perform public.enqueue_notification(
    v_battle.opponent_id, 'voided', p_battle_id,
    'voided:' || p_battle_id::text, v_payload
  );
end;
$$;

comment on function public.void_battle is
  'AI 재판정이 끝내 실패했을 때의 무효 종결. 점수 변화 없음, 매칭일이 오늘(KST)인 슬롯만 반환, '
  '남은 재판정 잡 삭제, 양쪽에 무효 알림 적재. 내부 전용.';

-- ---------------------------------------------------------------------------
-- N5 — delete_account: 상대 탈퇴로 대결이 취소됐다
-- ---------------------------------------------------------------------------
-- **20261029120000_ai_rejudgment.sql의 정의(가장 늦은 정의)를 기반으로** 고쳤다. 일곱 번 재정의된
-- 함수라 옛 정의를 베끼면 기준 증서·동의 기록·알림 토큰 삭제가 조용히 사라진다. 이번에 더한 것은
-- 1번 단계 뒤의 N5 적재 루프 하나뿐이고, 인자 없는 시그니처와 나머지 단계(2~9)는 그대로다.
--
-- 적재 위치가 슬롯 삭제 **앞**인 이유: 문구가 "오늘 대결 한도가 돌아왔어요"를 붙일지 말지를
-- slot_returned로 가르는데, 슬롯을 지운 뒤에는 그 사실을 알 길이 없다.
create or replace function public.delete_account()
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_cancelled_ids uuid[];
  v_cancelled record;
  v_today date := (now() at time zone 'Asia/Seoul')::date;
begin
  if v_user_id is null then
    raise exception '로그인이 필요합니다.';
  end if;

  -- 1. 끝나지 않은 대결은 승자·점수 변화 없이 취소한다. 속도전에서 이미 통과했어도 취소다(결정 42).
  with cancelled as (
    update public.battles
    set status = 'cancelled', finished_at = now()
    where status in ('pending', 'active', 'judging')
      and (creator_id = v_user_id or opponent_id = v_user_id)
    returning id
  )
  select coalesce(array_agg(id), '{}') into v_cancelled_ids from cancelled;

  -- N5. 남은 상대에게만. 상대가 없는 pending 모집은 알릴 사람이 없다(other_id가 null).
  -- 탈퇴한 사람의 이름은 담지 않는다.
  for v_cancelled in
    select b.id,
           b.title,
           case when b.creator_id = v_user_id then b.opponent_id else b.creator_id end as other_id
    from public.battles b
    where b.id = any (v_cancelled_ids)
  loop
    perform public.enqueue_notification(
      v_cancelled.other_id,
      'cancelled',
      v_cancelled.id,
      'cancelled:' || v_cancelled.id::text,
      jsonb_build_object(
        'title', v_cancelled.title,
        'slot_returned', exists (
          select 1 from public.daily_battle_slots s
          where s.battle_id = v_cancelled.id
            and s.user_id = v_cancelled.other_id
            and s.kst_date = v_today
        )
      )
    );
  end loop;

  -- 매칭된 날이 오늘(KST)인 슬롯만 지워 남은 상대의 오늘 한도를 돌려준다(결정 49·63).
  delete from public.daily_battle_slots
  where battle_id = any (v_cancelled_ids)
    and kst_date = v_today;

  -- 판정 대기 중이던 AI 재판정 잡. 대결이 취소됐으므로 판정할 것이 없다.
  delete from public.ai_judgment_jobs where battle_id = any (v_cancelled_ids);

  -- 2. 개인 투두.
  delete from public.todos where user_id = v_user_id;

  -- 3. 증거 사진 경로는 개인 데이터라 끊는다. 사진 파일은 앱이 이 RPC 직전에 Storage API로 지운다.
  --    제출 행 자체와 사유·시각은 남은 상대의 전적을 설명하는 판정 기록이라 남긴다.
  update public.battle_submissions
  set object_path = null
  where user_id = v_user_id;

  -- 4. 한도 원장과 점수. 묘비 사용자의 점수는 공개 대상이 아니다.
  delete from public.daily_battle_slots where user_id = v_user_id;
  delete from public.player_stats where user_id = v_user_id;

  -- 5. 기준 증서와 호출 원장. 대결이 성립하기 전의 초안이라 보존할 이유가 없다.
  delete from public.criteria_checks where user_id = v_user_id;
  delete from public.ai_criteria_calls where user_id = v_user_id;

  -- 6. 동의·철회 기록. 탈퇴 후에는 남기지 않는다(decisions 68).
  delete from public.ai_consent_events where user_id = v_user_id;
  delete from public.ai_consents where user_id = v_user_id;

  -- 7. 알림 토큰과 내가 받을 알림. 개인정보처리방침의 "탈퇴 시 삭제"와 맞춘다
  --    (push-notification spec "탈퇴하면 그 계정의 알림 등록 정보가 함께 사라진다").
  --    내가 수신자인 행만 지운다 - 상대가 받을 알림(방금 적재한 N5 포함)은 상대의 기록이다.
  delete from public.device_push_tokens where user_id = v_user_id;
  delete from public.notification_outbox where recipient_id = v_user_id;

  -- 8. 묘비화.
  update public.profiles
  set display_name = '탈퇴한 사용자', deleted_at = now()
  where id = v_user_id;

  -- 9. 실제 계정 삭제. 0행이면 "데이터만 지워지고 계정은 살아있는" 상태를 막기 위해 전체를 되돌린다.
  delete from auth.users where id = v_user_id;

  if not found then
    raise exception '계정을 삭제하지 못했습니다.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- claim_notifications: judge_turn 폐기 조건 추가
-- ---------------------------------------------------------------------------
-- deadline_soon과 같은 이유다. 창이 열린 직후 양쪽이 바로 판정해 버리면 1분 뒤 tick이 집어 들 때
-- 대결은 이미 끝나 있다. 그때 "판정할 차례예요"를 보내면 할 수 없는 일을 하라고 말하는 셈이다.
-- 기준: 20260920120000_push_tokens_and_outbox.sql. 바뀐 것은 (2)번 블록의 or 분기 하나뿐이다.
create or replace function public.claim_notifications(p_limit integer default 50)
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_rows jsonb;
begin
  -- (1) 임대가 만료된 발송은 실패로 내린다. 재시도하지 않는다 - spec은 누락을 허용하고 중복을 금지한다.
  update public.notification_outbox
  set status = 'failed',
      lease_until = null,
      last_error = coalesce(last_error, '발송 임대가 만료되었습니다.')
  where status = 'sending'
    and lease_until is not null
    and lease_until <= now();

  -- (2) 보낼 이유가 사라진 행을 폐기한다.
  update public.notification_outbox o
  set status = 'dropped',
      lease_until = null
  where o.status = 'pending'
    and (
      -- 받을 기기가 하나도 없다(알림 거부·로그아웃·기기 정리).
      not exists (
        select 1 from public.device_push_tokens t where t.user_id = o.recipient_id
      )
      -- 마감 임박 알림은 마감이 지났거나 대결이 더는 진행 중이 아니면 보내지 않는다
      -- (spec: 마감이 지난 뒤에 "마감이 다가온다"는 알림이 오지 않는다).
      or (
        o.kind = 'deadline_soon'
        and not exists (
          select 1 from public.battles b
          where b.id = o.battle_id
            and b.status = 'active'
            and b.deadline_at > now()
        )
      )
      -- 판정 차례 알림은 판정 창이 닫혔으면(종결·무효·취소되었거나 기한이 지났으면) 보내지 않는다.
      or (
        o.kind = 'judge_turn'
        and not exists (
          select 1 from public.battles b
          where b.id = o.battle_id
            and b.status = 'judging'
            and (b.judge_deadline_at is null or b.judge_deadline_at > now())
        )
      )
    );

  -- (3) 남은 pending을 임대한다. skip locked라 발송기가 겹쳐 돌아도 한 행을 한 번만 집는다.
  with picked as (
    select o.id
    from public.notification_outbox o
    where o.status = 'pending'
    order by o.created_at, o.id
    limit greatest(coalesce(p_limit, 50), 1)
    for update skip locked
  ),
  leased as (
    update public.notification_outbox o
    set status = 'sending',
        attempts = o.attempts + 1,
        lease_until = now() + interval '2 minutes'
    where o.id in (select id from picked)
    returning o.id, o.kind, o.battle_id, o.payload, o.recipient_id
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', l.id,
        'kind', l.kind,
        'battle_id', l.battle_id,
        'payload', l.payload,
        'tokens', coalesce(
          (select jsonb_agg(t.token order by t.created_at, t.token)
           from public.device_push_tokens t
           where t.user_id = l.recipient_id),
          '[]'::jsonb)
      )
      order by l.id
    ),
    '[]'::jsonb)
  into v_rows
  from leased l;

  return v_rows;
end;
$$;

comment on function public.claim_notifications is
  '보낼 알림을 임대해 반환한다(서버 전용). 임대 만료분은 failed로, 받을 기기가 없거나 보낼 이유가 '
  '사라진 행(마감 지난 임박 알림, 창이 닫힌 판정 차례 알림)은 dropped로 정리한다.';
