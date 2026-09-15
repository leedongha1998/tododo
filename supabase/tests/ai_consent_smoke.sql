-- AI 데이터 제공 동의·철회 스모크 테스트.
--
-- 로컬에 Docker가 없어 원격 DB에 직접 돌린다:
--   supabase db query --linked -f supabase/tests/ai_consent_smoke.sql
--
-- 임시 사용자 넷으로 동의·참가·철회·탈퇴를 실제로 호출하고, 마지막에 일부러 예외를 던져
-- 트랜잭션 전체를 롤백한다. 결과:
--   SMOKE RESULT ok=true                    -> 통과
--   SMOKE RESULT ok=false FAILURES: ...     -> 어긋난 항목(기대값/실제값)
--
-- 확인하는 것
--   join_no_consent    동의 없는 참가는 CONSENT_REQUIRED로 막힌다
--   join_after_consent 동의하면 참가가 성립한다(active)
--   insert_no_consent  동의 없는 사용자의 대결 생성은 RLS 정책이 막는다(42501)
--   insert_consented   동의한 사용자는 만들 수 있다
--   anon_denied        anon 롤은 give_ai_consent 실행 권한이 없다
--   impact             철회 전 영향 조회 = 진행 중 2, 모집 중 1
--   withdraw           진행 중 2개는 포기(-3, 상대 승), 모집 중 1개는 취소
--   slots_kept         포기로 끝났으므로 하루 한도는 돌려주지 않는다
--   events             given -> withdrawn 순서로 이력이 남는다
--   join_after_withdraw 철회 후 참가는 다시 막힌다
--   withdraw_twice     동의 기록이 없으면 철회는 거부된다
--   delete_account     탈퇴하면 동의·이력 행이 남지 않는다
do $$
declare
  v_a uuid := gen_random_uuid();
  v_b uuid := gen_random_uuid();
  v_c uuid := gen_random_uuid();
  v_d uuid := gen_random_uuid();
  v_today date := (now() at time zone 'Asia/Seoul')::date;
  v_p1 uuid;
  v_p2 uuid;
  v_w1 uuid;
  v_w2 uuid;
  v_w3 uuid;
  v_hint text;
  v_join_no_consent text := '(예외 없음)';
  v_join_after_withdraw text := '(예외 없음)';
  v_insert_no_consent text := '(예외 없음)';
  v_insert_consented text := '(실패)';
  v_anon_denied text := '(예외 없음)';
  v_withdraw_twice boolean := false;
  v_impact jsonb;
  v_result jsonb;
  v_actual jsonb;
  v_expected jsonb;
  v_diff text;
begin
  insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  values
    (v_a, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'consent-smoke-a@example.invalid', '{"full_name":"스모크A"}'::jsonb, now(), now()),
    (v_b, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'consent-smoke-b@example.invalid', '{"full_name":"스모크B"}'::jsonb, now(), now()),
    (v_c, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'consent-smoke-c@example.invalid', '{"full_name":"스모크C"}'::jsonb, now(), now()),
    (v_d, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'consent-smoke-d@example.invalid', '{"full_name":"스모크D"}'::jsonb, now(), now());

  update public.player_stats set score = 10 where user_id in (v_a, v_b);

  -- B가 올린 모집 두 개(직접 insert라 정책을 거치지 않는다 — 정책은 아래에서 따로 본다).
  insert into public.battles (type, status, title, creator_id, duration_hours)
  values ('speed', 'pending', '모집 1', v_b, 72) returning id into v_p1;
  insert into public.battles (type, status, title, creator_id, duration_hours)
  values ('speed', 'pending', '모집 2', v_b, 72) returning id into v_p2;

  -- 1. 동의하지 않은 C의 참가는 막힌다.
  perform set_config('request.jwt.claims', json_build_object('sub', v_c, 'role', 'authenticated')::text, true);
  begin
    perform public.join_battle(v_p1);
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    v_join_no_consent := coalesce(v_hint, '(힌트 없음)');
  end;

  -- 2. 동의한 뒤에는 참가가 된다.
  perform public.give_ai_consent('2026-09-14');
  perform public.join_battle(v_p1);

  -- 3. 대결 생성 정책: 동의하지 않은 D는 막히고, 동의하면 만들 수 있다.
  perform set_config('request.jwt.claims', json_build_object('sub', v_d, 'role', 'authenticated')::text, true);
  begin
    -- 이 블록에서 예외가 나면 set local role도 함께 되돌아간다.
    execute 'set local role authenticated';
    insert into public.battles (type, status, title, creator_id, duration_hours)
    values ('speed', 'pending', '동의 없이 생성', v_d, 72);
    execute 'reset role';
  exception when insufficient_privilege then
    v_insert_no_consent := 'RLS 차단';
  end;

  perform public.give_ai_consent('2026-09-14');
  begin
    execute 'set local role authenticated';
    insert into public.battles (type, status, title, creator_id, duration_hours)
    values ('speed', 'pending', '동의 후 생성', v_d, 72);
    execute 'reset role';
    v_insert_consented := '성공';
  exception when others then
    execute 'reset role';
    v_insert_consented := '실패: ' || sqlerrm;
  end;

  -- 4. anon 롤에는 실행 권한이 없다.
  begin
    execute 'set local role anon';
    perform public.give_ai_consent('2026-09-14');
    execute 'reset role';
  exception when insufficient_privilege then
    v_anon_denied := '권한 없음';
  when others then
    v_anon_denied := '다른 오류: ' || sqlerrm;
  end;
  execute 'reset role';

  -- 5. 철회: A는 진행 중 2개(하나는 내가 만든 속도전, 하나는 상대가 만든 품질전)와 모집 1개를 갖는다.
  perform set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
  perform public.give_ai_consent('2026-09-14');

  insert into public.battles (type, status, title, creator_id, opponent_id, duration_hours, started_at, deadline_at)
  values ('speed', 'active', '진행 중 속도전', v_a, v_b, 72, now(), now() + interval '3 days')
  returning id into v_w1;
  insert into public.battle_participants (battle_id, user_id) values (v_w1, v_b);

  insert into public.battles (type, status, title, creator_id, opponent_id, duration_hours, started_at, deadline_at)
  values ('quality', 'judging', '판정 중 품질전', v_b, v_a, 72, now(), now() + interval '3 days')
  returning id into v_w2;
  insert into public.battle_participants (battle_id, user_id) values (v_w2, v_a);

  insert into public.battles (type, status, title, creator_id, duration_hours)
  values ('speed', 'pending', '내 모집', v_a, 72) returning id into v_w3;

  -- 오늘 매칭된 대결의 한도. 포기로 끝나면 돌려받지 못해야 한다.
  insert into public.daily_battle_slots (user_id, kst_date, battle_id) values (v_a, v_today, v_w1);

  v_impact := public.get_consent_withdrawal_impact();
  v_result := public.withdraw_ai_consent();

  -- 6. 철회 뒤에는 다시 막힌다.
  begin
    perform public.join_battle(v_p2);
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    v_join_after_withdraw := coalesce(v_hint, '(힌트 없음)');
  end;

  begin
    perform public.withdraw_ai_consent();
  exception when others then
    v_withdraw_twice := true;
  end;

  -- 7. 탈퇴하면 동의·이력이 사라진다.
  perform set_config('request.jwt.claims', json_build_object('sub', v_d, 'role', 'authenticated')::text, true);
  perform public.delete_account();

  v_actual := jsonb_build_object(
    'join_no_consent', v_join_no_consent,
    'join_after_consent', (select status from public.battles where id = v_p1),
    'insert_no_consent', v_insert_no_consent,
    'insert_consented', v_insert_consented,
    'anon_denied', v_anon_denied,
    'impact', v_impact,
    'withdraw', v_result,
    'w1', (select status || '/' || coalesce(case winner_id when v_a then 'A' when v_b then 'B' end, '-')
                  || '/' || coalesce(case forfeited_by when v_a then 'A' when v_b then 'B' end, '-')
           from public.battles where id = v_w1),
    'w2', (select status || '/' || coalesce(case winner_id when v_a then 'A' when v_b then 'B' end, '-')
                  || '/' || coalesce(case forfeited_by when v_a then 'A' when v_b then 'B' end, '-')
           from public.battles where id = v_w2),
    'w3', (select status from public.battles where id = v_w3),
    'a_outcomes', (select string_agg(coalesce(outcome, '-'), ',' order by battle_id = v_w2)
                   from public.battle_participants
                   where user_id = v_a and battle_id in (v_w1, v_w2)),
    'a_stats', (select concat_ws('/', score, wins, losses, draws) from public.player_stats where user_id = v_a),
    'b_stats', (select concat_ws('/', score, wins, losses, draws) from public.player_stats where user_id = v_b),
    'slots_kept', (select count(*) from public.daily_battle_slots where user_id = v_a),
    'a_consent_rows', (select count(*) from public.ai_consents where user_id = v_a),
    'a_events', (select string_agg(event, ',' order by id) from public.ai_consent_events where user_id = v_a),
    'c_consent_rows', (select count(*) from public.ai_consents where user_id = v_c),
    'join_after_withdraw', v_join_after_withdraw,
    'withdraw_twice_rejected', v_withdraw_twice,
    'd_consent_rows', (select count(*) from public.ai_consents where user_id = v_d),
    'd_event_rows', (select count(*) from public.ai_consent_events where user_id = v_d)
  );

  -- A: 10 -3(w1 포기) -3(w2 포기) = 4, 패 2 / B: 10 +3 +3 = 16, 승 2
  v_expected := jsonb_build_object(
    'join_no_consent', 'CONSENT_REQUIRED',
    'join_after_consent', 'active',
    'insert_no_consent', 'RLS 차단',
    'insert_consented', '성공',
    'anon_denied', '권한 없음',
    'impact', jsonb_build_object('active_count', 2, 'pending_count', 1),
    'withdraw', jsonb_build_object('forfeited', 2, 'cancelled', 1),
    'w1', 'finished/B/A',
    'w2', 'finished/B/A',
    'w3', 'cancelled',
    'a_outcomes', 'forfeit,forfeit',
    'a_stats', '4/0/2/0',
    'b_stats', '16/2/0/0',
    'slots_kept', 1,
    'a_consent_rows', 0,
    'a_events', 'given,withdrawn',
    'c_consent_rows', 1,
    'join_after_withdraw', 'CONSENT_REQUIRED',
    'withdraw_twice_rejected', true,
    'd_consent_rows', 0,
    'd_event_rows', 0
  );

  select coalesce(string_agg(format('%s expected=%s actual=%s', e.key, e.value, coalesce(a.value::text, 'null')), '; '), '')
  into v_diff
  from jsonb_each(v_expected) e
  left join jsonb_each(v_actual) a on a.key = e.key
  where a.value is distinct from e.value;

  raise exception 'SMOKE RESULT ok=% %', v_diff = '',
    case when v_diff = '' then '' else ' FAILURES: ' || v_diff end;
end $$;
