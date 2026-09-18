-- forfeit_battle() 스모크 테스트 (ai-judge 규칙: 유형 무관 포기한 쪽 패배).
--
-- 로컬에 Docker가 없어 원격 DB에 직접 돌린다:
--   supabase db query --linked -f supabase/tests/forfeit_battle_smoke.sql
--
-- 임시 사용자 셋으로 포기를 실제로 호출하고, 마지막에 일부러 예외를 던져 전체를 롤백한다.
-- 결과:
--   SMOKE RESULT ok=true                    -> 통과
--   SMOKE RESULT ok=false FAILURES: ...     -> 어긋난 항목(기대값/실제값)
--
-- 확인하는 것
--   f_speed    A(0점)가 속도전 포기 -> finished/B, forfeited_by A, A forfeit(적용 0, 하한) / B win(+3)
--   f_quality  B가 판정 중 품질전 포기 -> finished/A (disputed 아님), A win(+3) / B forfeit(-3)
--   점수·카운터  A 3/1승/1패/0무, B 4/1승/1패/0무
--   거부       비참가자 포기, 이미 끝난 대결 포기, 비로그인 포기
do $$
declare
  v_a uuid := gen_random_uuid();
  v_b uuid := gen_random_uuid();
  v_c uuid := gen_random_uuid();
  v_f_speed uuid;
  v_f_quality uuid;
  v_f_other uuid;
  v_non_participant_rejected boolean := false;
  v_finished_rejected boolean := false;
  v_anon_rejected boolean := false;
  v_actual jsonb;
  v_expected jsonb;
  v_diff text;
begin
  insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  values
    (v_a, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'forfeit-smoke-a@example.invalid', '{"full_name":"스모크A"}'::jsonb, now(), now()),
    (v_b, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'forfeit-smoke-b@example.invalid', '{"full_name":"스모크B"}'::jsonb, now(), now()),
    (v_c, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'forfeit-smoke-c@example.invalid', '{"full_name":"스모크C"}'::jsonb, now(), now());

  -- A는 0점(하한 확인), B는 4점.
  update public.player_stats set score = 4 where user_id = v_b;

  insert into public.battles (min_criteria, superiority_criteria, type, status, title, creator_id, opponent_id, duration_minutes, started_at, deadline_at)
  values ('["상판이 보인다"]'::jsonb, null, 'speed', 'active', '속도전 포기', v_a, v_b, 4320, now(), now() + interval '3 days')
  returning id into v_f_speed;

  insert into public.battles (min_criteria, superiority_criteria, type, status, title, creator_id, opponent_id, duration_minutes, started_at, deadline_at)
  values ('["상판이 보인다"]'::jsonb, '["먼지가 없다"]'::jsonb, 'quality', 'judging', '품질전 포기', v_a, v_b, 4320, now(), now() + interval '3 days')
  returning id into v_f_quality;

  insert into public.battles (min_criteria, superiority_criteria, type, status, title, creator_id, opponent_id, duration_minutes, started_at, deadline_at)
  values ('["상판이 보인다"]'::jsonb, null, 'speed', 'active', '남의 대결', v_a, v_b, 4320, now(), now() + interval '3 days')
  returning id into v_f_other;

  insert into public.battle_participants (battle_id, user_id)
  values (v_f_speed, v_b), (v_f_quality, v_b), (v_f_other, v_b);

  -- A로 위장해 속도전 포기.
  perform set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
  perform public.forfeit_battle(v_f_speed);

  -- 이미 끝난 대결은 다시 포기할 수 없다.
  begin
    perform public.forfeit_battle(v_f_speed);
  exception when others then
    v_finished_rejected := true;
  end;

  -- B로 위장해 판정 중 품질전 포기.
  perform set_config('request.jwt.claims', json_build_object('sub', v_b, 'role', 'authenticated')::text, true);
  perform public.forfeit_battle(v_f_quality);

  -- C는 참가자가 아니다.
  perform set_config('request.jwt.claims', json_build_object('sub', v_c, 'role', 'authenticated')::text, true);
  begin
    perform public.forfeit_battle(v_f_other);
  exception when others then
    v_non_participant_rejected := true;
  end;

  -- 비로그인.
  perform set_config('request.jwt.claims', '', true);
  begin
    perform public.forfeit_battle(v_f_other);
  exception when others then
    v_anon_rejected := true;
  end;

  select jsonb_object_agg(
           l.name,
           b.status
             || '/' || coalesce(case b.winner_id when v_a then 'A' when v_b then 'B' end, '-')
             || '/' || coalesce(pa.outcome, '-')
             || '/' || coalesce(pb.outcome, '-')
             || '/' || coalesce(case b.forfeited_by when v_a then 'A' when v_b then 'B' end, '-')
             || '/' || coalesce(pa.score_delta_applied::text, '-')
             || '/' || coalesce(pb.score_delta_applied::text, '-')
         )
  into v_actual
  from unnest(array[v_f_speed, v_f_quality, v_f_other], array['f_speed', 'f_quality', 'f_other']) as l(id, name)
  join public.battles b on b.id = l.id
  left join public.battle_participants pa on pa.battle_id = b.id and pa.user_id = v_a
  left join public.battle_participants pb on pb.battle_id = b.id and pb.user_id = v_b;

  v_actual := v_actual || jsonb_build_object(
    'a_stats', (select concat_ws('/', score, wins, losses, draws) from public.player_stats where user_id = v_a),
    'b_stats', (select concat_ws('/', score, wins, losses, draws) from public.player_stats where user_id = v_b),
    'non_participant_rejected', v_non_participant_rejected,
    'finished_rejected', v_finished_rejected,
    'anon_rejected', v_anon_rejected
  );

  -- 표기: status/winner/A outcome/B outcome/forfeited_by/A 적용 점수/B 적용 점수
  v_expected := jsonb_build_object(
    'f_speed', 'finished/B/forfeit/win/A/0/3',
    'f_quality', 'finished/A/win/forfeit/B/3/-3',
    'f_other', 'active/-/-/-/-/-/-',
    'a_stats', '3/1/1/0',
    'b_stats', '4/1/1/0',
    'non_participant_rejected', true,
    'finished_rejected', true,
    'anon_rejected', true
  );

  select coalesce(string_agg(format('%s expected=%s actual=%s', e.key, e.value, coalesce(a.value::text, 'null')), '; '), '')
  into v_diff
  from jsonb_each(v_expected) e
  left join jsonb_each(v_actual) a on a.key = e.key
  where a.value is distinct from e.value;

  raise exception 'SMOKE RESULT ok=% %', v_diff = '',
    case when v_diff = '' then '' else ' FAILURES: ' || v_diff end;
end $$;
