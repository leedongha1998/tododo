-- settle_expired_battles() 스모크 테스트 (ai-judge 규칙).
--
-- 로컬에 Docker가 없어 원격 DB에 직접 돌린다:
--   supabase db query --linked -f supabase/tests/settle_expired_battles_smoke.sql
--
-- 마감이 지난 대결 일곱 개와 아직 안 지난 대결 하나를 만들어 정리 함수를 돌린다.
-- 마지막에 일부러 예외를 던져 트랜잭션 전체를 롤백하므로 실제 데이터는 남지 않는다.
-- 결과:
--   SMOKE RESULT ok=true                    -> 통과
--   SMOKE RESULT ok=false FAILURES: ...     -> 어긋난 항목(기대값/실제값)
-- settled_total은 참고용이다. 원격에 다른 사용자의 마감 지난 대결이 있으면 5보다 클 수 있다.
--
-- 기대값 (status/winner/A outcome/B outcome)
--   s_one      finished/A/win/loss      A 통과, B 불합격 2회 -> 마감 시 통과한 쪽 승, 상대 완료 못 한 패배
--   s_none     draw/-/draw/draw         아무도 제출 안 함
--   s_errors   draw/-/draw/draw         A는 AI 실패만(판정 횟수·통과 아님)
--   s_wait     active/-/-/-             A 통과, B 판정 중 -> 판정이 끝날 때까지 건너뜀
--   q_one      finished/A/win/loss      품질전 A만 제출 -> AI 판정 없이 A 승
--   q_none     draw/-/draw/draw         품질전 제출 없음
--   q_judging  judging/-/-/-            품질전 판정 중 -> 건너뜀
--   fresh      active/-/-/-             마감 전 -> 건드리지 않음
do $$
declare
  v_a uuid := gen_random_uuid();
  v_b uuid := gen_random_uuid();
  v_s_one uuid;
  v_s_none uuid;
  v_s_errors uuid;
  v_s_wait uuid;
  v_q_one uuid;
  v_q_none uuid;
  v_q_judging uuid;
  v_fresh uuid;
  v_settled integer;
  v_actual jsonb;
  v_expected jsonb;
  v_diff text;
begin
  insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  values
    (v_a, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'settle-smoke-a@example.invalid', '{"full_name":"스모크A"}'::jsonb, now(), now()),
    (v_b, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'settle-smoke-b@example.invalid', '{"full_name":"스모크B"}'::jsonb, now(), now());

  -- 하한에 걸리지 않게 10점에서 시작한다(하한은 forfeit_battle_smoke.sql에서 본다).
  update public.player_stats set score = 10 where user_id in (v_a, v_b);

  insert into public.battles (min_criteria, superiority_criteria, type, status, title, creator_id, opponent_id, duration_minutes, started_at, deadline_at)
  values ('["상판이 보인다"]'::jsonb, null, 'speed', 'active', 'A만 통과', v_a, v_b, 1440, now() - interval '2 days', now() - interval '1 hour')
  returning id into v_s_one;

  insert into public.battles (min_criteria, superiority_criteria, type, status, title, creator_id, opponent_id, duration_minutes, started_at, deadline_at)
  values ('["상판이 보인다"]'::jsonb, null, 'speed', 'active', '아무도 안 냄', v_a, v_b, 1440, now() - interval '2 days', now() - interval '1 hour')
  returning id into v_s_none;

  insert into public.battles (min_criteria, superiority_criteria, type, status, title, creator_id, opponent_id, duration_minutes, started_at, deadline_at)
  values ('["상판이 보인다"]'::jsonb, null, 'speed', 'active', 'AI 실패만', v_a, v_b, 1440, now() - interval '2 days', now() - interval '1 hour')
  returning id into v_s_errors;

  insert into public.battles (min_criteria, superiority_criteria, type, status, title, creator_id, opponent_id, duration_minutes, started_at, deadline_at)
  values ('["상판이 보인다"]'::jsonb, null, 'speed', 'active', '판정 중 대기', v_a, v_b, 1440, now() - interval '2 days', now() - interval '1 hour')
  returning id into v_s_wait;

  insert into public.battles (min_criteria, superiority_criteria, type, status, title, creator_id, opponent_id, duration_minutes, started_at, deadline_at)
  values ('["상판이 보인다"]'::jsonb, '["먼지가 없다"]'::jsonb, 'quality', 'active', '품질전 A만', v_a, v_b, 1440, now() - interval '2 days', now() - interval '1 hour')
  returning id into v_q_one;

  insert into public.battles (min_criteria, superiority_criteria, type, status, title, creator_id, opponent_id, duration_minutes, started_at, deadline_at)
  values ('["상판이 보인다"]'::jsonb, '["먼지가 없다"]'::jsonb, 'quality', 'active', '품질전 없음', v_a, v_b, 1440, now() - interval '2 days', now() - interval '1 hour')
  returning id into v_q_none;

  insert into public.battles (min_criteria, superiority_criteria, type, status, title, creator_id, opponent_id, duration_minutes, started_at, deadline_at)
  values ('["상판이 보인다"]'::jsonb, '["먼지가 없다"]'::jsonb, 'quality', 'judging', '품질전 판정 중', v_a, v_b, 1440, now() - interval '2 days', now() - interval '1 hour')
  returning id into v_q_judging;

  insert into public.battles (min_criteria, superiority_criteria, type, status, title, creator_id, opponent_id, duration_minutes, started_at, deadline_at)
  values ('["상판이 보인다"]'::jsonb, null, 'speed', 'active', '마감 전', v_a, v_b, 1440, now(), now() + interval '1 day')
  returning id into v_fresh;

  -- creator 참가자 행은 트리거가 만든다. opponent 행만 직접 넣는다.
  insert into public.battle_participants (battle_id, user_id)
  values (v_s_one, v_b), (v_s_none, v_b), (v_s_errors, v_b), (v_s_wait, v_b),
         (v_q_one, v_b), (v_q_none, v_b), (v_q_judging, v_b), (v_fresh, v_b);

  insert into public.battle_submissions (battle_id, user_id, object_path, captured_at, submitted_at, status)
  values
    (v_s_one, v_a, 'smoke/a.jpg', now() - interval '10 hours', now() - interval '10 hours', 'passed'),
    (v_s_one, v_b, 'smoke/b1.jpg', now() - interval '9 hours', now() - interval '9 hours', 'failed'),
    (v_s_one, v_b, 'smoke/b2.jpg', now() - interval '8 hours', now() - interval '8 hours', 'failed'),
    (v_s_errors, v_a, 'smoke/a1.jpg', now() - interval '10 hours', now() - interval '10 hours', 'error'),
    (v_s_errors, v_a, 'smoke/a2.jpg', now() - interval '9 hours', now() - interval '9 hours', 'error'),
    (v_s_errors, v_a, 'smoke/a3.jpg', now() - interval '8 hours', now() - interval '8 hours', 'error'),
    (v_s_wait, v_a, 'smoke/a.jpg', now() - interval '5 hours', now() - interval '5 hours', 'passed'),
    (v_q_one, v_a, 'smoke/a.jpg', now() - interval '10 hours', now() - interval '10 hours', 'submitted'),
    (v_q_judging, v_a, 'smoke/a.jpg', now() - interval '10 hours', now() - interval '10 hours', 'submitted'),
    (v_q_judging, v_b, 'smoke/b.jpg', now() - interval '9 hours', now() - interval '9 hours', 'submitted'),
    (v_fresh, v_a, 'smoke/a.jpg', now() - interval '1 minute', now() - interval '1 minute', 'passed');

  -- 마감 2시간 전에 낸 B의 제출이 아직 판정 중(마감 뒤 판정 완료도 인정해야 하므로 기다린다).
  insert into public.battle_submissions (battle_id, user_id, object_path, captured_at, submitted_at, status, judging_started_at)
  values (v_s_wait, v_b, 'smoke/b.jpg', now() - interval '2 hours', now() - interval '2 hours', 'judging', now());

  v_settled := public.settle_expired_battles();

  select jsonb_object_agg(
           l.name,
           b.status
             || '/' || coalesce(case b.winner_id when v_a then 'A' when v_b then 'B' end, '-')
             || '/' || coalesce(pa.outcome, '-')
             || '/' || coalesce(pb.outcome, '-')
         )
  into v_actual
  from unnest(
         array[v_s_one, v_s_none, v_s_errors, v_s_wait, v_q_one, v_q_none, v_q_judging, v_fresh],
         array['s_one', 's_none', 's_errors', 's_wait', 'q_one', 'q_none', 'q_judging', 'fresh']
       ) as l(id, name)
  join public.battles b on b.id = l.id
  left join public.battle_participants pa on pa.battle_id = b.id and pa.user_id = v_a
  left join public.battle_participants pb on pb.battle_id = b.id and pb.user_id = v_b;

  v_actual := v_actual || jsonb_build_object(
    's_one_delta', (select string_agg(coalesce(score_delta_applied::text, '-'), '/' order by user_id = v_b)
                    from public.battle_participants where battle_id = v_s_one),
    'a_stats', (select concat_ws('/', score, wins, losses, draws) from public.player_stats where user_id = v_a),
    'b_stats', (select concat_ws('/', score, wins, losses, draws) from public.player_stats where user_id = v_b),
    'finished_at_set', (select bool_and(finished_at is not null) from public.battles
                        where id in (v_s_one, v_s_none, v_s_errors, v_q_one, v_q_none)),
    'disputed_count', (select count(*) from public.battles
                       where status = 'disputed'
                         and id in (v_s_one, v_s_none, v_s_errors, v_s_wait, v_q_one, v_q_none, v_q_judging, v_fresh))
  );

  -- A: 10 +3(s_one) -1(s_none) -1(s_errors) +3(q_one) -1(q_none) = 13, 승2 패0 무3
  -- B: 10 -3(s_one) -1(s_none) -1(s_errors) -3(q_one) -1(q_none) = 1,  승0 패2 무3
  v_expected := jsonb_build_object(
    's_one', 'finished/A/win/loss',
    's_none', 'draw/-/draw/draw',
    's_errors', 'draw/-/draw/draw',
    's_wait', 'active/-/-/-',
    'q_one', 'finished/A/win/loss',
    'q_none', 'draw/-/draw/draw',
    'q_judging', 'judging/-/-/-',
    'fresh', 'active/-/-/-',
    's_one_delta', '3/-3',
    'a_stats', '13/2/0/3',
    'b_stats', '1/0/2/3',
    'finished_at_set', true,
    'disputed_count', 0
  );

  select coalesce(string_agg(format('%s expected=%s actual=%s', e.key, e.value, coalesce(a.value::text, 'null')), '; '), '')
  into v_diff
  from jsonb_each(v_expected) e
  left join jsonb_each(v_actual) a on a.key = e.key
  where a.value is distinct from e.value;

  raise exception 'SMOKE RESULT ok=% % settled_total=%', v_diff = '',
    case when v_diff = '' then '' else ' FAILURES: ' || v_diff end,
    v_settled;
end $$;
