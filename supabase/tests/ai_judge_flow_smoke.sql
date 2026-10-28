-- accept_submission() 거부 규칙 스모크 테스트 (mutual-judge 2단계).
--
-- 로컬에 Docker가 없어 원격 DB에 직접 돌린다:
--   supabase db query --linked -f supabase/tests/ai_judge_flow_smoke.sql
--
-- 마지막에 일부러 예외를 던져 전체를 롤백한다. 결과:
--   SMOKE RESULT ok=true                    -> 통과
--   SMOKE RESULT ok=false FAILURES: ...     -> 어긋난 항목(기대값/실제값)
--
-- 이 파일은 옛 "제출 즉시 AI 판정"(record_speed_verdict·5회 상한) 흐름을 테스트하던 파일을
-- 대체한다. 그 함수는 2단계에서 drop됐다. 교체·창 열기·상호 판정 흐름은
-- supabase/tests/mutual_judge_flow_smoke.sql이 덮는다 — 이 파일은 accept_submission이 사진을
-- "받아들이기 전에" 거부하는 규칙(거부는 행을 만들지 않는다)과 참가자가 아닌 사람의 호출만 본다.
--
-- 확인하는 것
--   reject_early      매칭(시작) 전에 찍은 사진은 CAPTURED_BEFORE_START
--   reject_gap        촬영·수신 시각이 10분 이상 벌어지면 CAPTURE_TIME_MISMATCH
--   reject_deadline   마감 뒤 수신은 DEADLINE_PASSED
--   reject_no_consent 동의가 없으면 CONSENT_REQUIRED(참가 뒤 철회한 경우를 흉내)
--   reject_not_participant 참가자가 아니면 거부된다
--   rejected_rows     위 거부는 모두 제출 행을 만들지 않는다(어떤 집계에도 들어가지 않는다)
--   accepted_row      거부되지 않은 제출은 행이 생긴다
do $$
declare
  v_a uuid := gen_random_uuid();  -- 생성자
  v_b uuid := gen_random_uuid();  -- 참가자
  v_c uuid := gen_random_uuid();  -- 참가자가 아닌 사람
  v_battle uuid;
  v_deadline_battle uuid;
  v_no_consent_battle uuid;
  v_reject_early text := '(예외 없음)';
  v_reject_gap text := '(예외 없음)';
  v_reject_deadline text := '(예외 없음)';
  v_reject_no_consent text := '(예외 없음)';
  v_reject_not_participant text := '(예외 없음)';
  v_hint text;
  v_accepted jsonb;
  v_actual jsonb;
  v_expected jsonb;
  v_diff text;
begin
  insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  select u.id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
         u.email, jsonb_build_object('full_name', u.name), now(), now()
  from (values
    (v_a, 'ai-judge-flow-a@example.invalid', '스모크A'),
    (v_b, 'ai-judge-flow-b@example.invalid', '스모크B'),
    (v_c, 'ai-judge-flow-c@example.invalid', '스모크C')
  ) as u(id, email, name);

  -- 제출에는 AI 데이터 제공 동의가 필요하다. v_c는 동의를 주지 않아 CONSENT_REQUIRED를 확인한다.
  perform set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
  perform public.give_ai_consent('2026-09-18');
  perform set_config('request.jwt.claims', json_build_object('sub', v_b, 'role', 'authenticated')::text, true);
  perform public.give_ai_consent('2026-09-18');

  insert into public.battles (
    min_criteria, superiority_criteria, type, status, title,
    creator_id, opponent_id, duration_minutes, started_at, deadline_at
  )
  values (
    '["상판이 보인다"]'::jsonb, null, 'speed', 'active', 'accept_submission 거부 스모크',
    v_a, v_b, 4320, now() - interval '1 day', now() + interval '1 day'
  )
  returning id into v_battle;
  insert into public.battle_participants (battle_id, user_id) values (v_battle, v_b);

  insert into public.battles (
    min_criteria, superiority_criteria, type, status, title,
    creator_id, opponent_id, duration_minutes, started_at, deadline_at
  )
  values (
    '["상판이 보인다"]'::jsonb, null, 'speed', 'active', '마감 뒤 거부 스모크',
    v_a, v_b, 4320, now() - interval '1 day', now() - interval '1 hour'
  )
  returning id into v_deadline_battle;
  insert into public.battle_participants (battle_id, user_id) values (v_deadline_battle, v_b);

  insert into public.battles (
    min_criteria, superiority_criteria, type, status, title,
    creator_id, opponent_id, duration_minutes, started_at, deadline_at
  )
  values (
    '["상판이 보인다"]'::jsonb, null, 'speed', 'active', '동의 없음 거부 스모크',
    v_a, v_c, 4320, now() - interval '1 day', now() + interval '1 day'
  )
  returning id into v_no_consent_battle;
  insert into public.battle_participants (battle_id, user_id) values (v_no_consent_battle, v_c);

  -- 1. 매칭(시작) 전에 찍은 사진.
  begin
    perform public.accept_submission(
      v_a, v_battle, format('%s/%s/early.jpg', v_battle, v_a), now() - interval '2 days');
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    v_reject_early := coalesce(v_hint, '(힌트 없음)');
  end;

  -- 2. 촬영·수신 시각이 10분 이상 벌어짐.
  begin
    perform public.accept_submission(
      v_a, v_battle, format('%s/%s/old.jpg', v_battle, v_a), now() - interval '20 minutes');
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    v_reject_gap := coalesce(v_hint, '(힌트 없음)');
  end;

  -- 3. 마감 뒤 수신.
  begin
    perform public.accept_submission(
      v_a, v_deadline_battle, format('%s/%s/late.jpg', v_deadline_battle, v_a), now());
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    v_reject_deadline := coalesce(v_hint, '(힌트 없음)');
  end;

  -- 4. 동의 없음(v_c는 참가했지만 동의를 준 적이 없다).
  begin
    perform public.accept_submission(
      v_c, v_no_consent_battle, format('%s/%s/1.jpg', v_no_consent_battle, v_c), now());
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    v_reject_no_consent := coalesce(v_hint, '(힌트 없음)');
  end;

  -- 5. 참가자가 아닌 사람.
  perform set_config('request.jwt.claims', json_build_object('sub', v_c, 'role', 'authenticated')::text, true);
  perform public.give_ai_consent('2026-09-18');
  begin
    perform public.accept_submission(
      v_c, v_battle, format('%s/%s/1.jpg', v_battle, v_c), now());
  exception when others then
    v_reject_not_participant := 'rejected';
  end;

  -- 6. 거부되지 않은 제출은 정상적으로 행이 생긴다.
  v_accepted := public.accept_submission(v_a, v_battle, format('%s/%s/ok.jpg', v_battle, v_a), now());

  v_actual := jsonb_build_object(
    'reject_early', v_reject_early,
    'reject_gap', v_reject_gap,
    'reject_deadline', v_reject_deadline,
    'reject_no_consent', v_reject_no_consent,
    'reject_not_participant', v_reject_not_participant,
    'rejected_rows', (select count(*) from public.battle_submissions
                      where battle_id in (v_battle, v_deadline_battle, v_no_consent_battle)
                        and (object_path like '%early.jpg' or object_path like '%old.jpg'
                             or object_path like '%late.jpg')),
    'accepted_row', (select count(*) from public.battle_submissions
                     where id = (v_accepted ->> 'submission_id')::bigint)
  );

  v_expected := jsonb_build_object(
    'reject_early', 'CAPTURED_BEFORE_START',
    'reject_gap', 'CAPTURE_TIME_MISMATCH',
    'reject_deadline', 'DEADLINE_PASSED',
    'reject_no_consent', 'CONSENT_REQUIRED',
    'reject_not_participant', 'rejected',
    'rejected_rows', 0,
    'accepted_row', 1
  );

  select coalesce(string_agg(format('%s expected=%s actual=%s', e.key, e.value, coalesce(a.value::text, 'null')), '; '), '')
  into v_diff
  from jsonb_each(v_expected) e
  left join jsonb_each(v_actual) a on a.key = e.key
  where a.value is distinct from e.value;

  raise exception 'SMOKE RESULT ok=% %', v_diff = '',
    case when v_diff = '' then '' else ' FAILURES: ' || v_diff end;
end $$;
