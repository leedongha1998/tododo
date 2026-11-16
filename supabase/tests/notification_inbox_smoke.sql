-- 앱 안 알림함 읽기 경로 스모크 테스트 (notification-inbox 1단계 기준).
--
-- 로컬에 Docker가 없어 원격 DB에 직접 돌린다:
--   supabase db query --linked -f supabase/tests/notification_inbox_smoke.sql
--
-- 임시 사용자 A·B(원장 행 보유), C(행이 하나도 없는 신규), D(50건 상한 확인용 묶음),
-- F(탈퇴 확인용)를 만들어 실제 함수를 부르고, 마지막에 일부러 예외를 던져 트랜잭션 전체를
-- 롤백한다. 결과:
--   SMOKE RESULT ok=true                    -> 통과
--   SMOKE RESULT ok=false FAILURES: ...     -> 어긋난 항목(기대값/실제값)
--
-- 확인하는 것 (design.md 10.1)
--   격리   A의 목록에 B의 행이 없고 그 반대도 없다. authenticated 롤로는 두 테이블이 0행이고
--          원장에 쓸 수 없다. anon 롤은 세 RPC를 부를 수 없고, 로그인 없이는 예외 문구가 난다
--   목록   발송 상태(pending/sent/failed/dropped) 무관하게 전부 보인다. 돌려주는 키가 정확히
--          다섯뿐이다(status·last_error 등은 없다). 7종 kind 전부 보인다. 정렬이
--          created_at desc, id desc다. 50건 상한이 걸리고 최신 50건만 남는다.
--          payload에 reason·object_path·display_name·winner_id가 없다(실제 적재 행으로 확인)
--   배지   행이 없으면 false, 읽음 전 true, 읽은 뒤 false(같은 시각의 행은 새 알림이 아니다),
--          그 뒤 생긴 행은 true. mark를 두 번 불러도 한 행이고 seen_at은 서버 시각이다.
--          A가 읽어도 B의 배지는 그대로다
--   정합   대결 행을 지우면(cascade) 그 알림도 목록에서 사라진다.
--          delete_account 뒤 그 사용자의 notification_reads·수신 원장 행이 0이다
--
-- ** now()가 트랜잭션 내내 고정이라는 점에 기대고 있다. ** created_at을 모두 명시해 "읽은 시각과
-- 같은 행 / 그보다 나중 행"의 경계를 손으로 만든다. 같은 이유로 "mark가 기존 행을 갱신한다"는
-- notification_reads에 과거 seen_at을 미리 넣어 두고 확인한다(그 insert는 테스트의 준비 동작이고,
-- 앱에서 그 테이블에 쓰는 경로는 mark_notifications_seen 하나뿐이다).
do $$
declare
  v_a uuid := gen_random_uuid();
  v_b uuid := gen_random_uuid();
  v_c uuid := gen_random_uuid();
  v_d uuid := gen_random_uuid();
  v_f uuid := gen_random_uuid();

  v_bt uuid := gen_random_uuid();        -- A·B의 대결(대부분의 알림이 붙는 곳)
  v_bt_join uuid := gen_random_uuid();   -- B가 실제로 참가해 matched 행을 만든다
  v_bt_del uuid := gen_random_uuid();    -- cascade 확인용(대결을 지운다)
  v_bt_d uuid := gen_random_uuid();      -- D의 묶음 60건이 붙는 곳
  v_bt_f uuid := gen_random_uuid();      -- F(탈퇴자)의 행이 붙는 곳

  v_now timestamptz := now();            -- 트랜잭션 시작 시각. 아래 비교의 기준이다.

  v_a_list jsonb;
  v_a_list2 jsonb;
  v_b_list jsonb;
  v_c_list jsonb;
  v_d_list jsonb;
  v_b_ids bigint[];
  v_a_ids bigint[];

  v_a_items integer;
  v_a_has_b_rows integer;
  v_a_keys text;
  v_a_kinds integer;
  v_a_status_tags integer;
  v_a_forbidden integer;
  v_a_tie_order text;
  v_b_items integer;
  v_b_has_a_rows integer;
  v_c_items integer;
  v_c_seen_null boolean;
  v_c_has_new boolean;
  v_d_items integer;
  v_d_old_rows integer;
  v_a_items_after integer;
  v_bt_del_rows integer;

  v_a_new_before boolean;
  v_a_new_old_seen boolean;
  v_a_reads_rows integer;
  v_a_seen_is_now boolean;
  v_a_new_after_mark boolean;
  v_a_new_after_insert boolean;
  v_a_reads_rows_twice integer;
  v_b_new_after_a_mark boolean;

  v_outbox_as_user integer;
  v_reads_as_user integer;
  v_outbox_insert text;
  v_outbox_update_rows integer;
  v_outbox_delete_rows integer;
  v_reads_insert text;
  v_anon_list text;
  v_anon_has text;
  v_anon_mark text;
  v_noauth_list text;
  v_noauth_has text;
  v_noauth_mark text;

  v_f_reads integer;
  v_f_outbox integer;

  v_actual jsonb;
  v_expected jsonb;
  v_diff text;
begin
  insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  select u.id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
         u.email, jsonb_build_object('full_name', u.name), now(), now()
  from (values
    (v_a, 'inbox-smoke-a@example.invalid', '스모크A'),
    (v_b, 'inbox-smoke-b@example.invalid', '스모크B'),
    (v_c, 'inbox-smoke-c@example.invalid', '스모크C'),
    (v_d, 'inbox-smoke-d@example.invalid', '스모크D'),
    (v_f, 'inbox-smoke-f@example.invalid', '스모크F')
  ) as u(id, email, name);

  -- ---------------------------------------------------------------------
  -- 준비: 대결 네 개와 실제 적재 한 건(join_battle)
  -- ---------------------------------------------------------------------
  insert into public.battles (id, min_criteria, superiority_criteria, type, status, title,
                              creator_id, opponent_id, duration_minutes, started_at, deadline_at)
  values (v_bt, '["상판이 보인다"]'::jsonb, null, 'speed', 'active', '책상 정리하기',
          v_a, v_b, 1440, now(), now() + interval '1 day');

  insert into public.battles (id, min_criteria, superiority_criteria, type, status, title,
                              creator_id, duration_minutes)
  values (v_bt_del, '["바닥이 보인다"]'::jsonb, null, 'speed', 'pending', '지워질 대결', v_a, 1440);

  insert into public.battles (id, min_criteria, superiority_criteria, type, status, title,
                              creator_id, duration_minutes)
  values (v_bt_d, '["창문이 열렸다"]'::jsonb, null, 'speed', 'pending', '묶음 대결', v_d, 1440);

  insert into public.battles (id, min_criteria, superiority_criteria, type, status, title,
                              creator_id, duration_minutes)
  values (v_bt_f, '["문이 닫혔다"]'::jsonb, null, 'speed', 'pending', '탈퇴자 대결', v_f, 1440);

  -- A가 올린 모집에 B가 참가한다 -> 생성자 A에게 matched 한 행이 **실제 적재 경로로** 생긴다.
  -- payload 금지 키 검사가 뜻을 가지려면 손으로 넣은 행이 아니라 이 행이 필요하다.
  insert into public.battles (id, min_criteria, superiority_criteria, type, status, title,
                              creator_id, duration_minutes)
  values (v_bt_join, '["운동화를 신었다"]'::jsonb, null, 'speed', 'pending', '아침 달리기', v_a, 1440);

  perform set_config('request.jwt.claims', json_build_object('sub', v_b, 'role', 'authenticated')::text, true);
  perform public.give_ai_consent('2026-09-14');
  perform public.join_battle(v_bt_join, 1);

  -- ---------------------------------------------------------------------
  -- 준비: A의 원장 행 — 7종 kind, 발송 상태 네 가지, 같은 시각 두 행
  -- ---------------------------------------------------------------------
  -- 발송 상태를 섞어 두는 이유: 알림함은 상태로 거르지 않는다(알림 권한을 거부한 사용자의 행은
  -- 전부 dropped다 — 거기서 비어 보이면 이 기능의 가치가 없다). 상태 자체는 돌려주지 않으므로
  -- payload의 tag로 "그 행이 목록에 있는가"만 센다.
  insert into public.notification_outbox (recipient_id, kind, battle_id, dedup_key, payload, status, created_at)
  values
    (v_a, 'matched',       v_bt, 'inbox:a:matched',
     jsonb_build_object('title', '책상 정리하기', 'battle_type', 'speed',
                        'deadline_at', to_char(v_now + interval '1 day', 'YYYY-MM-DD"T"HH24:MI:SSOF'),
                        'tag', 'st_pending'),
     'pending', v_now - interval '7 minutes'),
    (v_a, 'submitted',     v_bt, 'inbox:a:submitted',
     jsonb_build_object('title', '책상 정리하기', 'battle_type', 'speed', 'tag', 'st_sent'),
     'sent', v_now - interval '6 minutes'),
    (v_a, 'judge_turn',    v_bt, 'inbox:a:judge_turn',
     jsonb_build_object('title', '책상 정리하기', 'battle_type', 'speed',
                        'judge_deadline_at', to_char(v_now + interval '1 day', 'YYYY-MM-DD"T"HH24:MI:SSOF'),
                        'tag', 'st_failed'),
     'failed', v_now - interval '5 minutes'),
    (v_a, 'deadline_soon', v_bt, 'inbox:a:deadline_soon',
     jsonb_build_object('title', '책상 정리하기', 'battle_type', 'speed',
                        'deadline_at', to_char(v_now + interval '1 day', 'YYYY-MM-DD"T"HH24:MI:SSOF'),
                        'tag', 'st_dropped'),
     'dropped', v_now - interval '4 minutes'),
    (v_a, 'finished',      v_bt, 'inbox:a:finished',
     jsonb_build_object('title', '책상 정리하기', 'battle_type', 'speed', 'outcome', 'win', 'score_delta', 3),
     'sent', v_now - interval '3 minutes'),
    (v_a, 'voided',        v_bt, 'inbox:a:voided',
     jsonb_build_object('title', '책상 정리하기', 'battle_type', 'speed'),
     'sent', v_now - interval '2 minutes'),
    (v_a, 'cancelled',     v_bt, 'inbox:a:cancelled',
     jsonb_build_object('title', '책상 정리하기'),
     'sent', v_now - interval '1 minute'),
    -- cascade 확인용: 이 행은 대결과 함께 사라져야 한다.
    (v_a, 'matched',        v_bt_del, 'inbox:a:will-cascade',
     jsonb_build_object('title', '지워질 대결', 'battle_type', 'speed'),
     'sent', v_now - interval '8 minutes'),
    -- created_at이 같은 두 행. id desc가 깨뜨릴 축이라 뒤에 넣은 tie2가 먼저 와야 한다.
    (v_a, 'matched',        v_bt, 'inbox:a:tie1',
     jsonb_build_object('title', '책상 정리하기', 'battle_type', 'speed', 'tag', 'tie1'),
     'sent', v_now - interval '30 seconds'),
    (v_a, 'matched',        v_bt, 'inbox:a:tie2',
     jsonb_build_object('title', '책상 정리하기', 'battle_type', 'speed', 'tag', 'tie2'),
     'sent', v_now - interval '30 seconds');

  -- B의 행 두 개. A의 목록에 섞여 나오면 격리가 깨진 것이다.
  insert into public.notification_outbox (recipient_id, kind, battle_id, dedup_key, payload, status, created_at)
  values
    (v_b, 'submitted', v_bt, 'inbox:b:submitted',
     jsonb_build_object('title', '책상 정리하기', 'battle_type', 'speed'), 'sent', v_now - interval '9 minutes'),
    (v_b, 'finished',  v_bt, 'inbox:b:finished',
     jsonb_build_object('title', '책상 정리하기', 'battle_type', 'speed', 'outcome', 'loss', 'score_delta', -1),
     'sent', v_now - interval '10 minutes');

  select coalesce(array_agg(id), '{}') into v_b_ids
  from public.notification_outbox where recipient_id = v_b;

  -- D의 묶음 60건. n이 클수록 오래된 행이라 51~60이 상한에 밀려나야 한다.
  insert into public.notification_outbox (recipient_id, kind, battle_id, dedup_key, payload, status, created_at)
  select v_d, 'submitted', v_bt_d, 'inbox:d:' || n,
         jsonb_build_object('title', '묶음 대결', 'battle_type', 'speed', 'n', n),
         'pending', v_now - (n * interval '1 minute')
  from generate_series(1, 60) as n;

  -- F(탈퇴자)의 수신 행과 읽음 행.
  insert into public.notification_outbox (recipient_id, kind, battle_id, dedup_key, payload, status, created_at)
  values (v_f, 'matched', v_bt_f, 'inbox:f:matched',
          jsonb_build_object('title', '탈퇴자 대결', 'battle_type', 'speed'), 'sent', v_now - interval '1 minute');
  insert into public.notification_reads (user_id, seen_at) values (v_f, v_now - interval '1 day');

  -- ---------------------------------------------------------------------
  -- 1. A의 목록: 격리·키 화이트리스트·발송 상태 무관·7종·정렬
  -- ---------------------------------------------------------------------
  perform set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
  v_a_list := public.list_notifications();

  v_a_items := jsonb_array_length(v_a_list -> 'items');

  select count(*) into v_a_has_b_rows
  from jsonb_array_elements(v_a_list -> 'items') e
  where (e ->> 'id')::bigint = any (v_b_ids);

  -- 돌려주는 키가 정확히 다섯뿐이다. status·attempts·last_error·lease_until·dedup_key·sent_at·
  -- recipient_id가 섞여 있으면 여기서 드러난다.
  select string_agg(distinct k, ',' order by k) into v_a_keys
  from jsonb_array_elements(v_a_list -> 'items') e, jsonb_object_keys(e) k;

  select count(distinct e ->> 'kind') into v_a_kinds
  from jsonb_array_elements(v_a_list -> 'items') e;

  select count(*) into v_a_status_tags
  from jsonb_array_elements(v_a_list -> 'items') e
  where e -> 'payload' ->> 'tag' in ('st_pending', 'st_sent', 'st_failed', 'st_dropped');

  -- payload 금지 키. join_battle이 실제로 적재한 행까지 포함해 센다.
  select count(*) into v_a_forbidden
  from jsonb_array_elements(v_a_list -> 'items') e
  where e -> 'payload' ?| array['reason', 'verdict_reason', 'object_path', 'display_name', 'winner_id'];

  select string_agg(e -> 'payload' ->> 'tag', '>' order by ord) into v_a_tie_order
  from jsonb_array_elements(v_a_list -> 'items') with ordinality as t(e, ord)
  where e -> 'payload' ->> 'tag' in ('tie1', 'tie2');

  -- ---------------------------------------------------------------------
  -- 2. B·C·D의 목록
  -- ---------------------------------------------------------------------
  select coalesce(array_agg(id), '{}') into v_a_ids
  from public.notification_outbox where recipient_id = v_a;

  perform set_config('request.jwt.claims', json_build_object('sub', v_b, 'role', 'authenticated')::text, true);
  v_b_list := public.list_notifications();
  v_b_items := jsonb_array_length(v_b_list -> 'items');
  select count(*) into v_b_has_a_rows
  from jsonb_array_elements(v_b_list -> 'items') e
  where (e ->> 'id')::bigint = any (v_a_ids);

  perform set_config('request.jwt.claims', json_build_object('sub', v_c, 'role', 'authenticated')::text, true);
  v_c_list := public.list_notifications();
  v_c_items := jsonb_array_length(v_c_list -> 'items');
  v_c_seen_null := (v_c_list -> 'seen_at') = 'null'::jsonb;
  v_c_has_new := public.has_new_notifications();

  perform set_config('request.jwt.claims', json_build_object('sub', v_d, 'role', 'authenticated')::text, true);
  v_d_list := public.list_notifications();
  v_d_items := jsonb_array_length(v_d_list -> 'items');
  select count(*) into v_d_old_rows
  from jsonb_array_elements(v_d_list -> 'items') e
  where (e -> 'payload' ->> 'n')::integer > 50;

  -- ---------------------------------------------------------------------
  -- 3. cascade: 대결 행이 사라지면 그 알림도 사라진다
  -- ---------------------------------------------------------------------
  delete from public.battles where id = v_bt_del;
  v_bt_del_rows := (select count(*) from public.notification_outbox where battle_id = v_bt_del);

  perform set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
  v_a_list2 := public.list_notifications();
  v_a_items_after := jsonb_array_length(v_a_list2 -> 'items');

  -- ---------------------------------------------------------------------
  -- 4. 배지 판정과 읽음 찍기
  -- ---------------------------------------------------------------------
  v_a_new_before := public.has_new_notifications();

  -- 과거 시각을 미리 넣어 "mark가 기존 행을 갱신한다"를 볼 수 있게 한다(now()가 고정이라 두 번
  -- 불러서는 값의 변화를 관찰할 수 없다).
  insert into public.notification_reads (user_id, seen_at) values (v_a, v_now - interval '1 day');
  v_a_new_old_seen := public.has_new_notifications();

  perform public.mark_notifications_seen();
  v_a_reads_rows := (select count(*) from public.notification_reads where user_id = v_a);
  v_a_seen_is_now := (select seen_at = v_now from public.notification_reads where user_id = v_a);

  -- 읽은 뒤에는 false다. join_battle이 넣은 행의 created_at은 기본값 now() = seen_at과 **같으므로**
  -- > 비교의 경계도 여기서 함께 확인된다(같은 시각의 행은 새 알림이 아니다).
  v_a_new_after_mark := public.has_new_notifications();

  insert into public.notification_outbox (recipient_id, kind, battle_id, dedup_key, payload, status, created_at)
  values (v_a, 'submitted', v_bt, 'inbox:a:after-seen',
          jsonb_build_object('title', '책상 정리하기', 'battle_type', 'speed'),
          'pending', v_now + interval '1 second');
  v_a_new_after_insert := public.has_new_notifications();

  perform public.mark_notifications_seen();
  v_a_reads_rows_twice := (select count(*) from public.notification_reads where user_id = v_a);

  -- 읽음은 계정별 값이다. A가 찍어도 B의 배지는 그대로 켜져 있다.
  perform set_config('request.jwt.claims', json_build_object('sub', v_b, 'role', 'authenticated')::text, true);
  v_b_new_after_a_mark := public.has_new_notifications();

  -- ---------------------------------------------------------------------
  -- 5. 롤·권한: 테이블은 두 쪽 모두 0행이고 원장에 쓸 수 없다
  -- ---------------------------------------------------------------------
  -- do 블록은 postgres(소유자)로 돌아 정책을 건너뛰므로 롤을 바꿔야 한다(선례: push_token_smoke).
  perform set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
  begin
    execute 'set local role authenticated';
    v_outbox_as_user := (select count(*) from public.notification_outbox);
    v_reads_as_user := (select count(*) from public.notification_reads);
    execute 'reset role';
  exception when others then
    execute 'reset role';
    v_outbox_as_user := -1;
    v_reads_as_user := -1;
  end;
  execute 'reset role';

  begin
    execute 'set local role authenticated';
    insert into public.notification_outbox (recipient_id, kind, battle_id, dedup_key, payload)
    values (v_a, 'matched', v_bt, 'inbox:a:direct-insert', '{}'::jsonb);
    execute 'reset role';
    v_outbox_insert := '성공(정책이 남아 있음)';
  exception when insufficient_privilege then
    v_outbox_insert := 'RLS 차단';
  when others then
    execute 'reset role';
    v_outbox_insert := '다른 오류: ' || sqlerrm;
  end;
  execute 'reset role';

  -- update·delete는 정책이 없으면 예외가 아니라 0행이다(볼 수 있는 행이 없다).
  begin
    execute 'set local role authenticated';
    update public.notification_outbox set status = 'sent' where recipient_id = v_a;
    get diagnostics v_outbox_update_rows = row_count;
    delete from public.notification_outbox where recipient_id = v_a;
    get diagnostics v_outbox_delete_rows = row_count;
    execute 'reset role';
  exception when others then
    execute 'reset role';
    v_outbox_update_rows := -1;
    v_outbox_delete_rows := -1;
  end;
  execute 'reset role';

  begin
    execute 'set local role authenticated';
    insert into public.notification_reads (user_id, seen_at) values (v_b, v_now);
    execute 'reset role';
    v_reads_insert := '성공(정책이 남아 있음)';
  exception when insufficient_privilege then
    v_reads_insert := 'RLS 차단';
  when others then
    execute 'reset role';
    v_reads_insert := '다른 오류: ' || sqlerrm;
  end;
  execute 'reset role';

  -- anon 롤에는 실행 권한이 없다.
  begin
    execute 'set local role anon';
    perform public.list_notifications();
    execute 'reset role';
    v_anon_list := '성공(권한이 남아 있음)';
  exception when insufficient_privilege then
    v_anon_list := '권한 없음';
  when others then
    execute 'reset role';
    v_anon_list := '다른 오류: ' || sqlerrm;
  end;
  execute 'reset role';

  begin
    execute 'set local role anon';
    perform public.has_new_notifications();
    execute 'reset role';
    v_anon_has := '성공(권한이 남아 있음)';
  exception when insufficient_privilege then
    v_anon_has := '권한 없음';
  when others then
    execute 'reset role';
    v_anon_has := '다른 오류: ' || sqlerrm;
  end;
  execute 'reset role';

  begin
    execute 'set local role anon';
    perform public.mark_notifications_seen();
    execute 'reset role';
    v_anon_mark := '성공(권한이 남아 있음)';
  exception when insufficient_privilege then
    v_anon_mark := '권한 없음';
  when others then
    execute 'reset role';
    v_anon_mark := '다른 오류: ' || sqlerrm;
  end;
  execute 'reset role';

  -- 로그인 없이(claims 없음) 부르면 첫 줄 가드가 막는다.
  perform set_config('request.jwt.claims', '', true);
  begin
    perform public.list_notifications();
    v_noauth_list := '성공(가드 없음)';
  exception when others then
    v_noauth_list := sqlerrm;
  end;
  begin
    perform public.has_new_notifications();
    v_noauth_has := '성공(가드 없음)';
  exception when others then
    v_noauth_has := sqlerrm;
  end;
  begin
    perform public.mark_notifications_seen();
    v_noauth_mark := '성공(가드 없음)';
  exception when others then
    v_noauth_mark := sqlerrm;
  end;

  -- ---------------------------------------------------------------------
  -- 6. 탈퇴: 읽음 행과 내 수신 원장이 함께 지워진다
  -- ---------------------------------------------------------------------
  perform set_config('request.jwt.claims', json_build_object('sub', v_f, 'role', 'authenticated')::text, true);
  perform public.delete_account();
  v_f_reads := (select count(*) from public.notification_reads where user_id = v_f);
  v_f_outbox := (select count(*) from public.notification_outbox where recipient_id = v_f);

  -- ---------------------------------------------------------------------
  -- 결과 비교
  -- ---------------------------------------------------------------------
  v_actual := jsonb_build_object(
    'a_items', v_a_items,
    'a_has_b_rows', v_a_has_b_rows,
    'a_keys', v_a_keys,
    'a_kinds', v_a_kinds,
    'a_status_tags', v_a_status_tags,
    'a_forbidden', v_a_forbidden,
    'a_tie_order', v_a_tie_order,
    'b_items', v_b_items,
    'b_has_a_rows', v_b_has_a_rows,
    'c_items', v_c_items,
    'c_seen_null', v_c_seen_null,
    'c_has_new', v_c_has_new,
    'd_items', v_d_items,
    'd_old_rows', v_d_old_rows,
    'bt_del_rows', v_bt_del_rows,
    'a_items_after', v_a_items_after,
    'a_new_before', v_a_new_before,
    'a_new_old_seen', v_a_new_old_seen,
    'a_reads_rows', v_a_reads_rows,
    'a_seen_is_now', v_a_seen_is_now,
    'a_new_after_mark', v_a_new_after_mark,
    'a_new_after_insert', v_a_new_after_insert,
    'a_reads_rows_twice', v_a_reads_rows_twice,
    'b_new_after_a_mark', v_b_new_after_a_mark,
    'outbox_as_user', v_outbox_as_user,
    'reads_as_user', v_reads_as_user,
    'outbox_insert', v_outbox_insert,
    'outbox_update_rows', v_outbox_update_rows,
    'outbox_delete_rows', v_outbox_delete_rows,
    'reads_insert', v_reads_insert,
    'anon_list', v_anon_list,
    'anon_has', v_anon_has,
    'anon_mark', v_anon_mark,
    'noauth_list', v_noauth_list,
    'noauth_has', v_noauth_has,
    'noauth_mark', v_noauth_mark,
    'f_reads', v_f_reads,
    'f_outbox', v_f_outbox
  );

  v_expected := jsonb_build_object(
    -- 손으로 넣은 10행 + join_battle이 적재한 matched 1행.
    'a_items', 11,
    'a_has_b_rows', 0,
    -- 화이트리스트. 알파벳 순이다.
    'a_keys', 'battle_id,created_at,id,kind,payload',
    'a_kinds', 7,
    -- pending·sent·failed·dropped 네 행이 모두 보인다(발송 상태로 거르지 않는다).
    'a_status_tags', 4,
    'a_forbidden', 0,
    -- created_at이 같으면 id desc. 뒤에 넣은 tie2가 앞이다.
    'a_tie_order', 'tie2>tie1',
    'b_items', 2,
    'b_has_a_rows', 0,
    -- 신규 가입자는 목록도 비고 읽은 시각도 없고 배지도 꺼져 있다.
    'c_items', 0,
    'c_seen_null', true,
    'c_has_new', false,
    -- 60건을 넣어도 50건이고, 밀려난 것은 가장 오래된 10건(n > 50)이다.
    'd_items', 50,
    'd_old_rows', 0,
    -- 대결을 지우면 알림도 함께 사라진다.
    'bt_del_rows', 0,
    'a_items_after', 10,
    -- 읽음 행이 없으면 새 알림이 있다. 과거 시각으로 읽었어도 그 뒤 행이 있으니 그대로 켜져 있다.
    'a_new_before', true,
    'a_new_old_seen', true,
    -- 멱등(한 행) + 시각은 서버가 찍는다.
    'a_reads_rows', 1,
    'a_seen_is_now', true,
    -- seen_at과 같은 시각의 행은 새 알림이 아니다.
    'a_new_after_mark', false,
    'a_new_after_insert', true,
    'a_reads_rows_twice', 1,
    -- 읽음은 계정별이다.
    'b_new_after_a_mark', true,
    -- 테이블에는 정책이 없다 -> 사용자 롤로는 아무것도 보이지 않고 쓰지도 못한다.
    'outbox_as_user', 0,
    'reads_as_user', 0,
    'outbox_insert', 'RLS 차단',
    'outbox_update_rows', 0,
    'outbox_delete_rows', 0,
    'reads_insert', 'RLS 차단',
    'anon_list', '권한 없음',
    'anon_has', '권한 없음',
    'anon_mark', '권한 없음',
    'noauth_list', '로그인이 필요합니다.',
    'noauth_has', '로그인이 필요합니다.',
    'noauth_mark', '로그인이 필요합니다.',
    -- 탈퇴하면 읽음 행과 내 수신 원장이 함께 사라진다.
    'f_reads', 0,
    'f_outbox', 0
  );

  select coalesce(string_agg(format('%s expected=%s actual=%s', e.key, e.value, coalesce(a.value::text, 'null')), '; '), '')
  into v_diff
  from jsonb_each(v_expected) e
  left join jsonb_each(v_actual) a on a.key = e.key
  where a.value is distinct from e.value;

  raise exception 'SMOKE RESULT ok=% %', v_diff = '',
    case when v_diff = '' then '' else ' FAILURES: ' || v_diff end;
end $$;
