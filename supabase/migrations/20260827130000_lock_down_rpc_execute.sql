-- 비로그인(anon) 호출로 대결 상태를 건드릴 수 있던 구멍을 막는다.
--
-- 원인 두 가지가 겹쳐 있었다:
--  1) Postgres는 함수를 만들면 PUBLIC에 EXECUTE를 기본으로 준다. `grant execute ... to authenticated`를
--     써도 anon이 막히지 않아서, anon 키만으로 RPC를 호출할 수 있었다.
--  2) 참가자 검사가 `auth.uid() not in (creator_id, opponent_id)` 형태였는데, 비로그인이면
--     auth.uid()가 null이라 이 식이 TRUE가 아니라 NULL이 되어 예외가 발생하지 않고 통과했다.
--     그 뒤 update는 아무 행도 안 바꾸지만, submit_evidence 끝의 active -> judging 전환이나
--     decide_evidence의 품질전 dispute 처리는 그대로 실행됐다.
--
-- 그래서 (1) PUBLIC의 EXECUTE를 회수하고, (2) 각 함수 앞에 로그인 가드를 두고,
-- (3) 참가자 검사를 null에 안전한 `is distinct from` 형태로 바꾼다.

revoke execute on function public.join_battle(uuid) from public;
revoke execute on function public.cancel_battle(uuid) from public;
revoke execute on function public.submit_evidence(uuid, text, text) from public;
revoke execute on function public.decide_evidence(uuid, uuid, text) from public;

-- 트리거 함수는 트리거가 실행할 때 EXECUTE 권한을 보지 않으므로 아무도 직접 부를 필요가 없다.
revoke execute on function public.handle_new_user() from public;
revoke execute on function public.set_updated_at() from public;
revoke execute on function public.create_battle_participants() from public;

grant execute on function public.join_battle(uuid) to authenticated;
grant execute on function public.cancel_battle(uuid) to authenticated;
grant execute on function public.submit_evidence(uuid, text, text) to authenticated;
grant execute on function public.decide_evidence(uuid, uuid, text) to authenticated;

create or replace function public.join_battle(p_battle_id uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_battle public.battles%rowtype;
begin
  if auth.uid() is null then
    raise exception '로그인이 필요합니다.';
  end if;

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

create or replace function public.cancel_battle(p_battle_id uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_battle public.battles%rowtype;
begin
  if auth.uid() is null then
    raise exception '로그인이 필요합니다.';
  end if;

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

create or replace function public.submit_evidence(
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
  if auth.uid() is null then
    raise exception '로그인이 필요합니다.';
  end if;

  select * into v_battle from public.battles where id = p_battle_id for update;

  if v_battle is null then
    raise exception '대결을 찾을 수 없습니다.';
  end if;

  if v_battle.status not in ('active', 'judging') then
    raise exception '증거를 제출할 수 없는 상태입니다.';
  end if;

  -- null에 안전한 형태. opponent_id가 아직 null인 모집에도 그대로 쓸 수 있다.
  if auth.uid() is distinct from v_battle.creator_id
     and auth.uid() is distinct from v_battle.opponent_id then
    raise exception '이 대결의 참가자가 아닙니다.';
  end if;

  if p_evidence_type not in ('photo', 'text') then
    raise exception '증거 유형이 올바르지 않습니다.';
  end if;

  if p_evidence_content is null or length(trim(p_evidence_content)) = 0 then
    raise exception '증거 내용이 비어 있습니다.';
  end if;

  if v_battle.type = 'quality' and p_evidence_type <> 'photo' then
    raise exception '품질전은 사진 증거가 필수입니다.';
  end if;

  update public.battle_participants
  set
    evidence_type = p_evidence_type,
    evidence_content = p_evidence_content,
    evidence_submitted_at = now(),
    decision = null,
    decision_at = null
  where battle_id = p_battle_id and user_id = auth.uid();

  -- 참가자 행이 없으면 상태를 건드리지 않고 끝낸다(위 검사를 통과했어도 방어적으로 확인).
  if not found then
    raise exception '이 대결의 참가자가 아닙니다.';
  end if;

  if v_battle.status = 'active' then
    update public.battles set status = 'judging' where id = p_battle_id;
  end if;
end;
$$;

create or replace function public.decide_evidence(
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
  v_target public.battle_participants%rowtype;  -- 내가 판정하는 상대의 행
  v_self public.battle_participants%rowtype;    -- 상대가 판정한 내 행
begin
  if auth.uid() is null then
    raise exception '로그인이 필요합니다.';
  end if;

  if p_decision not in ('approve', 'dispute') then
    raise exception '판정 값이 올바르지 않습니다.';
  end if;

  select * into v_battle from public.battles where id = p_battle_id for update;

  if v_battle is null then
    raise exception '대결을 찾을 수 없습니다.';
  end if;

  if v_battle.status <> 'judging' then
    raise exception '판정할 수 있는 상태가 아닙니다.';
  end if;

  if auth.uid() is distinct from v_battle.creator_id
     and auth.uid() is distinct from v_battle.opponent_id then
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

  select * into v_target
  from public.battle_participants
  where battle_id = p_battle_id and user_id = p_target_user_id;

  select * into v_self
  from public.battle_participants
  where battle_id = p_battle_id and user_id = auth.uid();

  if v_battle.type = 'quality' then
    if p_decision = 'dispute' then
      update public.battles
      set status = 'disputed', finished_at = now()
      where id = p_battle_id;
    elsif v_self.decision = 'approve' then
      update public.battles
      set status = 'finished', finished_at = now()
      where id = p_battle_id;
    end if;
    return;
  end if;

  if v_self.decision is null then
    return;  -- 상대가 아직 내 증거를 판정하지 않음 -> judging 유지
  end if;

  if v_self.decision = 'approve' and v_target.decision = 'approve' then
    update public.battles
    set status = 'finished',
        finished_at = now(),
        winner_id = case
          when v_self.evidence_submitted_at <= v_target.evidence_submitted_at then v_self.user_id
          else v_target.user_id
        end
    where id = p_battle_id;
  elsif v_self.decision = 'approve' then
    update public.battles
    set status = 'finished', finished_at = now(), winner_id = v_self.user_id
    where id = p_battle_id;
  elsif v_target.decision = 'approve' then
    update public.battles
    set status = 'finished', finished_at = now(), winner_id = v_target.user_id
    where id = p_battle_id;
  else
    update public.battles
    set status = 'disputed', finished_at = now()
    where id = p_battle_id;
  end if;
end;
$$;

-- create or replace는 기존 권한을 유지하지만, 위 순서가 바뀌어도 안전하도록 한 번 더 못박는다.
revoke execute on function public.join_battle(uuid) from public;
revoke execute on function public.cancel_battle(uuid) from public;
revoke execute on function public.submit_evidence(uuid, text, text) from public;
revoke execute on function public.decide_evidence(uuid, uuid, text) from public;
