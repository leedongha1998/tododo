-- resolve_battle() / void_battle() 스모크 테스트 (mutual-judge 결론 규칙).
--
-- 로컬에 Docker가 없어 원격 DB에 직접 돌린다:
--   supabase db query --linked -f supabase/tests/resolve_battle_smoke.sql
--
-- 판정 창(judging)인 대결에 제출·판정 사실을 직접 넣고 resolve_battle을 부른다. 마지막에 일부러
-- 예외를 던져 트랜잭션 전체를 롤백한다. 결과는 예외 메시지로 돌아온다:
--   SMOKE RESULT ok=true                    -> 통과
--   SMOKE RESULT ok=false FAILURES: ...     -> 어긋난 항목(기대값/실제값)
--
-- A = 생성자, B = 참가자. A의 판정은 B의 제출에 대한 것이고 B의 판정은 A의 제출에 대한 것이다.
-- 기대값 (status/winner/A outcome/B outcome)
--   r1               속도전 양쪽 승인, A가 먼저 -> finished/A/win/completed_loss
--   r1_tie           같은 시각, B 제출이 먼저 기록됨 -> finished/B (생성자 우선이 아니라 id)
--   r_ai_pass        A가 B를 불복했지만 AI가 통과, B가 먼저 -> finished/B (거짓 불복은 이득이 없다)
--   r_ai_fail        A가 B를 불복하고 AI도 미달 -> finished/A/win/loss
--   r_pending_ai     불복했는데 AI 결과가 아직 없음 -> judging
--   r_pending_judge  A가 아직 판정하지 않음 -> judging
--   r_one_sub        속도전 A만 제출, B 승인 -> finished/A/win/loss
--   r_one_sub_fail   속도전 A만 제출, B 불복 후 AI 미달 -> draw
--   q_agree          품질전 둘 다 A를 승자로 -> finished/A/win/loss (AI 없음)
--   q_one_pick       품질전 A만 우열 답(B는 자동 승인) -> finished/A
--   q_mismatch       품질전 우열 불일치 -> judging (AI 재판정 대기, 잡은 3단계)
--   q_no_picks       품질전 둘 다 자동 승인(우열 미답) -> draw (AI 없음)
--   q_min_fail       품질전 B 사진 AI 미달 -> finished/A/win/loss (우열은 보지 않는다)
--   still_active     제출 창인 대결 -> 아무것도 하지 않음
--   다시 부르기        종결된 r1에 resolve_battle을 또 불러도 점수가 두 번 반영되지 않음
--   v_today / v_yday 무효: 오늘 매칭 슬롯만 반환, 점수 불변, 종결된 대결 무효화는 거부
do $$
declare
  v_a uuid := gen_random_uuid();
  v_b uuid := gen_random_uuid();
  v_c uuid := gen_random_uuid();
  v_d uuid := gen_random_uuid();
  v_today date := (now() at time zone 'Asia/Seoul')::date;
  v_ids jsonb := '{}'::jsonb;
  v_case record;
  v_name text;
  v_id uuid;
  v_still_active uuid;
  v_v_today uuid;
  v_v_yday uuid;
  v_r1_return text;
  v_r1_again text;
  v_still_active_return text;
  v_void_finished_rejected boolean := false;
  v_names text[] := array[
    'r1', 'r1_tie', 'r_ai_pass', 'r_ai_fail', 'r_pending_ai', 'r_pending_judge', 'r_one_sub', 'r_one_sub_fail',
    'q_agree', 'q_one_pick', 'q_mismatch', 'q_no_picks', 'q_min_fail'
  ];
  v_actual jsonb;
  v_expected jsonb;
  v_diff text;
begin
  insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  values
    (v_a, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'resolve-smoke-a@example.invalid', '{"full_name":"스모크A"}'::jsonb, now(), now()),
    (v_b, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'resolve-smoke-b@example.invalid', '{"full_name":"스모크B"}'::jsonb, now(), now()),
    (v_c, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'resolve-smoke-c@example.invalid', '{"full_name":"스모크C"}'::jsonb, now(), now()),
    (v_d, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'resolve-smoke-d@example.invalid', '{"full_name":"스모크D"}'::jsonb, now(), now());

  -- 하한에 걸리지 않게 시작 점수를 넉넉히 준다(B는 여러 번 진다).
  update public.player_stats set score = 10 where user_id in (v_a, v_c, v_d);
  update public.player_stats set score = 30 where user_id = v_b;

  -- 판정 창이 열린 대결들(사진 마감 2시간 전, 창은 1시간 전에 열림).
  for v_case in
    select n as name, case when n like 'q\_%' then 'quality' else 'speed' end as type
    from unnest(v_names) n
  loop
    insert into public.battles (min_criteria, superiority_criteria, type, status, title, creator_id, opponent_id,
                                duration_minutes, started_at, deadline_at, judging_opened_at, judge_deadline_at)
    values ('["상판이 보인다"]'::jsonb,
            case when v_case.type = 'quality' then '["먼지가 없다"]'::jsonb end,
            v_case.type, 'judging', 'resolve 스모크 ' || v_case.name, v_a, v_b,
            1440, now() - interval '1 day', now() - interval '2 hours',
            now() - interval '1 hour', now() + interval '23 hours')
    returning id into v_id;

    insert into public.battle_participants (battle_id, user_id) values (v_id, v_b);
    v_ids := v_ids || jsonb_build_object(v_case.name, v_id);
  end loop;

  -- 제출(사람이 승인했으면 opponent, 자동 승인이면 auto, AI가 정했으면 ai, 미결이면 null).
  insert into public.battle_submissions (battle_id, user_id, object_path, captured_at, submitted_at, meets_criteria, verdict_source)
  select (v_ids ->> s.name)::uuid,
         case s.who when 'A' then v_a else v_b end,
         'smoke/' || s.who || '.jpg',
         now() - make_interval(hours => s.hours_ago),
         now() - make_interval(hours => s.hours_ago),
         s.meets, s.src
  from (values
    ('r1', 'A', 5, true, 'opponent'), ('r1', 'B', 4, true, 'opponent'),
    ('r_ai_pass', 'A', 4, true, 'opponent'), ('r_ai_pass', 'B', 5, true, 'ai'),
    ('r_ai_fail', 'A', 4, true, 'opponent'), ('r_ai_fail', 'B', 5, false, 'ai'),
    ('r_pending_ai', 'A', 4, true, 'opponent'), ('r_pending_ai', 'B', 5, null, null),
    ('r_pending_judge', 'A', 4, true, 'opponent'), ('r_pending_judge', 'B', 5, null, null),
    ('r_one_sub', 'A', 4, true, 'opponent'),
    ('r_one_sub_fail', 'A', 4, false, 'ai'),
    ('q_agree', 'A', 4, true, 'opponent'), ('q_agree', 'B', 5, true, 'opponent'),
    ('q_one_pick', 'A', 4, true, 'auto'), ('q_one_pick', 'B', 5, true, 'opponent'),
    ('q_mismatch', 'A', 4, true, 'opponent'), ('q_mismatch', 'B', 5, true, 'opponent'),
    ('q_no_picks', 'A', 4, true, 'auto'), ('q_no_picks', 'B', 5, true, 'auto'),
    ('q_min_fail', 'A', 4, true, 'opponent'), ('q_min_fail', 'B', 5, false, 'ai')
  ) as s(name, who, hours_ago, meets, src);

  -- r1_tie: 같은 시각. B 행을 먼저 넣어 id가 작다.
  insert into public.battle_submissions (battle_id, user_id, object_path, captured_at, submitted_at, meets_criteria, verdict_source)
  values ((v_ids ->> 'r1_tie')::uuid, v_b, 'smoke/b.jpg', now() - interval '3 hours', timestamptz '2026-09-15 09:00:00+09', true, 'opponent');
  insert into public.battle_submissions (battle_id, user_id, object_path, captured_at, submitted_at, meets_criteria, verdict_source)
  values ((v_ids ->> 'r1_tie')::uuid, v_a, 'smoke/a.jpg', now() - interval '3 hours', timestamptz '2026-09-15 09:00:00+09', true, 'opponent');

  -- 판정. judge가 A면 B의 제출에 대한 판정이다. pick은 더 잘했다고 고른 사람.
  insert into public.battle_judgments (battle_id, judge_id, min_verdict, superior_id, auto)
  select (v_ids ->> j.name)::uuid,
         case j.judge when 'A' then v_a else v_b end,
         j.verdict,
         case j.pick when 'A' then v_a when 'B' then v_b end,
         j.auto
  from (values
    ('r1', 'A', 'approve', null, false), ('r1', 'B', 'approve', null, false),
    ('r1_tie', 'A', 'approve', null, false), ('r1_tie', 'B', 'approve', null, false),
    ('r_ai_pass', 'A', 'reject', null, false), ('r_ai_pass', 'B', 'approve', null, false),
    ('r_ai_fail', 'A', 'reject', null, false), ('r_ai_fail', 'B', 'approve', null, false),
    ('r_pending_ai', 'A', 'reject', null, false), ('r_pending_ai', 'B', 'approve', null, false),
    ('r_pending_judge', 'B', 'approve', null, false),
    ('r_one_sub', 'B', 'approve', null, false),
    ('r_one_sub_fail', 'B', 'reject', null, false),
    ('q_agree', 'A', 'approve', 'A', false), ('q_agree', 'B', 'approve', 'A', false),
    ('q_one_pick', 'A', 'approve', 'A', false), ('q_one_pick', 'B', 'approve', null, true),
    ('q_mismatch', 'A', 'approve', 'A', false), ('q_mismatch', 'B', 'approve', 'B', false),
    ('q_no_picks', 'A', 'approve', null, true), ('q_no_picks', 'B', 'approve', null, true),
    ('q_min_fail', 'A', 'reject', 'A', false), ('q_min_fail', 'B', 'approve', 'B', false)
  ) as j(name, judge, verdict, pick, auto);

  foreach v_name in array v_names loop
    if v_name = 'r1' then
      v_r1_return := public.resolve_battle((v_ids ->> 'r1')::uuid);
    else
      perform public.resolve_battle((v_ids ->> v_name)::uuid);
    end if;
  end loop;

  -- 종결된 대결에 다시 불러도 아무것도 바뀌지 않아야 한다.
  v_r1_again := public.resolve_battle((v_ids ->> 'r1')::uuid);

  -- 제출 창인 대결은 resolve_battle이 건드리지 않는다(정산은 settle_expired_battles 몫).
  insert into public.battles (min_criteria, superiority_criteria, type, status, title, creator_id, opponent_id, duration_minutes, started_at, deadline_at)
  values ('["상판이 보인다"]'::jsonb, null, 'speed', 'active', '제출 창', v_a, v_b, 1440, now(), now() - interval '1 minute')
  returning id into v_still_active;
  insert into public.battle_participants (battle_id, user_id) values (v_still_active, v_b);
  v_still_active_return := public.resolve_battle(v_still_active);

  -- 무효: C vs D. 하나는 오늘 매칭(판정 창), 하나는 어제 매칭(제출 창).
  insert into public.battles (min_criteria, superiority_criteria, type, status, title, creator_id, opponent_id,
                              duration_minutes, started_at, deadline_at, judging_opened_at, judge_deadline_at)
  values ('["상판이 보인다"]'::jsonb, '["먼지가 없다"]'::jsonb, 'quality', 'judging', 'void 오늘', v_c, v_d,
          4320, now(), now() + interval '3 days', now(), now() + interval '24 hours')
  returning id into v_v_today;
  insert into public.battle_participants (battle_id, user_id) values (v_v_today, v_d);
  insert into public.daily_battle_slots (user_id, kst_date, battle_id)
  values (v_c, v_today, v_v_today), (v_d, v_today, v_v_today);

  insert into public.battles (min_criteria, superiority_criteria, type, status, title, creator_id, opponent_id, duration_minutes, started_at, deadline_at)
  values ('["상판이 보인다"]'::jsonb, '["먼지가 없다"]'::jsonb, 'quality', 'active', 'void 어제', v_c, v_d, 4320, now() - interval '1 day', now() + interval '2 days')
  returning id into v_v_yday;
  insert into public.battle_participants (battle_id, user_id) values (v_v_yday, v_d);
  insert into public.daily_battle_slots (user_id, kst_date, battle_id)
  values (v_c, v_today - 1, v_v_yday), (v_d, v_today - 1, v_v_yday);

  perform public.void_battle(v_v_today);
  perform public.void_battle(v_v_yday);

  begin
    perform public.void_battle((v_ids ->> 'r1')::uuid);
  exception when others then
    v_void_finished_rejected := true;
  end;

  select jsonb_object_agg(
           l.name,
           b.status
             || '/' || coalesce(case b.winner_id when v_a then 'A' when v_b then 'B' when v_c then 'C' when v_d then 'D' end, '-')
             || '/' || coalesce(pc.outcome, '-')
             || '/' || coalesce(po.outcome, '-')
         )
  into v_actual
  from (
    select (v_ids ->> n)::uuid as id, n as name from unnest(v_names) n
    union all select v_still_active, 'still_active'
    union all select v_v_today, 'v_today'
    union all select v_v_yday, 'v_yday'
  ) as l
  join public.battles b on b.id = l.id
  left join public.battle_participants pc on pc.battle_id = b.id and pc.user_id = b.creator_id
  left join public.battle_participants po on po.battle_id = b.id and po.user_id = b.opponent_id;

  v_actual := v_actual || jsonb_build_object(
    'r1_return', v_r1_return,
    'r1_again', v_r1_again,
    'still_active_return', v_still_active_return,
    'r1_delta', (select string_agg(coalesce(score_delta_applied::text, '-'), '/' order by user_id = v_b)
                 from public.battle_participants where battle_id = (v_ids ->> 'r1')::uuid),
    'a_stats', (select concat_ws('/', score, wins, losses, draws) from public.player_stats where user_id = v_a),
    'b_stats', (select concat_ws('/', score, wins, losses, draws) from public.player_stats where user_id = v_b),
    'c_stats', (select concat_ws('/', score, wins, losses, draws) from public.player_stats where user_id = v_c),
    'd_stats', (select concat_ws('/', score, wins, losses, draws) from public.player_stats where user_id = v_d),
    'slots_today_left', (select count(*) from public.daily_battle_slots where battle_id = v_v_today),
    'slots_yday_left', (select count(*) from public.daily_battle_slots where battle_id = v_v_yday),
    'void_finished_rejected', v_void_finished_rejected,
    'disputed_count', (select count(*) from public.battles
                       where status = 'disputed' and creator_id in (v_a, v_c))
  );

  -- A: 10 +3(r1) -1(r1_tie) -1(r_ai_pass) +3(r_ai_fail) +3(r_one_sub) -1(r_one_sub_fail)
  --       +3(q_agree) +3(q_one_pick) -1(q_no_picks) +3(q_min_fail) = 24, 승6 패2 무2
  -- B: 30 -1 +3 +3 -3 -3 -1 -3 -3 -1 -3 = 18, 승2 패6 무2
  v_expected := jsonb_build_object(
    'r1', 'finished/A/win/completed_loss',
    'r1_tie', 'finished/B/completed_loss/win',
    'r_ai_pass', 'finished/B/completed_loss/win',
    'r_ai_fail', 'finished/A/win/loss',
    'r_pending_ai', 'judging/-/-/-',
    'r_pending_judge', 'judging/-/-/-',
    'r_one_sub', 'finished/A/win/loss',
    'r_one_sub_fail', 'draw/-/draw/draw',
    'q_agree', 'finished/A/win/loss',
    'q_one_pick', 'finished/A/win/loss',
    'q_mismatch', 'judging/-/-/-',
    'q_no_picks', 'draw/-/draw/draw',
    'q_min_fail', 'finished/A/win/loss',
    'still_active', 'active/-/-/-',
    'v_today', 'voided/-/-/-',
    'v_yday', 'voided/-/-/-',
    'r1_return', 'finished',
    'r1_again', 'finished',
    'still_active_return', 'active',
    'r1_delta', '3/-1',
    'a_stats', '24/6/2/2',
    'b_stats', '18/2/6/2',
    'c_stats', '10/0/0/0',
    'd_stats', '10/0/0/0',
    'slots_today_left', 0,
    'slots_yday_left', 2,
    'void_finished_rejected', true,
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
