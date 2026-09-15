-- ai-judge 2단계: AI 데이터 제공 동의와 철회.
--
-- 근거: docs/specs/ai-judge/spec.md "P0. AI 데이터 제공 동의", design.md "흐름 1", "흐름 8", 화면 1·2,
-- decisions.md 48(제3자 제공·국외 이전이라 별도 동의), 66(철회 시 진행 중 대결은 포기), 68(탈퇴 시 기록 삭제).
--
-- Gemini 무료 등급은 제출한 콘텐츠를 Google이 서비스 개선에 쓰고 사람이 검토할 수 있어, 처리 위탁이 아니라
-- 제3자 제공·국외 이전이다. 그래서 대결 생성·참가 전에 앱 안에서 별도 동의를 받고, 동의 없이는 서버가 막는다.
--
-- 이 마이그레이션은 기존 데이터를 지우거나 바꾸지 않는다(적용 시점에 battles 0행).

-- ---------------------------------------------------------------------------
-- 동의 기록
-- ---------------------------------------------------------------------------
-- profiles에 컬럼으로 두지 않는 이유: profiles에는 본인 update 정책이 있어 동의 여부를 RPC 없이
-- 스스로 바꿀 수 있게 된다. 쓰기는 아래 RPC만 한다(insert/update/delete 정책 없음).
create table public.ai_consents (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  consent_version text not null,
  consented_at timestamptz not null default now()
);

comment on table public.ai_consents is
  'AI 데이터 제공 동의. 행이 있으면 동의한 상태, 철회하면 행을 지운다.';
comment on column public.ai_consents.consent_version is
  '동의한 문안 버전. 받는 자·항목·목적·보유 기간·거부 권리 문구를 바꾸면 올린다.';

alter table public.ai_consents enable row level security;

create policy "users can view their own ai consent"
  on public.ai_consents for select
  to authenticated
  using (user_id = auth.uid());

-- 동의·철회 이력. 탈퇴하면 함께 지운다(decisions 68).
create table public.ai_consent_events (
  id bigserial primary key,
  user_id uuid not null references public.profiles (id) on delete cascade,
  event text not null constraint ai_consent_events_event_check check (event in ('given', 'withdrawn')),
  consent_version text,
  created_at timestamptz not null default now()
);

create index ai_consent_events_user_idx on public.ai_consent_events (user_id, created_at);

alter table public.ai_consent_events enable row level security;

create policy "users can view their own ai consent events"
  on public.ai_consent_events for select
  to authenticated
  using (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- 동의
-- ---------------------------------------------------------------------------
create function public.give_ai_consent(p_version text)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception '로그인이 필요합니다.';
  end if;

  if p_version is null or length(trim(p_version)) = 0 then
    raise exception '동의 문안 버전이 필요합니다.';
  end if;

  insert into public.ai_consents (user_id, consent_version, consented_at)
  values (v_user, p_version, now())
  on conflict (user_id) do update
    set consent_version = excluded.consent_version,
        consented_at = now();

  insert into public.ai_consent_events (user_id, event, consent_version)
  values (v_user, 'given', p_version);
end;
$$;

-- 철회 확인 문구용. 철회하면 어떤 대결이 어떻게 처리되는지 미리 보여 준다.
create function public.get_consent_withdrawal_impact()
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_active integer;
  v_pending integer;
begin
  if v_user is null then
    raise exception '로그인이 필요합니다.';
  end if;

  select count(*) into v_active
  from public.battles
  where status in ('active', 'judging')
    and (creator_id = v_user or opponent_id = v_user);

  select count(*) into v_pending
  from public.battles
  where status = 'pending' and creator_id = v_user;

  return jsonb_build_object('active_count', v_active, 'pending_count', v_pending);
end;
$$;

-- 철회: 진행 중 대결은 모두 내 포기(-3, 상대 승리), 모집 중 대결은 취소.
-- 한도(daily_battle_slots)는 돌려주지 않는다 — 포기로 끝난 대결은 반환 대상이 아니다(spec).
-- 잠금 순서는 "내 동의 행 -> 내 대결"이다. join_battle도 같은 순서로 잡아 교착이 생기지 않는다.
create function public.withdraw_ai_consent()
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_version text;
  v_battle public.battles%rowtype;
  v_forfeited integer := 0;
  v_cancelled integer := 0;
begin
  if v_user is null then
    raise exception '로그인이 필요합니다.';
  end if;

  select consent_version into v_version
  from public.ai_consents
  where user_id = v_user
  for update;

  if not found then
    raise exception using message = '동의한 기록이 없습니다.', hint = 'CONSENT_REQUIRED';
  end if;

  -- 모집 중부터 정리한다. 이 사이에 누가 참가해 active가 되면 아래 루프가 포기로 처리한다.
  with cancelled as (
    update public.battles
    set status = 'cancelled', finished_at = now()
    where status = 'pending' and creator_id = v_user
    returning id
  )
  select count(*) into v_cancelled from cancelled;

  for v_battle in
    select * from public.battles
    where status in ('active', 'judging')
      and (creator_id = v_user or opponent_id = v_user)
    order by created_at
    for update
  loop
    -- 포기 규칙(상대 승리 +3, 나 -3, forfeited_by 기록)을 한 곳에서만 쓰기 위해 그대로 부른다.
    perform public.forfeit_battle(v_battle.id);
    v_forfeited := v_forfeited + 1;
  end loop;

  delete from public.ai_consents where user_id = v_user;

  insert into public.ai_consent_events (user_id, event, consent_version)
  values (v_user, 'withdrawn', v_version);

  return jsonb_build_object('forfeited', v_forfeited, 'cancelled', v_cancelled);
end;
$$;

revoke execute on function public.give_ai_consent(text) from public, anon;
revoke execute on function public.get_consent_withdrawal_impact() from public, anon;
revoke execute on function public.withdraw_ai_consent() from public, anon;
grant execute on function public.give_ai_consent(text) to authenticated;
grant execute on function public.get_consent_withdrawal_impact() to authenticated;
grant execute on function public.withdraw_ai_consent() to authenticated;

-- ---------------------------------------------------------------------------
-- 동의 없이는 대결에 들어갈 수 없다
-- ---------------------------------------------------------------------------
-- 참가: 기존 join_battle(uuid)에 동의 검사만 더한다. 나머지 동작은 그대로다.
-- 내 동의 행을 for share로 잡아, 철회가 진행 중이면 그 트랜잭션이 끝난 뒤에 판정된다.
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

  perform 1 from public.ai_consents where user_id = auth.uid() for share;

  if not found then
    raise exception using message = 'AI 데이터 제공 동의가 필요합니다.', hint = 'CONSENT_REQUIRED';
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

revoke execute on function public.join_battle(uuid) from public, anon;
grant execute on function public.join_battle(uuid) to authenticated;

-- 생성: 현재 대결 생성은 battles 직접 insert다(3단계에서 create_battle RPC로 바뀌며 이 정책은 사라진다).
-- 그때까지는 정책에 동의 검사를 넣어 동의 없이 만든 모집이 생기지 않게 한다.
-- 철회가 모집 중 대결을 취소하므로, 모집 목록에 있는 대결의 생성자는 항상 동의한 상태다.
drop policy "creator can create a pending battle" on public.battles;

create policy "consented creator can create a pending battle"
  on public.battles for insert
  to authenticated
  with check (
    auth.uid() = creator_id
    and status = 'pending'
    and exists (select 1 from public.ai_consents c where c.user_id = auth.uid())
  );

-- ---------------------------------------------------------------------------
-- 탈퇴 시 동의·철회 기록도 함께 삭제 (decisions 68)
-- ---------------------------------------------------------------------------
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

  -- 5. 동의·철회 기록. 탈퇴 후에는 남기지 않는다(decisions 68).
  delete from public.ai_consent_events where user_id = v_user_id;
  delete from public.ai_consents where user_id = v_user_id;

  -- 6. 묘비화.
  update public.profiles
  set display_name = '탈퇴한 사용자', deleted_at = now()
  where id = v_user_id;

  -- 7. 실제 계정 삭제. 0행이면 "데이터만 지워지고 계정은 살아있는" 상태를 막기 위해 전체를 되돌린다.
  delete from auth.users where id = v_user_id;

  if not found then
    raise exception '계정을 삭제하지 못했습니다.';
  end if;
end;
$$;

revoke execute on function public.delete_account() from public, anon;
grant execute on function public.delete_account() to authenticated;
