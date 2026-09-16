-- ai-judge 6단계: 품질전 판정 잡, 자동 재시도, 마감 대기.
--
-- 근거: docs/specs/ai-judge/design.md "흐름 6", 품질전 전이표 Q3~Q6, "quality_judgments" 테이블,
-- "RPC — 서버 전용", "품질전 자동 재시도 정책", decisions 14·15·16·19·50·54·59.
--
-- 핵심 규칙
--   - 품질전 제출은 한 번뿐이고, 두 사진이 모두 올라온 순간 대결이 judging으로 넘어가며 판정 잡이 생긴다.
--   - 판정은 최대 4회 시도(최초 1 + 재시도 3), 간격 2분 → 5분 → 10분. 모두 실패하면 대결은 voided다.
--   - 승패는 AI가 아니라 순수 함수 quality_outcome이 정한다. 둘 다 최소 기준을 충족했는데 AI가 승자를
--     고르지 않으면 성공으로 치지 않고 실패(재시도)로 돌린다 — "동점 없음"을 서버가 강제한다.
--   - 판정 중(judging)인 대결은 마감이 지나도 settle이 건너뛴다(1단계 resolve_battle이 이미 그렇게 한다).
--     판정을 끝내는 쪽이 그 자리에서 종결시킨다.
--
-- 권한 구조
--   claim_quality_judgment / record_quality_verdict / record_quality_failure: Edge Function(service_role)
--   전용이다. 그래서 CLAUDE.md의 `auth.uid()` 로그인 가드 대신 authenticated까지 EXECUTE를 회수한다
--   (service 롤·cron에는 uid가 없어 가드를 두면 항상 실패한다 — settle_expired_battles·accept_submission과
--   같은 예외다). dispatch_quality_judgments는 cron 전용이라 service_role에도 주지 않는다.
--   fail_quality_judgment / quality_judgment_backoff는 내부 전용이라 SECURITY INVOKER로 두고 EXECUTE를
--   모두 회수한다(1단계 finalize_battle·void_battle·resolve_battle과 같은 방식).

-- cron이 Edge Function을 부르려면 HTTP가 필요하다. 이미 있으면 그대로 둔다.
create extension if not exists pg_net;

-- ---------------------------------------------------------------------------
-- battles.verdict_reason: 품질전 판정 한 줄 사유
-- ---------------------------------------------------------------------------
-- 품질전은 사유가 생기는 순간 종결되므로(판정 = 종결) 이 컬럼을 따로 가릴 필요가 없다.
-- 속도전 사유는 제출 행(battle_submissions.reason)에 있고 RLS가 종결 전까지 상대에게 가린다.
alter table public.battles add column verdict_reason text;

comment on column public.battles.verdict_reason is
  '품질전 AI 판정의 한 줄 사유. 둘 다 최소 기준을 통과했으면 우열 기준에 근거한 승패 사유, 한쪽만 통과했으면 미달 쪽 사진의 사유. 종결과 동시에 양쪽에 공개된다.';

-- ---------------------------------------------------------------------------
-- quality_judgments: 품질전 판정 잡 (신규)
-- ---------------------------------------------------------------------------
-- 대결 하나에 잡 하나(PK). 잡이 끝나면(성공·무효·포기·취소·탈퇴) 행을 지운다.
-- 클라이언트는 이 테이블을 알 필요가 없다 — RLS를 켜고 정책을 하나도 두지 않아 누구도 읽지 못한다.
create table public.quality_judgments (
  battle_id uuid primary key references public.battles (id) on delete cascade,
  attempts smallint not null default 0
    constraint quality_judgments_attempts_check check (attempts between 0 and 4),
  next_attempt_at timestamptz not null default now(),
  lease_token uuid,
  lease_until timestamptz,
  last_error text,
  created_at timestamptz not null default now()
);

comment on table public.quality_judgments is
  '품질전 AI 판정 잡. 두 사진이 모두 올라오면 생기고, 판정이 끝나거나 대결이 다른 이유로 끝나면 사라진다. 최대 4회 시도.';
comment on column public.quality_judgments.attempts is
  '시작된 시도 수(claim이 올린다). 4에 이르러 실패하면 대결이 voided가 된다.';
comment on column public.quality_judgments.lease_until is
  '임대 만료 시각. 만료 = 실패 1회(Edge 프로세스가 죽거나 실행 시간 제한에 걸린 경우를 흡수한다).';

create index quality_judgments_due_idx on public.quality_judgments (next_attempt_at);

alter table public.quality_judgments enable row level security;
-- 정책 없음: 서버 전용 함수(security definer)만 이 테이블을 만진다.

-- ---------------------------------------------------------------------------
-- 재시도 간격 (design.md "품질전 자동 재시도 정책")
-- ---------------------------------------------------------------------------
-- 2분 → 5분 → 10분. 무료 등급의 일시적 실패(분당 한도·과부하)는 몇 분이면 풀리고,
-- 일일 한도 소진은 몇 시간짜리라 더 늘려도 결과만 늦어진다. 마지막 실패까지 최장 약 17분.
create function public.quality_judgment_backoff(p_attempts integer)
returns interval
language sql
immutable
set search_path = public
as $$
  select case coalesce(p_attempts, 0)
    when 1 then interval '2 minutes'
    when 2 then interval '5 minutes'
    else interval '10 minutes'
  end;
$$;

comment on function public.quality_judgment_backoff is
  '품질전 재시도 간격. 시도 1회 뒤 2분, 2회 뒤 5분, 그 뒤 10분. 내부 전용.';

-- ---------------------------------------------------------------------------
-- fail_quality_judgment: 실패 한 번을 기록하고 다음 시도를 잡거나 무효로 끝낸다
-- ---------------------------------------------------------------------------
-- 호출자: record_quality_failure(Edge), record_quality_verdict(AI 응답이 규칙과 어긋난 경우),
--         dispatch_quality_judgments(임대 만료). 세 경로가 같은 규칙을 쓴다.
create function public.fail_quality_judgment(p_battle_id uuid, p_error text)
returns text
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_job public.quality_judgments%rowtype;
  v_status text;
begin
  select * into v_job from public.quality_judgments
  where battle_id = p_battle_id
  for update;

  if not found then
    return 'skipped';
  end if;

  select status into v_status from public.battles where id = p_battle_id for update;

  -- 포기·탈퇴·취소로 이미 끝난 대결이면 잡만 정리한다(결과를 다시 건드리지 않는다).
  if v_status is distinct from 'judging' then
    delete from public.quality_judgments where battle_id = p_battle_id;
    return 'skipped';
  end if;

  if v_job.attempts >= 4 then
    delete from public.quality_judgments where battle_id = p_battle_id;
    -- 무효: 점수·전적에 반영하지 않고, 매칭된 날이 오늘(KST)인 슬롯만 돌려준다.
    perform public.void_battle(p_battle_id);
    return 'voided';
  end if;

  update public.quality_judgments
  set next_attempt_at = now() + public.quality_judgment_backoff(attempts),
      lease_token = null,
      lease_until = null,
      -- 실패 원인은 운영자가 보는 기록이다. 길게 남기지 않는다.
      last_error = left(coalesce(p_error, ''), 300)
  where battle_id = p_battle_id;

  return 'retry_scheduled';
end;
$$;

comment on function public.fail_quality_judgment is
  '품질전 판정 실패 1회 처리. 시도가 남으면 다음 시각을 잡고, 4회를 다 썼으면 void_battle로 무효 종결. 내부 전용.';

-- ---------------------------------------------------------------------------
-- claim_quality_judgment: 판정 한 번을 임대해 간다 (Edge judge-quality)
-- ---------------------------------------------------------------------------
-- `for update skip locked` + 임대로 동시 실행을 한 번만 통과시킨다. submit-evidence의 즉시 실행과
-- cron의 dispatch가 겹쳐도 한쪽만 claim에 성공한다. 임대(3분)가 만료되면 dispatch가 실패 1회로 친다.
create function public.claim_quality_judgment(p_battle_id uuid)
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_job public.quality_judgments%rowtype;
  v_battle public.battles%rowtype;
  v_token uuid := gen_random_uuid();
  v_a_path text;
  v_b_path text;
begin
  select * into v_job from public.quality_judgments
  where battle_id = p_battle_id
    and next_attempt_at <= now()
    and attempts < 4
    and (lease_until is null or lease_until <= now())
  for update skip locked;

  if not found then
    return null;
  end if;

  select * into v_battle from public.battles where id = p_battle_id for update;

  -- 잡이 남아 있어도 대결이 이미 끝났으면(포기·탈퇴) 판정하지 않는다.
  if v_battle is null or v_battle.status <> 'judging' then
    delete from public.quality_judgments where battle_id = p_battle_id;
    return null;
  end if;

  -- 시도를 먼저 올리고 임대를 건다. 여기서 되돌아가는 경로는 모두 실패 처리를 거치므로
  -- 사진이 없는 잡이 영원히 남지 않는다.
  update public.quality_judgments
  set attempts = attempts + 1,
      lease_token = v_token,
      lease_until = now() + interval '3 minutes'
  where battle_id = p_battle_id;

  -- a = 생성자, b = 참가자. 이 순서는 DB 안에서만 쓰고, AI에 보내는 순서는 Edge가 매번 섞는다.
  select object_path into v_a_path
  from public.battle_submissions
  where battle_id = p_battle_id and user_id = v_battle.creator_id and status = 'submitted';

  select object_path into v_b_path
  from public.battle_submissions
  where battle_id = p_battle_id and user_id = v_battle.opponent_id and status = 'submitted';

  if v_a_path is null or v_b_path is null then
    -- 탈퇴로 경로가 끊겼거나 제출 행이 사라진 경우. 시도를 쓴 실패로 처리해 결국 무효로 끝낸다.
    perform public.fail_quality_judgment(p_battle_id, '증거 사진 경로가 없습니다.');
    return null;
  end if;

  return jsonb_build_object(
    'token', v_token,
    'attempt', v_job.attempts + 1,
    -- 판정 결과를 돌려줄 때 승자를 사용자 id로 적어야 하므로 두 참가자를 함께 알려 준다.
    'creator_id', v_battle.creator_id,
    'opponent_id', v_battle.opponent_id,
    'title', v_battle.title,
    'min_criteria', v_battle.min_criteria,
    'superiority_criteria', v_battle.superiority_criteria,
    'a_path', v_a_path,
    'b_path', v_b_path
  );
end;
$$;

comment on function public.claim_quality_judgment is
  '품질전 판정 한 번을 임대한다(서버 전용). a = 생성자, b = 참가자. 임대에 실패하면 null.';

-- ---------------------------------------------------------------------------
-- record_quality_verdict: AI 판정 사실을 기록하고 규칙대로 종결한다
-- ---------------------------------------------------------------------------
-- p_a_*는 생성자, p_b_*는 참가자 몫이다(Edge가 섞어 보낸 A/B를 참가자로 되돌린 뒤 넘긴다).
-- 승패 계산은 quality_outcome이 하고, 적용은 finalize_battle이 한다. 이 함수는 사실만 옮긴다.
create function public.record_quality_verdict(
  p_battle_id uuid,
  p_token uuid,
  p_a_meets boolean,
  p_a_reason text,
  p_b_meets boolean,
  p_b_reason text,
  p_winner_user_id uuid,
  p_reason text,
  p_model text
)
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_job public.quality_judgments%rowtype;
  v_battle public.battles%rowtype;
  v_winner_slot text;
  v_outcome record;
  v_verdict_reason text;
begin
  select * into v_job from public.quality_judgments where battle_id = p_battle_id for update;

  -- 잡이 없거나 임대가 내 것이 아니면 늦게 도착한 판정이다. 조용히 버린다.
  if not found or v_job.lease_token is null or v_job.lease_token is distinct from p_token then
    return jsonb_build_object('result', 'skipped');
  end if;

  select * into v_battle from public.battles where id = p_battle_id for update;

  if v_battle is null or v_battle.status <> 'judging' then
    delete from public.quality_judgments where battle_id = p_battle_id;
    return jsonb_build_object('result', 'skipped');
  end if;

  v_winner_slot := case
    when p_winner_user_id is null then null
    when p_winner_user_id = v_battle.creator_id then 'a'
    when p_winner_user_id = v_battle.opponent_id then 'b'
    else null
  end;

  select * into v_outcome from public.quality_outcome(p_a_meets, p_b_meets, v_winner_slot);

  -- 둘 다 충족인데 승자가 없거나 참가자가 아니면 성공으로 치지 않는다(동점 없음 규칙).
  if not v_outcome.valid then
    return jsonb_build_object(
      'result',
      public.fail_quality_judgment(p_battle_id, 'AI 응답이 판정 규칙과 맞지 않습니다.')
    );
  end if;

  -- 사진별 1단계 결과와 사유를 제출 행에 남긴다. 종결과 동시에 양쪽에 공개된다.
  update public.battle_submissions
  set meets_criteria = p_a_meets,
      reason = nullif(btrim(p_a_reason), ''),
      ai_model = p_model
  where battle_id = p_battle_id and user_id = v_battle.creator_id and status = 'submitted';

  update public.battle_submissions
  set meets_criteria = p_b_meets,
      reason = nullif(btrim(p_b_reason), ''),
      ai_model = p_model
  where battle_id = p_battle_id and user_id = v_battle.opponent_id and status = 'submitted';

  -- 결과 사유: 둘 다 통과면 우열 기준 근거(winner_reason), 한쪽만 통과면 미달 쪽 사진의 사유.
  -- 둘 다 미달이면 한 줄로 고를 근거가 없어 비워 두고, 화면이 양쪽 제출 사유를 보여 준다.
  v_verdict_reason := case
    when p_a_meets and p_b_meets then nullif(btrim(p_reason), '')
    when not p_a_meets and p_b_meets then nullif(btrim(p_a_reason), '')
    when p_a_meets and not p_b_meets then nullif(btrim(p_b_reason), '')
    else null
  end;

  update public.battles set verdict_reason = v_verdict_reason where id = p_battle_id;

  delete from public.quality_judgments where battle_id = p_battle_id;

  perform public.finalize_battle(
    p_battle_id,
    v_outcome.status,
    case v_outcome.winner
      when 'a' then v_battle.creator_id
      when 'b' then v_battle.opponent_id
      else null
    end,
    v_outcome.a_outcome,
    v_outcome.b_outcome
  );

  return jsonb_build_object('result', v_outcome.status);
end;
$$;

comment on function public.record_quality_verdict is
  '품질전 AI 판정 사실 기록과 종결(서버 전용). 승패는 quality_outcome이 정하고, AI가 규칙과 어긋난 응답을 주면 실패로 돌린다.';

-- ---------------------------------------------------------------------------
-- record_quality_failure: 판정 실패를 알린다 (Edge judge-quality)
-- ---------------------------------------------------------------------------
create function public.record_quality_failure(p_battle_id uuid, p_token uuid, p_error text)
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_job public.quality_judgments%rowtype;
begin
  select * into v_job from public.quality_judgments where battle_id = p_battle_id for update;

  if not found or v_job.lease_token is null or v_job.lease_token is distinct from p_token then
    return jsonb_build_object('result', 'skipped');
  end if;

  return jsonb_build_object('result', public.fail_quality_judgment(p_battle_id, p_error));
end;
$$;

comment on function public.record_quality_failure is
  '품질전 판정 실패 1회 기록(서버 전용). 임대 토큰이 맞을 때만 센다.';

-- ---------------------------------------------------------------------------
-- dispatch_quality_judgments: 기한이 된 잡을 Edge Function으로 보낸다 (cron 1분)
-- ---------------------------------------------------------------------------
-- 주소와 비밀값은 Vault에 이름으로만 둔다(judge_function_url, judge_cron_secret). 값 입력은 계정
-- 소유자가 하고, 마이그레이션·코드·로그 어디에도 값이 남지 않는다. 값이 없으면 아무것도 보내지 않는다 —
-- 임대 만료 처리는 값 없이도 돌아야 하므로 순서를 (a) 만료 정리 → (b) 발송으로 둔다.
create function public.dispatch_quality_judgments()
returns integer
language plpgsql
security definer set search_path = public
as $$
declare
  v_row record;
  v_url text;
  v_secret text;
  v_sent integer := 0;
begin
  -- (a) 임대가 만료된 잡 = 실패 1회. Edge 프로세스가 죽거나 실행 시간 제한에 걸린 경우를 흡수한다.
  for v_row in
    select battle_id from public.quality_judgments
    where lease_until is not null and lease_until <= now()
    order by battle_id
    for update skip locked
  loop
    perform public.fail_quality_judgment(v_row.battle_id, '판정 임대가 만료됐습니다.');
  end loop;

  select decrypted_secret into v_url from vault.decrypted_secrets where name = 'judge_function_url';
  select decrypted_secret into v_secret from vault.decrypted_secrets where name = 'judge_cron_secret';

  if v_url is null or v_secret is null then
    -- 아직 값이 들어오지 않았다. 잡은 남아 있으므로 값이 들어오는 순간부터 이어서 처리된다.
    return 0;
  end if;

  -- (b) 기한이 된 잡마다 한 번씩 부른다. 같은 잡을 여러 번 불러도 claim이 한 번만 통과시킨다.
  for v_row in
    select battle_id from public.quality_judgments
    where next_attempt_at <= now()
      and attempts < 4
      and (lease_until is null or lease_until <= now())
    order by next_attempt_at
  loop
    perform net.http_post(
      url := v_url,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-judge-secret', v_secret
      ),
      body := jsonb_build_object('battle_id', v_row.battle_id),
      timeout_milliseconds := 5000
    );
    v_sent := v_sent + 1;
  end loop;

  return v_sent;
end;
$$;

comment on function public.dispatch_quality_judgments is
  '기한이 된 품질전 판정 잡을 Edge Function으로 보내고 만료된 임대를 실패로 정리한다. cron 전용.';

-- ---------------------------------------------------------------------------
-- accept_submission: 품질전 두 번째 제출에서 judging 전환 + 잡 생성
-- ---------------------------------------------------------------------------
-- 인자 시그니처를 그대로 둔 create or replace다. 시그니처가 달라지면 새 오버로드가 생겨
-- 이미 배포된 submit-evidence가 옛 함수를 계속 부른다.
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
    -- 품질전은 한 번만 낼 수 있다(결정 14). 재제출 수단이 없다.
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

    -- Q3: 두 사진이 모두 올라온 순간 판정 대기로 넘어가고 잡이 생긴다. 같은 트랜잭션이라
    -- 잡만 있고 상태는 active인(또는 그 반대인) 중간 상태가 보이지 않는다.
    if v_both_submitted then
      update public.battles set status = 'judging' where id = p_battle_id;

      insert into public.quality_judgments (battle_id)
      values (p_battle_id)
      on conflict (battle_id) do nothing;
    end if;
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
  '증거 사진 제출 수락(서버 전용). 거부는 행을 만들지 않아 어떤 횟수에도 들어가지 않는다. 품질전 두 번째 제출은 대결을 judging으로 넘기고 판정 잡을 만든다.';

-- ---------------------------------------------------------------------------
-- 대결이 판정 말고 다른 이유로 끝나면 잡도 함께 사라진다
-- ---------------------------------------------------------------------------
-- battles 행은 지우지 않고 상태만 바꾸므로(on delete cascade가 작동하지 않는다) 명시적으로 지운다.
-- 잡이 남으면 cron이 끝난 대결을 계속 부르고, claim이 매번 버리는 헛일이 된다.

-- void_battle: 무효 종결 자체가 잡의 마지막 단계다(fail_quality_judgment가 먼저 잡을 지우지만,
-- 다른 경로로 불려도 남지 않게 여기서도 지운다).
create or replace function public.void_battle(p_battle_id uuid)
returns void
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_battle public.battles%rowtype;
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

  delete from public.quality_judgments where battle_id = p_battle_id;

  delete from public.daily_battle_slots
  where battle_id = p_battle_id
    and kst_date = (now() at time zone 'Asia/Seoul')::date;
end;
$$;

comment on function public.void_battle is
  'AI 판정 실패 무효 종결. 점수 변화 없음, 매칭일이 오늘(KST)인 슬롯만 반환, 판정 잡 삭제. 내부 전용.';

-- forfeit_battle: Q7. 포기하면 판정을 기다릴 이유가 없다.
create or replace function public.forfeit_battle(p_battle_id uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_battle public.battles%rowtype;
  v_opponent uuid;
begin
  if auth.uid() is null then
    raise exception '로그인이 필요합니다.';
  end if;

  select * into v_battle from public.battles where id = p_battle_id for update;

  if v_battle is null then
    raise exception '대결을 찾을 수 없습니다.';
  end if;

  -- null에 안전한 형태. opponent_id가 null이어도 그대로 쓸 수 있다.
  if auth.uid() is distinct from v_battle.creator_id
     and auth.uid() is distinct from v_battle.opponent_id then
    raise exception '이 대결의 참가자가 아닙니다.';
  end if;

  if v_battle.status not in ('active', 'judging') then
    raise exception '포기할 수 있는 상태가 아닙니다.';
  end if;

  v_opponent := case
    when auth.uid() = v_battle.creator_id then v_battle.opponent_id
    else v_battle.creator_id
  end;

  -- 상대가 없는 모집은 포기가 아니라 취소다.
  if v_opponent is null then
    raise exception '아직 상대가 없는 대결입니다.';
  end if;

  update public.battles
  set forfeited_by = auth.uid()
  where id = p_battle_id;

  -- 판정 중이던 품질전 잡은 여기서 끝난다. 늦게 도착한 판정은 claim/record가 종결 상태를 보고 버린다.
  delete from public.quality_judgments where battle_id = p_battle_id;

  perform public.finalize_battle(
    p_battle_id,
    'finished',
    v_opponent,
    case when auth.uid() = v_battle.creator_id then 'forfeit' else 'win' end,
    case when auth.uid() = v_battle.creator_id then 'win' else 'forfeit' end
  );
end;
$$;

revoke execute on function public.forfeit_battle(uuid) from public, anon;
grant execute on function public.forfeit_battle(uuid) to authenticated;

-- delete_account: 취소된 대결의 잡도 함께 지운다(design.md 탈퇴 1).
create or replace function public.delete_account()
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_cancelled_ids uuid[];
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

  -- 매칭된 날이 오늘(KST)인 슬롯만 지워 남은 상대의 오늘 한도를 돌려준다(결정 49·63).
  delete from public.daily_battle_slots
  where battle_id = any (v_cancelled_ids)
    and kst_date = (now() at time zone 'Asia/Seoul')::date;

  -- 판정 대기 중이던 품질전 잡. 대결이 취소됐으므로 판정할 것이 없다.
  delete from public.quality_judgments where battle_id = any (v_cancelled_ids);

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

  -- 7. 묘비화.
  update public.profiles
  set display_name = '탈퇴한 사용자', deleted_at = now()
  where id = v_user_id;

  -- 8. 실제 계정 삭제. 0행이면 "데이터만 지워지고 계정은 살아있는" 상태를 막기 위해 전체를 되돌린다.
  delete from auth.users where id = v_user_id;

  if not found then
    raise exception '계정을 삭제하지 못했습니다.';
  end if;
end;
$$;

revoke execute on function public.delete_account() from public, anon;
grant execute on function public.delete_account() to authenticated;

-- ---------------------------------------------------------------------------
-- 권한
-- ---------------------------------------------------------------------------
revoke execute on function public.quality_judgment_backoff(integer) from public, anon, authenticated;
revoke execute on function public.fail_quality_judgment(uuid, text) from public, anon, authenticated;
revoke execute on function public.claim_quality_judgment(uuid) from public, anon, authenticated;
revoke execute on function public.record_quality_verdict(uuid, uuid, boolean, text, boolean, text, uuid, text, text)
  from public, anon, authenticated;
revoke execute on function public.record_quality_failure(uuid, uuid, text) from public, anon, authenticated;
revoke execute on function public.dispatch_quality_judgments() from public, anon, authenticated;

grant execute on function public.claim_quality_judgment(uuid) to service_role;
grant execute on function public.record_quality_verdict(uuid, uuid, boolean, text, boolean, text, uuid, text, text)
  to service_role;
grant execute on function public.record_quality_failure(uuid, uuid, text) to service_role;
-- dispatch는 pg_cron(소유자 postgres)이 부른다. service_role에는 주지 않는다.

-- ---------------------------------------------------------------------------
-- cron: ai-judge-tick에 dispatch 추가
-- ---------------------------------------------------------------------------
-- 5단계에서 같은 이름으로 이미 등록돼 있다. cron.schedule을 같은 이름으로 다시 부르면 기존 작업이
-- 갱신된다(중복 등록이 아니다). sweep이 빠지지 않게 명령 문자열에 둘 다 넣는다.
-- 마감 정산(settle-expired-battles, 5분)은 기존 작업 그대로 둔다.
select cron.schedule(
  'ai-judge-tick',
  '* * * * *',
  $$select public.sweep_stale_submissions(); select public.dispatch_quality_judgments();$$
);
