-- resolve_battle() / void_battle() 스모크 테스트 (마감 전 즉시 종결과 무효 처리).
--
-- 로컬에 Docker가 없어 원격 DB에 직접 돌린다:
--   supabase db query --linked -f supabase/tests/resolve_battle_smoke.sql
--
-- 임시 사용자 넷과 대결을 만들어 service 함수를 직접 부르고, 마지막에 일부러 예외를 던져
-- 트랜잭션 전체를 롤백한다. 결과는 예외 메시지로 돌아온다:
--   SMOKE RESULT ok=true                    -> 통과
--   SMOKE RESULT ok=false FAILURES: ...     -> 어긋난 항목(기대값/실제값)
--
-- 확인하는 것
--   r1        양쪽 통과, A가 먼저 -> finished/A, A win(+3) / B completed_loss(-1)
--   r1_tie    같은 시각 통과, B 제출이 먼저 기록됨 -> finished/B (생성자 우선이 아니라 seq)
--   r2        A 통과, B 불합격 5회 -> 즉시 finished/A, B loss
--   r3        양쪽 불합격 5회 -> 즉시 draw
--   r_cont    A 통과, B 불합격 3회 -> active 유지
--   r_wait    A 통과(1시간 전), B 판정 중(2시간 전 제출) -> active 유지(역전 가능)
--   r_errors  A는 AI 실패만 5회(미산입), B 불합격 5회 -> active 유지(A는 아직 제출 가능)
--   다시 부르기  종결된 r1에 resolve_battle을 또 불러도 점수가 두 번 반영되지 않음
--   v_today   오늘 매칭된 판정 중 대결 무효 -> voided, 오늘 슬롯 삭제, 점수 불변
--   v_yday    어제 매칭된 대결 무효 -> voided, 어제 슬롯 유지
--   종결된 대결 무효화는 거부
do $$
declare
  v_a uuid := gen_random_uuid();
  v_b uuid := gen_random_uuid();
  v_c uuid := gen_random_uuid();
  v_d uuid := gen_random_uuid();
  v_today date := (now() at time zone 'Asia/Seoul')::date;
  v_r1 uuid;
  v_r1_tie uuid;
  v_r2 uuid;
  v_r3 uuid;
  v_r_cont uuid;
  v_r_wait uuid;
  v_r_errors uuid;
  v_v_today uuid;
  v_v_yday uuid;
  v_id uuid;
  v_i integer;
  v_r1_return text;
  v_r1_again text;
  v_void_finished_rejected boolean := false;
  v_actual jsonb;
  v_expected jsonb;
  v_diff text;
begin
  insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  values
    (v_a, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'resolve-smoke-a@example.invalid', '{"full_name":"스모크A"}'::jsonb, now(), now()),
    (v_b, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'resolve-smoke-b@example.invalid', '{"full_name":"스모크B"}'::jsonb, now(), now()),
    (v_c, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'resolve-smoke-c@example.invalid', '{"full_name":"스모크C"}'::jsonb, now(), now()),
    (v_d, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'resolve-smoke-d@example.invalid', '{"full_name":"스모크D"}'::jsonb, now(), now());

  -- 가입 트리거가 점수 행을 만들었는지부터 본다. 하한에 걸리지 않게 10점에서 시작한다.
  update public.player_stats set score = 10 where user_id in (v_a, v_b, v_c, v_d);

  -- 마감 전(내일 마감)인 속도전 A vs B 일곱 개.
  for v_i in 1..7 loop
    insert into public.battles (type, status, title, creator_id, opponent_id, duration_hours, started_at, deadline_at)
    values ('speed', 'active', 'resolve 스모크 ' || v_i, v_a, v_b, 72, now() - interval '1 day', now() + interval '1 day')
    returning id into v_id;

    insert into public.battle_participants (battle_id, user_id) values (v_id, v_b);

    case v_i
      when 1 then v_r1 := v_id;
      when 2 then v_r1_tie := v_id;
      when 3 then v_r2 := v_id;
      when 4 then v_r3 := v_id;
      when 5 then v_r_cont := v_id;
      when 6 then v_r_wait := v_id;
      else v_r_errors := v_id;
    end case;
  end loop;

  -- r1: A 2시간 전 통과, B 1시간 전 통과.
  insert into public.battle_submissions (battle_id, user_id, object_path, captured_at, submitted_at, status)
  values
    (v_r1, v_a, 'smoke/a.jpg', now() - interval '2 hours', now() - interval '2 hours', 'passed'),
    (v_r1, v_b, 'smoke/b.jpg', now() - interval '1 hour', now() - interval '1 hour', 'passed');

  -- r1_tie: 같은 시각. B 행을 먼저 넣어 seq가 작다.
  insert into public.battle_submissions (battle_id, user_id, object_path, captured_at, submitted_at, status)
  values (v_r1_tie, v_b, 'smoke/b.jpg', now() - interval '1 hour', timestamptz '2026-09-15 09:00:00+09', 'passed');
  insert into public.battle_submissions (battle_id, user_id, object_path, captured_at, submitted_at, status)
  values (v_r1_tie, v_a, 'smoke/a.jpg', now() - interval '1 hour', timestamptz '2026-09-15 09:00:00+09', 'passed');

  -- r2: A 통과, B 불합격 5회.
  insert into public.battle_submissions (battle_id, user_id, object_path, captured_at, submitted_at, status)
  values (v_r2, v_a, 'smoke/a.jpg', now() - interval '3 hours', now() - interval '3 hours', 'passed');
  insert into public.battle_submissions (battle_id, user_id, object_path, captured_at, submitted_at, status)
  select v_r2, v_b, 'smoke/b.jpg', now() - make_interval(mins => g), now() - make_interval(mins => g), 'failed'
  from generate_series(1, 5) g;

  -- r3: 양쪽 불합격 5회.
  insert into public.battle_submissions (battle_id, user_id, object_path, captured_at, submitted_at, status)
  select v_r3, u, 'smoke/x.jpg', now() - make_interval(mins => g), now() - make_interval(mins => g), 'failed'
  from generate_series(1, 5) g, unnest(array[v_a, v_b]) u;

  -- r_cont: A 통과, B 불합격 3회.
  insert into public.battle_submissions (battle_id, user_id, object_path, captured_at, submitted_at, status)
  values (v_r_cont, v_a, 'smoke/a.jpg', now() - interval '3 hours', now() - interval '3 hours', 'passed');
  insert into public.battle_submissions (battle_id, user_id, object_path, captured_at, submitted_at, status)
  select v_r_cont, v_b, 'smoke/b.jpg', now() - make_interval(mins => g), now() - make_interval(mins => g), 'failed'
  from generate_series(1, 3) g;

  -- r_wait: A 1시간 전 통과, B는 그보다 이른 2시간 전 제출이 아직 판정 중.
  insert into public.battle_submissions (battle_id, user_id, object_path, captured_at, submitted_at, status, judging_started_at)
  values
    (v_r_wait, v_a, 'smoke/a.jpg', now() - interval '1 hour', now() - interval '1 hour', 'passed', null),
    (v_r_wait, v_b, 'smoke/b.jpg', now() - interval '2 hours', now() - interval '2 hours', 'judging', now());

  -- r_errors: A는 AI 실패만 5회, B는 불합격 5회.
  insert into public.battle_submissions (battle_id, user_id, object_path, captured_at, submitted_at, status)
  select v_r_errors, v_a, 'smoke/a.jpg', now() - make_interval(mins => g), now() - make_interval(mins => g), 'error'
  from generate_series(1, 5) g;
  insert into public.battle_submissions (battle_id, user_id, object_path, captured_at, submitted_at, status)
  select v_r_errors, v_b, 'smoke/b.jpg', now() - make_interval(mins => g), now() - make_interval(mins => g), 'failed'
  from generate_series(1, 5) g;

  v_r1_return := public.resolve_battle(v_r1);
  perform public.resolve_battle(v_r1_tie);
  perform public.resolve_battle(v_r2);
  perform public.resolve_battle(v_r3);
  perform public.resolve_battle(v_r_cont);
  perform public.resolve_battle(v_r_wait);
  perform public.resolve_battle(v_r_errors);

  -- 종결된 대결에 다시 불러도 아무것도 바뀌지 않아야 한다.
  v_r1_again := public.resolve_battle(v_r1);

  -- 무효: C vs D. 하나는 오늘 매칭, 하나는 어제 매칭.
  insert into public.battles (type, status, title, creator_id, opponent_id, duration_hours, started_at, deadline_at)
  values ('quality', 'judging', 'void 오늘', v_c, v_d, 72, now(), now() + interval '3 days')
  returning id into v_v_today;
  insert into public.battle_participants (battle_id, user_id) values (v_v_today, v_d);
  insert into public.daily_battle_slots (user_id, kst_date, battle_id)
  values (v_c, v_today, v_v_today), (v_d, v_today, v_v_today);

  insert into public.battles (type, status, title, creator_id, opponent_id, duration_hours, started_at, deadline_at)
  values ('quality', 'active', 'void 어제', v_c, v_d, 72, now() - interval '1 day', now() + interval '2 days')
  returning id into v_v_yday;
  insert into public.battle_participants (battle_id, user_id) values (v_v_yday, v_d);
  insert into public.daily_battle_slots (user_id, kst_date, battle_id)
  values (v_c, v_today - 1, v_v_yday), (v_d, v_today - 1, v_v_yday);

  perform public.void_battle(v_v_today);
  perform public.void_battle(v_v_yday);

  begin
    perform public.void_battle(v_r1);
  exception when others then
    v_void_finished_rejected := true;
  end;

  select jsonb_object_agg(
           l.name,
           b.status
             || '/' || coalesce(case b.winner_id when v_a then 'A' when v_b then 'B' when v_c then 'C' when v_d then 'D' end, '-')
             || '/' || coalesce(pc.outcome, '-')
             || '/' || coalesce(po.outcome, '-')
         )
  into v_actual
  from unnest(
         array[v_r1, v_r1_tie, v_r2, v_r3, v_r_cont, v_r_wait, v_r_errors, v_v_today, v_v_yday],
         array['r1', 'r1_tie', 'r2', 'r3', 'r_cont', 'r_wait', 'r_errors', 'v_today', 'v_yday']
       ) as l(id, name)
  join public.battles b on b.id = l.id
  left join public.battle_participants pc on pc.battle_id = b.id and pc.user_id = b.creator_id
  left join public.battle_participants po on po.battle_id = b.id and po.user_id = b.opponent_id;

  v_actual := v_actual || jsonb_build_object(
    'r1_return', v_r1_return,
    'r1_again', v_r1_again,
    'r1_delta', (select string_agg(coalesce(score_delta_applied::text, '-'), '/' order by user_id = v_b)
                 from public.battle_participants where battle_id = v_r1),
    'r2_delta', (select string_agg(coalesce(score_delta_applied::text, '-'), '/' order by user_id = v_b)
                 from public.battle_participants where battle_id = v_r2),
    'a_stats', (select concat_ws('/', score, wins, losses, draws) from public.player_stats where user_id = v_a),
    'b_stats', (select concat_ws('/', score, wins, losses, draws) from public.player_stats where user_id = v_b),
    'c_stats', (select concat_ws('/', score, wins, losses, draws) from public.player_stats where user_id = v_c),
    'd_stats', (select concat_ws('/', score, wins, losses, draws) from public.player_stats where user_id = v_d),
    'slots_today_left', (select count(*) from public.daily_battle_slots where battle_id = v_v_today),
    'slots_yday_left', (select count(*) from public.daily_battle_slots where battle_id = v_v_yday),
    'void_finished_rejected', v_void_finished_rejected,
    'disputed_count', (select count(*) from public.battles
                       where status = 'disputed'
                         and id in (v_r1, v_r1_tie, v_r2, v_r3, v_r_cont, v_r_wait, v_r_errors, v_v_today, v_v_yday))
  );

  -- A: 10 +3(r1) -1(r1_tie) +3(r2) -1(r3) = 14, 승2 패1 무1
  -- B: 10 -1(r1) +3(r1_tie) -3(r2) -1(r3) = 8,  승1 패2 무1
  v_expected := jsonb_build_object(
    'r1', 'finished/A/win/completed_loss',
    'r1_tie', 'finished/B/completed_loss/win',
    'r2', 'finished/A/win/loss',
    'r3', 'draw/-/draw/draw',
    'r_cont', 'active/-/-/-',
    'r_wait', 'active/-/-/-',
    'r_errors', 'active/-/-/-',
    'v_today', 'voided/-/-/-',
    'v_yday', 'voided/-/-/-',
    'r1_return', 'finished',
    'r1_again', 'finished',
    'r1_delta', '3/-1',
    'r2_delta', '3/-3',
    'a_stats', '14/2/1/1',
    'b_stats', '8/1/2/1',
    'c_stats', '10/0/0/0',
    'd_stats', '10/0/0/0',
    'slots_today_left', 0,
    'slots_yday_left', 2,
    'void_finished_rejected', true,
    'disputed_count', 0
  );

  select coalesce(string_agg(format('%s expected=%s actual=%s', e.key, e.value, coalesce(a.value::text, 'null')), '; '), '')
  into v_diff
  from jsonb_each(v_expected) e
  left join jsonb_each(v_actual) a on a.key = e.key
  where a.value is distinct from e.value;

  raise exception 'SMOKE RESULT ok=% %', v_diff = '',
    case when v_diff = '' then '' else ' FAILURES: ' || v_diff end;
end $$;
