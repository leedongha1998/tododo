-- 대결 사건 -> 알림 원장 적재 스모크 테스트 (push-notification 3단계 기준).
--
-- 로컬에 Docker가 없어 원격 DB에 직접 돌린다:
--   supabase db query --linked -f supabase/tests/notification_events_smoke.sql
--
-- 임시 사용자 A·B(주 대결 쌍)와 D(탈퇴자)·E(D의 상대)를 만들어 실제 함수를 부르고, 마지막에
-- 일부러 예외를 던져 트랜잭션 전체를 롤백한다. 결과:
--   SMOKE RESULT ok=true                    -> 통과
--   SMOKE RESULT ok=false FAILURES: ...     -> 어긋난 항목(기대값/실제값)
--
-- 확인하는 것 (plan.md 3단계 검증 목록 = design "mutual-judge 반영"의 사건 지점 표)
--   N1  매칭: join_battle이 생성자에게만 1행, payload에 마감이 담긴다
--   N3  제출: 상대에게 1행, 교체 제출로 두 번 생기지 않음(dedup), 판정 창을 여는 제출에는 없음
--   N4' 판정 차례: 창이 열릴 때 판정할 증거가 있는 쪽에만(한쪽만 제출한 채 마감되면 1행)
--   N2  종결: 상호 판정·포기·마감 정산 세 경로 모두에서 적재, 포기한 본인 제외, 점수 변화 동봉
--   N2' 무효: 양쪽 2행
--   N5  탈퇴 취소: 남은 상대에게 1행, 상대 없는 pending 모집에는 0행
--   공통: payload에 reason·object_path·display_name·winner_id가 없다
--   장치: enqueue가 실패해도(일부러 제약 위반) 종결과 점수가 커밋된다
--   폐기: 창이 닫힌 뒤 남은 judge_turn은 claim_notifications가 dropped로 내린다
--
-- 참고: "enqueue 실패" 항목은 서버 로그에 WARNING 두 줄을 남긴다. 의도된 것이다.
do $$
declare
  v_a uuid := gen_random_uuid();
  v_b uuid := gen_random_uuid();
  v_d uuid := gen_random_uuid();
  v_e uuid := gen_random_uuid();

  v_bt1 uuid := gen_random_uuid();   -- 속도전: 매칭 -> 제출 -> 교체 -> 양쪽 제출 -> 종결
  v_bt2 uuid := gen_random_uuid();   -- 품질전: 포기
  v_bt3 uuid := gen_random_uuid();   -- 속도전: 마감 정산 무승부
  v_bt4 uuid := gen_random_uuid();   -- 품질전: 무효
  v_bt5 uuid := gen_random_uuid();   -- 속도전: 한쪽만 제출한 채 마감
  v_bt6 uuid := gen_random_uuid();   -- 속도전: enqueue가 실패해도 종결은 커밋
  v_bt7 uuid := gen_random_uuid();   -- D·E 매칭(탈퇴로 취소)
  v_bt8 uuid := gen_random_uuid();   -- D의 상대 없는 모집(알릴 사람 없음)

  v_n1_rows integer;
  v_n1_to_creator integer;
  v_n1_has_deadline boolean;
  v_n3_after_first integer;
  v_n3_after_replace integer;
  v_n3_to_a integer;
  v_judge_rows integer;
  v_judge_to_a integer;
  v_judge_to_b integer;
  v_judge_has_deadline boolean;
  v_bt1_finished integer;
  v_bt2_finished integer;
  v_bt2_to_b integer;
  v_bt3_finished integer;
  v_bt3_delta integer;
  v_bt4_voided integer;
  v_bt5_judge integer;
  v_bt5_to_b integer;
  v_bt6_status text;
  v_bt6_rows integer;
  v_bt6_score integer;
  v_n5_rows integer;
  v_n5_to_e integer;
  v_n5_pending_rows integer;
  v_forbidden integer;
  v_judge_dropped text;
  v_claim jsonb;

  v_actual jsonb;
  v_expected jsonb;
  v_diff text;
begin
  insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  select u.id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
         u.email, jsonb_build_object('full_name', u.name), now(), now()
  from (values
    (v_a, 'notify-smoke-a@example.invalid', '스모크A'),
    (v_b, 'notify-smoke-b@example.invalid', '스모크B'),
    (v_d, 'notify-smoke-d@example.invalid', '스모크D'),
    (v_e, 'notify-smoke-e@example.invalid', '스모크E')
  ) as u(id, email, name);

  -- 점수 하한 0에 걸리면 score_delta가 0이 되어 검증이 흔들린다. 넉넉히 올려 둔다.
  update public.player_stats set score = 30 where user_id in (v_a, v_b, v_d, v_e);

  -- 제출·참가에 동의가 필요하다.
  perform set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
  perform public.give_ai_consent('2026-09-14');
  perform set_config('request.jwt.claims', json_build_object('sub', v_b, 'role', 'authenticated')::text, true);
  perform public.give_ai_consent('2026-09-14');

  -- 발송 임대 검증(마지막 항목)에 쓸 기기 토큰. 토큰이 없으면 claim이 "받을 기기 없음"으로
  -- 전부 dropped로 내려 판정 차례 폐기 조건을 가릴 수 없다.
  insert into public.device_push_tokens (token, user_id)
  values ('notify-smoke-token-a', v_a), ('notify-smoke-token-b', v_b);

  -- ---------------------------------------------------------------------
  -- BT1: 모집 -> 매칭(N1) -> 제출(N3) -> 교체 -> 양쪽 제출(N4') -> 종결(N2)
  -- ---------------------------------------------------------------------
  insert into public.battles (id, min_criteria, superiority_criteria, type, status, title,
                              creator_id, duration_minutes)
  values (v_bt1, '["운동화를 신고 밖에 있다"]'::jsonb, null, 'speed', 'pending', '아침 달리기',
          v_a, 4320);

  perform set_config('request.jwt.claims', json_build_object('sub', v_b, 'role', 'authenticated')::text, true);
  perform public.join_battle(v_bt1, 1);

  -- 1. N1은 생성자에게만, 마감을 담아서.
  select count(*) into v_n1_rows from public.notification_outbox where battle_id = v_bt1;
  select count(*) into v_n1_to_creator
  from public.notification_outbox
  where battle_id = v_bt1 and kind = 'matched' and recipient_id = v_a;
  select (payload ? 'deadline_at') and payload->>'deadline_at' is not null into v_n1_has_deadline
  from public.notification_outbox where battle_id = v_bt1 and kind = 'matched';

  -- 2. N3: A가 내면 B에게 1행. 교체해도 한 번만.
  perform public.accept_submission(v_a, v_bt1, v_bt1::text || '/' || v_a::text || '/1.jpg', now());
  select count(*) into v_n3_after_first
  from public.notification_outbox where battle_id = v_bt1 and kind = 'submitted' and recipient_id = v_b;

  perform public.accept_submission(v_a, v_bt1, v_bt1::text || '/' || v_a::text || '/2.jpg', now());
  select count(*) into v_n3_after_replace
  from public.notification_outbox where battle_id = v_bt1 and kind = 'submitted' and recipient_id = v_b;

  -- 3. B가 내면 판정 창이 열린다 -> N3는 보내지 않고 N4'를 양쪽에 보낸다.
  perform public.accept_submission(v_b, v_bt1, v_bt1::text || '/' || v_b::text || '/1.jpg', now());
  select count(*) into v_n3_to_a
  from public.notification_outbox where battle_id = v_bt1 and kind = 'submitted' and recipient_id = v_a;
  select count(*) into v_judge_rows
  from public.notification_outbox where battle_id = v_bt1 and kind = 'judge_turn';
  select count(*) into v_judge_to_a
  from public.notification_outbox where battle_id = v_bt1 and kind = 'judge_turn' and recipient_id = v_a;
  select count(*) into v_judge_to_b
  from public.notification_outbox where battle_id = v_bt1 and kind = 'judge_turn' and recipient_id = v_b;
  select bool_and(payload->>'judge_deadline_at' is not null) into v_judge_has_deadline
  from public.notification_outbox where battle_id = v_bt1 and kind = 'judge_turn';

  -- 4. N2(상호 판정으로 결론이 난 경로를 대신해 종결 지점을 직접 부른다): 양쪽 1행씩.
  perform public.finalize_battle(v_bt1, 'finished', v_a, 'win', 'completed_loss');
  select count(*) into v_bt1_finished
  from public.notification_outbox where battle_id = v_bt1 and kind = 'finished';

  -- ---------------------------------------------------------------------
  -- BT2: 포기 -> 포기한 본인에게는 보내지 않는다
  -- ---------------------------------------------------------------------
  insert into public.battles (id, min_criteria, superiority_criteria, type, status, title,
                              creator_id, opponent_id, duration_minutes, started_at, deadline_at)
  values (v_bt2, '["바닥이 보인다"]'::jsonb, '["먼지가 없다"]'::jsonb, 'quality', 'active', '방 청소하기',
          v_a, v_b, 4320, now(), now() + interval '3 days');
  insert into public.battle_participants (battle_id, user_id) values (v_bt2, v_b);

  perform set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
  perform public.forfeit_battle(v_bt2);

  select count(*) into v_bt2_finished
  from public.notification_outbox where battle_id = v_bt2 and kind = 'finished';
  select count(*) into v_bt2_to_b
  from public.notification_outbox where battle_id = v_bt2 and kind = 'finished' and recipient_id = v_b;

  -- ---------------------------------------------------------------------
  -- BT3: 마감 정산(아무도 제출하지 않음) -> 무승부, 양쪽에 점수 변화까지
  -- ---------------------------------------------------------------------
  insert into public.battles (id, min_criteria, superiority_criteria, type, status, title,
                              creator_id, opponent_id, duration_minutes, started_at, deadline_at)
  values (v_bt3, '["책상이 비어 있다"]'::jsonb, null, 'speed', 'active', '책상 정리하기',
          v_a, v_b, 1440, now() - interval '2 days', now() - interval '1 minute');
  insert into public.battle_participants (battle_id, user_id) values (v_bt3, v_b);

  perform public.settle_expired_battles();

  select count(*) into v_bt3_finished
  from public.notification_outbox where battle_id = v_bt3 and kind = 'finished';
  select (payload->>'score_delta')::integer into v_bt3_delta
  from public.notification_outbox
  where battle_id = v_bt3 and kind = 'finished' and recipient_id = v_a;

  -- ---------------------------------------------------------------------
  -- BT4: 무효 -> 양쪽 2행
  -- ---------------------------------------------------------------------
  insert into public.battles (id, min_criteria, superiority_criteria, type, status, title,
                              creator_id, opponent_id, duration_minutes, started_at, deadline_at,
                              judging_opened_at, judge_deadline_at)
  values (v_bt4, '["설거지가 끝났다"]'::jsonb, '["물기가 없다"]'::jsonb, 'quality', 'judging', '설거지하기',
          v_a, v_b, 1440, now() - interval '2 days', now() - interval '1 day',
          now() - interval '1 hour', now() + interval '23 hours');
  insert into public.battle_participants (battle_id, user_id) values (v_bt4, v_b);

  perform public.void_battle(v_bt4);
  select count(*) into v_bt4_voided
  from public.notification_outbox where battle_id = v_bt4 and kind = 'voided';

  -- ---------------------------------------------------------------------
  -- BT5: 속도전에서 한쪽만 제출한 채 마감 -> 판정할 사람은 제출하지 않은 쪽뿐
  -- ---------------------------------------------------------------------
  insert into public.battles (id, min_criteria, superiority_criteria, type, status, title,
                              creator_id, opponent_id, duration_minutes, started_at, deadline_at)
  values (v_bt5, '["물컵이 비었다"]'::jsonb, null, 'speed', 'active', '물 마시기',
          v_a, v_b, 1440, now() - interval '1 hour', now() + interval '1 hour');
  insert into public.battle_participants (battle_id, user_id) values (v_bt5, v_b);

  perform public.accept_submission(v_a, v_bt5, v_bt5::text || '/' || v_a::text || '/1.jpg', now());
  -- 제출을 받은 뒤 마감만 과거로 돌린다(제출 시각 검사를 피해 "한쪽만 낸 채 마감"을 만든다).
  update public.battles set deadline_at = now() - interval '1 minute' where id = v_bt5;
  perform public.settle_expired_battles();

  select count(*) into v_bt5_judge
  from public.notification_outbox where battle_id = v_bt5 and kind = 'judge_turn';
  select count(*) into v_bt5_to_b
  from public.notification_outbox where battle_id = v_bt5 and kind = 'judge_turn' and recipient_id = v_b;

  -- ---------------------------------------------------------------------
  -- BT6: enqueue가 실패해도 종결과 점수는 커밋된다(원칙 2의 핵심 장치)
  -- ---------------------------------------------------------------------
  -- 새로 들어오는 finished 행만 막는 제약을 잠깐 걸어 둔다(not valid라 기존 행은 검사하지 않는다).
  insert into public.battles (id, min_criteria, superiority_criteria, type, status, title,
                              creator_id, opponent_id, duration_minutes, started_at, deadline_at)
  values (v_bt6, '["이불이 개어져 있다"]'::jsonb, null, 'speed', 'active', '이불 개기',
          v_a, v_b, 1440, now() - interval '1 hour', now() + interval '1 hour');
  insert into public.battle_participants (battle_id, user_id) values (v_bt6, v_b);

  alter table public.notification_outbox
    add constraint notify_smoke_block_finished check (kind <> 'finished') not valid;

  perform public.finalize_battle(v_bt6, 'finished', v_b, 'loss', 'win');

  alter table public.notification_outbox drop constraint notify_smoke_block_finished;

  select status into v_bt6_status from public.battles where id = v_bt6;
  select count(*) into v_bt6_rows from public.notification_outbox where battle_id = v_bt6;
  select score_delta_applied into v_bt6_score
  from public.battle_participants where battle_id = v_bt6 and user_id = v_b;

  -- ---------------------------------------------------------------------
  -- BT7·BT8: 탈퇴로 취소 -> 남은 상대에게만, 슬롯 반환 사실과 함께
  -- ---------------------------------------------------------------------
  insert into public.battles (id, min_criteria, superiority_criteria, type, status, title,
                              creator_id, opponent_id, duration_minutes, started_at, deadline_at)
  values (v_bt7, '["우산을 들고 있다"]'::jsonb, null, 'speed', 'active', '우산 챙기기',
          v_d, v_e, 1440, now(), now() + interval '1 day');
  insert into public.battle_participants (battle_id, user_id) values (v_bt7, v_e);

  -- 상대가 없는 모집은 취소되지만 알릴 사람이 없다.
  insert into public.battles (id, min_criteria, superiority_criteria, type, status, title,
                              creator_id, duration_minutes)
  values (v_bt8, '["빨래가 널려 있다"]'::jsonb, null, 'speed', 'pending', '빨래 널기', v_d, 1440);

  perform set_config('request.jwt.claims', json_build_object('sub', v_d, 'role', 'authenticated')::text, true);
  perform public.delete_account();

  select count(*) into v_n5_rows
  from public.notification_outbox where kind = 'cancelled' and battle_id in (v_bt7, v_bt8);
  select count(*) into v_n5_to_e
  from public.notification_outbox where kind = 'cancelled' and battle_id = v_bt7 and recipient_id = v_e;
  select count(*) into v_n5_pending_rows
  from public.notification_outbox where battle_id = v_bt8;

  -- ---------------------------------------------------------------------
  -- 공통: 잠금화면에 나가면 안 되는 키가 payload에 없다
  -- ---------------------------------------------------------------------
  select count(*) into v_forbidden
  from public.notification_outbox
  where battle_id in (v_bt1, v_bt2, v_bt3, v_bt4, v_bt5, v_bt6, v_bt7, v_bt8)
    and payload ?| array['reason', 'object_path', 'display_name', 'winner_id', 'verdict_reason'];

  -- ---------------------------------------------------------------------
  -- 폐기: 창이 닫힌 뒤 남은 judge_turn은 보내지 않는다
  -- ---------------------------------------------------------------------
  -- BT1은 이미 finished라 "판정할 차례"를 보낼 이유가 사라졌다.
  v_claim := public.claim_notifications(100);
  select status into v_judge_dropped
  from public.notification_outbox
  where battle_id = v_bt1 and kind = 'judge_turn' and recipient_id = v_a;

  v_actual := jsonb_build_object(
    'n1_rows', v_n1_rows,
    'n1_to_creator', v_n1_to_creator,
    'n1_has_deadline', v_n1_has_deadline,
    'n3_after_first', v_n3_after_first,
    'n3_after_replace', v_n3_after_replace,
    'n3_to_a', v_n3_to_a,
    'judge_rows', v_judge_rows,
    'judge_to_a', v_judge_to_a,
    'judge_to_b', v_judge_to_b,
    'judge_has_deadline', v_judge_has_deadline,
    'bt1_finished', v_bt1_finished,
    'bt2_finished', v_bt2_finished,
    'bt2_to_b', v_bt2_to_b,
    'bt3_finished', v_bt3_finished,
    'bt3_delta', v_bt3_delta,
    'bt4_voided', v_bt4_voided,
    'bt5_judge', v_bt5_judge,
    'bt5_to_b', v_bt5_to_b,
    'bt6_status', v_bt6_status,
    'bt6_rows', v_bt6_rows,
    'bt6_score', v_bt6_score,
    'n5_rows', v_n5_rows,
    'n5_to_e', v_n5_to_e,
    'n5_pending_rows', v_n5_pending_rows,
    'forbidden', v_forbidden,
    'judge_dropped', v_judge_dropped
  );

  v_expected := jsonb_build_object(
    -- 매칭 직후에는 N1 한 행뿐이다(참가한 본인에게는 보내지 않는다).
    'n1_rows', 1,
    'n1_to_creator', 1,
    'n1_has_deadline', true,
    -- 제출 알림은 상대에게 한 번. 교체해도 늘지 않는다.
    'n3_after_first', 1,
    'n3_after_replace', 1,
    -- 판정 창을 여는 제출에는 제출 알림을 보내지 않는다(N4'가 그 사실까지 담는다).
    'n3_to_a', 0,
    'judge_rows', 2,
    'judge_to_a', 1,
    'judge_to_b', 1,
    'judge_has_deadline', true,
    'bt1_finished', 2,
    -- 포기한 본인(A)에게는 보내지 않는다.
    'bt2_finished', 1,
    'bt2_to_b', 1,
    'bt3_finished', 2,
    'bt3_delta', -1,
    'bt4_voided', 2,
    -- 한쪽만 제출한 채 마감되면 판정할 사람은 제출하지 않은 쪽(B)뿐이다.
    'bt5_judge', 1,
    'bt5_to_b', 1,
    -- 알림 적재가 실패해도 종결과 점수는 그대로 커밋된다.
    'bt6_status', 'finished',
    'bt6_rows', 0,
    'bt6_score', 3,
    -- 탈퇴: 남은 상대에게만, 오늘 슬롯이 돌아온다는 사실과 함께.
    'n5_rows', 1,
    'n5_to_e', 1,
    'n5_pending_rows', 0,
    'forbidden', 0,
    'judge_dropped', 'dropped'
  );

  select coalesce(string_agg(format('%s expected=%s actual=%s', e.key, e.value, coalesce(a.value::text, 'null')), '; '), '')
  into v_diff
  from jsonb_each(v_expected) e
  left join jsonb_each(v_actual) a on a.key = e.key
  where a.value is distinct from e.value;

  raise exception 'SMOKE RESULT ok=% %', v_diff = '',
    case when v_diff = '' then '' else ' FAILURES: ' || v_diff end;
end $$;
