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
-- settle_due_bot_battles()·settle_expired_battles()는 전역을 훑으므로 반환값은 '1 이상'으로만
-- 본다(원격에 다른 사용자의 밀린 대결이 있으면 더 클 수 있다). 바뀐 행은 롤백된다.
--
-- 확인하는 것 (design.md §14 "bot_battle_flow_smoke.sql 필수 확인" 1~15과 1:1)
--   start_*        시작 1판의 모양: active·speed·마감·기준 복사·참가자 2행·사진 없는 봇 제출 행
--   tbot_*         t_bot이 기간의 50~85%, 마감보다 앞, 사용자에게 보이지 않음
--   limit_*        하루 3회, 4번째 거부, KST 경계로 초기화, 포기해도 돌아오지 않음
--   replace_*      t_bot 전 교체 가능 + 제출 시각 갱신 / t_bot 뒤 SUBMISSION_LOCKED
--   win_*          봇보다 먼저 냄 -> 승리 +1, 전적 카운터는 그대로, 봇 점수 행 없음
--   cl_*           t_bot 뒤 첫 제출 -> **그 트랜잭션에서** 종결, 완료한 패배 -1
--   loss_*         미제출 + 마감 -> 완료 못 한 패배 -1, 봇의 판정 행은 만들지 않는다
--   forfeit_*      포기 -> 봇이 승자, -1
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
  v_reveal_before integer := -1;
  v_reveal_after integer := -1;
  v_topics_rows integer := -1;
  v_recruit_bot integer;

  v_limit_4th text := '(거부되지 않음)';
  v_limit_after_forfeit text := '(거부되지 않음)';
  v_lock_err text := '(거부되지 않음)';
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
  -- 3. 교체(t_bot 전) -> 제출 시각 갱신 -> t_bot 뒤 잠김 -> 포기
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

  -- 포기(빠져나가는 유일한 길). 봇이 승자가 되고 사용자는 -1이다.
  perform public.forfeit_battle(v_b_lock);

  begin
    perform public.start_bot_battle(v_topic);
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    v_limit_after_forfeit := coalesce(v_hint, '(힌트 없음)');
  end;

  v_actual := v_actual || jsonb_build_object(
    'forfeit_shape', (select concat_ws('/', b.status, (b.winner_id = v_bot)::text,
                                       (b.forfeited_by = v_a)::text)
                      from public.battles b where b.id = v_b_lock),
    'forfeit_outcome', (select concat_ws('/', outcome, score_delta_applied::text)
                        from public.battle_participants
                        where battle_id = v_b_lock and user_id = v_a),
    'limit_after_forfeit', v_limit_after_forfeit,
    'limit_used_after_forfeit', public.bot_daily_battles_used(v_a)::text
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

  v_actual := v_actual || jsonb_build_object(
    'consent_settle', public.settle_bot_battle(v_b_nc),
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
    -- 승리·완료한 패배·완료 못 한 패배 셋. 포기는 본인에게 보내지 않고 상대는 봇이라 0행이다.
    'notify_user_rows', (select count(*)::text from public.notification_outbox
                         where recipient_id = v_a and kind = 'finished'),
    'notify_forfeit_rows', (select count(*)::text from public.notification_outbox
                            where battle_id = v_b_lock),
    'notify_is_bot_flag', (select bool_and((payload ->> 'is_bot')::boolean)::text
                           from public.notification_outbox
                           where battle_id in (v_b_win, v_b_cl, v_b_loss) and kind = 'finished')
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
  -- 기대값
  -- -------------------------------------------------------------------------
  -- v_a 점수: 10 -1(포기) +1(승) -1(완료한 패배) -1(완료 못 한 패배) = 8, 전적은 0/0/0 그대로
  -- v_b 점수: 0 +1(승) = 1
  -- v_c 점수: 10 +3 = 13(승 1), v_d 점수: 10 -1 = 9(패 1)  <- 사람 대결 표 그대로
  --
  -- ** 네 묶음으로 쪼개 쓴다. ** PostgreSQL 함수의 인자 상한은 100개라(FUNC_MAX_ARGS)
  -- 97개 키를 한 jsonb_build_object에 담으면 194개 인자가 되어 호출 자체가 거부된다.
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
    'forfeit_shape', 'finished/true/true',
    'forfeit_outcome', 'forfeit/-1',
    'limit_after_forfeit', 'BOT_DAILY_LIMIT',
    'limit_used_after_forfeit', '3'
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
    'notify_user_rows', '3',
    'notify_forfeit_rows', '0',
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
    'a_stats', '8/0/0/0',
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

  select coalesce(string_agg(format('%s expected=%s actual=%s', e.key, e.value, coalesce(a.value::text, 'null')), '; '), '')
  into v_diff
  from jsonb_each(v_expected) e
  left join jsonb_each(v_actual) a on a.key = e.key
  where a.value is distinct from e.value;

  raise exception 'SMOKE RESULT ok=% % (settle_due=%, settle_expired=%)', v_diff = '',
    case when v_diff = '' then '' else ' FAILURES: ' || v_diff end,
    v_settle_due, v_settle_exp;
end $$;
