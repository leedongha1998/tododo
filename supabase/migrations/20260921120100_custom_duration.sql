-- mutual-judge 1단계: 대결 기간을 분 단위 커스텀으로.
--
-- 근거: docs/specs/mutual-judge/spec.md "P0. 커스텀 마감", design.md "커스텀 마감(분 단위)".
--
-- 규칙
--   - 기간은 생성자가 정하고 1분~10080분(7일) 사이다. 상한은 지금의 최대값(7일)과 같고
--     하한만 24시간 → 1분으로 내린다(범위를 넓히는 것이 아니라 아래로만 연다).
--   - "기간"은 사진을 내는 창(제출 창)이다. 마감 뒤의 판정 창은 2단계에서 따로 생긴다.
--   - 마감은 여전히 매칭되는 순간부터 흐른다(모집 중에는 null).
--   - duration_hours와 duration_minutes를 함께 두지 않는다. 진실이 두 곳에 생긴다.
--
-- 이 파일은 판정 구조를 건드리지 않는다. accept_submission·record_speed_verdict·resolve_battle·
-- settle_expired_battles의 본문과 권한, battle_participants·battle_submissions 스키마,
-- Storage 정책은 그대로다 — 적용 후에도 옛 판정(제출 즉시 AI·5회 상한)이 그대로 돌아가야 한다.
-- 배포된 submit-evidence Edge Function이 부르는 함수의 시그니처를 하나도 바꾸지 않는 이유가 이것이다.

-- ---------------------------------------------------------------------------
-- 컬럼 이전
-- ---------------------------------------------------------------------------
-- 1단계의 첫 마이그레이션이 battles를 비웠으므로 아래 update는 실제로 0행을 고친다.
-- 그래도 문장을 남긴다 — 마이그레이션은 행이 있는 환경에서도 같은 결과를 내야 하고,
-- 데이터 정리 없이 이 파일만 적용해도 뜻이 통해야 한다.
alter table public.battles add column duration_minutes integer;

update public.battles set duration_minutes = duration_hours * 60;

alter table public.battles
  alter column duration_minutes set not null,
  alter column duration_minutes set default 1440,
  add constraint battles_duration_minutes_check
    check (duration_minutes between 1 and 10080);

-- 컬럼을 지우면 그 컬럼만 보는 check 제약(battles_duration_hours_check)도 함께 사라진다.
-- 같은 ALTER 안에서 제약과 컬럼을 함께 드롭하면 순서에 기대는 문장이 되므로 따로 쓴다.
alter table public.battles drop column duration_hours;

comment on column public.battles.duration_minutes is
  '대결을 만든 사람이 고른 제출 창의 길이(분, 1~10080). 매칭 시점에 이 값으로 deadline_at을 계산한다. '
  '기본값 1440(1일)은 직접 insert하는 테스트의 편의용이고, create_battle은 항상 값을 넘긴다.';

-- ---------------------------------------------------------------------------
-- create_battle: 드롭하고 다시 만든다
-- ---------------------------------------------------------------------------
-- create or replace로는 못 고친다. 인자 타입이 (uuid, integer)로 그대로이고 이름만 바뀌므로
-- PostgreSQL이 'cannot change name of input parameter'로 거부한다. 드롭이 유일한 길이다.
--
-- PostgREST는 인자 이름으로 RPC를 찾으므로 앱(BattleRepository.createBattle)도 같은 단계에서
-- p_duration_minutes로 바꿨다. 앱이 아직 배포되지 않아 구버전 호환은 필요 없다.
--
-- 드롭하면 GRANT도 함께 사라진다. 아래에서 revoke/grant를 다시 쓴다.
drop function public.create_battle(uuid, integer);

-- 대결 생성. 증서에 적힌 제목·유형·기준을 그대로 복사한다(클라이언트가 보낸 텍스트를 쓰지 않는다).
create function public.create_battle(p_check_id uuid, p_duration_minutes integer)
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

  -- null을 따로 보는 이유: 옛 검사(not in (24,72,168))는 null이면 NULL로 평가돼 통과한 뒤
  -- not null 컬럼 제약에서 깨졌다. 같은 함수가 같은 문구로 막는 쪽이 읽힌다.
  if p_duration_minutes is null or p_duration_minutes < 1 or p_duration_minutes > 10080 then
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
      type, status, title, creator_id, duration_minutes, min_criteria, superiority_criteria
    )
    values (
      v_check.type, 'pending', v_check.title, v_user, p_duration_minutes,
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

comment on function public.create_battle(uuid, integer) is
  '기준 증서로 모집을 올린다. 기간은 분 단위(1~10080)이고 마감은 매칭 시점에 걸린다.';

revoke execute on function public.create_battle(uuid, integer) from public, anon;
grant execute on function public.create_battle(uuid, integer) to authenticated;

-- ---------------------------------------------------------------------------
-- join_battle: 마감 계산만 분 단위로 (시그니처 유지 → GRANT 그대로)
-- ---------------------------------------------------------------------------
-- 20260917120000_join_and_player_cards.sql의 정의를 그대로 옮기고 make_interval 한 줄만 바꿨다.
create or replace function public.join_battle(p_battle_id uuid, p_criteria_version integer)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_battle public.battles%rowtype;
  v_today date := (now() at time zone 'Asia/Seoul')::date;
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
  where id = p_battle_id;

  insert into public.battle_participants (battle_id, user_id)
  values (p_battle_id, auth.uid());
end;
$$;

comment on function public.join_battle(uuid, integer) is
  '모집 참가. 내가 확인한 기준 버전으로만 참가하며, 매칭되는 순간 양쪽의 그날 한도를 소진하고 '
  '제출 창 마감(duration_minutes 분 뒤)이 걸린다.';

-- ---------------------------------------------------------------------------
-- list_open_recruits: 반환 키만 duration_minutes로 (시그니처 유지 → GRANT 그대로)
-- ---------------------------------------------------------------------------
create or replace function public.list_open_recruits()
returns setof jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception '로그인이 필요합니다.';
  end if;

  return query
    select jsonb_build_object(
      'battle', jsonb_build_object(
        'id', b.id,
        'type', b.type,
        'status', b.status,
        'title', b.title,
        'creator_id', b.creator_id,
        'created_at', b.created_at,
        'duration_minutes', b.duration_minutes,
        'criteria_version', b.criteria_version,
        'min_criteria', b.min_criteria,
        'superiority_criteria', b.superiority_criteria
      ),
      'creator', jsonb_build_object(
        'user_id', p.id,
        'display_name', p.display_name,
        'deleted', p.deleted_at is not null,
        'score', s.score,
        'wins', s.wins,
        'losses', s.losses,
        'draws', s.draws
      )
    )
    from public.battles b
    join public.profiles p on p.id = b.creator_id
    left join public.player_stats s on s.user_id = b.creator_id
    where b.status = 'pending'
      and b.opponent_id is null
      and b.creator_id <> v_user
    order by b.created_at;
end;
$$;

comment on function public.list_open_recruits is
  '남이 올린 모집 목록. 대결·기준 두 목록·기준 버전·생성자 전적을 한 번에 돌려준다.';

-- ---------------------------------------------------------------------------
-- 마감 정산 주기: 5분 -> 1분
-- ---------------------------------------------------------------------------
-- 1분 대결의 마감 정산이 대결 길이의 다섯 배 늦게 일어나면 안 된다.
-- 같은 이름으로 cron.schedule을 다시 부르면 기존 작업이 갱신된다(ai-judge 6단계 선례).
-- settle_expired_battles() 본문과 권한은 이 단계에서 건드리지 않는다(2단계 몫).
select cron.schedule(
  'settle-expired-battles',
  '* * * * *',
  $$select public.settle_expired_battles()$$
);
