-- settle_expired_battles() 스모크 테스트.
--
-- 로컬에 Docker가 없어 supabase start를 못 쓰므로 원격 DB에 직접 돌린다:
--   supabase db query --linked -f supabase/tests/settle_expired_battles_smoke.sql
--
-- 마감이 지난 대결 여섯 개와 아직 안 지난 대결 하나를 만들어 정리 함수를 돌려본다.
-- 마지막에 일부러 예외를 던져 트랜잭션 전체를 롤백하므로 실제 데이터는 남지 않는다.
-- 결과는 예외 메시지(SMOKE RESULT ...)로 돌아온다. 기대값:
--   s_both=finished/A     (양쪽 다 유효 -> 제출이 이른 A 승)
--   s_one=finished/A      (A만 제출 -> A 승, 상대가 판정 안 해도 마감이 판정을 대신한다)
--   s_disputed=draw/-     (A는 이의제기로 무효, B는 미제출 -> 유효한 완료 없음)
--   s_none=draw/-         (아무도 제출 안 함)
--   q_both=finished/-     (품질전은 승자를 두지 않는다)
--   q_one=draw/-          (한쪽만 해냄 -> 무승부)
--   fresh=active/-        (마감 전이므로 건드리지 않는다)
--   settled=6             (정리된 대결 수)
do $$
declare
  v_a uuid := gen_random_uuid();
  v_b uuid := gen_random_uuid();
  v_s_both uuid;
  v_s_one uuid;
  v_s_disputed uuid;
  v_s_none uuid;
  v_q_both uuid;
  v_q_one uuid;
  v_fresh uuid;
  v_settled integer;
  v_result text := '';

  function_result record;
begin
  insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  values
    (v_a, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'settle-smoke-a@example.invalid', '{"full_name":"스모크A"}'::jsonb, now(), now()),
    (v_b, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'settle-smoke-b@example.invalid', '{"full_name":"스모크B"}'::jsonb, now(), now());

  -- 대결 여섯 개는 마감이 지난 상태, 마지막 하나는 아직 남은 상태로 만든다.
  insert into public.battles (type, status, title, creator_id, opponent_id, duration_hours, started_at, deadline_at)
  values
    ('speed', 'judging', '둘 다 유효', v_a, v_b, 24, now() - interval '2 days', now() - interval '1 hour')
  returning id into v_s_both;

  insert into public.battles (type, status, title, creator_id, opponent_id, duration_hours, started_at, deadline_at)
  values ('speed', 'judging', 'A만 제출', v_a, v_b, 24, now() - interval '2 days', now() - interval '1 hour')
  returning id into v_s_one;

  insert into public.battles (type, status, title, creator_id, opponent_id, duration_hours, started_at, deadline_at)
  values ('speed', 'judging', 'A는 이의제기당함', v_a, v_b, 24, now() - interval '2 days', now() - interval '1 hour')
  returning id into v_s_disputed;

  insert into public.battles (type, status, title, creator_id, opponent_id, duration_hours, started_at, deadline_at)
  values ('speed', 'active', '아무도 제출 안 함', v_a, v_b, 24, now() - interval '2 days', now() - interval '1 hour')
  returning id into v_s_none;

  insert into public.battles (type, status, title, creator_id, opponent_id, duration_hours, started_at, deadline_at)
  values ('quality', 'judging', '품질전 둘 다', v_a, v_b, 24, now() - interval '2 days', now() - interval '1 hour')
  returning id into v_q_both;

  insert into public.battles (type, status, title, creator_id, opponent_id, duration_hours, started_at, deadline_at)
  values ('quality', 'judging', '품질전 한쪽만', v_a, v_b, 24, now() - interval '2 days', now() - interval '1 hour')
  returning id into v_q_one;

  insert into public.battles (type, status, title, creator_id, opponent_id, duration_hours, started_at, deadline_at)
  values ('speed', 'judging', '아직 마감 전', v_a, v_b, 24, now(), now() + interval '1 day')
  returning id into v_fresh;

  -- creator 참가자 행은 트리거가 만든다. opponent 행만 직접 넣는다.
  insert into public.battle_participants (battle_id, user_id)
  values (v_s_both, v_b), (v_s_one, v_b), (v_s_disputed, v_b), (v_s_none, v_b),
         (v_q_both, v_b), (v_q_one, v_b), (v_fresh, v_b);

  -- 양쪽 다 제출(판정 없음). A가 더 이르다.
  update public.battle_participants set evidence_type = 'text', evidence_content = 'A',
    evidence_submitted_at = now() - interval '10 hours'
  where battle_id = v_s_both and user_id = v_a;
  update public.battle_participants set evidence_type = 'text', evidence_content = 'B',
    evidence_submitted_at = now() - interval '5 hours'
  where battle_id = v_s_both and user_id = v_b;

  -- A만 제출, B는 판정도 제출도 안 함.
  update public.battle_participants set evidence_type = 'text', evidence_content = 'A',
    evidence_submitted_at = now() - interval '10 hours'
  where battle_id = v_s_one and user_id = v_a;

  -- A는 제출했지만 이의제기를 받아 무효. B는 미제출.
  update public.battle_participants set evidence_type = 'text', evidence_content = 'A',
    evidence_submitted_at = now() - interval '10 hours', decision = 'dispute', decision_at = now()
  where battle_id = v_s_disputed and user_id = v_a;

  -- 품질전: 둘 다 제출(판정 없음).
  update public.battle_participants set evidence_type = 'photo', evidence_content = 'p/a.jpg',
    evidence_submitted_at = now() - interval '10 hours'
  where battle_id = v_q_both and user_id = v_a;
  update public.battle_participants set evidence_type = 'photo', evidence_content = 'p/b.jpg',
    evidence_submitted_at = now() - interval '9 hours'
  where battle_id = v_q_both and user_id = v_b;

  -- 품질전: A만 제출.
  update public.battle_participants set evidence_type = 'photo', evidence_content = 'p/a.jpg',
    evidence_submitted_at = now() - interval '10 hours'
  where battle_id = v_q_one and user_id = v_a;

  v_settled := public.settle_expired_battles();

  for function_result in
    select
      b.id,
      b.status,
      case
        when b.winner_id = v_a then 'A'
        when b.winner_id = v_b then 'B'
        else '-'
      end as winner
    from public.battles b
    where b.id in (v_s_both, v_s_one, v_s_disputed, v_s_none, v_q_both, v_q_one, v_fresh)
  loop
    v_result := v_result || case function_result.id
      when v_s_both then ' s_both='
      when v_s_one then ' s_one='
      when v_s_disputed then ' s_disputed='
      when v_s_none then ' s_none='
      when v_q_both then ' q_both='
      when v_q_one then ' q_one='
      else ' fresh='
    end || function_result.status || '/' || function_result.winner;
  end loop;

  raise exception 'SMOKE RESULT%  settled=%', v_result, v_settled;
end;
$$;
