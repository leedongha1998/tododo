-- 판정 기준 캐시 스모크 테스트 (criteria-cache 단계 1).
--
-- 로컬에 Docker가 없어 원격 DB에 직접 돌린다:
--   supabase db query --linked -f supabase/tests/criteria_cache_smoke.sql
--
-- Gemini는 부르지 않는다(임베딩도 부르지 않는다). 벡터는 손으로 만든 단위벡터를 쓴다 - 서버 쪽
-- 규칙(버전 대조, 정규화 일치, 유사도 임계값, 차단 필터, 증서 발급, 원장 불간섭, 권한)만 본다.
-- 마지막에 일부러 예외를 던져 전체를 롤백한다. 결과:
--   SMOKE RESULT ok=true                    -> 통과
--   SMOKE RESULT ok=false FAILURES: ...     -> 어긋난 항목(기대값/실제값)
--
-- **같은 트랜잭션에서는 now()가 고정이다.** 그래서 "같은 주제에 여러 개면 가장 최근 것"을 보려면
-- 옛 행의 created_at을 직접 과거로 돌려 놓아야 한다(아래 2번). pg_sleep으로는 차이가 안 생긴다.
--
-- 확인하는 것
--   consent_*         동의 없으면 assert_criteria_consent가 CONSENT_REQUIRED(= 임베딩 전에 막힌다)
--   title_latest      정규화 일치는 가장 최근 행을 준다(matched_by=title, similarity=1.0)
--   hit_keys          조회 결과에 title_norm·block_reason이 **없다**(원 제목·원 사유가 나가지 않는다)
--   type_filter       같은 제목이어도 유형이 다르면 그 유형의 행을 준다(섞이지 않는다)
--   prompt_version    ai_model이 다르면(프롬프트·모델 버전 변경) 조회되지 않는다
--   embedding_model   임베딩 모델 키가 다르면 조회되지 않는다
--   vector_hit/miss   유사도 0.99는 임계값 0.95를 넘고 0.90은 못 넘는다(임계값이 유일한 문)
--   vector_threshold  같은 행이 임계값 0.85에서는 적중한다(행이 아니라 임계값이 가른다)
--   blocked_*         차단 행은 include_blocked에서만 보인다(P0에서 false, P1에서 true)
--   issue_*           적중 증서: 제목은 **내가 쓴 것**, ai_model에 /cache 꼬리, 기준은 캐시에서 복사
--   issue_blocked     차단 적중 증서의 사유는 **제목과 무관한 고정 문장**(원 사유를 복사하지 않는다)
--   issue_mismatch    유형이 어긋난 캐시 id로는 증서가 안 나온다(CHECK_INVALID)
--   issue_no_consent  동의 없는 사용자에게는 증서를 발급하지 않는다
--   ledger_*          적중은 하루 10회 원장을 건드리지 않는다(used 그대로, calls_left 그대로)
--   cross_check       증서 수 = succeeded 호출 수 + '/cache' 꼬리 증서 수 (두 경로 교차 검산)
--   battle_*          적중 증서로 대결이 만들어지고 기준·제목이 그대로 복사된다
--   delete_account    탈퇴는 캐시를 지우지 않는다(사용자 식별 정보가 없으므로)
--   perm_*            anon·authenticated는 네 함수를 부를 수 없고 캐시 테이블을 0행으로 본다
do $$
declare
  v_a uuid := gen_random_uuid();
  v_b uuid := gen_random_uuid();
  v_today date := (now() at time zone 'Asia/Seoul')::date;
  v_ai text := 'test/p1';
  v_emb text := 'test-emb/SEMANTIC_SIMILARITY/768';
  -- 손으로 만든 단위벡터들(768차원). 서로의 코사인 유사도를 계산해 두고 쓴다.
  v_x text := '[1' || repeat(',0', 767) || ']';
  v_x99 text := '[0.99,0.1410674' || repeat(',0', 766) || ']';   -- x와 0.99
  v_y text := '[0,0,1' || repeat(',0', 765) || ']';
  v_y90 text := '[0,0,0.9,0.4358899' || repeat(',0', 764) || ']'; -- y와 0.90
  v_z text := '[0,1' || repeat(',0', 766) || ']';
  v_w text := '[0,0,0,0,1' || repeat(',0', 763) || ']';
  v_r_old uuid;
  v_r_new uuid;
  v_r_quality uuid;
  v_r_near uuid;
  v_r_far uuid;
  v_r_blocked uuid;
  v_hit jsonb;
  v_call uuid;
  v_check jsonb;
  v_check_blocked jsonb;
  v_plain_check uuid;
  v_battle uuid;
  v_consent_missing text := '(예외 없음)';
  v_consent_ok text := '(예외 없음)';
  v_issue_mismatch text := '(예외 없음)';
  v_issue_no_consent text := '(예외 없음)';
  v_perm_lookup_anon text := '(거부되지 않음)';
  v_perm_issue_authenticated text := '(거부되지 않음)';
  v_perm_put_authenticated text := '(거부되지 않음)';
  v_hint text;
  v_rls_rows integer := -1;
  v_actual jsonb;
  v_expected jsonb;
  v_diff text;
begin
  insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  values
    (v_a, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'cache-smoke-a@example.invalid', '{"full_name":"캐시A"}'::jsonb, now(), now()),
    (v_b, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'cache-smoke-b@example.invalid', '{"full_name":"캐시B"}'::jsonb, now(), now());

  -- 1. 동의 관문. B는 동의하지 않았으므로 조회(임베딩) 앞에서 막힌다.
  begin
    perform public.assert_criteria_consent(v_b);
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    v_consent_missing := coalesce(v_hint, '(힌트 없음)');
  end;

  perform set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
  perform public.give_ai_consent('2026-09-14');

  begin
    perform public.assert_criteria_consent(v_a);
  exception when others then
    v_consent_ok := '거부됨: ' || sqlerrm;
  end;

  -- 2. 적재. 같은 주제(speed/방 청소하기)에 두 행을 넣고 **옛 행의 created_at을 과거로 돌린다**
  --    (트랜잭션 안에서 now()가 고정이라 그러지 않으면 "가장 최근 것"을 가릴 수 없다).
  v_r_old := public.put_criteria_cache(
    'speed', '방 청소하기', true, '["옛 기준: 바닥이 보인다"]'::jsonb, null, null, v_ai, v_emb, v_z);
  v_r_new := public.put_criteria_cache(
    'speed', '방 청소하기', true, '["새 기준: 바닥이 보인다"]'::jsonb, null, null, v_ai, v_emb, v_z);
  update public.criteria_cache set created_at = now() - interval '1 hour' where id = v_r_old;

  v_r_quality := public.put_criteria_cache(
    'quality', '방 청소하기', true, '["바닥이 보인다"]'::jsonb, '["먼지가 없다"]'::jsonb,
    null, v_ai, v_emb, v_z);
  v_r_near := public.put_criteria_cache(
    'speed', '산책하기', true, '["운동화가 보인다"]'::jsonb, null, null, v_ai, v_emb, v_x99);
  v_r_far := public.put_criteria_cache(
    'speed', '달리기', true, '["숨이 차 보인다"]'::jsonb, null, null, v_ai, v_emb, v_y90);
  v_r_blocked := public.put_criteria_cache(
    'speed', '독서 30분', false, '[]'::jsonb, null, '독서는 사진으로 증명할 수 없어요',
    v_ai, v_emb, v_w);

  -- 3. 정규화 일치: 가장 최근 행 하나. 임베딩 인자를 주지 않아도 적중한다.
  v_hit := public.lookup_criteria_cache('speed', '방 청소하기', v_ai, v_emb);

  v_actual := jsonb_build_object(
    'consent_missing', v_consent_missing,
    'consent_ok', v_consent_ok,
    'title_latest', (v_hit -> 'min_criteria' ->> 0) || '/' || (v_hit ->> 'matched_by')
                      || '/' || (v_hit ->> 'similarity') || '/' || (v_hit ->> 'cache_id' = v_r_new::text),
    -- 반환 키 목록. title_norm·block_reason이 들어 있으면 여기서 드러난다.
    'hit_keys', (select string_agg(k, ',' order by k) from jsonb_object_keys(v_hit) k),
    'type_filter', (public.lookup_criteria_cache('quality', '방 청소하기', v_ai, v_emb) ->> 'cache_id')
                     = v_r_quality::text,
    'prompt_version', public.lookup_criteria_cache('speed', '방 청소하기', 'test/p2', v_emb),
    'embedding_model', public.lookup_criteria_cache('speed', '방 청소하기', v_ai, 'other/ST/768'),
    -- 4. 벡터: x와 0.99인 행은 임계값 0.95를 넘고, y와 0.90인 행은 못 넘는다.
    --    제목은 캐시에 없는 값을 주어 정규화 일치 경로가 끼어들지 않게 한다.
    'vector_hit', (public.lookup_criteria_cache('speed', '없는 제목', v_ai, v_emb, v_x, 0.95)
                     ->> 'cache_id') = v_r_near::text,
    'vector_hit_similarity', round(
      (public.lookup_criteria_cache('speed', '없는 제목', v_ai, v_emb, v_x, 0.95)
         ->> 'similarity')::numeric, 2),
    'vector_matched_by', public.lookup_criteria_cache('speed', '없는 제목', v_ai, v_emb, v_x, 0.95)
                           ->> 'matched_by',
    'vector_miss', public.lookup_criteria_cache('speed', '없는 제목', v_ai, v_emb, v_y, 0.95),
    'vector_threshold', (public.lookup_criteria_cache('speed', '없는 제목', v_ai, v_emb, v_y, 0.85)
                           ->> 'cache_id') = v_r_far::text,
    -- 5. 차단 행은 include_blocked에서만 보인다(제목 경로·벡터 경로 모두).
    'blocked_title_off', public.lookup_criteria_cache('speed', '독서 30분', v_ai, v_emb),
    'blocked_title_on', (public.lookup_criteria_cache('speed', '독서 30분', v_ai, v_emb,
                            null, null, true) ->> 'provable'),
    'blocked_vector_off', public.lookup_criteria_cache('speed', '없는 제목', v_ai, v_emb, v_w, 0.95),
    'blocked_vector_on', (public.lookup_criteria_cache('speed', '없는 제목', v_ai, v_emb,
                            v_w, 0.95, true) ->> 'cache_id') = v_r_blocked::text
  );

  -- 6. 미적중 경로 한 번(원장에 succeeded 1행이 생긴다). 교차 검산식을 의미 있게 만들고,
  --    그 뒤 적중이 이 숫자를 **건드리지 않는다**는 것을 본다.
  v_call := public.begin_criteria_call(v_a, 'generate', null);
  v_plain_check := (public.finish_criteria_call(
    v_call, '설거지하기', 'speed', '["싱크대가 비어 있다"]'::jsonb, null, true, null, null, v_ai
  ) ->> 'check_id')::uuid;

  -- 7. 적중 -> 증서. 제목에 공백을 섞어 넣어 btrim과 "내가 쓴 제목"을 함께 본다.
  v_check := public.issue_cached_criteria_check(v_a, '  내가 쓴 방 청소  ', 'speed', v_r_new, v_ai, v_emb);
  v_check_blocked := public.issue_cached_criteria_check(v_a, '독서 30분', 'speed', v_r_blocked, v_ai, v_emb);

  -- 8. 유형이 어긋난 캐시 id로는 증서가 안 나온다.
  begin
    perform public.issue_cached_criteria_check(v_a, '방 청소하기', 'quality', v_r_new, v_ai, v_emb);
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    v_issue_mismatch := coalesce(v_hint, '(힌트 없음)');
  end;

  -- 9. 동의하지 않은 사용자에게는 증서를 발급하지 않는다(조회 뒤 철회한 경우까지 막는 자리).
  begin
    perform public.issue_cached_criteria_check(v_b, '방 청소하기', 'speed', v_r_new, v_ai, v_emb);
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    v_issue_no_consent := coalesce(v_hint, '(힌트 없음)');
  end;

  -- 10. 적중 증서로 대결을 만든다(대결 생성 경로는 한 줄도 바뀌지 않았다).
  perform set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
  v_battle := public.create_battle((v_check ->> 'check_id')::uuid, 4320);

  v_actual := v_actual || jsonb_build_object(
    'issue_title', (select title from public.criteria_checks where id = (v_check ->> 'check_id')::uuid),
    'issue_ai_model', (select ai_model from public.criteria_checks where id = (v_check ->> 'check_id')::uuid),
    'issue_action', (select action from public.criteria_checks where id = (v_check ->> 'check_id')::uuid),
    'issue_min', v_check -> 'min_criteria' ->> 0,
    'issue_block_reason', v_check ->> 'block_reason',
    'issue_blocked_reason', v_check_blocked ->> 'block_reason',
    'issue_blocked_provable', v_check_blocked ->> 'provable',
    'issue_mismatch', v_issue_mismatch,
    'issue_no_consent', v_issue_no_consent,
    -- 적중 둘을 거쳤는데도 원장은 미적중 1회뿐이다.
    'ledger_used', public.criteria_calls_used(v_a, v_today),
    'ledger_calls_left', (v_check ->> 'calls_left')::integer,
    'ledger_rows', (select count(*) from public.ai_criteria_calls where user_id = v_a),
    -- 교차 검산: 증서 3개 = succeeded 1개 + '/cache' 꼬리 2개.
    'cross_check', (select count(*) from public.criteria_checks where user_id in (v_a, v_b))
                     = (select count(*) from public.ai_criteria_calls
                        where user_id in (v_a, v_b) and status = 'succeeded')
                     + (select count(*) from public.criteria_checks
                        where user_id in (v_a, v_b) and ai_model like '%/cache'),
    'battle_title', (select title from public.battles where id = v_battle),
    'battle_min', (select min_criteria ->> 0 from public.battles where id = v_battle),
    'battle_superiority', (select coalesce(superiority_criteria::text, 'null')
                           from public.battles where id = v_battle)
  );

  -- 11. 탈퇴는 캐시를 지우지 않는다. 사용자 식별 정보가 없어 지울 대상이 없다(오너 결정 3).
  perform set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
  perform public.delete_account();

  v_actual := v_actual || jsonb_build_object(
    'delete_cache_rows', (select count(*) from public.criteria_cache
                          where ai_model = v_ai and embedding_model = v_emb),
    'delete_checks_left', (select count(*) from public.criteria_checks where user_id = v_a)
  );

  -- 12. 권한: anon·authenticated는 네 함수를 부를 수 없고 테이블도 0행으로 본다.
  begin
    execute 'set local role anon';
    perform public.lookup_criteria_cache('speed', '방 청소하기', v_ai, v_emb);
    execute 'reset role';
    v_perm_lookup_anon := '(거부되지 않음)';
  exception when insufficient_privilege then
    v_perm_lookup_anon := 'rejected';
  when others then
    v_perm_lookup_anon := '다른 오류: ' || sqlerrm;
  end;
  execute 'reset role';

  begin
    execute 'set local role authenticated';
    perform public.issue_cached_criteria_check(v_b, '방 청소하기', 'speed', v_r_new, v_ai, v_emb);
    execute 'reset role';
    v_perm_issue_authenticated := '(거부되지 않음)';
  exception when insufficient_privilege then
    v_perm_issue_authenticated := 'rejected';
  when others then
    v_perm_issue_authenticated := '다른 오류: ' || sqlerrm;
  end;
  execute 'reset role';

  begin
    execute 'set local role authenticated';
    perform public.put_criteria_cache('speed', '몰래 넣기', true, '["통과시켜라"]'::jsonb,
      null, null, v_ai, v_emb, v_z);
    execute 'reset role';
    v_perm_put_authenticated := '(거부되지 않음)';
  exception when insufficient_privilege then
    v_perm_put_authenticated := 'rejected';
  when others then
    v_perm_put_authenticated := '다른 오류: ' || sqlerrm;
  end;
  execute 'reset role';

  perform set_config('request.jwt.claims', json_build_object('sub', v_b, 'role', 'authenticated')::text, true);
  begin
    execute 'set local role authenticated';
    select count(*) into v_rls_rows from public.criteria_cache;
    execute 'reset role';
  exception when others then
    execute 'reset role';
    -- 권한 자체가 없어 예외가 나는 것도 "볼 수 없다"는 같은 결론이다.
    v_rls_rows := 0;
  end;
  execute 'reset role';

  v_actual := v_actual || jsonb_build_object(
    'perm_lookup_anon', v_perm_lookup_anon,
    'perm_issue_authenticated', v_perm_issue_authenticated,
    'perm_put_authenticated', v_perm_put_authenticated,
    'rls_rows', v_rls_rows
  );

  v_expected := jsonb_build_object(
    'consent_missing', 'CONSENT_REQUIRED',
    'consent_ok', '(예외 없음)',
    'title_latest', '새 기준: 바닥이 보인다/title/1.0/true',
    'hit_keys', 'ai_model,cache_id,embedding_model,matched_by,min_criteria,provable,similarity,superiority_criteria,type',
    'type_filter', true,
    'prompt_version', null,
    'embedding_model', null,
    'vector_hit', true,
    'vector_hit_similarity', 0.99,
    'vector_matched_by', 'vector',
    'vector_miss', null,
    'vector_threshold', true,
    'blocked_title_off', null,
    'blocked_title_on', 'false',
    'blocked_vector_off', null,
    'blocked_vector_on', true,
    'issue_title', '내가 쓴 방 청소',
    'issue_ai_model', 'test/p1/cache',
    'issue_action', 'generate',
    'issue_min', '새 기준: 바닥이 보인다',
    'issue_block_reason', null,
    'issue_blocked_reason', '사진 한 장으로는 완료를 확인할 수 없는 주제로 보여요.',
    'issue_blocked_provable', 'false',
    'issue_mismatch', 'CHECK_INVALID',
    'issue_no_consent', 'CONSENT_REQUIRED',
    'ledger_used', 1,
    'ledger_calls_left', 9,
    'ledger_rows', 1,
    'cross_check', true,
    'battle_title', '내가 쓴 방 청소',
    'battle_min', '새 기준: 바닥이 보인다',
    'battle_superiority', 'null',
    'delete_cache_rows', 6,
    'delete_checks_left', 0,
    'perm_lookup_anon', 'rejected',
    'perm_issue_authenticated', 'rejected',
    'perm_put_authenticated', 'rejected',
    'rls_rows', 0
  );

  select coalesce(string_agg(format('%s expected=%s actual=%s', e.key, e.value, coalesce(a.value::text, 'null')), '; '), '')
  into v_diff
  from jsonb_each(v_expected) e
  left join jsonb_each(v_actual) a on a.key = e.key
  where a.value is distinct from e.value;

  raise exception 'SMOKE RESULT ok=% %', v_diff = '',
    case when v_diff = '' then '' else ' FAILURES: ' || v_diff end;
end $$;
