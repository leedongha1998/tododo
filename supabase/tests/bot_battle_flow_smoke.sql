-- 봇전 전체 흐름 스모크 테스트 (bot-battle 2단계).
--
-- 로컬에 Docker가 없어 원격 DB에 직접 돌린다:
--   supabase db query --linked -f supabase/tests/bot_battle_flow_smoke.sql
--
-- Gemini는 한 번도 부르지 않는다(부를 자리가 없다 - 그것이 이 기능의 합격선이다).
-- 마지막에 일부러 예외를 던져 트랜잭션 전체를 롤백하므로 실제 데이터는 남지 않는다. 결과:
--   SMOKE RESULT ok=true                    -> 통과
--   SMOKE RESULT ok=false FAILURES: ...     -> 어긋난 항목(기대값/실제값)
--
-- ** 같은 트랜잭션에서는 now()가 고정이다. ** 그래서 "시간이 흘렀다"는 것은 행의 시각을 과거로
-- 미는 방식으로 흉내 낸다(봇의 submitted_at을 당겨 t_bot 경과를, 사용자의 submitted_at을 더
-- 당겨 "봇보다 먼저 냈다"를). pg_sleep으로는 차이가 생기지 않는다. 그래서 "교체하면 제출 시각이
-- 갱신된다"도 **일부러 과거로 민 값이 now()로 되돌아오는지**로 본다.
--
-- settle_due_bot_battles()·settle_expired_battles()·close_expired_judging_windows()는 전역을
-- 훑으므로 반환값은 '1 이상'으로만 본다(원격에 다른 사용자의 밀린 대결이 있으면 더 클 수 있다).
-- 바뀐 행은 롤백된다.
--
-- ** 예외를 잡는 블록은 그 안의 DB 변경을 되돌린다. ** PL/pgSQL의 begin … exception 블록은
-- 서브트랜잭션이라, "거부되는지"를 보려고 감싼 호출이 **거부되기 전에 한 일까지** 함께 사라진다.
-- 그래서 섹션 3은 두 사실을 **두 단계로 나눠** 본다 - 포기가 거부되는 것(forfeit_refused)과,
-- 그 판이 포기 패배가 아니라 승리로 끝나는 것(forfeit_shape·forfeit_outcome). forfeit_battle이
-- 거부 전에 돌린 정산이 예외와 함께 되돌아가므로, 블록을 빠져나온 뒤 settle_bot_battle을 한 번
-- 더 불러 같은 상태를 다시 만든 다음 모양을 읽는다(그 둘은 같은 입력에 같은 결과를 낸다 -
-- submitted_at은 이미 과거에 찍힌 값이고 정산은 그 값을 만지지 않는다).
--
-- 확인하는 것 (design.md §14 "bot_battle_flow_smoke.sql 필수 확인" 1~15과 1:1 + 리뷰 지적 W1·W3)
--   start_*        시작 1판의 모양: active·speed·마감·기준 복사·참가자 2행·사진 없는 봇 제출 행
--   tbot_*         t_bot이 기간의 50~85%, 마감보다 앞, 사용자에게 보이지 않음
--   limit_*        하루 3회, 4번째 거부, KST 경계로 초기화, 종결 뒤에도 돌아오지 않음
--                  (포기해도 돌아오지 않는다는 검사는 forfeit_idle_limit_used에 있다)
--   replace_*      t_bot 전 교체 가능 + 제출 시각 갱신 / t_bot 뒤 SUBMISSION_LOCKED
--   win_*          봇보다 먼저 냄 -> 승리 +1, 전적 카운터는 그대로, 봇 점수 행 없음
--   cl_*           t_bot 뒤 첫 제출 -> **그 트랜잭션에서** 종결, 완료한 패배 -1
--   loss_*         미제출 + 마감 -> 완료 못 한 패배 -1, 봇의 판정 행은 만들지 않는다
--   forfeit_*      ** W1 회귀 **: 어긋남 구간(t_bot은 지났고 아직 정산되지 않은 구간)의 포기는
--                  BOT_ALREADY_SETTLED로 거부되고, 그 판은 포기 패배(-1)가 아니라 승리(+1)로 끝난다
--   forfeit_idle_* 진짜 포기(t_bot 전): 봇이 승자, 포기 -1, 알림 0행, 그날 횟수는 돌아오지 않는다
--   evidence_*     ** 증거 규칙은 봇전에서도 그대로다 **: 사진 경로·촬영 시각이 없으면 거부되고
--                  CAPTURED_BEFORE_START·CAPTURE_TIME_MISMATCH가 그대로 난다
--   judge_*        ** W3 음성 테스트 **: 봇전에 'reject'가 들어가는 것을 막는 것은 벽 두 겹
--                  (JUDGING_NOT_OPEN·ALREADY_JUDGED)뿐이다 + 벽을 치우면 재판정 잡이 실제로
--                  생긴다는 양성 대조
--   safety_*       안전망: 창이 열린 채 종결에 실패해도 close_expired_judging_windows가 같은
--                  결론(승리 +1)을 낸다(design §3.1 B10 — 한 번도 돌려 본 적이 없었다)
--   idle_*         t_bot 전에는 정산 RPC가 0을 돌려주고 상태를 바꾸지 않는다(오너 결정 6)
--   reveal_*       공개 범위: t_bot 전 1행(내 것만), 종결 후 2행
--   judgment_*     자동 승인 2행(auto/approve), verdict_source='auto'
--   notify_*       finished 하나뿐, 봇 수신 0행, judge_turn·submitted·matched 0행
--   gate_*         ** 합격선 **: 증서·호출 원장·캐시·재판정 잡에 행이 생기지 않는다
--   consent_*      동의 없이 시작·제출·종결 가능 / 사람 대결은 여전히 막힘 / 철회가 봇전을 건드리지 않음
--   delete_*       탈퇴하면 진행 중 봇전이 cancelled, 점수 변동 없음
--   expose_*       get_player_card(봇) 거부, 모집 목록에 봇이 없음
--   perm_*         내부 함수는 anon·authenticated에서 거부, 앱 RPC는 허용, 주제 테이블은 0행
--   human_*        ** 사람 대결 회귀 **: +3 / -1과 전적 카운터 증가가 그대로다
do $$
declare
  v_bot uuid := public.bot_user_id();
  v_a uuid := gen_random_uuid();   -- 동의한 사용자(대부분의 경로)
  v_b uuid := gen_random_uuid();   -- 동의하지 않은 사용자
  v_c uuid := gen_random_uuid();   -- 사람 대결 회귀 - 생성자
  v_d uuid := gen_random_uuid();   -- 사람 대결 회귀 - 참가자
  v_e uuid := gen_random_uuid();   -- 탈퇴 사용자

  v_topic uuid;
  v_dur integer;
  v_topic_min jsonb;
  v_topic_title text;

  v_b_win uuid;    -- 승리
  v_b_cl uuid;     -- 완료한 패배
  v_b_lock uuid;   -- 교체 -> 잠김 -> 포기
  v_b_loss uuid;   -- 완료 못 한 패배
  v_b_idle uuid;   -- t_bot 전에 멈춰 있는 판
  v_b_nc uuid;     -- 동의하지 않은 사용자의 판
  v_b_del uuid;    -- 탈퇴로 취소되는 판
  v_b_judge uuid;  -- W3: 'reject'가 들어갈 수 있는지(벽 두 겹 + 양성 대조)
  v_b_safe uuid;   -- 안전망: close_expired_judging_windows가 같은 결론을 내는지
  v_h uuid;        -- 사람 대결

  v_base_cache integer;
  v_base_jobs integer;
  v_topics jsonb;
  v_accept jsonb;
  v_impact jsonb;
  v_withdraw jsonb;
  v_limits jsonb;
  v_sub_id bigint;
  v_sub_id2 bigint;
  v_ratio_ok boolean := true;
  v_settle_due integer;
  v_settle_exp integer;
  v_settle_idle integer;
  v_settle_perm integer;
  v_closed_judging integer;
  v_judge_gap text;
  v_reveal_before integer := -1;
  v_reveal_after integer := -1;
  v_topics_rows integer := -1;
  v_recruit_bot integer;

  v_limit_4th text := '(거부되지 않음)';
  v_limit_after_settle text := '(거부되지 않음)';
  v_lock_err text := '(거부되지 않음)';
  v_forfeit_err text := '(거부되지 않음)';
  v_consent_settle text;
  v_ev_captured_null text := '(거부되지 않음)';
  v_ev_path_empty text := '(거부되지 않음)';
  v_ev_before_start text := '(거부되지 않음)';
  v_ev_mismatch text := '(거부되지 않음)';
  v_judge_finished text := '(거부되지 않음)';
  v_judge_forced text := '(거부되지 않음)';
  v_create_err text := '(거부되지 않음)';
  v_join_err text := '(거부되지 않음)';
  v_card_err text := '(거부되지 않음)';
  v_perm_start_anon text := '(거부되지 않음)';
  v_perm_due text := '(거부되지 않음)';
  v_perm_one text := '(거부되지 않음)';
  v_perm_used text := '(거부되지 않음)';
  v_perm_score text := '(거부되지 않음)';
  v_perm_topics text := '(거부됨)';
  v_perm_settle_mine text := '(거부됨)';
  v_hint text;

  v_actual jsonb := '{}'::jsonb;
  v_expected jsonb;
  v_diff text;
begin
  -- -------------------------------------------------------------------------
  -- 0. 합격선 기준선. 사용자 식별 칸이 없는 두 테이블은 전체 수의 변화로 본다.
  -- -------------------------------------------------------------------------
  select count(*) into v_base_cache from public.criteria_cache;
  select count(*) into v_base_jobs from public.ai_judgment_jobs;

  insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  values
    (v_a, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'bot-smoke-a@example.invalid', '{"full_name":"봇스모크A"}'::jsonb, now(), now()),
    (v_b, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'bot-smoke-b@example.invalid', '{"full_name":"봇스모크B"}'::jsonb, now(), now()),
    (v_c, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'bot-smoke-c@example.invalid', '{"full_name":"봇스모크C"}'::jsonb, now(), now()),
    (v_d, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'bot-smoke-d@example.invalid', '{"full_name":"봇스모크D"}'::jsonb, now(), now()),
    (v_e, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'bot-smoke-e@example.invalid', '{"full_name":"봇스모크E"}'::jsonb, now(), now());

  -- 하한 0에 걸려 점수 변화가 가려지지 않게 10점에서 시작한다(v_b만 0점에서 시작해 +1을 본다).
  update public.player_stats set score = 10 where user_id in (v_a, v_c, v_d, v_e);

  perform set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
  perform public.give_ai_consent('2026-09-14');
  perform set_config('request.jwt.claims', json_build_object('sub', v_c, 'role', 'authenticated')::text, true);
  perform public.give_ai_consent('2026-09-14');
  perform set_config('request.jwt.claims', json_build_object('sub', v_d, 'role', 'authenticated')::text, true);
  perform public.give_ai_consent('2026-09-14');
  perform set_config('request.jwt.claims', json_build_object('sub', v_e, 'role', 'authenticated')::text, true);
  perform public.give_ai_consent('2026-09-14');
  -- v_b는 동의하지 않는다(아래 consent_* 항목).

  select id, duration_minutes, min_criteria, title
  into v_topic, v_dur, v_topic_min, v_topic_title
  from public.bot_battle_topics
  where active
  order by sort_order
  limit 1;

  -- -------------------------------------------------------------------------
  -- 1. 주제 목록 + 시작 3판
  -- -------------------------------------------------------------------------
  perform set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);

  v_topics := public.list_bot_battle_topics();

  v_b_win := public.start_bot_battle(v_topic);
  v_b_cl := public.start_bot_battle(v_topic);
  v_b_lock := public.start_bot_battle(v_topic);

  -- t_bot 검사는 **행을 만지기 전에** 해야 한다(아래에서 started_at·submitted_at을 민다).
  select v_ratio_ok and bool_and(
           extract(epoch from (s.submitted_at - b.started_at)) >= b.duration_minutes * 60 * 0.50
       and extract(epoch from (s.submitted_at - b.started_at)) <= b.duration_minutes * 60 * 0.85
       and s.submitted_at < b.deadline_at
       and s.object_path is null
       and s.captured_at is null)
  into v_ratio_ok
  from public.battles b
  join public.battle_submissions s on s.battle_id = b.id and s.user_id = v_bot
  where b.id in (v_b_win, v_b_cl, v_b_lock);

  v_actual := v_actual || jsonb_build_object(
    'start_topics_limit', (v_topics ->> 'daily_limit'),
    'start_topics_left', (v_topics ->> 'daily_left'),
    'start_topics_count', jsonb_array_length(v_topics -> 'topics')::text,
    'start_topics_first', (v_topics -> 'topics' -> 0 ->> 'title'),
    'start_topics_keys', (select string_agg(k, ',' order by k)
                          from jsonb_object_keys(v_topics -> 'topics' -> 0) k),
    'start_shape', (select concat_ws('/', b.type, b.status, b.is_bot::text,
                                     (b.opponent_id = v_bot)::text,
                                     (b.bot_topic_id = v_topic)::text,
                                     b.duration_minutes::text,
                                     b.criteria_version::text,
                                     (b.superiority_criteria is null)::text,
                                     (b.deadline_at = b.started_at
                                        + make_interval(mins => b.duration_minutes))::text,
                                     (b.min_criteria = v_topic_min)::text,
                                     (b.title = v_topic_title)::text,
                                     (b.forfeited_by is null)::text)
                    from public.battles b where b.id = v_b_win),
    'start_participants', (select count(*)::text from public.battle_participants
                           where battle_id = v_b_win),
    'start_bot_hidden', (select has_submitted::text from public.battle_participants
                         where battle_id = v_b_win and user_id = v_bot),
    'start_bot_submission', (select count(*)::text from public.battle_submissions
                             where battle_id = v_b_win and user_id = v_bot),
    'start_user_submission', (select count(*)::text from public.battle_submissions
                              where battle_id = v_b_win and user_id = v_a)
  );

  -- -------------------------------------------------------------------------
  -- 2. 하루 3회: 네 번째 호출 거부
  -- -------------------------------------------------------------------------
  begin
    perform public.start_bot_battle(v_topic);
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    v_limit_4th := coalesce(v_hint, '(힌트 없음)');
  end;

  v_topics := public.list_bot_battle_topics();

  v_actual := v_actual || jsonb_build_object(
    'limit_4th', v_limit_4th,
    'limit_used', public.bot_daily_battles_used(v_a)::text,
    'limit_left_after', (v_topics ->> 'daily_left')
  );

  -- -------------------------------------------------------------------------
  -- 3. 교체(t_bot 전) -> 제출 시각 갱신 -> t_bot 뒤 잠김 -> 포기 거부(W1) -> 승리로 종결
  -- -------------------------------------------------------------------------
  v_accept := public.accept_submission(
    v_a, v_b_lock, v_b_lock::text || '/' || v_a::text || '/p1.jpg', now());
  v_sub_id := (v_accept ->> 'submission_id')::bigint;

  -- "옛날에 냈다"로 만들어 둔다. 교체가 제출 시각을 갱신하는지 보려면 now()가 고정된 이
  -- 트랜잭션에서는 이 방법밖에 없다(그러지 않으면 갱신 전후 값이 같아 아무것도 증명하지 못한다).
  update public.battle_submissions
  set submitted_at = now() - interval '7 minutes'
  where id = v_sub_id;

  v_accept := public.accept_submission(
    v_a, v_b_lock, v_b_lock::text || '/' || v_a::text || '/p2.jpg', now());
  v_sub_id2 := (v_accept ->> 'submission_id')::bigint;

  v_actual := v_actual || jsonb_build_object(
    'replace_same_row', (v_sub_id = v_sub_id2)::text,
    'replace_rows', (select count(*)::text from public.battle_submissions
                     where battle_id = v_b_lock and user_id = v_a),
    'replace_path', (select right(object_path, 6) from public.battle_submissions where id = v_sub_id),
    'replace_submitted_refreshed', (select (submitted_at = now())::text
                                    from public.battle_submissions where id = v_sub_id),
    'replace_status', (select status from public.battles where id = v_b_lock),
    'replace_judging_opened', (v_accept ->> 'judging_opened'),
    'replace_battle_status', (v_accept ->> 'battle_status')
  );

  -- t_bot 경과를 흉내 낸다(봇의 제출 시각을 과거로 당긴다).
  update public.battle_submissions
  set submitted_at = now() - interval '10 seconds'
  where battle_id = v_b_lock and user_id = v_bot;

  begin
    perform public.accept_submission(
      v_a, v_b_lock, v_b_lock::text || '/' || v_a::text || '/p3.jpg', now());
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    v_lock_err := coalesce(v_hint, '(힌트 없음)');
  end;

  v_actual := v_actual || jsonb_build_object(
    'replace_locked', v_lock_err,
    'replace_path_kept', (select right(object_path, 6) from public.battle_submissions where id = v_sub_id)
  );

  -- -------------------------------------------------------------------------
  -- 3-W1. 어긋남 구간의 포기는 거부된다 (리뷰 지적 W1 회귀)
  -- -------------------------------------------------------------------------
  -- 지금 v_b_lock은 **어긋남 구간**에 있다: 봇의 목표 시각은 지났고(위에서 10초 전으로 밀었다)
  -- status는 아직 'active'라 포기 버튼이 살아 있다. 그 구간에 들어올 수 있는 봇전은 **사용자가
  -- t_bot 전에 제출한 판뿐이므로**(t_bot 뒤 첫 제출은 그 트랜잭션에서 바로 종결된다) 그 구간의
  -- 결과는 **언제나 승리**다. 포기가 먼저 커밋되면 +1이 -1로 뒤집힌다.
  --
  -- 그 상황을 만들려면 내 제출이 봇보다 **앞서야** 한다(여기까지는 둘 다 과거로 밀기 전이라
  -- 내 제출이 now()였다 - 봇의 now()-10초보다 늦다). 교체 단정이 모두 끝났으므로 지금 민다.
  update public.battle_submissions
  set submitted_at = now() - interval '5 minutes'
  where id = v_sub_id;

  -- 포기를 시도한다. forfeit_battle이 먼저 정산하고 상태를 다시 읽어 거부해야 한다.
  -- ** 이 블록이 서브트랜잭션이라, 거부와 함께 그 안의 정산도 되돌아간다 ** (파일 머리말).
  -- 그래서 아래에서 settle_bot_battle을 한 번 더 불러 같은 상태를 다시 만든 뒤 모양을 읽는다.
  begin
    perform public.forfeit_battle(v_b_lock);
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    v_forfeit_err := coalesce(v_hint, '(힌트 없음)');
  end;

  perform public.settle_bot_battle(v_b_lock);

  -- 종결된 뒤에도 그날의 횟수는 돌아오지 않는다(네 번째 시작은 여전히 거부된다).
  begin
    perform public.start_bot_battle(v_topic);
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    v_limit_after_settle := coalesce(v_hint, '(힌트 없음)');
  end;

  v_actual := v_actual || jsonb_build_object(
    'forfeit_refused', v_forfeit_err,
    -- ** 'finished/true/true'는 옛 값과 글자가 같지만 뜻이 완전히 다르다. **
    -- 옛 뜻: 종결 / 승자는 봇 / 포기한 사람은 나.
    -- 새 뜻: 종결 / ** 승자는 나 ** / ** 아무도 포기하지 않았다(forfeited_by is null) **.
    -- concat_ws는 null을 건너뛰어 칸 수가 줄어들므로 두 비교 모두 ::text로 boolean을 낸다.
    'forfeit_shape', (select concat_ws('/', b.status, (b.winner_id = v_a)::text,
                                       (b.forfeited_by is null)::text)
                      from public.battles b where b.id = v_b_lock),
    'forfeit_outcome', (select concat_ws('/', outcome, score_delta_applied::text)
                        from public.battle_participants
                        where battle_id = v_b_lock and user_id = v_a),
    'limit_after_settle', v_limit_after_settle,
    'limit_used_after_settle', public.bot_daily_battles_used(v_a)::text
  );

  -- -------------------------------------------------------------------------
  -- 4. KST 경계: 어제 시작한 판은 오늘 횟수에 들어가지 않는다
  -- -------------------------------------------------------------------------
  update public.battles
  set started_at = started_at - interval '1 day'
  where is_bot and creator_id = v_a;

  v_b_loss := public.start_bot_battle(v_topic);
  v_b_idle := public.start_bot_battle(v_topic);

  select v_ratio_ok and bool_and(
           extract(epoch from (s.submitted_at - b.started_at)) >= b.duration_minutes * 60 * 0.50
       and extract(epoch from (s.submitted_at - b.started_at)) <= b.duration_minutes * 60 * 0.85
       and s.submitted_at < b.deadline_at)
  into v_ratio_ok
  from public.battles b
  join public.battle_submissions s on s.battle_id = b.id and s.user_id = v_bot
  where b.id in (v_b_loss, v_b_idle);

  v_actual := v_actual || jsonb_build_object(
    'limit_kst_used', public.bot_daily_battles_used(v_a)::text,
    'limit_kst_left', (public.list_bot_battle_topics() ->> 'daily_left')
  );

  -- -------------------------------------------------------------------------
  -- 5. t_bot 전: 정산 RPC가 아무것도 하지 않고, 상대 제출 행이 보이지 않는다
  -- -------------------------------------------------------------------------
  v_accept := public.accept_submission(
    v_a, v_b_idle, v_b_idle::text || '/' || v_a::text || '/p.jpg', now());

  begin
    execute 'set local role authenticated';
    select count(*) into v_reveal_before from public.battle_submissions where battle_id = v_b_idle;
    execute 'reset role';
  exception when others then
    execute 'reset role';
    v_reveal_before := -1;
  end;
  execute 'reset role';

  v_settle_idle := public.settle_my_bot_battles();

  v_actual := v_actual || jsonb_build_object(
    'idle_accept_opened', (v_accept ->> 'judging_opened'),
    'idle_accept_status', (v_accept ->> 'battle_status'),
    'idle_settled', v_settle_idle::text,
    'idle_status', (select status from public.battles where id = v_b_idle),
    'reveal_before', v_reveal_before::text,
    -- t_bot은 battles의 어떤 컬럼에도 없다. timestamptz 컬럼 수를 함께 고정해, 나중에 시각
    -- 컬럼이 하나 더 생기면 이 검사가 조용히 불완전해지지 않게 한다.
    'reveal_tbot_hidden', (select not exists (
                             select 1 from public.battles b
                             join public.battle_submissions s
                               on s.battle_id = b.id and s.user_id = v_bot
                             where b.id = v_b_idle
                               and s.submitted_at in (b.created_at, b.started_at, b.deadline_at,
                                                      b.finished_at, b.judging_opened_at,
                                                      b.judge_deadline_at)))::text,
    'reveal_ts_columns', (select count(*)::text from information_schema.columns
                          where table_schema = 'public' and table_name = 'battles'
                            and data_type like 'timestamp%')
  );

  -- -------------------------------------------------------------------------
  -- 6. 승리: 봇보다 먼저 낸 제출 -> cron 경로로 종결
  -- -------------------------------------------------------------------------
  perform public.accept_submission(
    v_a, v_b_win, v_b_win::text || '/' || v_a::text || '/p.jpg', now());

  -- "사용자가 5분 전에 냈고 1분 전에 t_bot이 지났다"를 만든다. now()가 고정이라 두 시각을
  -- 직접 과거로 밀지 않으면 둘이 같아져 동순위 처리(행 id가 작은 봇 승)로 떨어진다.
  update public.battle_submissions set submitted_at = now() - interval '5 minutes'
  where battle_id = v_b_win and user_id = v_a;
  update public.battle_submissions set submitted_at = now() - interval '1 minute'
  where battle_id = v_b_win and user_id = v_bot;

  v_settle_due := public.settle_due_bot_battles();

  v_actual := v_actual || jsonb_build_object(
    'win_settled_any', (v_settle_due >= 1)::text,
    'win_shape', (select concat_ws('/', b.status, (b.winner_id = v_a)::text,
                                   (b.finished_at is not null)::text)
                  from public.battles b where b.id = v_b_win),
    'win_user_outcome', (select concat_ws('/', outcome, score_delta_applied::text)
                         from public.battle_participants
                         where battle_id = v_b_win and user_id = v_a),
    'win_bot_outcome', (select concat_ws('/', outcome, coalesce(score_delta_applied::text, 'null'),
                                         has_submitted::text, has_judged::text)
                        from public.battle_participants
                        where battle_id = v_b_win and user_id = v_bot),
    'win_bot_stats_rows', (select count(*)::text from public.player_stats where user_id = v_bot),
    'judgment_rows', (select count(*)::text from public.battle_judgments where battle_id = v_b_win),
    'judgment_auto', (select concat_ws('/', bool_and(auto)::text, bool_and(min_verdict = 'approve')::text,
                                       bool_and(superior_id is null)::text)
                      from public.battle_judgments where battle_id = v_b_win),
    'judgment_verdict_source', (select concat_ws('/', bool_and(verdict_source = 'auto')::text,
                                                 bool_and(meets_criteria)::text)
                                from public.battle_submissions where battle_id = v_b_win)
  );

  begin
    execute 'set local role authenticated';
    select count(*) into v_reveal_after from public.battle_submissions where battle_id = v_b_win;
    execute 'reset role';
  exception when others then
    execute 'reset role';
    v_reveal_after := -1;
  end;
  execute 'reset role';

  v_actual := v_actual || jsonb_build_object('reveal_after', v_reveal_after::text);

  -- -------------------------------------------------------------------------
  -- 7. 완료한 패배: t_bot 뒤 첫 제출은 **그 트랜잭션에서** 끝난다
  -- -------------------------------------------------------------------------
  update public.battle_submissions set submitted_at = now() - interval '1 minute'
  where battle_id = v_b_cl and user_id = v_bot;

  v_accept := public.accept_submission(
    v_a, v_b_cl, v_b_cl::text || '/' || v_a::text || '/p.jpg', now());

  v_actual := v_actual || jsonb_build_object(
    'cl_accept_opened', (v_accept ->> 'judging_opened'),
    -- ** 'judging'이 아니라 'finished'여야 한다 ** (accept_submission이 실제 상태를 다시 읽는다)
    'cl_accept_status', (v_accept ->> 'battle_status'),
    'cl_shape', (select concat_ws('/', b.status, (b.winner_id = v_bot)::text)
                 from public.battles b where b.id = v_b_cl),
    'cl_outcome', (select concat_ws('/', outcome, score_delta_applied::text)
                   from public.battle_participants where battle_id = v_b_cl and user_id = v_a)
  );

  -- -------------------------------------------------------------------------
  -- 8. 완료 못 한 패배: 미제출 + 마감 -> 기존 마감 정산이 집는다
  -- -------------------------------------------------------------------------
  update public.battles set deadline_at = now() - interval '1 minute' where id = v_b_loss;
  update public.battle_submissions set submitted_at = now() - interval '5 minutes'
  where battle_id = v_b_loss and user_id = v_bot;

  v_settle_exp := public.settle_expired_battles();

  v_actual := v_actual || jsonb_build_object(
    'loss_settled_any', (v_settle_exp >= 1)::text,
    'loss_shape', (select concat_ws('/', b.status, (b.winner_id = v_bot)::text)
                   from public.battles b where b.id = v_b_loss),
    'loss_outcome', (select concat_ws('/', outcome, score_delta_applied::text)
                     from public.battle_participants where battle_id = v_b_loss and user_id = v_a),
    -- 사용자가 내지 않았으므로 봇이 판정할 것이 없다 -> 판정 행은 사용자 쪽 1개뿐이다.
    -- concat_ws는 boolean을 't'/'f'로 쓰므로(출력 함수) 비교 결과마다 ::text를 붙여 둔다.
    'loss_judgments', (select concat_ws('/', count(*)::text,
                                        (max(judge_id::text) = v_a::text)::text)
                       from public.battle_judgments where battle_id = v_b_loss)
  );

  -- -------------------------------------------------------------------------
  -- 9. 동의 없이도 봇전은 된다 / 사람 대결은 여전히 막힌다
  -- -------------------------------------------------------------------------
  perform set_config('request.jwt.claims', json_build_object('sub', v_b, 'role', 'authenticated')::text, true);

  v_b_nc := public.start_bot_battle(v_topic);

  select v_ratio_ok and bool_and(
           extract(epoch from (s.submitted_at - b.started_at)) >= b.duration_minutes * 60 * 0.50
       and extract(epoch from (s.submitted_at - b.started_at)) <= b.duration_minutes * 60 * 0.85
       and s.submitted_at < b.deadline_at)
  into v_ratio_ok
  from public.battles b
  join public.battle_submissions s on s.battle_id = b.id and s.user_id = v_bot
  where b.id = v_b_nc;

  perform public.accept_submission(
    v_b, v_b_nc, v_b_nc::text || '/' || v_b::text || '/p.jpg', now());

  update public.battle_submissions set submitted_at = now() - interval '5 minutes'
  where battle_id = v_b_nc and user_id = v_b;
  update public.battle_submissions set submitted_at = now() - interval '1 minute'
  where battle_id = v_b_nc and user_id = v_bot;

  -- ** 정산 호출을 jsonb_build_object 밖으로 뺀다. ** 같은 statement 안에 두면 아래 읽기들이
  -- statement 시작 시점 스냅샷을 보아 정산 **전** 상태(outcome null, 점수 0)를 읽는다.
  -- 2026-11-24 원격 첫 실행에서 consent_outcome·consent_stats 두 키가 정확히 그렇게 어긋났다 —
  -- 제품이 아니라 테스트 버그였고(consent_settle은 'finished'로 통과했다) 이 파일에서 이 한 자리만
  -- 그 모양이었다(나머지는 전부 변수로 먼저 받는다).
  v_consent_settle := public.settle_bot_battle(v_b_nc);
  v_actual := v_actual || jsonb_build_object(
    'consent_settle', v_consent_settle,
    'consent_rows', (select count(*)::text from public.ai_consents where user_id = v_b),
    'consent_outcome', (select concat_ws('/', outcome, score_delta_applied::text)
                        from public.battle_participants where battle_id = v_b_nc and user_id = v_b),
    'consent_stats', (select concat_ws('/', score, wins, losses, draws)
                      from public.player_stats where user_id = v_b)
  );

  begin
    perform public.create_battle(gen_random_uuid(), 10);
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    v_create_err := coalesce(v_hint, '(힌트 없음)');
  end;

  begin
    perform public.join_battle(gen_random_uuid(), 1);
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    v_join_err := coalesce(v_hint, '(힌트 없음)');
  end;

  v_actual := v_actual || jsonb_build_object(
    'consent_create_battle', v_create_err,
    'consent_join_battle', v_join_err
  );

  -- -------------------------------------------------------------------------
  -- 10. 합격선: AI와 닿는 네 테이블에 행이 생기지 않았다
  -- -------------------------------------------------------------------------
  perform set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
  v_limits := public.get_my_limits();

  v_actual := v_actual || jsonb_build_object(
    'gate_criteria_checks', (select count(*)::text from public.criteria_checks
                             where user_id in (v_a, v_b, v_c, v_d, v_e)),
    'gate_criteria_calls', (select count(*)::text from public.ai_criteria_calls
                            where user_id in (v_a, v_b, v_c, v_d, v_e)),
    'gate_cache_delta', ((select count(*) from public.criteria_cache) - v_base_cache)::text,
    'gate_jobs_delta', ((select count(*) from public.ai_judgment_jobs) - v_base_jobs)::text,
    'gate_jobs_mine', (select count(*)::text from public.ai_judgment_jobs
                       where battle_id in (v_b_win, v_b_cl, v_b_lock, v_b_loss, v_b_idle, v_b_nc)),
    'gate_criteria_left', (v_limits ->> 'criteria_calls_left'),
    'gate_draw_voided', (select count(*)::text from public.battles
                         where status in ('draw', 'voided')
                           and id in (v_b_win, v_b_cl, v_b_lock, v_b_loss, v_b_idle, v_b_nc)),
    'tbot_ratio_ok', v_ratio_ok::text
  );

  -- -------------------------------------------------------------------------
  -- 11. 알림: finished 하나뿐. 봇 수신 0행.
  -- -------------------------------------------------------------------------
  v_actual := v_actual || jsonb_build_object(
    'notify_kinds', (select coalesce(string_agg(distinct kind, ',' order by kind), '(없음)')
                     from public.notification_outbox
                     where battle_id in (v_b_win, v_b_cl, v_b_lock, v_b_loss, v_b_idle, v_b_nc)),
    'notify_bot_rows', (select count(*)::text from public.notification_outbox
                        where recipient_id = v_bot),
    -- 네 판 전부 종결 알림이 온다: 교체 판(포기가 거부되고 승리로 끝났다)·승리·완료한 패배·
    -- 완료 못 한 패배. ** 진짜 포기는 본인에게 보내지 않는데 그 검사는 섹션 12b로 옮겼다 **
    -- (여기서는 아직 v_b_idle이 active여야 하므로 포기가 일어나지 않았다).
    'notify_user_rows', (select count(*)::text from public.notification_outbox
                         where recipient_id = v_a and kind = 'finished'),
    -- 옛 'notify_forfeit_rows'(v_b_lock의 포기 알림 0행) 자리다. 이제 v_b_lock은 포기가 아니라
    -- 내 승리로 끝나므로 내게 종결 알림 1행이 쌓인다 - 뜻이 바뀌었으니 이름도 바꿨다.
    'notify_lock_rows', (select count(*)::text from public.notification_outbox
                         where battle_id = v_b_lock),
    'notify_is_bot_flag', (select bool_and((payload ->> 'is_bot')::boolean)::text
                           from public.notification_outbox
                           where battle_id in (v_b_win, v_b_cl, v_b_lock, v_b_loss)
                             and kind = 'finished')
  );

  -- -------------------------------------------------------------------------
  -- 12. 철회가 봇전을 건드리지 않는다
  -- -------------------------------------------------------------------------
  v_impact := public.get_consent_withdrawal_impact();
  v_withdraw := public.withdraw_ai_consent();

  v_actual := v_actual || jsonb_build_object(
    'consent_impact_active', (v_impact ->> 'active_count'),
    'consent_impact_pending', (v_impact ->> 'pending_count'),
    'consent_withdraw_forfeited', (v_withdraw ->> 'forfeited'),
    'consent_withdraw_cancelled', (v_withdraw ->> 'cancelled'),
    'consent_idle_kept', (select status from public.battles where id = v_b_idle)
  );

  -- -------------------------------------------------------------------------
  -- 12b. 증거 규칙은 봇전에서도 그대로다 + 진짜 포기 (리뷰 지적 W3-3, W1의 나머지 절반)
  -- -------------------------------------------------------------------------
  -- accept_submission을 통째로 재정의했는데 사용자 쪽 증거 규칙이 그대로인지를 SQL에서 아무도
  -- 보지 않았다. v_b_idle을 쓴다 - 아직 active이고(위 consent_idle_kept가 그것을 고정한다)
  -- t_bot 전이라 거부 네 건이 상태를 바꾸지 않는다. 거부는 모두 블록 안에서 되돌아간다.
  --
  -- 앞의 두 건은 hint 없이 raise되므로(migration 원문) 힌트가 아니라 **메시지**로 받는다.
  -- 뒤의 두 건은 hint가 있다. 이 네 가드는 사람 대결과 **같은 코드 경로**이고, 봇전 분기
  -- (동의 건너뛰기·t_bot 기준 잠금)보다 **앞에** 있다는 것이 여기서 고정하는 사실이다.
  begin
    perform public.accept_submission(
      v_a, v_b_idle, v_b_idle::text || '/' || v_a::text || '/p.jpg', null::timestamptz);
  exception when others then
    v_ev_captured_null := sqlerrm;
  end;

  begin
    perform public.accept_submission(v_a, v_b_idle, '', now());
  exception when others then
    v_ev_path_empty := sqlerrm;
  end;

  -- v_b_idle의 started_at은 now()다(섹션 4에서 날짜를 민 **뒤** 시작했다). 1분 전에 찍은 사진은
  -- 이 대결의 증거가 아니다. 10분 검사보다 이 검사가 먼저다.
  begin
    perform public.accept_submission(
      v_a, v_b_idle, v_b_idle::text || '/' || v_a::text || '/p.jpg',
      now() - interval '1 minute');
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    v_ev_before_start := coalesce(v_hint, '(힌트 없음)');
  end;

  -- 기기 시계가 앞선 경우(미래 촬영). 절댓값으로 보므로 11분 뒤도 거부다 - 그리고 미래 값은
  -- 시작 전 검사를 통과하므로 이 가드에 정확히 도달한다.
  begin
    perform public.accept_submission(
      v_a, v_b_idle, v_b_idle::text || '/' || v_a::text || '/p.jpg',
      now() + interval '11 minutes');
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    v_ev_mismatch := coalesce(v_hint, '(힌트 없음)');
  end;

  v_actual := v_actual || jsonb_build_object(
    'evidence_no_captured', v_ev_captured_null,
    'evidence_no_path', v_ev_path_empty,
    'evidence_before_start', v_ev_before_start,
    'evidence_mismatch', v_ev_mismatch,
    -- 네 번의 거부가 아무것도 바꾸지 않았다(상태·내 제출 1행·경로 그대로).
    'evidence_kept', (select concat_ws('/', b.status, count(s.id)::text,
                                       coalesce(max(right(s.object_path, 5)), '(없음)'))
                      from public.battles b
                      left join public.battle_submissions s
                        on s.battle_id = b.id and s.user_id = v_a
                      where b.id = v_b_idle
                      group by b.status)
  );

  -- ** 진짜 포기 **: 어긋남 구간이 아닌 포기(t_bot 전)는 그대로 성립해야 한다.
  -- 위 W1 분기는 "먼저 정산한다"뿐이고 t_bot 전에는 정산이 아무 일도 하지 않으므로, 이 판은
  -- 상태가 그대로 'active'로 읽혀 포기로 내려간다. 그것이 정확히 여기서 검사하려는 것이다.
  -- (여기 두는 이유: v_b_idle은 섹션 12의 consent_idle_kept까지 active로 남아 있어야 한다.)
  perform public.forfeit_battle(v_b_idle);

  v_actual := v_actual || jsonb_build_object(
    'forfeit_idle_shape', (select concat_ws('/', b.status, (b.winner_id = v_bot)::text,
                                            (b.forfeited_by = v_a)::text)
                           from public.battles b where b.id = v_b_idle),
    'forfeit_idle_outcome', (select concat_ws('/', outcome, score_delta_applied::text)
                             from public.battle_participants
                             where battle_id = v_b_idle and user_id = v_a),
    -- 포기 알림은 생기지 않는다: 본인은 건너뛰고(내 행동의 결과다) 상대는 봇이라 막힌다.
    -- 섹션 5의 제출 알림도 수신자가 봇이라 막혔으므로 이 대결의 원장은 0행이어야 한다.
    'forfeit_idle_notify', (select count(*)::text from public.notification_outbox
                            where battle_id = v_b_idle),
    -- 포기해도 그날의 횟수는 돌아오지 않는다(오늘 시작한 두 판 그대로).
    'forfeit_idle_limit_used', public.bot_daily_battles_used(v_a)::text
  );

  -- -------------------------------------------------------------------------
  -- 13. 탈퇴: 진행 중 봇전은 승자 없이 cancelled, 점수 변동 없음
  -- -------------------------------------------------------------------------
  perform set_config('request.jwt.claims', json_build_object('sub', v_e, 'role', 'authenticated')::text, true);
  v_b_del := public.start_bot_battle(v_topic);
  perform public.delete_account();

  v_actual := v_actual || jsonb_build_object(
    'delete_status', (select concat_ws('/', status, coalesce(winner_id::text, 'null'))
                      from public.battles where id = v_b_del),
    'delete_outcomes', (select concat_ws('/', count(*)::text,
                                         count(*) filter (where outcome is null)::text,
                                         count(*) filter (where score_delta_applied is null)::text)
                        from public.battle_participants where battle_id = v_b_del),
    'delete_notifications', (select count(*)::text from public.notification_outbox
                             where battle_id = v_b_del)
  );

  -- -------------------------------------------------------------------------
  -- 14. 봇이 사람처럼 나타나지 않는다
  -- -------------------------------------------------------------------------
  perform set_config('request.jwt.claims', json_build_object('sub', v_c, 'role', 'authenticated')::text, true);

  begin
    perform public.get_player_card(v_bot);
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    v_card_err := coalesce(v_hint, '(힌트 없음)');
  end;

  select count(*) into v_recruit_bot
  from public.list_open_recruits(50) as t(item)
  where (t.item -> 'creator' ->> 'user_id')::uuid = v_bot
     or (t.item -> 'battle' ->> 'id')::uuid = any (
          array[v_b_win, v_b_cl, v_b_lock, v_b_loss, v_b_idle, v_b_nc, v_b_del]);

  v_actual := v_actual || jsonb_build_object(
    'expose_player_card', v_card_err,
    'expose_recruits', v_recruit_bot::text,
    'expose_bot_deleted_at', (select (deleted_at is null)::text from public.profiles where id = v_bot)
  );

  -- -------------------------------------------------------------------------
  -- 15. 사람 대결 회귀: 점수 +3 / -1과 전적 카운터가 그대로다
  -- -------------------------------------------------------------------------
  insert into public.battles (
    type, status, title, creator_id, opponent_id, duration_minutes,
    min_criteria, superiority_criteria, started_at, deadline_at
  )
  values (
    'speed', 'active', '사람 대결 회귀', v_c, v_d, 1440,
    '["상판이 보인다"]'::jsonb, null, now(), now() + interval '1 day'
  )
  returning id into v_h;

  insert into public.battle_participants (battle_id, user_id) values (v_h, v_d);

  perform public.accept_submission(v_c, v_h, v_h::text || '/' || v_c::text || '/p.jpg', now());
  perform public.accept_submission(v_d, v_h, v_h::text || '/' || v_d::text || '/p.jpg', now());

  -- 두 제출의 submitted_at이 같으므로(now() 고정) 동순위 처리로 먼저 기록된 쪽(생성자)이 이긴다.
  perform set_config('request.jwt.claims', json_build_object('sub', v_c, 'role', 'authenticated')::text, true);
  perform public.submit_judgment(v_h, 'approve', null);
  perform set_config('request.jwt.claims', json_build_object('sub', v_d, 'role', 'authenticated')::text, true);
  perform public.submit_judgment(v_h, 'approve', null);

  v_actual := v_actual || jsonb_build_object(
    'human_shape', (select concat_ws('/', status, (winner_id = v_c)::text, is_bot::text)
                    from public.battles where id = v_h),
    'human_c_outcome', (select concat_ws('/', outcome, score_delta_applied::text)
                        from public.battle_participants where battle_id = v_h and user_id = v_c),
    'human_d_outcome', (select concat_ws('/', outcome, score_delta_applied::text)
                        from public.battle_participants where battle_id = v_h and user_id = v_d),
    'human_c_stats', (select concat_ws('/', score, wins, losses, draws)
                      from public.player_stats where user_id = v_c),
    'human_d_stats', (select concat_ws('/', score, wins, losses, draws)
                      from public.player_stats where user_id = v_d),
    'human_kinds', (select string_agg(distinct kind, ',' order by kind)
                    from public.notification_outbox where battle_id = v_h),
    'human_verdict_source', (select string_agg(distinct verdict_source, ',')
                             from public.battle_submissions where battle_id = v_h),
    -- 봇전으로 올린 점수는 섞이고 전적은 섞이지 않는다.
    'a_stats', (select concat_ws('/', score, wins, losses, draws)
                from public.player_stats where user_id = v_a),
    'e_stats_rows', (select count(*)::text from public.player_stats where user_id = v_e)
  );

  -- -------------------------------------------------------------------------
  -- 16. 권한
  -- -------------------------------------------------------------------------
  begin
    execute 'set local role anon';
    perform public.start_bot_battle(v_topic);
    execute 'reset role';
  exception when insufficient_privilege then
    v_perm_start_anon := 'rejected';
  when others then
    v_perm_start_anon := '다른 오류: ' || sqlerrm;
  end;
  execute 'reset role';

  begin
    execute 'set local role authenticated';
    perform public.settle_due_bot_battles();
    execute 'reset role';
  exception when insufficient_privilege then
    v_perm_due := 'rejected';
  when others then
    v_perm_due := '다른 오류: ' || sqlerrm;
  end;
  execute 'reset role';

  begin
    execute 'set local role authenticated';
    perform public.settle_bot_battle(v_b_idle);
    execute 'reset role';
  exception when insufficient_privilege then
    v_perm_one := 'rejected';
  when others then
    v_perm_one := '다른 오류: ' || sqlerrm;
  end;
  execute 'reset role';

  begin
    execute 'set local role authenticated';
    perform public.bot_daily_battles_used(v_a);
    execute 'reset role';
  exception when insufficient_privilege then
    v_perm_used := 'rejected';
  when others then
    v_perm_used := '다른 오류: ' || sqlerrm;
  end;
  execute 'reset role';

  begin
    execute 'set local role authenticated';
    perform public.bot_outcome_score_delta('win');
    execute 'reset role';
  exception when insufficient_privilege then
    v_perm_score := 'rejected';
  when others then
    v_perm_score := '다른 오류: ' || sqlerrm;
  end;
  execute 'reset role';

  -- 앱이 부르는 두 RPC는 authenticated로 되어야 한다.
  perform set_config('request.jwt.claims', json_build_object('sub', v_c, 'role', 'authenticated')::text, true);
  begin
    execute 'set local role authenticated';
    perform public.list_bot_battle_topics();
    v_settle_perm := public.settle_my_bot_battles();
    execute 'reset role';
    v_perm_topics := 'allowed';
    v_perm_settle_mine := 'allowed';
  exception when others then
    execute 'reset role';
    v_perm_topics := '거부됨: ' || sqlerrm;
    v_perm_settle_mine := '거부됨: ' || sqlerrm;
  end;
  execute 'reset role';

  begin
    execute 'set local role authenticated';
    select count(*) into v_topics_rows from public.bot_battle_topics;
    execute 'reset role';
  exception when others then
    execute 'reset role';
    -- 권한 자체가 없어 예외가 나는 것도 "볼 수 없다"는 같은 결론이다.
    v_topics_rows := 0;
  end;
  execute 'reset role';

  v_actual := v_actual || jsonb_build_object(
    'perm_start_anon', v_perm_start_anon,
    'perm_settle_due', v_perm_due,
    'perm_settle_one', v_perm_one,
    'perm_daily_used', v_perm_used,
    'perm_score_delta', v_perm_score,
    'perm_list_topics', v_perm_topics,
    'perm_settle_mine', v_perm_settle_mine,
    'perm_topics_rows', v_topics_rows::text
  );

  -- -------------------------------------------------------------------------
  -- 17. 봇전에 'reject'가 들어갈 수 있는가 (리뷰 지적 W3-1)
  -- -------------------------------------------------------------------------
  -- 합격선(AI 호출 0회)은 "min_verdict='reject'에 도달할 식이 없다"에 기대 있고, 그것을 지키는
  -- 것은 submit_judgment의 **벽 두 겹**뿐이다(그 함수에는 is_bot 분기가 없다).
  --   ① JUDGING_NOT_OPEN - 봇전은 판정 창이 열린 트랜잭션에서 종결되므로 status가 'judging'으로
  --      관측되는 순간이 없다.
  --   ② ALREADY_JUDGED  - 창이 열릴 때 사용자의 자동 승인 행이 PK를 이미 차지한다.
  -- 두 겹을 각각 **그 벽이 실제로 작동하는 모양으로** 고정하고, 마지막에 두 겹을 치워 보는
  -- 양성 대조로 "막는 것이 이 둘뿐"임을 드러낸다.
  --
  -- ** 이 섹션과 18은 섹션 10(gate_jobs_delta·gate_jobs_mine이 0을 요구한다)보다 뒤에 둔다. **
  -- 그 측정은 이미 끝났으므로 여기서 생기는 잡이 그 값을 바꾸지 않는다. 그래도 아래에서 잡 행을
  -- **지워 둔다** - 섹션 18의 close_expired_judging_windows가 전역을 훑기 때문이다.
  --
  -- 쓰는 사용자는 v_b다(봇전을 한 판만 썼으므로 하루 3회 중 두 자리가 남아 있다). v_b의
  -- consent_stats는 섹션 9에서 이미 읽었으므로 여기서 점수가 더 오르는 것은 그 값을 건드리지
  -- 않는다. 동의가 없어도 봇전은 시작·제출·종결이 전부 된다(그것이 섹션 9의 결론이다).
  perform set_config('request.jwt.claims', json_build_object('sub', v_b, 'role', 'authenticated')::text, true);

  v_b_judge := public.start_bot_battle(v_topic);   -- v_b의 2번째 판

  perform public.accept_submission(
    v_b, v_b_judge, v_b_judge::text || '/' || v_b::text || '/p.jpg', now());

  update public.battle_submissions set submitted_at = now() - interval '5 minutes'
  where battle_id = v_b_judge and user_id = v_b;
  update public.battle_submissions set submitted_at = now() - interval '1 minute'
  where battle_id = v_b_judge and user_id = v_bot;

  -- 정상 경로로 종결시킨다(승리 +1). 자동 승인 두 행과 meets_criteria=true가 여기서 생긴다.
  perform public.settle_bot_battle(v_b_judge);

  -- 벽 ①: 종결된 봇전에는 판정이 들어가지 않는다. **앱이 실제로 만나는 상태가 이것이다.**
  begin
    perform public.submit_judgment(v_b_judge, 'reject', null);
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    v_judge_finished := coalesce(v_hint, '(힌트 없음)');
  end;

  -- 벽 ②: 억지로 judging에 세워도(기한은 미래로 둔다 - 그러지 않으면 JUDGE_WINDOW_CLOSED가 먼저
  -- 나서 보려는 벽이 가려진다) 자동 승인 행이 PK를 차지하고 있어 거부된다.
  update public.battles
  set status = 'judging',
      judging_opened_at = now(),
      judge_deadline_at = now() + interval '24 hours'
  where id = v_b_judge;

  begin
    perform public.submit_judgment(v_b_judge, 'reject', null);
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    v_judge_forced := coalesce(v_hint, '(힌트 없음)');
  end;

  -- ** 양성 대조: 벽 두 겹을 치우면 'reject'가 들어가고 재판정 잡이 생긴다. **
  -- 자동 승인 행을 지우고(벽 ②) meets_criteria를 비워 "창이 막 열렸다"로 되돌린다 - 그러지 않으면
  -- min_verdict_effect(제출됨, 'reject', true)가 pass가 되어 불복이 결론을 바꾸지 않는다.
  -- 이것이 성공하는 것이 **정상**이다: 봇전을 지키는 것은 위 두 겹이고 submit_judgment·
  -- resolve_battle에는 봇전 분기가 없다. 이 키가 '(거부되지 않음)'이 아닌 값으로 바뀌면 누군가
  -- 세 번째 벽을 넣은 것이고, 그때는 위 두 벽의 뜻을 다시 읽어야 한다.
  delete from public.battle_judgments where battle_id = v_b_judge and judge_id = v_b;
  update public.battle_submissions
  set meets_criteria = null, verdict_source = null
  where battle_id = v_b_judge;

  v_judge_gap := public.submit_judgment(v_b_judge, 'reject', null);

  v_actual := v_actual || jsonb_build_object(
    'judge_wall_finished', v_judge_finished,
    'judge_wall_forced', v_judge_forced,
    -- 불복이 기록됐고 결론이 나지 않아 judging에 머문다(= AI를 기다린다).
    'judge_gap_status', v_judge_gap,
    -- 그 잡의 대상은 **봇의 사진 없는 제출**이다(target_id = 봇). 도달할 수 있다면 AI에게 없는
    -- 사진을 판정하라고 보내는 셈이다 - 벽 두 겹이 왜 합격선인지가 이 한 행에 있다.
    'judge_gap_jobs', (select concat_ws('/', count(*)::text, max(kind),
                                        bool_and(target_id = v_bot)::text)
                       from public.ai_judgment_jobs where battle_id = v_b_judge)
  );

  -- 전역을 훑는 섹션 18이 이 잡을 보지 않게 치운다(측정은 위에서 끝났다).
  delete from public.ai_judgment_jobs where battle_id = v_b_judge;

  -- -------------------------------------------------------------------------
  -- 18. 안전망: 창이 열린 채 남은 봇전도 같은 결론으로 끝난다 (리뷰 지적 W3-2)
  -- -------------------------------------------------------------------------
  -- design §3.1 B10은 "B5~B7의 resolve_battle이 예외로 실패해 창이 남은 경우 close_expired_
  -- judging_windows가 자동 승인을 채우고 **같은 결론**을 낸다"고 주장하는데 한 번도 돌려 보지
  -- 않았다. 그 사고의 모양(창은 열렸고 자동 승인 행도 meets_criteria도 없다)을 손으로 만들어
  -- 돌린다. 기대는 섹션 6(B5)과 **같은 결론**이다 - 승리, +1, 전적 카운터 0, 잡 0행.
  v_b_safe := public.start_bot_battle(v_topic);   -- v_b의 3번째 판(상한에 걸리지 않는다)

  perform public.accept_submission(
    v_b, v_b_safe, v_b_safe::text || '/' || v_b::text || '/p.jpg', now());

  update public.battle_submissions set submitted_at = now() - interval '5 minutes'
  where battle_id = v_b_safe and user_id = v_b;
  update public.battle_submissions set submitted_at = now() - interval '1 minute'
  where battle_id = v_b_safe and user_id = v_bot;

  -- 판정 기한을 과거로 민다(창이 열린 지 25시간 지났다). 판정 행을 **넣지 않는** 것이 핵심이다.
  update public.battles
  set status = 'judging',
      judging_opened_at = now() - interval '25 hours',
      judge_deadline_at = now() - interval '1 hour'
  where id = v_b_safe;

  v_closed_judging := public.close_expired_judging_windows();

  v_actual := v_actual || jsonb_build_object(
    'safety_closed_any', (v_closed_judging >= 1)::text,
    'safety_shape', (select concat_ws('/', b.status, (b.winner_id = v_b)::text,
                                      (b.finished_at is not null)::text)
                     from public.battles b where b.id = v_b_safe),
    'safety_outcome', (select concat_ws('/', outcome, score_delta_applied::text)
                       from public.battle_participants
                       where battle_id = v_b_safe and user_id = v_b),
    -- 안전망도 같은 자동 승인 두 행을 쓴다(한쪽은 봇이 낸 것으로 기록된다).
    'safety_judgments', (select concat_ws('/', count(*)::text, bool_and(auto)::text,
                                          bool_and(min_verdict = 'approve')::text)
                         from public.battle_judgments where battle_id = v_b_safe),
    'safety_verdict_source', (select concat_ws('/', count(*)::text,
                                               bool_and(verdict_source = 'auto')::text,
                                               bool_and(meets_criteria)::text)
                              from public.battle_submissions where battle_id = v_b_safe),
    'safety_jobs', (select count(*)::text from public.ai_judgment_jobs
                    where battle_id in (v_b_judge, v_b_safe)),
    -- v_b 점수: 0 +1(섹션 9의 승) +1(섹션 17의 승) +1(여기) = 3. 전적은 봇전이라 0/0/0 그대로다.
    'safety_stats', (select concat_ws('/', score, wins, losses, draws)
                     from public.player_stats where user_id = v_b)
  );

  -- -------------------------------------------------------------------------
  -- 기대값
  -- -------------------------------------------------------------------------
  -- v_a 점수: 10 +1(교체 판 - 포기가 거부되고 승리) +1(승) -1(완료한 패배) -1(완료 못 한 패배)
  --           -1(진짜 포기, 섹션 12b) = 9. 전적은 0/0/0 그대로다(봇전은 카운터를 건드리지 않는다).
  -- v_b 점수: 0 +1(섹션 9의 승) +1(섹션 17의 승) +1(섹션 18의 승) = 3
  --           ** consent_stats('1/0/0/0')와 safety_stats('3/0/0/0')가 다른 것이 정상이다 ** -
  --           앞은 섹션 9에서, 뒤는 섹션 18에서 읽은 같은 행의 다른 시점이다.
  -- v_c 점수: 10 +3 = 13(승 1), v_d 점수: 10 -1 = 9(패 1)  <- 사람 대결 표 그대로
  --
  -- ** 다섯 묶음으로 쪼개 쓴다. ** PostgreSQL 함수의 인자 상한은 100개라(FUNC_MAX_ARGS)
  -- 키 전부를 한 jsonb_build_object에 담으면 그 두 배가 인자 수가 되어 호출 자체가 거부된다.
  v_expected := jsonb_build_object(
    -- 1. 시작
    'start_topics_limit', '3',
    'start_topics_left', '3',
    'start_topics_count', '8',
    'start_topics_first', '설거지하기',
    'start_topics_keys', 'duration_minutes,id,min_criteria,title',
    'start_shape', 'speed/active/true/true/true/' || v_dur::text || '/1/true/true/true/true/true',
    'start_participants', '2',
    'start_bot_hidden', 'false',
    'start_bot_submission', '1',
    'start_user_submission', '0',
    -- 2. 하루 3회
    'limit_4th', 'BOT_DAILY_LIMIT',
    'limit_used', '3',
    'limit_left_after', '0',
    -- 3. 교체·잠김·포기
    'replace_same_row', 'true',
    'replace_rows', '1',
    'replace_path', 'p2.jpg',
    'replace_submitted_refreshed', 'true',
    'replace_status', 'active',
    'replace_judging_opened', 'false',
    'replace_battle_status', 'active',
    'replace_locked', 'SUBMISSION_LOCKED',
    'replace_path_kept', 'p2.jpg',
    -- ** W1 **: 어긋남 구간의 포기는 거부되고 그 판은 **승리**로 끝난다.
    -- (옛 기대값은 forfeit_shape='finished/true/true'(승자 봇/포기 나) + forfeit_outcome='forfeit/-1'
    --  이었다. 그것이 버그를 정답으로 고정해 두고 있었다.)
    'forfeit_refused', 'BOT_ALREADY_SETTLED',
    'forfeit_shape', 'finished/true/true',      -- 종결 / 승자는 나 / 아무도 포기하지 않았다
    'forfeit_outcome', 'win/1',
    'limit_after_settle', 'BOT_DAILY_LIMIT',
    'limit_used_after_settle', '3'
  );

  v_expected := v_expected || jsonb_build_object(
    -- 4. KST 경계
    'limit_kst_used', '2',
    'limit_kst_left', '1',
    -- 5. t_bot 전
    'idle_accept_opened', 'false',
    'idle_accept_status', 'active',
    'idle_settled', '0',
    'idle_status', 'active',
    'reveal_before', '1',
    'reveal_tbot_hidden', 'true',
    'reveal_ts_columns', '6',
    -- 6. 승리
    'win_settled_any', 'true',
    'win_shape', 'finished/true/true',
    'win_user_outcome', 'win/1',
    'win_bot_outcome', 'completed_loss/null/true/true',
    'win_bot_stats_rows', '0',
    'judgment_rows', '2',
    'judgment_auto', 'true/true/true',
    'judgment_verdict_source', 'true/true',
    'reveal_after', '2',
    -- 7. 완료한 패배
    'cl_accept_opened', 'true',
    'cl_accept_status', 'finished',
    'cl_shape', 'finished/true',
    'cl_outcome', 'completed_loss/-1'
  );

  v_expected := v_expected || jsonb_build_object(
    -- 8. 완료 못 한 패배
    'loss_settled_any', 'true',
    'loss_shape', 'finished/true',
    'loss_outcome', 'loss/-1',
    'loss_judgments', '1/true',
    -- 9·12. 동의
    'consent_settle', 'finished',
    'consent_rows', '0',
    'consent_outcome', 'win/1',
    'consent_stats', '1/0/0/0',
    'consent_create_battle', 'CONSENT_REQUIRED',
    'consent_join_battle', 'CONSENT_REQUIRED',
    'consent_impact_active', '0',
    'consent_impact_pending', '0',
    'consent_withdraw_forfeited', '0',
    'consent_withdraw_cancelled', '0',
    'consent_idle_kept', 'active',
    -- 10. 합격선
    'gate_criteria_checks', '0',
    'gate_criteria_calls', '0',
    'gate_cache_delta', '0',
    'gate_jobs_delta', '0',
    'gate_jobs_mine', '0',
    'gate_criteria_left', '10',
    'gate_draw_voided', '0',
    'tbot_ratio_ok', 'true'
  );

  v_expected := v_expected || jsonb_build_object(
    -- 11. 알림
    'notify_kinds', 'finished',
    'notify_bot_rows', '0',
    -- 3 -> 4. v_b_lock이 포기가 아니라 **내 승리**로 끝나므로 종결 알림이 하나 더 쌓인다.
    'notify_user_rows', '4',
    'notify_lock_rows', '1',
    'notify_is_bot_flag', 'true',
    -- 13. 탈퇴
    'delete_status', 'cancelled/null',
    'delete_outcomes', '2/2/2',
    'delete_notifications', '0',
    -- 14. 봇 노출
    'expose_player_card', 'BOT_NO_STATS',
    'expose_recruits', '0',
    'expose_bot_deleted_at', 'true',
    -- 15. 사람 대결 회귀
    'human_shape', 'finished/true/false',
    'human_c_outcome', 'win/3',
    'human_d_outcome', 'completed_loss/-1',
    'human_c_stats', '13/1/0/0',
    'human_d_stats', '9/0/1/0',
    'human_kinds', 'finished,judge_turn,submitted',
    'human_verdict_source', 'opponent',
    -- 8 -> 9. W1이 v_b_lock의 -1을 +1로 바꾸고(+2), 섹션 12b의 진짜 포기가 -1을 더한다.
    -- 10 +1(v_b_lock 승) +1(v_b_win 승) -1(완료한 패배) -1(완료 못 한 패배) -1(포기) = 9.
    -- 승/패/무는 전부 봇전이라 0/0/0 그대로다(사람 대결은 v_c·v_d가 치렀다).
    'a_stats', '9/0/0/0',
    'e_stats_rows', '0',
    -- 16. 권한
    'perm_start_anon', 'rejected',
    'perm_settle_due', 'rejected',
    'perm_settle_one', 'rejected',
    'perm_daily_used', 'rejected',
    'perm_score_delta', 'rejected',
    'perm_list_topics', 'allowed',
    'perm_settle_mine', 'allowed',
    'perm_topics_rows', '0'
  );

  v_expected := v_expected || jsonb_build_object(
    -- 12b. 증거 규칙(봇전에서도 그대로) + 진짜 포기
    -- 앞의 두 건은 hint가 없어 메시지로 받는다(그 두 가드는 migration에서 hint 없이 raise한다).
    'evidence_no_captured', '촬영 시각이 필요합니다.',
    'evidence_no_path', '사진 경로가 필요합니다.',
    'evidence_before_start', 'CAPTURED_BEFORE_START',
    'evidence_mismatch', 'CAPTURE_TIME_MISMATCH',
    'evidence_kept', 'active/1/p.jpg',
    'forfeit_idle_shape', 'finished/true/true',   -- 종결 / 승자는 봇 / 포기한 사람은 나
    'forfeit_idle_outcome', 'forfeit/-1',
    'forfeit_idle_notify', '0',
    'forfeit_idle_limit_used', '2',
    -- 17. 벽 두 겹 + 양성 대조
    'judge_wall_finished', 'JUDGING_NOT_OPEN',
    'judge_wall_forced', 'ALREADY_JUDGED',
    'judge_gap_status', 'judging',
    'judge_gap_jobs', '1/min_criteria/true',
    -- 18. 안전망(design §3.1 B10)이 섹션 6과 같은 결론을 낸다
    'safety_closed_any', 'true',
    'safety_shape', 'finished/true/true',
    'safety_outcome', 'win/1',
    'safety_judgments', '2/true/true',
    'safety_verdict_source', '2/true/true',
    'safety_jobs', '0',
    'safety_stats', '3/0/0/0'
  );

  select coalesce(string_agg(format('%s expected=%s actual=%s', e.key, e.value, coalesce(a.value::text, 'null')), '; '), '')
  into v_diff
  from jsonb_each(v_expected) e
  left join jsonb_each(v_actual) a on a.key = e.key
  where a.value is distinct from e.value;

  raise exception 'SMOKE RESULT ok=% % (settle_due=%, settle_expired=%)', v_diff = '',
    case when v_diff = '' then '' else ' FAILURES: ' || v_diff end,
    v_settle_due, v_settle_exp;
end $$;
