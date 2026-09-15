-- 기준 생성·검사 원장과 대결 생성 스모크 테스트.
--
-- 로컬에 Docker가 없어 원격 DB에 직접 돌린다:
--   supabase db query --linked -f supabase/tests/criteria_smoke.sql
--
-- Gemini는 부르지 않는다. Edge Function이 하는 순서(begin -> finish/fail)를 SQL로 흉내 낸다.
-- 마지막에 일부러 예외를 던져 전체를 롤백한다. 결과:
--   SMOKE RESULT ok=true                    -> 통과
--   SMOKE RESULT ok=false FAILURES: ...     -> 어긋난 항목(기대값/실제값)
--
-- 확인하는 것
--   no_consent        동의 없으면 기준 생성 호출 자체가 막힌다(CONSENT_REQUIRED)
--   failed_not_counted 실패한 호출은 하루 10회에 세지 않는다
--   limit_11th        성공 10회를 채우면 11번째는 CRITERIA_CALL_LIMIT
--   speed_battle      속도전은 우열 기준 없이 생성된다
--   quality_battle    품질전은 두 목록으로 생성된다
--   pending_second    모집 중 대결이 있으면 두 번째 생성은 PENDING_EXISTS
--   check_reuse       한 번 쓴 증서는 다시 못 쓴다(CHECK_INVALID)
--   blocked_check     차단된 증서로는 만들 수 없다(CHECK_INVALID)
--   speed_superiority 속도전에 우열 기준을 넣으면 DB 제약이 막는다
--   quality_missing   품질전에 우열 기준이 없으면 DB 제약이 막는다
--   update_version    모집 중 기준 수정은 버전을 올린다
--   update_matched    매칭된 뒤에는 NOT_PENDING
--   limits            get_my_limits가 모집 중·남은 횟수를 알려 준다
--   delete_account    탈퇴하면 증서·호출 원장이 사라진다
do $$
declare
  v_a uuid := gen_random_uuid();
  v_b uuid := gen_random_uuid();
  v_c uuid := gen_random_uuid();
  v_today date := (now() at time zone 'Asia/Seoul')::date;
  v_call uuid;
  v_check uuid;
  v_check2 uuid;
  v_blocked uuid;
  v_battle uuid;
  v_quality uuid;
  v_quality_created text;
  v_matched uuid;
  v_version integer;
  v_i integer;
  v_hint text;
  v_no_consent text := '(예외 없음)';
  v_limit_11th text := '(예외 없음)';
  v_pending_second text := '(예외 없음)';
  v_check_reuse text := '(예외 없음)';
  v_blocked_check text := '(예외 없음)';
  v_update_matched text := '(예외 없음)';
  v_speed_superiority boolean := false;
  v_quality_missing boolean := false;
  v_actual jsonb;
  v_expected jsonb;
  v_diff text;
begin
  insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  values
    (v_a, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'criteria-smoke-a@example.invalid', '{"full_name":"스모크A"}'::jsonb, now(), now()),
    (v_b, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'criteria-smoke-b@example.invalid', '{"full_name":"스모크B"}'::jsonb, now(), now()),
    (v_c, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'criteria-smoke-c@example.invalid', '{"full_name":"스모크C"}'::jsonb, now(), now());

  -- 1. 동의 없이는 호출 자체가 막힌다(Gemini로 제목이 나가기 전에 멈춘다).
  begin
    perform public.begin_criteria_call(v_a, 'generate', null);
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    v_no_consent := coalesce(v_hint, '(힌트 없음)');
  end;

  perform set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
  perform public.give_ai_consent('2026-09-14');
  perform set_config('request.jwt.claims', json_build_object('sub', v_b, 'role', 'authenticated')::text, true);
  perform public.give_ai_consent('2026-09-14');
  perform set_config('request.jwt.claims', json_build_object('sub', v_c, 'role', 'authenticated')::text, true);
  perform public.give_ai_consent('2026-09-14');

  -- 2. 실패한 호출은 세지 않는다.
  v_call := public.begin_criteria_call(v_a, 'generate', null);
  perform public.fail_criteria_call(v_call);

  -- 3. 성공 호출로 속도전 증서를 만든다.
  v_call := public.begin_criteria_call(v_a, 'generate', null);
  v_check := (public.finish_criteria_call(
    v_call, '방 청소하기', 'speed', '["바닥이 보인다"]'::jsonb, null, true, null, null, 'test/p1'
  ) ->> 'check_id')::uuid;

  perform set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
  v_battle := public.create_battle(v_check, 72);

  -- 4. 모집 중 대결이 있으면 두 번째 생성은 막힌다.
  v_call := public.begin_criteria_call(v_b, 'generate', null);
  v_check2 := (public.finish_criteria_call(
    v_call, '설거지하기', 'speed', '["싱크대가 비어 있다"]'::jsonb, null, true, null, null, 'test/p1'
  ) ->> 'check_id')::uuid;

  begin
    perform public.begin_criteria_call(v_a, 'generate', null);
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    v_pending_second := coalesce(v_hint, '(힌트 없음)');
  end;

  -- 5. 한 번 쓴 증서는 다시 못 쓴다(B의 증서를 A가 쓰는 것도 막히지만, 여기서는 재사용을 본다).
  perform set_config('request.jwt.claims', json_build_object('sub', v_b, 'role', 'authenticated')::text, true);
  perform public.create_battle(v_check2, 24);
  begin
    perform public.create_battle(v_check2, 24);
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    v_check_reuse := coalesce(v_hint, '(힌트 없음)');
  end;

  -- 6. 차단된 증서로는 만들 수 없다.
  v_call := public.begin_criteria_call(v_c, 'generate', null);
  v_blocked := (public.finish_criteria_call(
    v_call, '책 읽기', 'speed', '[]'::jsonb, null, false, '사진으로 확인할 수 없는 미션이에요', null, 'test/p1'
  ) ->> 'check_id')::uuid;

  perform set_config('request.jwt.claims', json_build_object('sub', v_c, 'role', 'authenticated')::text, true);
  begin
    perform public.create_battle(v_blocked, 24);
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    v_blocked_check := coalesce(v_hint, '(힌트 없음)');
  end;

  -- 7. 품질전은 두 목록으로 만든다.
  v_call := public.begin_criteria_call(v_c, 'generate', null);
  v_check := (public.finish_criteria_call(
    v_call, '책상 정리하기', 'quality', '["상판이 보인다"]'::jsonb, '["먼지가 없다"]'::jsonb,
    true, null, null, 'test/p1'
  ) ->> 'check_id')::uuid;
  v_quality := public.create_battle(v_check, 168);
  -- 아래 9번 사례가 같은 대결의 기준을 바꾸므로, 생성 직후 값을 여기서 잡아 둔다.
  select type || '/' || (superiority_criteria ->> 0) || '/' || (min_criteria ->> 0)
    into v_quality_created
  from public.battles where id = v_quality;

  -- 8. 유형별 우열 기준 제약을 DB가 강제한다.
  begin
    insert into public.battles (type, status, title, creator_id, duration_hours, min_criteria, superiority_criteria)
    values ('speed', 'pending', '잘못된 속도전', v_a, 24, '["a"]'::jsonb, '["b"]'::jsonb);
  exception when check_violation then
    v_speed_superiority := true;
  end;

  begin
    insert into public.battles (type, status, title, creator_id, duration_hours, min_criteria, superiority_criteria)
    values ('quality', 'pending', '잘못된 품질전', v_a, 24, '["a"]'::jsonb, null);
  exception when check_violation then
    v_quality_missing := true;
  end;

  -- 9. 모집 중 기준 수정은 버전을 올린다.
  v_call := public.begin_criteria_call(v_c, 'check', v_quality);
  v_check := (public.finish_criteria_call(
    v_call, '책상 정리하기', 'quality', '["상판이 완전히 보인다"]'::jsonb, '["케이블이 묶여 있다"]'::jsonb,
    true, null, v_quality, 'test/p1'
  ) ->> 'check_id')::uuid;
  v_version := public.update_battle_criteria(v_quality, v_check);

  -- 10. 매칭된 대결의 기준은 바꿀 수 없다.
  insert into public.battles (type, status, title, creator_id, opponent_id, duration_hours,
                              started_at, deadline_at, min_criteria)
  values ('speed', 'active', '매칭된 대결', v_c, v_a, 24, now(), now() + interval '1 day', '["a"]'::jsonb)
  returning id into v_matched;
  insert into public.battle_participants (battle_id, user_id) values (v_matched, v_a);

  begin
    perform public.begin_criteria_call(v_c, 'check', v_matched);
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    v_update_matched := coalesce(v_hint, '(힌트 없음)');
  end;

  -- 11. 하루 10회 한도. C는 위에서 3회 성공했으므로 7회를 더 채운다.
  for v_i in 1..7 loop
    v_call := public.begin_criteria_call(v_c, 'check', null);
    perform public.finish_criteria_call(
      v_call, '책상 정리하기', 'quality', '["상판이 보인다"]'::jsonb, '["먼지가 없다"]'::jsonb,
      true, null, null, 'test/p1'
    );
  end loop;

  begin
    perform public.begin_criteria_call(v_c, 'check', null);
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    v_limit_11th := coalesce(v_hint, '(힌트 없음)');
  end;

  v_actual := jsonb_build_object(
    'no_consent', v_no_consent,
    'a_calls_counted', public.criteria_calls_used(v_a, v_today),
    'c_calls_counted', public.criteria_calls_used(v_c, v_today),
    'limit_11th', v_limit_11th,
    'speed_battle', (select type || '/' || coalesce(superiority_criteria::text, 'null')
                       || '/' || (min_criteria ->> 0) || '/' || criteria_version
                     from public.battles where id = v_battle),
    'quality_battle', v_quality_created,
    'update_version', v_version,
    'pending_second', v_pending_second,
    'check_reuse', v_check_reuse,
    'blocked_check', v_blocked_check,
    'update_matched', v_update_matched,
    'speed_superiority_blocked', v_speed_superiority,
    'quality_missing_blocked', v_quality_missing,
    'consumed_checks', (select count(*) from public.criteria_checks where consumed_at is not null),
    'limits_a', (select public.get_my_limits() from (select set_config('request.jwt.claims',
                   json_build_object('sub', v_a, 'role', 'authenticated')::text, true)) s)
  );

  -- 탈퇴하면 증서와 호출 원장이 사라진다.
  perform set_config('request.jwt.claims', json_build_object('sub', v_c, 'role', 'authenticated')::text, true);
  perform public.delete_account();

  v_actual := v_actual || jsonb_build_object(
    'c_checks_left', (select count(*) from public.criteria_checks where user_id = v_c),
    'c_calls_left', (select count(*) from public.ai_criteria_calls where user_id = v_c)
  );

  v_expected := jsonb_build_object(
    'no_consent', 'CONSENT_REQUIRED',
    -- A: 실패 1회는 세지 않고 성공 1회만 센다.
    'a_calls_counted', 1,
    -- C: 생성 3회(차단 1 포함) + 수정 1회 + 7회 = 11회지만 11번째는 막혔으므로 10회.
    'c_calls_counted', 10,
    'limit_11th', 'CRITERIA_CALL_LIMIT',
    'speed_battle', 'speed/null/바닥이 보인다/1',
    'quality_battle', 'quality/먼지가 없다/상판이 보인다',
    'update_version', 2,
    'pending_second', 'PENDING_EXISTS',
    'check_reuse', 'CHECK_INVALID',
    'blocked_check', 'CHECK_INVALID',
    'update_matched', 'NOT_PENDING',
    'speed_superiority_blocked', true,
    'quality_missing_blocked', true,
    'consumed_checks', 4,
    'limits_a', jsonb_build_object(
      'consented', true, 'has_pending', true, 'daily_battle_used', false, 'criteria_calls_left', 9
    ),
    'c_checks_left', 0,
    'c_calls_left', 0
  );

  select coalesce(string_agg(format('%s expected=%s actual=%s', e.key, e.value, coalesce(a.value::text, 'null')), '; '), '')
  into v_diff
  from jsonb_each(v_expected) e
  left join jsonb_each(v_actual) a on a.key = e.key
  where a.value is distinct from e.value;

  raise exception 'SMOKE RESULT ok=% %', v_diff = '',
    case when v_diff = '' then '' else ' FAILURES: ' || v_diff end;
end $$;
