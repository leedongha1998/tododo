-- 대결 생성 방식을 "특정 상대 지목 초대"에서 "주제 모집 → 첫 참가자와 매칭"으로 변경.
-- opponent_id는 매칭 전까지 null이며, 매칭되는 순간(join_battle)에만 채워진다.
alter table public.battles alter column opponent_id drop not null;

-- 모집 중(status='pending')인 대결은 참가자가 아니어도 누구나 볼 수 있어야 목록에 뜬다.
-- (기존 "참가자만 볼 수 있음" 정책은 그대로 두고, OR로 추가)
create policy "anyone can view open recruiting battles"
  on public.battles for select
  to authenticated
  using (status = 'pending');

-- 대결 생성 시 참가자 행은 creator 것만 만든다 (opponent는 아직 없음).
create or replace function public.create_battle_participants()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.battle_participants (battle_id, user_id)
  values (new.id, new.creator_id);
  return new;
end;
$$;

-- 특정 상대 지목 수락 방식은 더 이상 쓰지 않는다. join_battle로 대체.
drop function if exists public.accept_battle(uuid);

-- 모집 참가: opponent가 아직 없는 pending 모집에 참가하면 즉시 매칭되어 active로 전환된다.
-- for update 잠금으로 동시에 여러 명이 참가 시도해도 한 명만 매칭되도록 한다.
create function public.join_battle(p_battle_id uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_battle public.battles%rowtype;
begin
  select * into v_battle from public.battles where id = p_battle_id for update;

  if v_battle is null then
    raise exception '대결을 찾을 수 없습니다.';
  end if;

  if v_battle.status <> 'pending' or v_battle.opponent_id is not null then
    raise exception '이미 매칭되었거나 종료된 모집입니다.';
  end if;

  if auth.uid() = v_battle.creator_id then
    raise exception '본인이 등록한 모집에는 참가할 수 없습니다.';
  end if;

  update public.battles
  set opponent_id = auth.uid(), status = 'active', started_at = now()
  where id = p_battle_id;

  insert into public.battle_participants (battle_id, user_id)
  values (p_battle_id, auth.uid());
end;
$$;

-- 모집 취소: pending 상태에서 등록한 본인만 취소할 수 있다 (아직 상대가 없으므로).
create or replace function public.cancel_battle(p_battle_id uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_battle public.battles%rowtype;
begin
  select * into v_battle from public.battles where id = p_battle_id for update;

  if v_battle is null then
    raise exception '대결을 찾을 수 없습니다.';
  end if;

  if auth.uid() <> v_battle.creator_id then
    raise exception '모집을 등록한 본인만 취소할 수 있습니다.';
  end if;

  if v_battle.status <> 'pending' then
    raise exception '대기 중인 모집만 취소할 수 있습니다.';
  end if;

  update public.battles
  set status = 'cancelled', finished_at = now()
  where id = p_battle_id;
end;
$$;

grant execute on function public.join_battle(uuid) to authenticated;
