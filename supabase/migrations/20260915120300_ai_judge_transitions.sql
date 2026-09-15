-- ai-judge 1단계: 종결 적용 함수와 포기·마감 정산·탈퇴 재작성.
--
-- 근거: docs/specs/ai-judge/design.md "점수와 outcome", "흐름 7. 마감 정산", "흐름 8. 포기",
-- "탈퇴(delete_account)와의 상호작용".
--
-- 권한 구조
--   - finalize_battle / void_battle / resolve_battle: 내부 전용. SECURITY INVOKER로 두고 EXECUTE를
--     public/anon/authenticated에서 모두 회수한다. SECURITY DEFINER 함수(forfeit_battle, delete_account)와
--     cron(settle_expired_battles) 안에서만 불리므로 함수 소유자(postgres) 권한으로 실행된다.
--     DEFINER가 아니므로 CLAUDE.md의 로그인 가드 규칙 대상이 아니고, 앱에서는 부를 수 없다.
--   - forfeit_battle / delete_account: 앱이 부르는 RPC. 로그인 가드 + is distinct from + anon 회수.
--   - settle_expired_battles: cron 전용. 기존과 같이 가드 없이 authenticated까지 회수.

-- ---------------------------------------------------------------------------
-- finalize_battle: 승패가 있는 모든 종결(속도전 R/D, 품질전 Q4/Q8/Q9, 포기)의 유일한 적용 지점
-- ---------------------------------------------------------------------------
-- 상태·승자·finished_at, 참가자 outcome·score_delta_applied, player_stats 점수(하한 0)·카운터를
-- 한 번에 기록한다. 점수 반영이 이 함수 한 곳에만 있어야 이중 반영이 생기지 않는다.
-- 호출자가 대결 행을 이미 잠갔더라도 여기서 다시 잠그고 진행 중인지 확인한다.
create function public.finalize_battle(
  p_battle_id uuid,
  p_status text,
  p_winner_id uuid,
  p_creator_outcome text,
  p_opponent_outcome text
)
returns void
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_battle public.battles%rowtype;
  v_participant record;
  v_delta integer;
  v_old_score integer;
  v_new_score integer;
begin
  select * into v_battle from public.battles where id = p_battle_id for update;

  if v_battle is null then
    raise exception '대결을 찾을 수 없습니다.';
  end if;

  if v_battle.status not in ('active', 'judging') then
    raise exception '진행 중인 대결만 종결할 수 있습니다. (현재: %)', v_battle.status;
  end if;

  if v_battle.opponent_id is null then
    raise exception '상대가 없는 대결은 종결할 수 없습니다.';
  end if;

  -- 호출부 실수로 규칙과 어긋난 결과가 기록되지 않게 모양을 검사한다.
  -- outcome이 null이면 점수 계산이 null -> greatest(null, 0) = 0이 되어 점수가 날아가므로 먼저 막는다.
  if p_creator_outcome is null or p_opponent_outcome is null then
    raise exception '종결 결과 값이 비어 있습니다.';
  end if;

  if p_status = 'finished' then
    if p_winner_id is null
       or (p_winner_id is distinct from v_battle.creator_id
           and p_winner_id is distinct from v_battle.opponent_id) then
      raise exception '승자가 이 대결의 참가자가 아닙니다.';
    end if;
    if (p_winner_id = v_battle.creator_id and (p_creator_outcome <> 'win'
          or p_opponent_outcome not in ('completed_loss', 'loss', 'forfeit')))
       or (p_winner_id = v_battle.opponent_id and (p_opponent_outcome <> 'win'
          or p_creator_outcome not in ('completed_loss', 'loss', 'forfeit'))) then
      raise exception '승자와 결과 값이 맞지 않습니다.';
    end if;
  elsif p_status = 'draw' then
    if p_winner_id is not null or p_creator_outcome <> 'draw' or p_opponent_outcome <> 'draw' then
      raise exception '무승부에는 승자가 없고 양쪽 결과가 draw여야 합니다.';
    end if;
  else
    raise exception '종결 상태가 올바르지 않습니다: %', p_status;
  end if;

  update public.battles
  set status = p_status,
      winner_id = p_winner_id,
      finished_at = now()
  where id = p_battle_id;

  for v_participant in
    select v_battle.creator_id as user_id, p_creator_outcome as outcome
    union all
    select v_battle.opponent_id, p_opponent_outcome
  loop
    v_delta := public.outcome_score_delta(v_participant.outcome);

    -- 가입 트리거·백필로 행이 있어야 하지만, 없으면 0점에서 시작한다.
    insert into public.player_stats (user_id)
    values (v_participant.user_id)
    on conflict (user_id) do nothing;

    select score into v_old_score
    from public.player_stats
    where user_id = v_participant.user_id
    for update;

    v_new_score := greatest(v_old_score + v_delta, 0);

    update public.player_stats
    set score = v_new_score,
        wins = wins + case when v_participant.outcome = 'win' then 1 else 0 end,
        losses = losses + case when v_participant.outcome in ('completed_loss', 'loss', 'forfeit') then 1 else 0 end,
        draws = draws + case when v_participant.outcome = 'draw' then 1 else 0 end
    where user_id = v_participant.user_id;

    update public.battle_participants
    set outcome = v_participant.outcome,
        score_delta_applied = v_new_score - v_old_score
    where battle_id = p_battle_id and user_id = v_participant.user_id;
  end loop;
end;
$$;

comment on function public.finalize_battle is
  '승패가 있는 종결의 유일한 적용 지점(상태·승자·outcome·점수 하한 0·카운터). 내부 전용.';

-- ---------------------------------------------------------------------------
-- void_battle: AI 판정 실패로 무효 종결 (MVP에서는 6단계 품질전 재시도 소진만 부른다)
-- ---------------------------------------------------------------------------
-- 점수·전적은 건드리지 않는다. 매칭된 날(KST)이 오늘인 슬롯만 지워 오늘 한도를 돌려준다.
-- 매칭일이 지난 슬롯은 남는다 — 지워도 오늘 한도가 늘지 않고, 하루 2대결 구멍이 생기지 않게.
create function public.void_battle(p_battle_id uuid)
returns void
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_battle public.battles%rowtype;
begin
  select * into v_battle from public.battles where id = p_battle_id for update;

  if v_battle is null then
    raise exception '대결을 찾을 수 없습니다.';
  end if;

  if v_battle.status not in ('active', 'judging') then
    raise exception '진행 중인 대결만 무효로 만들 수 있습니다. (현재: %)', v_battle.status;
  end if;

  update public.battles
  set status = 'voided',
      finished_at = now()
  where id = p_battle_id;

  delete from public.daily_battle_slots
  where battle_id = p_battle_id
    and kst_date = (now() at time zone 'Asia/Seoul')::date;
end;
$$;

comment on function public.void_battle is
  'AI 판정 실패 무효 종결. 점수 변화 없음, 매칭일이 오늘(KST)인 슬롯만 반환. 내부 전용.';

-- ---------------------------------------------------------------------------
-- resolve_battle: 현재 제출 상태로 종결 여부를 보고, 종결이면 finalize_battle로 적용한다
-- ---------------------------------------------------------------------------
-- 규칙 계산은 순수 함수(speed_outcome, quality_deadline_outcome)에 맡긴다.
-- 부르는 곳: settle_expired_battles(1단계), record_speed_verdict·sweep(5단계).
-- 반환: 호출 뒤의 대결 상태. 이미 종결된 대결이면 아무것도 바꾸지 않고 현재 상태를 돌려준다
-- (늦게 도착한 판정이 종결된 대결의 점수를 다시 건드리지 않게).
create function public.resolve_battle(p_battle_id uuid)
returns text
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_battle public.battles%rowtype;
  v_deadline_passed boolean;
  v_a_passed_at timestamptz;
  v_a_pass_seq bigint;
  v_a_attempts integer;
  v_a_judging boolean;
  v_b_passed_at timestamptz;
  v_b_pass_seq bigint;
  v_b_attempts integer;
  v_b_judging boolean;
  v_a_submitted boolean;
  v_b_submitted boolean;
  v_speed record;
  v_quality record;
begin
  select * into v_battle from public.battles where id = p_battle_id for update;

  if v_battle is null then
    raise exception '대결을 찾을 수 없습니다.';
  end if;

  if v_battle.status not in ('active', 'judging') or v_battle.opponent_id is null then
    return v_battle.status;
  end if;

  v_deadline_passed := v_battle.deadline_at is not null and v_battle.deadline_at <= now();

  if v_battle.type = 'speed' then
    -- 요약 컬럼이 아니라 제출 원본에서 센다. error는 횟수에 넣지 않는다.
    select
      min(s.submitted_at) filter (where s.status = 'passed'),
      min(s.id) filter (where s.status = 'passed'),
      count(*) filter (where s.status in ('passed', 'failed')),
      coalesce(bool_or(s.status = 'judging'), false)
    into v_a_passed_at, v_a_pass_seq, v_a_attempts, v_a_judging
    from public.battle_submissions s
    where s.battle_id = p_battle_id and s.user_id = v_battle.creator_id;

    select
      min(s.submitted_at) filter (where s.status = 'passed'),
      min(s.id) filter (where s.status = 'passed'),
      count(*) filter (where s.status in ('passed', 'failed')),
      coalesce(bool_or(s.status = 'judging'), false)
    into v_b_passed_at, v_b_pass_seq, v_b_attempts, v_b_judging
    from public.battle_submissions s
    where s.battle_id = p_battle_id and s.user_id = v_battle.opponent_id;

    select * into v_speed
    from public.speed_outcome(
      v_a_passed_at, v_a_pass_seq, v_a_attempts, v_a_judging,
      v_b_passed_at, v_b_pass_seq, v_b_attempts, v_b_judging,
      v_deadline_passed
    );

    if v_speed.decision = 'continue' then
      return v_battle.status;
    end if;

    perform public.finalize_battle(
      p_battle_id,
      case when v_speed.decision = 'draw' then 'draw' else 'finished' end,
      case v_speed.winner
        when 'a' then v_battle.creator_id
        when 'b' then v_battle.opponent_id
        else null
      end,
      v_speed.a_outcome,
      v_speed.b_outcome
    );

    return case when v_speed.decision = 'draw' then 'draw' else 'finished' end;
  end if;

  -- 품질전. judging은 판정 잡(6단계)이 끝낸다. 마감이 지나도 기다린다(Q10).
  if v_battle.status = 'judging' or not v_deadline_passed then
    return v_battle.status;
  end if;

  select exists (
    select 1 from public.battle_submissions s
    where s.battle_id = p_battle_id and s.user_id = v_battle.creator_id and s.status = 'submitted'
  ) into v_a_submitted;

  select exists (
    select 1 from public.battle_submissions s
    where s.battle_id = p_battle_id and s.user_id = v_battle.opponent_id and s.status = 'submitted'
  ) into v_b_submitted;

  select * into v_quality from public.quality_deadline_outcome(v_a_submitted, v_b_submitted);

  -- 양쪽 제출인데 active로 남은 불일치 상태. 정산을 멈추지 않고 건너뛴다.
  if v_quality.status is null then
    return v_battle.status;
  end if;

  perform public.finalize_battle(
    p_battle_id,
    v_quality.status,
    case v_quality.winner
      when 'a' then v_battle.creator_id
      when 'b' then v_battle.opponent_id
      else null
    end,
    v_quality.a_outcome,
    v_quality.b_outcome
  );

  return v_quality.status;
end;
$$;

comment on function public.resolve_battle is
  '제출 원본으로 종결 여부를 계산해 finalize_battle로 적용. 종결된 대결은 그대로 반환. 내부 전용.';

revoke execute on function public.finalize_battle(uuid, text, uuid, text, text) from public, anon, authenticated;
revoke execute on function public.void_battle(uuid) from public, anon, authenticated;
revoke execute on function public.resolve_battle(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- forfeit_battle 재작성: 유형 무관 포기한 쪽 패배(-3), 상대 승리(+3)
-- ---------------------------------------------------------------------------
-- 품질전도 승자를 두므로 disputed로 끝내지 않는다(결정 56).
-- 판정 중인 속도전 제출은 그대로 둔다. 나중에 도착한 판정은 제출 행에만 남고,
-- resolve_battle은 종결된 대결을 건드리지 않는다.
create or replace function public.forfeit_battle(p_battle_id uuid)
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

  -- null에 안전한 형태. opponent_id가 null이어도 그대로 쓸 수 있다.
  if auth.uid() is distinct from v_battle.creator_id
     and auth.uid() is distinct from v_battle.opponent_id then
    raise exception '이 대결의 참가자가 아닙니다.';
  end if;

  if v_battle.status not in ('active', 'judging') then
    raise exception '포기할 수 있는 상태가 아닙니다.';
  end if;

  v_opponent := case
    when auth.uid() = v_battle.creator_id then v_battle.opponent_id
    else v_battle.creator_id
  end;

  -- 상대가 없는 모집은 포기가 아니라 취소다.
  if v_opponent is null then
    raise exception '아직 상대가 없는 대결입니다.';
  end if;

  update public.battles
  set forfeited_by = auth.uid()
  where id = p_battle_id;

  perform public.finalize_battle(
    p_battle_id,
    'finished',
    v_opponent,
    case when auth.uid() = v_battle.creator_id then 'forfeit' else 'win' end,
    case when auth.uid() = v_battle.creator_id then 'win' else 'forfeit' end
  );
end;
$$;

revoke execute on function public.forfeit_battle(uuid) from public, anon;
grant execute on function public.forfeit_battle(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- settle_expired_battles 재작성: 마감이 지난 대결을 새 규칙으로 정산
-- ---------------------------------------------------------------------------
-- 기존 "마감이 판정을 대신한다" 규칙은 폐기한다(spec "마감 정산").
-- 판정 중인 제출이 있는 속도전과 judging 품질전은 건너뛴다 — 판정을 끝내는 쪽(5·6단계)이
-- resolve_battle에서 마감까지 함께 본다. cron은 안전망이다.
-- cron 전용이라 auth.uid() 가드를 두지 않고(cron에는 uid가 없어 항상 실패) EXECUTE를 전부 회수한다.
-- pg_cron 작업 'settle-expired-battles'(5분)는 이름·주기 그대로 이 함수를 부른다.
create or replace function public.settle_expired_battles()
returns integer
language plpgsql
security definer set search_path = public
as $$
declare
  v_battle_id uuid;
  v_status text;
  v_settled integer := 0;
begin
  for v_battle_id in
    select b.id from public.battles b
    where b.status in ('active', 'judging')
      and b.deadline_at is not null
      and b.deadline_at <= now()
      and b.opponent_id is not null
    order by b.deadline_at
    for update skip locked
  loop
    v_status := public.resolve_battle(v_battle_id);

    if v_status in ('finished', 'draw') then
      v_settled := v_settled + 1;
    end if;
  end loop;

  return v_settled;
end;
$$;

revoke execute on function public.settle_expired_battles() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- delete_account 재작성
-- ---------------------------------------------------------------------------
-- 2단계(동의 기록), 3단계(기준 원장), 6단계(판정 잡)가 각자 정리 줄을 이어 붙인다.
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

  -- 5. 묘비화.
  update public.profiles
  set display_name = '탈퇴한 사용자', deleted_at = now()
  where id = v_user_id;

  -- 6. 실제 계정 삭제. 0행이면 "데이터만 지워지고 계정은 살아있는" 상태를 막기 위해 전체를 되돌린다.
  delete from auth.users where id = v_user_id;

  if not found then
    raise exception '계정을 삭제하지 못했습니다.';
  end if;
end;
$$;

revoke execute on function public.delete_account() from public, anon;
grant execute on function public.delete_account() to authenticated;
