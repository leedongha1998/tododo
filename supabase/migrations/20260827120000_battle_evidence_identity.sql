-- 대결 정체성 재정의: 속도전도 "증거 제출 -> 상대 승인/이의제기"를 거쳐야 완료·승부가 확정된다.
-- 자기 신고(complete_speed_task)로 승부가 나던 구조를 폐지하고, 품질전 전용이던 증거/판정 RPC를
-- 두 유형 공용으로 일반화한다. 유형별로 다른 것은 "결과 판정 규칙"뿐이다.
-- 근거: docs/specs/battle-identity/spec.md, design.md

-- 완료·승부 확정 시각은 유형에 상관없이 evidence_submitted_at 하나로 통일한다.
-- completed_at은 어긋날 수 있는 중복 소스이므로 제거한다(배포 전이라 호환 부담 없음).
alter table public.battle_participants drop column completed_at;

comment on column public.battle_participants.evidence_submitted_at is
  '증거 제출 시각(서버). 속도전의 승부 기준 시각이기도 하다. 재제출하면 갱신된다.';
comment on column public.battle_participants.evidence_content is
  '텍스트 증거면 본문, 사진 증거면 battle_evidence 버킷의 오브젝트 경로.';
comment on column public.battle_participants.decision is
  '이 행의 참가자가 아니라 상대방이 내린 판정. 이 참가자의 완료가 유효한지를 뜻한다 - approve인 참가자만 유효한 완료를 가진 것으로 취급한다.';

drop function if exists public.complete_speed_task(uuid);
drop function if exists public.submit_quality_evidence(uuid, text, text);
drop function if exists public.decide_quality_evidence(uuid, uuid, text);

-- 증거 제출: 속도전/품질전 공용. 최초 제출 시 judging으로 전환한다.
-- 재제출은 판정 전이든 이의제기당한 뒤든 항상 허용하며, 판정과 제출 시각이 함께 리셋된다
-- (실수 복구는 되게 하되, 제출 시각이 밀리므로 대충 빨리 내고 나중에 제대로 내는 전략이 이득이 되지 않는다).
create function public.submit_evidence(
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

  if v_battle.status not in ('active', 'judging') then
    raise exception '증거를 제출할 수 없는 상태입니다.';
  end if;

  if auth.uid() not in (v_battle.creator_id, v_battle.opponent_id) then
    raise exception '이 대결의 참가자가 아닙니다.';
  end if;

  if p_evidence_type not in ('photo', 'text') then
    raise exception '증거 유형이 올바르지 않습니다.';
  end if;

  if p_evidence_content is null or length(trim(p_evidence_content)) = 0 then
    raise exception '증거 내용이 비어 있습니다.';
  end if;

  -- 품질전은 사진 필수(텍스트만으로는 증명으로 인정하지 않는다). 속도전은 사진/텍스트 둘 다 허용.
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

  if v_battle.status = 'active' then
    update public.battles set status = 'judging' where id = p_battle_id;
  end if;
end;
$$;

-- 판정: 상대방의 증거를 approve/dispute한다. 결과 판정은 유형별로 다르다.
--   품질전 - 승자 개념이 없다. dispute 하나면 즉시 disputed, 양쪽 approve면 finished.
--   속도전 - dispute는 그 참가자의 완료를 무효화할 뿐 즉시 종결이 아니다.
--            양쪽 판정이 모두 내려진 뒤 유효한(approve된) 완료 개수로 결과를 낸다.
create function public.decide_evidence(
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

  -- 판정을 반영한 뒤 두 참가자 행을 다시 읽어 결과를 계산한다.
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

  -- 속도전: 양쪽 판정이 모두 내려져야 유효한 완료가 몇 개인지 확정된다.
  if v_self.decision is null then
    return;  -- 상대가 아직 내 증거를 판정하지 않음 -> judging 유지
  end if;

  if v_self.decision = 'approve' and v_target.decision = 'approve' then
    -- 둘 다 유효 -> 증거 제출 시각이 이른 쪽 승리
    update public.battles
    set status = 'finished',
        finished_at = now(),
        winner_id = case
          when v_self.evidence_submitted_at <= v_target.evidence_submitted_at then v_self.user_id
          else v_target.user_id
        end
    where id = p_battle_id;
  elsif v_self.decision = 'approve' then
    -- 내 완료만 유효(상대는 이의제기로 무효) -> 제출이 늦었더라도 내가 승리
    update public.battles
    set status = 'finished', finished_at = now(), winner_id = v_self.user_id
    where id = p_battle_id;
  elsif v_target.decision = 'approve' then
    -- 상대 완료만 유효 -> 상대 승리
    update public.battles
    set status = 'finished', finished_at = now(), winner_id = v_target.user_id
    where id = p_battle_id;
  else
    -- 양쪽 다 이의제기 -> 유효한 완료가 없으므로 승자 없이 미결
    update public.battles
    set status = 'disputed', finished_at = now()
    where id = p_battle_id;
  end if;
end;
$$;

grant execute on function public.submit_evidence(uuid, text, text) to authenticated;
grant execute on function public.decide_evidence(uuid, uuid, text) to authenticated;

-- 증거 사진 저장소. 비공개 버킷이며 조회는 서명 URL로만 한다.
-- 경로 규칙: {battle_id}/{user_id}/evidence.jpg
insert into storage.buckets (id, name, public)
values ('battle_evidence', 'battle_evidence', false)
on conflict (id) do nothing;

-- 업로드: 본인 폴더에만, 그리고 실제 참가자이고 증거 제출 가능한 상태일 때만.
-- (b.id::text로 비교해 폴더명이 uuid가 아닐 때 캐스팅 에러가 나지 않게 한다)
create policy "participants can upload own evidence"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'battle_evidence'
    and (storage.foldername(name))[2] = auth.uid()::text
    and exists (
      select 1 from public.battles b
      where b.id::text = (storage.foldername(name))[1]
        and auth.uid() in (b.creator_id, b.opponent_id)
        and b.status in ('active', 'judging')
    )
  );

-- 재제출(upsert) 시 update도 열어야 한다.
create policy "participants can update own evidence"
  on storage.objects for update
  to authenticated
  using (
    bucket_id = 'battle_evidence'
    and (storage.foldername(name))[2] = auth.uid()::text
  )
  with check (
    bucket_id = 'battle_evidence'
    and (storage.foldername(name))[2] = auth.uid()::text
    and exists (
      select 1 from public.battles b
      where b.id::text = (storage.foldername(name))[1]
        and auth.uid() in (b.creator_id, b.opponent_id)
        and b.status in ('active', 'judging')
    )
  );

-- 조회: 참가자라면 본인/상대 증거 사진을 모두 볼 수 있어야 승인 화면에서 보여줄 수 있다.
create policy "participants can read battle evidence"
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'battle_evidence'
    and exists (
      select 1 from public.battles b
      where b.id::text = (storage.foldername(name))[1]
        and auth.uid() in (b.creator_id, b.opponent_id)
    )
  );
