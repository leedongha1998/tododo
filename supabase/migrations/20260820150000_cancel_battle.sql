-- 대결 초대 취소/거절: pending 상태에서만, 참가자(창시자 또는 상대) 누구든 취소할 수 있다.
-- 보낸 사람 입장에서는 "취소", 받은 사람 입장에서는 "거절"이지만 상태 전이는 동일하다.
alter table public.battles
  drop constraint battles_status_check,
  add constraint battles_status_check
    check (status in ('pending', 'active', 'judging', 'finished', 'disputed', 'cancelled'));

create function public.cancel_battle(p_battle_id uuid)
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

  if auth.uid() not in (v_battle.creator_id, v_battle.opponent_id) then
    raise exception '이 초대의 당사자가 아닙니다.';
  end if;

  if v_battle.status <> 'pending' then
    raise exception '대기 중인 초대만 취소할 수 있습니다.';
  end if;

  update public.battles
  set status = 'cancelled', finished_at = now()
  where id = p_battle_id;
end;
$$;

grant execute on function public.cancel_battle(uuid) to authenticated;
