-- bot-battle 2단계: 봇전 시작·정산 RPC와 기존 함수 여섯 개의 봇전 분기, cron 등록.
--
-- 근거: docs/specs/bot-battle/design.md §1(핵심 난점)·§3(상태 전이)·§5(하루 3회)·§6(API 계약)·
--       §7(봇을 걸러야 하는 자리)·§8(동의 게이트)·§9(알림)·§15(2단계),
--       docs/specs/bot-battle/spec.md "합격선", 오너 결정 1~6.
--
-- 핵심 규칙
--   - **새 판정 기계를 만들지 않는다.** 봇전의 네 결과(승 / 완료한 패배 / 완료 못 한 패배 / 포기)는
--     전부 기존 judging_gate -> min_verdict_effect -> mutual_speed_outcome -> finalize_battle
--     사슬이 그대로 낸다. 그 네 함수는 **한 줄도 고치지 않는다.** 봇전이 더하는 것은 입력 두 개뿐이다 -
--     (a) 제출 시각이 t_bot인 사진 없는 봇 제출 행, (b) 판정 창이 열리는 순간 채워지는 자동 승인.
--   - **봇전은 판정 창이 열리는 시점에 끝난다. 그보다 일찍도, 늦게도 끝나지 않는다.**
--     일찍 끝나지 않게 하는 것: accept_submission이 봇전에서 "상대가 제출했는가"를 exists가 아니라
--     봇 행의 submitted_at <= now()로 보기 때문에 t_bot 전에는 게이트가 wait다(교체가 살아 있다).
--     늦게 끝나지 않게 하는 것: 창을 여는 유일한 지점(open_judging_window)이 봇전이면 자동 승인을
--     채우고 같은 트랜잭션에서 resolve_battle을 부른다 - 판정 기한 24시간이 한 번도 걸리지 않는다.
--   - **Gemini 호출 0회.** 이 파일에는 begin_criteria_call·lookup_criteria_cache·put_criteria_cache·
--     ensure_ai_judgment_job 호출이 하나도 없다. 봇전에 들어가는 판정은 approve + auto 두 행뿐이라
--     resolve_battle의 잡 생성 조건(min_verdict='reject')에 도달할 식이 없다.
--   - **사람 대결이 한 줄도 달라지지 않는다.** 아래 일곱 함수는 전부 분기를 **더하는** 모양이고,
--     사람 대결 경로의 조건·점수·문구는 그대로다.
--
-- 함수 본문은 전부 **가장 늦은 정의를 그대로 복사한 뒤** 봇전 분기만 끼워 넣었다. 기준이 된 파일:
--   enqueue_notification = 20260920120000
--   open_judging_window·accept_submission·finalize_battle = 20261103120000
--   get_player_card = 20260917120000
--   withdraw_ai_consent·get_consent_withdrawal_impact = 20260916120000
--   forfeit_battle = 20261029120000 (2026-11-22 reviewer W1으로 추가)
-- 전부 create or replace이고 시그니처를 유지하므로 GRANT는 그대로 남고, 배포된
-- submit-evidence Edge Function도 **재배포가 필요 없다**(accept_submission의 인자가 그대로다).
--
-- 적용 전 확인(오너): 1단계(20261120120000)가 적용되어 있어야 한다.

-- ---------------------------------------------------------------------------
-- bot_daily_battles_used: 하루 3회 계수 (원장 없이 battles를 센다)
-- ---------------------------------------------------------------------------
-- 원장(옛 daily_battle_slots 같은 것)을 두지 않는 이유: 기준 생성 10회는 "호출"이 행을 남기지
-- 않아 원장이 필요했지만, 봇전은 **시작 = battles 행 1개**라 원장이 사본일 뿐이다. 사본은 어긋날
-- 수 있고(이중 집계·누락), 2026-11-06에 드롭한 daily_battle_slots를 되살리는 모양이 된다.
--
-- 하루 경계는 기준 생성 10회와 **같은 식**(KST 자정)을 쓴다 - 사용자에게 자정이 두 개면 안 된다.
-- 다만 비교를 (started_at at time zone 'Asia/Seoul')::date = today가 아니라 **경계 시각 이상**으로
-- 쓴다. 함수 호출을 컬럼에 씌우지 않아 battles_bot_creator_started_idx를 그대로 탄다.
--
-- 돌려주지 않는다: 포기·무효·취소로 횟수가 돌아오지 않는다(돌려주면 "주제가 마음에 안 들면
-- 포기하고 다시 고르기"가 무한이 된다). 그래서 status를 보지 않고 행 자체를 센다.
create function public.bot_daily_battles_used(p_user_id uuid)
returns integer
language sql
stable
set search_path = public
as $$
  select count(*)::integer
  from public.battles
  where is_bot
    and creator_id = p_user_id
    and started_at >= (((now() at time zone 'Asia/Seoul')::date)::timestamp at time zone 'Asia/Seoul')
$$;

comment on function public.bot_daily_battles_used is
  '오늘(KST) 이 사용자가 시작한 봇전 수. 원장 없이 battles 행을 센다(포기·취소로 돌려주지 '
  '않으므로 status를 보지 않는다). 기준 생성 하루 10회와는 완전히 별개의 한도다. 내부 전용.';

revoke execute on function public.bot_daily_battles_used(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- list_bot_battle_topics: 주제 목록 + 오늘 남은 횟수 (앱이 부르는 RPC)
-- ---------------------------------------------------------------------------
-- 남은 횟수를 같은 응답에 담는 이유: bot_battle_topics는 RLS 정책이 0개라 읽는 경로가 이 함수
-- 하나다. get_my_limits는 **고치지 않는다** - 그 RPC는 동의 여부와 기준 생성 한도를 말하는
-- 자리이고, 두 한도를 한 응답에 섞으면 화면이 "오늘 남은 횟수"를 두 개 들고 있게 된다.
create function public.list_bot_battle_topics()
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_used integer;
begin
  if auth.uid() is null then
    raise exception '로그인이 필요합니다.';
  end if;

  v_used := public.bot_daily_battles_used(v_user);

  return jsonb_build_object(
    'daily_limit', 3,
    'daily_left', greatest(3 - v_used, 0),
    'topics', coalesce(
      (
        select jsonb_agg(
                 jsonb_build_object(
                   'id', t.id,
                   'title', t.title,
                   'min_criteria', t.min_criteria,
                   'duration_minutes', t.duration_minutes
                 )
                 order by t.sort_order, t.created_at
               )
        from public.bot_battle_topics t
        where t.active
      ),
      '[]'::jsonb
    )
  );
end;
$$;

comment on function public.list_bot_battle_topics is
  '연습 대결 주제 목록(active만, sort_order -> created_at 순)과 오늘 남은 횟수. '
  'bot_battle_topics를 읽는 유일한 경로다(그 테이블은 RLS 정책이 0개다).';

revoke execute on function public.list_bot_battle_topics() from public, anon;
grant execute on function public.list_bot_battle_topics() to authenticated;

-- ---------------------------------------------------------------------------
-- start_bot_battle: 봇전 시작 (앱이 부르는 RPC)
-- ---------------------------------------------------------------------------
-- 동의 검사도, 기준 생성 호출도, 캐시 조회도, 알림 적재도 **없다.**
--   - 동의: 봇전에서 Google로 나가는 것이 하나도 없다(기준은 운영자가 쓴 고정 문구, 사진은
--     아무도 보지 않고, 제목은 임베딩으로도 나가지 않는다). 막는 자리 셋(begin_criteria_call·
--     create_battle·join_battle)은 그대로 둔다(design §8).
--   - 알림: N1(매칭)을 보내지 않는다. 사용자가 직접 시작하므로 그 화면에 있다(design §9).
--
-- pending을 거치지 않고 active로 시작한다. 그래서 cancel_battle(모집 취소)이 적용될 자리가 없고,
-- 빠져나가는 길은 포기(forfeit_battle)뿐이다.
create function public.start_bot_battle(p_topic_id uuid)
returns uuid
language plpgsql
security definer set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_topic public.bot_battle_topics%rowtype;
  v_battle_id uuid;
  v_started_at timestamptz := now();
  v_deadline_at timestamptz;
  v_bot_at timestamptz;
begin
  if auth.uid() is null then
    raise exception '로그인이 필요합니다.';
  end if;

  -- 같은 사용자의 동시 호출을 직렬화해 하루 3회를 정확히 센다. **키를 기준 생성 한도와 다르게
  -- 둔다** - 같은 키(hashtext(user)) 를 쓰면 무관한 두 한도가 서로를 기다린다.
  perform pg_advisory_xact_lock(hashtext('bot_battle:' || v_user::text));

  if public.bot_daily_battles_used(v_user) >= 3 then
    raise exception using message = '오늘 연습 대결 횟수를 다 썼습니다.', hint = 'BOT_DAILY_LIMIT';
  end if;

  select * into v_topic
  from public.bot_battle_topics
  where id = p_topic_id and active;

  if not found then
    raise exception using message = '지금은 쓸 수 없는 주제입니다.', hint = 'BOT_TOPIC_INVALID';
  end if;

  v_deadline_at := v_started_at + make_interval(mins => v_topic.duration_minutes);

  -- ** t_bot: 봇의 목표 시각. 기간의 50~85% 구간에서 균등 무작위, 초 단위 내림. **
  -- 앞쪽이 잦으면 "시작하자마자 졌다"가 되고 뒤쪽이면 늘 이겨서 긴장이 없다(spec P0-3의 권고).
  -- 분 단위로 뽑으면 5분 주제에서 가능한 값이 3개뿐이라 금방 외워지므로 초 단위로 뽑는다.
  -- greatest(30, ...)는 1분 주제가 들어올 경우의 하한이다(지금 묶음에는 5분이 가장 짧다).
  --
  -- least(..., deadline - 1s)가 **t_bot < deadline_at 불변식을 계산이 아니라 코드로** 보장한다.
  -- 이 불변식이 깨지면 마감 시점에 봇이 "제출하지 않은" 것이 되어 draw가 생길 수 있고,
  -- "봇전에 draw가 없다"는 증명이 여기에 기대 있다. 증명에만 맡기지 않는다.
  -- make_interval의 secs는 double precision이다. greatest(integer, integer)가 integer를 내므로
  -- 암묵 캐스팅에 기대지 않고 ::double precision을 명시한다(초 단위 내림은 floor가 이미 했다).
  v_bot_at := v_started_at
    + make_interval(secs => greatest(
        30,
        floor(v_topic.duration_minutes * 60 * (0.50 + 0.35 * random()))::integer
      )::double precision);
  v_bot_at := least(v_bot_at, v_deadline_at - interval '1 second');

  -- 기준은 주제 행에서 **그대로 복사**한다(증서·캐시·임베딩을 거치지 않는다). criteria_version은
  -- 1로 고정되고 바뀌지 않는다 - update_battle_criteria는 status='pending'을 요구해 봇전에
  -- 도달하지 않는다. superiority_criteria는 null이어야 한다(battles_superiority_by_type).
  insert into public.battles (
    type, status, title, creator_id, opponent_id, started_at, deadline_at,
    duration_minutes, min_criteria, superiority_criteria, is_bot, bot_topic_id
  )
  values (
    'speed', 'active', v_topic.title, v_user, public.bot_user_id(), v_started_at, v_deadline_at,
    v_topic.duration_minutes, v_topic.min_criteria, null, true, v_topic.id
  )
  returning id into v_battle_id;

  -- battles_create_participants 트리거는 생성자 행 하나만 만든다(join_battle도 자기 행을 직접
  -- 넣는다). 봇 행이 없으면 앱의 battleDetailProvider가 "상대 참가자"를 찾다가 터진다.
  insert into public.battle_participants (battle_id, user_id)
  values (v_battle_id, public.bot_user_id());

  -- ** 봇 제출 행을 지금 넣는다. 제출 시각이 t_bot이다. **
  -- 여기에 두는 이유(design §1.4): battles·battle_participants는 참가자가 행 전체를 읽어
  -- t_bot이 그대로 새지만, battle_submissions의 select 정책은 "판정 창이 열리거나 종결된 뒤에만
  -- 상대 행"이라는 정확히 필요한 시점 분기를 이미 갖고 있다. 봇전에서 judging_opened_at이
  -- 찍히는 순간은 언제나 t_bot 이후이므로, 이 행이 보이기 시작하는 시점도 언제나 t_bot 이후다.
  -- 그전에는 사용자 세션이 자기 행만(0 또는 1행) 보므로 행 수로도 t_bot을 추정할 수 없다.
  --
  -- object_path·captured_at이 null이다. 사진이 없으므로 Storage에 발급할 서명 URL 자체가 없다.
  -- meets_criteria·verdict_source는 판정 창이 열릴 때 true/'auto'가 된다.
  insert into public.battle_submissions (battle_id, user_id, object_path, captured_at, submitted_at)
  values (v_battle_id, public.bot_user_id(), null, null, v_bot_at);

  return v_battle_id;
end;
$$;

comment on function public.start_bot_battle is
  '연습 봇과의 대결을 시작한다(하루 3회, KST 자정 경계). 주제 묶음의 제목·최소 기준·기간을 '
  '그대로 복사해 pending을 거치지 않고 active로 만들고, 봇의 참가자 행과 제출 행(제출 시각 = '
  '봇의 목표 시각)을 함께 넣는다. AI 호출·기준 생성 한도 소비·캐시 접촉·동의 검사·알림이 전혀 '
  '없다. 포기해도 그날의 횟수는 돌아오지 않는다.';

revoke execute on function public.start_bot_battle(uuid) from public, anon;
grant execute on function public.start_bot_battle(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- settle_bot_battle: 봇전 정산의 유일한 몸통 (내부 전용, 멱등)
-- ---------------------------------------------------------------------------
-- 권한 예외: 이 함수는 cron(settle_due_bot_battles)과 같은 트랜잭션의 SECURITY DEFINER
-- 함수(settle_my_bot_battles)만 부른다. 그래서 CLAUDE.md의 auth.uid() 로그인 가드를 **두지
-- 않는다** - cron에는 uid가 없어 가드를 두면 항상 실패한다(선례: settle_expired_battles·
-- close_expired_judging_windows·dispatch_notifications). Edge Function이 부르는 함수가 아니므로
-- service_role에도 주지 않고 EXECUTE를 전부 회수한다. 호출자가 "누구의 대결인지"를 이미 좁혔다.
--
-- 승패를 계산하지 않는다. 하는 일은 "지금 판정 창을 열 때가 됐는지"를 기존 judging_gate에 묻고,
-- 열 때가 됐으면 open_judging_window를 부르는 것뿐이다(그 안에서 자동 승인 + resolve_battle).
-- 그래서 몇 번 불러도, 언제 불려도 결과가 같다 - submitted_at은 과거에 서버가 찍은 값이고
-- 이 함수가 그 값을 만지지 않으므로 지연은 **결과가 아니라 결과를 아는 시점**만 바꾼다.
create function public.settle_bot_battle(p_battle_id uuid)
returns text
language plpgsql
security definer set search_path = public
as $$
declare
  v_battle public.battles%rowtype;
  v_user_submitted boolean;
  v_bot_revealed boolean;
  v_gate text;
  v_status text;
begin
  select * into v_battle from public.battles where id = p_battle_id for update;

  if not found then
    -- 없는 대결은 '없는 상태' 이름을 만들지 않고 null로 말한다(호출자는 'active'인지만 본다).
    return null;
  end if;

  -- 멱등: 봇전이 아니거나 이미 제출 창을 벗어났으면 아무것도 하지 않고 현재 상태를 돌려준다.
  if not v_battle.is_bot or v_battle.status <> 'active' then
    return v_battle.status;
  end if;

  -- 봇전은 creator = 사용자, opponent = 봇으로 고정이다(battles_bot_opponent_check가 보장).
  select exists (
    select 1 from public.battle_submissions
    where battle_id = p_battle_id and user_id = v_battle.creator_id
  ) into v_user_submitted;

  -- ** "봇이 제출했는가"가 아니라 "봇의 제출이 공개됐는가"다. ** 제출 행은 시작부터 있지만
  -- t_bot 전에는 아직 일어나지 않은 일이다(design §1.5).
  select exists (
    select 1 from public.battle_submissions
    where battle_id = p_battle_id
      and user_id = public.bot_user_id()
      and submitted_at <= now()
  ) into v_bot_revealed;

  -- 마감은 settle_expired_battles가 따로 본다. 여기서는 deadline_passed = false로 묻는다 -
  -- 즉 "양쪽 제출"이 성립할 때만 열린다. 사용자가 아직 내지 않았으면 wait이고, 마감까지 처음
  -- 제출할 수 있다(완료한 패배 경로).
  v_gate := public.judging_gate('speed', v_user_submitted, v_bot_revealed, false);

  if v_gate = 'open' then
    perform public.open_judging_window(p_battle_id);
  end if;

  select status into v_status from public.battles where id = p_battle_id;
  return v_status;
end;
$$;

comment on function public.settle_bot_battle is
  '봇전 한 건의 정산(멱등). 봇의 제출이 공개될 때가 됐고(submitted_at <= now()) 사용자도 냈으면 '
  '판정 창을 연다 - 그 안에서 자동 승인이 채워지고 같은 트랜잭션에서 종결된다. 승패를 계산하지 '
  '않는다. cron·내부 전용이라 로그인 가드를 두지 않는다(cron에는 auth.uid()가 없다).';

revoke execute on function public.settle_bot_battle(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- settle_due_bot_battles: t_bot이 지난 봇전을 훑는다 (cron 1분)
-- ---------------------------------------------------------------------------
-- 권한 예외의 이유는 settle_bot_battle과 같다(cron 전용, uid 없음, Edge가 부르지 않음).
--
-- 한 행씩 예외를 흡수한다: 한 대결의 예외가 같은 tick의 다른 대결을 막지 않게 한다
-- (settle_expired_battles 선례). skip locked는 사용자의 제출 트랜잭션이 그 행을 잡고 있을 때
-- 1분짜리 작업이 그것을 기다리지 않게 한다 - 놓친 행은 다음 tick이 집는다.
create function public.settle_due_bot_battles()
returns integer
language plpgsql
security definer set search_path = public
as $$
declare
  v_battle_id uuid;
  v_settled integer := 0;
begin
  for v_battle_id in
    select b.id
    from public.battles b
    where b.is_bot
      and b.status = 'active'
      and exists (
        select 1 from public.battle_submissions s
        where s.battle_id = b.id
          and s.user_id = public.bot_user_id()
          and s.submitted_at <= now()
      )
    order by b.started_at
    for update skip locked
  loop
    begin
      if public.settle_bot_battle(v_battle_id) is distinct from 'active' then
        v_settled := v_settled + 1;
      end if;
    exception when others then
      raise warning '연습 대결 정산 실패 (battle=%): %', v_battle_id, sqlerrm;
    end;
  end loop;

  return v_settled;
end;
$$;

comment on function public.settle_due_bot_battles is
  '봇의 목표 시각이 지난 봇전을 정산한다(사용자가 이미 냈으면 그 자리에서 종결된다). '
  '마감 정산(settle_expired_battles)과 **다른 cron 작업**이라 한쪽의 예외가 다른 쪽을 '
  '되돌리지 않는다. cron 전용이라 로그인 가드를 두지 않는다(cron에는 auth.uid()가 없다).';

revoke execute on function public.settle_due_bot_battles() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- settle_my_bot_battles: 화면이 부르는 깨우기 (앱이 부르는 RPC)
-- ---------------------------------------------------------------------------
-- ** 이것이 "클라이언트가 승패를 정한다"가 아닌 이유 **: 인자가 없고(어느 대결인지도 서버가
-- 고른다), 시각 판단을 전부 now()로 서버가 하며, 호출해도 t_bot 전에는 아무 일도 일어나지
-- 않는다. 클라이언트가 보내는 것은 "지금 다시 봐 달라"는 신호 하나이고, cron이 같은 일을 1분마다
-- 한다. 호출 결과도 결과를 바꾸지 않는다(submitted_at은 이미 과거에 찍힌 값이다).
--
-- 예외를 흡수하는 이유(design은 cron 쪽만 적었다): 앱의 내 대결 목록이 **목록을 읽기 전에**
-- 이 RPC를 부르므로, 한 대결의 예외가 밖으로 나가면 내 대결 탭 전체가 오류 화면이 된다.
-- 정산은 관문이 아니다(cron이 1분 안에 같은 일을 한다). 서버 로그는 raise warning으로 남긴다.
create function public.settle_my_bot_battles()
returns integer
language plpgsql
security definer set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_battle_id uuid;
  v_settled integer := 0;
begin
  if auth.uid() is null then
    raise exception '로그인이 필요합니다.';
  end if;

  for v_battle_id in
    select b.id
    from public.battles b
    where b.is_bot
      and b.status = 'active'
      and b.creator_id = v_user
      and exists (
        select 1 from public.battle_submissions s
        where s.battle_id = b.id
          and s.user_id = public.bot_user_id()
          and s.submitted_at <= now()
      )
    order by b.started_at
    for update skip locked
  loop
    begin
      if public.settle_bot_battle(v_battle_id) is distinct from 'active' then
        v_settled := v_settled + 1;
      end if;
    exception when others then
      raise warning '연습 대결 정산 실패 (battle=%): %', v_battle_id, sqlerrm;
    end;
  end loop;

  return v_settled;
end;
$$;

comment on function public.settle_my_bot_battles is
  '내 봇전 중 봇의 목표 시각이 지난 것을 지금 정산한다(종결된 수를 돌려준다). 인자가 없고 시각 '
  '판단을 전부 서버가 하는 멱등한 깨우기이며, 목표 시각 전에는 아무 일도 일어나지 않는다 - '
  'cron이 같은 일을 1분마다 하고 이 호출은 결과가 아니라 결과를 아는 시점만 당긴다.';

revoke execute on function public.settle_my_bot_battles() from public, anon;
grant execute on function public.settle_my_bot_battles() to authenticated;

-- ---------------------------------------------------------------------------
-- 고치는 기존 함수 1/6 — enqueue_notification: 봇을 수신자로 받지 않는다
-- ---------------------------------------------------------------------------
-- 기준: 20260920120000_push_tokens_and_outbox.sql. 바뀐 것은 첫 가드의 한 조건뿐이다.
--
-- N2(finalize_battle)·N3(accept_submission)·N5(delete_account)가 봇을 수신자로 부른다.
-- notification_outbox.recipient_id가 profiles를 가리키므로 FK로는 걸리지 않고 조용히 쌓인다.
-- 한 곳에서 막으면 호출자를 하나도 고칠 필요가 없고 원장에 쓰레기가 남지 않는다(design §7-3).
create or replace function public.enqueue_notification(
  p_recipient_id uuid,
  p_kind text,
  p_battle_id uuid,
  p_dedup_key text,
  p_payload jsonb
)
returns void
language plpgsql
security invoker
set search_path = public
as $$
begin
  -- 받을 사람이나 대결이 없으면 알릴 것이 없다(예: 상대가 없는 pending 모집). 조용히 지나간다.
  -- 연습 봇도 알릴 사람이 아니다 - 봇은 기기도 알림함도 없고, 봇 수신 행이 쌓이면 발송기가
  -- 매 tick 그것을 집어 토큰 없음으로 버리게 된다.
  if p_recipient_id is null or p_battle_id is null
     or p_recipient_id = public.bot_user_id() then
    return;
  end if;

  begin
    insert into public.notification_outbox (recipient_id, kind, battle_id, dedup_key, payload)
    values (p_recipient_id, p_kind, p_battle_id, p_dedup_key, coalesce(p_payload, '{}'::jsonb))
    on conflict (recipient_id, dedup_key) do nothing;
  exception when others then
    -- 판정을 되돌리지 않는다. 운영자가 보는 로그만 남긴다.
    raise warning '알림 적재 실패 (kind=%, battle=%): %', p_kind, p_battle_id, sqlerrm;
  end;
end;
$$;

comment on function public.enqueue_notification is
  '알림 원장에 한 행을 넣는다(중복은 무시). 수신자가 없거나 연습 봇이면 조용히 지나간다. '
  '내부 전용. 실패해도 예외를 올리지 않고 warning만 남긴다 - 알림이 판정 트랜잭션을 되돌리지 '
  '못하게 하는 장치다.';

-- ---------------------------------------------------------------------------
-- 고치는 기존 함수 2/6 — open_judging_window: 봇전은 창이 열리는 순간 끝난다
-- ---------------------------------------------------------------------------
-- 기준: 20261103120000_notification_events.sql. 사람 대결 경로(N4' 적재 두 줄)는 그대로 두고
-- 그 **앞에** 봇전 분기를 더했다.
--
-- 창을 여는 세 경로(accept_submission의 양쪽 제출, settle_bot_battle의 t_bot 경과,
-- settle_expired_battles의 마감)가 전부 이 함수를 지나므로, "판정 창이 열린다 = 봇전이 끝난다"가
-- **한 함수 안의 사실**이 되고 세 경로가 그 효과를 그대로 얻는다.
--
-- 왜 자동 승인인가: 봇은 판정하지 않고, 사용자에게는 판정할 증거가 없다(봇은 사진을 내지 않는다).
-- 그러면 "미판정은 승인으로 간주한다"는 **이미 확정된 도메인 규칙**이 그대로 적용된다 - 새 규칙을
-- 만드는 것이 아니다. 점수 규칙도 이미 "자동 승인으로 인정된 완료도 감면을 받는다"고 적혀 있다.
-- 새 verdict_source 값도 만들지 않는다(auto를 봇전에서 문구만 달리 읽는다).
create or replace function public.open_judging_window(p_battle_id uuid)
returns void
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_battle public.battles%rowtype;
  v_creator_submitted boolean;
  v_opponent_submitted boolean;
  v_payload jsonb;
begin
  update public.battles
  set status = 'judging',
      judging_opened_at = now(),
      judge_deadline_at = now() + interval '24 hours'
  where id = p_battle_id
  returning * into v_battle;

  if v_battle.id is null or v_battle.opponent_id is null then
    return;
  end if;

  select exists (
    select 1 from public.battle_submissions
    where battle_id = p_battle_id and user_id = v_battle.creator_id
  ) into v_creator_submitted;

  select exists (
    select 1 from public.battle_submissions
    where battle_id = p_battle_id and user_id = v_battle.opponent_id
  ) into v_opponent_submitted;

  -- ** 봇전: 기다릴 판정이 없으므로 24시간 기한을 쓰지 않고 그 자리에서 끝낸다. **
  -- creator = 사용자, opponent = 봇으로 고정이다(battles_bot_opponent_check가 보장).
  -- 여기서 exists로 센 v_opponent_submitted는 봇전에서 언제나 true다 - 봇 제출 행은 시작부터
  -- 있고, 봇전에서 이 함수가 불리는 시점은 언제나 t_bot 이후이기 때문이다(design §1.5).
  if v_battle.is_bot then
    -- (1) 사용자가 봇의 제출을 자동 승인한다. 판정할 증거가 없으므로 묻지 않는다.
    --     on conflict do nothing이라 안전망(close_expired_judging_windows)이 같은 행을 다시
    --     넣으려 해도 조용히 지나간다.
    insert into public.battle_judgments (battle_id, judge_id, min_verdict, superior_id, auto)
    values (p_battle_id, v_battle.creator_id, 'approve', null, true)
    on conflict (battle_id, judge_id) do nothing;

    update public.battle_participants
    set has_judged = true
    where battle_id = p_battle_id and user_id = v_battle.creator_id;

    -- (2) 봇이 사용자의 제출을 자동 승인한다. 사용자가 내지 않았으면 판정할 것이 없어 행을
    --     만들지 않는다(close_expired_judging_windows가 "필요한 판정만" 채우는 것과 같은 규칙).
    if v_creator_submitted then
      insert into public.battle_judgments (battle_id, judge_id, min_verdict, superior_id, auto)
      values (p_battle_id, v_battle.opponent_id, 'approve', null, true)
      on conflict (battle_id, judge_id) do nothing;

      update public.battle_participants
      set has_judged = true
      where battle_id = p_battle_id and user_id = v_battle.opponent_id;
    end if;

    -- (3) 봇의 has_submitted는 **지금** 참이 된다. 제출 행은 시작부터 있지만 이 컬럼은 상대가
    --     읽는 요약이라(battle_participants의 불변식) t_bot 전에 true가 되면 "봇이 제출했어요"가
    --     보여 공개 범위가 깨진다. 즉 봇전에서 이 컬럼의 뜻은 "제출 행이 있는가"가 아니라
    --     "그 제출이 공개됐는가"다.
    update public.battle_participants
    set has_submitted = true
    where battle_id = p_battle_id and user_id = v_battle.opponent_id;

    -- (4) 있는 제출 행들의 최소 기준 결론. 결과 화면이 "누가 인정했는지"를 말할 수 있게 한다.
    update public.battle_submissions
    set meets_criteria = true, verdict_source = 'auto'
    where battle_id = p_battle_id and meets_criteria is null;

    -- (5) 같은 트랜잭션에서 종결한다. 결론은 기존 mutual_speed_outcome이 두 submitted_at을
    --     비교해 낸다 - 이 함수는 승패를 계산하지 않는다.
    perform public.resolve_battle(p_battle_id);

    -- N4'(판정할 차례)를 보내지 않는다. 사용자가 판정할 것이 없다(design §7-4).
    return;
  end if;

  -- 상대의 제출 시각·사진·판정 내용은 담지 않는다. "판정할 것이 있다"와 기한만 담는다.
  v_payload := jsonb_build_object(
    'title', v_battle.title,
    'battle_type', v_battle.type,
    'judge_deadline_at', v_battle.judge_deadline_at
  );

  -- 생성자는 상대가 냈을 때, 상대는 생성자가 냈을 때 판정할 것이 생긴다.
  if v_opponent_submitted then
    perform public.enqueue_notification(
      v_battle.creator_id, 'judge_turn', p_battle_id,
      'judge:' || p_battle_id::text, v_payload
    );
  end if;

  if v_creator_submitted then
    perform public.enqueue_notification(
      v_battle.opponent_id, 'judge_turn', p_battle_id,
      'judge:' || p_battle_id::text, v_payload
    );
  end if;
end;
$$;

comment on function public.open_judging_window is
  '판정 창을 연다(서버 시각 + 24시간 고정). accept_submission·settle_expired_battles·'
  'settle_bot_battle만 부른다. 사람 대결은 판정할 증거가 있는 참가자에게 "판정할 차례" 알림을 '
  '적재한다. ** 봇전은 그 자리에서 자동 승인 두 행을 채우고 resolve_battle로 종결한다 ** - '
  '판정 기한 24시간이 한 번도 걸리지 않고 N4'' 알림도 보내지 않는다. 내부 전용.';

-- ---------------------------------------------------------------------------
-- 고치는 기존 함수 3/6 — accept_submission: 동의 건너뛰기 + t_bot 기준 잠금
-- ---------------------------------------------------------------------------
-- 기준: 20261103120000_notification_events.sql.
-- ** 인자 시그니처를 유지한다 ** - 배포된 submit-evidence Edge Function이 이 시그니처로 부르므로
-- 바꾸면 옛 오버로드를 계속 부르게 된다. 유지하므로 재배포도 필요 없다.
--
-- 바뀐 것 네 가지(사용자 쪽 증거 규칙은 한 글자도 바뀌지 않는다 - 앱 카메라 전용, 경로 위조 차단,
-- 시작 전 촬영 거부, 10분 차이 거부가 전부 그대로다):
--   ① 봇전이면 동의 검사를 건너뛴다. 봇전에서 Google로 나가는 것이 하나도 없다(design §8).
--   ② 봇전에서 "상대가 제출했는가"를 exists가 아니라 **봇 행의 submitted_at <= now()**로 본다.
--      t_bot 전에는 false이므로 게이트가 wait이고 교체가 열려 있다(오너 결정 6).
--   ③ 봇전에서 그 값이 true인데 내 행이 있으면 SUBMISSION_LOCKED(교체 잠김).
--      사람 대결은 status가 active인 동안 상대가 내지 않았다는 불변식이 성립해 이 자리에
--      도달하지 않지만, 봇전은 봇 제출 행이 시작부터 있어 그 불변식이 없다.
--   ④ 반환 battle_status를 'judging' 하드코딩에서 **창을 연 뒤 다시 읽은 실제 상태**로 바꿨다.
--      봇전은 같은 트랜잭션에서 'finished'가 되므로, 그러지 않으면 끝난 대결에 judging을
--      돌려준다. 사람 대결은 여전히 'judging'이 읽힌다(값이 같다).
create or replace function public.accept_submission(
  p_user_id uuid,
  p_battle_id uuid,
  p_object_path text,
  p_captured_at timestamptz
)
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_battle public.battles%rowtype;
  v_now timestamptz := now();
  v_opponent_id uuid;
  v_my_submission public.battle_submissions%rowtype;
  v_opponent_submitted boolean;
  v_submission public.battle_submissions%rowtype;
  v_replaced_path text;
  v_gate text;
  v_judging_opened boolean := false;
  v_final_status text;
begin
  if p_user_id is null then
    raise exception '사용자가 필요합니다.';
  end if;

  if p_object_path is null or length(btrim(p_object_path)) = 0 then
    raise exception '사진 경로가 필요합니다.';
  end if;

  if p_captured_at is null then
    raise exception '촬영 시각이 필요합니다.';
  end if;

  select * into v_battle from public.battles where id = p_battle_id for update;

  if v_battle is null then
    raise exception '대결을 찾을 수 없습니다.';
  end if;

  if p_user_id is distinct from v_battle.creator_id
     and p_user_id is distinct from v_battle.opponent_id then
    raise exception '이 대결의 참가자가 아닙니다.';
  end if;

  -- 참가할 때 확인했지만 그 사이 철회했을 수 있다. 동의 없이 사진이 AI로 나가면 안 된다.
  -- 봇전은 사진이 아무 데도(AI에도) 나가지 않으므로 이 관문이 지킬 것이 없다. 동의 게이트 네
  -- 곳 중 여기 하나만 가른다 - begin_criteria_call·create_battle·join_battle은 그대로다.
  if not v_battle.is_bot then
    perform 1 from public.ai_consents where user_id = p_user_id;
    if not found then
      raise exception using message = 'AI 데이터 제공 동의가 필요합니다.', hint = 'CONSENT_REQUIRED';
    end if;
  end if;

  -- 판정 창이 열렸거나 종결됐으면 더 낼 수 없다. 마감만 지난 경우는 아래에서 따로 구분해 알린다.
  if v_battle.status <> 'active' then
    raise exception using message = '제출할 수 있는 상태가 아닙니다.', hint = 'SUBMISSION_LOCKED';
  end if;

  if v_battle.deadline_at is null or v_battle.deadline_at <= v_now then
    raise exception using message = '마감이 지났습니다.', hint = 'DEADLINE_PASSED';
  end if;

  -- 경로 위조 차단. Storage 정책과 같은 규칙을 서버에서 한 번 더 본다.
  if p_object_path not like (p_battle_id::text || '/' || p_user_id::text || '/%') then
    raise exception '사진 경로가 올바르지 않습니다.';
  end if;

  -- 대결이 시작되기 전에 찍어 둔 사진은 이 대결의 증거가 아니다.
  if v_battle.started_at is not null and p_captured_at < v_battle.started_at then
    raise exception using message = '대결 시작 전에 찍은 사진입니다.', hint = 'CAPTURED_BEFORE_START';
  end if;

  -- 촬영과 수신이 10분 이상 벌어지면 거부한다. 기기 시계가 앞선 경우도 같으므로 절댓값으로 본다.
  if abs(extract(epoch from (v_now - p_captured_at))) >= 600 then
    raise exception using message = '촬영 시각과 수신 시각이 너무 벌어졌습니다.', hint = 'CAPTURE_TIME_MISMATCH';
  end if;

  v_opponent_id := case
    when p_user_id = v_battle.creator_id then v_battle.opponent_id
    else v_battle.creator_id
  end;

  select * into v_my_submission from public.battle_submissions
  where battle_id = p_battle_id and user_id = p_user_id
  for update;

  if v_battle.is_bot then
    -- ** 봇전의 "상대가 제출했는가"는 행의 존재가 아니라 그 제출이 일어났는지다. **
    -- 봇 제출 행은 시작부터 있고 submitted_at이 t_bot이므로, 그 시각이 되기 전에는 아직
    -- 일어나지 않은 일이다. 이 한 줄이 "t_bot 전에는 교체할 수 있다"의 전부다(오너 결정 6).
    select exists (
      select 1 from public.battle_submissions
      where battle_id = p_battle_id and user_id = v_opponent_id and submitted_at <= v_now
    ) into v_opponent_submitted;
  else
    select exists (
      select 1 from public.battle_submissions where battle_id = p_battle_id and user_id = v_opponent_id
    ) into v_opponent_submitted;
  end if;

  if v_my_submission.id is not null then
    -- 이미 냈다. 사람 대결은 status가 여전히 active이므로 상대는 아직 내지 않았다(위 불변식).
    if v_battle.type <> 'speed' then
      raise exception using message = '이미 제출했습니다.', hint = 'SUBMISSION_LOCKED';
    end if;

    -- 봇전에는 그 불변식이 없다. t_bot이 지나면 status가 아직 active여도 교체는 닫혀 있다.
    -- (아직 한 장도 내지 않았다면 아래 insert 경로로 마감까지 **처음** 제출할 수 있다 -
    --  교체 잠김과 첫 제출 금지는 다르다.)
    if v_battle.is_bot and v_opponent_submitted then
      raise exception using message = '상대가 제출해 사진을 바꿀 수 없습니다.', hint = 'SUBMISSION_LOCKED';
    end if;

    v_replaced_path := v_my_submission.object_path;

    update public.battle_submissions
    set object_path = p_object_path,
        captured_at = p_captured_at,
        submitted_at = v_now,
        meets_criteria = null,
        verdict_source = null,
        reason = null,
        ai_model = null
    where id = v_my_submission.id
    returning * into v_submission;
  else
    insert into public.battle_submissions (battle_id, user_id, object_path, captured_at, submitted_at)
    values (p_battle_id, p_user_id, p_object_path, p_captured_at, v_now)
    returning * into v_submission;

    update public.battle_participants
    set has_submitted = true
    where battle_id = p_battle_id and user_id = p_user_id;
  end if;

  v_gate := public.judging_gate(v_battle.type, true, v_opponent_submitted, false);

  if v_gate = 'open' then
    perform public.open_judging_window(p_battle_id);
    v_judging_opened := true;
  else
    -- N3. 상대에게 "냈다"는 사실 하나만. 사진 경로도, 제출 시각도, 몇 번 교체했는지도 담지 않는다
    -- (마감 전에 상대에게 보이는 것은 제출 사실뿐이라는 도메인 규칙 그대로다).
    -- 봇전에서는 수신자가 봇뿐이라 enqueue_notification의 가드가 조용히 막는다("봇이 냈어요"는
    -- 사실상 "너 졌어"라서 보내지 않는 것이 맞다 - design §9의 N3).
    perform public.enqueue_notification(
      v_opponent_id,
      'submitted',
      p_battle_id,
      'sub:' || p_battle_id::text,
      jsonb_build_object('title', v_battle.title, 'battle_type', v_battle.type)
    );
  end if;

  -- 창을 열었으면 실제 상태를 다시 읽는다. 사람 대결은 'judging'이고 **봇전은 같은
  -- 트랜잭션에서 이미 'finished'다**(open_judging_window가 종결까지 한다).
  if v_judging_opened then
    select status into v_final_status from public.battles where id = p_battle_id;
  else
    v_final_status := v_battle.status;
  end if;

  return jsonb_build_object(
    'submission_id', v_submission.id,
    'replaced_object_path', v_replaced_path,
    'judging_opened', v_judging_opened,
    'battle_status', v_final_status
  );
end;
$$;

comment on function public.accept_submission is
  '증거 사진 제출(서버 전용). status=active인 동안 내 행이 있으면 교체(속도전만, 상대가 아직 '
  '제출하지 않은 동안)로 덮어쓰고, 없으면 새로 만든다. 양쪽이 모두 내면 같은 트랜잭션에서 판정 '
  '창을 연다. 창이 열리지 않는 제출은 상대에게 제출 알림을 적재한다. 봇전은 동의 검사를 '
  '건너뛰고(나가는 데이터가 없다) "상대 제출"을 봇의 목표 시각 경과로 판단하며, 창이 열리면 '
  '그 자리에서 종결되어 battle_status에 finished가 담긴다. 시그니처 유지(배포된 '
  'submit-evidence가 이 시그니처로 부른다).';

-- ---------------------------------------------------------------------------
-- 고치는 기존 함수 4/6 — finalize_battle: 점수는 섞고 전적은 가른다
-- ---------------------------------------------------------------------------
-- 기준: 20261103120000_notification_events.sql. 상태·승자·모양 검사·N2 적재 조건은 그대로다.
--
-- 봇전에서 바뀌는 것 네 가지:
--   - 점수 delta를 bot_outcome_score_delta로 구한다(승 +1, 그 밖 -1). 하한 0은 그대로.
--   - 승/패/무 카운터를 **건드리지 않는다.** 모집 목록의 생성자 전적과 대결 화면의 상대 전적은
--     "내가 붙을 상대를 가늠하는 수단"인데, 봇전 승수가 거기 섞이면 그 숫자가 쓸모없어진다.
--     그래서 player_stats에 칸을 더하지도, 별도 집계 테이블을 만들지도 않고 이 세 줄만 가른다.
--   - 봇 참가자는 점수·카운터·player_stats 행을 전부 건너뛰고 outcome만 기록한다. 봇에게는
--     점수 개념이 없으므로 score_delta_applied에 0을 적어 "변화 없음"이라고 말하지 않고 null로
--     둔다(행이 스스로를 설명하게).
--   - N2 payload에 is_bot을 담는다. 서버 문구(notification_text.ts)가 completed_loss의 감면
--     꼬리("기준을 통과해서 감점이 줄었어요")를 봇전에서 붙이지 않게 하기 위함이다 - 봇전은
--     완료한 패배와 미착수가 둘 다 -1이라 줄어든 것이 없어 그 문장이 거짓이 된다.
create or replace function public.finalize_battle(
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
    -- 연습 봇에게는 점수·전적 개념이 없다. outcome만 적고(행이 스스로를 설명하게) 점수 행 생성·
    -- 점수 갱신·카운터·알림을 모두 건너뛴다. score_delta_applied는 null로 남는다.
    if v_battle.is_bot and v_participant.user_id = public.bot_user_id() then
      update public.battle_participants
      set outcome = v_participant.outcome
      where battle_id = p_battle_id and user_id = v_participant.user_id;
      continue;
    end if;

    -- 봇전은 전용 점수표를 쓴다. 사람 대결의 표(outcome_score_delta)는 한 줄도 바뀌지 않는다.
    v_delta := case
      when v_battle.is_bot then public.bot_outcome_score_delta(v_participant.outcome)
      else public.outcome_score_delta(v_participant.outcome)
    end;

    -- 가입 트리거·백필로 행이 있어야 하지만, 없으면 0점에서 시작한다.
    insert into public.player_stats (user_id)
    values (v_participant.user_id)
    on conflict (user_id) do nothing;

    select score into v_old_score
    from public.player_stats
    where user_id = v_participant.user_id
    for update;

    v_new_score := greatest(v_old_score + v_delta, 0);

    -- 점수는 섞고 전적은 가른다: 봇전은 승/패/무 카운터를 건드리지 않는다.
    update public.player_stats
    set score = v_new_score,
        wins = wins + case when not v_battle.is_bot and v_participant.outcome = 'win' then 1 else 0 end,
        losses = losses + case when not v_battle.is_bot and v_participant.outcome in ('completed_loss', 'loss', 'forfeit') then 1 else 0 end,
        draws = draws + case when not v_battle.is_bot and v_participant.outcome = 'draw' then 1 else 0 end
    where user_id = v_participant.user_id;

    update public.battle_participants
    set outcome = v_participant.outcome,
        score_delta_applied = v_new_score - v_old_score
    where battle_id = p_battle_id and user_id = v_participant.user_id;

    -- N2. 포기한 본인에게는 보내지 않는다 - 내 행동의 결과라 알릴 것이 없다.
    -- forfeited_by는 forfeit_battle이 이 함수를 부르기 전에 기록하므로 위 select가 이미 본다.
    -- 점수는 '이번 변화'(하한 0에 걸리면 0)만 담는다. 누적 점수·승패 카운터는 담지 않는다(spec).
    -- is_bot은 서버 문구가 감면 꼬리를 가릴 때 쓴다(봇전은 완료한 패배와 미착수가 둘 다 -1이다).
    if v_battle.forfeited_by is distinct from v_participant.user_id then
      perform public.enqueue_notification(
        v_participant.user_id,
        'finished',
        p_battle_id,
        'finished:' || p_battle_id::text,
        jsonb_build_object(
          'title', v_battle.title,
          'battle_type', v_battle.type,
          'outcome', v_participant.outcome,
          'score_delta', v_new_score - v_old_score,
          'is_bot', v_battle.is_bot
        )
      );
    end if;
  end loop;
end;
$$;

comment on function public.finalize_battle is
  '승패가 있는 종결의 유일한 적용 지점(상태·승자·outcome·점수 하한 0·카운터). 양쪽에 종결 알림을 '
  '적재한다(포기한 본인 제외). 봇전은 전용 점수표(bot_outcome_score_delta)를 쓰고 승/패/무 '
  '카운터를 건드리지 않으며, 봇 참가자에게는 outcome만 적고 점수 행을 만들지 않는다. 내부 전용.';

-- ---------------------------------------------------------------------------
-- 고치는 기존 함수 5/6 — get_player_card: 봇의 전적은 내주지 않는다
-- ---------------------------------------------------------------------------
-- 기준: 20260917120000_join_and_player_cards.sql. 더한 것은 거부 한 블록뿐이다.
--
-- 왜 필요한가: 봇은 "내 대결 상대"라서 기존 공개 조건의 첫 exists를 **통과한다.** 거부하지
-- 않으면 봇의 누적 전적(모든 사용자의 봇전이 쌓인 숫자)이 상대 카드에 뜬다. 지금은
-- player_stats 행이 없어 숫자가 전부 null로 나가지만, 그 null을 화면이 "0승 0패"로 그리면
-- 그것도 봇을 사람처럼 보이게 하는 것이다. 화면은 애초에 이 함수를 부르지 않는다(design §10.4) -
-- 서버에서도 막아 두 겹으로 둔다.
create or replace function public.get_player_card(p_user_id uuid)
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_profile public.profiles%rowtype;
  v_stats public.player_stats%rowtype;
begin
  if v_user is null then
    raise exception '로그인이 필요합니다.';
  end if;

  if p_user_id is null then
    raise exception '사용자가 필요합니다.';
  end if;

  -- 연습 봇은 전적을 집계하지도 보여 주지도 않는다. 봇 자리에는 "연습 상대"라는 사실만 보인다.
  if p_user_id = public.bot_user_id() then
    raise exception using message = '연습 봇은 전적이 없습니다.', hint = 'BOT_NO_STATS';
  end if;

  if p_user_id <> v_user
     and not exists (
       select 1 from public.battles b
       where (b.creator_id = v_user and b.opponent_id = p_user_id)
          or (b.opponent_id = v_user and b.creator_id = p_user_id)
     )
     and not exists (
       select 1 from public.battles b
       where b.creator_id = p_user_id and b.status = 'pending'
     ) then
    raise exception '이 사용자의 전적을 볼 수 없습니다.';
  end if;

  select * into v_profile from public.profiles where id = p_user_id;
  if not found then
    raise exception '사용자를 찾을 수 없습니다.';
  end if;

  -- 탈퇴한 사용자는 player_stats 행이 없다. 점수 자리는 null로 나간다.
  select * into v_stats from public.player_stats where user_id = p_user_id;

  return jsonb_build_object(
    'user_id', v_profile.id,
    'display_name', v_profile.display_name,
    'deleted', v_profile.deleted_at is not null,
    'score', v_stats.score,
    'wins', v_stats.wins,
    'losses', v_stats.losses,
    'draws', v_stats.draws
  );
end;
$$;

comment on function public.get_player_card is
  '상대·생성자 전적 카드. 공개 범위는 본인 + 나와 같은 대결의 상대 + 모집 중 대결의 생성자뿐이다. '
  '연습 봇은 그 조건을 통과하지만 전적 개념이 없으므로 BOT_NO_STATS로 거부한다.';

-- ---------------------------------------------------------------------------
-- 고치는 기존 함수 6/6 — 동의 철회가 봇전을 건드리지 않는다
-- ---------------------------------------------------------------------------
-- 기준: 20260916120000_ai_consent.sql. 두 함수의 진행 중 대결 조회에 and not is_bot 한 조건씩.
--
-- 근거: 봇전은 동의를 근거로 성립한 대결이 아니다(동의 없이도 시작할 수 있다). 그래서 철회로
-- 포기 처리되지 않고, 확인 문구의 개수도 봇전을 세지 않는다. 진행 중인 사람 대결에 대한
-- 처리(포기 -3, 모집 취소)는 한 줄도 바뀌지 않는다.
--
-- pending 조회에는 조건을 더하지 않았다: battles_bot_opponent_check(is_bot = 상대가 봇)와
-- battles_bot_topic_pair_check가 함께 **status='pending'인 봇전 행을 구조적으로 불가능하게**
-- 만든다(모집 행은 opponent_id가 null이다). 제약이 이미 증명하는 것에 중복 필터를 넣지 않는다.
create or replace function public.get_consent_withdrawal_impact()
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
    and not is_bot
    and (creator_id = v_user or opponent_id = v_user);

  select count(*) into v_pending
  from public.battles
  where status = 'pending' and creator_id = v_user;

  return jsonb_build_object('active_count', v_active, 'pending_count', v_pending);
end;
$$;

comment on function public.get_consent_withdrawal_impact is
  '철회하면 어떤 대결이 어떻게 처리되는지 미리 보여 준다. 진행 중 개수에 봇전을 세지 않는다 - '
  '봇전은 철회로 포기되지 않는다.';

create or replace function public.withdraw_ai_consent()
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
  -- (봇전은 pending을 거치지 않으므로 이 update에 걸릴 봇전 행이 존재할 수 없다 - 위 주석.)
  with cancelled as (
    update public.battles
    set status = 'cancelled', finished_at = now()
    where status = 'pending' and creator_id = v_user
    returning id
  )
  select count(*) into v_cancelled from cancelled;

  -- ** 봇전은 건드리지 않는다 ** (and not is_bot). 진행 중인 연습 대결은 그대로 이어진다.
  for v_battle in
    select * from public.battles
    where status in ('active', 'judging')
      and not is_bot
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

comment on function public.withdraw_ai_consent is
  '동의 철회. 진행 중인 사람 대결은 모두 내 포기로, 모집 중인 대결은 취소로 끝낸다. '
  '봇전은 동의를 근거로 성립한 대결이 아니므로 철회가 건드리지 않는다.';


-- ---------------------------------------------------------------------------
-- 고치는 기존 함수 7/7 — forfeit_battle: 봇전은 포기 전에 먼저 정산한다
-- ---------------------------------------------------------------------------
-- 기준: 20261029120000_ai_rejudgment.sql. 시그니처 유지(create or replace)이므로
-- GRANT(authenticated)는 그대로 남는다. 사람 대결 경로는 한 글자도 바뀌지 않았다.
--
-- ** 왜 필요한가 (reviewer W1, 2026-11-22). ** 봇전에는 "t_bot은 지났는데 아직 정산되지 않은"
-- 어긋남 구간이 있다(cron 1분 + 화면의 깨우기). 그 구간에서 status는 아직 'active'이고 포기
-- 버튼이 살아 있다. 그런데 ** 그 구간에 들어올 수 있는 봇전은 사용자가 t_bot 전에 제출한 판뿐이다 **
-- (t_bot 뒤의 첫 제출은 그 트랜잭션에서 바로 종결된다). 즉 그 구간의 결과는 ** 언제나 승리 ** 이고,
-- 포기가 먼저 커밋되면 그 승리(+1)가 포기 패배(-1)로 뒤집히며 전적 라벨도 승 -> 패로 바뀐다.
-- design §1.6은 이 경우를 "봇전은 손해가 다 -1이라 어느 쪽이든 같다"로 넘겼는데, 비교 대상이
-- -1 대 -1이 아니라 ** +1 대 -1 ** 이어서 그 근거가 성립하지 않는다.
--
-- 고치는 방법: 행을 잠근 뒤 ** 먼저 정산하고 상태를 다시 읽는다. ** 같은 트랜잭션·같은 잠금이라
-- 그 사이에 끼어들 수 없다(앱에서 포기 직전에 깨우는 방식은 두 호출 사이에 cron이 들어온다).
-- 정산으로 끝난 대결에는 전용 힌트(BOT_ALREADY_SETTLED)를 준다 - 아래 공용 상태 검사에 맡기면
-- "포기할 수 있는 상태가 아닙니다"만 보여 사용자가 자기가 이겼다는 것을 모른다.
--
-- ** 거부가 정산까지 되돌린다 — 그것이 맞다. ** 예외가 함수 밖으로 나가면 같은 트랜잭션에서
-- 방금 한 정산도 함께 롤백된다. 즉 거부 직후 대결은 아직 'active'이고, 결과는 cron이 1분 안에
-- 쓴다. 중요한 것은 "포기가 커밋되지 않는다"이고 그것은 지켜진다 - 확정된 승리가 포기 패배로
-- 뒤집히는 일이 없다. 반대로 예외 없이 조용히 정산만 하고 돌아오면 앱이 "포기했습니다"를
-- 띄워 거짓을 말하게 된다(이 함수는 returns void라 "포기하지 않았다"를 돌려줄 길이 없다).
-- 그래서 앱 문구도 "이미 결과가 나왔다"가 아니라 "곧 결과가 나온다"로 적는다.
--
-- settle_bot_battle은 멱등이고 t_bot 전에는 아무 일도 하지 않으므로, 어긋남 구간이 아니면 이
-- 분기는 상태를 바꾸지 않고 그대로 포기로 내려간다(t_bot 전 포기·미제출 포기는 그대로 -1이다).
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

  -- ** 봇전만: 이미 확정된 결과를 포기로 덮어쓰지 않는다(위 머리 주석). **
  if v_battle.is_bot then
    perform public.settle_bot_battle(p_battle_id);
    select * into v_battle from public.battles where id = p_battle_id for update;

    if v_battle.status not in ('active', 'judging') then
      raise exception using
        message = '이미 결과가 나왔습니다.', hint = 'BOT_ALREADY_SETTLED';
    end if;
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

  -- 진행 중이던 AI 재판정은 여기서 끝난다. 늦게 도착한 판정은 claim/record가 종결 상태를 보고 버린다.
  delete from public.ai_judgment_jobs where battle_id = p_battle_id;

  perform public.finalize_battle(
    p_battle_id,
    'finished',
    v_opponent,
    case when auth.uid() = v_battle.creator_id then 'forfeit' else 'win' end,
    case when auth.uid() = v_battle.creator_id then 'win' else 'forfeit' end
  );
end;
$$;

comment on function public.forfeit_battle is
  '포기(기권). 포기한 쪽이 지고 상대가 승자로 기록되며 finished로 끝난다. ** 봇전은 포기 전에 '
  'settle_bot_battle로 먼저 정산해, 봇의 목표 시각이 이미 지난 판(결과가 확정된 판)을 포기로 '
  '덮어쓰지 않는다 ** - 그 경우 BOT_ALREADY_SETTLED로 거부한다. 사람 대결 경로는 그대로다.';
-- ---------------------------------------------------------------------------
-- cron: settle-bot-battles (1분)
-- ---------------------------------------------------------------------------
-- 다섯 번째 작업을 따로 두는 이유는 mutual-judge가 셋을 쪼갠 것과 같다 - 한 작업의 명령 문자열은
-- 한 트랜잭션이라, 봇전 정산에서 예외가 나면 같은 tick의 마감 정산까지 되돌아간다.
-- 비용은 1분에 한 번 작은 조건부 인덱스 스캔이다(활성 봇전은 사용자당 최대 3행).
--
-- 1분인 이유: 봇의 목표 시각이 지난 뒤 결과가 기록되기까지의 어긋남 구간을 60초 안으로 묶는다.
-- 클라이언트는 t_bot을 모르므로(그게 규칙이다) "그 시각에 한 번"이 불가능하고, 화면이 부르는
-- settle_my_bot_battles가 그 구간을 더 당긴다.
--
-- 같은 이름으로 cron.schedule을 다시 부르면 기존 작업이 **갱신**된다(중복 등록이 아니다).
select cron.schedule(
  'settle-bot-battles',
  '* * * * *',
  $$select public.settle_due_bot_battles();$$
);
