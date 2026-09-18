-- 모집 참가·하루 1대결·전적 카드 스모크 테스트.
--
-- 로컬에 Docker가 없어 원격 DB에 직접 돌린다:
--   supabase db query --linked -f supabase/tests/join_battle_smoke.sql
--
-- 마지막에 일부러 예외를 던져 전체를 롤백한다. 결과:
--   SMOKE RESULT ok=true                    -> 통과
--   SMOKE RESULT ok=false FAILURES: ...     -> 어긋난 항목(기대값/실제값)
--
-- 확인하는 것
--   wrong_version    참가자가 본 기준과 현재 기준이 다르면 CRITERIA_CHANGED
--   joined           올바른 버전이면 매칭(active, 마감 설정, 참가자 2명)
--   slots_after_join 매칭 순간 양쪽에 그날 슬롯 1행씩
--   already_matched  매칭된 모집에 또 참가하면 ALREADY_MATCHED
--   my_limit         오늘 이미 대결한 사람은 MY_DAILY_LIMIT
--   creator_limit    생성자가 오늘 한도를 다 썼으면 CREATOR_DAILY_LIMIT
--   no_consent       동의하지 않은 사람은 CONSENT_REQUIRED
--   self_join        본인 모집에는 참가할 수 없다
--   yesterday_slot   어제 매칭 슬롯은 오늘 한도를 막지 않는다
--   recruits         list_open_recruits는 내 모집을 빼고 생성자 전적을 함께 준다
--   card_opponent    같은 대결 상대의 전적은 볼 수 있다
--   card_creator     모집 중 대결 생성자의 전적은 볼 수 있다
--   card_stranger    그 외 사용자의 전적 조회는 거부된다
--   card_deleted     탈퇴한 사용자는 deleted=true, 점수 없음
do $$
declare
  v_a uuid := gen_random_uuid();  -- 모집 생성 후 매칭되는 사람
  v_b uuid := gen_random_uuid();  -- 참가자
  v_c uuid := gen_random_uuid();  -- 제3자
  v_d uuid := gen_random_uuid();  -- 오늘 한도를 이미 쓴 생성자
  v_e uuid := gen_random_uuid();  -- 동의하지 않은 사람
  v_f uuid := gen_random_uuid();  -- 어제 슬롯만 있는 사람
  v_g uuid := gen_random_uuid();  -- 한도가 남은 생성자
  v_today date := (now() at time zone 'Asia/Seoul')::date;
  v_call uuid;
  v_check uuid;
  v_p_a uuid;
  v_p_d uuid;
  v_p_g uuid;
  v_hint text;
  v_wrong_version text := '(예외 없음)';
  v_already text := '(예외 없음)';
  v_my_limit text := '(예외 없음)';
  v_creator_limit text := '(예외 없음)';
  v_no_consent text := '(예외 없음)';
  v_self_join boolean := false;
  v_card_stranger boolean := false;
  v_recruits jsonb;
  v_joined text;
  v_slots_after_join integer;
  v_actual jsonb;
  v_expected jsonb;
  v_diff text;
begin
  insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  select u.id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
         u.email, jsonb_build_object('full_name', u.name), now(), now()
  from (values
    (v_a, 'join-smoke-a@example.invalid', '스모크A'),
    (v_b, 'join-smoke-b@example.invalid', '스모크B'),
    (v_c, 'join-smoke-c@example.invalid', '스모크C'),
    (v_d, 'join-smoke-d@example.invalid', '스모크D'),
    (v_e, 'join-smoke-e@example.invalid', '스모크E'),
    (v_f, 'join-smoke-f@example.invalid', '스모크F'),
    (v_g, 'join-smoke-g@example.invalid', '스모크G')
  ) as u(id, email, name);

  update public.player_stats set score = 7, wins = 2, losses = 1, draws = 0 where user_id = v_a;

  -- 동의(E만 동의하지 않는다).
  perform set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
  perform public.give_ai_consent('2026-09-14');
  perform set_config('request.jwt.claims', json_build_object('sub', v_b, 'role', 'authenticated')::text, true);
  perform public.give_ai_consent('2026-09-14');
  perform set_config('request.jwt.claims', json_build_object('sub', v_c, 'role', 'authenticated')::text, true);
  perform public.give_ai_consent('2026-09-14');
  perform set_config('request.jwt.claims', json_build_object('sub', v_d, 'role', 'authenticated')::text, true);
  perform public.give_ai_consent('2026-09-14');
  perform set_config('request.jwt.claims', json_build_object('sub', v_f, 'role', 'authenticated')::text, true);
  perform public.give_ai_consent('2026-09-14');
  perform set_config('request.jwt.claims', json_build_object('sub', v_g, 'role', 'authenticated')::text, true);
  perform public.give_ai_consent('2026-09-14');

  -- A가 모집을 올린다(대결 생성은 create_battle RPC로만 가능하다).
  v_call := public.begin_criteria_call(v_a, 'generate', null);
  v_check := (public.finish_criteria_call(
    v_call, '방 청소하기', 'quality', '["바닥이 보인다"]'::jsonb, '["먼지가 없다"]'::jsonb,
    true, null, null, 'test/p1'
  ) ->> 'check_id')::uuid;
  perform set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
  v_p_a := public.create_battle(v_check, 4320);

  -- 1. 참가자가 본 버전이 현재와 다르면 참가가 성립하지 않는다.
  perform set_config('request.jwt.claims', json_build_object('sub', v_b, 'role', 'authenticated')::text, true);
  begin
    perform public.join_battle(v_p_a, 99);
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    v_wrong_version := coalesce(v_hint, '(힌트 없음)');
  end;

  -- 2. 올바른 버전이면 매칭된다.
  perform public.join_battle(v_p_a, 1);

  -- 3. 매칭된 모집에는 더 참가할 수 없다.
  perform set_config('request.jwt.claims', json_build_object('sub', v_c, 'role', 'authenticated')::text, true);
  begin
    perform public.join_battle(v_p_a, 1);
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    v_already := coalesce(v_hint, '(힌트 없음)');
  end;

  -- D가 모집을 올리고, D에게 오늘 슬롯을 만들어 준다(이미 다른 대결을 한 상태).
  v_call := public.begin_criteria_call(v_d, 'generate', null);
  v_check := (public.finish_criteria_call(
    v_call, '설거지하기', 'speed', '["싱크대가 비어 있다"]'::jsonb, null, true, null, null, 'test/p1'
  ) ->> 'check_id')::uuid;
  perform set_config('request.jwt.claims', json_build_object('sub', v_d, 'role', 'authenticated')::text, true);
  v_p_d := public.create_battle(v_check, 1440);
  insert into public.daily_battle_slots (user_id, kst_date, battle_id) values (v_d, v_today, v_p_a);

  -- 4. 오늘 이미 대결한 B는 다른 모집에 참가할 수 없다(내 한도가 먼저 걸린다).
  perform set_config('request.jwt.claims', json_build_object('sub', v_b, 'role', 'authenticated')::text, true);
  begin
    perform public.join_battle(v_p_d, 1);
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    v_my_limit := coalesce(v_hint, '(힌트 없음)');
  end;

  -- 5. 생성자가 오늘 한도를 다 썼으면 참가자에게 이유를 알린다.
  perform set_config('request.jwt.claims', json_build_object('sub', v_c, 'role', 'authenticated')::text, true);
  begin
    perform public.join_battle(v_p_d, 1);
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    v_creator_limit := coalesce(v_hint, '(힌트 없음)');
  end;

  -- 6. 동의하지 않은 사람은 막힌다.
  perform set_config('request.jwt.claims', json_build_object('sub', v_e, 'role', 'authenticated')::text, true);
  begin
    perform public.join_battle(v_p_d, 1);
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    v_no_consent := coalesce(v_hint, '(힌트 없음)');
  end;

  -- 7. 본인 모집에는 참가할 수 없다.
  perform set_config('request.jwt.claims', json_build_object('sub', v_d, 'role', 'authenticated')::text, true);
  begin
    perform public.join_battle(v_p_d, 1);
  exception when others then
    v_self_join := true;
  end;

  -- G가 모집을 올린다(생성자 한도 남음). F는 어제 슬롯만 있다.
  v_call := public.begin_criteria_call(v_g, 'generate', null);
  v_check := (public.finish_criteria_call(
    v_call, '빨래 개기', 'speed', '["옷이 개켜져 있다"]'::jsonb, null, true, null, null, 'test/p1'
  ) ->> 'check_id')::uuid;
  perform set_config('request.jwt.claims', json_build_object('sub', v_g, 'role', 'authenticated')::text, true);
  v_p_g := public.create_battle(v_check, 1440);

  insert into public.daily_battle_slots (user_id, kst_date, battle_id) values (v_f, v_today - 1, v_p_a);

  -- 8. 어제 슬롯은 오늘 한도를 막지 않는다.
  perform set_config('request.jwt.claims', json_build_object('sub', v_f, 'role', 'authenticated')::text, true);
  perform public.join_battle(v_p_g, 1);

  -- 9. 목록: C에게는 D의 모집만 남는다(A·G는 매칭됐고 C 본인 모집은 없다).
  perform set_config('request.jwt.claims', json_build_object('sub', v_c, 'role', 'authenticated')::text, true);
  select jsonb_agg(r order by r -> 'battle' ->> 'title') into v_recruits
  from public.list_open_recruits() r;

  -- 10. 전적 카드.
  perform set_config('request.jwt.claims', json_build_object('sub', v_b, 'role', 'authenticated')::text, true);
  v_actual := jsonb_build_object('card_opponent', public.get_player_card(v_a));

  perform set_config('request.jwt.claims', json_build_object('sub', v_c, 'role', 'authenticated')::text, true);
  v_actual := v_actual || jsonb_build_object('card_creator', (public.get_player_card(v_d) ->> 'display_name'));

  begin
    -- C와 B는 같은 대결이 없고 B는 모집도 없다.
    perform public.get_player_card(v_b);
  exception when others then
    v_card_stranger := true;
  end;

  -- A가 탈퇴하면 v_p_a가 취소되고 그날 슬롯이 반납된다. 매칭 결과는 그 전에 잡아 둔다.
  v_joined := (select status || '/' || (opponent_id = v_b)::text || '/' || (deadline_at is not null)::text
               from public.battles where id = v_p_a);
  v_slots_after_join := (select count(*) from public.daily_battle_slots
                         where battle_id = v_p_a and kst_date = v_today and user_id in (v_a, v_b));

  -- 탈퇴한 상대의 카드.
  perform set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
  perform public.delete_account();
  perform set_config('request.jwt.claims', json_build_object('sub', v_b, 'role', 'authenticated')::text, true);

  v_actual := v_actual || jsonb_build_object(
    'wrong_version', v_wrong_version,
    'joined', v_joined,
    'participants', (select count(*) from public.battle_participants where battle_id = v_p_a),
    'slots_after_join', v_slots_after_join,
    'already_matched', v_already,
    'my_limit', v_my_limit,
    'creator_limit', v_creator_limit,
    'no_consent', v_no_consent,
    'self_join_rejected', v_self_join,
    'yesterday_slot_joined', (select status from public.battles where id = v_p_g),
    'f_slots', (select count(*) from public.daily_battle_slots where user_id = v_f),
    'recruits_count', jsonb_array_length(coalesce(v_recruits, '[]'::jsonb)),
    'recruits_title', v_recruits -> 0 -> 'battle' ->> 'title',
    'recruits_version', v_recruits -> 0 -> 'battle' ->> 'criteria_version',
    'recruits_min', v_recruits -> 0 -> 'battle' -> 'min_criteria' ->> 0,
    'recruits_superiority', coalesce(v_recruits -> 0 -> 'battle' ->> 'superiority_criteria', 'null'),
    'recruits_creator', v_recruits -> 0 -> 'creator' ->> 'display_name',
    'card_stranger_rejected', v_card_stranger,
    'card_deleted', (public.get_player_card(v_a) ->> 'deleted'),
    'card_deleted_score', coalesce(public.get_player_card(v_a) ->> 'score', 'null')
  );

  v_expected := jsonb_build_object(
    'wrong_version', 'CRITERIA_CHANGED',
    'joined', 'active/true/true',
    'participants', 2,
    'slots_after_join', 2,
    'already_matched', 'ALREADY_MATCHED',
    'my_limit', 'MY_DAILY_LIMIT',
    'creator_limit', 'CREATOR_DAILY_LIMIT',
    'no_consent', 'CONSENT_REQUIRED',
    'self_join_rejected', true,
    'yesterday_slot_joined', 'active',
    -- 어제 1행 + 오늘 매칭으로 1행.
    'f_slots', 2,
    'recruits_count', 1,
    'recruits_title', '설거지하기',
    'recruits_version', '1',
    'recruits_min', '싱크대가 비어 있다',
    'recruits_superiority', 'null',
    'recruits_creator', '스모크D',
    'card_opponent', jsonb_build_object(
      'user_id', v_a, 'display_name', '스모크A', 'deleted', false,
      'score', 7, 'wins', 2, 'losses', 1, 'draws', 0
    ),
    'card_creator', '스모크D',
    'card_stranger_rejected', true,
    'card_deleted', 'true',
    'card_deleted_score', 'null'
  );

  select coalesce(string_agg(format('%s expected=%s actual=%s', e.key, e.value, coalesce(a.value::text, 'null')), '; '), '')
  into v_diff
  from jsonb_each(v_expected) e
  left join jsonb_each(v_actual) a on a.key = e.key
  where a.value is distinct from e.value;

  raise exception 'SMOKE RESULT ok=% %', v_diff = '',
    case when v_diff = '' then '' else ' FAILURES: ' || v_diff end;
end $$;
