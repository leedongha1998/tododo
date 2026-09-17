-- 기기 알림 토큰·알림 발송 원장 스모크 테스트 (push-notification 1단계 기준).
--
-- 로컬에 Docker가 없어 원격 DB에 직접 돌린다:
--   supabase db query --linked -f supabase/tests/push_token_smoke.sql
--
-- 임시 사용자 A(토큰 있음) / B(토큰을 등록했다 해제) / U(탈퇴)를 만들어 실제로 RPC를 부르고,
-- 마지막에 일부러 예외를 던져 트랜잭션 전체를 롤백한다. 결과:
--   SMOKE RESULT ok=true                    -> 통과
--   SMOKE RESULT ok=false FAILURES: ...     -> 어긋난 항목(기대값/실제값)
--
-- 확인하는 것 (design.md "구현 단계 분할" 1단계 검증 목록)
--   토큰: 같은 토큰 재등록 시 1행 + last_seen_at 갱신, 다른 계정이 등록하면 소유자 교체,
--         내 토큰만 해제 가능(남의 토큰은 안 지워짐), 탈퇴 시 토큰·수신 원장 삭제
--   RLS:  남의 토큰 select 0행, 내 토큰은 보임, 원장은 authenticated에게 0행, 토큰 직접 insert 차단
--   권한: anon은 register_push_token을 부를 수 없다
--   원장: 같은 dedup_key로 두 번 넣어도 1행(첫 payload 유지), 잘못된 kind는 예외가 밖으로 나오지 않는다
--   발송: claim 한 번 뒤 두 번째 claim은 0행, 토큰 없는 수신자는 dropped,
--         마감이 지난 deadline_soon은 dropped, record_notification_result가 sent + 죽은 토큰 정리
--
-- 참고: 8번 항목(잘못된 kind)은 서버 로그에 WARNING 한 줄을 남긴다. 의도된 것이다.
do $$
declare
  v_a uuid := gen_random_uuid();
  v_b uuid := gen_random_uuid();
  v_u uuid := gen_random_uuid();
  v_battle uuid;
  v_battle_past uuid;
  v_battle_u uuid;
  v_tok_a text := 'smoke-fcm-token-a';
  v_tok_shared text := 'smoke-fcm-token-shared';
  v_tok_u text := 'smoke-fcm-token-u';
  v_upsert_rows integer;
  v_upsert_refreshed boolean;
  v_owner_swapped boolean;
  v_shared_rows integer;
  v_a_rows_after_swap integer;
  v_others_token_visible integer;
  v_own_token_visible integer;
  v_outbox_visible integer;
  v_token_insert text;
  v_anon_denied text;
  v_unregister_other integer;
  v_unregister_self integer;
  v_dedup_rows integer;
  v_dedup_payload text;
  v_bad_kind text;
  v_bad_kind_rows integer;
  v_claim jsonb;
  v_claim2 jsonb;
  v_claim_id bigint;
  v_u_tokens_before integer;
  v_u_outbox_before integer;
  v_actual jsonb;
  v_expected jsonb;
  v_diff text;
begin
  insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  values
    (v_a, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'push-smoke-a@example.invalid', '{"full_name":"스모크A"}'::jsonb, now(), now()),
    (v_b, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'push-smoke-b@example.invalid', '{"full_name":"스모크B"}'::jsonb, now(), now()),
    (v_u, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'push-smoke-u@example.invalid', '{"full_name":"스모크U"}'::jsonb, now(), now());

  -- 원장 행은 battle_id가 필수다. 한 사람당 pending 모집은 1개라 전부 active로 만든다.
  insert into public.battles (min_criteria, superiority_criteria, type, status, title,
                              creator_id, opponent_id, duration_hours, started_at, deadline_at)
  values ('["상판이 보인다"]'::jsonb, null, 'speed', 'active', '알림 원장 대결',
          v_a, v_b, 72, now(), now() + interval '3 days')
  returning id into v_battle;
  insert into public.battle_participants (battle_id, user_id) values (v_battle, v_b);

  -- 마감이 이미 지난 대결. deadline_soon이 폐기되는지 보는 데 쓴다.
  insert into public.battles (min_criteria, superiority_criteria, type, status, title,
                              creator_id, opponent_id, duration_hours, started_at, deadline_at)
  values ('["상판이 보인다"]'::jsonb, null, 'speed', 'active', '마감 지난 대결',
          v_a, v_b, 24, now() - interval '2 days', now() - interval '1 hour')
  returning id into v_battle_past;
  insert into public.battle_participants (battle_id, user_id) values (v_battle_past, v_b);

  -- U가 만든 진행 중 대결. 탈퇴하면 취소된다(기존 delete_account 동작이 남아 있는지 확인용).
  insert into public.battles (min_criteria, superiority_criteria, type, status, title,
                              creator_id, opponent_id, duration_hours, started_at, deadline_at)
  values ('["상판이 보인다"]'::jsonb, null, 'speed', 'active', '탈퇴 대결',
          v_u, v_a, 24, now(), now() + interval '1 day')
  returning id into v_battle_u;
  insert into public.battle_participants (battle_id, user_id) values (v_battle_u, v_a);

  -- 1. 같은 토큰을 두 번 등록해도 1행이고 last_seen_at만 갱신된다.
  perform set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
  perform public.register_push_token(v_tok_a);
  update public.device_push_tokens
  set created_at = now() - interval '1 hour', last_seen_at = now() - interval '1 hour'
  where token = v_tok_a;
  perform public.register_push_token(v_tok_a);

  v_upsert_rows := (select count(*) from public.device_push_tokens where token = v_tok_a);
  v_upsert_refreshed := (select last_seen_at > created_at from public.device_push_tokens where token = v_tok_a);

  -- 2. 같은 기기를 B가 쓰면 소유자가 교체된다(행이 늘지 않는다).
  perform public.register_push_token(v_tok_shared);
  perform set_config('request.jwt.claims', json_build_object('sub', v_b, 'role', 'authenticated')::text, true);
  perform public.register_push_token(v_tok_shared);

  v_owner_swapped := (select user_id = v_b from public.device_push_tokens where token = v_tok_shared);
  v_shared_rows := (select count(*) from public.device_push_tokens where token = v_tok_shared);
  v_a_rows_after_swap := (select count(*) from public.device_push_tokens where user_id = v_a);

  -- 3. RLS: B로 보면 내 토큰만 보이고 남의 토큰과 원장은 보이지 않는다.
  --    do 블록은 postgres(소유자)로 돌아 정책을 건너뛰므로 롤을 바꿔야 한다.
  begin
    execute 'set local role authenticated';
    v_others_token_visible := (select count(*) from public.device_push_tokens where token = v_tok_a);
    v_own_token_visible := (select count(*) from public.device_push_tokens where token = v_tok_shared);
    v_outbox_visible := (select count(*) from public.notification_outbox);
    execute 'reset role';
  exception when others then
    execute 'reset role';
    v_others_token_visible := -1;
    v_own_token_visible := -1;
    v_outbox_visible := -1;
  end;
  execute 'reset role';

  -- 4. 쓰기 정책이 없으므로 토큰 직접 insert는 막힌다(RLS 위반은 insufficient_privilege).
  begin
    execute 'set local role authenticated';
    insert into public.device_push_tokens (token, user_id) values ('smoke-direct-insert', v_b);
    execute 'reset role';
    v_token_insert := '성공(정책이 남아 있음)';
  exception when insufficient_privilege then
    v_token_insert := 'RLS 차단';
  when others then
    execute 'reset role';
    v_token_insert := '다른 오류: ' || sqlerrm;
  end;
  execute 'reset role';

  -- 5. anon 롤에는 실행 권한이 없다.
  begin
    execute 'set local role anon';
    perform public.register_push_token('smoke-anon-token');
    execute 'reset role';
    v_anon_denied := '성공(권한이 남아 있음)';
  exception when insufficient_privilege then
    v_anon_denied := '권한 없음';
  when others then
    execute 'reset role';
    v_anon_denied := '다른 오류: ' || sqlerrm;
  end;
  execute 'reset role';

  -- 6. 해제는 내 행만. B가 A의 토큰을 지우려 해도 남고, 자기 토큰은 지워진다.
  perform public.unregister_push_token(v_tok_a);
  v_unregister_other := (select count(*) from public.device_push_tokens where token = v_tok_a);
  perform public.unregister_push_token(v_tok_shared);
  v_unregister_self := (select count(*) from public.device_push_tokens where token = v_tok_shared);

  -- 7. 같은 dedup_key로 두 번 넣어도 1행이고 첫 payload가 남는다.
  perform public.enqueue_notification(v_a, 'matched', v_battle, 'matched:' || v_battle,
                                      jsonb_build_object('title', '알림 원장 대결'));
  perform public.enqueue_notification(v_a, 'matched', v_battle, 'matched:' || v_battle,
                                      jsonb_build_object('title', '두 번째'));
  v_dedup_rows := (select count(*) from public.notification_outbox
                   where recipient_id = v_a and dedup_key = 'matched:' || v_battle);
  v_dedup_payload := (select payload ->> 'title' from public.notification_outbox
                      where recipient_id = v_a and dedup_key = 'matched:' || v_battle);

  -- 8. 원장 insert가 실패해도(잘못된 kind) 예외가 호출자에게 올라오지 않는다 = 판정을 되돌리지 않는다.
  begin
    perform public.enqueue_notification(v_a, 'nope', v_battle, 'bad:' || v_battle, '{}'::jsonb);
    v_bad_kind := '예외 없음';
  exception when others then
    v_bad_kind := '예외 발생: ' || sqlerrm;
  end;
  v_bad_kind_rows := (select count(*) from public.notification_outbox where dedup_key = 'bad:' || v_battle);

  -- 9. 토큰이 없는 수신자(B)와 마감이 지난 임박 알림은 발송 대상이 아니다.
  perform public.enqueue_notification(v_b, 'quality_submitted', v_battle, 'qsub:' || v_battle,
                                      jsonb_build_object('title', '알림 원장 대결'));
  perform public.enqueue_notification(v_a, 'deadline_soon', v_battle_past, 'deadline:' || v_battle_past,
                                      jsonb_build_object('title', '마감 지난 대결'));

  -- A는 6번에서 토큰을 해제했으므로 다시 등록해야 claim 대상이 된다.
  perform set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
  perform public.register_push_token(v_tok_a);

  v_claim := public.claim_notifications(50);
  v_claim2 := public.claim_notifications(50);
  v_claim_id := (v_claim -> 0 ->> 'id')::bigint;

  -- 10. 발송 결과 기록 + 죽은 토큰 정리.
  perform public.record_notification_result(v_claim_id, 'sent', null, array[v_tok_a]);

  -- 11. 탈퇴. 파괴적 호출이므로 비교에 쓸 이전 상태를 먼저 변수에 잡아 둔다.
  perform set_config('request.jwt.claims', json_build_object('sub', v_u, 'role', 'authenticated')::text, true);
  perform public.register_push_token(v_tok_u);
  perform public.enqueue_notification(v_u, 'finished', v_battle_u, 'finished:' || v_battle_u,
                                      jsonb_build_object('title', '탈퇴 대결'));
  v_u_tokens_before := (select count(*) from public.device_push_tokens where user_id = v_u);
  v_u_outbox_before := (select count(*) from public.notification_outbox where recipient_id = v_u);

  perform public.delete_account();

  v_actual := jsonb_build_object(
    'upsert_rows', v_upsert_rows,
    'upsert_refreshed', v_upsert_refreshed,
    'owner_swapped', v_owner_swapped,
    'shared_rows', v_shared_rows,
    'a_rows_after_swap', v_a_rows_after_swap,
    'others_token_visible', v_others_token_visible,
    'own_token_visible', v_own_token_visible,
    'outbox_visible', v_outbox_visible,
    'token_insert', v_token_insert,
    'anon_denied', v_anon_denied,
    'unregister_other', v_unregister_other,
    'unregister_self', v_unregister_self,
    'dedup_rows', v_dedup_rows,
    'dedup_payload', v_dedup_payload,
    'bad_kind', v_bad_kind,
    'bad_kind_rows', v_bad_kind_rows,
    'claim_count', jsonb_array_length(v_claim),
    'claim_kind', v_claim -> 0 ->> 'kind',
    'claim_tokens', jsonb_array_length(v_claim -> 0 -> 'tokens'),
    'claim_attempts', (select attempts from public.notification_outbox where id = v_claim_id),
    'second_claim_count', jsonb_array_length(v_claim2),
    'b_row_status', (select status from public.notification_outbox
                     where recipient_id = v_b and dedup_key = 'qsub:' || v_battle),
    'deadline_row_status', (select status from public.notification_outbox
                            where recipient_id = v_a and dedup_key = 'deadline:' || v_battle_past),
    'sent_status', (select status from public.notification_outbox where id = v_claim_id),
    'sent_at_set', (select sent_at is not null from public.notification_outbox where id = v_claim_id),
    'dead_token_rows', (select count(*) from public.device_push_tokens where token = v_tok_a),
    'u_tokens_before', v_u_tokens_before,
    'u_outbox_before', v_u_outbox_before,
    'u_tokens_after', (select count(*) from public.device_push_tokens where user_id = v_u),
    'u_outbox_after', (select count(*) from public.notification_outbox where recipient_id = v_u),
    'a_outbox_kept', (select count(*) from public.notification_outbox where recipient_id = v_a),
    'u_battle', (select status from public.battles where id = v_battle_u),
    'u_profile', (select display_name || '/' || (deleted_at is not null)::text
                  from public.profiles where id = v_u),
    'u_auth_exists', (select exists (select 1 from auth.users where id = v_u))
  );

  v_expected := jsonb_build_object(
    'upsert_rows', 1,
    'upsert_refreshed', true,
    'owner_swapped', true,
    'shared_rows', 1,
    -- A는 v_tok_a만 남는다(공용 토큰은 B가 가져갔다).
    'a_rows_after_swap', 1,
    'others_token_visible', 0,
    'own_token_visible', 1,
    -- 정책이 하나도 없으므로 내가 받을 알림조차 보이지 않는다.
    'outbox_visible', 0,
    'token_insert', 'RLS 차단',
    'anon_denied', '권한 없음',
    'unregister_other', 1,
    'unregister_self', 0,
    'dedup_rows', 1,
    'dedup_payload', '알림 원장 대결',
    'bad_kind', '예외 없음',
    'bad_kind_rows', 0,
    -- 발송 대상은 A의 matched 1건뿐이다(B는 토큰 없음, deadline_soon은 마감 지남).
    'claim_count', 1,
    'claim_kind', 'matched',
    'claim_tokens', 1,
    'claim_attempts', 1,
    'second_claim_count', 0,
    'b_row_status', 'dropped',
    'deadline_row_status', 'dropped',
    'sent_status', 'sent',
    'sent_at_set', true,
    'dead_token_rows', 0,
    'u_tokens_before', 1,
    'u_outbox_before', 1,
    'u_tokens_after', 0,
    'u_outbox_after', 0,
    -- A가 받을 2행(matched=sent, deadline_soon=dropped)은 남의 탈퇴로 지워지지 않는다.
    'a_outbox_kept', 2,
    'u_battle', 'cancelled',
    'u_profile', '탈퇴한 사용자/true',
    'u_auth_exists', false
  );

  select coalesce(string_agg(format('%s expected=%s actual=%s', e.key, e.value, coalesce(a.value::text, 'null')), '; '), '')
  into v_diff
  from jsonb_each(v_expected) e
  left join jsonb_each(v_actual) a on a.key = e.key
  where a.value is distinct from e.value;

  raise exception 'SMOKE RESULT ok=% %', v_diff = '',
    case when v_diff = '' then '' else ' FAILURES: ' || v_diff end;
end $$;
