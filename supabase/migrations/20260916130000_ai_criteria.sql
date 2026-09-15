-- ai-judge 3단계: AI 판정 기준(생성·검사 원장, 증서, 대결 기준 컬럼).
--
-- 근거: docs/specs/ai-judge/design.md "흐름 2·3", "테이블 변경", "API 계약", decisions 36·46·61·64·67.
--
-- 핵심 규칙
--   - 기준 생성·재검사 AI 호출은 사용자당 하루(KST) 10회. 실패한 호출은 세지 않는다(결정 61).
--   - 모집 중인 대결은 사용자당 1개(결정 64). 오늘 매칭 대결이 있으면 새로 만들 수 없다.
--   - 품질전은 최소 기준 + 우열 기준 두 목록, 속도전은 최소 기준만(결정 67) — DB 제약으로 강제한다.
--   - 대결 생성은 검사를 통과한 증서(criteria_checks)로만 한다. 서버가 증서의 제목·유형·기준을
--     그대로 복사하므로 "검사 뒤 몰래 다른 기준 올리기"가 불가능하다.
--
-- 적용 시점 battles 0행을 확인하고 min_criteria를 not null로 둔다(읽기 전용 조회로 확인함).

-- ---------------------------------------------------------------------------
-- 기준 목록 모양 검사 (문자열 1~5개, 각 항목 공백 제외 1~100자)
-- ---------------------------------------------------------------------------
create function public.is_criteria_list(p_list jsonb)
returns boolean
language sql
immutable
set search_path = public
as $$
  select jsonb_typeof(p_list) = 'array'
     and jsonb_array_length(p_list) between 1 and 5
     and not exists (
       select 1
       from jsonb_array_elements(p_list) e
       where jsonb_typeof(e) <> 'string'
          or length(btrim(e #>> '{}')) = 0
          or length(e #>> '{}') > 100
     );
$$;

comment on function public.is_criteria_list is
  '판정 기준 목록의 모양 검사(문자열 1~5개, 각 1~100자). 체크 제약에서 쓴다.';

revoke execute on function public.is_criteria_list(jsonb) from public, anon;

-- ---------------------------------------------------------------------------
-- battles: 확정된 기준과 버전
-- ---------------------------------------------------------------------------
alter table public.battles
  add column min_criteria jsonb not null,
  add column superiority_criteria jsonb,
  add column criteria_version integer not null default 1;

alter table public.battles
  add constraint battles_min_criteria_shape check (public.is_criteria_list(min_criteria)),
  add constraint battles_superiority_shape
    check (superiority_criteria is null or public.is_criteria_list(superiority_criteria)),
  -- 품질전은 우열 기준 필수, 속도전은 없어야 한다(결정 67).
  add constraint battles_superiority_by_type
    check ((type = 'quality') = (superiority_criteria is not null));

comment on column public.battles.min_criteria is
  '합격/불합격을 가르는 최소 기준(문자열 배열 1~5개). 두 유형 공통.';
comment on column public.battles.superiority_criteria is
  '품질전에서 둘 다 최소 기준을 통과했을 때 승자를 가르는 우열 기준. 속도전은 null.';
comment on column public.battles.criteria_version is
  '두 기준 목록의 공통 버전. 생성자가 모집 중에 기준을 바꾸면 올라가고, 참가자는 자기가 본 버전으로만 참가한다.';

-- 모집 중인 대결은 사용자당 1개. 동시 생성 경합도 이 인덱스가 막는다(결정 64).
create unique index battles_one_pending_per_creator
  on public.battles (creator_id) where status = 'pending';

-- 생성은 create_battle RPC로만 한다. 직접 insert가 열려 있으면 기준 검사를 건너뛸 수 있다.
-- (2단계에서 동의 조건을 붙이며 이름이 바뀐 정책이다.)
drop policy "consented creator can create a pending battle" on public.battles;

-- ---------------------------------------------------------------------------
-- criteria_checks: "검사를 통과한 기준" 증서
-- ---------------------------------------------------------------------------
create table public.criteria_checks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  action text not null constraint criteria_checks_action_check check (action in ('generate', 'check')),
  -- 모집 중 기준 수정이면 대상 대결. 새로 만드는 경우 null.
  battle_id uuid references public.battles (id) on delete cascade,
  title text not null constraint criteria_checks_title_check check (length(btrim(title)) between 1 and 60),
  type text not null constraint criteria_checks_type_check check (type in ('speed', 'quality')),
  min_criteria jsonb not null default '[]'::jsonb,
  superiority_criteria jsonb,
  provable boolean not null,
  block_reason text,
  ai_model text,
  created_at timestamptz not null default now(),
  consumed_at timestamptz,
  -- 통과한 증서만 모양을 강제한다. 차단된 증서는 목록이 비어 있다.
  constraint criteria_checks_min_shape
    check (not provable or public.is_criteria_list(min_criteria)),
  constraint criteria_checks_superiority_shape
    check (superiority_criteria is null or public.is_criteria_list(superiority_criteria)),
  constraint criteria_checks_superiority_by_type
    check (not provable or ((type = 'quality') = (superiority_criteria is not null))),
  constraint criteria_checks_block_reason
    check (provable or (block_reason is not null and length(btrim(block_reason)) > 0))
);

create index criteria_checks_user_idx on public.criteria_checks (user_id, created_at desc);

comment on table public.criteria_checks is
  'AI 검사를 통과(또는 차단)한 기준 증서. create_battle/update_battle_criteria는 이 행의 내용만 복사한다.';
comment on column public.criteria_checks.consumed_at is
  '대결 생성·기준 수정에 쓰인 시각. 한 번 쓴 증서는 다시 못 쓴다.';

alter table public.criteria_checks enable row level security;

create policy "users can view their own criteria checks"
  on public.criteria_checks for select
  to authenticated
  using (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- ai_criteria_calls: 하루 10회 한도 원장
-- ---------------------------------------------------------------------------
create table public.ai_criteria_calls (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  kst_date date not null,
  status text not null
    constraint ai_criteria_calls_status_check check (status in ('in_progress', 'succeeded', 'failed')),
  created_at timestamptz not null default now()
);

create index ai_criteria_calls_user_date_idx on public.ai_criteria_calls (user_id, kst_date);

comment on table public.ai_criteria_calls is
  '기준 생성·재검사 AI 호출 원장. 산입 = succeeded + 2분 이내 in_progress. 실패는 세지 않는다(결정 61).';

alter table public.ai_criteria_calls enable row level security;

create policy "users can view their own criteria calls"
  on public.ai_criteria_calls for select
  to authenticated
  using (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- 한도 계산 (하루 10회)
-- ---------------------------------------------------------------------------
-- 2분 이내 in_progress를 함께 세는 이유: 동시에 여러 요청이 들어와 한도를 넘기는 경합을 막는다.
-- 2분이 지난 in_progress는 Edge가 죽은 것으로 보고 세지 않는다(5단계 sweep이 failed로 정리한다).
create function public.criteria_calls_used(p_user_id uuid, p_kst_date date)
returns integer
language sql
stable
set search_path = public
as $$
  select count(*)::integer
  from public.ai_criteria_calls
  where user_id = p_user_id
    and kst_date = p_kst_date
    and (status = 'succeeded'
         or (status = 'in_progress' and created_at > now() - interval '2 minutes'));
$$;

revoke execute on function public.criteria_calls_used(uuid, date) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- service 전용: Edge Function battle-criteria가 부른다
-- ---------------------------------------------------------------------------
-- 이 세 함수는 service_role만 실행할 수 있다. 사용자 id는 Edge Function이 JWT로 확인한 값을 넘긴다.
-- 그래서 auth.uid() 가드 대신 authenticated까지 EXECUTE를 회수한다(기존 settle_expired_battles 선례).
create function public.begin_criteria_call(
  p_user_id uuid,
  p_action text,
  p_battle_id uuid default null
)
returns uuid
language plpgsql
security definer set search_path = public
as $$
declare
  v_today date := (now() at time zone 'Asia/Seoul')::date;
  v_call_id uuid;
begin
  if p_user_id is null then
    raise exception '사용자가 필요합니다.';
  end if;

  if p_action not in ('generate', 'check') then
    raise exception '올바르지 않은 호출 유형입니다.';
  end if;

  -- 같은 사용자의 동시 요청을 직렬화해 한도를 정확히 센다.
  perform pg_advisory_xact_lock(hashtext(p_user_id::text));

  -- 동의 전에는 제목도 기준도 AI로 나가면 안 된다. 그래서 Gemini 호출 전에 여기서 막는다.
  perform 1 from public.ai_consents where user_id = p_user_id;
  if not found then
    raise exception using message = 'AI 데이터 제공 동의가 필요합니다.', hint = 'CONSENT_REQUIRED';
  end if;

  if p_action = 'generate' then
    perform 1 from public.battles where creator_id = p_user_id and status = 'pending';
    if found then
      raise exception using message = '모집 중인 대결이 이미 있습니다.', hint = 'PENDING_EXISTS';
    end if;

    perform 1 from public.daily_battle_slots where user_id = p_user_id and kst_date = v_today;
    if found then
      raise exception using message = '오늘 한도를 이미 썼습니다.', hint = 'MY_DAILY_LIMIT';
    end if;
  elsif p_battle_id is not null then
    -- 모집 중 기준 수정. 매칭된 뒤에는 누구도 기준을 바꿀 수 없다.
    perform 1 from public.battles
    where id = p_battle_id and creator_id = p_user_id and status = 'pending';
    if not found then
      raise exception using message = '모집 중인 내 대결이 아닙니다.', hint = 'NOT_PENDING';
    end if;
  end if;

  if public.criteria_calls_used(p_user_id, v_today) >= 10 then
    raise exception using message = '오늘 기준 생성 횟수를 다 썼습니다.', hint = 'CRITERIA_CALL_LIMIT';
  end if;

  insert into public.ai_criteria_calls (user_id, kst_date, status)
  values (p_user_id, v_today, 'in_progress')
  returning id into v_call_id;

  return v_call_id;
end;
$$;

-- 성공: 호출을 산입하고 증서를 만든다. 반환값의 calls_left로 앱이 남은 횟수를 보여 준다.
create function public.finish_criteria_call(
  p_call_id uuid,
  p_title text,
  p_type text,
  p_min_criteria jsonb,
  p_superiority_criteria jsonb,
  p_provable boolean,
  p_block_reason text,
  p_battle_id uuid default null,
  p_ai_model text default null
)
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_call public.ai_criteria_calls%rowtype;
  v_check_id uuid;
begin
  update public.ai_criteria_calls
  set status = 'succeeded'
  where id = p_call_id and status = 'in_progress'
  returning * into v_call;

  if not found then
    raise exception '진행 중인 기준 호출이 아닙니다.';
  end if;

  insert into public.criteria_checks (
    user_id, action, battle_id, title, type,
    min_criteria, superiority_criteria, provable, block_reason, ai_model
  )
  values (
    v_call.user_id,
    case when p_battle_id is null then 'generate' else 'check' end,
    p_battle_id,
    btrim(p_title),
    p_type,
    coalesce(p_min_criteria, '[]'::jsonb),
    p_superiority_criteria,
    p_provable,
    p_block_reason,
    p_ai_model
  )
  returning id into v_check_id;

  return jsonb_build_object(
    'check_id', v_check_id,
    'calls_left', greatest(10 - public.criteria_calls_used(v_call.user_id, v_call.kst_date), 0)
  );
end;
$$;

-- 실패: 한도에 세지 않는다(결정 61).
create function public.fail_criteria_call(p_call_id uuid)
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_call public.ai_criteria_calls%rowtype;
begin
  update public.ai_criteria_calls
  set status = 'failed'
  where id = p_call_id and status = 'in_progress'
  returning * into v_call;

  if not found then
    raise exception '진행 중인 기준 호출이 아닙니다.';
  end if;

  return jsonb_build_object(
    'calls_left', greatest(10 - public.criteria_calls_used(v_call.user_id, v_call.kst_date), 0)
  );
end;
$$;

revoke execute on function public.begin_criteria_call(uuid, text, uuid) from public, anon, authenticated;
revoke execute on function public.finish_criteria_call(uuid, text, text, jsonb, jsonb, boolean, text, uuid, text)
  from public, anon, authenticated;
revoke execute on function public.fail_criteria_call(uuid) from public, anon, authenticated;
grant execute on function public.begin_criteria_call(uuid, text, uuid) to service_role;
grant execute on function public.finish_criteria_call(uuid, text, text, jsonb, jsonb, boolean, text, uuid, text)
  to service_role;
grant execute on function public.fail_criteria_call(uuid) to service_role;

-- ---------------------------------------------------------------------------
-- 앱이 부르는 RPC
-- ---------------------------------------------------------------------------
-- 대결 생성. 증서에 적힌 제목·유형·기준을 그대로 복사한다(클라이언트가 보낸 텍스트를 쓰지 않는다).
create function public.create_battle(p_check_id uuid, p_duration_hours integer)
returns uuid
language plpgsql
security definer set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_today date := (now() at time zone 'Asia/Seoul')::date;
  v_check public.criteria_checks%rowtype;
  v_battle_id uuid;
begin
  if v_user is null then
    raise exception '로그인이 필요합니다.';
  end if;

  if p_duration_hours not in (24, 72, 168) then
    raise exception '기간이 올바르지 않습니다.';
  end if;

  perform 1 from public.ai_consents where user_id = v_user;
  if not found then
    raise exception using message = 'AI 데이터 제공 동의가 필요합니다.', hint = 'CONSENT_REQUIRED';
  end if;

  select * into v_check
  from public.criteria_checks
  where id = p_check_id and user_id = v_user
  for update;

  -- 차단됐거나, 이미 썼거나, 오래됐거나, 모집 수정용 증서면 생성에 쓸 수 없다.
  if not found
     or not v_check.provable
     or v_check.consumed_at is not null
     or v_check.created_at <= now() - interval '24 hours'
     or v_check.battle_id is not null then
    raise exception using message = '사용할 수 없는 기준입니다.', hint = 'CHECK_INVALID';
  end if;

  perform 1 from public.battles where creator_id = v_user and status = 'pending';
  if found then
    raise exception using message = '모집 중인 대결이 이미 있습니다.', hint = 'PENDING_EXISTS';
  end if;

  perform 1 from public.daily_battle_slots where user_id = v_user and kst_date = v_today;
  if found then
    raise exception using message = '오늘 한도를 이미 썼습니다.', hint = 'MY_DAILY_LIMIT';
  end if;

  begin
    insert into public.battles (
      type, status, title, creator_id, duration_hours, min_criteria, superiority_criteria
    )
    values (
      v_check.type, 'pending', v_check.title, v_user, p_duration_hours,
      v_check.min_criteria, v_check.superiority_criteria
    )
    returning id into v_battle_id;
  exception when unique_violation then
    -- 부분 유니크 인덱스(모집 1개)에 걸린 경합.
    raise exception using message = '모집 중인 대결이 이미 있습니다.', hint = 'PENDING_EXISTS';
  end;

  update public.criteria_checks set consumed_at = now() where id = p_check_id;

  return v_battle_id;
end;
$$;

-- 모집 중 기준 수정(결정 46). 두 목록은 항상 증서에서 함께 복사되므로 한쪽만 바뀌는 경로가 없다.
create function public.update_battle_criteria(p_battle_id uuid, p_check_id uuid)
returns integer
language plpgsql
security definer set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_battle public.battles%rowtype;
  v_check public.criteria_checks%rowtype;
  v_version integer;
begin
  if v_user is null then
    raise exception '로그인이 필요합니다.';
  end if;

  select * into v_battle from public.battles where id = p_battle_id for update;

  if v_battle is null then
    raise exception '대결을 찾을 수 없습니다.';
  end if;

  if v_battle.creator_id is distinct from v_user then
    raise exception '모집을 등록한 본인만 기준을 바꿀 수 있습니다.';
  end if;

  if v_battle.status <> 'pending' then
    raise exception using message = '이미 매칭되어 기준을 바꿀 수 없습니다.', hint = 'NOT_PENDING';
  end if;

  select * into v_check
  from public.criteria_checks
  where id = p_check_id and user_id = v_user
  for update;

  if not found
     or not v_check.provable
     or v_check.consumed_at is not null
     or v_check.created_at <= now() - interval '24 hours'
     or v_check.battle_id is distinct from p_battle_id
     or v_check.type is distinct from v_battle.type
     or v_check.title is distinct from v_battle.title then
    raise exception using message = '사용할 수 없는 기준입니다.', hint = 'CHECK_INVALID';
  end if;

  update public.battles
  set min_criteria = v_check.min_criteria,
      superiority_criteria = v_check.superiority_criteria,
      criteria_version = criteria_version + 1
  where id = p_battle_id
  returning criteria_version into v_version;

  update public.criteria_checks set consumed_at = now() where id = p_check_id;

  return v_version;
end;
$$;

-- 생성 화면 사전 안내용. 판단은 각 함수가 다시 한다(이 값은 편의일 뿐이다).
create function public.get_my_limits()
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_today date := (now() at time zone 'Asia/Seoul')::date;
begin
  if v_user is null then
    raise exception '로그인이 필요합니다.';
  end if;

  return jsonb_build_object(
    'consented', exists (select 1 from public.ai_consents where user_id = v_user),
    'has_pending', exists (select 1 from public.battles where creator_id = v_user and status = 'pending'),
    'daily_battle_used', exists (
      select 1 from public.daily_battle_slots where user_id = v_user and kst_date = v_today
    ),
    'criteria_calls_left', greatest(10 - public.criteria_calls_used(v_user, v_today), 0)
  );
end;
$$;

revoke execute on function public.create_battle(uuid, integer) from public, anon;
revoke execute on function public.update_battle_criteria(uuid, uuid) from public, anon;
revoke execute on function public.get_my_limits() from public, anon;
grant execute on function public.create_battle(uuid, integer) to authenticated;
grant execute on function public.update_battle_criteria(uuid, uuid) to authenticated;
grant execute on function public.get_my_limits() to authenticated;

-- ---------------------------------------------------------------------------
-- 탈퇴 시 기준 원장도 지운다 (design.md 탈퇴 4)
-- ---------------------------------------------------------------------------
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
