-- nickname 2단계(DB-B): 기존 사용자 전원의 이름을 무작위 별명으로 덮는다 (P0-2).
--
-- 근거: docs/specs/nickname/design.md §5·§12 2단계, spec.md 오너 결정 2(2026-11-24).
--
-- ** 되돌릴 수 없다. ** 원래 이름(실명·이메일 포함)은 어디에도 복사하지 않는다(오너 결정 2 - 보관하면
-- 실명을 서버에 하나 더 두는 셈이다). 적용 전에 오너 확인을 두 번 받는다(1차: 아래 사전 확인 결과,
-- 2차: 적용 직전 "되돌릴 수 없다"를 다시 말하고).
--
-- 전제: 1단계(20261124140000_nickname.sql)가 적용돼 있어야 한다 - random_nickname()과 nickname_states를 쓴다.
--
-- 대상: deleted_at is null이고, 봇이 아니고, nickname_states 행이 없는 프로필.
--   - "상태 행이 없음"이 정확히 1단계 이전에 가입한 사람을 가리킨다. 1단계 이후 가입자는 이미 무작위
--     이름이고 상태 행도 있다. 그래서 이 블록을 실수로 두 번 돌려도 두 번째 실행은 0명이다 - 이미 확정한
--     별명을 덮는 일이 구조적으로 없다.
--   - 실명인지 이메일인지 가리지 않는다(서버가 가릴 수 없다, 오너 결정 2).
--   - 탈퇴 묘비("탈퇴한 사용자")와 봇("연습 봇")은 건드리지 않는다.
--
-- 사전 확인(읽기 전용, 이름 값은 출력하지 않는다):
--   select count(*) filter (where deleted_at is null and id <> public.bot_user_id()) as targets,
--          count(*) filter (where deleted_at is not null) as tombstones,
--          count(*) filter (where display_name like '%@%') as emails,
--          count(*) filter (where deleted_at is not null and display_name <> '탈퇴한 사용자') as odd_tombstones
--   from public.profiles;
--   2026-11-24 점검 기준 targets ≈ 44 - 묘비 수, emails = 1, odd_tombstones = 0이 예상값이다.
--   odd_tombstones가 0이 아니면 아래 사후 단언("묘비 이름이 바뀌었습니다")이 이 블록과 무관하게 실패한다 -
--   적용 전에 원인을 먼저 본다.
--
-- 사후 확인: 아래 단언에 더해 select count(*) from public.profiles where display_name like '%@%'; -> 0.
do $$
declare
  r record;
  v_count integer := 0;
begin
  for r in
    select p.id
    from public.profiles p
    where p.deleted_at is null
      and p.id <> public.bot_user_id()
      and not exists (select 1 from public.nickname_states s where s.user_id = p.id)
    order by p.created_at
  loop
    -- 한 사람씩 갱신한다. plpgsql 안의 문장은 앞 문장의 결과를 보므로, random_nickname의 "쓰이지 않은
    -- 조합 먼저"가 이번 일괄 덮기에서 앞 사람에게 준 이름까지 피한다(update 한 문장으로 하면 같은
    -- 스냅숏을 봐서 겹칠 수 있다).
    update public.profiles
    set display_name = public.random_nickname()
    where id = r.id
      -- 루프를 시작한 뒤 이 사람이 탈퇴했으면 묘비 이름을 덮지 않고 건너뛴다(리뷰 제안 2).
      -- 덮으면 아래 사후 단언이 잡아 이 단계 전체가 되돌아가 다시 돌려야 한다.
      and deleted_at is null;
    if not found then
      continue;
    end if;

    insert into public.nickname_states (user_id, reset_at)
    values (r.id, now());

    v_count := v_count + 1;
  end loop;

  raise notice 'nickname reset: % profiles', v_count;

  -- 사후 단언(하나라도 어긋나면 이 마이그레이션 전체가 되돌아간다).
  if exists (select 1 from public.profiles where display_name like '%@%') then
    raise exception '이름에 @가 남은 프로필이 있습니다.';
  end if;

  if exists (
    select 1
    from public.profiles p
    where p.deleted_at is null
      and p.id <> public.bot_user_id()
      and not exists (select 1 from public.nickname_states s where s.user_id = p.id)
  ) then
    raise exception '상태 행이 없는 사용자가 남았습니다.';
  end if;

  if (select display_name from public.profiles where id = public.bot_user_id()) is distinct from '연습 봇' then
    raise exception '봇 이름이 바뀌었습니다.';
  end if;

  if exists (
    select 1
    from public.profiles
    where deleted_at is not null
      and display_name <> '탈퇴한 사용자'
  ) then
    raise exception '묘비 이름이 바뀌었습니다.';
  end if;

  -- 덮은 이름이 전부 규칙을 통과하는지(random_nickname이 보장하지만 되돌릴 수 없는 단계라 한 번 더 본다).
  if exists (
    select 1
    from public.profiles p
    join public.nickname_states s on s.user_id = p.id
    where s.reset_at is not null
      and (public.check_nickname(p.display_name)).code is not null
  ) then
    raise exception '규칙에 맞지 않는 별명으로 덮인 사용자가 있습니다.';
  end if;
end $$;
