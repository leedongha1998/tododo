-- 매칭된 대결에서 빠져나갈 길이 없었다. 모집 취소(cancel_battle)는 상대가 아직 없을 때만 되고,
-- 매칭된 뒤에는 상대가 증거를 내지 않거나 판정하지 않으면 대결이 active/judging으로 영영 남았다.
-- 포기(기권)를 추가한다.
--
-- 포기한 쪽이 진다. 승자 없이 취소로 처리하면 "질 것 같으면 포기"가 패배를 피하는 수단이 되어
-- 승부의 의미가 없어지기 때문이다. 품질전은 승자를 두지 않는 유형이므로(CLAUDE.md 도메인 규칙)
-- 기권해도 winner_id를 채우지 않고 미결로 끝낸다.

alter table public.battles
  add column forfeited_by uuid references public.profiles (id);

comment on column public.battles.forfeited_by is
  '포기(기권)한 참가자. 승패 자체는 status/winner_id가 말하고, 이 값은 어떻게 끝났는지를 남긴다.';

create function public.forfeit_battle(p_battle_id uuid)
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

  if v_battle.status not in ('active', 'judging') then
    raise exception '포기할 수 있는 상태가 아닙니다.';
  end if;

  -- null에 안전한 형태. 비로그인이면 위에서 이미 막히지만 규칙을 그대로 따른다.
  if auth.uid() is distinct from v_battle.creator_id
     and auth.uid() is distinct from v_battle.opponent_id then
    raise exception '이 대결의 참가자가 아닙니다.';
  end if;

  v_opponent := case
    when auth.uid() = v_battle.creator_id then v_battle.opponent_id
    else v_battle.creator_id
  end;

  -- 상대가 없는 모집은 포기가 아니라 취소다. active/judging이면 상대가 있어야 하지만
  -- 데이터가 어긋난 경우에 승자 없는 finished를 만들지 않도록 막는다.
  if v_opponent is null then
    raise exception '아직 상대가 없는 대결입니다.';
  end if;

  if v_battle.type = 'speed' then
    update public.battles
    set status = 'finished',
        winner_id = v_opponent,
        forfeited_by = auth.uid(),
        finished_at = now()
    where id = p_battle_id;
  else
    update public.battles
    set status = 'disputed',
        forfeited_by = auth.uid(),
        finished_at = now()
    where id = p_battle_id;
  end if;
end;
$$;

-- Postgres는 PUBLIC에, Supabase는 anon에 EXECUTE를 기본으로 준다. 둘 다 회수한 뒤 부여한다.
revoke execute on function public.forfeit_battle(uuid) from public, anon;
grant execute on function public.forfeit_battle(uuid) to authenticated;
