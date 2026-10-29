-- mutual-judge 3단계: 불복·우열 불일치 AI 재판정 재배선.
--
-- 근거: docs/specs/mutual-judge/spec.md "P0. AI 재판정",
-- docs/specs/mutual-judge/design.md "AI 재판정 재배선"(새 서버 전용 함수 표, AI 호출별 입력/출력),
-- 상태 전이표 T8~T11, "주기 작업(cron) 구성", "구현 단계 분할 3단계".
--
-- 핵심 규칙
--   - AI 호출은 "결론이 나지 않은 건"에만 붙는다. 사람 판정으로 결론이 나면 AI 호출은 0회다.
--     호출을 만드는 유일한 지점은 (a) 불복당한 제출, (b) 품질전 우열 답 불일치다.
--   - 잡 단위가 대결에서 **건**으로 바뀐다. 한 대결에 최대 3건(최소 기준 불복 2 + 우열 1)이 따로
--     생기고 각자 4회 시도·임대·백오프를 따로 센다. 그래서 quality_judgments(대결당 1건, PK가
--     battle_id)를 버리고 ai_judgment_jobs를 새로 만든다.
--   - 재시도 구조(2·5·10분 백오프, 최대 4회, 임대 3분, 끝내 실패하면 voided)는 ai-judge 6단계에서
--     검증된 quality_judgment_backoff·fail_quality_judgment의 내용을 **그대로 옮긴 것**이다.
--     새로 설계하지 않았다.
--   - 점수·outcome 표는 한 줄도 바뀌지 않는다(win +3 / completed_loss -1 / loss -3 / forfeit -3 /
--     draw -1, 하한 0, voided·cancelled 0). 반영은 finalize_battle, 무효는 void_battle 한 곳이다.
--   - AI에게 "상대가 불복했다"를 알리지 않는다. 사용자 id·이름·상대 정보·촬영 시각·점수·사람의
--     판정 결과도 보내지 않는다(claim이 돌려주는 것은 제목·필요한 기준 목록·사진 경로뿐이다.
--     참가자 id는 승자를 사용자 id로 되돌리기 위해 Edge가 쓰는 값이고 AI로는 나가지 않는다).
--   - ensure_ai_judgment_job을 부르는 곳은 resolve_battle **한 곳**이다. submit_judgment는 이미
--     같은 트랜잭션에서 resolve_battle을 부르므로 본문을 고치지 않았다(잡 생성 조건이 두 곳으로
--     갈라지면 "불복은 기록됐는데 잡이 없다"가 조용히 생긴다).
--   - record_speed_verdict·sweep_stale_submissions 드롭과 sweep_stale_criteria_calls 신설은
--     **2단계(20260922120000)가 이미 했다.** 여기서 다시 드롭·생성하지 않는다(없는 함수를
--     드롭하면 이 마이그레이션 전체가 실패한다).
--
-- 권한 구조(design "API 계약 공통 규칙")
--   - Edge judge-dispute가 부르는 claim/record 3종: SECURITY DEFINER + service_role만.
--   - cron이 부르는 dispatch: SECURITY DEFINER + 아무 롤도 못 부름(소유자 postgres로 실행).
--   - 위 함수들에는 `auth.uid() is null` 가드를 두지 않는다 - 서비스 롤·cron에는 auth.uid()가 없어
--     그 가드가 항상 실패한다(settle_expired_battles 선례). 대신 EXECUTE를 authenticated까지
--     회수하고, 사용자 id는 Edge가 JWT로 검증해 인자로 넘기는 구조를 그대로 쓴다.
--   - 내부 전용(ai_judgment_backoff·fail_ai_judgment·ensure_ai_judgment_job): SECURITY INVOKER +
--     EXECUTE 전부 회수.

-- ---------------------------------------------------------------------------
-- battles.verdict_model: 우열 재판정을 한 모델 (신규)
-- ---------------------------------------------------------------------------
-- verdict_reason과 같은 판정의 쌍이다. 우열 재판정의 모델·프롬프트 버전을 제출 행의 ai_model에
-- 적지 않는 이유: 그 컬럼은 "그 제출의 최소 기준 판정을 한 모델"이고, 우열 경로의 두 제출은
-- 보통 사람이 승인한 것(verdict_source='opponent'/'auto')이라 거기에 모델을 적으면 한 행의 두 값이
-- 서로 모순되고 5단계의 판정 내역 공개가 "사람이 승인한 제출"을 AI 판정으로 보여 준다.
-- 반대로 양쪽 불복 뒤 우열로 간 경로에서는 두 행의 ai_model이 이미 차 있어 우열 모델을 남길 자리가
-- 아예 없다. 사유와 모델을 같은 행에 나란히 두면 두 문제가 함께 사라진다(인젝션 방어 원칙 7).
alter table public.battles add column verdict_model text;

comment on column public.battles.verdict_model is
  '우열 AI 재판정을 한 모델과 프롬프트 버전(gemini-2.5-flash/p1 꼴). verdict_reason과 같은 판정의 '
  '쌍이다. 최소 기준 재판정의 모델은 battle_submissions.ai_model에 있다.';

-- ---------------------------------------------------------------------------
-- ai_judgment_jobs: AI 재판정 잡 (신규, quality_judgments 대체)
-- ---------------------------------------------------------------------------
-- 한 대결에 최대 3건: 최소 기준 재판정은 "판정할 사진의 주인"마다 하나(target_id), 우열 재판정은
-- 대결당 하나(target_id is null). 순서는 디스패처가 아니라 **잡 생성 시점**이 만든다 -
-- 최소 기준 잡은 불복이 기록되는 즉시, 우열 잡은 두 최소 기준 결론이 모두 pass가 된 뒤에만 생긴다.
create table public.ai_judgment_jobs (
  id bigserial primary key,
  battle_id uuid not null references public.battles (id) on delete cascade,
  kind text not null
    constraint ai_judgment_jobs_kind_check check (kind in ('min_criteria', 'superiority')),
  target_id uuid references public.profiles (id) on delete cascade,
  attempts smallint not null default 0
    constraint ai_judgment_jobs_attempts_check check (attempts between 0 and 4),
  next_attempt_at timestamptz not null default now(),
  lease_token uuid,
  lease_until timestamptz,
  last_error text,
  created_at timestamptz not null default now(),
  constraint ai_judgment_jobs_target_check
    check ((kind = 'min_criteria') = (target_id is not null))
);

comment on table public.ai_judgment_jobs is
  'AI 재판정 잡. 불복당한 제출(kind=min_criteria, target_id=사진 주인)과 품질전 우열 답 불일치'
  '(kind=superiority, target_id null)에만 생긴다. 끝나거나 대결이 다른 이유로 끝나면 사라진다. '
  '어느 잡이든 4회를 다 쓰면 그 대결은 voided다.';
comment on column public.ai_judgment_jobs.target_id is
  '최소 기준 재판정에서 판정할 사진의 주인. 불복한 사람이 아니라 불복당한 사람이다.';
comment on column public.ai_judgment_jobs.attempts is
  '시작된 시도 수(claim이 올린다). 4에 이르러 실패하면 그 대결의 잡을 전부 지우고 voided가 된다.';
comment on column public.ai_judgment_jobs.lease_until is
  '임대 만료 시각. 만료 = 실패 1회(Edge 프로세스가 죽거나 실행 시간 제한에 걸린 경우를 흡수한다).';

-- 같은 사진을 두 번 판정하지 않고, 우열 재판정도 대결당 한 번뿐이다. ensure_ai_judgment_job의
-- "on conflict do nothing"이 이 두 인덱스에 걸려 멱등해진다.
create unique index ai_judgment_jobs_min_criteria_unique
  on public.ai_judgment_jobs (battle_id, target_id) where kind = 'min_criteria';
create unique index ai_judgment_jobs_superiority_unique
  on public.ai_judgment_jobs (battle_id) where kind = 'superiority';
create index ai_judgment_jobs_due_idx on public.ai_judgment_jobs (next_attempt_at);
create index ai_judgment_jobs_battle_idx on public.ai_judgment_jobs (battle_id);

alter table public.ai_judgment_jobs enable row level security;
-- 정책 없음: 서버 전용 함수만 이 테이블을 만진다(quality_judgments 선례). 클라이언트는 이 테이블을
-- 알 필요가 없다 - 화면은 battles.status와 battle_participants.has_judged로 "AI가 다시 보는 중"을 안다.

-- ---------------------------------------------------------------------------
-- ai_judgment_backoff: 재시도 간격 (quality_judgment_backoff의 내용 그대로)
-- ---------------------------------------------------------------------------
-- 2분 -> 5분 -> 10분. 무료 등급의 일시적 실패(분당 한도·과부하)는 몇 분이면 풀리고,
-- 일일 한도 소진은 몇 시간짜리라 더 늘려도 결과만 늦어진다. 마지막 실패까지 최장 약 17분.
create function public.ai_judgment_backoff(p_attempts integer)
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

comment on function public.ai_judgment_backoff is
  'AI 재판정 재시도 간격. 시도 1회 뒤 2분, 2회 뒤 5분, 그 뒤 10분. 내부 전용.';

-- ---------------------------------------------------------------------------
-- fail_ai_judgment: 실패 한 번을 기록하고 다음 시도를 잡거나 무효로 끝낸다 (내부 전용)
-- ---------------------------------------------------------------------------
-- 호출자: record_ai_judgment_failure(Edge), record_min_criteria_verdict/record_superiority_verdict
--         (AI 응답이 규칙과 어긋난 경우), dispatch_ai_judgments(임대 만료). 네 경로가 같은 규칙을 쓴다.
create function public.fail_ai_judgment(p_job_id bigint, p_error text)
returns text
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_job public.ai_judgment_jobs%rowtype;
  v_status text;
begin
  select * into v_job from public.ai_judgment_jobs
  where id = p_job_id
  for update;

  if not found then
    return 'skipped';
  end if;

  select status into v_status from public.battles where id = v_job.battle_id for update;

  -- 포기·탈퇴·취소로 이미 끝난 대결이면 잡만 정리한다(결과를 다시 건드리지 않는다).
  if v_status is distinct from 'judging' then
    delete from public.ai_judgment_jobs where battle_id = v_job.battle_id;
    return 'skipped';
  end if;

  if v_job.attempts >= 4 then
    -- 이 대결은 더 이상 가를 수 없다. 남은 다른 잡도 함께 지운다(D5).
    delete from public.ai_judgment_jobs where battle_id = v_job.battle_id;
    -- 무효: 점수·전적에 반영하지 않고, 매칭된 날이 오늘(KST)인 슬롯만 돌려준다.
    perform public.void_battle(v_job.battle_id);
    return 'voided';
  end if;

  update public.ai_judgment_jobs
  set next_attempt_at = now() + public.ai_judgment_backoff(attempts),
      lease_token = null,
      lease_until = null,
      -- 실패 원인은 운영자가 보는 기록이다. 길게 남기지 않는다.
      last_error = left(coalesce(p_error, ''), 300)
  where id = p_job_id;

  return 'retry_scheduled';
end;
$$;

comment on function public.fail_ai_judgment is
  'AI 재판정 실패 1회 처리. 시도가 남으면 다음 시각을 잡고, 4회를 다 썼으면 그 대결의 잡을 모두 '
  '지우고 void_battle로 무효 종결. 내부 전용.';

-- ---------------------------------------------------------------------------
-- ensure_ai_judgment_job: 잡을 만드는 유일한 지점 (내부 전용)
-- ---------------------------------------------------------------------------
-- resolve_battle만 부른다. 멱등하므로 같은 결론이 여러 번 계산돼도(판정·자동 승인·AI 기록이
-- 모두 resolve_battle을 거친다) 잡이 중복되지 않는다.
create function public.ensure_ai_judgment_job(
  p_battle_id uuid,
  p_kind text,
  p_target_id uuid
)
returns void
language plpgsql
security invoker
set search_path = public
as $$
begin
  insert into public.ai_judgment_jobs (battle_id, kind, target_id)
  values (p_battle_id, p_kind, p_target_id)
  on conflict do nothing;
end;
$$;

comment on function public.ensure_ai_judgment_job is
  'AI 재판정 잡을 만든다(이미 있으면 아무 일도 하지 않는다). 부르는 곳은 resolve_battle 한 곳이다. 내부 전용.';

-- ---------------------------------------------------------------------------
-- claim_ai_judgment: 재판정 한 번을 임대해 간다 (Edge judge-dispute)
-- ---------------------------------------------------------------------------
-- `for update skip locked` + 임대로 동시 실행을 한 번만 통과시킨다. cron이 같은 잡을 여러 번 불러도
-- 한쪽만 claim에 성공한다. 임대(3분)가 만료되면 dispatch가 실패 1회로 친다.
--
-- 돌려주는 것은 kind에 필요한 최소한이다: 최소 기준 재판정에는 우열 기준을 주지 않고, 우열 재판정에는
-- 최소 기준을 주지 않는다(사람이 이미 통과시킨 사진을 AI가 미달로 보고 승자를 비우는 일을 막는다).
-- 로그인 가드를 두지 않는 이유는 파일 머리말의 권한 구조 참고(service 롤에는 auth.uid()가 없다).
create function public.claim_ai_judgment(p_job_id bigint)
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_job public.ai_judgment_jobs%rowtype;
  v_battle public.battles%rowtype;
  v_token uuid := gen_random_uuid();
  v_target_path text;
  v_a_path text;
  v_b_path text;
begin
  select * into v_job from public.ai_judgment_jobs
  where id = p_job_id
    and next_attempt_at <= now()
    and attempts < 4
    and (lease_until is null or lease_until <= now())
  for update skip locked;

  if not found then
    return null;
  end if;

  select * into v_battle from public.battles where id = v_job.battle_id for update;

  -- 잡이 남아 있어도 대결이 이미 끝났으면(포기·탈퇴·무효) 판정하지 않는다.
  if v_battle is null or v_battle.status <> 'judging' then
    delete from public.ai_judgment_jobs where battle_id = v_job.battle_id;
    return null;
  end if;

  -- 시도를 먼저 올리고 임대를 건다. 여기서 되돌아가는 경로는 모두 실패 처리를 거치므로
  -- 사진이 없는 잡이 영원히 남지 않는다.
  update public.ai_judgment_jobs
  set attempts = attempts + 1,
      lease_token = v_token,
      lease_until = now() + interval '3 minutes'
  where id = p_job_id;

  if v_job.kind = 'min_criteria' then
    select object_path into v_target_path
    from public.battle_submissions
    where battle_id = v_job.battle_id and user_id = v_job.target_id;

    if v_target_path is null then
      -- 탈퇴로 경로가 끊겼거나 제출 행이 사라진 경우. 시도를 쓴 실패로 처리한다.
      perform public.fail_ai_judgment(p_job_id, '증거 사진 경로가 없습니다.');
      return null;
    end if;

    return jsonb_build_object(
      'job_id', v_job.id,
      'kind', v_job.kind,
      'token', v_token,
      'attempt', v_job.attempts + 1,
      'title', v_battle.title,
      'min_criteria', v_battle.min_criteria,
      'target_path', v_target_path
    );
  end if;

  -- 우열 재판정. a = 생성자, b = 참가자. 이 순서는 DB 안에서만 쓰고, AI에 보내는 순서는 Edge가 매번 섞는다.
  select object_path into v_a_path
  from public.battle_submissions
  where battle_id = v_job.battle_id and user_id = v_battle.creator_id;

  select object_path into v_b_path
  from public.battle_submissions
  where battle_id = v_job.battle_id and user_id = v_battle.opponent_id;

  if v_a_path is null or v_b_path is null then
    perform public.fail_ai_judgment(p_job_id, '증거 사진 경로가 없습니다.');
    return null;
  end if;

  return jsonb_build_object(
    'job_id', v_job.id,
    'kind', v_job.kind,
    'token', v_token,
    'attempt', v_job.attempts + 1,
    'title', v_battle.title,
    'superiority_criteria', v_battle.superiority_criteria,
    -- 승자를 사용자 id로 적어 돌려줘야 하므로 두 참가자를 함께 알려 준다(AI로는 보내지 않는다).
    'creator_id', v_battle.creator_id,
    'opponent_id', v_battle.opponent_id,
    'a_path', v_a_path,
    'b_path', v_b_path
  );
end;
$$;

comment on function public.claim_ai_judgment is
  'AI 재판정 한 번을 임대한다(서버 전용). kind에 필요한 값만 돌려준다(최소 기준에는 우열 기준을, '
  '우열에는 최소 기준을 주지 않는다). 임대에 실패하거나 대결이 끝났으면 null. '
  'Edge 전용이라 로그인 가드를 두지 않는다(service 롤에는 auth.uid()가 없다).';

-- ---------------------------------------------------------------------------
-- record_min_criteria_verdict: 최소 기준 재판정 사실을 기록한다 (Edge judge-dispute)
-- ---------------------------------------------------------------------------
-- AI가 "통과"라고 하면 사람의 불복이 뒤집힌다(min_verdict_effect의 reject + ai_meets=true -> pass).
-- 승패 계산은 resolve_battle이 하고 적용은 finalize_battle이 한다. 이 함수는 사실만 옮긴다.
create function public.record_min_criteria_verdict(
  p_job_id bigint,
  p_token uuid,
  p_meets boolean,
  p_reason text,
  p_model text
)
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_job public.ai_judgment_jobs%rowtype;
  v_battle public.battles%rowtype;
  v_updated integer;
begin
  select * into v_job from public.ai_judgment_jobs where id = p_job_id for update;

  -- 잡이 없거나 임대가 내 것이 아니면 늦게 도착한 판정이다. 조용히 버린다.
  if not found or v_job.lease_token is null or v_job.lease_token is distinct from p_token then
    return jsonb_build_object('result', 'skipped');
  end if;

  if v_job.kind <> 'min_criteria' then
    return jsonb_build_object(
      'result', public.fail_ai_judgment(p_job_id, '잡 종류와 판정 종류가 다릅니다.')
    );
  end if;

  select * into v_battle from public.battles where id = v_job.battle_id for update;

  if v_battle is null or v_battle.status <> 'judging' then
    delete from public.ai_judgment_jobs where battle_id = v_job.battle_id;
    return jsonb_build_object('result', 'skipped');
  end if;

  if p_meets is null then
    return jsonb_build_object(
      'result', public.fail_ai_judgment(p_job_id, 'AI 응답에 통과 여부가 없습니다.')
    );
  end if;

  update public.battle_submissions
  set meets_criteria = p_meets,
      reason = nullif(btrim(p_reason), ''),
      verdict_source = 'ai',
      ai_model = p_model
  where battle_id = v_job.battle_id and user_id = v_job.target_id;

  get diagnostics v_updated = row_count;

  if v_updated = 0 then
    -- 판정 대상 제출 행이 사라졌다. 성공으로 치지 않는다.
    return jsonb_build_object(
      'result', public.fail_ai_judgment(p_job_id, '판정 대상 제출을 찾을 수 없습니다.')
    );
  end if;

  delete from public.ai_judgment_jobs where id = p_job_id;

  return jsonb_build_object('result', public.resolve_battle(v_job.battle_id));
end;
$$;

comment on function public.record_min_criteria_verdict is
  '불복당한 제출의 최소 기준 재판정 기록과 결론 재계산(서버 전용). AI가 통과라고 하면 사람의 '
  '불복이 뒤집힌다. 임대 토큰이 맞을 때만 센다. Edge 전용이라 로그인 가드를 두지 않는다.';

-- ---------------------------------------------------------------------------
-- record_superiority_verdict: 우열 재판정 사실을 기록한다 (Edge judge-dispute)
-- ---------------------------------------------------------------------------
-- 동점이 없다는 규칙을 서버가 강제한다: 승자가 두 참가자 중 하나가 아니면 **성공으로 치지 않고**
-- fail_ai_judgment를 부른다(기존 record_quality_verdict의 valid=false 처리와 같은 선).
create function public.record_superiority_verdict(
  p_job_id bigint,
  p_token uuid,
  p_winner_user_id uuid,
  p_reason text,
  p_model text
)
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_job public.ai_judgment_jobs%rowtype;
  v_battle public.battles%rowtype;
begin
  select * into v_job from public.ai_judgment_jobs where id = p_job_id for update;

  if not found or v_job.lease_token is null or v_job.lease_token is distinct from p_token then
    return jsonb_build_object('result', 'skipped');
  end if;

  if v_job.kind <> 'superiority' then
    return jsonb_build_object(
      'result', public.fail_ai_judgment(p_job_id, '잡 종류와 판정 종류가 다릅니다.')
    );
  end if;

  select * into v_battle from public.battles where id = v_job.battle_id for update;

  if v_battle is null or v_battle.status <> 'judging' then
    delete from public.ai_judgment_jobs where battle_id = v_job.battle_id;
    return jsonb_build_object('result', 'skipped');
  end if;

  if p_winner_user_id is null
     or (p_winner_user_id is distinct from v_battle.creator_id
         and p_winner_user_id is distinct from v_battle.opponent_id) then
    return jsonb_build_object(
      'result', public.fail_ai_judgment(p_job_id, 'AI 응답의 승자가 이 대결의 참가자가 아닙니다.')
    );
  end if;

  -- 우열 사유와 그 판정을 한 모델은 한 행에 나란히 적는다(인젝션 방어 원칙 7). 종결과 동시에
  -- 양쪽에 공개된다 - 이 함수가 곧바로 종결시키므로 판정 창 중에 새지 않는다.
  -- battle_submissions.ai_model은 건드리지 않는다(위 verdict_model 컬럼 주석의 이유).
  update public.battles
  set verdict_reason = nullif(btrim(p_reason), ''),
      verdict_model = p_model
  where id = v_job.battle_id;

  delete from public.ai_judgment_jobs where id = p_job_id;

  -- 사람의 우열 답으로는 결론이 나지 않은 건이다. resolve_battle은 사람의 답만 보므로 다시 부르면
  -- 또 ai로 갈라진다 - 그래서 여기서 바로 종결한다. 품질전 패배는 항상 loss(-3)이고 감면이 없다.
  perform public.finalize_battle(
    v_job.battle_id,
    'finished',
    p_winner_user_id,
    case when p_winner_user_id = v_battle.creator_id then 'win' else 'loss' end,
    case when p_winner_user_id = v_battle.opponent_id then 'win' else 'loss' end
  );

  return jsonb_build_object('result', 'finished');
end;
$$;

comment on function public.record_superiority_verdict is
  '품질전 우열 재판정 기록과 종결(서버 전용). 승자가 참가자가 아니면 성공으로 치지 않고 실패 1회로 '
  '돌린다(동점 없음). 사람의 우열 답으로는 결론이 나지 않은 건이라 resolve_battle을 다시 거치지 '
  '않고 바로 finalize_battle로 종결한다. Edge 전용이라 로그인 가드를 두지 않는다.';

-- ---------------------------------------------------------------------------
-- record_ai_judgment_failure: 재판정 실패를 알린다 (Edge judge-dispute)
-- ---------------------------------------------------------------------------
create function public.record_ai_judgment_failure(p_job_id bigint, p_token uuid, p_error text)
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_job public.ai_judgment_jobs%rowtype;
begin
  select * into v_job from public.ai_judgment_jobs where id = p_job_id for update;

  if not found or v_job.lease_token is null or v_job.lease_token is distinct from p_token then
    return jsonb_build_object('result', 'skipped');
  end if;

  return jsonb_build_object('result', public.fail_ai_judgment(p_job_id, p_error));
end;
$$;

comment on function public.record_ai_judgment_failure is
  'AI 재판정 실패 1회 기록(서버 전용). 임대 토큰이 맞을 때만 센다. Edge 전용이라 로그인 가드를 두지 않는다.';

-- ---------------------------------------------------------------------------
-- dispatch_ai_judgments: 기한이 된 잡을 Edge Function으로 보낸다 (cron 1분)
-- ---------------------------------------------------------------------------
-- 주소와 비밀값은 Vault에 이름으로만 둔다(judge_function_url, judge_cron_secret). 값 입력은 계정
-- 소유자가 하고, 마이그레이션·코드·로그 어디에도 값이 남지 않는다. 값이 없으면 아무것도 보내지 않는다 -
-- 임대 만료 처리는 값 없이도 돌아야 하므로 순서를 (a) 만료 정리 -> (b) 발송으로 둔다.
create function public.dispatch_ai_judgments()
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
  --     한 잡의 예외가 같은 tick의 다른 잡을 막지 않게 한 바퀴씩 예외를 흡수한다.
  for v_row in
    select id from public.ai_judgment_jobs
    where lease_until is not null and lease_until <= now()
    order by id
    for update skip locked
  loop
    begin
      perform public.fail_ai_judgment(v_row.id, '판정 임대가 만료됐습니다.');
    exception when others then
      raise warning 'AI 재판정 임대 정리 실패 (job=%): %', v_row.id, sqlerrm;
    end;
  end loop;

  select decrypted_secret into v_url from vault.decrypted_secrets where name = 'judge_function_url';
  select decrypted_secret into v_secret from vault.decrypted_secrets where name = 'judge_cron_secret';

  if v_url is null or v_secret is null then
    -- 아직 값이 들어오지 않았다. 잡은 남아 있으므로 값이 들어오는 순간부터 이어서 처리된다.
    return 0;
  end if;

  -- (b) 기한이 된 잡마다 한 번씩 부른다. 같은 잡을 여러 번 불러도 claim이 한 번만 통과시킨다.
  for v_row in
    select id from public.ai_judgment_jobs
    where next_attempt_at <= now()
      and attempts < 4
      and (lease_until is null or lease_until <= now())
    order by next_attempt_at, id
  loop
    perform net.http_post(
      url := v_url,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-judge-secret', v_secret
      ),
      body := jsonb_build_object('job_id', v_row.id),
      timeout_milliseconds := 5000
    );
    v_sent := v_sent + 1;
  end loop;

  return v_sent;
end;
$$;

comment on function public.dispatch_ai_judgments is
  '기한이 된 AI 재판정 잡을 Edge Function으로 보내고 만료된 임대를 실패로 정리한다. cron 전용이라 '
  '로그인 가드를 두지 않는다(cron에는 auth.uid()가 없다).';

-- ---------------------------------------------------------------------------
-- resolve_battle: 잡 배선 (2단계 본문 + ensure_ai_judgment_job 세 자리)
-- ---------------------------------------------------------------------------
-- 2단계(20260922120000)의 본문을 그대로 옮기고 "3단계가 여기에 끼워 넣는다"고 적어 둔 자리만 채웠다.
-- 시그니처(uuid -> text)는 유지한다.
--
-- 잡을 만드는 조건은 "pending인데 그 pending이 불복 때문인 경우"다. min_verdict_effect는 (a) 상대가
-- 아직 판정하지 않음과 (b) 불복 + AI 결과 없음을 똑같이 pending으로 돌려주므로, 여기서 두 경우를
-- 가른다 - (a)에 잡을 만들면 사람이 판정하기도 전에 AI를 부른다.
create or replace function public.resolve_battle(p_battle_id uuid)
returns text
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_battle public.battles%rowtype;
  v_a_sub public.battle_submissions%rowtype;
  v_b_sub public.battle_submissions%rowtype;
  v_creator_judgment public.battle_judgments%rowtype;
  v_opponent_judgment public.battle_judgments%rowtype;
  v_a_effect text;
  v_b_effect text;
  v_a_pick text;
  v_b_pick text;
  v_speed record;
  v_quality record;
begin
  select * into v_battle from public.battles where id = p_battle_id for update;

  if v_battle is null then
    raise exception '대결을 찾을 수 없습니다.';
  end if;

  -- status='active'로 불렸을 때는 판정이 있을 수 없다(창이 아직 안 열렸다). cron이
  -- judging_gate로 따로 본다. 종결된 대결도 그대로 반환한다(늦게 온 판정이 다시 건드리지 않게).
  if v_battle.status <> 'judging' or v_battle.opponent_id is null then
    return v_battle.status;
  end if;

  select * into v_a_sub from public.battle_submissions
  where battle_id = p_battle_id and user_id = v_battle.creator_id;
  select * into v_b_sub from public.battle_submissions
  where battle_id = p_battle_id and user_id = v_battle.opponent_id;
  -- creator_judgment = creator_id가 낸 판정(= 상대 제출에 대한 판정 + 자기 우열 선택).
  select * into v_creator_judgment from public.battle_judgments
  where battle_id = p_battle_id and judge_id = v_battle.creator_id;
  select * into v_opponent_judgment from public.battle_judgments
  where battle_id = p_battle_id and judge_id = v_battle.opponent_id;

  -- a(creator) 제출의 결론은 상대(opponent)의 판정을 본다. b는 반대.
  v_a_effect := public.min_verdict_effect(
    v_a_sub.id is not null, v_opponent_judgment.min_verdict, v_a_sub.meets_criteria
  );
  v_b_effect := public.min_verdict_effect(
    v_b_sub.id is not null, v_creator_judgment.min_verdict, v_b_sub.meets_criteria
  );

  if v_a_effect = 'pending' or v_b_effect = 'pending' then
    -- 불복당했는데 AI 결과가 없는 제출에만 재판정 잡을 만든다(멱등). 상대가 아직 판정하지 않아
    -- pending인 경우는 사람의 차례이므로 아무것도 하지 않는다.
    if v_a_sub.id is not null
       and v_opponent_judgment.min_verdict = 'reject'
       and v_a_sub.meets_criteria is null then
      perform public.ensure_ai_judgment_job(p_battle_id, 'min_criteria', v_battle.creator_id);
    end if;

    if v_b_sub.id is not null
       and v_creator_judgment.min_verdict = 'reject'
       and v_b_sub.meets_criteria is null then
      perform public.ensure_ai_judgment_job(p_battle_id, 'min_criteria', v_battle.opponent_id);
    end if;

    return 'judging';
  end if;

  if v_battle.type = 'speed' then
    select * into v_speed from public.mutual_speed_outcome(
      v_a_effect, v_a_sub.submitted_at, v_a_sub.id,
      v_b_effect, v_b_sub.submitted_at, v_b_sub.id
    );

    perform public.finalize_battle(
      p_battle_id,
      v_speed.status,
      case v_speed.winner
        when 'a' then v_battle.creator_id
        when 'b' then v_battle.opponent_id
        else null
      end,
      v_speed.a_outcome,
      v_speed.b_outcome
    );

    -- 종결됐으면 남은 잡은 할 일이 없다. claim·fail도 종결 상태를 보고 버리지만, Vault 값이 없어
    -- 발송이 멈춘 동안에는 아무도 그 잡을 집지 않아 고아로 남는다 - 그래서 여기서 지운다.
    delete from public.ai_judgment_jobs where battle_id = p_battle_id;

    return v_speed.status;
  end if;

  -- 품질전 우열 선택. a_pick = creator가 고른 승자, b_pick = opponent가 고른 승자(둘 다 'a'/'b' 슬롯).
  v_a_pick := case
    when v_creator_judgment.superior_id is null then null
    when v_creator_judgment.superior_id = v_battle.creator_id then 'a'
    when v_creator_judgment.superior_id = v_battle.opponent_id then 'b'
    else null
  end;
  v_b_pick := case
    when v_opponent_judgment.superior_id is null then null
    when v_opponent_judgment.superior_id = v_battle.creator_id then 'a'
    when v_opponent_judgment.superior_id = v_battle.opponent_id then 'b'
    else null
  end;

  select * into v_quality
  from public.mutual_quality_outcome(v_a_effect, v_b_effect, v_a_pick, v_b_pick);

  if v_quality.next = 'ai' then
    -- 둘 다 최소 기준을 통과했는데 아무도 승복하지 않았다. 우열 기준으로 AI가 가른다.
    perform public.ensure_ai_judgment_job(p_battle_id, 'superiority', null);
    return 'judging';
  end if;

  perform public.finalize_battle(
    p_battle_id,
    v_quality.status,
    case v_quality.winner
      when 'a' then v_battle.creator_id
      when 'b' then v_battle.opponent_id
      else null
    end,
    v_quality.a_outcome,
    v_quality.b_outcome
  );

  delete from public.ai_judgment_jobs where battle_id = p_battle_id;

  return v_quality.status;
end;
$$;

comment on function public.resolve_battle is
  '상호 판정 결론으로 종결 여부를 계산해 finalize_battle로 적용한다. 불복당한 제출에 AI 결과가 '
  '없으면 최소 기준 재판정 잡을, 품질전 우열 답이 어긋나면 우열 재판정 잡을 만들고 judging을 '
  '반환한다(잡을 만드는 유일한 지점이다). 내부 전용.';

-- ---------------------------------------------------------------------------
-- 대결이 판정 말고 다른 이유로 끝나면 잡도 함께 사라진다 (테이블 이름 교체)
-- ---------------------------------------------------------------------------
-- battles 행은 지우지 않고 상태만 바꾸므로(on delete cascade가 작동하지 않는다) 명시적으로 지운다.

-- void_battle: 무효 종결 자체가 잡의 마지막 단계다(fail_ai_judgment가 먼저 잡을 지우지만,
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

  delete from public.ai_judgment_jobs where battle_id = p_battle_id;

  delete from public.daily_battle_slots
  where battle_id = p_battle_id
    and kst_date = (now() at time zone 'Asia/Seoul')::date;
end;
$$;

comment on function public.void_battle is
  'AI 재판정이 끝내 실패했을 때의 무효 종결. 점수 변화 없음, 매칭일이 오늘(KST)인 슬롯만 반환, '
  '남은 재판정 잡 삭제. 내부 전용.';

-- forfeit_battle: 포기하면 판정을 기다릴 이유가 없다. 시그니처 유지(create or replace)이므로
-- GRANT(authenticated)는 그대로 남는다.
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

  -- 진행 중이던 AI 재판정은 여기서 끝난다. 늦게 도착한 판정은 claim/record가 종결 상태를 보고 버린다.
  delete from public.ai_judgment_jobs where battle_id = p_battle_id;

  perform public.finalize_battle(
    p_battle_id,
    'finished',
    v_opponent,
    case when auth.uid() = v_battle.creator_id then 'forfeit' else 'win' end,
    case when auth.uid() = v_battle.creator_id then 'win' else 'forfeit' end
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- delete_account: 취소된 대결의 AI 재판정 잡도 함께 지운다
-- ---------------------------------------------------------------------------
-- **20260920120000_push_tokens_and_outbox.sql의 정의(가장 늦은 정의)를 기반으로** 고쳤다.
-- 여섯 번 재정의된 함수라 옛 정의를 베끼면 기준 증서·동의 기록·알림 토큰 삭제가 조용히 사라진다.
-- 이번에 바뀐 것은 1번 단계의 잡 삭제 한 줄(quality_judgments -> ai_judgment_jobs)뿐이고,
-- 인자 없는 시그니처와 나머지 단계(2~9)는 그대로다.
-- battle_judgments의 내 판정 행은 남긴다 - 상대의 전적을 설명하는 판정 기록이고 사진·식별 정보가
-- 아니다(제출 행을 남기는 것과 같은 이유).
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
  --    내가 수신자인 행만 지운다 - 상대가 받을 알림은 상대의 기록이라 건드리지 않는다.
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

-- resolve_battle·void_battle·forfeit_battle·delete_account는 드롭 없이 create or replace였으므로
-- 권한이 그대로 남는다(어느 함수가 드롭됐고 어느 함수가 아닌지 파일에서 읽히게 다시 쓰지 않는다 -
-- 1단계의 join_battle·list_open_recruits와 같은 방식).

-- ---------------------------------------------------------------------------
-- cron: ai-judge-tick 명령 교체 (아래 드롭보다 먼저)
-- ---------------------------------------------------------------------------
-- 같은 이름으로 다시 부르면 기존 작업이 갱신된다(중복 등록이 아니다, ai-judge 6단계 선례).
-- settle-expired-battles(1분)·close-judging-windows(1분)는 건드리지 않는다.
--
-- **순서가 중요하다**: 명령 문자열을 먼저 갈아야 드롭된 dispatch_quality_judgments를 가리키는
-- tick이 한 번도 돌 수 없다. 반대 순서는 "db push가 파일 하나를 단일 트랜잭션으로 적용한다"는
-- 전제에 안전성을 의존하게 된다 - 그 전제 없이도 안전하게 두려고 이 블록을 위로 올렸다.
select cron.schedule(
  'ai-judge-tick',
  '* * * * *',
  $$select public.sweep_stale_criteria_calls(); select public.dispatch_ai_judgments();$$
);

-- ---------------------------------------------------------------------------
-- 품질전 판정 잡 폐기 (quality_judgments 일체)
-- ---------------------------------------------------------------------------
-- 2단계 적용 뒤로는 아무도 새 잡을 만들지 않아 비어 있다. 시작 조건·대상·단위가 모두 달라졌으므로
-- 고치지 않고 버린다. 배포된 judge-quality Edge Function은 이 드롭으로 동작을 멈추고, 오너가
-- judge-dispute 실호출을 확인한 뒤 `supabase functions delete judge-quality`로 지운다.
drop function public.dispatch_quality_judgments();
drop function public.record_quality_failure(uuid, uuid, text);
drop function public.record_quality_verdict(
  uuid, uuid, boolean, text, boolean, text, uuid, text, text
);
drop function public.claim_quality_judgment(uuid);
drop function public.fail_quality_judgment(uuid, text);
drop function public.quality_judgment_backoff(integer);
drop table public.quality_judgments;

-- ---------------------------------------------------------------------------
-- 권한
-- ---------------------------------------------------------------------------
-- 내부 전용: 아무 롤도 부를 수 없다(호출자는 resolve_battle·record_*·dispatch다).
revoke execute on function public.ai_judgment_backoff(integer) from public, anon, authenticated;
revoke execute on function public.fail_ai_judgment(bigint, text) from public, anon, authenticated;
revoke execute on function public.ensure_ai_judgment_job(uuid, text, uuid)
  from public, anon, authenticated;

-- Edge Function(service_role) 전용. 로그인 가드 대신 authenticated까지 회수한다(머리말의 예외).
revoke execute on function public.claim_ai_judgment(bigint) from public, anon, authenticated;
revoke execute on function public.record_min_criteria_verdict(bigint, uuid, boolean, text, text)
  from public, anon, authenticated;
revoke execute on function public.record_superiority_verdict(bigint, uuid, uuid, text, text)
  from public, anon, authenticated;
revoke execute on function public.record_ai_judgment_failure(bigint, uuid, text)
  from public, anon, authenticated;

grant execute on function public.claim_ai_judgment(bigint) to service_role;
grant execute on function public.record_min_criteria_verdict(bigint, uuid, boolean, text, text)
  to service_role;
grant execute on function public.record_superiority_verdict(bigint, uuid, uuid, text, text)
  to service_role;
grant execute on function public.record_ai_judgment_failure(bigint, uuid, text) to service_role;

-- dispatch는 pg_cron(소유자 postgres)이 부른다. service_role에는 주지 않는다.
revoke execute on function public.dispatch_ai_judgments() from public, anon, authenticated;
