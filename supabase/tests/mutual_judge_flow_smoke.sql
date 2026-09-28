-- mutual-judge 2단계 흐름 스모크 테스트 (제출·교체·판정 창·상호 판정·자동 승인·공개 범위·권한).
--
-- 로컬에 Docker가 없어 원격 DB에 직접 돌린다:
--   supabase db query --linked -f supabase/tests/mutual_judge_flow_smoke.sql
--
-- 마지막에 일부러 예외를 던져 전체를 롤백한다. 결과:
--   SMOKE RESULT ok=t                     -> 통과
--   SMOKE RESULT ok=f  FAILURES: ...      -> 어긋난 항목(기대값/실제값)
--
-- A = 생성자, B = 참가자. 트랜잭션 안의 now()는 고정이다.
-- 확인하는 것
--   f1 (속도전)  첫 제출은 창을 열지 않음 / 교체는 행을 덮어쓰고 submitted_at을 다시 찍고 옛 경로를 돌려줌 /
--               판정 창 전 B는 A의 제출 행을 0행 읽음 / B 제출로 판정 창 열림(기한 = 열림 + 24시간) /
--               창이 열린 뒤 A 교체는 SUBMISSION_LOCKED / 창이 열리면 B가 제출 2행을 읽음 /
--               A 판정 뒤 A 재판정은 ALREADY_JUDGED / 창 중에는 B가 A의 판정을 읽지 못함 /
--               속도전에 우열을 넣으면 거부 / 양쪽 승인 즉시 종결(24시간 대기 없음) / 종결 뒤 판정 2행 공개
--   f2 (품질전)  두 번째 제출은 SUBMISSION_LOCKED / 우열 없이 판정하면 SUPERIORITY_REQUIRED /
--               불복은 AI 재판정을 기다리며 judging에 머묾(잡은 3단계)
--   f3 (속도전)  판정 기한 경과: 빠진 판정만 자동 승인(auto) -> 결론. 자동 승인된 완료도 completed_loss
--   f4 (속도전)  A만 제출, 기한 경과: B만 자동 승인(A는 판정할 것이 없다) -> A 승. 기한 뒤 판정은 JUDGE_WINDOW_CLOSED
--   f5 (속도전)  기한 전, A만 제출: A가 판정하려 하면 NOTHING_TO_JUDGE, 창은 그대로
--   f6 (속도전)  제출 창에서 판정하려 하면 JUDGING_NOT_OPEN
--   권한         anon은 submit_judgment, authenticated는 accept_submission·close_expired_judging_windows를 못 부른다
do $$
declare
  v_a uuid := gen_random_uuid();
  v_b uuid := gen_random_uuid();
  v_f1 uuid;
  v_f2 uuid;
  v_f3 uuid;
  v_f4 uuid;
  v_f5 uuid;
  v_f6 uuid;
  v_r jsonb;
  v_f1_first jsonb;
  v_f1_replace jsonb;
  v_f1_b jsonb;
  v_hint text;
  v_f1_locked text := '(예외 없음)';
  v_f1_again text := '(예외 없음)';
  v_f1_speed_superior text := '(예외 없음)';
  v_f1_a_judge text;
  v_f1_b_judge text;
  v_f1_b_sees_before bigint;
  v_f1_b_sees_after bigint;
  v_f1_b_sees_judgments_during bigint;
  v_f1_b_sees_judgments_after bigint;
  v_f2_second text := '(예외 없음)';
  v_f2_no_superior text := '(예외 없음)';
  v_f2_a_judge text;
  v_f2_b_judge text;
  v_f4_late text := '(예외 없음)';
  v_f5_nothing text := '(예외 없음)';
  v_f6_not_open text := '(예외 없음)';
  v_closed integer;
  v_anon_judge text := '(예외 없음)';
  v_auth_accept text := '(예외 없음)';
  v_auth_close text := '(예외 없음)';
  v_actual jsonb;
  v_expected jsonb;
  v_diff text;
begin
  insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  values
    (v_a, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'mutual-smoke-a@example.invalid', '{"full_name":"스모크A"}'::jsonb, now(), now()),
    (v_b, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'mutual-smoke-b@example.invalid', '{"full_name":"스모크B"}'::jsonb, now(), now());

  -- 제출은 동의가 있어야 받는다(이 스모크의 확인 대상이 아니다).
  perform set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
  perform public.give_ai_consent('2026-09-14');
  perform set_config('request.jwt.claims', json_build_object('sub', v_b, 'role', 'authenticated')::text, true);
  perform public.give_ai_consent('2026-09-14');

  -- 제출 창인 대결 셋(f1 속도전, f2 품질전, f6 속도전). 5분 전에 매칭, 1시간 뒤 마감.
  insert into public.battles (min_criteria, superiority_criteria, type, status, title, creator_id, opponent_id, duration_minutes, started_at, deadline_at)
  values ('["상판이 보인다"]'::jsonb, null, 'speed', 'active', 'f1 속도전', v_a, v_b, 60, now() - interval '5 minutes', now() + interval '55 minutes')
  returning id into v_f1;
  insert into public.battles (min_criteria, superiority_criteria, type, status, title, creator_id, opponent_id, duration_minutes, started_at, deadline_at)
  values ('["바닥이 보인다"]'::jsonb, '["먼지가 없다"]'::jsonb, 'quality', 'active', 'f2 품질전', v_a, v_b, 60, now() - interval '5 minutes', now() + interval '55 minutes')
  returning id into v_f2;
  insert into public.battles (min_criteria, superiority_criteria, type, status, title, creator_id, opponent_id, duration_minutes, started_at, deadline_at)
  values ('["상판이 보인다"]'::jsonb, null, 'speed', 'active', 'f6 속도전', v_a, v_b, 60, now() - interval '5 minutes', now() + interval '55 minutes')
  returning id into v_f6;

  -- 판정 창인 대결 셋. f3·f4는 판정 기한이 지났고 f5는 아직이다.
  insert into public.battles (min_criteria, superiority_criteria, type, status, title, creator_id, opponent_id, duration_minutes,
                              started_at, deadline_at, judging_opened_at, judge_deadline_at)
  values ('["상판이 보인다"]'::jsonb, null, 'speed', 'judging', 'f3 기한 경과', v_a, v_b, 60,
          now() - interval '27 hours', now() - interval '26 hours', now() - interval '26 hours', now() - interval '2 hours')
  returning id into v_f3;
  insert into public.battles (min_criteria, superiority_criteria, type, status, title, creator_id, opponent_id, duration_minutes,
                              started_at, deadline_at, judging_opened_at, judge_deadline_at)
  values ('["상판이 보인다"]'::jsonb, null, 'speed', 'judging', 'f4 한쪽 제출 기한 경과', v_a, v_b, 60,
          now() - interval '27 hours', now() - interval '26 hours', now() - interval '26 hours', now() - interval '2 hours')
  returning id into v_f4;
  insert into public.battles (min_criteria, superiority_criteria, type, status, title, creator_id, opponent_id, duration_minutes,
                              started_at, deadline_at, judging_opened_at, judge_deadline_at)
  values ('["상판이 보인다"]'::jsonb, null, 'speed', 'judging', 'f5 한쪽 제출 기한 전', v_a, v_b, 60,
          now() - interval '2 hours', now() - interval '1 hour', now() - interval '1 hour', now() + interval '23 hours')
  returning id into v_f5;

  -- creator 참가자 행은 트리거가 만든다. opponent 행만 직접 넣는다.
  insert into public.battle_participants (battle_id, user_id)
  values (v_f1, v_b), (v_f2, v_b), (v_f3, v_b), (v_f4, v_b), (v_f5, v_b), (v_f6, v_b);

  -- f3: 양쪽 제출(B가 먼저), A는 B를 승인했고 B는 판정하지 않았다.
  insert into public.battle_submissions (battle_id, user_id, object_path, captured_at, submitted_at, meets_criteria, verdict_source)
  values
    (v_f3, v_a, 'smoke/a.jpg', now() - interval '26 hours 10 minutes', now() - interval '26 hours 10 minutes', null, null),
    (v_f3, v_b, 'smoke/b.jpg', now() - interval '26 hours 30 minutes', now() - interval '26 hours 30 minutes', true, 'opponent');
  insert into public.battle_judgments (battle_id, judge_id, min_verdict) values (v_f3, v_a, 'approve');
  update public.battle_participants set has_submitted = true where battle_id = v_f3;
  update public.battle_participants set has_judged = true where battle_id = v_f3 and user_id = v_a;

  -- f4·f5: A만 제출.
  insert into public.battle_submissions (battle_id, user_id, object_path, captured_at, submitted_at)
  values
    (v_f4, v_a, 'smoke/a.jpg', now() - interval '26 hours 10 minutes', now() - interval '26 hours 10 minutes'),
    (v_f5, v_a, 'smoke/a.jpg', now() - interval '70 minutes', now() - interval '70 minutes');
  update public.battle_participants set has_submitted = true where battle_id in (v_f4, v_f5) and user_id = v_a;

  -- ── f1: 속도전 제출·교체·잠금·공개·판정 ──────────────────────────────────────
  v_f1_first := public.accept_submission(v_a, v_f1, v_f1 || '/' || v_a || '/p1.jpg', now());

  -- 교체가 제출 시각을 다시 찍는지 보려고 첫 제출을 3분 전으로 돌려 둔다.
  update public.battle_submissions set submitted_at = now() - interval '3 minutes'
  where battle_id = v_f1 and user_id = v_a;

  v_f1_replace := public.accept_submission(v_a, v_f1, v_f1 || '/' || v_a || '/p2.jpg', now());

  -- 판정 창 전: B는 A의 제출 행을 읽지 못한다.
  perform set_config('request.jwt.claims', json_build_object('sub', v_b, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  select count(*) into v_f1_b_sees_before from public.battle_submissions where battle_id = v_f1;
  execute 'reset role';

  -- B 제출 -> 양쪽 제출이므로 판정 창이 열린다.
  v_f1_b := public.accept_submission(v_b, v_f1, v_f1 || '/' || v_b || '/b1.jpg', now());

  begin
    perform public.accept_submission(v_a, v_f1, v_f1 || '/' || v_a || '/p3.jpg', now());
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    v_f1_locked := coalesce(nullif(v_hint, ''), sqlerrm);
  end;

  -- 판정 창이 열리면 B는 제출 2행을 읽는다.
  execute 'set local role authenticated';
  select count(*) into v_f1_b_sees_after from public.battle_submissions where battle_id = v_f1;
  execute 'reset role';

  perform set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
  v_f1_a_judge := public.submit_judgment(v_f1, 'approve', null);

  begin
    perform public.submit_judgment(v_f1, 'reject', null);
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    v_f1_again := coalesce(nullif(v_hint, ''), sqlerrm);
  end;

  -- 판정 창 중에는 B가 A의 판정 내용을 읽지 못한다(상대 답을 보고 고르는 경로 차단).
  perform set_config('request.jwt.claims', json_build_object('sub', v_b, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  select count(*) into v_f1_b_sees_judgments_during from public.battle_judgments where battle_id = v_f1;
  execute 'reset role';

  begin
    perform public.submit_judgment(v_f1, 'approve', v_a);
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    v_f1_speed_superior := coalesce(nullif(v_hint, ''), sqlerrm);
  end;

  v_f1_b_judge := public.submit_judgment(v_f1, 'approve', null);

  execute 'set local role authenticated';
  select count(*) into v_f1_b_sees_judgments_after from public.battle_judgments where battle_id = v_f1;
  execute 'reset role';

  -- ── f2: 품질전 ───────────────────────────────────────────────────────────────
  perform public.accept_submission(v_a, v_f2, v_f2 || '/' || v_a || '/q1.jpg', now());

  begin
    perform public.accept_submission(v_a, v_f2, v_f2 || '/' || v_a || '/q2.jpg', now());
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    v_f2_second := coalesce(nullif(v_hint, ''), sqlerrm);
  end;

  perform public.accept_submission(v_b, v_f2, v_f2 || '/' || v_b || '/q1.jpg', now());

  perform set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
  begin
    perform public.submit_judgment(v_f2, 'approve', null);
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    v_f2_no_superior := coalesce(nullif(v_hint, ''), sqlerrm);
  end;

  -- A는 B의 사진을 불복하고 자기가 더 잘했다고 한다. B는 A를 승인하고 자기가 더 잘했다고 한다.
  v_f2_a_judge := public.submit_judgment(v_f2, 'reject', v_a);
  perform set_config('request.jwt.claims', json_build_object('sub', v_b, 'role', 'authenticated')::text, true);
  v_f2_b_judge := public.submit_judgment(v_f2, 'approve', v_b);

  -- ── f4·f5·f6: 판정 오류 코드 ───────────────────────────────────────────────
  begin
    perform public.submit_judgment(v_f4, 'approve', null);
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    v_f4_late := coalesce(nullif(v_hint, ''), sqlerrm);
  end;

  perform set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
  begin
    perform public.submit_judgment(v_f5, 'approve', null);
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    v_f5_nothing := coalesce(nullif(v_hint, ''), sqlerrm);
  end;

  begin
    perform public.submit_judgment(v_f6, 'approve', null);
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    v_f6_not_open := coalesce(nullif(v_hint, ''), sqlerrm);
  end;

  -- ── 판정 기한 경과: 자동 승인 ───────────────────────────────────────────────
  v_closed := public.close_expired_judging_windows();

  -- ── 권한 ────────────────────────────────────────────────────────────────────
  begin
    execute 'set local role anon';
    perform public.submit_judgment(v_f5, 'approve', null);
    execute 'reset role';
  exception when insufficient_privilege then
    v_anon_judge := '권한 없음';
  when others then
    v_anon_judge := '다른 오류: ' || sqlerrm;
  end;
  execute 'reset role';

  begin
    execute 'set local role authenticated';
    perform public.accept_submission(v_a, v_f6, v_f6 || '/' || v_a || '/x.jpg', now());
    execute 'reset role';
  exception when insufficient_privilege then
    v_auth_accept := '권한 없음';
  when others then
    v_auth_accept := '다른 오류: ' || sqlerrm;
  end;
  execute 'reset role';

  begin
    execute 'set local role authenticated';
    perform public.close_expired_judging_windows();
    execute 'reset role';
  exception when insufficient_privilege then
    v_auth_close := '권한 없음';
  when others then
    v_auth_close := '다른 오류: ' || sqlerrm;
  end;
  execute 'reset role';

  select jsonb_object_agg(
           l.name,
           b.status
             || '/' || coalesce(case b.winner_id when v_a then 'A' when v_b then 'B' end, '-')
             || '/' || coalesce(pa.outcome, '-')
             || '/' || coalesce(pb.outcome, '-')
         )
  into v_actual
  from unnest(
         array[v_f1, v_f2, v_f3, v_f4, v_f5, v_f6],
         array['f1', 'f2', 'f3', 'f4', 'f5', 'f6']
       ) as l(id, name)
  join public.battles b on b.id = l.id
  left join public.battle_participants pa on pa.battle_id = b.id and pa.user_id = v_a
  left join public.battle_participants pb on pb.battle_id = b.id and pb.user_id = v_b;

  v_actual := v_actual || jsonb_build_object(
    'f1_first_opened', v_f1_first -> 'judging_opened',
    'f1_first_replaced', v_f1_first -> 'replaced_object_path',
    'f1_replace_path', v_f1_replace ->> 'replaced_object_path',
    'f1_a_rows', (select count(*) from public.battle_submissions where battle_id = v_f1 and user_id = v_a),
    'f1_a_path', (select object_path from public.battle_submissions where battle_id = v_f1 and user_id = v_a),
    'f1_a_resubmitted_now', (select submitted_at = now() from public.battle_submissions
                             where battle_id = v_f1 and user_id = v_a),
    'f1_b_sees_before', v_f1_b_sees_before,
    'f1_b_opened', v_f1_b -> 'judging_opened',
    'f1_b_status', v_f1_b ->> 'battle_status',
    'f1_window', (select judging_opened_at = now() and judge_deadline_at = now() + interval '24 hours'
                  from public.battles where id = v_f1),
    'f1_locked', v_f1_locked,
    'f1_b_sees_after', v_f1_b_sees_after,
    'f1_a_judge', v_f1_a_judge,
    'f1_again', v_f1_again,
    'f1_b_sees_judgments_during', v_f1_b_sees_judgments_during,
    'f1_speed_superior', v_f1_speed_superior,
    'f1_b_judge', v_f1_b_judge,
    'f1_b_sees_judgments_after', v_f1_b_sees_judgments_after,
    'f1_flags', (select string_agg(has_submitted::text || ',' || has_judged::text, '/' order by user_id = v_b)
                 from public.battle_participants where battle_id = v_f1),
    'f1_sources', (select string_agg(coalesce(verdict_source, '-'), '/' order by user_id = v_b)
                   from public.battle_submissions where battle_id = v_f1),
    'f2_second', v_f2_second,
    'f2_no_superior', v_f2_no_superior,
    'f2_a_judge', v_f2_a_judge,
    'f2_b_judge', v_f2_b_judge,
    'f2_meets', (select string_agg(coalesce(meets_criteria::text, '-'), '/' order by user_id = v_b)
                 from public.battle_submissions where battle_id = v_f2),
    'f3_b_auto', (select auto from public.battle_judgments where battle_id = v_f3 and judge_id = v_b),
    'f3_a_source', (select verdict_source from public.battle_submissions where battle_id = v_f3 and user_id = v_a),
    'f3_b_judged', (select has_judged from public.battle_participants where battle_id = v_f3 and user_id = v_b),
    'f4_late', v_f4_late,
    'f4_a_judgments', (select count(*) from public.battle_judgments where battle_id = v_f4 and judge_id = v_a),
    'f4_b_auto', (select auto from public.battle_judgments where battle_id = v_f4 and judge_id = v_b),
    'f5_nothing', v_f5_nothing,
    'f6_not_open', v_f6_not_open,
    'anon_judge', v_anon_judge,
    'auth_accept', v_auth_accept,
    'auth_close', v_auth_close,
    'disputed_count', (select count(*) from public.battles
                       where status = 'disputed' and id in (v_f1, v_f2, v_f3, v_f4, v_f5, v_f6))
  );

  v_expected := jsonb_build_object(
    -- f1: 교체한 A의 제출 시각(now)과 B의 제출 시각(now)이 같아 먼저 기록된 A(작은 id)가 이긴다.
    'f1', 'finished/A/win/completed_loss',
    'f2', 'judging/-/-/-',
    -- f3: B가 먼저 냈다. A의 완료는 B가 판정하지 않아 자동 승인됐고 그래도 completed_loss 감면을 받는다.
    'f3', 'finished/B/completed_loss/win',
    'f4', 'finished/A/win/loss',
    'f5', 'judging/-/-/-',
    'f6', 'active/-/-/-',
    'f1_first_opened', false,
    'f1_first_replaced', null,
    'f1_replace_path', v_f1 || '/' || v_a || '/p1.jpg',
    'f1_a_rows', 1,
    'f1_a_path', v_f1 || '/' || v_a || '/p2.jpg',
    'f1_a_resubmitted_now', true,
    'f1_b_sees_before', 0,
    'f1_b_opened', true,
    'f1_b_status', 'judging',
    'f1_window', true,
    'f1_locked', 'SUBMISSION_LOCKED',
    'f1_b_sees_after', 2,
    'f1_a_judge', 'judging',
    'f1_again', 'ALREADY_JUDGED',
    'f1_b_sees_judgments_during', 0,
    'f1_speed_superior', '속도전에는 우열 판정이 없습니다.',
    'f1_b_judge', 'finished',
    'f1_b_sees_judgments_after', 2,
    'f1_flags', 'true,true/true,true',
    'f1_sources', 'opponent/opponent',
    'f2_second', 'SUBMISSION_LOCKED',
    'f2_no_superior', 'SUPERIORITY_REQUIRED',
    'f2_a_judge', 'judging',
    'f2_b_judge', 'judging',
    'f2_meets', 'true/-',
    'f3_b_auto', true,
    'f3_a_source', 'auto',
    'f3_b_judged', true,
    'f4_late', 'JUDGE_WINDOW_CLOSED',
    'f4_a_judgments', 0,
    'f4_b_auto', true,
    'f5_nothing', 'NOTHING_TO_JUDGE',
    'f6_not_open', 'JUDGING_NOT_OPEN',
    'anon_judge', '권한 없음',
    'auth_accept', '권한 없음',
    'auth_close', '권한 없음',
    'disputed_count', 0
  );

  select coalesce(string_agg(format('%s expected=%s actual=%s', e.key, e.value, coalesce(a.value::text, 'null')), '; '), '')
  into v_diff
  from jsonb_each(v_expected) e
  left join jsonb_each(v_actual) a on a.key = e.key
  where a.value is distinct from e.value;

  raise exception 'SMOKE RESULT ok=% % closed_total=%', v_diff = '',
    case when v_diff = '' then '' else ' FAILURES: ' || v_diff end,
    v_closed;
end $$;
