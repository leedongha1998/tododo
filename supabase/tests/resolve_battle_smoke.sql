-- resolve_battle() / void_battle() 스모크 테스트 (mutual-judge 2단계).
--
-- 로컬에 Docker가 없어 원격 DB에 직접 돌린다:
--   supabase db query --linked -f supabase/tests/resolve_battle_smoke.sql
--
-- resolve_battle은 이제 battle_submissions·battle_judgments의 "사실"로 결론을 낸다.
-- 2단계에는 AI 재판정 배선이 없으므로, 불복(reject)의 AI 결과는 battle_submissions.meets_criteria를
-- 직접 채워 흉내 낸다(실제로는 3단계의 record_min_criteria_verdict가 이 값을 채운다).
--
-- 마지막에 일부러 예외를 던져 전체를 롤백한다. 결과:
--   SMOKE RESULT ok=true                    -> 통과
--   SMOKE RESULT ok=false FAILURES: ...     -> 어긋난 항목(기대값/실제값)
--
-- 확인하는 것
--   r1        양쪽 승인, A가 먼저 제출 -> finished/A, A win(+3) / B completed_loss(-1)
--   r1_tie    같은 시각 제출, B 제출이 먼저 기록됨 -> finished/B(생성자 우선이 아니라 seq)
--   r2        A 승인, B 불복+AI 미달 -> 즉시 finished/A, B loss
--   r3        양쪽 불복+AI 미달 -> 즉시 draw
--   r_pending A 승인, B 불복했지만 AI 결과 아직 없음 -> judging 유지(결론 안 남)
--   다시 부르기 종결된 r1에 resolve_battle을 또 불러도 점수가 두 번 반영되지 않음
--   v_today   오늘 매칭된 judging 대결 무효 -> voided, 오늘 슬롯 삭제, 점수 불변
--   v_yday    어제 매칭된 대결 무효 -> voided, 어제 슬롯 유지
--   종결된 대결 무효화는 거부
--   perm_*    anon·authenticated가 내부 전용 함수를 부르면 거부된다
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
  v_r_pending uuid;
  v_v_today uuid;
  v_v_yday uuid;
  v_id uuid;
  v_sub_a bigint;
  v_sub_b bigint;
  v_r1_return text;
  v_r1_again text;
  v_void_finished_rejected boolean := false;
  v_perm_resolve text := '(거부되지 않음)';
  v_perm_void text := '(거부되지 않음)';
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

  -- 하한에 걸리지 않게 10점에서 시작한다.
  update public.player_stats set score = 10 where user_id in (v_a, v_b, v_c, v_d);

  -- r1: A가 먼저 제출, B가 나중. 둘 다 승인.
  insert into public.battles (
    min_criteria, superiority_criteria, type, status, title, creator_id, opponent_id,
    duration_minutes, started_at, deadline_at, judging_opened_at, judge_deadline_at
  )
  values (
    '["상판이 보인다"]'::jsonb, null, 'speed', 'judging', 'resolve 스모크 r1', v_a, v_b,
    4320, now() - interval '1 day', now() + interval '1 day', now(), now() + interval '24 hours'
  )
  returning id into v_r1;
  insert into public.battle_participants (battle_id, user_id) values (v_r1, v_b);
  insert into public.battle_submissions (battle_id, user_id, object_path, captured_at, submitted_at)
  values
    (v_r1, v_a, 'smoke/a.jpg', now() - interval '2 hours', now() - interval '2 hours'),
    (v_r1, v_b, 'smoke/b.jpg', now() - interval '1 hour', now() - interval '1 hour');
  insert into public.battle_judgments (battle_id, judge_id, min_verdict, superior_id, auto)
  values (v_r1, v_a, 'approve', null, false), (v_r1, v_b, 'approve', null, false);

  -- r1_tie: 같은 시각 제출. B 행을 먼저 넣어 seq가 작다.
  insert into public.battles (
    min_criteria, superiority_criteria, type, status, title, creator_id, opponent_id,
    duration_minutes, started_at, deadline_at, judging_opened_at, judge_deadline_at
  )
  values (
    '["상판이 보인다"]'::jsonb, null, 'speed', 'judging', 'resolve 스모크 r1_tie', v_a, v_b,
    4320, now() - interval '1 day', now() + interval '1 day', now(), now() + interval '24 hours'
  )
  returning id into v_r1_tie;
  insert into public.battle_participants (battle_id, user_id) values (v_r1_tie, v_b);
  insert into public.battle_submissions (battle_id, user_id, object_path, captured_at, submitted_at)
  values (v_r1_tie, v_b, 'smoke/b.jpg', now() - interval '1 hour', timestamptz '2026-09-15 09:00:00+09');
  insert into public.battle_submissions (battle_id, user_id, object_path, captured_at, submitted_at)
  values (v_r1_tie, v_a, 'smoke/a.jpg', now() - interval '1 hour', timestamptz '2026-09-15 09:00:00+09');
  insert into public.battle_judgments (battle_id, judge_id, min_verdict, superior_id, auto)
  values (v_r1_tie, v_a, 'approve', null, false), (v_r1_tie, v_b, 'approve', null, false);

  -- r2: A 승인, B 불복 + AI 미달(meets_criteria=false로 흉내).
  insert into public.battles (
    min_criteria, superiority_criteria, type, status, title, creator_id, opponent_id,
    duration_minutes, started_at, deadline_at, judging_opened_at, judge_deadline_at
  )
  values (
    '["상판이 보인다"]'::jsonb, null, 'speed', 'judging', 'resolve 스모크 r2', v_a, v_b,
    4320, now() - interval '1 day', now() + interval '1 day', now(), now() + interval '24 hours'
  )
  returning id into v_r2;
  insert into public.battle_participants (battle_id, user_id) values (v_r2, v_b);
  insert into public.battle_submissions (battle_id, user_id, object_path, captured_at, submitted_at)
  values (v_r2, v_a, 'smoke/a.jpg', now() - interval '3 hours', now() - interval '3 hours');
  insert into public.battle_submissions (
    battle_id, user_id, object_path, captured_at, submitted_at, meets_criteria, verdict_source, reason
  )
  values (v_r2, v_b, 'smoke/b.jpg', now() - interval '3 hours', now() - interval '3 hours',
          false, 'ai', '상판이 보이지 않는다');
  insert into public.battle_judgments (battle_id, judge_id, min_verdict, superior_id, auto)
  values (v_r2, v_a, 'reject', null, false), (v_r2, v_b, 'approve', null, false);

  -- r3: 양쪽 불복 + AI 미달.
  insert into public.battles (
    min_criteria, superiority_criteria, type, status, title, creator_id, opponent_id,
    duration_minutes, started_at, deadline_at, judging_opened_at, judge_deadline_at
  )
  values (
    '["상판이 보인다"]'::jsonb, null, 'speed', 'judging', 'resolve 스모크 r3', v_a, v_b,
    4320, now() - interval '1 day', now() + interval '1 day', now(), now() + interval '24 hours'
  )
  returning id into v_r3;
  insert into public.battle_participants (battle_id, user_id) values (v_r3, v_b);
  insert into public.battle_submissions (
    battle_id, user_id, object_path, captured_at, submitted_at, meets_criteria, verdict_source, reason
  )
  values
    (v_r3, v_a, 'smoke/a.jpg', now() - interval '3 hours', now() - interval '3 hours',
     false, 'ai', '상판이 보이지 않는다'),
    (v_r3, v_b, 'smoke/b.jpg', now() - interval '3 hours', now() - interval '3 hours',
     false, 'ai', '상판이 보이지 않는다');
  insert into public.battle_judgments (battle_id, judge_id, min_verdict, superior_id, auto)
  values (v_r3, v_a, 'reject', null, false), (v_r3, v_b, 'reject', null, false);

  -- r_pending: A는 B의 사진을 승인하고, B는 A의 사진에 불복했지만 AI 결과가 아직 없다
  -- (A의 제출 결론이 pending이 된다 -- 2단계는 여기서 멈춘다. 3단계가 AI 재판정을 배선한다).
  insert into public.battles (
    min_criteria, superiority_criteria, type, status, title, creator_id, opponent_id,
    duration_minutes, started_at, deadline_at, judging_opened_at, judge_deadline_at
  )
  values (
    '["상판이 보인다"]'::jsonb, null, 'speed', 'judging', 'resolve 스모크 r_pending', v_a, v_b,
    4320, now() - interval '1 day', now() + interval '1 day', now(), now() + interval '24 hours'
  )
  returning id into v_r_pending;
  insert into public.battle_participants (battle_id, user_id) values (v_r_pending, v_b);
  insert into public.battle_submissions (battle_id, user_id, object_path, captured_at, submitted_at)
  values
    (v_r_pending, v_a, 'smoke/a.jpg', now() - interval '3 hours', now() - interval '3 hours'),
    (v_r_pending, v_b, 'smoke/b.jpg', now() - interval '3 hours', now() - interval '3 hours');
  insert into public.battle_judgments (battle_id, judge_id, min_verdict, superior_id, auto)
  values (v_r_pending, v_a, 'approve', null, false), (v_r_pending, v_b, 'reject', null, false);

  v_r1_return := public.resolve_battle(v_r1);
  perform public.resolve_battle(v_r1_tie);
  perform public.resolve_battle(v_r2);
  perform public.resolve_battle(v_r3);
  perform public.resolve_battle(v_r_pending);

  -- 종결된 대결에 다시 불러도 아무것도 바뀌지 않아야 한다.
  v_r1_again := public.resolve_battle(v_r1);

  -- 무효: C vs D. 하나는 오늘 매칭, 하나는 어제 매칭. void_battle은 이 단계에서 바뀌지 않았으므로
  -- (3단계가 ai_judgment_jobs 삭제를 더한다) 직접 불러 여전히 올바른지 확인한다.
  insert into public.battles (
    min_criteria, superiority_criteria, type, status, title, creator_id, opponent_id,
    duration_minutes, started_at, deadline_at, judging_opened_at, judge_deadline_at
  )
  values (
    '["상판이 보인다"]'::jsonb, '["먼지가 없다"]'::jsonb, 'quality', 'judging', 'void 오늘', v_c, v_d,
    4320, now(), now() + interval '3 days', now(), now() + interval '24 hours'
  )
  returning id into v_v_today;
  insert into public.battle_participants (battle_id, user_id) values (v_v_today, v_d);
  insert into public.daily_battle_slots (user_id, kst_date, battle_id)
  values (v_c, v_today, v_v_today), (v_d, v_today, v_v_today);

  insert into public.battles (
    min_criteria, superiority_criteria, type, status, title, creator_id, opponent_id,
    duration_minutes, started_at, deadline_at, judging_opened_at, judge_deadline_at
  )
  values (
    '["상판이 보인다"]'::jsonb, '["먼지가 없다"]'::jsonb, 'quality', 'judging', 'void 어제', v_c, v_d,
    4320, now() - interval '1 day', now() + interval '2 days', now(), now() + interval '24 hours'
  )
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

  -- 권한: 내부 전용 함수는 anon·authenticated 어느 쪽도 부를 수 없다.
  begin
    execute 'set local role authenticated';
    perform public.resolve_battle(v_r_pending);
    execute 'reset role';
  exception when insufficient_privilege then
    v_perm_resolve := 'rejected';
  when others then
    v_perm_resolve := '다른 오류: ' || sqlerrm;
  end;
  execute 'reset role';

  begin
    execute 'set local role anon';
    perform public.void_battle(v_r_pending);
    execute 'reset role';
  exception when insufficient_privilege then
    v_perm_void := 'rejected';
  when others then
    v_perm_void := '다른 오류: ' || sqlerrm;
  end;
  execute 'reset role';

  v_actual := jsonb_build_object(
    'r1', (select status || '/' || coalesce(case winner_id when v_a then 'A' when v_b then 'B' end, '-')
                || '/' || coalesce(pa.outcome, '-') || '/' || coalesce(pb.outcome, '-')
          from public.battles b
          left join public.battle_participants pa on pa.battle_id = b.id and pa.user_id = v_a
          left join public.battle_participants pb on pb.battle_id = b.id and pb.user_id = v_b
          where b.id = v_r1),
    'r1_tie', (select status || '/' || coalesce(case winner_id when v_a then 'A' when v_b then 'B' end, '-')
              from public.battles where id = v_r1_tie),
    'r2', (select status || '/' || coalesce(case winner_id when v_a then 'A' when v_b then 'B' end, '-')
          from public.battles where id = v_r2),
    'r3', (select status from public.battles where id = v_r3),
    'r_pending', (select status from public.battles where id = v_r_pending),
    'r1_return', v_r1_return,
    'r1_again', v_r1_again,
    'r1_delta', (select string_agg(coalesce(score_delta_applied::text, '-'), '/' order by user_id = v_b)
                from public.battle_participants where battle_id = v_r1),
    'a_stats', (select concat_ws('/', score, wins, losses, draws) from public.player_stats where user_id = v_a),
    'b_stats', (select concat_ws('/', score, wins, losses, draws) from public.player_stats where user_id = v_b),
    'c_stats', (select concat_ws('/', score, wins, losses, draws) from public.player_stats where user_id = v_c),
    'd_stats', (select concat_ws('/', score, wins, losses, draws) from public.player_stats where user_id = v_d),
    'v_today_status', (select status from public.battles where id = v_v_today),
    'v_yday_status', (select status from public.battles where id = v_v_yday),
    'slots_today_left', (select count(*) from public.daily_battle_slots where battle_id = v_v_today),
    'slots_yday_left', (select count(*) from public.daily_battle_slots where battle_id = v_v_yday),
    'void_finished_rejected', v_void_finished_rejected,
    'perm_resolve', v_perm_resolve,
    'perm_void', v_perm_void,
    'disputed_count', (select count(*) from public.battles
                       where creator_id in (v_a, v_c) and status = 'disputed')
  );

  -- A: 10 +3(r1) -1(r1_tie) +3(r2) -1(r3) = 14, 승2 패1 무1
  -- B: 10 -1(r1) +3(r1_tie) -3(r2) -1(r3) = 8,  승1 패2 무1
  v_expected := jsonb_build_object(
    'r1', 'finished/A/win/completed_loss',
    'r1_tie', 'finished/B',
    'r2', 'finished/A',
    'r3', 'draw',
    'r_pending', 'judging',
    'r1_return', 'finished',
    'r1_again', 'finished',
    'r1_delta', '3/-1',
    'a_stats', '14/2/1/1',
    'b_stats', '8/1/2/1',
    'c_stats', '10/0/0/0',
    'd_stats', '10/0/0/0',
    'v_today_status', 'voided',
    'v_yday_status', 'voided',
    'slots_today_left', 0,
    'slots_yday_left', 2,
    'void_finished_rejected', true,
    'perm_resolve', 'rejected',
    'perm_void', 'rejected',
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
