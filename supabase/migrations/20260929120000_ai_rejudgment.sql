-- mutual-judge 3단계: 불복·우열 불일치의 AI 재판정.
--
-- 근거: docs/specs/mutual-judge/design.md "AI 재판정 재배선", "ai_judgment_jobs", "새 서버 전용 함수",
-- "AI 호출별 입력/출력", "흐름 5·6·7", "주기 작업".
--
-- 핵심 규칙
--   - AI는 사람 판정으로 결론이 나지 않은 것만 본다. 호출을 만드는 곳은 둘뿐이다:
--     (a) 불복(reject)이 기록될 때 그 제출의 최소 기준 재판정, (b) 품질전 두 사진이 모두 통과로 확정됐는데
--     우열 답이 어긋날 때의 우열 재판정. 잡 생성은 ensure_ai_judgment_job 한 곳에만 있다.
--   - 불복당한 제출에서는 AI의 판정이 사람의 판정을 대체한다(거짓 불복은 이득이 없다). AI 판정은 최종이다.
--   - 실패 처리는 ai-judge에서 검증한 구조를 그대로 옮긴다: 잡마다 최대 4회(최초 1 + 재시도 3),
--     간격 2분 → 5분 → 10분, 임대 3분(만료 = 실패 1회). 어느 잡이든 4회를 다 쓰면 대결은 voided다.
--   - 순서는 잡 생성 시점이 만든다. 우열 잡은 두 최소 기준 결론이 모두 pass가 된 뒤에만 생긴다.
--
-- 이 파일이 끝내는 2단계의 과도기: 2단계에서 judging에 멈춰 있던 불복·불일치 대결은 다음
-- close-judging-windows tick(판정 기한 경과 뒤)이나 다음 판정에서 resolve_battle이 잡을 만들어 이어받는다.
--
-- 적용 뒤 오너 작업: Vault judge_function_url 값을 judge-dispute 주소로 교체 → judge-dispute 배포 →
-- 실호출 확인 → judge-quality 삭제. 값이 바뀌기 전에는 dispatch가 옛 주소(judge-quality)로 job_id를 보내고,
-- 옛 함수는 battle_id가 없다며 400으로 거절한다. 잡은 남아 있다가 값이 바뀌는 순간부터 처리된다
-- (다만 임대가 걸리지 않으므로 시도 수도 줄지 않는다).
--
-- 권한 구조
--   claim_ai_judgment / record_min_criteria_verdict / record_superiority_verdict / record_ai_judgment_failure:
--   Edge Function(service_role) 전용이다. service 롤·cron에는 auth.uid()가 없어 CLAUDE.md의 로그인 가드를
--   두면 항상 실패하므로 두지 않고, authenticated까지 EXECUTE를 회수한 뒤 service_role에만 준다
--   (accept_submission·settle_expired_battles와 같은 예외).
--   dispatch_ai_judgments는 cron 전용이라 service_role에도 주지 않는다.
--   ai_judgment_backoff / fail_ai_judgment / ensure_ai_judgment_job은 내부 전용이라 SECURITY INVOKER로 두고
--   EXECUTE를 모두 회수한다.

-- ---------------------------------------------------------------------------
-- ai_judgment_jobs: AI 재판정 잡 (신규, quality_judgments를 대체)
-- ---------------------------------------------------------------------------
-- 한 대결에 최대 3건(최소 기준 불복 2 + 우열 1)이 따로 생기고, 각자 시도·임대·백오프를 센다.
-- 클라이언트는 이 테이블을 알 필요가 없다 — RLS를 켜고 정책을 하나도 두지 않는다.
create table public.ai_judgment_jobs (
  id bigserial primary key,
  battle_id uuid not null references public.battles (id) on delete cascade,
  kind text not null
    constraint ai_judgment_jobs_kind_check check (kind in ('min_criteria', 'superiority')),
  -- min_criteria: 판정할 사진의 주인. superiority: null.
  target_id uuid references public.profiles (id) on delete cascade,
  attempts smallint not null default 0
    constraint ai_judgment_jobs_attempts_check check (attempts between 0 and 4),
  next_attempt_at timestamptz not null default now(),
  lease_token uuid,
  lease_until timestamptz,
  last_error text,
  created_at timestamptz not null default now(),
  constraint ai_judgment_jobs_target_shape_check check ((kind = 'min_criteria') = (target_id is not null))
);

comment on table public.ai_judgment_jobs is
  'AI 재판정 잡. 불복(min_criteria, 제출마다 1건)과 품질전 우열 불일치(superiority, 대결당 1건)에서만 생긴다. '
  '판정이 끝나거나 대결이 다른 이유로 끝나면 사라진다. 잡마다 최대 4회 시도하고, 어느 잡이든 다 쓰면 대결은 voided다.';
comment on column public.ai_judgment_jobs.attempts is
  '시작된 시도 수(claim이 올린다). 4에 이르러 실패하면 대결이 voided가 된다.';
comment on column public.ai_judgment_jobs.lease_until is
  '임대 만료 시각. 만료 = 실패 1회(Edge 프로세스가 죽거나 실행 시간 제한에 걸린 경우를 흡수한다).';

create unique index ai_judgment_jobs_one_min_criteria_idx
  on public.ai_judgment_jobs (battle_id, target_id) where kind = 'min_criteria';
create unique index ai_judgment_jobs_one_superiority_idx
  on public.ai_judgment_jobs (battle_id) where kind = 'superiority';
create index ai_judgment_jobs_due_idx on public.ai_judgment_jobs (next_attempt_at);

alter table public.ai_judgment_jobs enable row level security;
-- 정책 없음: 서버 전용 함수(security definer)만 이 테이블을 만진다.

-- ---------------------------------------------------------------------------
-- 옛 품질전 판정 잡 제거
-- ---------------------------------------------------------------------------
-- 2단계부터 잡을 만드는 곳도 부르는 곳도 없었다. 이 잡을 지우던 void_battle·forfeit_battle·
-- delete_account는 아래에서 ai_judgment_jobs를 지우도록 다시 정의한다.
drop function public.claim_quality_judgment(uuid);
drop function public.record_quality_verdict(uuid, uuid, boolean, text, boolean, text, uuid, text, text);
drop function public.record_quality_failure(uuid, uuid, text);
drop function public.dispatch_quality_judgments();
drop function public.fail_quality_judgment(uuid, text);
drop function public.quality_judgment_backoff(integer);
drop table public.quality_judgments;

-- ---------------------------------------------------------------------------
-- 재시도 간격 (ai-judge의 quality_judgment_backoff와 같은 값)
-- ---------------------------------------------------------------------------
-- 2분 → 5분 → 10분. 무료 등급의 일시적 실패(분당 한도·과부하)는 몇 분이면 풀리고,
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
-- ensure_ai_judgment_job: 잡 생성의 유일한 지점
-- ---------------------------------------------------------------------------
-- 이미 있으면 아무것도 하지 않는다. 호출자: submit_judgment(불복), resolve_battle(불복 보정·우열 불일치).
create function public.ensure_ai_judgment_job(p_battle_id uuid, p_kind text, p_target_id uuid)
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
  'AI 재판정 잡을 만든다(이미 있으면 그대로). 잡을 만드는 유일한 함수. 내부 전용.';

-- ---------------------------------------------------------------------------
-- fail_ai_judgment: 실패 한 번을 기록하고 다음 시도를 잡거나 무효로 끝낸다
-- ---------------------------------------------------------------------------
-- 호출자: record_ai_judgment_failure(Edge), record_superiority_verdict(AI 응답이 규칙과 어긋난 경우),
--         claim_ai_judgment(사진 없음), dispatch_ai_judgments(임대 만료). 네 경로가 같은 규칙을 쓴다.
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
  select * into v_job from public.ai_judgment_jobs where id = p_job_id for update;

  if not found then
    return 'skipped';
  end if;

  select status into v_status from public.battles where id = v_job.battle_id for update;

  -- 포기·탈퇴로 이미 끝난 대결이면 잡만 정리한다(결과를 다시 건드리지 않는다).
  if v_status is distinct from 'judging' then
    delete from public.ai_judgment_jobs where battle_id = v_job.battle_id;
    return 'skipped';
  end if;

  if v_job.attempts >= 4 then
    -- 무효: 점수·전적에 반영하지 않고, 매칭된 날이 오늘(KST)인 슬롯만 돌려준다.
    -- 같은 대결의 다른 잡도 함께 지운다(void_battle이 지운다).
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
  'AI 재판정 실패 1회 처리. 시도가 남으면 다음 시각을 잡고, 4회를 다 썼으면 void_battle로 무효 종결. 내부 전용.';

-- ---------------------------------------------------------------------------
-- claim_ai_judgment: 재판정 한 번을 임대해 간다 (Edge judge-dispute)
-- ---------------------------------------------------------------------------
-- `for update skip locked` + 임대로 동시 실행을 한 번만 통과시킨다. 임대(3분)가 만료되면 dispatch가
-- 실패 1회로 친다. AI에 보낼 것만 돌려준다 — 사람의 판정 결과, 사용자 이름, 촬영 시각은 없다
-- (AI에게 "상대가 불복했다"를 알리면 판정이 사람의 주장에 끌린다).
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

  -- 잡이 남아 있어도 대결이 이미 끝났으면(포기·탈퇴) 판정하지 않는다.
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
      -- 탈퇴로 경로가 끊겼거나 제출 행이 없는 경우. 시도를 쓴 실패로 처리해 결국 무효로 끝낸다.
      perform public.fail_ai_judgment(p_job_id, '증거 사진 경로가 없습니다.');
      return null;
    end if;

    return jsonb_build_object(
      'token', v_token,
      'attempt', v_job.attempts + 1,
      'kind', v_job.kind,
      'title', v_battle.title,
      'min_criteria', v_battle.min_criteria,
      'target_path', v_target_path
    );
  end if;

  -- 우열: a = 생성자, b = 참가자. 이 순서는 DB 안에서만 쓰고, AI에 보내는 순서는 Edge가 매번 섞는다.
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
    'token', v_token,
    'attempt', v_job.attempts + 1,
    'kind', v_job.kind,
    'title', v_battle.title,
    'superiority_criteria', v_battle.superiority_criteria,
    -- 승자를 사용자 id로 적어 돌려줘야 하므로 두 참가자를 함께 알려 준다.
    'creator_id', v_battle.creator_id,
    'opponent_id', v_battle.opponent_id,
    'a_path', v_a_path,
    'b_path', v_b_path
  );
end;
$$;

comment on function public.claim_ai_judgment is
  'AI 재판정 한 번을 임대한다(서버 전용). 최소 기준은 사진 1장, 우열은 2장(a = 생성자, b = 참가자). 임대에 실패하면 null.';

-- ---------------------------------------------------------------------------
-- record_min_criteria_verdict: 불복당한 제출의 AI 결론을 기록하고 결론을 다시 본다
-- ---------------------------------------------------------------------------
-- AI 결론은 제출 행에 사실로만 들어간다(verdict_source = 'ai'). 승패는 resolve_battle이 낸다.
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
  v_status text;
begin
  select * into v_job from public.ai_judgment_jobs where id = p_job_id for update;

  -- 잡이 없거나 임대가 내 것이 아니면 늦게 도착한 판정이다. 조용히 버린다.
  if not found or v_job.kind <> 'min_criteria'
     or v_job.lease_token is null or v_job.lease_token is distinct from p_token then
    return jsonb_build_object('result', 'skipped');
  end if;

  select status into v_status from public.battles where id = v_job.battle_id for update;

  if v_status is distinct from 'judging' then
    delete from public.ai_judgment_jobs where battle_id = v_job.battle_id;
    return jsonb_build_object('result', 'skipped');
  end if;

  if p_meets is null then
    return jsonb_build_object('result', public.fail_ai_judgment(p_job_id, 'AI 응답에 통과 여부가 없습니다.'));
  end if;

  update public.battle_submissions
  set meets_criteria = p_meets,
      verdict_source = 'ai',
      reason = nullif(btrim(p_reason), ''),
      ai_model = p_model
  where battle_id = v_job.battle_id and user_id = v_job.target_id;

  delete from public.ai_judgment_jobs where id = p_job_id;

  return jsonb_build_object('result', public.resolve_battle(v_job.battle_id));
end;
$$;

comment on function public.record_min_criteria_verdict is
  '불복당한 제출의 AI 최소 기준 결론을 기록하고 resolve_battle로 결론을 다시 본다(서버 전용). AI 결론은 사람의 불복을 대체한다.';

-- ---------------------------------------------------------------------------
-- record_superiority_verdict: 품질전 우열 AI 결론으로 종결한다
-- ---------------------------------------------------------------------------
-- 우열 잡은 두 사진이 모두 통과로 확정되고 우열 답이 어긋났을 때만 생긴다. 판정은 한 사람당 한 번뿐이고
-- 최소 기준 결론도 더 바뀌지 않으므로, AI가 고른 승자로 바로 종결한다. 품질전 패배에는 감면이 없다.
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

  if not found or v_job.kind <> 'superiority'
     or v_job.lease_token is null or v_job.lease_token is distinct from p_token then
    return jsonb_build_object('result', 'skipped');
  end if;

  select * into v_battle from public.battles where id = v_job.battle_id for update;

  if v_battle is null or v_battle.status <> 'judging' then
    delete from public.ai_judgment_jobs where battle_id = v_job.battle_id;
    return jsonb_build_object('result', 'skipped');
  end if;

  -- 승자가 두 참가자 중 하나가 아니면 성공으로 치지 않는다(동점 없음을 서버가 강제한다).
  if p_winner_user_id is null
     or (p_winner_user_id is distinct from v_battle.creator_id
         and p_winner_user_id is distinct from v_battle.opponent_id) then
    return jsonb_build_object('result', public.fail_ai_judgment(p_job_id, 'AI 응답의 승자가 참가자가 아닙니다.'));
  end if;

  -- 사유는 종결과 동시에 양쪽에 공개된다(판정 창 중에 새지 않는다).
  update public.battles
  set verdict_reason = nullif(btrim(p_reason), '')
  where id = v_job.battle_id;

  delete from public.ai_judgment_jobs where id = p_job_id;

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
  '품질전 우열 AI 결론으로 종결한다(서버 전용). 승자가 참가자가 아니면 실패 1회로 돌린다.';

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
  'AI 재판정 실패 1회 기록(서버 전용). 임대 토큰이 맞을 때만 센다.';

-- ---------------------------------------------------------------------------
-- dispatch_ai_judgments: 기한이 된 잡을 Edge Function으로 보낸다 (cron 1분)
-- ---------------------------------------------------------------------------
-- 주소와 비밀값은 Vault에 이름으로만 둔다(judge_function_url, judge_cron_secret). 값이 없으면 아무것도
-- 보내지 않는다 — 임대 만료 처리는 값 없이도 돌아야 하므로 순서를 (a) 만료 정리 → (b) 발송으로 둔다.
-- cron 전용이라 auth.uid() 가드를 두지 않고 EXECUTE를 authenticated까지 전부 회수한다.
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
  -- (a) 임대가 만료된 잡 = 실패 1회. 한 잡의 실패가 같은 tick의 다른 잡을 막지 않게 감싼다.
  for v_row in
    select id from public.ai_judgment_jobs
    where lease_until is not null and lease_until <= now()
    order by id
    for update skip locked
  loop
    begin
      perform public.fail_ai_judgment(v_row.id, '판정 임대가 만료됐습니다.');
    exception
      when others then
        raise warning 'dispatch_ai_judgments: 잡 % 만료 정리 실패: %', v_row.id, sqlerrm;
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
    order by next_attempt_at
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
  '기한이 된 AI 재판정 잡을 Edge Function으로 보내고 만료된 임대를 실패로 정리한다. cron 전용.';

-- ---------------------------------------------------------------------------
-- resolve_battle: 불복·우열 불일치에 잡을 붙인다 (시그니처 uuid -> text 유지)
-- ---------------------------------------------------------------------------
-- 2단계 정의에 두 줄이 더해진다: 최소 기준이 "불복했는데 AI 결과 없음"이면 그 제출의 잡을,
-- 품질전 우열이 어긋나면 우열 잡을 보정한다(이미 있으면 그대로). 잡 생성은 ensure_ai_judgment_job뿐이다.
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
  v_a_judgment public.battle_judgments%rowtype;
  v_b_judgment public.battle_judgments%rowtype;
  v_a_effect text;
  v_b_effect text;
  v_speed record;
  v_quality record;
begin
  select * into v_battle from public.battles where id = p_battle_id for update;

  if v_battle is null then
    raise exception '대결을 찾을 수 없습니다.';
  end if;

  if v_battle.status <> 'judging' or v_battle.opponent_id is null then
    return v_battle.status;
  end if;

  select * into v_a_sub from public.battle_submissions
  where battle_id = p_battle_id and user_id = v_battle.creator_id;

  select * into v_b_sub from public.battle_submissions
  where battle_id = p_battle_id and user_id = v_battle.opponent_id;

  -- a의 판정은 b의 제출에 대한 것이고, b의 판정은 a의 제출에 대한 것이다.
  select * into v_a_judgment from public.battle_judgments
  where battle_id = p_battle_id and judge_id = v_battle.creator_id;

  select * into v_b_judgment from public.battle_judgments
  where battle_id = p_battle_id and judge_id = v_battle.opponent_id;

  -- meets_criteria는 승인에도 채워지므로, AI 결과로 넘기는 것은 AI가 정한 값뿐이다.
  v_a_effect := public.min_verdict_effect(
    v_a_sub.id is not null,
    v_b_judgment.min_verdict,
    case when v_a_sub.verdict_source = 'ai' then v_a_sub.meets_criteria end
  );
  v_b_effect := public.min_verdict_effect(
    v_b_sub.id is not null,
    v_a_judgment.min_verdict,
    case when v_b_sub.verdict_source = 'ai' then v_b_sub.meets_criteria end
  );

  -- 불복했는데 AI 결과가 없는 제출은 AI가 다시 본다. 잡이 이미 있으면 그대로 둔다.
  if v_a_effect = 'pending' and v_b_judgment.min_verdict = 'reject' then
    perform public.ensure_ai_judgment_job(p_battle_id, 'min_criteria', v_battle.creator_id);
  end if;
  if v_b_effect = 'pending' and v_a_judgment.min_verdict = 'reject' then
    perform public.ensure_ai_judgment_job(p_battle_id, 'min_criteria', v_battle.opponent_id);
  end if;

  -- 판정 대기 또는 AI 재판정 대기.
  if v_a_effect = 'pending' or v_b_effect = 'pending' then
    return v_battle.status;
  end if;

  if v_battle.type = 'speed' then
    select * into v_speed
    from public.mutual_speed_outcome(
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

    return v_speed.status;
  end if;

  select * into v_quality
  from public.mutual_quality_outcome(
    v_a_effect,
    v_b_effect,
    case v_a_judgment.superior_id
      when v_battle.creator_id then 'a'
      when v_battle.opponent_id then 'b'
      else null
    end,
    case v_b_judgment.superior_id
      when v_battle.creator_id then 'a'
      when v_battle.opponent_id then 'b'
      else null
    end
  );

  -- 우열 불일치: 아무도 승복하지 않았다. AI가 우열 기준으로 한쪽을 고른다.
  if v_quality.next = 'ai' then
    perform public.ensure_ai_judgment_job(p_battle_id, 'superiority', null);
    return v_battle.status;
  end if;

  if v_quality.next = 'wait' then
    return v_battle.status;
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

  return v_quality.status;
end;
$$;

comment on function public.resolve_battle is
  '판정 창의 판정 사실(승인·불복·우열·AI 결과)로 결론을 내 finalize_battle로 적용하고, 결론이 나지 않은 불복·우열 불일치에는 AI 재판정 잡을 붙인다. judging이 아니면 그대로 반환. 내부 전용.';

-- ---------------------------------------------------------------------------
-- submit_judgment: 불복이면 그 자리에서 잡을 만든다 (시그니처 유지)
-- ---------------------------------------------------------------------------
-- 2단계 정의에 한 줄(불복 → ensure_ai_judgment_job)만 더해진다. resolve_battle도 같은 보정을 하지만
-- 판정의 사실 기록과 잡 생성을 같은 자리에서 보이게 둔다. create or replace라 GRANT는 그대로 남는다.
create or replace function public.submit_judgment(
  p_battle_id uuid,
  p_min_verdict text,
  p_superior_id uuid
)
returns text
language plpgsql
security definer set search_path = public
as $$
declare
  v_me uuid := auth.uid();
  v_battle public.battles%rowtype;
  v_target_id uuid;
  v_target public.battle_submissions%rowtype;
begin
  if auth.uid() is null then
    raise exception '로그인이 필요합니다.';
  end if;

  select * into v_battle from public.battles where id = p_battle_id for update;

  if v_battle is null then
    raise exception '대결을 찾을 수 없습니다.';
  end if;

  -- null에 안전한 형태(`not in`은 비로그인일 때 통과한다).
  if v_me is distinct from v_battle.creator_id
     and v_me is distinct from v_battle.opponent_id then
    raise exception '이 대결의 참가자가 아닙니다.';
  end if;

  if v_battle.status <> 'judging' then
    raise exception using message = '판정할 수 있는 상태가 아닙니다.', hint = 'JUDGING_NOT_OPEN';
  end if;

  if v_battle.judge_deadline_at <= now() then
    raise exception using message = '판정 기한이 지났습니다.', hint = 'JUDGE_WINDOW_CLOSED';
  end if;

  if p_min_verdict is null or p_min_verdict not in ('approve', 'reject') then
    raise exception '판정 값이 올바르지 않습니다.';
  end if;

  v_target_id := case when v_me = v_battle.creator_id then v_battle.opponent_id else v_battle.creator_id end;

  select * into v_target from public.battle_submissions
  where battle_id = p_battle_id and user_id = v_target_id;

  if v_target.id is null then
    raise exception using message = '상대가 제출하지 않아 판정할 것이 없습니다.', hint = 'NOTHING_TO_JUDGE';
  end if;

  perform 1 from public.battle_judgments where battle_id = p_battle_id and judge_id = v_me;
  if found then
    raise exception using message = '이미 판정했습니다.', hint = 'ALREADY_JUDGED';
  end if;

  -- 유형과 참가자가 다른 테이블에 있어 CHECK로 쓸 수 없는 규칙.
  if v_battle.type = 'speed' then
    if p_superior_id is not null then
      raise exception '속도전에는 우열 판정이 없습니다.';
    end if;
  else
    -- 품질전은 최소 기준과 우열을 한 번에 답한다(design 결정 사항 2).
    if p_superior_id is null then
      raise exception using message = '우열 판정이 필요합니다.', hint = 'SUPERIORITY_REQUIRED';
    end if;
    if p_superior_id is distinct from v_battle.creator_id
       and p_superior_id is distinct from v_battle.opponent_id then
      raise exception '우열 판정 대상이 이 대결의 참가자가 아닙니다.';
    end if;
  end if;

  insert into public.battle_judgments (battle_id, judge_id, min_verdict, superior_id, auto)
  values (p_battle_id, v_me, p_min_verdict, p_superior_id, false);

  update public.battle_participants
  set has_judged = true
  where battle_id = p_battle_id and user_id = v_me;

  if p_min_verdict = 'approve' then
    update public.battle_submissions
    set meets_criteria = true,
        verdict_source = 'opponent'
    where id = v_target.id;
  else
    -- 불복: 상대 제출은 AI가 다시 본다. AI 판정이 이 불복을 대체한다.
    perform public.ensure_ai_judgment_job(p_battle_id, 'min_criteria', v_target_id);
  end if;

  return public.resolve_battle(p_battle_id);
end;
$$;

comment on function public.submit_judgment is
  '판정 창에서 상대 증거를 판정한다(한 번뿐). 속도전은 승인/불복, 품질전은 승인/불복 + 우열. 불복이면 AI 재판정 잡을 만든다. 결론은 resolve_battle이 낸다.';

-- ---------------------------------------------------------------------------
-- 대결이 판정 말고 다른 이유로 끝나면 잡도 함께 사라진다
-- ---------------------------------------------------------------------------
-- battles 행은 지우지 않고 상태만 바꾸므로(on delete cascade가 작동하지 않는다) 명시적으로 지운다.
-- 잡이 남으면 cron이 끝난 대결을 계속 부르고, claim이 매번 버리는 헛일이 된다.

-- void_battle: 무효 종결 자체가 잡의 마지막 단계다. 같은 대결의 다른 잡도 함께 지운다.
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
  'AI 재판정 실패 무효 종결. 점수 변화 없음, 매칭일이 오늘(KST)인 슬롯만 반환, 그 대결의 AI 잡 삭제. 내부 전용.';

-- forfeit_battle: 유형·상태(active/judging) 무관 포기한 쪽 패배. 포기하면 판정을 기다릴 이유가 없다.
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

  -- 진행 중이던 AI 재판정은 여기서 끝난다. 늦게 도착한 결과는 claim/record가 종결 상태를 보고 버린다.
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

revoke execute on function public.forfeit_battle(uuid) from public, anon;
grant execute on function public.forfeit_battle(uuid) to authenticated;

-- delete_account: 가장 늦은 정의(20260920120000_push_tokens_and_outbox.sql)를 그대로 옮기고
-- 취소된 대결의 잡을 지우는 줄만 quality_judgments -> ai_judgment_jobs로 바꾼다.
-- 옛 정의를 베끼면 기준 증서·동의 기록·알림 토큰 삭제가 조용히 사라진다.
-- battle_judgments의 내 행은 남긴다 — 상대의 전적을 설명하는 판정 기록이고 사진·식별 정보가 아니다.
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

  -- 1. 끝나지 않은 대결은 승자·점수 변화 없이 취소한다. 이미 인정받은 완료가 있어도 취소다(결정 42).
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

  -- 대기 중이던 AI 재판정 잡. 대결이 취소됐으므로 판정할 것이 없다.
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

revoke execute on function public.delete_account() from public, anon;
grant execute on function public.delete_account() to authenticated;

-- ---------------------------------------------------------------------------
-- 권한
-- ---------------------------------------------------------------------------
revoke execute on function public.ai_judgment_backoff(integer) from public, anon, authenticated;
revoke execute on function public.ensure_ai_judgment_job(uuid, text, uuid) from public, anon, authenticated;
revoke execute on function public.fail_ai_judgment(bigint, text) from public, anon, authenticated;
revoke execute on function public.claim_ai_judgment(bigint) from public, anon, authenticated;
revoke execute on function public.record_min_criteria_verdict(bigint, uuid, boolean, text, text)
  from public, anon, authenticated;
revoke execute on function public.record_superiority_verdict(bigint, uuid, uuid, text, text)
  from public, anon, authenticated;
revoke execute on function public.record_ai_judgment_failure(bigint, uuid, text) from public, anon, authenticated;
revoke execute on function public.dispatch_ai_judgments() from public, anon, authenticated;

grant execute on function public.claim_ai_judgment(bigint) to service_role;
grant execute on function public.record_min_criteria_verdict(bigint, uuid, boolean, text, text) to service_role;
grant execute on function public.record_superiority_verdict(bigint, uuid, uuid, text, text) to service_role;
grant execute on function public.record_ai_judgment_failure(bigint, uuid, text) to service_role;
-- dispatch는 pg_cron(소유자 postgres)이 부른다. service_role에는 주지 않는다.

-- ---------------------------------------------------------------------------
-- cron: ai-judge-tick에 dispatch 추가
-- ---------------------------------------------------------------------------
-- 같은 이름으로 다시 부르면 기존 작업이 갱신된다(중복 등록이 아니다).
select cron.schedule(
  'ai-judge-tick',
  '* * * * *',
  $$select public.sweep_stale_criteria_calls(); select public.dispatch_ai_judgments();$$
);
