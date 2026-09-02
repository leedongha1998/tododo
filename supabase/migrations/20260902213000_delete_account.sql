-- 계정 삭제(탈퇴). Google 계정으로 로그인하는 앱은 Play 정책상 앱 내 계정 삭제 수단이 필요하다.
--
-- 설계: auth.users 행은 실제로 지우되 profiles 행은 '탈퇴한 사용자' 묘비로 남긴다.
-- 그대로 하드 삭제하면 cascade로 대결 행까지 사라져 남은 상대방의 전적에서도 그 대결이
-- 소리 없이 없어진다. 그래서 개인 데이터(투두, 증거 사진/본문, 표시 이름)만 실제로 지우고
-- 대결 기록 자체는 익명 상태로 보존한다.
--
-- 이를 위해 지금까지 auth.users를 가리키던 FK를 전부 public.profiles로 옮긴다.
-- (profiles는 auth.users와 1:1이므로 기존 행은 전부 그대로 옮겨진다.)

alter table public.profiles add column deleted_at timestamptz;

comment on column public.profiles.deleted_at is
  '탈퇴 시각. null이 아니면 auth 계정이 삭제된 묘비 행이다.';

-- profiles는 auth.users가 사라진 뒤에도 남아야 하므로 FK를 끊는다.
-- (행 생성은 여전히 on_auth_user_created 트리거가 담당한다.)
alter table public.profiles drop constraint profiles_id_fkey;

alter table public.todos
  drop constraint todos_user_id_fkey,
  add constraint todos_user_id_fkey foreign key (user_id)
    references public.profiles (id) on delete cascade;

alter table public.battles
  drop constraint battles_creator_id_fkey,
  add constraint battles_creator_id_fkey foreign key (creator_id)
    references public.profiles (id) on delete cascade,
  drop constraint battles_opponent_id_fkey,
  add constraint battles_opponent_id_fkey foreign key (opponent_id)
    references public.profiles (id) on delete cascade,
  drop constraint battles_winner_id_fkey,
  add constraint battles_winner_id_fkey foreign key (winner_id)
    references public.profiles (id);

alter table public.battle_participants
  drop constraint battle_participants_user_id_fkey,
  add constraint battle_participants_user_id_fkey foreign key (user_id)
    references public.profiles (id) on delete cascade;

-- 탈퇴: 본인 계정만 지울 수 있다. 되돌릴 수 없다.
create function public.delete_account()
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    raise exception '로그인이 필요합니다.';
  end if;

  -- 아직 끝나지 않은 대결은 승자 없이 취소한다.
  -- (남은 상대가 오지 않을 증거/판정을 무한정 기다리지 않게 한다.)
  update public.battles
  set status = 'cancelled', finished_at = now()
  where status in ('pending', 'active', 'judging')
    and (creator_id = v_user_id or opponent_id = v_user_id);

  delete from public.todos where user_id = v_user_id;

  -- 증거 사진 오브젝트. 경로 규칙은 {battle_id}/{user_id}/evidence.jpg
  delete from storage.objects
  where bucket_id = 'battle_evidence'
    and (storage.foldername(name))[2] = v_user_id::text;

  -- 증거 본문/사진 경로는 개인 데이터이므로 지운다.
  -- 판정 근거였던 제출 시각·승인 결과는 남은 상대의 전적을 설명하는 값이라 남긴다.
  update public.battle_participants
  set evidence_type = null, evidence_content = null
  where user_id = v_user_id;

  update public.profiles
  set display_name = '탈퇴한 사용자', deleted_at = now()
  where id = v_user_id;

  -- 실제 계정 삭제. 세션/토큰/소셜 연결은 auth 스키마 cascade로 함께 사라진다.
  -- 이 함수의 소유자(postgres)는 auth.users에 delete 권한이 있고 RLS도 우회하지만,
  -- 훗날 권한이 바뀌어 한 행도 못 지우게 되면 "데이터만 지워지고 계정은 살아있는" 상태가
  -- 남는다. 그래서 0행이면 예외를 던져 트랜잭션 전체를 되돌린다.
  delete from auth.users where id = v_user_id;

  if not found then
    raise exception '계정을 삭제하지 못했습니다.';
  end if;
end;
$$;

revoke execute on function public.delete_account() from public, anon;
grant execute on function public.delete_account() to authenticated;

-- 증거 사진은 클라이언트가 Storage API로 먼저 지운다. storage.objects 행만 지우면 실제 파일이
-- 버킷에 남기 때문이다. 그래서 본인 폴더에 대한 delete 정책이 필요하다.
-- (위 RPC의 storage.objects 삭제는 이 단계가 실패했을 때를 위한 최후 방어선이다.)
create policy "participants can delete own evidence"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'battle_evidence'
    and (storage.foldername(name))[2] = auth.uid()::text
  );
