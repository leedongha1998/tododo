-- 별명 흐름 스모크 테스트 (nickname 1단계).
--
-- 로컬에 Docker가 없어 원격 DB에 직접 돌린다:
--   supabase db query --linked -f supabase/tests/nickname_flow_smoke.sql
--
-- 가짜 사용자 다섯을 만들어 별명 경로를 전부 지나고, 마지막에 일부러 예외를 던져 트랜잭션 전체를
-- 롤백한다(실제 데이터는 남지 않는다). 결과:
--   SMOKE RESULT ok=t                    -> 통과
--   SMOKE RESULT ok=f  FAILURES: ...     -> 어긋난 항목(기대값/실제값)
--
-- ** 같은 트랜잭션에서는 now()가 고정이다. ** 그래서 "거부된 확정이 confirmed_at을 건드리지 않았다"는
-- confirmed_at을 과거 리터럴로 미뤄 둔 뒤 그 값이 그대로인지로 본다.
-- ** volatile 함수 호출은 변수로 먼저 받는다 ** - 같은 문장 안의 서브질의는 문장 시작 스냅숏을 읽어
-- 방금 쓴 값을 보지 못한다.
-- ** 거부를 감싼 begin … exception 블록은 서브트랜잭션이다 ** - 그 안의 set local role도 함께 되돌아간다.
--
-- 확인하는 것 (design §11.2 1~9 + §11.1-4 양성 대조)
--   new_*        1 새 계정 기본 이름: 실명·이메일 아님, 규칙 통과, @ 없음, 상태 행 (null, null), 점수 행 있음
--   write_*      2 직접 쓰기 거부: 자기 이름·deleted_at update, 남의 행 update, insert, delete 전부 권한 오류.
--                  같은 롤의 select는 모든 프로필을 읽는다
--   set_*        3 set_nickname: 정규화 값 반환·저장, confirmed, 같은 이름 재확정·남이 쓰는 이름(중복) 성공
--   reject_*     4 LENGTH / CHARS / RESERVED(detail=연습봇) / BANNED(detail 없음). 거부 뒤 이름·confirmed_at 그대로
--   others_*     5 남·봇·묘비 이름 그대로, 묘비 uid로 세 RPC 전부 ACCOUNT_DELETED
--   perm_*       6 anon은 세 RPC 거부, 로그인 없으면 '로그인이 필요합니다.', authenticated는 내부 함수
--                  다섯·새 테이블 셋 거부
--   delete_*     7 탈퇴: 묘비 이름, nickname_states 0행, 투두도 지워진다
--   suggest_*    8 suggest_nickname: 규칙 통과, 아무것도 쓰지 않는다
--   reset_*      9 2단계(B)의 대상 조건: 상태 행이 없는 사람만 고른다. 상태 행·reset_at에 따른 관문 상태
--   pool_*       양성 대조: 기본 별명 조합에 걸리는 금칙어를 넣으면 assert_nickname_pool_valid()가 실패한다
do $$
declare
  v_bot uuid := public.bot_user_id();
  v_a uuid := gen_random_uuid();   -- 주인공
  v_b uuid := gen_random_uuid();   -- 남(이름이 그대로인지, 중복 이름)
  v_c uuid := gen_random_uuid();   -- 상태 행이 있는 사용자(2단계 대상 아님)
  v_d uuid := gen_random_uuid();   -- 상태 행이 없는 사용자(2단계 이전 가입자 흉내)
  v_t uuid := gen_random_uuid();   -- 탈퇴

  v_a_initial text;
  v_b_name text;
  v_set text;
  v_set_same text;
  v_set_dup text;
  v_state_a jsonb;
  v_state_c jsonb;
  v_state_d jsonb;
  v_state_d_reset jsonb;
  v_suggest text;
  v_a_before text;
  v_a_after text;
  v_a_confirmed_before timestamptz;
  v_a_confirmed_after timestamptz;
  v_read_count integer := -1;

  v_rej_length text := '(거부되지 않음)';
  v_rej_chars text := '(거부되지 않음)';
  v_rej_reserved text := '(거부되지 않음)';
  v_rej_reserved_detail text;
  v_rej_banned text := '(거부되지 않음)';
  v_rej_banned_detail text;
  v_t_results text := '';
  v_anon_results text := '';
  v_nologin_results text := '';
  v_write_results text := '';
  v_perm_results text := '';
  v_pool_err text := '(실패하지 않음)';
  v_pool_after text;
  v_reset_targets text;

  v_sql text;
  v_hint text;
  v_detail text;

  v_actual jsonb := '{}'::jsonb;
  v_expected jsonb;
  v_diff text;
begin
  -- -------------------------------------------------------------------------
  -- 1. 새 계정의 기본 이름 (P0-1)
  -- -------------------------------------------------------------------------
  insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  values
    (v_a, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'nick-smoke-a@example.invalid', '{"full_name":"스모크실명","name":"스모크실명"}'::jsonb, now(), now()),
    (v_b, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'nick-smoke-b@example.invalid', '{"full_name":"스모크B"}'::jsonb, now(), now()),
    (v_c, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'nick-smoke-c@example.invalid', '{"full_name":"스모크C"}'::jsonb, now(), now()),
    (v_d, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'nick-smoke-d@example.invalid', '{"full_name":"스모크D"}'::jsonb, now(), now()),
    (v_t, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'nick-smoke-t@example.invalid', '{"full_name":"스모크T"}'::jsonb, now(), now());

  select display_name into v_a_initial from public.profiles where id = v_a;

  v_actual := v_actual || jsonb_build_object(
    'new_not_real_name', v_a_initial not in ('스모크실명', 'nick-smoke-a@example.invalid'),
    'new_passes_rule', (public.check_nickname(v_a_initial)).code is null,
    'new_no_at', (select count(*) from public.profiles
                  where id in (v_a, v_b, v_c, v_d, v_t) and display_name like '%@%'),
    'new_no_real_names', (select count(*) from public.profiles
                          where id in (v_a, v_b, v_c, v_d, v_t) and display_name like '스모크%'),
    'new_state', (select concat_ws('/', count(*), count(confirmed_at), count(reset_at))
                  from public.nickname_states where user_id in (v_a, v_b, v_c, v_d, v_t)),
    'new_stats', (select count(*) from public.player_stats where user_id in (v_a, v_b, v_c, v_d, v_t))
  );

  -- -------------------------------------------------------------------------
  -- 2. 직접 쓰기 거부 (P0-5). authenticated 롤 + A의 JWT로 위장한다.
  -- -------------------------------------------------------------------------
  perform set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);

  foreach v_sql in array array[
    format('update public.profiles set display_name = %L where id = %L', '연습 봇', v_a),
    format('update public.profiles set deleted_at = now() where id = %L', v_a),
    format('update public.profiles set display_name = %L where id = %L', '남의 이름', v_b),
    format('insert into public.profiles (id, display_name) values (%L, %L)', gen_random_uuid(), '가짜'),
    format('delete from public.profiles where id = %L', v_a)
  ] loop
    begin
      execute 'set local role authenticated';
      execute v_sql;
      execute 'reset role';
      v_write_results := v_write_results || '/열림';
    exception when insufficient_privilege then
      v_write_results := v_write_results || '/거부';
    when others then
      v_write_results := v_write_results || '/다른 오류: ' || sqlerrm;
    end;
    execute 'reset role';
  end loop;

  -- 읽기는 그대로다(모집 목록·상대 카드가 깨지지 않는다). 봇·남 포함 다섯 행이 보인다.
  execute 'set local role authenticated';
  select count(*) into v_read_count
  from public.profiles
  where id in (v_a, v_b, v_c, v_d, v_bot);
  execute 'reset role';

  v_actual := v_actual || jsonb_build_object(
    'write_results', v_write_results,
    'write_read_count', v_read_count,
    'write_a_unchanged', (select display_name = v_a_initial and deleted_at is null
                          from public.profiles where id = v_a)
  );

  -- -------------------------------------------------------------------------
  -- 3. set_nickname (관문 확정과 프로필 바꾸기가 같은 RPC). 실제 앱처럼 authenticated 롤로 부른다.
  -- -------------------------------------------------------------------------
  execute 'set local role authenticated';
  v_set := public.set_nickname('  수달   왕 ');
  v_state_a := public.get_my_nickname_state();
  v_set_same := public.set_nickname('수달 왕');
  execute 'reset role';

  -- B도 같은 이름을 쓴다(중복 허용, 오너 결정 5).
  perform set_config('request.jwt.claims', json_build_object('sub', v_b, 'role', 'authenticated')::text, true);
  v_set_dup := public.set_nickname('수달 왕');
  select display_name into v_b_name from public.profiles where id = v_b;

  v_actual := v_actual || jsonb_build_object(
    'set_returned', v_set,
    'set_stored', (select display_name from public.profiles where id = v_a),
    'set_confirmed_at', (select confirmed_at is not null from public.nickname_states where user_id = v_a),
    'set_state', v_state_a,
    'set_same_again', v_set_same,
    'set_duplicate', v_set_dup
  );

  -- -------------------------------------------------------------------------
  -- 4. 거부 코드. 거부 뒤 이름과 confirmed_at이 그대로인지(now()가 고정이라 과거 리터럴로 미뤄 둔다).
  -- -------------------------------------------------------------------------
  update public.nickname_states set confirmed_at = '2026-01-01 00:00:00+00' where user_id = v_a;
  perform set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);

  begin
    perform public.set_nickname('가');
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    v_rej_length := coalesce(v_hint, '(힌트 없음)');
  end;

  begin
    perform public.set_nickname('a@b.co');
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    v_rej_chars := coalesce(v_hint, '(힌트 없음)');
  end;

  begin
    perform public.set_nickname('연습  봇');
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint, v_detail = pg_exception_detail;
    v_rej_reserved := coalesce(v_hint, '(힌트 없음)');
    v_rej_reserved_detail := v_detail;
  end;

  begin
    perform public.set_nickname('씨발');
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint, v_detail = pg_exception_detail;
    v_rej_banned := coalesce(v_hint, '(힌트 없음)');
    v_rej_banned_detail := v_detail;
  end;

  v_actual := v_actual || jsonb_build_object(
    'reject_length', v_rej_length,
    'reject_chars', v_rej_chars,
    'reject_reserved', v_rej_reserved,
    'reject_reserved_detail', v_rej_reserved_detail,
    'reject_banned', v_rej_banned,
    'reject_banned_detail', coalesce(v_rej_banned_detail, ''),
    'reject_name_kept', (select display_name from public.profiles where id = v_a),
    'reject_confirmed_kept', (select confirmed_at = '2026-01-01 00:00:00+00'::timestamptz
                              from public.nickname_states where user_id = v_a)
  );

  -- -------------------------------------------------------------------------
  -- 7. 탈퇴 (5번이 묘비를 쓰므로 먼저 만든다). T에게 투두와 확정한 별명이 있다.
  -- -------------------------------------------------------------------------
  insert into public.todos (user_id, title) values (v_t, '별명 스모크 할 일');
  perform set_config('request.jwt.claims', json_build_object('sub', v_t, 'role', 'authenticated')::text, true);
  perform public.set_nickname('곧 떠날 사람');
  perform public.delete_account();

  v_actual := v_actual || jsonb_build_object(
    'delete_profile', (select display_name || '/' || (deleted_at is not null)::text
                       from public.profiles where id = v_t),
    'delete_state_rows', (select count(*) from public.nickname_states where user_id = v_t),
    'delete_todos', (select count(*) from public.todos where user_id = v_t),
    'delete_auth_user', (select count(*) from auth.users where id = v_t)
  );

  -- -------------------------------------------------------------------------
  -- 5. 남·봇·묘비. 묘비 uid의 (아직 만료되지 않은) JWT로 세 RPC를 부르면 전부 ACCOUNT_DELETED.
  -- -------------------------------------------------------------------------
  foreach v_sql in array array[
    'select public.set_nickname(''되살아난 이름'')',
    'select public.get_my_nickname_state()',
    'select public.suggest_nickname()'
  ] loop
    begin
      execute v_sql;
      v_t_results := v_t_results || '/(거부되지 않음)';
    exception when others then
      get stacked diagnostics v_hint = pg_exception_hint;
      v_t_results := v_t_results || '/' || coalesce(v_hint, '(힌트 없음)');
    end;
  end loop;

  v_actual := v_actual || jsonb_build_object(
    'others_b_name', (select display_name from public.profiles where id = v_b),
    'others_bot_name', (select display_name from public.profiles where id = v_bot),
    'others_tombstone_name', (select display_name from public.profiles where id = v_t),
    'others_tombstone_rpcs', v_t_results
  );

  -- -------------------------------------------------------------------------
  -- 6. 권한
  -- -------------------------------------------------------------------------
  -- 6a. anon은 세 RPC를 부를 수 없다.
  foreach v_sql in array array[
    'select public.get_my_nickname_state()',
    'select public.set_nickname(''수달 왕'')',
    'select public.suggest_nickname()'
  ] loop
    begin
      execute 'set local role anon';
      execute v_sql;
      execute 'reset role';
      v_anon_results := v_anon_results || '/열림';
    exception when insufficient_privilege then
      v_anon_results := v_anon_results || '/거부';
    when others then
      v_anon_results := v_anon_results || '/다른 오류: ' || sqlerrm;
    end;
    execute 'reset role';
  end loop;

  -- 6b. 로그인 없이(JWT에 sub가 없음) 부르면 첫 줄 가드가 막는다.
  perform set_config('request.jwt.claims', '{}', true);
  foreach v_sql in array array[
    'select public.get_my_nickname_state()',
    'select public.set_nickname(''수달 왕'')',
    'select public.suggest_nickname()'
  ] loop
    begin
      execute 'set local role authenticated';
      execute v_sql;
      execute 'reset role';
      v_nologin_results := v_nologin_results || '/열림';
    exception when others then
      v_nologin_results := v_nologin_results || '/' || sqlerrm;
    end;
    execute 'reset role';
  end loop;

  -- 6c. authenticated는 내부 함수 다섯과 새 테이블 셋을 직접 쓸 수 없다.
  perform set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
  foreach v_sql in array array[
    'select public.normalize_nickname(''수달'')',
    'select public.nickname_compare_key(''수달'')',
    'select public.check_nickname(''수달 왕'')',
    'select public.random_nickname()',
    'select public.assert_nickname_pool_valid()',
    'select count(*) from public.nickname_words',
    'select count(*) from public.nickname_blocked_terms',
    'select count(*) from public.nickname_states'
  ] loop
    begin
      execute 'set local role authenticated';
      execute v_sql;
      execute 'reset role';
      v_perm_results := v_perm_results || '/열림';
    exception when insufficient_privilege then
      v_perm_results := v_perm_results || '/거부';
    when others then
      v_perm_results := v_perm_results || '/다른 오류: ' || sqlerrm;
    end;
    execute 'reset role';
  end loop;

  v_actual := v_actual || jsonb_build_object(
    'perm_anon', v_anon_results,
    'perm_nologin', v_nologin_results,
    'perm_internal', v_perm_results
  );

  -- -------------------------------------------------------------------------
  -- 8. suggest_nickname: 규칙 통과, 아무것도 쓰지 않는다. 호출을 변수로 먼저 받는다.
  -- -------------------------------------------------------------------------
  select display_name into v_a_before from public.profiles where id = v_a;
  select confirmed_at into v_a_confirmed_before from public.nickname_states where user_id = v_a;
  execute 'set local role authenticated';
  v_suggest := public.suggest_nickname();
  execute 'reset role';
  select display_name into v_a_after from public.profiles where id = v_a;
  select confirmed_at into v_a_confirmed_after from public.nickname_states where user_id = v_a;

  v_actual := v_actual || jsonb_build_object(
    'suggest_passes_rule', (public.check_nickname(v_suggest)).code is null,
    'suggest_wrote_nothing', v_a_before = v_a_after
                             and v_a_confirmed_before is not distinct from v_a_confirmed_after
  );

  -- -------------------------------------------------------------------------
  -- 9. 2단계(B)의 대상 조건과 관문 상태. B 파일은 일회성이라 그 블록을 부르지 않고 조건만 고정한다.
  -- -------------------------------------------------------------------------
  -- D는 1단계 이전 가입자처럼 상태 행이 없다.
  delete from public.nickname_states where user_id = v_d;

  select string_agg(case p.id when v_c then 'C' when v_d then 'D' when v_t then 'T' end, ',' order by p.id = v_d)
  into v_reset_targets
  from public.profiles p
  where p.id in (v_c, v_d, v_t, v_bot)
    and p.deleted_at is null
    and p.id <> public.bot_user_id()
    and not exists (select 1 from public.nickname_states s where s.user_id = p.id);

  perform set_config('request.jwt.claims', json_build_object('sub', v_c, 'role', 'authenticated')::text, true);
  v_state_c := public.get_my_nickname_state();
  perform set_config('request.jwt.claims', json_build_object('sub', v_d, 'role', 'authenticated')::text, true);
  v_state_d := public.get_my_nickname_state();
  -- B가 하는 일(상태 행에 reset_at)을 흉내 내면 관문이 안내 줄을 띄운다.
  insert into public.nickname_states (user_id, reset_at) values (v_d, now());
  v_state_d_reset := public.get_my_nickname_state();

  v_actual := v_actual || jsonb_build_object(
    'reset_targets', v_reset_targets,
    'reset_state_fresh', v_state_c - 'nickname',
    'reset_state_fresh_name', (v_state_c ->> 'nickname') = (select display_name from public.profiles where id = v_c),
    'reset_state_no_row', v_state_d - 'nickname',
    'reset_state_after_reset', v_state_d_reset - 'nickname'
  );

  -- -------------------------------------------------------------------------
  -- 양성 대조(design §11.1-4): 기본 별명 조합(…수달)에 걸리는 금칙어를 넣으면 검증이 실패한다.
  -- 검증이 아무것도 안 하고 통과만 하는 함수가 아닌지 본다. 마지막에 지운다(어차피 전체가 롤백된다).
  -- -------------------------------------------------------------------------
  insert into public.nickname_blocked_terms (term, category, match) values ('수달', 'banned', 'contains');
  begin
    perform public.assert_nickname_pool_valid();
  exception when others then
    v_pool_err := sqlerrm;
  end;
  delete from public.nickname_blocked_terms where term = '수달';

  -- ** perform으로 진짜 부른다(리뷰 경고 2). ** 서브질의 안에 두면 결과를 참조하지 않는 호출을
  -- 플래너가 버려, 검증이 깨져 있어도 항상 'ok'가 나온다.
  begin
    perform public.assert_nickname_pool_valid();
    v_pool_after := 'ok';
  exception when others then
    v_pool_after := sqlerrm;
  end;

  v_actual := v_actual || jsonb_build_object(
    'pool_rejects_bad_term', v_pool_err like '규칙에 걸리는 기본 별명 조합이 40개%',
    'pool_ok_after_removal', v_pool_after
  );

  -- -------------------------------------------------------------------------
  -- 기대값
  -- -------------------------------------------------------------------------
  v_expected := jsonb_build_object(
    'new_not_real_name', true,
    'new_passes_rule', true,
    'new_no_at', 0,
    'new_no_real_names', 0,
    'new_state', '5/0/0',
    'new_stats', 5,

    'write_results', '/거부/거부/거부/거부/거부',
    'write_read_count', 5,
    'write_a_unchanged', true,

    'set_returned', '수달 왕',
    'set_stored', '수달 왕',
    'set_confirmed_at', true,
    'set_state', jsonb_build_object('nickname', '수달 왕', 'confirmed', true, 'was_reset', false),
    'set_same_again', '수달 왕',
    'set_duplicate', '수달 왕',

    'reject_length', 'NICKNAME_LENGTH',
    'reject_chars', 'NICKNAME_CHARS',
    'reject_reserved', 'NICKNAME_RESERVED',
    'reject_reserved_detail', '연습봇',
    'reject_banned', 'NICKNAME_BANNED',
    'reject_banned_detail', '',
    'reject_name_kept', '수달 왕',
    'reject_confirmed_kept', true,

    'delete_profile', '탈퇴한 사용자/true',
    'delete_state_rows', 0,
    'delete_todos', 0,
    'delete_auth_user', 0,

    'others_b_name', '수달 왕',
    'others_bot_name', '연습 봇',
    'others_tombstone_name', '탈퇴한 사용자',
    'others_tombstone_rpcs', '/ACCOUNT_DELETED/ACCOUNT_DELETED/ACCOUNT_DELETED',

    'perm_anon', '/거부/거부/거부',
    'perm_nologin', '/로그인이 필요합니다./로그인이 필요합니다./로그인이 필요합니다.',
    'perm_internal', '/거부/거부/거부/거부/거부/거부/거부/거부',

    'suggest_passes_rule', true,
    'suggest_wrote_nothing', true,

    'reset_targets', 'D',
    'reset_state_fresh', jsonb_build_object('confirmed', false, 'was_reset', false),
    'reset_state_fresh_name', true,
    'reset_state_no_row', jsonb_build_object('confirmed', false, 'was_reset', false),
    'reset_state_after_reset', jsonb_build_object('confirmed', false, 'was_reset', true),

    'pool_rejects_bad_term', true,
    'pool_ok_after_removal', 'ok'
  );

  select coalesce(string_agg(format('%s expected=%s actual=%s', e.key, e.value, coalesce(a.value::text, 'null')), '; '), '')
  into v_diff
  from jsonb_each(v_expected) e
  left join jsonb_each(v_actual) a on a.key = e.key
  where a.value is distinct from e.value;

  raise exception 'SMOKE RESULT ok=% %', v_diff = '',
    case when v_diff = '' then '' else ' FAILURES: ' || v_diff end;
end $$;
