-- 대결 마감 시각.
--
-- 상대가 잠수하면 대결이 active/judging으로 영영 남는 문제를 푼다. 포기(기권)는 내가 빠져나가는
-- 수단일 뿐이고, 잠수를 푸는 건 마감이다.
--
-- 규칙
--   - 기간은 대결을 만든 사람이 정한다(1일/3일/7일). 마감은 매칭되는 순간부터 흐른다 —
--     모집만 걸어두고 아무도 안 오는 동안 시간이 깎이면 안 되기 때문이다.
--   - 마감이 지나면 그 시점의 상태로 승부를 낸다. 이때 마감이 판정을 대신한다:
--     증거를 냈고 상대에게 이의제기를 받지 않았으면 유효한 완료로 본다(미판정 = 승인 취급).
--     그러지 않으면 잠수한 상대가 내 승리를 막을 수 있다.
--   - 속도전: 유효한 완료가 양쪽이면 제출이 이른 쪽 승리, 한쪽이면 그쪽 승리, 없으면 무승부.
--   - 품질전: 승자를 두지 않는 유형이므로 양쪽 다 유효하면 finished, 그 외에는 무승부.
--   - 무승부는 새 상태 draw다. 이의제기로 끝난 disputed("싸우다 못 끝냈다")와 구별해야
--     "시간이 다 됐다"를 화면에서 다르게 말할 수 있다.

alter table public.battles
  drop constraint battles_status_check,
  add constraint battles_status_check
    check (status in ('pending', 'active', 'judging', 'finished', 'disputed', 'cancelled', 'draw'));

alter table public.battles
  add column duration_hours integer not null default 72
    constraint battles_duration_hours_check check (duration_hours in (24, 72, 168)),
  add column deadline_at timestamptz;

comment on column public.battles.duration_hours is
  '대결을 만든 사람이 고른 기간. 매칭 시점에 이 값으로 deadline_at을 계산한다.';
comment on column public.battles.deadline_at is
  '마감 시각(서버). 매칭(join_battle) 시점에 정해지며 모집 중에는 null이다.';

-- 매칭되는 순간 마감을 건다. 나머지 동작은 그대로다.
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
  set opponent_id = auth.uid(),
      status = 'active',
      started_at = now(),
      deadline_at = now() + make_interval(hours => v_battle.duration_hours)
  where id = p_battle_id;

  insert into public.battle_participants (battle_id, user_id)
  values (p_battle_id, auth.uid());
end;
$$;

-- 마감이 지난 대결을 종결시킨다. 사용자가 아니라 스케줄러가 부르는 함수라
-- auth.uid() 가드를 두지 않는다(가드를 두면 cron에서 항상 실패한다).
-- 대신 authenticated/anon/public에서 EXECUTE를 전부 회수해 앱에서는 부를 수 없게 한다.
create function public.settle_expired_battles()
returns integer
language plpgsql
security definer set search_path = public
as $$
declare
  v_battle public.battles%rowtype;
  v_creator public.battle_participants%rowtype;
  v_opponent public.battle_participants%rowtype;
  v_creator_done boolean;
  v_opponent_done boolean;
  v_winner uuid;
  v_settled integer := 0;
begin
  for v_battle in
    select * from public.battles
    where status in ('active', 'judging')
      and deadline_at is not null
      and deadline_at <= now()
      and opponent_id is not null
    order by deadline_at
    for update skip locked
  loop
    select * into v_creator from public.battle_participants
    where battle_id = v_battle.id and user_id = v_battle.creator_id;

    select * into v_opponent from public.battle_participants
    where battle_id = v_battle.id and user_id = v_battle.opponent_id;

    -- 마감이 판정을 대신한다. 이의제기를 받은 완료만 무효다.
    v_creator_done := v_creator.evidence_submitted_at is not null
      and v_creator.decision is distinct from 'dispute';
    v_opponent_done := v_opponent.evidence_submitted_at is not null
      and v_opponent.decision is distinct from 'dispute';

    if v_battle.type = 'speed' then
      if v_creator_done and v_opponent_done then
        v_winner := case
          when v_creator.evidence_submitted_at <= v_opponent.evidence_submitted_at
          then v_creator.user_id
          else v_opponent.user_id
        end;
      elsif v_creator_done then
        v_winner := v_creator.user_id;
      elsif v_opponent_done then
        v_winner := v_opponent.user_id;
      else
        v_winner := null;
      end if;

      if v_winner is null then
        update public.battles
        set status = 'draw', finished_at = now()
        where id = v_battle.id;
      else
        update public.battles
        set status = 'finished', winner_id = v_winner, finished_at = now()
        where id = v_battle.id;
      end if;
    else
      -- 품질전은 승자를 두지 않는다. 둘 다 해냈으면 종료, 아니면 무승부.
      if v_creator_done and v_opponent_done then
        update public.battles
        set status = 'finished', finished_at = now()
        where id = v_battle.id;
      else
        update public.battles
        set status = 'draw', finished_at = now()
        where id = v_battle.id;
      end if;
    end if;

    v_settled := v_settled + 1;
  end loop;

  return v_settled;
end;
$$;

revoke execute on function public.settle_expired_battles() from public, anon, authenticated;
revoke execute on function public.join_battle(uuid) from public, anon;
grant execute on function public.join_battle(uuid) to authenticated;

-- 앱을 아무도 열지 않아도 결과가 나와야 하므로 스케줄러가 돌린다.
create extension if not exists pg_cron;

select cron.schedule(
  'settle-expired-battles',
  '*/5 * * * *',
  $$select public.settle_expired_battles()$$
);
