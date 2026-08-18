-- 대결 참가자 행 자동 생성 (client는 battle_participants에 직접 insert 못 함)
create function public.create_battle_participants()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.battle_participants (battle_id, user_id)
  values (new.id, new.creator_id), (new.id, new.opponent_id);
  return new;
end;
$$;

create trigger battles_create_participants
  after insert on public.battles
  for each row execute function public.create_battle_participants();

-- 초대 수락: opponent만 pending -> active로 전환할 수 있다.
create function public.accept_battle(p_battle_id uuid)
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

  if auth.uid() <> v_battle.opponent_id then
    raise exception '상대방만 초대를 수락할 수 있습니다.';
  end if;

  if v_battle.status <> 'pending' then
    raise exception '이미 진행 중이거나 종료된 대결입니다.';
  end if;

  update public.battles
  set status = 'active', started_at = now()
  where id = p_battle_id;
end;
$$;

-- 속도전: 서버 타임스탬프 기준으로 먼저 완료한 사람이 승리한다.
create function public.complete_speed_task(p_battle_id uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_battle public.battles%rowtype;
  v_now timestamptz := now();
begin
  select * into v_battle from public.battles where id = p_battle_id for update;

  if v_battle is null then
    raise exception '대결을 찾을 수 없습니다.';
  end if;

  if v_battle.type <> 'speed' then
    raise exception '속도전 대결이 아닙니다.';
  end if;

  if v_battle.status <> 'active' then
    raise exception '진행 중인 대결이 아닙니다.';
  end if;

  if auth.uid() not in (v_battle.creator_id, v_battle.opponent_id) then
    raise exception '이 대결의 참가자가 아닙니다.';
  end if;

  update public.battle_participants
  set completed_at = v_now
  where battle_id = p_battle_id and user_id = auth.uid() and completed_at is null;

  if not found then
    -- 이미 완료 처리된 경우 조용히 무시 (중복 호출 대비)
    return;
  end if;

  if v_battle.winner_id is null then
    update public.battles
    set winner_id = auth.uid(), status = 'finished', finished_at = v_now
    where id = p_battle_id;
  end if;
end;
$$;

-- 품질전: 완료 시 증거 제출. 최초 제출 시 judging 상태로 전환.
create function public.submit_quality_evidence(
  p_battle_id uuid,
  p_evidence_type text,
  p_evidence_content text
)
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

  if v_battle.type <> 'quality' then
    raise exception '품질전 대결이 아닙니다.';
  end if;

  if v_battle.status not in ('active', 'judging') then
    raise exception '증거를 제출할 수 없는 상태입니다.';
  end if;

  if auth.uid() not in (v_battle.creator_id, v_battle.opponent_id) then
    raise exception '이 대결의 참가자가 아닙니다.';
  end if;

  if p_evidence_type not in ('photo', 'text') then
    raise exception '증거 유형이 올바르지 않습니다.';
  end if;

  update public.battle_participants
  set
    evidence_type = p_evidence_type,
    evidence_content = p_evidence_content,
    evidence_submitted_at = now(),
    decision = null,
    decision_at = null
  where battle_id = p_battle_id and user_id = auth.uid();

  if v_battle.status = 'active' then
    update public.battles set status = 'judging' where id = p_battle_id;
  end if;
end;
$$;

-- 품질전: 상대방의 증거를 approve/dispute. approve면 종료, dispute면 미결(disputed)로 남는다.
create function public.decide_quality_evidence(
  p_battle_id uuid,
  p_target_user_id uuid,
  p_decision text
)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_battle public.battles%rowtype;
  v_target public.battle_participants%rowtype;
  v_other_decision text;
begin
  if p_decision not in ('approve', 'dispute') then
    raise exception '판정 값이 올바르지 않습니다.';
  end if;

  select * into v_battle from public.battles where id = p_battle_id for update;

  if v_battle is null then
    raise exception '대결을 찾을 수 없습니다.';
  end if;

  if v_battle.type <> 'quality' then
    raise exception '품질전 대결이 아닙니다.';
  end if;

  if v_battle.status <> 'judging' then
    raise exception '판정할 수 있는 상태가 아닙니다.';
  end if;

  if auth.uid() not in (v_battle.creator_id, v_battle.opponent_id) then
    raise exception '이 대결의 참가자가 아닙니다.';
  end if;

  if auth.uid() = p_target_user_id then
    raise exception '본인의 증거는 직접 판정할 수 없습니다.';
  end if;

  select * into v_target
  from public.battle_participants
  where battle_id = p_battle_id and user_id = p_target_user_id
  for update;

  if v_target is null or v_target.evidence_submitted_at is null then
    raise exception '판정할 증거가 없습니다.';
  end if;

  if v_target.decision is not null then
    raise exception '이미 판정된 증거입니다.';
  end if;

  update public.battle_participants
  set decision = p_decision, decision_at = now()
  where battle_id = p_battle_id and user_id = p_target_user_id;

  if p_decision = 'dispute' then
    update public.battles set status = 'disputed' where id = p_battle_id;
    return;
  end if;

  -- approve: 상대방(나) 증거도 이미 승인됐는지 확인해 둘 다 승인이면 종료.
  select decision into v_other_decision
  from public.battle_participants
  where battle_id = p_battle_id and user_id = auth.uid();

  if v_other_decision = 'approve' then
    update public.battles
    set status = 'finished', finished_at = now()
    where id = p_battle_id;
  end if;
end;
$$;

-- 클라이언트(authenticated role)에서 RPC로 직접 호출할 함수만 실행 권한을 연다.
grant execute on function public.accept_battle(uuid) to authenticated;
grant execute on function public.complete_speed_task(uuid) to authenticated;
grant execute on function public.submit_quality_evidence(uuid, text, text) to authenticated;
grant execute on function public.decide_quality_evidence(uuid, uuid, text) to authenticated;

