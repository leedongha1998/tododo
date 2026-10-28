-- 판정 창·제출 교체·상호 판정 흐름 스모크 테스트 (mutual-judge 2단계).
--
-- 로컬에 Docker가 없어 원격 DB에 직접 돌린다:
--   supabase db query --linked -f supabase/tests/mutual_judge_flow_smoke.sql
--
-- 마지막에 일부러 예외를 던져 전체를 롤백한다. 결과:
--   SMOKE RESULT ok=true                    -> 통과
--   SMOKE RESULT ok=false FAILURES: ...     -> 어긋난 항목(기대값/실제값)
--
-- 2단계는 AI 재판정 배선(ai_judgment_jobs)이 없다. 그래서 불복(reject)·우열 불일치는
-- 영원히 judging에 머문다 — 그 결과를 "아직 안 끝남"으로 검증하고, voided/AI 뒤집기는
-- 3단계 테스트(ai_rejudgment)로 넘긴다.
--
-- 확인하는 것
--   both_open        양쪽 제출 -> 마감 전이라도 즉시 judging, judge_deadline_at = 열린 시각+24h
--   replace_*        속도전 교체가 submitted_at을 갱신하고, 상대 제출 후에는 SUBMISSION_LOCKED
--   quality_locked   품질전 두 번째 제출은 거부(SUBMISSION_LOCKED)
--   settle_speed_one 마감, 속도전 한쪽만 제출 -> 창 열림(judging), 즉시 종결 아님
--   settle_speed_none 마감, 속도전 아무도 제출 안 함 -> draw
--   settle_quality_one 마감, 품질전 한쪽만 제출 -> 판정 없이 제출자 승리
--   settle_quality_none 마감, 품질전 아무도 제출 안 함 -> draw
--   judge_not_open    judging이 아닌 대결에 판정하면 JUDGING_NOT_OPEN
--   nothing_to_judge  상대가 제출하지 않았으면 NOTHING_TO_JUDGE
--   already_judged    같은 사람이 두 번 판정하면 ALREADY_JUDGED
--   superiority_required 품질전에서 우열 답을 빼면 SUPERIORITY_REQUIRED
--   speed_no_superiority 속도전에서 우열 답을 넣으면 거부
--   both_judge_instant 양쪽 판정이 끝나면 24시간을 기다리지 않고 즉시 종결
--   auto_approve_one  판정 기한 경과 -> 필요한 판정만 자동 승인, completed_loss 없음(한쪽만 제출)
--   auto_approve_both 양쪽 제출 + 양쪽 미판정 -> 기한 경과 시 둘 다 자동 승인, finished + completed_loss 감면
--   quality_agree     우열 답이 같은 사람을 가리키면 AI 없이 그 사람 승리
--   quality_mismatch  우열 답이 어긋나면 AI가 필요하다(next=ai) -> 3단계 전까지는 judging에 머문다
--   reject_pending    불복당한 제출은 AI 결과가 올 때까지 judging에 머문다
--   rls_before_open   판정 창 열리기 전에는 상대의 제출·판정 행이 보이지 않는다
--   rls_after_open    판정 창이 열리면 상대의 제출 행이 보인다(판정 내용은 종결 후에만)
--   perm_*            anon·authenticated의 서버 전용 함수 권한 오류
--   disputed_count    어떤 경로도 disputed를 만들지 않는다
do $$
declare
  v_a uuid := gen_random_uuid();  -- creator
  v_b uuid := gen_random_uuid();  -- opponent
  v_both_open uuid;
  v_replace uuid;
  v_settle_speed_one uuid;
  v_settle_speed_none uuid;
  v_settle_quality_one uuid;
  v_settle_quality_none uuid;
  v_quality_locked uuid;
  v_judge_not_open uuid;
  v_nothing_to_judge uuid;
  v_already_judged uuid;
  v_superiority_required uuid;
  v_speed_no_superiority uuid;
  v_both_judge_instant uuid;
  v_auto_approve_one uuid;
  v_auto_approve_both uuid;
  v_quality_agree uuid;
  v_quality_mismatch uuid;
  v_reject_pending uuid;
  v_rls uuid;
  v_i integer;
  v_id uuid;
  v_sub jsonb;
  v_replace_id_before bigint;
  v_replace_id_after bigint;
  v_replace_path_before text;
  v_replace_path_after text;
  v_replace_locked text := '(예외 없음)';
  v_quality_locked_err text := '(예외 없음)';
  v_judge_not_open_err text := '(예외 없음)';
  v_nothing_to_judge_err text := '(예외 없음)';
  v_already_judged_err text := '(예외 없음)';
  v_superiority_required_err text := '(예외 없음)';
  v_speed_no_superiority_err text := '(예외 없음)';
  v_perm_submit_judgment_anon text := '(예외 없음)';
  v_perm_close_windows_authenticated text := '(예외 없음)';
  v_rls_before_submissions integer := -1;
  v_rls_before_judgments integer := -1;
  v_rls_after_submissions integer := -1;
  v_hint text;
  v_actual jsonb;
  v_expected jsonb;
  v_diff text;
begin
  insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  select u.id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
         u.email, jsonb_build_object('full_name', u.name), now(), now()
  from (values
    (v_a, 'mutual-flow-a@example.invalid', '스모크A'),
    (v_b, 'mutual-flow-b@example.invalid', '스모크B')
  ) as u(id, email, name);

  update public.player_stats set score = 10 where user_id in (v_a, v_b);

  perform set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
  perform public.give_ai_consent('2026-09-18');
  perform set_config('request.jwt.claims', json_build_object('sub', v_b, 'role', 'authenticated')::text, true);
  perform public.give_ai_consent('2026-09-18');

  -- 매칭된 속도전 열한 개 + 품질전 여섯 개(어제 시작, 내일 마감). creator 참가자 행은 트리거가 만든다.
  for v_i in 1..11 loop
    insert into public.battles (
      min_criteria, superiority_criteria, type, status, title,
      creator_id, opponent_id, duration_minutes, started_at, deadline_at
    )
    values (
      '["상판이 보인다"]'::jsonb, null, 'speed', 'active', 'mutual flow speed ' || v_i,
      v_a, v_b, 4320, now() - interval '1 day', now() + interval '1 day'
    )
    returning id into v_id;

    insert into public.battle_participants (battle_id, user_id) values (v_id, v_b);

    case v_i
      when 1 then v_both_open := v_id;
      when 2 then v_replace := v_id;
      when 3 then v_settle_speed_one := v_id;
      when 4 then v_settle_speed_none := v_id;
      when 5 then v_judge_not_open := v_id;
      when 6 then v_nothing_to_judge := v_id;
      when 7 then v_already_judged := v_id;
      when 8 then v_speed_no_superiority := v_id;
      when 9 then v_both_judge_instant := v_id;
      when 10 then v_auto_approve_one := v_id;
      else v_auto_approve_both := v_id;
    end case;
  end loop;

  for v_i in 1..6 loop
    insert into public.battles (
      min_criteria, superiority_criteria, type, status, title,
      creator_id, opponent_id, duration_minutes, started_at, deadline_at
    )
    values (
      '["바닥이 보인다"]'::jsonb, '["먼지가 없다"]'::jsonb, 'quality', 'active',
      'mutual flow quality ' || v_i, v_a, v_b, 4320, now() - interval '1 day', now() + interval '1 day'
    )
    returning id into v_id;

    insert into public.battle_participants (battle_id, user_id) values (v_id, v_b);

    case v_i
      when 1 then v_settle_quality_one := v_id;
      when 2 then v_settle_quality_none := v_id;
      when 3 then v_quality_locked := v_id;
      when 4 then v_quality_agree := v_id;
      when 5 then v_quality_mismatch := v_id;
      else v_reject_pending := v_id;
    end case;
  end loop;

  -- RLS용 대결 하나 더(마감 전이면 뒤에서 상태를 바꿀 수 있어야 하므로 따로 둔다).
  insert into public.battles (
    min_criteria, superiority_criteria, type, status, title,
    creator_id, opponent_id, duration_minutes, started_at, deadline_at
  )
  values (
    '["상판이 보인다"]'::jsonb, null, 'speed', 'active', 'mutual flow rls',
    v_a, v_b, 4320, now() - interval '1 day', now() + interval '1 day'
  )
  returning id into v_rls;
  insert into public.battle_participants (battle_id, user_id) values (v_rls, v_b);

  -- 품질전 우열 요구 확인용 대결 하나 더.
  insert into public.battles (
    min_criteria, superiority_criteria, type, status, title,
    creator_id, opponent_id, duration_minutes, started_at, deadline_at
  )
  values (
    '["바닥이 보인다"]'::jsonb, '["먼지가 없다"]'::jsonb, 'quality', 'active',
    'mutual flow quality superiority required', v_a, v_b, 4320,
    now() - interval '1 day', now() + interval '1 day'
  )
  returning id into v_superiority_required;
  insert into public.battle_participants (battle_id, user_id) values (v_superiority_required, v_b);

  -- 1. 양쪽 제출 -> 마감 전이라도 즉시 judging, 판정 기한은 "지금 + 24시간".
  perform public.accept_submission(v_a, v_both_open, format('%s/%s/1.jpg', v_both_open, v_a), now());
  perform public.accept_submission(v_b, v_both_open, format('%s/%s/1.jpg', v_both_open, v_b), now());

  -- 2. 속도전 교체: 상대가 내기 전까지 바꿀 수 있고, 바꾸면 행을 덮어쓴다(새 행이 아니다).
  --    같은 트랜잭션 안에서는 now()가 고정이라 제출 시각 자체의 변화는 여기서 보이지 않는다
  --    (실제 호출에서는 매번 다른 서버 시각이 찍힌다) — 대신 같은 행(id)이 재사용되고
  --    경로가 바뀌는 것으로 "덮어쓰기"를 확인한다.
  v_sub := public.accept_submission(v_a, v_replace, format('%s/%s/old.jpg', v_replace, v_a), now());
  v_replace_id_before := (v_sub ->> 'submission_id')::bigint;
  select object_path into v_replace_path_before
  from public.battle_submissions where id = v_replace_id_before;

  v_sub := public.accept_submission(v_a, v_replace, format('%s/%s/new.jpg', v_replace, v_a), now());
  v_replace_id_after := (v_sub ->> 'submission_id')::bigint;
  select object_path into v_replace_path_after
  from public.battle_submissions where id = v_replace_id_after;

  perform public.accept_submission(v_b, v_replace, format('%s/%s/1.jpg', v_replace, v_b), now());
  begin
    perform public.accept_submission(v_a, v_replace, format('%s/%s/again.jpg', v_replace, v_a), now());
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    v_replace_locked := coalesce(v_hint, '(힌트 없음)');
  end;

  -- 3. 품질전 두 번째 제출은 거부된다(재제출 없음).
  perform public.accept_submission(v_a, v_quality_locked, format('%s/%s/1.jpg', v_quality_locked, v_a), now());
  begin
    perform public.accept_submission(v_a, v_quality_locked, format('%s/%s/2.jpg', v_quality_locked, v_a), now());
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    v_quality_locked_err := coalesce(v_hint, '(힌트 없음)');
  end;

  -- 4. 마감 시 정산.
  perform public.accept_submission(v_a, v_settle_speed_one, format('%s/%s/1.jpg', v_settle_speed_one, v_a), now());
  update public.battles set deadline_at = now() - interval '1 hour' where id = v_settle_speed_one;

  update public.battles set deadline_at = now() - interval '1 hour' where id = v_settle_speed_none;

  perform public.accept_submission(
    v_a, v_settle_quality_one, format('%s/%s/1.jpg', v_settle_quality_one, v_a), now());
  update public.battles set deadline_at = now() - interval '1 hour' where id = v_settle_quality_one;

  update public.battles set deadline_at = now() - interval '1 hour' where id = v_settle_quality_none;

  perform public.settle_expired_battles();

  -- 5. judging이 아닌 대결에 판정하면 JUDGING_NOT_OPEN.
  perform set_config('request.jwt.claims', json_build_object('sub', v_b, 'role', 'authenticated')::text, true);
  begin
    perform public.submit_judgment(v_judge_not_open, 'approve', null);
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    v_judge_not_open_err := coalesce(v_hint, '(힌트 없음)');
  end;

  -- 6. 상대가 제출하지 않았으면 판정할 것이 없다(NOTHING_TO_JUDGE).
  perform public.accept_submission(
    v_a, v_nothing_to_judge, format('%s/%s/1.jpg', v_nothing_to_judge, v_a), now());
  update public.battles set deadline_at = now() - interval '1 hour' where id = v_nothing_to_judge;
  perform public.settle_expired_battles();  -- a만 제출 -> 창 열림(judging), 판정할 사람은 b.
  perform set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
  begin
    perform public.submit_judgment(v_nothing_to_judge, 'approve', null);
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    v_nothing_to_judge_err := coalesce(v_hint, '(힌트 없음)');
  end;

  -- 7. 판정은 한 번뿐이다(ALREADY_JUDGED).
  perform public.accept_submission(v_a, v_already_judged, format('%s/%s/1.jpg', v_already_judged, v_a), now());
  perform public.accept_submission(v_b, v_already_judged, format('%s/%s/1.jpg', v_already_judged, v_b), now());
  perform set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
  perform public.submit_judgment(v_already_judged, 'approve', null);
  begin
    perform public.submit_judgment(v_already_judged, 'approve', null);
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    v_already_judged_err := coalesce(v_hint, '(힌트 없음)');
  end;

  -- 8. 속도전에 우열 답을 넣으면 거부된다(우열은 품질전만).
  perform public.accept_submission(
    v_a, v_speed_no_superiority, format('%s/%s/1.jpg', v_speed_no_superiority, v_a), now());
  perform public.accept_submission(
    v_b, v_speed_no_superiority, format('%s/%s/1.jpg', v_speed_no_superiority, v_b), now());
  perform set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
  begin
    perform public.submit_judgment(v_speed_no_superiority, 'approve', v_b);
  exception when others then
    v_speed_no_superiority_err := 'rejected';
  end;

  -- 9. 양쪽 판정이 끝나면 24시간을 기다리지 않고 즉시 종결된다.
  perform public.accept_submission(
    v_a, v_both_judge_instant, format('%s/%s/1.jpg', v_both_judge_instant, v_a), now());
  perform public.accept_submission(
    v_b, v_both_judge_instant, format('%s/%s/1.jpg', v_both_judge_instant, v_b), now());
  perform set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
  perform public.submit_judgment(v_both_judge_instant, 'approve', null);
  perform set_config('request.jwt.claims', json_build_object('sub', v_b, 'role', 'authenticated')::text, true);
  perform public.submit_judgment(v_both_judge_instant, 'approve', null);

  -- 10. 판정 기한 경과 -> 필요한 판정만 자동 승인(한쪽만 제출).
  perform public.accept_submission(
    v_a, v_auto_approve_one, format('%s/%s/1.jpg', v_auto_approve_one, v_a), now());
  update public.battles set deadline_at = now() - interval '2 hours' where id = v_auto_approve_one;
  perform public.settle_expired_battles();  -- a만 제출 -> 창 열림.
  update public.battles set judge_deadline_at = now() - interval '1 hour' where id = v_auto_approve_one;
  perform public.close_expired_judging_windows();

  -- 11. 양쪽 제출 + 양쪽 미판정 -> 기한 경과 시 둘 다 자동 승인. 같은 트랜잭션이라 두 제출 시각이
  --     같으므로 승부는 동률 규칙(seq가 작은 쪽, 즉 먼저 기록된 a)으로 갈린다 — 실제 호출에서는
  --     서버 시각이 실제로 달라 이 동률 규칙까지 갈 일이 거의 없다.
  perform public.accept_submission(
    v_a, v_auto_approve_both, format('%s/%s/1.jpg', v_auto_approve_both, v_a), now());
  perform public.accept_submission(
    v_b, v_auto_approve_both, format('%s/%s/1.jpg', v_auto_approve_both, v_b), now());
  update public.battles set judge_deadline_at = now() - interval '1 hour' where id = v_auto_approve_both;
  perform public.close_expired_judging_windows();

  -- 12. 품질전: 우열 답이 같은 사람을 가리키면 AI 없이 그 사람 승리.
  perform public.accept_submission(v_a, v_quality_agree, format('%s/%s/1.jpg', v_quality_agree, v_a), now());
  perform public.accept_submission(v_b, v_quality_agree, format('%s/%s/1.jpg', v_quality_agree, v_b), now());
  perform set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
  perform public.submit_judgment(v_quality_agree, 'approve', v_a);
  perform set_config('request.jwt.claims', json_build_object('sub', v_b, 'role', 'authenticated')::text, true);
  perform public.submit_judgment(v_quality_agree, 'approve', v_a);

  -- 13. 품질전: 우열 답이 어긋나면(둘 다 자기 승리 주장) AI가 필요하다 -> 3단계 전까지는 judging.
  perform public.accept_submission(v_a, v_quality_mismatch, format('%s/%s/1.jpg', v_quality_mismatch, v_a), now());
  perform public.accept_submission(v_b, v_quality_mismatch, format('%s/%s/1.jpg', v_quality_mismatch, v_b), now());
  perform set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
  perform public.submit_judgment(v_quality_mismatch, 'approve', v_a);
  perform set_config('request.jwt.claims', json_build_object('sub', v_b, 'role', 'authenticated')::text, true);
  perform public.submit_judgment(v_quality_mismatch, 'approve', v_b);

  -- 14. 불복당한 제출은 AI 결과가 올 때까지 judging에 머문다(3단계 전까지 끝나지 않는다).
  perform public.accept_submission(v_a, v_reject_pending, format('%s/%s/1.jpg', v_reject_pending, v_a), now());
  perform public.accept_submission(v_b, v_reject_pending, format('%s/%s/1.jpg', v_reject_pending, v_b), now());
  perform set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
  -- a가 b의 사진을 불복한다(b의 effect가 pending이 된다).
  perform public.submit_judgment(v_reject_pending, 'reject', v_a);
  perform set_config('request.jwt.claims', json_build_object('sub', v_b, 'role', 'authenticated')::text, true);
  -- b는 a의 사진을 승인한다(a의 effect는 pass). 그래도 b의 effect가 pending이라 전체는 judging.
  perform public.submit_judgment(v_reject_pending, 'approve', v_a);

  -- 15. 품질전에서 우열 답을 빼면 SUPERIORITY_REQUIRED.
  perform public.accept_submission(
    v_a, v_superiority_required, format('%s/%s/1.jpg', v_superiority_required, v_a), now());
  perform public.accept_submission(
    v_b, v_superiority_required, format('%s/%s/1.jpg', v_superiority_required, v_b), now());
  perform set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
  begin
    perform public.submit_judgment(v_superiority_required, 'approve', null);
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    v_superiority_required_err := coalesce(v_hint, '(힌트 없음)');
  end;

  -- 16. RLS: 판정 창이 열리기 전에는 상대의 제출·판정 행이 보이지 않는다.
  perform public.accept_submission(v_a, v_rls, format('%s/%s/1.jpg', v_rls, v_a), now());

  perform set_config('request.jwt.claims', json_build_object('sub', v_b, 'role', 'authenticated')::text, true);
  begin
    execute 'set local role authenticated';
    select count(*) into v_rls_before_submissions
    from public.battle_submissions where battle_id = v_rls and user_id = v_a;
    select count(*) into v_rls_before_judgments
    from public.battle_judgments where battle_id = v_rls and judge_id = v_a;
    execute 'reset role';
  exception when others then
    execute 'reset role';
    v_rls_before_submissions := -2;
  end;

  -- 판정 창을 연다(b도 제출). 열린 뒤에는 상대 제출 행이 보인다.
  perform public.accept_submission(v_b, v_rls, format('%s/%s/1.jpg', v_rls, v_b), now());

  perform set_config('request.jwt.claims', json_build_object('sub', v_b, 'role', 'authenticated')::text, true);
  begin
    execute 'set local role authenticated';
    select count(*) into v_rls_after_submissions
    from public.battle_submissions where battle_id = v_rls and user_id = v_a;
    execute 'reset role';
  exception when others then
    execute 'reset role';
    v_rls_after_submissions := -2;
  end;

  -- 17. 권한: anon은 submit_judgment를 부를 수 없고, authenticated는 close_expired_judging_windows를
  --     부를 수 없다(cron/service 전용).
  begin
    execute 'set local role anon';
    perform public.submit_judgment(v_both_open, 'approve', null);
    execute 'reset role';
    v_perm_submit_judgment_anon := '(거부되지 않음)';
  exception when insufficient_privilege then
    v_perm_submit_judgment_anon := 'rejected';
  when others then
    v_perm_submit_judgment_anon := '다른 오류: ' || sqlerrm;
  end;
  execute 'reset role';

  begin
    execute 'set local role authenticated';
    perform public.close_expired_judging_windows();
    execute 'reset role';
    v_perm_close_windows_authenticated := '(거부되지 않음)';
  exception when insufficient_privilege then
    v_perm_close_windows_authenticated := 'rejected';
  when others then
    v_perm_close_windows_authenticated := '다른 오류: ' || sqlerrm;
  end;
  execute 'reset role';

  v_actual := jsonb_build_object(
    'both_open_status', (select status from public.battles where id = v_both_open),
    'both_open_window_len', (
      select round(extract(epoch from (judge_deadline_at - judging_opened_at)) / 3600)
      from public.battles where id = v_both_open
    ),
    'replace_same_row', v_replace_id_after = v_replace_id_before,
    'replace_path_changed', v_replace_path_after <> v_replace_path_before,
    'replace_locked', v_replace_locked,
    'quality_locked_err', v_quality_locked_err,
    'settle_speed_one', (select status from public.battles where id = v_settle_speed_one),
    'settle_speed_none', (select status from public.battles where id = v_settle_speed_none),
    'settle_quality_one', (select status || '/' || (winner_id = v_a)::text
                           from public.battles where id = v_settle_quality_one),
    'settle_quality_none', (select status from public.battles where id = v_settle_quality_none),
    'judge_not_open_err', v_judge_not_open_err,
    'nothing_to_judge_err', v_nothing_to_judge_err,
    'already_judged_err', v_already_judged_err,
    'speed_no_superiority_err', v_speed_no_superiority_err,
    'superiority_required_err', v_superiority_required_err,
    'both_judge_instant', (select status || '/' || (winner_id is not null)::text
                           from public.battles where id = v_both_judge_instant),
    'auto_approve_one', (select status || '/' || coalesce(case winner_id when v_a then 'A' end, '-')
                         from public.battles where id = v_auto_approve_one),
    'auto_approve_both', (select status || '/' || coalesce(case winner_id when v_a then 'A' when v_b then 'B' end, '-')
                          from public.battles where id = v_auto_approve_both),
    'auto_approve_both_a_outcome', (select outcome from public.battle_participants
                                    where battle_id = v_auto_approve_both and user_id = v_a),
    'auto_approve_both_b_outcome', (select outcome from public.battle_participants
                                    where battle_id = v_auto_approve_both and user_id = v_b),
    'quality_agree', (select status || '/' || (winner_id = v_a)::text
                      from public.battles where id = v_quality_agree),
    'quality_mismatch', (select status from public.battles where id = v_quality_mismatch),
    'reject_pending', (select status from public.battles where id = v_reject_pending),
    'rls_before_submissions', v_rls_before_submissions,
    'rls_before_judgments', v_rls_before_judgments,
    'rls_after_submissions', v_rls_after_submissions,
    'perm_submit_judgment_anon', v_perm_submit_judgment_anon,
    'perm_close_windows_authenticated', v_perm_close_windows_authenticated,
    'disputed_count', (select count(*) from public.battles where creator_id = v_a and status = 'disputed')
  );

  v_expected := jsonb_build_object(
    'both_open_status', 'judging',
    'both_open_window_len', 24,
    'replace_same_row', true,
    'replace_path_changed', true,
    'replace_locked', 'SUBMISSION_LOCKED',
    'quality_locked_err', 'SUBMISSION_LOCKED',
    'settle_speed_one', 'judging',
    'settle_speed_none', 'draw',
    'settle_quality_one', 'finished/true',
    'settle_quality_none', 'draw',
    'judge_not_open_err', 'JUDGING_NOT_OPEN',
    'nothing_to_judge_err', 'NOTHING_TO_JUDGE',
    'already_judged_err', 'ALREADY_JUDGED',
    'speed_no_superiority_err', 'rejected',
    'superiority_required_err', 'SUPERIORITY_REQUIRED',
    'both_judge_instant', 'finished/true',
    'auto_approve_one', 'finished/A',
    'auto_approve_both', 'finished/A',
    'auto_approve_both_a_outcome', 'win',
    'auto_approve_both_b_outcome', 'completed_loss',
    'quality_agree', 'finished/true',
    'quality_mismatch', 'judging',
    'reject_pending', 'judging',
    'rls_before_submissions', 0,
    'rls_before_judgments', 0,
    'rls_after_submissions', 1,
    'perm_submit_judgment_anon', 'rejected',
    'perm_close_windows_authenticated', 'rejected',
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
