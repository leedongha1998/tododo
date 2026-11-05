-- 대결 한도 제거: 하루 1대결과 모집 중 1개를 없애고 기준 생성 10회만 남긴다.
--
-- 근거: docs/specs/daily-limit-removal/decision.md (2026-11-06 오너 결정).
--
-- 왜: 한도의 목적은 AI 비용 억제였는데, mutual-judge로 바뀌면서 "대결 하나 = AI 호출 하나"라는
-- 전제가 깨졌다. 1차 판정은 사람이 하고 AI는 불복·우열 불일치에만 불린다. 보장된 AI 지출은
-- 기준 생성 10회/일이 이미 막는다. **AI 재판정 호출에 상한이 없어지는 것은 오너가 알고 고른
-- 쪽이다**(대안 두 개를 제시했고 "그냥 없앤다"를 선택). 비용이 실제로 문제가 되면 그때 재판정
-- 한도를 새로 둔다 - 지금 미리 만들지 않는다.
--
-- 판정·점수·상태 전이·종결 규칙은 한 줄도 바꾸지 않는다. 바뀌는 것은 "대결을 몇 개 할 수
-- 있는가"뿐이다.
--
-- 함수 본문은 전부 **가장 늦은 정의를 그대로 복사한 뒤 한도 부분만 걷어냈다.** 기준이 된 파일:
-- begin_criteria_call·get_my_limits=20260916130000, create_battle=20260921120100,
-- join_battle·void_battle·delete_account=20261103120000.

-- ---------------------------------------------------------------------------
-- 모집 중 1개 제한: 유니크 인덱스 제거
-- ---------------------------------------------------------------------------
drop index public.battles_one_pending_per_creator;

-- ---------------------------------------------------------------------------
-- begin_criteria_call: 기준 생성 전 한도 검사에서 대결 수 조건을 뺀다
-- ---------------------------------------------------------------------------
-- 남는 검사는 동의와 기준 생성 10회뿐이다. 'generate'는 더 이상 사전 조건이 없어 분기가
-- 비므로, 모집 수정('check' + battle_id)만 따로 본다.
create or replace function public.begin_criteria_call(
  p_user_id uuid,
  p_action text,
  p_battle_id uuid default null
)
returns uuid
language plpgsql
security definer set search_path = public
as $$
declare
  v_today date := (now() at time zone 'Asia/Seoul')::date;
  v_call_id uuid;
begin
  if p_user_id is null then
    raise exception '사용자가 필요합니다.';
  end if;

  if p_action not in ('generate', 'check') then
    raise exception '올바르지 않은 호출 유형입니다.';
  end if;

  -- 같은 사용자의 동시 요청을 직렬화해 한도를 정확히 센다.
  perform pg_advisory_xact_lock(hashtext(p_user_id::text));

  -- 동의 전에는 제목도 기준도 AI로 나가면 안 된다. 그래서 Gemini 호출 전에 여기서 막는다.
  perform 1 from public.ai_consents where user_id = p_user_id;
  if not found then
    raise exception using message = 'AI 데이터 제공 동의가 필요합니다.', hint = 'CONSENT_REQUIRED';
  end if;

  if p_action <> 'generate' and p_battle_id is not null then
    -- 모집 중 기준 수정. 매칭된 뒤에는 누구도 기준을 바꿀 수 없다.
    perform 1 from public.battles
    where id = p_battle_id and creator_id = p_user_id and status = 'pending';
    if not found then
      raise exception using message = '모집 중인 내 대결이 아닙니다.', hint = 'NOT_PENDING';
    end if;
  end if;

  if public.criteria_calls_used(p_user_id, v_today) >= 10 then
    raise exception using message = '오늘 기준 생성 횟수를 다 썼습니다.', hint = 'CRITERIA_CALL_LIMIT';
  end if;

  insert into public.ai_criteria_calls (user_id, kst_date, status)
  values (p_user_id, v_today, 'in_progress')
  returning id into v_call_id;

  return v_call_id;
end;
$$;

comment on function public.begin_criteria_call(uuid, text, uuid) is
  'AI 기준 생성·검사 호출을 시작한다. 남은 한도는 동의와 하루 10회뿐이다(대결 수 제한 없음).';

-- ---------------------------------------------------------------------------
-- create_battle: 모집 등록에서 두 한도 검사를 뺀다
-- ---------------------------------------------------------------------------
-- 유니크 인덱스가 사라졌으므로 경합을 잡던 unique_violation 처리도 함께 없앤다.
create or replace function public.create_battle(p_check_id uuid, p_duration_minutes integer)
returns uuid
language plpgsql
security definer set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_check public.criteria_checks%rowtype;
  v_battle_id uuid;
begin
  if v_user is null then
    raise exception '로그인이 필요합니다.';
  end if;

  -- null을 따로 보는 이유: 옛 검사(not in (24,72,168))는 null이면 NULL로 평가돼 통과한 뒤
  -- not null 컬럼 제약에서 깨졌다. 같은 함수가 같은 문구로 막는 쪽이 읽힌다.
  if p_duration_minutes is null or p_duration_minutes < 1 or p_duration_minutes > 10080 then
    raise exception '기간이 올바르지 않습니다.';
  end if;

  perform 1 from public.ai_consents where user_id = v_user;
  if not found then
    raise exception using message = 'AI 데이터 제공 동의가 필요합니다.', hint = 'CONSENT_REQUIRED';
  end if;

  select * into v_check
  from public.criteria_checks
  where id = p_check_id and user_id = v_user
  for update;

  -- 차단됐거나, 이미 썼거나, 오래됐거나, 모집 수정용 증서면 생성에 쓸 수 없다.
  if not found
     or not v_check.provable
     or v_check.consumed_at is not null
     or v_check.created_at <= now() - interval '24 hours'
     or v_check.battle_id is not null then
    raise exception using message = '사용할 수 없는 기준입니다.', hint = 'CHECK_INVALID';
  end if;

  insert into public.battles (
    type, status, title, creator_id, duration_minutes, min_criteria, superiority_criteria
  )
  values (
    v_check.type, 'pending', v_check.title, v_user, p_duration_minutes,
    v_check.min_criteria, v_check.superiority_criteria
  )
  returning id into v_battle_id;

  update public.criteria_checks set consumed_at = now() where id = p_check_id;

  return v_battle_id;
end;
$$;

comment on function public.create_battle(uuid, integer) is
  '기준 증서로 모집을 올린다. 기간은 분 단위(1~10080)이고 마감은 매칭 시점에 걸린다. '
  '모집 개수 제한 없음.';

-- ---------------------------------------------------------------------------
-- join_battle: 참가에서 양쪽 한도 검사와 슬롯 기록을 뺀다
-- ---------------------------------------------------------------------------
-- 기준: 20261103120000_notification_events.sql. N1 알림 적재는 그대로 둔다.
create or replace function public.join_battle(p_battle_id uuid, p_criteria_version integer)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_battle public.battles%rowtype;
  v_deadline_at timestamptz;
begin
  if auth.uid() is null then
    raise exception '로그인이 필요합니다.';
  end if;

  -- 잠금 순서는 "내 동의 행 -> 대결"이다(withdraw_ai_consent와 같은 순서라 교착이 없다).
  perform 1 from public.ai_consents where user_id = auth.uid() for share;
  if not found then
    raise exception using message = 'AI 데이터 제공 동의가 필요합니다.', hint = 'CONSENT_REQUIRED';
  end if;

  select * into v_battle from public.battles where id = p_battle_id for update;

  if v_battle is null then
    raise exception '대결을 찾을 수 없습니다.';
  end if;

  if v_battle.status <> 'pending' or v_battle.opponent_id is not null then
    raise exception using message = '이미 매칭되었거나 종료된 모집입니다.', hint = 'ALREADY_MATCHED';
  end if;

  if auth.uid() = v_battle.creator_id then
    raise exception '본인이 등록한 모집에는 참가할 수 없습니다.';
  end if;

  -- 참가자가 본 기준과 지금 기준이 다르면 참가가 성립하지 않는다(결정 46).
  if v_battle.criteria_version is distinct from p_criteria_version then
    raise exception using message = '기준이 바뀌었습니다.', hint = 'CRITERIA_CHANGED';
  end if;

  update public.battles
  set opponent_id = auth.uid(),
      status = 'active',
      started_at = now(),
      deadline_at = now() + make_interval(mins => v_battle.duration_minutes)
  where id = p_battle_id
  returning deadline_at into v_deadline_at;

  insert into public.battle_participants (battle_id, user_id)
  values (p_battle_id, auth.uid());

  -- N1. 참가한 본인에게는 보내지 않는다(내 행동의 결과라 알릴 것이 없다).
  -- 참가자 이름을 담지 않는다 - 표시 이름은 소셜 로그인에서 온 실명일 수 있다.
  perform public.enqueue_notification(
    v_battle.creator_id,
    'matched',
    p_battle_id,
    'matched:' || p_battle_id::text,
    jsonb_build_object(
      'title', v_battle.title,
      'battle_type', v_battle.type,
      'deadline_at', v_deadline_at
    )
  );
end;
$$;

comment on function public.join_battle(uuid, integer) is
  '모집 참가. 내가 확인한 기준 버전으로만 참가하며, 매칭되는 순간 제출 창 마감(duration_minutes '
  '분 뒤)이 걸린다. 생성자에게 매칭 알림을 적재한다. 하루 대결 수 제한 없음.';

-- ---------------------------------------------------------------------------
-- get_my_limits: 남은 한도는 기준 생성 횟수뿐이다
-- ---------------------------------------------------------------------------
-- has_pending·daily_battle_used를 더 내주지 않는다. 둘 다 한도를 설명하려고 있던 값이고,
-- 한도가 사라지면 화면이 그것으로 할 일이 없다(내가 올린 모집은 "내 대결" 탭이 보여 준다).
create or replace function public.get_my_limits()
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_today date := (now() at time zone 'Asia/Seoul')::date;
begin
  if v_user is null then
    raise exception '로그인이 필요합니다.';
  end if;

  return jsonb_build_object(
    'consented', exists (select 1 from public.ai_consents where user_id = v_user),
    'criteria_calls_left', greatest(10 - public.criteria_calls_used(v_user, v_today), 0)
  );
end;
$$;

comment on function public.get_my_limits is
  '남은 한도. 동의 여부와 오늘 남은 기준 생성 횟수만 돌려준다(대결 수 제한 없음).';

-- ---------------------------------------------------------------------------
-- void_battle: 슬롯 반환을 뺀다
-- ---------------------------------------------------------------------------
-- 기준: 20261103120000_notification_events.sql. 무효 알림은 그대로 둔다.
create or replace function public.void_battle(p_battle_id uuid)
returns void
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_battle public.battles%rowtype;
  v_payload jsonb;
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

  delete from public.ai_judgment_jobs where battle_id = p_battle_id;

  -- N2'. 실패 원인·사유는 담지 않는다("판정이 무효가 됐다"와 "점수·전적에 반영되지 않는다"까지만).
  -- opponent_id가 null이면 enqueue_notification이 조용히 지나간다.
  v_payload := jsonb_build_object('title', v_battle.title, 'battle_type', v_battle.type);

  perform public.enqueue_notification(
    v_battle.creator_id, 'voided', p_battle_id,
    'voided:' || p_battle_id::text, v_payload
  );
  perform public.enqueue_notification(
    v_battle.opponent_id, 'voided', p_battle_id,
    'voided:' || p_battle_id::text, v_payload
  );
end;
$$;

comment on function public.void_battle is
  'AI 재판정이 끝내 실패했을 때의 무효 종결. 점수 변화 없음, 남은 재판정 잡 삭제, 양쪽에 무효 '
  '알림 적재. 내부 전용.';

-- ---------------------------------------------------------------------------
-- delete_account: 슬롯 삭제와 N5의 slot_returned를 뺀다
-- ---------------------------------------------------------------------------
-- **20261103120000_notification_events.sql의 정의(가장 늦은 정의)를 기반으로** 고쳤다. 여덟 번
-- 재정의된 함수라 옛 정의를 베끼면 기준 증서·동의 기록·알림 토큰 삭제가 조용히 사라진다.
-- 이번에 바뀐 것은 슬롯 관련 두 곳(반환 삭제, 내 행 삭제)과 N5 payload의 slot_returned뿐이고,
-- 인자 없는 시그니처와 나머지 단계는 그대로다.
create or replace function public.delete_account()
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_cancelled_ids uuid[];
  v_cancelled record;
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

  -- N5. 남은 상대에게만. 상대가 없는 pending 모집은 알릴 사람이 없다(other_id가 null).
  -- 탈퇴한 사람의 이름은 담지 않는다. 한도가 없어졌으므로 "한도가 돌아왔다"는 말도 하지 않는다.
  for v_cancelled in
    select b.id,
           b.title,
           case when b.creator_id = v_user_id then b.opponent_id else b.creator_id end as other_id
    from public.battles b
    where b.id = any (v_cancelled_ids)
  loop
    perform public.enqueue_notification(
      v_cancelled.other_id,
      'cancelled',
      v_cancelled.id,
      'cancelled:' || v_cancelled.id::text,
      jsonb_build_object('title', v_cancelled.title)
    );
  end loop;

  -- 판정 대기 중이던 AI 재판정 잡. 대결이 취소됐으므로 판정할 것이 없다.
  delete from public.ai_judgment_jobs where battle_id = any (v_cancelled_ids);

  -- 2. 개인 투두.
  delete from public.todos where user_id = v_user_id;

  -- 3. 증거 사진 경로는 개인 데이터라 끊는다. 사진 파일은 앱이 이 RPC 직전에 Storage API로 지운다.
  --    제출 행 자체와 사유·시각은 남은 상대의 전적을 설명하는 판정 기록이라 남긴다.
  update public.battle_submissions
  set object_path = null
  where user_id = v_user_id;

  -- 4. 점수. 묘비 사용자의 점수는 공개 대상이 아니다.
  delete from public.player_stats where user_id = v_user_id;

  -- 5. 기준 증서와 호출 원장. 대결이 성립하기 전의 초안이라 보존할 이유가 없다.
  delete from public.criteria_checks where user_id = v_user_id;
  delete from public.ai_criteria_calls where user_id = v_user_id;

  -- 6. 동의·철회 기록. 탈퇴 후에는 남기지 않는다(decisions 68).
  delete from public.ai_consent_events where user_id = v_user_id;
  delete from public.ai_consents where user_id = v_user_id;

  -- 7. 알림 토큰과 내가 받을 알림. 개인정보처리방침의 "탈퇴 시 삭제"와 맞춘다.
  --    내가 수신자인 행만 지운다 - 상대가 받을 알림(방금 적재한 N5 포함)은 상대의 기록이다.
  delete from public.device_push_tokens where user_id = v_user_id;
  delete from public.notification_outbox where recipient_id = v_user_id;

  -- 8. 묘비화.
  update public.profiles
  set display_name = '탈퇴한 사용자', deleted_at = now()
  where id = v_user_id;

  -- 9. 실제 계정 삭제. 0행이면 "데이터만 지워지고 계정은 살아있는" 상태를 막기 위해 전체를 되돌린다.
  delete from auth.users where id = v_user_id;

  if not found then
    raise exception '계정을 삭제하지 못했습니다.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- daily_battle_slots: 아무도 읽지 않는 원장을 드롭한다
-- ---------------------------------------------------------------------------
-- 한도가 사라지면 이 테이블은 쓰는 곳도 보는 곳도 없다. 남겨 두면 "언젠가 한도가 돌아올지도
-- 모른다"는 미래 대비 구조가 된다(CLAUDE.md "하지 말 것"). 필요해지면 그때 다시 만든다.
-- 위 함수들을 먼저 고쳤으므로 이 시점에 이 테이블을 참조하는 코드는 하나도 없다.
drop table public.daily_battle_slots;
