-- 커스텀 마감(분 단위) 스모크 테스트.
--
-- 로컬에 Docker가 없어 원격 DB에 직접 돌린다:
--   supabase db query --linked -f supabase/tests/custom_duration_smoke.sql
--
-- 마지막에 일부러 예외를 던져 전체를 롤백한다. 결과:
--   SMOKE RESULT ok=t                     -> 통과
--   SMOKE RESULT ok=f  FAILURES: ...      -> 어긋난 항목(기대값/실제값)
--
-- 확인하는 것
--   min_one / thirty / max_week  1분·30분·10080분 대결 생성이 성공한다
--   zero / over / null_arg       0분·10081분·null은 create_battle이 거부한다(증서는 그대로 남는다)
--   check_zero / check_over      직접 insert도 battles_duration_minutes_check가 막는다
--   deadline_one / deadline_30   매칭 순간 마감이 분 단위로 정확히 걸린다
--   recruit_duration             list_open_recruits가 duration_minutes를 돌려준다
--   recruit_no_hours             옛 duration_hours 키는 더 없다
--   anon_denied                  anon 롤에는 create_battle 실행 권한이 없다(드롭·재생성으로 새지 않았다)
--   settle_denied                authenticated 롤에는 settle_expired_battles 실행 권한이 없다
do $$
declare
  v_a uuid := gen_random_uuid();  -- 1분 대결 생성자
  v_b uuid := gen_random_uuid();  -- 1분 대결 참가자
  v_c uuid := gen_random_uuid();  -- 30분 대결 생성자
  v_d uuid := gen_random_uuid();  -- 30분 대결 참가자
  v_e uuid := gen_random_uuid();  -- 7일 모집 생성자(모집 상태로 남긴다)
  v_f uuid := gen_random_uuid();  -- 모집 목록을 보는 사람
  v_g uuid := gen_random_uuid();  -- 범위 밖 값을 넣어 보는 사람
  v_call uuid;
  v_check uuid;
  v_check_g uuid;
  v_p_one uuid;
  v_p_thirty uuid;
  v_p_long uuid;
  v_p_ok uuid;
  v_recruit jsonb;
  v_zero text := '(예외 없음)';
  v_over text := '(예외 없음)';
  v_null_arg text := '(예외 없음)';
  v_check_zero boolean := false;
  v_check_over boolean := false;
  v_anon_denied text := '(예외 없음)';
  v_settle_denied text := '(예외 없음)';
  v_actual jsonb;
  v_expected jsonb;
  v_diff text;
begin
  insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  select u.id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
         u.email, jsonb_build_object('full_name', u.name), now(), now()
  from (values
    (v_a, 'duration-smoke-a@example.invalid', '스모크A'),
    (v_b, 'duration-smoke-b@example.invalid', '스모크B'),
    (v_c, 'duration-smoke-c@example.invalid', '스모크C'),
    (v_d, 'duration-smoke-d@example.invalid', '스모크D'),
    (v_e, 'duration-smoke-e@example.invalid', '스모크E'),
    (v_f, 'duration-smoke-f@example.invalid', '스모크F'),
    (v_g, 'duration-smoke-g@example.invalid', '스모크G')
  ) as u(id, email, name);

  -- 동의 없이는 생성·참가가 막히므로 전원 동의한다(이 스모크의 확인 대상이 아니다).
  perform set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
  perform public.give_ai_consent('2026-09-14');
  perform set_config('request.jwt.claims', json_build_object('sub', v_b, 'role', 'authenticated')::text, true);
  perform public.give_ai_consent('2026-09-14');
  perform set_config('request.jwt.claims', json_build_object('sub', v_c, 'role', 'authenticated')::text, true);
  perform public.give_ai_consent('2026-09-14');
  perform set_config('request.jwt.claims', json_build_object('sub', v_d, 'role', 'authenticated')::text, true);
  perform public.give_ai_consent('2026-09-14');
  perform set_config('request.jwt.claims', json_build_object('sub', v_e, 'role', 'authenticated')::text, true);
  perform public.give_ai_consent('2026-09-14');
  perform set_config('request.jwt.claims', json_build_object('sub', v_f, 'role', 'authenticated')::text, true);
  perform public.give_ai_consent('2026-09-14');
  perform set_config('request.jwt.claims', json_build_object('sub', v_g, 'role', 'authenticated')::text, true);
  perform public.give_ai_consent('2026-09-14');

  -- 1. 하한 1분. 한 사람당 pending 모집은 1개라 생성자를 사람마다 나눈다.
  v_call := public.begin_criteria_call(v_a, 'generate', null);
  v_check := (public.finish_criteria_call(
    v_call, '설거지하기', 'speed', '["싱크대가 비어 있다"]'::jsonb, null, true, null, null, 'test/p1'
  ) ->> 'check_id')::uuid;
  perform set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
  v_p_one := public.create_battle(v_check, 1);

  -- 2. 30분.
  v_call := public.begin_criteria_call(v_c, 'generate', null);
  v_check := (public.finish_criteria_call(
    v_call, '책상 정리하기', 'speed', '["상판이 보인다"]'::jsonb, null, true, null, null, 'test/p1'
  ) ->> 'check_id')::uuid;
  perform set_config('request.jwt.claims', json_build_object('sub', v_c, 'role', 'authenticated')::text, true);
  v_p_thirty := public.create_battle(v_check, 30);

  -- 3. 상한 10080분(7일). 모집 상태로 남겨 list_open_recruits로 읽는다.
  v_call := public.begin_criteria_call(v_e, 'generate', null);
  v_check := (public.finish_criteria_call(
    v_call, '방 청소하기', 'quality', '["바닥이 보인다"]'::jsonb, '["먼지가 없다"]'::jsonb,
    true, null, null, 'test/p1'
  ) ->> 'check_id')::uuid;
  perform set_config('request.jwt.claims', json_build_object('sub', v_e, 'role', 'authenticated')::text, true);
  v_p_long := public.create_battle(v_check, 10080);

  -- 4. 범위 밖은 거부된다. 거부는 증서를 쓰지 않으므로(검사가 증서 조회보다 앞이다)
  --    같은 증서로 세 번 실패한 뒤 성공까지 확인한다.
  v_call := public.begin_criteria_call(v_g, 'generate', null);
  v_check_g := (public.finish_criteria_call(
    v_call, '빨래 개기', 'speed', '["옷이 개어져 있다"]'::jsonb, null, true, null, null, 'test/p1'
  ) ->> 'check_id')::uuid;
  perform set_config('request.jwt.claims', json_build_object('sub', v_g, 'role', 'authenticated')::text, true);

  begin
    perform public.create_battle(v_check_g, 0);
  exception when others then
    v_zero := sqlerrm;
  end;

  begin
    perform public.create_battle(v_check_g, 10081);
  exception when others then
    v_over := sqlerrm;
  end;

  begin
    perform public.create_battle(v_check_g, null);
  exception when others then
    v_null_arg := sqlerrm;
  end;

  v_p_ok := public.create_battle(v_check_g, 1440);

  -- 5. 테이블 제약도 같은 범위를 막는다(RPC를 우회하는 경로가 남지 않게).
  begin
    insert into public.battles (min_criteria, superiority_criteria, type, status, title, creator_id, duration_minutes)
    values ('["상판이 보인다"]'::jsonb, null, 'speed', 'pending', '0분 직접 insert', v_f, 0);
  exception when check_violation then
    v_check_zero := true;
  end;

  begin
    insert into public.battles (min_criteria, superiority_criteria, type, status, title, creator_id, duration_minutes)
    values ('["상판이 보인다"]'::jsonb, null, 'speed', 'pending', '10081분 직접 insert', v_f, 10081);
  exception when check_violation then
    v_check_over := true;
  end;

  -- 6. 매칭 순간 마감이 분 단위로 정확히 걸린다. started_at과 deadline_at은 같은 문장에서
  --    같은 now()로 찍히므로 차이가 정확히 기간이어야 한다.
  perform set_config('request.jwt.claims', json_build_object('sub', v_b, 'role', 'authenticated')::text, true);
  perform public.join_battle(v_p_one, 1);
  perform set_config('request.jwt.claims', json_build_object('sub', v_d, 'role', 'authenticated')::text, true);
  perform public.join_battle(v_p_thirty, 1);

  -- 7. 모집 목록이 분 단위 기간을 돌려주고 옛 키는 없다.
  --    recruit-browse에서 이 함수는 인자 없이 부르면 "최신 20건"이 된다. 이 확인이 기대는 것은
  --    DB의 모집 건수가 아니라 **created_at 순서**다 — 이 스모크가 방금 만든 모집은 같은 트랜잭션의
  --    now()로 찍혀 기존 행(더미 등)보다 늘 최신이라 최신순 첫 묶음 안에 들어온다.
  perform set_config('request.jwt.claims', json_build_object('sub', v_f, 'role', 'authenticated')::text, true);
  select t.item into v_recruit
  from public.list_open_recruits() as t(item)
  where (t.item -> 'battle' ->> 'id')::uuid = v_p_long;

  -- 8. 권한: 드롭·재생성한 create_battle이 anon에 새지 않았는지, cron 전용 함수가 잠겨 있는지.
  begin
    execute 'set local role anon';
    perform public.create_battle(v_check_g, 60);
    execute 'reset role';
  exception when insufficient_privilege then
    v_anon_denied := '권한 없음';
  when others then
    v_anon_denied := '다른 오류: ' || sqlerrm;
  end;
  execute 'reset role';

  begin
    execute 'set local role authenticated';
    perform public.settle_expired_battles();
    execute 'reset role';
  exception when insufficient_privilege then
    v_settle_denied := '권한 없음';
  when others then
    v_settle_denied := '다른 오류: ' || sqlerrm;
  end;
  execute 'reset role';

  v_actual := jsonb_build_object(
    'min_one', (select duration_minutes from public.battles where id = v_p_one),
    'thirty', (select duration_minutes from public.battles where id = v_p_thirty),
    'max_week', (select duration_minutes from public.battles where id = v_p_long),
    'after_rejects', (select duration_minutes from public.battles where id = v_p_ok),
    'zero', v_zero,
    'over', v_over,
    'null_arg', v_null_arg,
    'check_zero', v_check_zero,
    'check_over', v_check_over,
    'deadline_one', (select (deadline_at - started_at) = interval '1 minute'
                     from public.battles where id = v_p_one),
    'deadline_30', (select (deadline_at - started_at) = interval '30 minutes'
                    from public.battles where id = v_p_thirty),
    'recruit_duration', v_recruit -> 'battle' ->> 'duration_minutes',
    'recruit_no_hours', not (v_recruit -> 'battle' ? 'duration_hours'),
    'anon_denied', v_anon_denied,
    'settle_denied', v_settle_denied
  );

  v_expected := jsonb_build_object(
    'min_one', 1,
    'thirty', 30,
    'max_week', 10080,
    'after_rejects', 1440,
    'zero', '기간이 올바르지 않습니다.',
    'over', '기간이 올바르지 않습니다.',
    'null_arg', '기간이 올바르지 않습니다.',
    'check_zero', true,
    'check_over', true,
    'deadline_one', true,
    'deadline_30', true,
    'recruit_duration', '10080',
    'recruit_no_hours', true,
    'anon_denied', '권한 없음',
    'settle_denied', '권한 없음'
  );

  select coalesce(string_agg(format('%s expected=%s actual=%s', e.key, e.value, coalesce(a.value::text, 'null')), '; '), '')
  into v_diff
  from jsonb_each(v_expected) e
  left join jsonb_each(v_actual) a on a.key = e.key
  where a.value is distinct from e.value;

  raise exception 'SMOKE RESULT ok=% %', v_diff = '',
    case when v_diff = '' then '' else ' FAILURES: ' || v_diff end;
end $$;
