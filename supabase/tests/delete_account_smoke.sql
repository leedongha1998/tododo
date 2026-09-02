-- delete_account() 스모크 테스트.
--
-- 로컬에 Docker가 없어 supabase start를 못 쓰므로, 원격 DB에 직접 돌린다:
--   supabase db query --linked -f supabase/tests/delete_account_smoke.sql
--
-- 임시 사용자를 만들어 실제로 탈퇴시켜 보고, 마지막에 일부러 예외를 던져 트랜잭션 전체를
-- 롤백한다. 결과는 예외 메시지(SMOKE RESULT ...)로 돌아온다. 기대값:
--   auth_user_exists=f  todos_left=0  profile_name=탈퇴한 사용자
--   deleted_at_set=t    battle_status=cancelled  evidence=(null)
-- 어느 하나라도 다르면 delete_account()가 깨진 것이다.
do $$
declare
  v_uid uuid := gen_random_uuid();
  v_todos int;
  v_user_exists boolean;
  v_name text;
  v_deleted boolean;
  v_battle_status text;
  v_evidence text;
begin
  insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  values (
    v_uid,
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'delete-account-smoke@example.invalid',
    '{"full_name":"스모크테스트"}'::jsonb,
    now(),
    now()
  );

  insert into public.todos (user_id, title) values (v_uid, '테스트 할 일');

  insert into public.battles (type, status, title, creator_id)
  values ('speed', 'pending', '테스트 모집', v_uid);

  update public.battle_participants
  set evidence_type = 'text', evidence_content = '테스트 증거', evidence_submitted_at = now()
  where user_id = v_uid;

  -- 이 세션을 해당 사용자로 위장시킨다 (auth.uid()가 읽는 값).
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', v_uid, 'role', 'authenticated')::text,
    true
  );

  perform public.delete_account();

  select count(*) into v_todos from public.todos where user_id = v_uid;
  select exists(select 1 from auth.users where id = v_uid) into v_user_exists;
  select display_name, deleted_at is not null into v_name, v_deleted
  from public.profiles where id = v_uid;
  select status into v_battle_status from public.battles where creator_id = v_uid;
  select coalesce(evidence_content, '(null)') into v_evidence
  from public.battle_participants where user_id = v_uid;

  raise exception 'SMOKE RESULT auth_user_exists=% todos_left=% profile_name=% deleted_at_set=% battle_status=% evidence=%',
    v_user_exists, v_todos, v_name, v_deleted, v_battle_status, v_evidence;
end $$;
