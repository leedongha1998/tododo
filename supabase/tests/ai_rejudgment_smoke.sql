-- mutual-judge 3단계 AI 재판정 스모크 테스트.
--
-- 로컬에 Docker가 없어 원격 DB에 직접 돌린다:
--   supabase db query --linked -f supabase/tests/ai_rejudgment_smoke.sql
--
-- 마지막에 일부러 예외를 던져 전체를 롤백한다(pg_net 요청 큐도 같이 롤백되므로 실제 호출은 나가지 않는다).
--   SMOKE RESULT ok=t                     -> 통과
--   SMOKE RESULT ok=f  FAILURES: ...      -> 어긋난 항목(기대값/실제값)
--
-- A = 생성자, B = 참가자. 모든 대결은 판정 창(judging)에서 시작한다. 트랜잭션 안의 now()는 고정이라
-- 재시도를 흉내 낼 때는 next_attempt_at을 직접 과거로 돌린다.
-- 확인하는 것
--   j1  A가 B를 불복 -> 잡 1개(대상 B). claim은 사진 1장과 최소 기준만 주고 사람의 판정은 주지 않는다.
--       AI가 통과로 보면 불복이 뒤집혀 먼저 낸 B가 이긴다(거짓 불복은 이득이 없다). 잡은 사라진다.
--   j2  양쪽 불복 -> 잡 2개
--   j3  품질전 우열 불일치 -> 우열 잡 1개. 승자가 참가자가 아니면 실패 1회(재시도 예약),
--       참가자면 그 사람 승리로 종결하고 사유를 남긴다
--   j4  임대 토큰이 다르면 기록을 버린다. 4회 실패 -> voided, 오늘 매칭 슬롯 반환, 점수 불변, 잡 삭제
--   j5  어제 매칭 대결이 무효가 되면 어제 슬롯은 남는다
--   j6  임대 만료 = 실패 1회(dispatch). 다음 시도는 2분 뒤
--   j7  포기하면 잡이 사라진다
--   j8  탈퇴하면 잡이 사라진다
--   권한 authenticated는 claim·dispatch를 못 부르고, service_role은 claim을 부를 수 있다
do $$
declare
  v_a uuid := gen_random_uuid();
  v_b uuid := gen_random_uuid();
  v_e uuid := gen_random_uuid();
  v_f uuid := gen_random_uuid();
  v_today date := (now() at time zone 'Asia/Seoul')::date;
  v_ids jsonb := '{}'::jsonb;
  v_name text;
  v_id uuid;
  v_j8 uuid;
  v_job bigint;
  v_claim jsonb;
  v_j1_claim jsonb;
  v_j1_record jsonb;
  v_j3_claim jsonb;
  v_j3_bad jsonb;
  v_j3_attempts_after_bad smallint;
  v_j3_record jsonb;
  v_j4_wrong_token jsonb;
  v_j4_results text[] := '{}';
  v_j5_result jsonb;
  v_j6_job bigint;
  v_i integer;
  v_sent integer;
  v_auth_claim text := '(예외 없음)';
  v_auth_dispatch text := '(예외 없음)';
  v_service_claim text := '(예외 없음)';
  v_actual jsonb;
  v_expected jsonb;
  v_diff text;
begin
  insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  select u.id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
         u.email, jsonb_build_object('full_name', u.name), now(), now()
  from (values
    (v_a, 'rejudge-smoke-a@example.invalid', '스모크A'),
    (v_b, 'rejudge-smoke-b@example.invalid', '스모크B'),
    (v_e, 'rejudge-smoke-e@example.invalid', '스모크E'),
    (v_f, 'rejudge-smoke-f@example.invalid', '스모크F')
  ) as u(id, email, name);

  update public.player_stats set score = 10 where user_id in (v_a, v_b, v_e, v_f);

  -- 판정 창이 열린 대결들. 사진 마감 1시간 전, 창은 1시간 전에 열렸고 기한은 23시간 남았다.
  foreach v_name in array array['j1', 'j2', 'j3', 'j4', 'j5', 'j6', 'j7'] loop
    insert into public.battles (min_criteria, superiority_criteria, type, status, title, creator_id, opponent_id,
                                duration_minutes, started_at, deadline_at, judging_opened_at, judge_deadline_at)
    values ('["상판이 보인다"]'::jsonb,
            case when v_name = 'j3' then '["먼지가 없다"]'::jsonb end,
            case when v_name = 'j3' then 'quality' else 'speed' end,
            'judging', '재판정 스모크 ' || v_name, v_a, v_b,
            60, now() - interval '2 hours', now() - interval '1 hour',
            now() - interval '1 hour', now() + interval '23 hours')
    returning id into v_id;

    insert into public.battle_participants (battle_id, user_id, has_submitted) values (v_id, v_b, true);
    update public.battle_participants set has_submitted = true where battle_id = v_id and user_id = v_a;

    -- 양쪽 제출. B가 먼저 냈다.
    insert into public.battle_submissions (battle_id, user_id, object_path, captured_at, submitted_at)
    values
      (v_id, v_a, v_id || '/' || v_a || '/a.jpg', now() - interval '90 minutes', now() - interval '90 minutes'),
      (v_id, v_b, v_id || '/' || v_b || '/b.jpg', now() - interval '100 minutes', now() - interval '100 minutes');

    v_ids := v_ids || jsonb_build_object(v_name, v_id);
  end loop;

  -- 한도 슬롯: j4는 오늘, j5는 어제 매칭.
  insert into public.daily_battle_slots (user_id, kst_date, battle_id)
  values (v_a, v_today, (v_ids ->> 'j4')::uuid), (v_b, v_today, (v_ids ->> 'j4')::uuid),
         (v_a, v_today - 1, (v_ids ->> 'j5')::uuid), (v_b, v_today - 1, (v_ids ->> 'j5')::uuid);

  -- ── 판정 ─────────────────────────────────────────────────────────────────────
  -- A의 판정: j1·j2·j4·j5·j6·j7은 B 불복, j3은 승인 + 자기가 더 잘했다.
  perform set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
  foreach v_name in array array['j1', 'j2', 'j4', 'j5', 'j6', 'j7'] loop
    perform public.submit_judgment((v_ids ->> v_name)::uuid, 'reject', null);
  end loop;
  perform public.submit_judgment((v_ids ->> 'j3')::uuid, 'approve', v_a);

  -- B의 판정: j1은 A 승인, j2는 A 불복, j3은 승인 + 자기가 더 잘했다(우열 불일치).
  perform set_config('request.jwt.claims', json_build_object('sub', v_b, 'role', 'authenticated')::text, true);
  perform public.submit_judgment((v_ids ->> 'j1')::uuid, 'approve', null);
  perform public.submit_judgment((v_ids ->> 'j2')::uuid, 'reject', null);
  perform public.submit_judgment((v_ids ->> 'j3')::uuid, 'approve', v_b);
  foreach v_name in array array['j4', 'j5', 'j6', 'j7'] loop
    perform public.submit_judgment((v_ids ->> v_name)::uuid, 'approve', null);
  end loop;

  v_actual := jsonb_build_object(
    'j1_jobs', (select string_agg(kind || ':' || case target_id when v_a then 'A' when v_b then 'B' else '-' end, ',')
                from public.ai_judgment_jobs where battle_id = (v_ids ->> 'j1')::uuid),
    'j2_jobs', (select count(*) from public.ai_judgment_jobs where battle_id = (v_ids ->> 'j2')::uuid),
    'j3_jobs', (select string_agg(kind, ',') from public.ai_judgment_jobs where battle_id = (v_ids ->> 'j3')::uuid)
  );

  -- ── j1: AI가 불복을 뒤집는다 ──────────────────────────────────────────────────
  select id into v_job from public.ai_judgment_jobs where battle_id = (v_ids ->> 'j1')::uuid;
  v_j1_claim := public.claim_ai_judgment(v_job);
  v_j1_record := public.record_min_criteria_verdict(v_job, (v_j1_claim ->> 'token')::uuid, true, '상판이 모두 보인다', 'test/p2');

  -- ── j3: 우열 재판정 ───────────────────────────────────────────────────────────
  select id into v_job from public.ai_judgment_jobs where battle_id = (v_ids ->> 'j3')::uuid;
  v_j3_claim := public.claim_ai_judgment(v_job);
  v_j3_bad := public.record_superiority_verdict(v_job, (v_j3_claim ->> 'token')::uuid, gen_random_uuid(), '엉뚱한 승자', 'test/p2');
  select attempts into v_j3_attempts_after_bad from public.ai_judgment_jobs where id = v_job;
  update public.ai_judgment_jobs set next_attempt_at = now() - interval '1 second' where id = v_job;
  v_claim := public.claim_ai_judgment(v_job);
  v_j3_record := public.record_superiority_verdict(v_job, (v_claim ->> 'token')::uuid, v_a, '먼지가 하나도 없다', 'test/p2');

  -- ── j4: 토큰 불일치, 4회 실패 -> 무효 ─────────────────────────────────────────
  select id into v_job from public.ai_judgment_jobs where battle_id = (v_ids ->> 'j4')::uuid;
  for v_i in 1..4 loop
    update public.ai_judgment_jobs set next_attempt_at = now() - interval '1 second' where id = v_job;
    v_claim := public.claim_ai_judgment(v_job);
    if v_i = 1 then
      v_j4_wrong_token := public.record_ai_judgment_failure(v_job, gen_random_uuid(), '남의 임대');
    end if;
    v_j4_results := v_j4_results
      || (public.record_ai_judgment_failure(v_job, (v_claim ->> 'token')::uuid, 'Gemini 503') ->> 'result');
  end loop;

  -- ── j5: 어제 매칭 대결의 무효 ─────────────────────────────────────────────────
  select id into v_job from public.ai_judgment_jobs where battle_id = (v_ids ->> 'j5')::uuid;
  update public.ai_judgment_jobs set attempts = 3 where id = v_job;
  v_claim := public.claim_ai_judgment(v_job);
  v_j5_result := public.record_ai_judgment_failure(v_job, (v_claim ->> 'token')::uuid, 'Gemini 503');

  -- ── j6: 임대 만료 = 실패 1회 ──────────────────────────────────────────────────
  select id into v_j6_job from public.ai_judgment_jobs where battle_id = (v_ids ->> 'j6')::uuid;
  perform public.claim_ai_judgment(v_j6_job);
  update public.ai_judgment_jobs set lease_until = now() - interval '1 second' where id = v_j6_job;
  -- Vault 값이 없으면 발송만 건너뛴다(원격에는 값이 있어 기한이 된 잡을 부르지만, 롤백되므로 나가지 않는다).
  v_sent := public.dispatch_ai_judgments();

  -- ── j7: 포기 ────────────────────────────────────────────────────────────────
  perform set_config('request.jwt.claims', json_build_object('sub', v_b, 'role', 'authenticated')::text, true);
  perform public.forfeit_battle((v_ids ->> 'j7')::uuid);

  -- ── j8: 탈퇴 (E vs F, E가 F를 불복한 뒤 F가 탈퇴) ─────────────────────────────
  insert into public.battles (min_criteria, superiority_criteria, type, status, title, creator_id, opponent_id,
                              duration_minutes, started_at, deadline_at, judging_opened_at, judge_deadline_at)
  values ('["상판이 보인다"]'::jsonb, null, 'speed', 'judging', '재판정 스모크 j8', v_e, v_f,
          60, now() - interval '2 hours', now() - interval '1 hour', now() - interval '1 hour', now() + interval '23 hours')
  returning id into v_j8;
  insert into public.battle_participants (battle_id, user_id) values (v_j8, v_f);
  insert into public.battle_submissions (battle_id, user_id, object_path, captured_at, submitted_at)
  values (v_j8, v_e, v_j8 || '/' || v_e || '/a.jpg', now() - interval '90 minutes', now() - interval '90 minutes'),
         (v_j8, v_f, v_j8 || '/' || v_f || '/b.jpg', now() - interval '95 minutes', now() - interval '95 minutes');
  perform set_config('request.jwt.claims', json_build_object('sub', v_e, 'role', 'authenticated')::text, true);
  perform public.submit_judgment(v_j8, 'reject', null);
  v_actual := v_actual || jsonb_build_object(
    'j8_jobs_before', (select count(*) from public.ai_judgment_jobs where battle_id = v_j8)
  );
  perform set_config('request.jwt.claims', json_build_object('sub', v_f, 'role', 'authenticated')::text, true);
  perform public.delete_account();

  -- ── 권한 ────────────────────────────────────────────────────────────────────
  select id into v_job from public.ai_judgment_jobs where battle_id = (v_ids ->> 'j2')::uuid order by id limit 1;

  begin
    execute 'set local role authenticated';
    perform public.claim_ai_judgment(v_job);
    execute 'reset role';
  exception when insufficient_privilege then
    v_auth_claim := '권한 없음';
  when others then
    v_auth_claim := '다른 오류: ' || sqlerrm;
  end;
  execute 'reset role';

  begin
    execute 'set local role authenticated';
    perform public.dispatch_ai_judgments();
    execute 'reset role';
  exception when insufficient_privilege then
    v_auth_dispatch := '권한 없음';
  when others then
    v_auth_dispatch := '다른 오류: ' || sqlerrm;
  end;
  execute 'reset role';

  begin
    execute 'set local role service_role';
    v_claim := public.claim_ai_judgment(v_job);
    execute 'reset role';
    v_service_claim := case when v_claim ? 'token' then '임대함' else '임대 못 함' end;
  exception when others then
    v_service_claim := '오류: ' || sqlerrm;
  end;
  execute 'reset role';

  select v_actual || jsonb_object_agg(
           l.name,
           b.status
             || '/' || coalesce(case b.winner_id when v_a then 'A' when v_b then 'B' end, '-')
             || '/' || coalesce(pa.outcome, '-')
             || '/' || coalesce(pb.outcome, '-')
         )
  into v_actual
  from (select (v_ids ->> n)::uuid as id, n as name
        from unnest(array['j1', 'j2', 'j3', 'j4', 'j5', 'j6', 'j7']) n) as l
  join public.battles b on b.id = l.id
  left join public.battle_participants pa on pa.battle_id = b.id and pa.user_id = v_a
  left join public.battle_participants pb on pb.battle_id = b.id and pb.user_id = v_b;

  v_actual := v_actual || jsonb_build_object(
    'j1_claim_kind', v_j1_claim ->> 'kind',
    'j1_claim_path', v_j1_claim ->> 'target_path' = (v_ids ->> 'j1') || '/' || v_b || '/b.jpg',
    -- AI에게 사람의 판정을 알리지 않는다.
    'j1_claim_keys', (select string_agg(k, ',' order by k) from jsonb_object_keys(v_j1_claim) k),
    'j1_record', v_j1_record ->> 'result',
    'j1_b_source', (select verdict_source || '/' || meets_criteria::text || '/' || coalesce(reason, '-')
                    from public.battle_submissions
                    where battle_id = (v_ids ->> 'j1')::uuid and user_id = v_b),
    'j1_jobs_after', (select count(*) from public.ai_judgment_jobs where battle_id = (v_ids ->> 'j1')::uuid),
    'j3_claim_keys', (select string_agg(k, ',' order by k) from jsonb_object_keys(v_j3_claim) k),
    'j3_bad', v_j3_bad ->> 'result',
    'j3_attempts_after_bad', v_j3_attempts_after_bad,
    'j3_record', v_j3_record ->> 'result',
    'j3_reason', (select verdict_reason from public.battles where id = (v_ids ->> 'j3')::uuid),
    'j4_wrong_token', v_j4_wrong_token ->> 'result',
    'j4_results', array_to_string(v_j4_results, ','),
    'j4_jobs_after', (select count(*) from public.ai_judgment_jobs where battle_id = (v_ids ->> 'j4')::uuid),
    'j4_slots_left', (select count(*) from public.daily_battle_slots where battle_id = (v_ids ->> 'j4')::uuid),
    'j5_result', v_j5_result ->> 'result',
    'j5_slots_left', (select count(*) from public.daily_battle_slots where battle_id = (v_ids ->> 'j5')::uuid),
    'j6_job', (select attempts || '/' || (lease_token is null)::text || '/' || (next_attempt_at = now() + interval '2 minutes')::text
                      || '/' || coalesce(last_error, '-')
               from public.ai_judgment_jobs where id = v_j6_job),
    'j7_jobs_after', (select count(*) from public.ai_judgment_jobs where battle_id = (v_ids ->> 'j7')::uuid),
    'j8_status', (select status from public.battles where id = v_j8),
    'j8_jobs_after', (select count(*) from public.ai_judgment_jobs where battle_id = v_j8),
    'a_stats', (select concat_ws('/', score, wins, losses, draws) from public.player_stats where user_id = v_a),
    'b_stats', (select concat_ws('/', score, wins, losses, draws) from public.player_stats where user_id = v_b),
    'auth_claim', v_auth_claim,
    'auth_dispatch', v_auth_dispatch,
    'service_claim', v_service_claim,
    'disputed_count', (select count(*) from public.battles where status = 'disputed' and creator_id in (v_a, v_e))
  );

  -- A: 10 -1(j1 완료한 패배) +3(j3 승) +3(j7 상대 포기) = 15, 승2 패1 무0
  -- B: 10 +3(j1 승) -3(j3 패) -3(j7 포기) = 7, 승1 패2 무0
  v_expected := jsonb_build_object(
    'j1_jobs', 'min_criteria:B',
    'j2_jobs', 2,
    'j3_jobs', 'superiority',
    'j1', 'finished/B/completed_loss/win',
    'j2', 'judging/-/-/-',
    'j3', 'finished/A/win/loss',
    'j4', 'voided/-/-/-',
    'j5', 'voided/-/-/-',
    'j6', 'judging/-/-/-',
    'j7', 'finished/A/win/forfeit',
    'j1_claim_kind', 'min_criteria',
    'j1_claim_path', true,
    'j1_claim_keys', 'attempt,kind,min_criteria,target_path,title,token',
    'j1_record', 'finished',
    'j1_b_source', 'ai/true/상판이 모두 보인다',
    'j1_jobs_after', 0,
    'j3_claim_keys', 'a_path,attempt,b_path,creator_id,kind,opponent_id,superiority_criteria,title,token',
    'j3_bad', 'retry_scheduled',
    'j3_attempts_after_bad', 1,
    'j3_record', 'finished',
    'j3_reason', '먼지가 하나도 없다',
    'j4_wrong_token', 'skipped',
    'j4_results', 'retry_scheduled,retry_scheduled,retry_scheduled,voided',
    'j4_jobs_after', 0,
    'j4_slots_left', 0,
    'j5_result', 'voided',
    'j5_slots_left', 2,
    'j6_job', '1/true/true/판정 임대가 만료됐습니다.',
    'j7_jobs_after', 0,
    'j8_jobs_before', 1,
    'j8_status', 'cancelled',
    'j8_jobs_after', 0,
    'a_stats', '15/2/1/0',
    'b_stats', '7/1/2/0',
    'auth_claim', '권한 없음',
    'auth_dispatch', '권한 없음',
    'service_claim', '임대함',
    'disputed_count', 0
  );

  select coalesce(string_agg(format('%s expected=%s actual=%s', e.key, e.value, coalesce(a.value::text, 'null')), '; '), '')
  into v_diff
  from jsonb_each(v_expected) e
  left join jsonb_each(v_actual) a on a.key = e.key
  where a.value is distinct from e.value;

  raise exception 'SMOKE RESULT ok=% % sent=%', v_diff = '',
    case when v_diff = '' then '' else ' FAILURES: ' || v_diff end,
    v_sent;
end $$;
