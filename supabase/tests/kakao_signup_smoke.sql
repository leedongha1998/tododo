-- 카카오 가입 표시 이름 스모크 테스트 (kakao-login design §8.1).
--
-- 로컬에 Docker가 없어 원격 DB에 직접 돌린다(20261125120000_kakao_login.sql 적용 뒤):
--   supabase db query --linked -f supabase/tests/kakao_signup_smoke.sql
--
-- 헬퍼 둘을 표로 부르고, auth.users에 실제로 행을 넣어 트리거가 만든 profiles·player_stats를 본다.
-- 마지막에 일부러 예외를 던져 트랜잭션 전체를 롤백한다. 결과:
--   SMOKE RESULT ok=true                    -> 통과
--   SMOKE RESULT ok=false FAILURES: ...     -> 어긋난 항목(기대값/실제값)
--
-- 확인하는 것
--   H1~H10  kakao_display_name: 후보 키 순서, 공백 걷기, 빈 값·이메일 꼴·사용자 email·회원번호·
--           시스템 이름(연습 봇·탈퇴한 사용자)은 이름이 되지 않는다
--   K1~K4   is_kakao_signup: app_meta.provider, user_meta.iss 호스트, Google, null
--   T1~T8   트리거: Google 결과 불변(이메일 대체 포함), 기존 스모크 꼴(app_meta 없음) 불변,
--           카카오 닉네임, 이메일 없는 카카오 가입 성공, 이메일이 이름이 되지 않음, 판별 불가 가입 성공
--   권한    앱 롤(anon·authenticated)은 두 헬퍼를 부를 수 없다
do $$
declare
  v_default constant text := '이름 없는 도전자';
  v_t1 uuid := gen_random_uuid();
  v_t2 uuid := gen_random_uuid();
  v_t3 uuid := gen_random_uuid();
  v_t4 uuid := gen_random_uuid();
  v_t5 uuid := gen_random_uuid();
  v_t6 uuid := gen_random_uuid();
  v_t7 uuid := gen_random_uuid();
  v_t8 uuid := gen_random_uuid();
  v_actual jsonb;
  v_expected jsonb;
  v_diff text;
begin
  insert into auth.users (id, instance_id, aud, role, email,
                          raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  values
    -- T1 Google: full_name 있음
    (v_t1, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'kakao-smoke-t1@example.invalid',
     '{"provider":"google","providers":["google"]}'::jsonb,
     '{"full_name":"구글이","iss":"https://accounts.google.com"}'::jsonb, now(), now()),
    -- T2 Google: full_name 없음 → 이메일(불변 — 합격선 4가 지키는 것)
    (v_t2, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'kakao-smoke-t2@example.invalid',
     '{"provider":"google","providers":["google"]}'::jsonb,
     '{"iss":"https://accounts.google.com"}'::jsonb, now(), now()),
    -- T3 기존 스모크 꼴: raw_app_meta_data 없음
    (v_t3, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'kakao-smoke-t3@example.invalid', null,
     '{"full_name":"스모크U"}'::jsonb, now(), now()),
    -- T4 카카오: 닉네임 있음, 이메일 없음
    (v_t4, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     null,
     '{"provider":"kakao","providers":["kakao"]}'::jsonb,
     '{"full_name":"카카오닉","sub":"4411","provider_id":"4411"}'::jsonb, now(), now()),
    -- T5 카카오: 닉네임 키 없음, 이메일 없음 → 가입 성공 + 기본 이름(합격선 1·2)
    (v_t5, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     null,
     '{"provider":"kakao","providers":["kakao"]}'::jsonb,
     '{"sub":"4412","provider_id":"4412"}'::jsonb, now(), now()),
    -- T6 카카오: 닉네임 없음, 이메일 있음 → 이메일이 이름이 되지 않는다
    (v_t6, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'kakao-smoke-t6@example.invalid',
     '{"provider":"kakao","providers":["kakao"]}'::jsonb,
     '{"sub":"4413"}'::jsonb, now(), now()),
    -- T7 판별 불가: 메타 모두 비어 있고 이메일 없음 → 가입 성공 + 기본 이름
    (v_t7, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     null, '{}'::jsonb, '{}'::jsonb, now(), now()),
    -- T8 Google 꼴인데 이름이 '연습 봇' — Google 규칙은 이 기능이 바꾸지 않는다
    (v_t8, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'kakao-smoke-t8@example.invalid',
     '{"provider":"google","providers":["google"]}'::jsonb,
     '{"full_name":"연습 봇"}'::jsonb, now(), now());

  v_actual := jsonb_build_object(
    'H1', public.kakao_display_name('{"full_name":"두두"}', null),
    'H2_name', public.kakao_display_name('{"name":"두두"}', null),
    'H2_preferred', public.kakao_display_name('{"preferred_username":"두두"}', null),
    'H2_user_name', public.kakao_display_name('{"user_name":"두두"}', null),
    'H2_nickname', public.kakao_display_name('{"nickname":"두두"}', null),
    'H2_order', public.kakao_display_name('{"nickname":"넷째","full_name":"첫째"}', null),
    'H3', public.kakao_display_name('{"full_name":"  두두  "}', null),
    'H4_empty', public.kakao_display_name('{}', null),
    'H4_null', public.kakao_display_name(null, null),
    'H5', public.kakao_display_name('{"full_name":"   "}', null),
    'H6', public.kakao_display_name('{"full_name":"a@b.co"}', null),
    'H7', public.kakao_display_name('{"full_name":"Me@X.com"}', 'me@x.com'),
    'H7_not_email_shape', public.kakao_display_name('{"full_name":"ME"}', 'me'),
    'H8', public.kakao_display_name('{"full_name":"4411","sub":"4411"}', null),
    'H8_provider_id', public.kakao_display_name('{"full_name":"4411","provider_id":"4411"}', null),
    'H9', public.kakao_display_name('{"full_name":"   ","name":"두두"}', null),
    'H10_bot', public.kakao_display_name('{"full_name":"연습 봇"}', null),
    'H10_tomb', public.kakao_display_name('{"full_name":"탈퇴한 사용자"}', null),
    'H10_similar', public.kakao_display_name('{"full_name":"연습 봇 아님"}', null),
    'K1', public.is_kakao_signup('{"provider":"kakao"}', null),
    'K2', public.is_kakao_signup('{}', '{"iss":"https://kapi.kakao.com/v2/user/me"}'),
    'K2_kauth', public.is_kakao_signup('{}', '{"iss":"https://kauth.kakao.com"}'),
    'K2_lookalike', public.is_kakao_signup('{}', '{"iss":"https://evil.com/kakao.com"}'),
    'K3', public.is_kakao_signup('{"provider":"google"}', '{"iss":"https://accounts.google.com"}'),
    'K4', public.is_kakao_signup(null, null),
    'T1', (select display_name from public.profiles where id = v_t1),
    'T2', (select display_name from public.profiles where id = v_t2),
    'T3', (select display_name from public.profiles where id = v_t3),
    'T4', (select display_name from public.profiles where id = v_t4),
    'T4_stats', (select count(*) from public.player_stats where user_id = v_t4),
    'T5', (select display_name from public.profiles where id = v_t5),
    'T5_stats', (select count(*) from public.player_stats where user_id = v_t5),
    'T6', (select display_name from public.profiles where id = v_t6),
    'T7', (select display_name from public.profiles where id = v_t7),
    'T8', (select display_name from public.profiles where id = v_t8),
    'anon_can_call', has_function_privilege('anon', 'public.kakao_display_name(jsonb, text)', 'execute'),
    'auth_can_call', has_function_privilege('authenticated', 'public.kakao_display_name(jsonb, text)', 'execute'),
    'auth_can_call_k', has_function_privilege('authenticated', 'public.is_kakao_signup(jsonb, jsonb)', 'execute'),
    'auth_can_call_trigger', has_function_privilege('authenticated', 'public.handle_new_user()', 'execute')
  );

  v_expected := jsonb_build_object(
    'H1', '두두',
    'H2_name', '두두',
    'H2_preferred', '두두',
    'H2_user_name', '두두',
    'H2_nickname', '두두',
    'H2_order', '첫째',
    'H3', '두두',
    'H4_empty', v_default,
    'H4_null', v_default,
    'H5', v_default,
    'H6', v_default,
    'H7', v_default,
    'H7_not_email_shape', v_default,
    'H8', v_default,
    'H8_provider_id', v_default,
    'H9', '두두',
    'H10_bot', v_default,
    'H10_tomb', v_default,
    'H10_similar', '연습 봇 아님',
    'K1', true,
    'K2', true,
    'K2_kauth', true,
    'K2_lookalike', false,
    'K3', false,
    'K4', false,
    'T1', '구글이',
    'T2', 'kakao-smoke-t2@example.invalid',
    'T3', '스모크U',
    'T4', '카카오닉',
    'T4_stats', 1,
    'T5', v_default,
    'T5_stats', 1,
    'T6', v_default,
    'T7', v_default,
    'T8', '연습 봇',
    'anon_can_call', false,
    'auth_can_call', false,
    'auth_can_call_k', false,
    'auth_can_call_trigger', false
  );

  select coalesce(string_agg(format('%s expected=%s actual=%s', e.key, e.value, coalesce(a.value::text, 'null')), '; '), '')
  into v_diff
  from jsonb_each(v_expected) e
  left join jsonb_each(v_actual) a on a.key = e.key
  where a.value is distinct from e.value;

  raise exception 'SMOKE RESULT ok=% %', v_diff = '',
    case when v_diff = '' then '' else ' FAILURES: ' || v_diff end;
end $$;
