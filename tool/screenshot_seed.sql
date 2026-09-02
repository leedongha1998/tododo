-- 스토어 스크린샷을 찍기 위한 샘플 데이터. **원격 DB에 직접 쓴다** — 찍고 나면 반드시
-- tool/screenshot_cleanup.sql로 지울 것. 사용법: supabase db query --linked -f tool/screenshot_seed.sql
-- v_me는 스크린샷을 찍을 계정(에뮬레이터에 로그인된 사용자)의 profiles.id로 바꿔 쓴다.
-- 전부 고정 UUID(000000f0… 대역)라 정리 스크립트가 정확히 되돌릴 수 있고,
-- 실제 사용자 데이터(기존 투두 등)는 건드리지 않는다.
do $$
declare
  v_me uuid := '6455cd58-2866-4d3f-8a83-9aa7186ec81c';  -- Dongha Lee (에뮬레이터 로그인 계정)
  v_rival uuid := '000000f0-0000-4000-8000-000000000001';
  v_rival2 uuid := '000000f0-0000-4000-8000-000000000002';
  v_active uuid := '000000f0-0000-4000-8000-00000000000a';
  v_recruit1 uuid := '000000f0-0000-4000-8000-00000000000b';
  v_recruit2 uuid := '000000f0-0000-4000-8000-00000000000c';
  v_done1 uuid := '000000f0-0000-4000-8000-00000000000d';
  v_done2 uuid := '000000f0-0000-4000-8000-00000000000e';
  v_done3 uuid := '000000f0-0000-4000-8000-00000000000f';
begin
  -- 상대 프로필. auth 계정 없이 profiles 행만 만든다(탈퇴 묘비와 같은 구조).
  insert into public.profiles (id, display_name) values
    (v_rival, '박세연'),
    (v_rival2, '김도현')
  on conflict (id) do update set display_name = excluded.display_name;

  -- 개인 할 일
  insert into public.todos (id, user_id, title, is_done, created_at) values
    ('000000f0-0000-4000-8000-000000000101', v_me, '아침 7시 기상하기', true, now() - interval '5 hour'),
    ('000000f0-0000-4000-8000-000000000102', v_me, '러닝 3km', false, now() - interval '4 hour'),
    ('000000f0-0000-4000-8000-000000000103', v_me, '책 20쪽 읽기', true, now() - interval '3 hour'),
    ('000000f0-0000-4000-8000-000000000104', v_me, '영어 단어 30개 외우기', false, now() - interval '2 hour'),
    ('000000f0-0000-4000-8000-000000000105', v_me, '방 청소하기', false, now() - interval '1 hour')
  on conflict (id) do nothing;

  -- 진행 중(판정 대기) 속도전 — 양쪽 다 증거 제출, 아직 아무도 판정하지 않음
  insert into public.battles (id, type, status, title, creator_id, opponent_id, created_at, started_at)
  values (v_active, 'speed', 'judging', '아침 7시 기상하기', v_me, v_rival,
          now() - interval '9 hour', now() - interval '9 hour')
  on conflict (id) do nothing;

  insert into public.battle_participants (battle_id, user_id)
  values (v_active, v_rival) on conflict do nothing;

  update public.battle_participants
  set evidence_type = 'text',
      evidence_content = '6시 52분 기상. 알람 끄자마자 물 한 잔 마셨습니다.',
      evidence_submitted_at = now() - interval '4 hour 12 minute'
  where battle_id = v_active and user_id = v_me;

  update public.battle_participants
  set evidence_type = 'text',
      evidence_content = '7시 3분에 일어났어요… 늦잠 잤습니다. 인정합니다.',
      evidence_submitted_at = now() - interval '3 hour 47 minute'
  where battle_id = v_active and user_id = v_rival;

  -- 모집 중인 대결(다른 사람이 올린 것) — 모집함 화면용
  insert into public.battles (id, type, status, title, creator_id, created_at) values
    (v_recruit1, 'quality', 'pending', '방 청소하고 사진 인증', v_rival2, now() - interval '2 hour'),
    (v_recruit2, 'speed', 'pending', '오늘 안에 헬스장 다녀오기', v_rival, now() - interval '40 minute')
  on conflict (id) do nothing;

  -- 끝난 대결 — 프로필 전적 화면용
  insert into public.battles
    (id, type, status, title, creator_id, opponent_id, winner_id, created_at, started_at, finished_at)
  values
    (v_done1, 'speed', 'finished', '책 20쪽 읽기', v_me, v_rival, v_me,
     now() - interval '3 day', now() - interval '3 day', now() - interval '3 day' + interval '2 hour'),
    (v_done2, 'speed', 'finished', '점심 전에 설거지 끝내기', v_rival2, v_me, v_rival2,
     now() - interval '2 day', now() - interval '2 day', now() - interval '2 day' + interval '1 hour'),
    (v_done3, 'quality', 'finished', '책상 정리하고 사진 인증', v_me, v_rival, null,
     now() - interval '1 day', now() - interval '1 day', now() - interval '1 day' + interval '3 hour')
  on conflict (id) do nothing;

  insert into public.battle_participants (battle_id, user_id) values
    (v_done1, v_rival), (v_done2, v_me), (v_done3, v_rival)
  on conflict do nothing;

  update public.battle_participants
  set evidence_type = 'text', evidence_content = '완독!', evidence_submitted_at = now() - interval '3 day',
      decision = 'approve', decision_at = now() - interval '3 day'
  where battle_id in (v_done1, v_done2, v_done3);

  raise notice 'seeded';
end $$;
