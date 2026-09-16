-- 증거 제출·속도전 판정 흐름 스모크 테스트 (ai-judge 5단계).
--
-- 로컬에 Docker가 없어 원격 DB에 직접 돌린다:
--   supabase db query --linked -f supabase/tests/ai_judge_flow_smoke.sql
--
-- 마지막에 일부러 예외를 던져 전체를 롤백한다. 결과:
--   SMOKE RESULT ok=true                    -> 통과
--   SMOKE RESULT ok=false FAILURES: ...     -> 어긋난 항목(기대값/실제값)
--
-- 확인하는 것
--   reject_early      매칭(시작) 전에 찍은 사진은 CAPTURED_BEFORE_START
--   reject_gap        촬영·수신 시각이 10분 이상 벌어지면 CAPTURE_TIME_MISMATCH
--   reject_deadline   마감 뒤 수신은 DEADLINE_PASSED
--   rejected_rows     거부된 사진은 제출 행을 만들지 않는다(어떤 횟수에도 미산입)
--   both_passed       양쪽 통과 -> 마감 전이라도 즉시 종결, 통과 시각이 이른 쪽 승리
--   exhausted         한쪽 통과 + 상대 5회 소진 -> 즉시 종결(통과자 승, 상대 loss)
--   draw_exhausted    양쪽 5회 소진 -> 즉시 draw
--   error_*           AI 실패(error)는 5회에 세지 않고 다시 제출할 수 있다
--   locked_after_pass 통과한 뒤에는 제출이 잠긴다(SUBMISSION_LOCKED)
--   judging_blocks    판정 중인 내 제출이 있으면 JUDGING_IN_PROGRESS
--   settle_skips      판정 중 제출이 있는 속도전은 마감이 지나도 settle이 건너뛴다
--   sweep_*           3분 넘게 판정 중인 제출은 error로 내려가고 대결은 계속된다
--   rls_opponent      진행 중에는 상대의 제출 행이 한 건도 보이지 않는다(authenticated로 위장)
do $$
declare
  v_a uuid := gen_random_uuid();  -- 생성자
  v_b uuid := gen_random_uuid();  -- 참가자
  v_b_pass uuid;
  v_b_exhaust uuid;
  v_b_draw uuid;
  v_b_err uuid;
  v_b_reject uuid;
  v_b_late uuid;
  v_b_wait uuid;
  v_b_sweep uuid;
  v_priv uuid;
  v_id uuid;
  v_i integer;
  v_sub bigint;
  v_sweep_sub bigint;
  v_hint text;
  v_reject_early text := '(예외 없음)';
  v_reject_gap text := '(예외 없음)';
  v_reject_deadline text := '(예외 없음)';
  v_locked text := '(예외 없음)';
  v_judging_blocks text := '(예외 없음)';
  v_err_resubmitted boolean := false;
  v_rls_opponent integer := -1;
  v_rls_own integer := -1;
  v_actual jsonb;
  v_expected jsonb;
  v_diff text;
begin
  insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  select u.id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
         u.email, jsonb_build_object('full_name', u.name), now(), now()
  from (values
    (v_a, 'flow-smoke-a@example.invalid', '스모크A'),
    (v_b, 'flow-smoke-b@example.invalid', '스모크B')
  ) as u(id, email, name);

  -- 점수 하한(0)에 걸려 결과가 가려지지 않게 넉넉히 둔다.
  update public.player_stats set score = 10 where user_id in (v_a, v_b);

  -- 제출에는 AI 데이터 제공 동의가 필요하다(참가 뒤 철회했을 수 있으므로 서버가 다시 본다).
  perform set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
  perform public.give_ai_consent('2026-09-14');
  perform set_config('request.jwt.claims', json_build_object('sub', v_b, 'role', 'authenticated')::text, true);
  perform public.give_ai_consent('2026-09-14');

  -- 매칭된 속도전 아홉 개(어제 시작, 내일 마감). 생성자 참가자 행은 트리거가 만든다.
  for v_i in 1..9 loop
    insert into public.battles (
      min_criteria, superiority_criteria, type, status, title,
      creator_id, opponent_id, duration_hours, started_at, deadline_at
    )
    values (
      '["상판이 보인다"]'::jsonb, null, 'speed', 'active', 'flow 스모크 ' || v_i,
      v_a, v_b, 72, now() - interval '1 day', now() + interval '1 day'
    )
    returning id into v_id;

    insert into public.battle_participants (battle_id, user_id) values (v_id, v_b);

    case v_i
      when 1 then v_b_pass := v_id;
      when 2 then v_b_exhaust := v_id;
      when 3 then v_b_draw := v_id;
      when 4 then v_b_err := v_id;
      when 5 then v_b_reject := v_id;
      when 6 then v_b_late := v_id;
      when 7 then v_b_wait := v_id;
      when 8 then v_b_sweep := v_id;
      else v_priv := v_id;
    end case;
  end loop;

  -- 마감이 지난 대결(거부 확인용).
  update public.battles set deadline_at = now() - interval '1 hour' where id = v_b_late;

  -- 1. 거부 3종. 어느 것도 제출 행을 만들지 않는다.
  begin
    perform public.accept_submission(
      v_a, v_b_reject, format('%s/%s/early.jpg', v_b_reject, v_a), now() - interval '2 days');
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    v_reject_early := coalesce(v_hint, '(힌트 없음)');
  end;

  begin
    perform public.accept_submission(
      v_a, v_b_reject, format('%s/%s/old.jpg', v_b_reject, v_a), now() - interval '20 minutes');
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    v_reject_gap := coalesce(v_hint, '(힌트 없음)');
  end;

  begin
    perform public.accept_submission(
      v_a, v_b_late, format('%s/%s/late.jpg', v_b_late, v_a), now());
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    v_reject_deadline := coalesce(v_hint, '(힌트 없음)');
  end;

  -- 2. 양쪽 통과: 나중에 기록됐어도 통과 시각이 이른 쪽이 이긴다.
  --    (한 트랜잭션 안에서는 now()가 고정이라 A의 제출 시각을 앞당겨 시간 비교를 확인한다.)
  v_sub := (public.accept_submission(
    v_b, v_b_pass, format('%s/%s/1.jpg', v_b_pass, v_b), now()) ->> 'submission_id')::bigint;
  perform public.record_speed_verdict(v_sub, 'passed', '상판이 보인다', 'test/p1');

  v_sub := (public.accept_submission(
    v_a, v_b_pass, format('%s/%s/1.jpg', v_b_pass, v_a), now()) ->> 'submission_id')::bigint;
  update public.battle_submissions set submitted_at = now() - interval '30 minutes' where id = v_sub;
  perform public.record_speed_verdict(v_sub, 'passed', '상판이 보인다', 'test/p1');

  -- 3. 통과 뒤에는 잠긴다.
  begin
    perform public.accept_submission(
      v_a, v_b_pass, format('%s/%s/2.jpg', v_b_pass, v_a), now());
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    v_locked := coalesce(v_hint, '(힌트 없음)');
  end;

  -- 4. 한쪽 통과 + 상대 5회 소진 -> 마감 전이라도 즉시 종결.
  v_sub := (public.accept_submission(
    v_a, v_b_exhaust, format('%s/%s/1.jpg', v_b_exhaust, v_a), now()) ->> 'submission_id')::bigint;
  perform public.record_speed_verdict(v_sub, 'passed', '상판이 보인다', 'test/p1');

  for v_i in 1..5 loop
    v_sub := (public.accept_submission(
      v_b, v_b_exhaust, format('%s/%s/%s.jpg', v_b_exhaust, v_b, v_i), now()) ->> 'submission_id')::bigint;
    perform public.record_speed_verdict(v_sub, 'failed', '상판이 보이지 않는다', 'test/p1');
  end loop;

  -- 5. 양쪽 5회 소진 -> 즉시 draw.
  for v_i in 1..5 loop
    v_sub := (public.accept_submission(
      v_a, v_b_draw, format('%s/%s/%s.jpg', v_b_draw, v_a, v_i), now()) ->> 'submission_id')::bigint;
    perform public.record_speed_verdict(v_sub, 'failed', '상판이 보이지 않는다', 'test/p1');
  end loop;
  for v_i in 1..5 loop
    v_sub := (public.accept_submission(
      v_b, v_b_draw, format('%s/%s/%s.jpg', v_b_draw, v_b, v_i), now()) ->> 'submission_id')::bigint;
    perform public.record_speed_verdict(v_sub, 'failed', '상판이 보이지 않는다', 'test/p1');
  end loop;

  -- 6. AI 실패는 횟수에 세지 않고 다시 낼 수 있다.
  for v_i in 1..3 loop
    v_sub := (public.accept_submission(
      v_a, v_b_err, format('%s/%s/%s.jpg', v_b_err, v_a, v_i), now()) ->> 'submission_id')::bigint;
    perform public.record_speed_verdict(v_sub, 'error', null, 'test/p1');
  end loop;

  begin
    v_sub := (public.accept_submission(
      v_a, v_b_err, format('%s/%s/4.jpg', v_b_err, v_a), now()) ->> 'submission_id')::bigint;
    v_err_resubmitted := true;
  exception when others then
    v_err_resubmitted := false;
  end;

  -- 7. 판정 중인 내 제출이 있으면 새 제출을 받지 않는다(위 6번이 judging 상태로 남아 있다).
  begin
    perform public.accept_submission(
      v_a, v_b_err, format('%s/%s/5.jpg', v_b_err, v_a), now());
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    v_judging_blocks := coalesce(v_hint, '(힌트 없음)');
  end;

  -- 8. 판정 중 제출이 있는 대결은 마감이 지나도 settle이 건너뛴다.
  perform public.accept_submission(
    v_a, v_b_wait, format('%s/%s/1.jpg', v_b_wait, v_a), now());
  update public.battles set deadline_at = now() - interval '1 hour' where id = v_b_wait;
  perform public.settle_expired_battles();

  -- 9. 3분 넘게 판정 중인 제출은 sweep이 error로 내린다(횟수 미산입).
  v_sweep_sub := (public.accept_submission(
    v_a, v_b_sweep, format('%s/%s/1.jpg', v_b_sweep, v_a), now()) ->> 'submission_id')::bigint;
  update public.battle_submissions
  set judging_started_at = now() - interval '4 minutes'
  where id = v_sweep_sub;
  perform public.sweep_stale_submissions();

  -- 10. 진행 중에는 상대의 제출 행이 보이지 않는다(RLS).
  v_sub := (public.accept_submission(
    v_a, v_priv, format('%s/%s/1.jpg', v_priv, v_a), now()) ->> 'submission_id')::bigint;
  perform public.record_speed_verdict(v_sub, 'failed', 'A의 사유', 'test/p1');
  v_sub := (public.accept_submission(
    v_b, v_priv, format('%s/%s/1.jpg', v_priv, v_b), now()) ->> 'submission_id')::bigint;
  perform public.record_speed_verdict(v_sub, 'failed', 'B의 사유', 'test/p1');

  perform set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
  begin
    -- 이 블록에서 예외가 나면 set local role도 함께 되돌아간다.
    execute 'set local role authenticated';
    select count(*) into v_rls_opponent
    from public.battle_submissions where battle_id = v_priv and user_id = v_b;
    select count(*) into v_rls_own
    from public.battle_submissions where battle_id = v_priv and user_id = v_a;
    execute 'reset role';
  exception when others then
    execute 'reset role';
    v_rls_opponent := -2;
  end;
  execute 'reset role';

  v_actual := jsonb_build_object(
    'reject_early', v_reject_early,
    'reject_gap', v_reject_gap,
    'reject_deadline', v_reject_deadline,
    'rejected_rows', (select count(*) from public.battle_submissions
                      where battle_id in (v_b_reject, v_b_late)),
    'both_passed', (select status || '/' || (winner_id = v_a)::text
                    from public.battles where id = v_b_pass),
    'both_passed_a', (select outcome from public.battle_participants
                      where battle_id = v_b_pass and user_id = v_a),
    'both_passed_b', (select outcome from public.battle_participants
                      where battle_id = v_b_pass and user_id = v_b),
    'locked_after_pass', v_locked,
    'exhausted', (select status || '/' || (winner_id = v_a)::text
                  from public.battles where id = v_b_exhaust),
    'exhausted_b', (select outcome from public.battle_participants
                    where battle_id = v_b_exhaust and user_id = v_b),
    'exhausted_b_attempts', (select attempts_used from public.battle_participants
                             where battle_id = v_b_exhaust and user_id = v_b),
    'draw_exhausted', (select status from public.battles where id = v_b_draw),
    'draw_outcomes', (select string_agg(outcome, ',' order by outcome)
                      from public.battle_participants where battle_id = v_b_draw),
    'error_rows', (select count(*) from public.battle_submissions
                   where battle_id = v_b_err and status = 'error'),
    'error_attempts', (select attempts_used from public.battle_participants
                       where battle_id = v_b_err and user_id = v_a),
    'error_battle', (select status from public.battles where id = v_b_err),
    'error_resubmitted', v_err_resubmitted,
    'judging_blocks', v_judging_blocks,
    'settle_skips', (select status from public.battles where id = v_b_wait),
    'sweep_status', (select status from public.battle_submissions where id = v_sweep_sub),
    'sweep_attempts', (select attempts_used from public.battle_participants
                       where battle_id = v_b_sweep and user_id = v_a),
    'sweep_battle', (select status from public.battles where id = v_b_sweep),
    'rls_opponent', v_rls_opponent,
    'rls_own', v_rls_own,
    -- 어떤 경로도 disputed를 만들지 않는다(MVP 미도달).
    'disputed_count', (select count(*) from public.battles
                       where creator_id = v_a and status = 'disputed')
  );

  v_expected := jsonb_build_object(
    'reject_early', 'CAPTURED_BEFORE_START',
    'reject_gap', 'CAPTURE_TIME_MISMATCH',
    'reject_deadline', 'DEADLINE_PASSED',
    'rejected_rows', 0,
    'both_passed', 'finished/true',
    'both_passed_a', 'win',
    'both_passed_b', 'completed_loss',
    'locked_after_pass', 'SUBMISSION_LOCKED',
    'exhausted', 'finished/true',
    'exhausted_b', 'loss',
    'exhausted_b_attempts', 5,
    'draw_exhausted', 'draw',
    'draw_outcomes', 'draw,draw',
    'error_rows', 3,
    'error_attempts', 0,
    'error_battle', 'active',
    'error_resubmitted', true,
    'judging_blocks', 'JUDGING_IN_PROGRESS',
    'settle_skips', 'active',
    'sweep_status', 'error',
    'sweep_attempts', 0,
    'sweep_battle', 'active',
    'rls_opponent', 0,
    'rls_own', 1,
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
