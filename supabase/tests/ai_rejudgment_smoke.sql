-- AI 재판정 흐름 스모크 테스트 (mutual-judge 3단계).
--
-- 로컬에 Docker가 없어 원격 DB에 직접 돌린다:
--   supabase db query --linked -f supabase/tests/ai_rejudgment_smoke.sql
--
-- 마지막에 일부러 예외를 던져 전체를 롤백한다. 결과:
--   SMOKE RESULT ok=true                    -> 통과
--   SMOKE RESULT ok=false FAILURES: ...     -> 어긋난 항목(기대값/실제값)
--
-- Gemini를 부르지 않는다. Edge Function이 하는 일(claim -> 판정 -> record)을 SQL에서 직접 흉내내
-- 서버 쪽 규칙만 본다. 같은 트랜잭션 안에서는 now()가 고정이므로(백오프로 미뤄진 잡은 영원히
-- 기한이 되지 않는다) 재시도 테스트는 next_attempt_at·lease_until을 직접 과거로 돌려 놓는다.
--
-- 확인하는 것
--   reject_one_*      불복 1건 -> 잡 1개(kind=min_criteria, target=불복당한 쪽)
--   claim_payload_*   claim이 kind에 필요한 값만 준다(최소 기준에 우열 기준 없음, 그 반대도)
--   ai_pass_*         AI가 통과라고 하면 사람의 불복이 뒤집힌다(완료한 패배 감면까지)
--   reject_both_*     양쪽 불복 -> 잡 2개, 둘 다 미달이면 draw
--   superiority_*     우열 불일치 -> 잡 1개(target null), 승자 확정 -> finished + verdict_reason/verdict_model
--                     (우열 모델은 battles에만 남고 제출 행의 ai_model은 건드리지 않는다)
--   bad_winner_*      승자가 참가자가 아니면 성공으로 치지 않고 실패 1회(대결은 judging 유지)
--   stale_token       임대 토큰이 맞지 않는 기록은 조용히 버린다(skipped)
--   exhausted_*       4회 소진 -> voided, 점수·전적 무반영, 오늘 매칭 슬롯만 반환
--   lease_*           임대 만료 = 실패 1회(dispatch가 정리)
--   old_token_*       임대가 만료돼 새 토큰으로 재claim된 뒤 옛 토큰으로 온 응답은 버려진다
--   forfeit_jobs      포기하면 남은 잡이 사라진다
--   delete_jobs       탈퇴로 취소된 대결의 잡이 사라진다
--   perm_*            anon·authenticated의 서버 전용 함수 권한 오류, 잡 테이블은 RLS로 0행
--   dropped_*         quality_judgments 일체가 사라졌다
--   disputed_count    어떤 경로도 disputed를 만들지 않는다
do $$
declare
  v_a uuid := gen_random_uuid();  -- creator
  v_b uuid := gen_random_uuid();  -- opponent
  v_c uuid := gen_random_uuid();  -- 탈퇴 테스트용 creator
  v_today date := (now() at time zone 'Asia/Seoul')::date;
  v_reject_one uuid;
  v_reject_both uuid;
  v_exhausted uuid;
  v_lease uuid;
  v_stale_lease uuid;
  v_forfeit uuid;
  v_superiority uuid;
  v_bad_winner uuid;
  v_delete uuid;
  v_i integer;
  v_id uuid;
  v_job_id bigint;
  v_job_b bigint;
  v_claim jsonb;
  v_token uuid;
  v_result jsonb;
  v_reject_one_jobs integer := -1;
  v_reject_one_target text := '(없음)';
  v_claim_min_keys text := '(없음)';
  v_claim_sup_keys text := '(없음)';
  v_reject_both_jobs integer := -1;
  v_superiority_jobs integer := -1;
  v_superiority_target text := '(target 있음)';
  v_bad_winner_result text := '(없음)';
  v_bad_winner_attempts integer := -1;
  v_stale_token_result text := '(없음)';
  v_old_token_result text := '(없음)';
  v_old_token_untouched boolean;
  v_exhausted_results text := '';
  v_lease_attempts integer := -1;
  v_lease_token_cleared boolean;
  v_lease_error text := '(없음)';
  v_forfeit_jobs integer := -1;
  v_delete_jobs integer := -1;
  v_delete_status text := '(없음)';
  v_perm_claim_anon text := '(예외 없음)';
  v_perm_dispatch_authenticated text := '(예외 없음)';
  v_perm_record_authenticated text := '(예외 없음)';
  v_rls_jobs integer := -1;
  v_actual jsonb;
  v_expected jsonb;
  v_diff text;
begin
  insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  select u.id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
         u.email, jsonb_build_object('full_name', u.name), now(), now()
  from (values
    (v_a, 'ai-rejudge-a@example.invalid', '스모크A'),
    (v_b, 'ai-rejudge-b@example.invalid', '스모크B'),
    (v_c, 'ai-rejudge-c@example.invalid', '스모크C')
  ) as u(id, email, name);

  update public.player_stats set score = 10 where user_id in (v_a, v_b, v_c);

  perform set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
  perform public.give_ai_consent('2026-09-18');
  perform set_config('request.jwt.claims', json_build_object('sub', v_b, 'role', 'authenticated')::text, true);
  perform public.give_ai_consent('2026-09-18');
  perform set_config('request.jwt.claims', json_build_object('sub', v_c, 'role', 'authenticated')::text, true);
  perform public.give_ai_consent('2026-09-18');

  -- 매칭된 속도전 여섯 개(어제 시작, 내일 마감). creator 참가자 행은 트리거가 만든다.
  for v_i in 1..6 loop
    insert into public.battles (
      min_criteria, superiority_criteria, type, status, title,
      creator_id, opponent_id, duration_minutes, started_at, deadline_at
    )
    values (
      '["상판이 보인다"]'::jsonb, null, 'speed', 'active', 'rejudge speed ' || v_i,
      v_a, v_b, 4320, now() - interval '1 day', now() + interval '1 day'
    )
    returning id into v_id;

    insert into public.battle_participants (battle_id, user_id) values (v_id, v_b);

    case v_i
      when 1 then v_reject_one := v_id;
      when 2 then v_reject_both := v_id;
      when 3 then v_exhausted := v_id;
      when 4 then v_lease := v_id;
      when 5 then v_forfeit := v_id;
      else v_stale_lease := v_id;
    end case;
  end loop;

  -- 매칭된 품질전 두 개.
  for v_i in 1..2 loop
    insert into public.battles (
      min_criteria, superiority_criteria, type, status, title,
      creator_id, opponent_id, duration_minutes, started_at, deadline_at
    )
    values (
      '["바닥이 보인다"]'::jsonb, '["먼지가 없다"]'::jsonb, 'quality', 'active',
      'rejudge quality ' || v_i, v_a, v_b, 4320, now() - interval '1 day', now() + interval '1 day'
    )
    returning id into v_id;

    insert into public.battle_participants (battle_id, user_id) values (v_id, v_b);

    if v_i = 1 then
      v_superiority := v_id;
    else
      v_bad_winner := v_id;
    end if;
  end loop;

  -- 탈퇴 테스트용(C 생성, B 참가).
  insert into public.battles (
    min_criteria, superiority_criteria, type, status, title,
    creator_id, opponent_id, duration_minutes, started_at, deadline_at
  )
  values (
    '["상판이 보인다"]'::jsonb, null, 'speed', 'active', 'rejudge delete',
    v_c, v_b, 4320, now() - interval '1 day', now() + interval '1 day'
  )
  returning id into v_delete;
  insert into public.battle_participants (battle_id, user_id) values (v_delete, v_b);

  -- 슬롯 원장: 무효 대결은 오늘 매칭, 다른 대결은 어제 매칭(PK가 (user, kst_date)라 하루 한 행뿐이다).
  insert into public.daily_battle_slots (user_id, kst_date, battle_id)
  values
    (v_a, v_today, v_exhausted), (v_b, v_today, v_exhausted),
    (v_a, v_today - 1, v_reject_one), (v_b, v_today - 1, v_reject_one);

  -- 1. 불복 1건 -> 잡 1개. a가 b의 사진을 불복하고, b는 a의 사진을 승인한다.
  perform public.accept_submission(v_a, v_reject_one, format('%s/%s/1.jpg', v_reject_one, v_a), now());
  perform public.accept_submission(v_b, v_reject_one, format('%s/%s/1.jpg', v_reject_one, v_b), now());

  perform set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
  perform public.submit_judgment(v_reject_one, 'reject', null);

  select count(*) into v_reject_one_jobs from public.ai_judgment_jobs where battle_id = v_reject_one;
  select case when target_id = v_b then 'B' when target_id = v_a then 'A' else '(기타)' end
  into v_reject_one_target
  from public.ai_judgment_jobs where battle_id = v_reject_one and kind = 'min_criteria';

  perform set_config('request.jwt.claims', json_build_object('sub', v_b, 'role', 'authenticated')::text, true);
  perform public.submit_judgment(v_reject_one, 'approve', null);

  -- 2. claim은 kind에 필요한 값만 준다. AI가 통과라고 하면 사람의 불복이 뒤집힌다.
  select id into v_job_id from public.ai_judgment_jobs where battle_id = v_reject_one;
  v_claim := public.claim_ai_judgment(v_job_id);
  select string_agg(key, ',' order by key) into v_claim_min_keys from jsonb_object_keys(v_claim) as k(key);
  v_token := (v_claim ->> 'token')::uuid;

  v_result := public.record_min_criteria_verdict(
    v_job_id, v_token, true, '상판이 모두 보인다', 'smoke-model/p1');

  -- 3. 양쪽 불복 -> 잡 2개. 둘 다 미달이면 draw.
  perform public.accept_submission(v_a, v_reject_both, format('%s/%s/1.jpg', v_reject_both, v_a), now());
  perform public.accept_submission(v_b, v_reject_both, format('%s/%s/1.jpg', v_reject_both, v_b), now());

  perform set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
  perform public.submit_judgment(v_reject_both, 'reject', null);
  perform set_config('request.jwt.claims', json_build_object('sub', v_b, 'role', 'authenticated')::text, true);
  perform public.submit_judgment(v_reject_both, 'reject', null);

  select count(*) into v_reject_both_jobs from public.ai_judgment_jobs where battle_id = v_reject_both;

  select id into v_job_b from public.ai_judgment_jobs
  where battle_id = v_reject_both and target_id = v_b;
  v_claim := public.claim_ai_judgment(v_job_b);
  perform public.record_min_criteria_verdict(
    v_job_b, (v_claim ->> 'token')::uuid, false, '물건이 그대로 있다', 'smoke-model/p1');

  select id into v_job_id from public.ai_judgment_jobs
  where battle_id = v_reject_both and target_id = v_a;
  v_claim := public.claim_ai_judgment(v_job_id);
  perform public.record_min_criteria_verdict(
    v_job_id, (v_claim ->> 'token')::uuid, false, '사진이 흐리다', 'smoke-model/p1');

  -- 4. 품질전 우열 불일치 -> 잡 1개(target null) -> 승자 확정.
  perform public.accept_submission(v_a, v_superiority, format('%s/%s/1.jpg', v_superiority, v_a), now());
  perform public.accept_submission(v_b, v_superiority, format('%s/%s/1.jpg', v_superiority, v_b), now());

  perform set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
  perform public.submit_judgment(v_superiority, 'approve', v_a);
  perform set_config('request.jwt.claims', json_build_object('sub', v_b, 'role', 'authenticated')::text, true);
  perform public.submit_judgment(v_superiority, 'approve', v_b);

  select count(*) into v_superiority_jobs from public.ai_judgment_jobs where battle_id = v_superiority;
  select id into v_job_id from public.ai_judgment_jobs
  where battle_id = v_superiority and kind = 'superiority';
  select case when target_id is null then '(target 없음)' else '(target 있음)' end
  into v_superiority_target
  from public.ai_judgment_jobs where id = v_job_id;

  v_claim := public.claim_ai_judgment(v_job_id);
  select string_agg(key, ',' order by key) into v_claim_sup_keys from jsonb_object_keys(v_claim) as k(key);
  perform public.record_superiority_verdict(
    v_job_id, (v_claim ->> 'token')::uuid, v_b, '먼지가 더 적다', 'smoke-model/p1');

  -- 5. 승자가 참가자가 아니면 성공으로 치지 않는다(실패 1회, 대결은 judging 유지).
  perform public.accept_submission(v_a, v_bad_winner, format('%s/%s/1.jpg', v_bad_winner, v_a), now());
  perform public.accept_submission(v_b, v_bad_winner, format('%s/%s/1.jpg', v_bad_winner, v_b), now());

  perform set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
  perform public.submit_judgment(v_bad_winner, 'approve', v_a);
  perform set_config('request.jwt.claims', json_build_object('sub', v_b, 'role', 'authenticated')::text, true);
  perform public.submit_judgment(v_bad_winner, 'approve', v_b);

  select id into v_job_id from public.ai_judgment_jobs where battle_id = v_bad_winner;
  v_claim := public.claim_ai_judgment(v_job_id);
  v_result := public.record_superiority_verdict(
    v_job_id, (v_claim ->> 'token')::uuid, gen_random_uuid(), '엉뚱한 승자', 'smoke-model/p1');
  v_bad_winner_result := v_result ->> 'result';
  select attempts into v_bad_winner_attempts from public.ai_judgment_jobs where id = v_job_id;

  -- 6. 임대 토큰이 맞지 않는 기록은 조용히 버린다(위 실패로 임대가 풀린 잡에 아무 토큰을 보낸다).
  v_result := public.record_min_criteria_verdict(
    v_job_id, gen_random_uuid(), true, '늦게 도착', 'smoke-model/p1');
  v_stale_token_result := v_result ->> 'result';

  -- 7. 4회 소진 -> voided. 같은 트랜잭션에서는 now()가 고정이라 백오프로 미뤄진 잡이 다시 기한이
  --    되지 않으므로, 매 시도 전에 next_attempt_at을 과거로 돌려 놓는다(실제로는 cron이 기다린다).
  perform public.accept_submission(v_a, v_exhausted, format('%s/%s/1.jpg', v_exhausted, v_a), now());
  perform public.accept_submission(v_b, v_exhausted, format('%s/%s/1.jpg', v_exhausted, v_b), now());

  perform set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
  perform public.submit_judgment(v_exhausted, 'reject', null);

  select id into v_job_id from public.ai_judgment_jobs where battle_id = v_exhausted;

  for v_i in 1..4 loop
    update public.ai_judgment_jobs
    set next_attempt_at = now() - interval '1 second', lease_until = null, lease_token = null
    where id = v_job_id;

    v_claim := public.claim_ai_judgment(v_job_id);
    v_result := public.record_ai_judgment_failure(
      v_job_id, (v_claim ->> 'token')::uuid, 'AI 호출 실패 ' || v_i);
    v_exhausted_results := v_exhausted_results ||
      case when v_i = 1 then '' else '/' end || coalesce(v_result ->> 'result', 'null');
  end loop;

  -- 8. 임대 만료 = 실패 1회. dispatch가 만료된 임대를 정리한다(Vault 값이 없어도 도는 부분이다).
  perform public.accept_submission(v_a, v_lease, format('%s/%s/1.jpg', v_lease, v_a), now());
  perform public.accept_submission(v_b, v_lease, format('%s/%s/1.jpg', v_lease, v_b), now());

  perform set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
  perform public.submit_judgment(v_lease, 'reject', null);

  select id into v_job_id from public.ai_judgment_jobs where battle_id = v_lease;
  perform public.claim_ai_judgment(v_job_id);
  update public.ai_judgment_jobs set lease_until = now() - interval '1 second' where id = v_job_id;

  perform public.dispatch_ai_judgments();

  select attempts, lease_token is null, coalesce(last_error, '(없음)')
  into v_lease_attempts, v_lease_token_cleared, v_lease_error
  from public.ai_judgment_jobs where id = v_job_id;

  -- 8-2. 임대가 만료돼 **다른 실행이 새 토큰으로 재claim한 뒤** 옛 실행이 옛 토큰으로 응답하면
  --      조용히 버린다(record_*의 세 번째 조건 lease_token is distinct from p_token). 6번은 토큰이
  --      null로 비워진 경로를 보므로 이 경로가 따로 필요하다 - 여기서 틀리면 죽은 줄 알았던 호출이
  --      뒤늦게 결론을 덮어쓴다. 기록이 남지 않는 것(meets_criteria가 여전히 null)까지 본다.
  perform public.accept_submission(v_a, v_stale_lease, format('%s/%s/1.jpg', v_stale_lease, v_a), now());
  perform public.accept_submission(v_b, v_stale_lease, format('%s/%s/1.jpg', v_stale_lease, v_b), now());

  perform set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
  perform public.submit_judgment(v_stale_lease, 'reject', null);

  select id into v_job_id from public.ai_judgment_jobs where battle_id = v_stale_lease;
  v_claim := public.claim_ai_judgment(v_job_id);          -- 첫 실행이 T1으로 임대
  v_token := (v_claim ->> 'token')::uuid;
  update public.ai_judgment_jobs set lease_until = now() - interval '1 second' where id = v_job_id;
  perform public.claim_ai_judgment(v_job_id);             -- 다른 실행이 T2로 재임대

  v_result := public.record_min_criteria_verdict(
    v_job_id, v_token, true, '옛 실행의 응답', 'smoke-model/p1');
  v_old_token_result := v_result ->> 'result';

  select meets_criteria is null into v_old_token_untouched
  from public.battle_submissions where battle_id = v_stale_lease and user_id = v_b;

  -- 9. 포기하면 남은 잡이 사라진다. 파괴적 호출이므로 읽을 값은 호출 뒤 잡 개수뿐이다.
  perform public.accept_submission(v_a, v_forfeit, format('%s/%s/1.jpg', v_forfeit, v_a), now());
  perform public.accept_submission(v_b, v_forfeit, format('%s/%s/1.jpg', v_forfeit, v_b), now());

  perform set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
  perform public.submit_judgment(v_forfeit, 'reject', null);
  perform public.forfeit_battle(v_forfeit);

  select count(*) into v_forfeit_jobs from public.ai_judgment_jobs where battle_id = v_forfeit;

  -- 10. 탈퇴로 취소된 대결의 잡도 사라진다. C가 탈퇴하므로 C로 하는 일은 이것이 마지막이다.
  perform public.accept_submission(v_c, v_delete, format('%s/%s/1.jpg', v_delete, v_c), now());
  perform public.accept_submission(v_b, v_delete, format('%s/%s/1.jpg', v_delete, v_b), now());

  perform set_config('request.jwt.claims', json_build_object('sub', v_c, 'role', 'authenticated')::text, true);
  perform public.submit_judgment(v_delete, 'reject', null);
  perform public.delete_account();

  select count(*) into v_delete_jobs from public.ai_judgment_jobs where battle_id = v_delete;
  select status into v_delete_status from public.battles where id = v_delete;

  -- 11. 권한: anon은 claim을, authenticated는 dispatch·record를 부를 수 없다(cron/service 전용).
  begin
    execute 'set local role anon';
    perform public.claim_ai_judgment(1);
    execute 'reset role';
    v_perm_claim_anon := '(거부되지 않음)';
  exception when insufficient_privilege then
    v_perm_claim_anon := 'rejected';
  when others then
    v_perm_claim_anon := '다른 오류: ' || sqlerrm;
  end;
  execute 'reset role';

  begin
    execute 'set local role authenticated';
    perform public.dispatch_ai_judgments();
    execute 'reset role';
    v_perm_dispatch_authenticated := '(거부되지 않음)';
  exception when insufficient_privilege then
    v_perm_dispatch_authenticated := 'rejected';
  when others then
    v_perm_dispatch_authenticated := '다른 오류: ' || sqlerrm;
  end;
  execute 'reset role';

  begin
    execute 'set local role authenticated';
    perform public.record_min_criteria_verdict(1, gen_random_uuid(), true, '사유', 'm');
    execute 'reset role';
    v_perm_record_authenticated := '(거부되지 않음)';
  exception when insufficient_privilege then
    v_perm_record_authenticated := 'rejected';
  when others then
    v_perm_record_authenticated := '다른 오류: ' || sqlerrm;
  end;
  execute 'reset role';

  -- 12. 잡 테이블은 RLS를 켜고 정책이 없다. 남아 있는 잡(5번의 재시도 대기)이 보이지 않아야 한다.
  perform set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
  begin
    execute 'set local role authenticated';
    select count(*) into v_rls_jobs from public.ai_judgment_jobs;
    execute 'reset role';
  exception when others then
    execute 'reset role';
    v_rls_jobs := -2;
  end;
  execute 'reset role';

  v_actual := jsonb_build_object(
    'reject_one_jobs', v_reject_one_jobs,
    'reject_one_target', v_reject_one_target,
    -- claim 입력 분리: 최소 기준 재판정에는 우열 기준도, 참가자 id도 가지 않는다.
    'claim_min_keys', v_claim_min_keys,
    'claim_sup_keys', v_claim_sup_keys,
    'ai_pass_status', (select status || '/' || coalesce(case winner_id when v_a then 'A' when v_b then 'B' end, '-')
                       from public.battles where id = v_reject_one),
    'ai_pass_b_outcome', (select outcome from public.battle_participants
                          where battle_id = v_reject_one and user_id = v_b),
    'ai_pass_b_source', (select coalesce(verdict_source, '(null)') || '/' || coalesce(reason, '(null)')
                         from public.battle_submissions
                         where battle_id = v_reject_one and user_id = v_b),
    'ai_pass_jobs', (select count(*) from public.ai_judgment_jobs where battle_id = v_reject_one),
    'reject_both_jobs', v_reject_both_jobs,
    'reject_both_status', (select status from public.battles where id = v_reject_both),
    'reject_both_a_outcome', (select outcome from public.battle_participants
                              where battle_id = v_reject_both and user_id = v_a),
    'reject_both_jobs_left', (select count(*) from public.ai_judgment_jobs where battle_id = v_reject_both),
    'superiority_jobs', v_superiority_jobs,
    'superiority_target', v_superiority_target,
    'superiority_status', (select status || '/' || coalesce(case winner_id when v_a then 'A' when v_b then 'B' end, '-')
                           from public.battles where id = v_superiority),
    'superiority_reason', (select coalesce(verdict_reason, '(null)') from public.battles where id = v_superiority),
    'superiority_a_outcome', (select outcome from public.battle_participants
                              where battle_id = v_superiority and user_id = v_a),
    'superiority_jobs_left', (select count(*) from public.ai_judgment_jobs where battle_id = v_superiority),
    -- 우열 모델은 battles에만 남는다. 제출 행의 ai_model은 사람이 승인한 행이므로 비어 있어야 한다.
    'superiority_model', (select coalesce(verdict_model, '(null)') from public.battles where id = v_superiority),
    'superiority_subs_ai_model', (select count(*) from public.battle_submissions
                                  where battle_id = v_superiority and ai_model is not null),
    'bad_winner_result', v_bad_winner_result,
    'bad_winner_attempts', v_bad_winner_attempts,
    'bad_winner_status', (select status from public.battles where id = v_bad_winner),
    'bad_winner_jobs', (select count(*) from public.ai_judgment_jobs where battle_id = v_bad_winner),
    'stale_token_result', v_stale_token_result,
    'exhausted_results', v_exhausted_results,
    'exhausted_status', (select status from public.battles where id = v_exhausted),
    'exhausted_winner', (select winner_id is null from public.battles where id = v_exhausted),
    'exhausted_outcomes', (select count(*) from public.battle_participants
                           where battle_id = v_exhausted and outcome is not null),
    'exhausted_deltas', (select count(*) from public.battle_participants
                         where battle_id = v_exhausted and score_delta_applied is not null),
    'exhausted_jobs', (select count(*) from public.ai_judgment_jobs where battle_id = v_exhausted),
    'exhausted_today_slots', (select count(*) from public.daily_battle_slots where battle_id = v_exhausted),
    'yesterday_slots_kept', (select count(*) from public.daily_battle_slots where battle_id = v_reject_one),
    'lease_attempts', v_lease_attempts,
    'lease_token_cleared', v_lease_token_cleared,
    'lease_error', v_lease_error,
    'lease_jobs', (select count(*) from public.ai_judgment_jobs where battle_id = v_lease),
    'old_token_result', v_old_token_result,
    'old_token_untouched', v_old_token_untouched,
    'forfeit_jobs', v_forfeit_jobs,
    'delete_jobs', v_delete_jobs,
    'delete_status', v_delete_status,
    'perm_claim_anon', v_perm_claim_anon,
    'perm_dispatch_authenticated', v_perm_dispatch_authenticated,
    'perm_record_authenticated', v_perm_record_authenticated,
    'rls_jobs', v_rls_jobs,
    'dropped_table', (select count(*) from pg_class
                      where relname = 'quality_judgments' and relnamespace = 'public'::regnamespace),
    'dropped_functions', (select count(*) from pg_proc
                          where pronamespace = 'public'::regnamespace
                            and proname in ('claim_quality_judgment', 'record_quality_verdict',
                                            'record_quality_failure', 'dispatch_quality_judgments',
                                            'quality_judgment_backoff', 'fail_quality_judgment',
                                            'record_speed_verdict', 'sweep_stale_submissions')),
    'disputed_count', (select count(*) from public.battles
                       where creator_id in (v_a, v_c) and status = 'disputed')
  );

  v_expected := jsonb_build_object(
    'reject_one_jobs', 1,
    'reject_one_target', 'B',
    'claim_min_keys', 'attempt,job_id,kind,min_criteria,target_path,title,token',
    'claim_sup_keys',
      'a_path,attempt,b_path,creator_id,job_id,kind,opponent_id,superiority_criteria,title,token',
    'ai_pass_status', 'finished/A',
    'ai_pass_b_outcome', 'completed_loss',
    'ai_pass_b_source', 'ai/상판이 모두 보인다',
    'ai_pass_jobs', 0,
    'reject_both_jobs', 2,
    'reject_both_status', 'draw',
    'reject_both_a_outcome', 'draw',
    'reject_both_jobs_left', 0,
    'superiority_jobs', 1,
    'superiority_target', '(target 없음)',
    'superiority_status', 'finished/B',
    'superiority_reason', '먼지가 더 적다',
    'superiority_a_outcome', 'loss',
    'superiority_jobs_left', 0,
    'superiority_model', 'smoke-model/p1',
    'superiority_subs_ai_model', 0,
    'bad_winner_result', 'retry_scheduled',
    'bad_winner_attempts', 1,
    'bad_winner_status', 'judging',
    'bad_winner_jobs', 1,
    'stale_token_result', 'skipped',
    'exhausted_results', 'retry_scheduled/retry_scheduled/retry_scheduled/voided',
    'exhausted_status', 'voided',
    'exhausted_winner', true,
    'exhausted_outcomes', 0,
    'exhausted_deltas', 0,
    'exhausted_jobs', 0,
    'exhausted_today_slots', 0,
    'yesterday_slots_kept', 2,
    'lease_attempts', 1,
    'lease_token_cleared', true,
    'lease_error', '판정 임대가 만료됐습니다.',
    'lease_jobs', 1,
    'old_token_result', 'skipped',
    'old_token_untouched', true,
    'forfeit_jobs', 0,
    'delete_jobs', 0,
    'delete_status', 'cancelled',
    'perm_claim_anon', 'rejected',
    'perm_dispatch_authenticated', 'rejected',
    'perm_record_authenticated', 'rejected',
    'rls_jobs', 0,
    'dropped_table', 0,
    'dropped_functions', 0,
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
