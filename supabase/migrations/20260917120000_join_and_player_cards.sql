-- ai-judge 4단계: 모집 목록 조회, 기준 버전 확인 참가, 하루 1대결 소진, 상대 전적 카드.
--
-- 근거: docs/specs/ai-judge/design.md "흐름 4", 화면 4·6, API 계약, decisions 31·44·45·46·49·63·64.
--
-- 핵심 규칙
--   - 참가자는 자기가 확인한 기준(criteria_version)으로만 참가한다. 그 사이 생성자가 기준을 바꿨으면
--     참가가 성립하지 않고 바뀐 기준을 다시 보여 준다(CRITERIA_CHANGED).
--   - 매칭되는 순간 만든 쪽과 참가한 쪽 모두 그날(KST)의 1대결 한도를 소진한다.
--     생성자가 오늘 한도를 이미 썼으면 참가를 막고 참가자에게 이유를 알린다(목록에서 숨기지는 않는다).
--   - 전적은 친구·대결 상대·모집 생성자에게만 보인다. 임의 사용자 전적 조회 경로를 만들지 않는다.
--
-- 이 마이그레이션은 기존 행을 지우거나 바꾸지 않는다.

-- ---------------------------------------------------------------------------
-- 모집 목록: 대결 + 두 기준 목록 + 버전 + 생성자 카드를 한 번에
-- ---------------------------------------------------------------------------
-- 생성자 전적을 목록 수만큼 따로 부르지 않으려고 한 쿼리로 묶는다.
-- battles의 "모집 중은 누구나 조회" 정책이 있지만, 생성자 점수는 player_stats(본인만 select)에 있어
-- 이 함수가 security definer로 대신 읽어 준다. 공개 범위는 아래 where로 좁힌다(모집 중 대결의 생성자).
create function public.list_open_recruits()
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
        'duration_hours', b.duration_hours,
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
-- 참가: 기준 버전 확인 + 양쪽 하루 한도 소진
-- ---------------------------------------------------------------------------
-- 기존 join_battle(uuid)는 버전 확인과 한도 소진이 없어 그대로 두면 우회 경로가 된다. 지운다.
drop function if exists public.join_battle(uuid);

create function public.join_battle(p_battle_id uuid, p_criteria_version integer)
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
      deadline_at = now() + make_interval(hours => v_battle.duration_hours)
  where id = p_battle_id;

  insert into public.battle_participants (battle_id, user_id)
  values (p_battle_id, auth.uid());
end;
$$;

comment on function public.join_battle(uuid, integer) is
  '모집 참가. 내가 확인한 기준 버전으로만 참가하며, 매칭되는 순간 양쪽의 그날 한도를 소진한다.';

-- ---------------------------------------------------------------------------
-- 상대·생성자 전적 카드
-- ---------------------------------------------------------------------------
-- 공개 범위는 "본인 + 나와 같은 대결의 상대 + 모집 중 대결의 생성자"뿐이다(결정 30-1).
-- 무효 대결은 애초에 카운터에 들어가지 않으므로 여기서 따로 숨길 것이 없다(결정 43).
create function public.get_player_card(p_user_id uuid)
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_profile public.profiles%rowtype;
  v_stats public.player_stats%rowtype;
begin
  if v_user is null then
    raise exception '로그인이 필요합니다.';
  end if;

  if p_user_id is null then
    raise exception '사용자가 필요합니다.';
  end if;

  if p_user_id <> v_user
     and not exists (
       select 1 from public.battles b
       where (b.creator_id = v_user and b.opponent_id = p_user_id)
          or (b.opponent_id = v_user and b.creator_id = p_user_id)
     )
     and not exists (
       select 1 from public.battles b
       where b.creator_id = p_user_id and b.status = 'pending'
     ) then
    raise exception '이 사용자의 전적을 볼 수 없습니다.';
  end if;

  select * into v_profile from public.profiles where id = p_user_id;
  if not found then
    raise exception '사용자를 찾을 수 없습니다.';
  end if;

  -- 탈퇴한 사용자는 player_stats 행이 없다. 점수 자리는 null로 나간다.
  select * into v_stats from public.player_stats where user_id = p_user_id;

  return jsonb_build_object(
    'user_id', v_profile.id,
    'display_name', v_profile.display_name,
    'deleted', v_profile.deleted_at is not null,
    'score', v_stats.score,
    'wins', v_stats.wins,
    'losses', v_stats.losses,
    'draws', v_stats.draws
  );
end;
$$;

revoke execute on function public.list_open_recruits() from public, anon;
revoke execute on function public.join_battle(uuid, integer) from public, anon;
revoke execute on function public.get_player_card(uuid) from public, anon;
grant execute on function public.list_open_recruits() to authenticated;
grant execute on function public.join_battle(uuid, integer) to authenticated;
grant execute on function public.get_player_card(uuid) to authenticated;
