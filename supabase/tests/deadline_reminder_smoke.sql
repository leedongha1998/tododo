-- 마감 임박 알림(N6) 스모크 테스트 (push-notification 6단계 기준).
--
-- 로컬에 Docker가 없어 원격 DB에 직접 돌린다:
--   supabase db query --linked -f supabase/tests/deadline_reminder_smoke.sql
--
-- 임시 사용자 A·B(사람 대결 쌍), C(상대 없는 모집), U(봇전)를 만들고 대결을 직접 넣어 부른다.
-- 마지막에 일부러 예외를 던져 트랜잭션 전체를 롤백한다. 결과:
--   SMOKE RESULT ok=t                       -> 통과(Postgres는 boolean을 t로 찍는다)
--   SMOKE RESULT ok=f FAILURES: ...         -> 어긋난 항목(기대값/실제값)
--
-- ** 같은 트랜잭션에서는 now()가 고정이다. ** 그래서 "남은 시간"은 deadline_at을 now() 기준
-- 상대값으로 넣어 만든다(started_at = deadline_at - 기간). 경계 케이스도 같은 방식이다.
--
-- ** 호출과 읽기를 한 statement에 두지 않는다. ** enqueue_deadline_reminders()·claim_notifications()는
-- 변수로 먼저 받고, 원장은 다음 statement에서 읽는다. 한 jsonb_build_object 안에서 함께 하면 읽기가
-- statement 시작 스냅샷을 봐서 호출 전 값을 읽는다(봇전 스모크에서 실제로 났다).
--
-- 두 함수는 전역을 훑는다. 원격에 다른 사용자의 진행 중 대결이 있으면 첫 실행 반환값이 이 스모크의
-- 대상 수보다 클 수 있으므로 "이상"으로 본다. 두 번째 실행은 정확히 0이어야 한다(now()가 고정이라
-- 후보가 전부 이미 원장에 있다). 원장 검증은 전부 이 스모크가 만든 대결만 본다.
--
-- 확인하는 것 (plan.md 6단계, 2026-11-24 오너 결정)
--   대상     품질전 미제출 O / 제출 X, 속도전 미제출 O / 제출 X (두 유형 같은 조건)
--   제외     pending(마감 null)·judging·finished·마감 경과 X
--   문턱     min(6시간, 기간의 절반): 3일 대결 6h1m 남음 X / 5h59m 남음 O,
--            60분 대결 31분 남음 X / 30분 남음 O(경계 포함) / 29분 남음 O
--   봇전     사용자 O, 봇은 수신자가 아님, t_bot이 앞이든 마감 직전이든 이미 지났든 결과가 같음,
--            문턱 밖이면 t_bot이 문턱 안에 있어도 X, 사용자가 냈으면 X
--   한 번만  두 번째 실행 0행
--   모양     kind·dedup_key·payload 키 셋(title·battle_type·deadline_at)
--   폐기     쌓인 뒤 마감이 지나거나 active가 아니게 되면 claim_notifications가 dropped,
--            아직 유효한 행은 dropped가 아님
--   cron     notify-tick이 적재 -> 발송 순으로 부르고 1분 주기·active, 작업 수 5개 전부 1분
--   권한     anon·authenticated 실행 불가, service_role 실행 가능
do $$
declare
  v_bot uuid := public.bot_user_id();
  v_a uuid := gen_random_uuid();
  v_b uuid := gen_random_uuid();
  v_c uuid := gen_random_uuid();
  v_u uuid := gen_random_uuid();
  v_topic uuid;

  v_q1 uuid := gen_random_uuid();   -- 품질전 3h 남음: A 미제출 O, B 제출 X
  v_s1 uuid := gen_random_uuid();   -- 속도전 3h 남음: A 제출 X, B 미제출 O
  v_p1 uuid := gen_random_uuid();   -- pending 모집(마감 null)
  v_j1 uuid := gen_random_uuid();   -- judging, 마감 1h 남음
  v_f1 uuid := gen_random_uuid();   -- finished, 마감 1h 남음
  v_e1 uuid := gen_random_uuid();   -- active인데 마감 1분 경과(정산 전)
  v_l1 uuid := gen_random_uuid();   -- 3일 대결 6h1m 남음: X
  v_l2 uuid := gen_random_uuid();   -- 3일 대결 5h59m 남음: O
  v_h1 uuid := gen_random_uuid();   -- 60분 대결 31분 남음: X
  v_h2 uuid := gen_random_uuid();   -- 60분 대결 30분 남음: O(경계)
  v_h3 uuid := gen_random_uuid();   -- 60분 대결 29분 남음: O
  v_bb1 uuid := gen_random_uuid();  -- 봇전 10분, 4분 남음, t_bot 30초 뒤
  v_bb2 uuid := gen_random_uuid();  -- 봇전 10분, 4분 남음, t_bot 마감 1초 전
  v_bb3 uuid := gen_random_uuid();  -- 봇전 10분, 6분 남음, t_bot 1분 뒤(문턱 안): X
  v_bb4 uuid := gen_random_uuid();  -- 봇전 10분, 6분 남음, t_bot 마감 1초 전: X
  v_bb5 uuid := gen_random_uuid();  -- 봇전 10분, 4분 남음, 사용자가 이미 냄: X
  v_bb6 uuid := gen_random_uuid();  -- 봇전 10분, 4분 남음, t_bot 30초 전(정산 전 어긋남 구간)

  v_ours uuid[];
  v_first integer;
  v_second integer;
  v_our_rows integer;
  v_claim jsonb;
  v_claim_count integer;

  v_job_schedule text;
  v_job_command text;
  v_job_active boolean;
  v_job_count integer;
  v_job_not_every_minute integer;

  v_actual jsonb;
  v_expected jsonb;
  v_diff text;
begin
  insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  select u.id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
         u.email, jsonb_build_object('full_name', u.name), now(), now()
  from (values
    (v_a, 'deadline-smoke-a@example.invalid', '임박A'),
    (v_b, 'deadline-smoke-b@example.invalid', '임박B'),
    (v_c, 'deadline-smoke-c@example.invalid', '임박C'),
    (v_u, 'deadline-smoke-u@example.invalid', '임박U')
  ) as u(id, email, name);

  -- 봇전 행에는 주제가 짝으로 붙어야 한다(battles_bot_topic_pair_check). 어느 주제든 된다 -
  -- 기간은 아래에서 직접 정하고, 주제의 기간과 맞아야 한다는 제약은 없다.
  select id into v_topic from public.bot_battle_topics order by active desc, id limit 1;

  v_ours := array[v_q1, v_s1, v_p1, v_j1, v_f1, v_e1, v_l1, v_l2, v_h1, v_h2, v_h3,
                  v_bb1, v_bb2, v_bb3, v_bb4, v_bb5, v_bb6];

  -- 발송 폐기 검증(뒤)에 쓸 기기 토큰. 토큰이 없으면 claim이 "받을 기기 없음"으로 전부 dropped로
  -- 내려 마감 경과 폐기 조건을 가릴 수 없다.
  insert into public.device_push_tokens (token, user_id) values ('deadline-smoke-token-a', v_a);

  -- ---------------------------------------------------------------------
  -- 대결: 마감은 now() + 남은 시간, 시작은 마감 - 기간
  -- ---------------------------------------------------------------------
  insert into public.battles (
    id, type, status, title, creator_id, opponent_id, duration_minutes,
    min_criteria, superiority_criteria, started_at, deadline_at,
    judging_opened_at, judge_deadline_at, winner_id, is_bot, bot_topic_id
  )
  select
    v.id, v.type, v.status, v.title, v.creator, v.opponent, v.mins,
    '["책상 위가 한눈에 보인다"]'::jsonb,
    case when v.type = 'quality' then '["물건이 더 반듯하게 정리됐다"]'::jsonb end,
    case when v.left_ is not null then now() + v.left_ - make_interval(mins => v.mins) end,
    case when v.left_ is not null then now() + v.left_ end,
    case when v.status = 'judging' then now() end,
    case when v.status = 'judging' then now() + v.left_ + interval '24 hours' end,
    case when v.status = 'finished' then v.creator end,
    v.is_bot,
    case when v.is_bot then v_topic end
  from (values
    (v_q1,  'quality', 'active',   '임박 품질전',      v_a, v_b,   1440, interval '3 hours',              false),
    (v_s1,  'speed',   'active',   '임박 속도전',      v_a, v_b,   1440, interval '3 hours',              false),
    (v_p1,  'speed',   'pending',  '임박 모집',        v_c, null,    60, null,                            false),
    (v_j1,  'speed',   'judging',  '임박 판정 중',     v_a, v_b,   1440, interval '1 hour',               false),
    (v_f1,  'speed',   'finished', '임박 종결',        v_a, v_b,   1440, interval '1 hour',               false),
    (v_e1,  'speed',   'active',   '임박 마감 경과',   v_a, v_b,   1440, interval '-1 minute',            false),
    (v_l1,  'speed',   'active',   '임박 3일 6h1m',    v_a, v_b,   4320, interval '6 hours 1 minute',     false),
    (v_l2,  'speed',   'active',   '임박 3일 5h59m',   v_a, v_b,   4320, interval '5 hours 59 minutes',   false),
    (v_h1,  'speed',   'active',   '임박 60분 31m',    v_a, v_b,     60, interval '31 minutes',           false),
    (v_h2,  'speed',   'active',   '임박 60분 30m',    v_a, v_b,     60, interval '30 minutes',           false),
    (v_h3,  'speed',   'active',   '임박 60분 29m',    v_a, v_b,     60, interval '29 minutes',           false),
    (v_bb1, 'speed',   'active',   '임박 봇 1',        v_u, v_bot,   10, interval '4 minutes',            true),
    (v_bb2, 'speed',   'active',   '임박 봇 2',        v_u, v_bot,   10, interval '4 minutes',            true),
    (v_bb3, 'speed',   'active',   '임박 봇 3',        v_u, v_bot,   10, interval '6 minutes',            true),
    (v_bb4, 'speed',   'active',   '임박 봇 4',        v_u, v_bot,   10, interval '6 minutes',            true),
    (v_bb5, 'speed',   'active',   '임박 봇 5',        v_u, v_bot,   10, interval '4 minutes',            true),
    (v_bb6, 'speed',   'active',   '임박 봇 6',        v_u, v_bot,   10, interval '4 minutes',            true)
  ) as v(id, type, status, title, creator, opponent, mins, left_, is_bot);

  -- battles_create_participants 트리거가 생성자 행을 이미 만든다. 상대(사람 또는 봇) 행만 넣는다.
  insert into public.battle_participants (battle_id, user_id)
  select b.id, b.opponent_id
  from public.battles b
  where b.id = any(v_ours) and b.opponent_id is not null;

  -- 사람 제출: 품질전 B, 속도전 A, 봇전 5의 U. 촬영 시각은 사람 행에 필수다.
  insert into public.battle_submissions (battle_id, user_id, object_path, captured_at)
  values
    (v_q1,  v_b, v_q1::text  || '/' || v_b::text || '/1.jpg', now()),
    (v_s1,  v_a, v_s1::text  || '/' || v_a::text || '/1.jpg', now()),
    (v_bb5, v_u, v_bb5::text || '/' || v_u::text || '/1.jpg', now());

  -- 봇 제출 행: 사진도 촬영 시각도 없고 submitted_at이 t_bot이다(start_bot_battle과 같은 모양).
  insert into public.battle_submissions (battle_id, user_id, object_path, captured_at, submitted_at)
  values
    (v_bb1, v_bot, null, null, now() + interval '30 seconds'),
    (v_bb2, v_bot, null, null, now() + interval '4 minutes' - interval '1 second'),
    (v_bb3, v_bot, null, null, now() + interval '1 minute'),
    (v_bb4, v_bot, null, null, now() + interval '6 minutes' - interval '1 second'),
    (v_bb5, v_bot, null, null, now() + interval '3 minutes'),
    (v_bb6, v_bot, null, null, now() - interval '30 seconds');

  -- ---------------------------------------------------------------------
  -- 적재: 호출은 변수로 먼저 받는다
  -- ---------------------------------------------------------------------
  v_first := public.enqueue_deadline_reminders();

  select count(*) into v_our_rows
  from public.notification_outbox
  where battle_id = any(v_ours);

  -- 대결·수신자별 행 수. 키가 없으면 0이다.
  v_actual := jsonb_build_object(
    'first_covers_ours', v_first >= v_our_rows,
    'our_rows', v_our_rows,
    'non_deadline_kind_rows', (select count(*) from public.notification_outbox o
                               where o.battle_id = any(v_ours) and o.kind <> 'deadline_soon'),
    'q1_unsubmitted_a', (select count(*) from public.notification_outbox o
                         where o.battle_id = v_q1 and o.recipient_id = v_a),
    'q1_submitted_b', (select count(*) from public.notification_outbox o
                       where o.battle_id = v_q1 and o.recipient_id = v_b),
    's1_submitted_a', (select count(*) from public.notification_outbox o
                       where o.battle_id = v_s1 and o.recipient_id = v_a),
    's1_unsubmitted_b', (select count(*) from public.notification_outbox o
                         where o.battle_id = v_s1 and o.recipient_id = v_b),
    'pending_rows', (select count(*) from public.notification_outbox o where o.battle_id = v_p1),
    'judging_rows', (select count(*) from public.notification_outbox o where o.battle_id = v_j1),
    'finished_rows', (select count(*) from public.notification_outbox o where o.battle_id = v_f1),
    'expired_rows', (select count(*) from public.notification_outbox o where o.battle_id = v_e1)
  );

  v_actual := v_actual || jsonb_build_object(
    'long_6h01m_rows', (select count(*) from public.notification_outbox o where o.battle_id = v_l1),
    'long_5h59m_rows', (select count(*) from public.notification_outbox o where o.battle_id = v_l2),
    'half_31m_rows', (select count(*) from public.notification_outbox o where o.battle_id = v_h1),
    'half_30m_rows', (select count(*) from public.notification_outbox o where o.battle_id = v_h2),
    'half_29m_rows', (select count(*) from public.notification_outbox o where o.battle_id = v_h3),
    'bot_tbot_soon_user', (select count(*) from public.notification_outbox o
                           where o.battle_id = v_bb1 and o.recipient_id = v_u),
    'bot_tbot_late_user', (select count(*) from public.notification_outbox o
                           where o.battle_id = v_bb2 and o.recipient_id = v_u),
    'bot_tbot_past_user', (select count(*) from public.notification_outbox o
                           where o.battle_id = v_bb6 and o.recipient_id = v_u),
    'bot_battle_rows', (select count(*) from public.notification_outbox o
                        where o.battle_id in (v_bb1, v_bb2, v_bb6)),
    'bot_outside_rows', (select count(*) from public.notification_outbox o
                         where o.battle_id in (v_bb3, v_bb4)),
    'bot_user_submitted_rows', (select count(*) from public.notification_outbox o
                                where o.battle_id = v_bb5),
    'bot_recipient_rows', (select count(*) from public.notification_outbox o
                           where o.battle_id = any(v_ours) and o.recipient_id = v_bot)
  );

  -- 모양: 품질전 A의 행 하나로 본다.
  v_actual := v_actual || coalesce((
    select jsonb_build_object(
      'shape_kind', o.kind,
      'shape_dedup_key', o.dedup_key = 'deadline:' || v_q1::text,
      'shape_status', o.status,
      'shape_payload_keys', (select jsonb_agg(t.k order by t.k) from jsonb_object_keys(o.payload) as t(k)),
      'shape_battle_type', o.payload->>'battle_type',
      'shape_title', o.payload->>'title',
      'shape_deadline_matches', (o.payload->>'deadline_at')::timestamptz
                                = (select b.deadline_at from public.battles b where b.id = v_q1)
    )
    from public.notification_outbox o
    where o.battle_id = v_q1 and o.recipient_id = v_a
  ), '{}'::jsonb);

  -- 한 번만: 같은 시각(now() 고정)에 다시 부르면 후보가 전부 이미 원장에 있다.
  v_second := public.enqueue_deadline_reminders();

  v_actual := v_actual || jsonb_build_object(
    'second_run', v_second,
    'our_rows_after_second', (select count(*) from public.notification_outbox o
                              where o.battle_id = any(v_ours))
  );

  -- ---------------------------------------------------------------------
  -- 폐기: 쌓인 뒤 보낼 이유가 사라지면 claim_notifications가 dropped로 내린다
  -- ---------------------------------------------------------------------
  -- 품질전은 마감이 지난 것으로, 3일 대결은 판정 창이 열린 것으로 만든다. 60분 29m 대결의 A 행은
  -- 그대로 유효하다(A에게 기기 토큰이 있으므로 "받을 기기 없음"으로도 내려가지 않는다).
  update public.battles set deadline_at = now() - interval '1 second' where id = v_q1;
  update public.battles
  set status = 'judging', judging_opened_at = now(), judge_deadline_at = now() + interval '1 day'
  where id = v_l2;

  -- 전역을 임대한다. 원격의 다른 pending 행이 많으면 이 스모크의 유효 행이 이번 묶음에 안 들 수
  -- 있으므로 그 행은 "dropped가 아니다"로만 본다. 임대된 행은 끝의 롤백으로 되돌아간다.
  v_claim := public.claim_notifications(500);

  v_actual := v_actual || jsonb_build_object(
    'claim_returned_array', jsonb_typeof(v_claim) = 'array',
    'drop_after_deadline', (select o.status from public.notification_outbox o
                            where o.battle_id = v_q1 and o.recipient_id = v_a),
    'drop_not_active', (select o.status from public.notification_outbox o
                        where o.battle_id = v_l2 and o.recipient_id = v_a),
    'live_not_dropped', (select o.status <> 'dropped' from public.notification_outbox o
                         where o.battle_id = v_h3 and o.recipient_id = v_a)
  );

  -- ---------------------------------------------------------------------
  -- cron·권한
  -- ---------------------------------------------------------------------
  select schedule, command, active
  into v_job_schedule, v_job_command, v_job_active
  from cron.job where jobname = 'notify-tick';

  select count(*), count(*) filter (where schedule <> '* * * * *')
  into v_job_count, v_job_not_every_minute
  from cron.job;

  v_actual := v_actual || jsonb_build_object(
    'cron_schedule', v_job_schedule,
    'cron_active', v_job_active,
    'cron_calls_enqueue', position('public.enqueue_deadline_reminders()' in v_job_command) > 0,
    'cron_calls_dispatch', position('public.dispatch_notifications()' in v_job_command) > 0,
    'cron_enqueue_first', position('public.enqueue_deadline_reminders()' in v_job_command) > 0
      and position('public.enqueue_deadline_reminders()' in v_job_command)
          < position('public.dispatch_notifications()' in v_job_command),
    'cron_job_count', v_job_count,
    'cron_not_every_minute', v_job_not_every_minute,
    'anon_execute', has_function_privilege('anon', 'public.enqueue_deadline_reminders()', 'execute'),
    'authenticated_execute',
      has_function_privilege('authenticated', 'public.enqueue_deadline_reminders()', 'execute'),
    'service_role_execute',
      has_function_privilege('service_role', 'public.enqueue_deadline_reminders()', 'execute')
  );

  -- 기대 행 수 11 = 품질전 A 1 + 속도전 B 1 + 3일 5h59m 2 + 60분 30m 2 + 60분 29m 2 + 봇전 사용자 3.
  v_expected := jsonb_build_object(
    'first_covers_ours', true,
    'our_rows', 11,
    'non_deadline_kind_rows', 0,
    'q1_unsubmitted_a', 1,
    'q1_submitted_b', 0,
    's1_submitted_a', 0,
    's1_unsubmitted_b', 1,
    'pending_rows', 0,
    'judging_rows', 0,
    'finished_rows', 0,
    'expired_rows', 0,
    'long_6h01m_rows', 0,
    'long_5h59m_rows', 2,
    'half_31m_rows', 0,
    'half_30m_rows', 2,
    'half_29m_rows', 2,
    'bot_tbot_soon_user', 1,
    'bot_tbot_late_user', 1,
    'bot_tbot_past_user', 1,
    'bot_battle_rows', 3,
    'bot_outside_rows', 0,
    'bot_user_submitted_rows', 0,
    'bot_recipient_rows', 0,
    'shape_kind', 'deadline_soon',
    'shape_dedup_key', true,
    'shape_status', 'pending',
    'shape_payload_keys', jsonb_build_array('battle_type', 'deadline_at', 'title'),
    'shape_battle_type', 'quality',
    'shape_title', '임박 품질전',
    'shape_deadline_matches', true
  ) || jsonb_build_object(
    'second_run', 0,
    'our_rows_after_second', 11,
    'claim_returned_array', true,
    'drop_after_deadline', 'dropped',
    'drop_not_active', 'dropped',
    'live_not_dropped', true,
    'cron_schedule', '* * * * *',
    'cron_active', true,
    'cron_calls_enqueue', true,
    'cron_calls_dispatch', true,
    'cron_enqueue_first', true,
    'cron_job_count', 5,
    'cron_not_every_minute', 0,
    'anon_execute', false,
    'authenticated_execute', false,
    'service_role_execute', true
  );

  select coalesce(string_agg(format('%s expected=%s actual=%s', e.key, e.value, coalesce(a.value::text, 'null')), '; '), '')
  into v_diff
  from jsonb_each(v_expected) e
  left join jsonb_each(v_actual) a on a.key = e.key
  where a.value is distinct from e.value;

  raise exception 'SMOKE RESULT ok=% %', v_diff = '',
    case when v_diff = '' then '' else ' FAILURES: ' || v_diff end;
end $$;
