-- delete_account() 스모크 테스트 (ai-judge 1단계 기준).
--
-- 로컬에 Docker가 없어 원격 DB에 직접 돌린다:
--   supabase db query --linked -f supabase/tests/delete_account_smoke.sql
--
-- 임시 사용자 U(탈퇴)와 O(남는 상대)를 만들어 U를 실제로 탈퇴시키고, 마지막에 일부러 예외를 던져
-- 트랜잭션 전체를 롤백한다. 결과:
--   SMOKE RESULT ok=true                    -> 통과
--   SMOKE RESULT ok=false FAILURES: ...     -> 어긋난 항목(기대값/실제값)
--
-- 확인하는 것
--   끝나지 않은 대결(오늘 매칭 active, 어제 매칭 active, 모집 중) -> cancelled, outcome 없음
--   이미 끝난 대결 -> 그대로 finished
--   남은 상대 O: 점수 불변(5점), 오늘 매칭 슬롯은 반환(삭제), 어제 매칭 슬롯은 유지
--   U: 슬롯·점수 행 삭제, 제출 행은 남되 object_path null·사유 유지, 투두 삭제, 묘비화, auth 계정 삭제
do $$
declare
  v_u uuid := gen_random_uuid();
  v_o uuid := gen_random_uuid();
  v_today date := (now() at time zone 'Asia/Seoul')::date;
  v_b_today uuid;
  v_b_yday uuid;
  v_b_pending uuid;
  v_b_done uuid;
  v_actual jsonb;
  v_expected jsonb;
  v_diff text;
begin
  insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  values
    (v_u, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'delete-account-smoke-u@example.invalid', '{"full_name":"스모크U"}'::jsonb, now(), now()),
    (v_o, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'delete-account-smoke-o@example.invalid', '{"full_name":"스모크O"}'::jsonb, now(), now());

  update public.player_stats set score = 5 where user_id = v_o;

  insert into public.todos (user_id, title) values (v_u, '테스트 할 일');

  -- 오늘 매칭된 속도전(U 생성). U는 이미 통과했지만 탈퇴하면 그래도 취소다.
  insert into public.battles (min_criteria, superiority_criteria, type, status, title, creator_id, opponent_id, duration_minutes, started_at, deadline_at)
  values ('["상판이 보인다"]'::jsonb, null, 'speed', 'active', '오늘 매칭', v_u, v_o, 4320, now(), now() + interval '3 days')
  returning id into v_b_today;
  insert into public.battle_participants (battle_id, user_id) values (v_b_today, v_o);

  -- 어제 매칭된 품질전(O 생성).
  insert into public.battles (min_criteria, superiority_criteria, type, status, title, creator_id, opponent_id, duration_minutes, started_at, deadline_at)
  values ('["상판이 보인다"]'::jsonb, '["먼지가 없다"]'::jsonb, 'quality', 'active', '어제 매칭', v_o, v_u, 4320, now() - interval '1 day', now() + interval '2 days')
  returning id into v_b_yday;
  insert into public.battle_participants (battle_id, user_id) values (v_b_yday, v_u);

  -- 모집 중(U 생성).
  insert into public.battles (min_criteria, superiority_criteria, type, status, title, creator_id)
  values ('["상판이 보인다"]'::jsonb, null, 'speed', 'pending', '모집 중', v_u)
  returning id into v_b_pending;

  -- 이미 끝난 대결(O 승).
  insert into public.battles (min_criteria, superiority_criteria, type, status, title, creator_id, opponent_id, winner_id, duration_minutes, started_at, deadline_at, finished_at)
  values ('["상판이 보인다"]'::jsonb, null, 'speed', 'finished', '지난 대결', v_u, v_o, v_o, 1440, now() - interval '5 days', now() - interval '4 days', now() - interval '4 days')
  returning id into v_b_done;
  insert into public.battle_participants (battle_id, user_id) values (v_b_done, v_o);

  insert into public.daily_battle_slots (user_id, kst_date, battle_id)
  values
    (v_u, v_today, v_b_today), (v_o, v_today, v_b_today),
    (v_u, v_today - 1, v_b_yday), (v_o, v_today - 1, v_b_yday);

  insert into public.battle_submissions (battle_id, user_id, object_path, captured_at, submitted_at, status, reason)
  values (v_b_today, v_u, v_b_today || '/' || v_u || '/smoke.jpg', now(), now(), 'passed', '책상이 비어 있다');

  -- 이 세션을 U로 위장시킨다 (auth.uid()가 읽는 값).
  perform set_config('request.jwt.claims', json_build_object('sub', v_u, 'role', 'authenticated')::text, true);

  perform public.delete_account();

  v_actual := jsonb_build_object(
    'auth_user_exists', (select exists (select 1 from auth.users where id = v_u)),
    'todos_left', (select count(*) from public.todos where user_id = v_u),
    'profile', (select display_name || '/' || (deleted_at is not null)::text from public.profiles where id = v_u),
    'b_today', (select status from public.battles where id = v_b_today),
    'b_yday', (select status from public.battles where id = v_b_yday),
    'b_pending', (select status from public.battles where id = v_b_pending),
    'b_done', (select status from public.battles where id = v_b_done),
    'cancelled_outcomes', (select count(*) from public.battle_participants
                           where battle_id in (v_b_today, v_b_yday) and outcome is not null),
    'o_score', (select score from public.player_stats where user_id = v_o),
    'o_slot_today', (select count(*) from public.daily_battle_slots where user_id = v_o and kst_date = v_today),
    'o_slot_yday', (select count(*) from public.daily_battle_slots where user_id = v_o and kst_date = v_today - 1),
    'u_slots', (select count(*) from public.daily_battle_slots where user_id = v_u),
    'u_stats_rows', (select count(*) from public.player_stats where user_id = v_u),
    'u_submission', (select coalesce(object_path, '(null)') || '/' || coalesce(reason, '(null)')
                     from public.battle_submissions where user_id = v_u)
  );

  v_expected := jsonb_build_object(
    'auth_user_exists', false,
    'todos_left', 0,
    'profile', '탈퇴한 사용자/true',
    'b_today', 'cancelled',
    'b_yday', 'cancelled',
    'b_pending', 'cancelled',
    'b_done', 'finished',
    'cancelled_outcomes', 0,
    'o_score', 5,
    'o_slot_today', 0,
    'o_slot_yday', 1,
    'u_slots', 0,
    'u_stats_rows', 0,
    'u_submission', '(null)/책상이 비어 있다'
  );

  select coalesce(string_agg(format('%s expected=%s actual=%s', e.key, e.value, coalesce(a.value::text, 'null')), '; '), '')
  into v_diff
  from jsonb_each(v_expected) e
  left join jsonb_each(v_actual) a on a.key = e.key
  where a.value is distinct from e.value;

  raise exception 'SMOKE RESULT ok=% %', v_diff = '',
    case when v_diff = '' then '' else ' FAILURES: ' || v_diff end;
end $$;
