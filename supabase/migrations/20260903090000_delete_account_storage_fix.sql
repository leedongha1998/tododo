-- delete_account()가 항상 실패하던 문제 수정.
--
-- 앞 마이그레이션(20260902213000)은 증거 사진 정리의 "최후 방어선"으로 storage.objects를
-- 직접 delete했는데, Supabase에는 storage.protect_delete() 트리거가 있어 SQL로 스토리지
-- 테이블 행을 지우면 예외가 난다:
--   ERROR 42501: Direct deletion from storage tables is not allowed. Use the Storage API instead.
-- SECURITY DEFINER 함수 안이라도 막히므로, 이 한 줄 때문에 탈퇴 전체가 롤백됐다.
--
-- 그래서 DB 쪽 삭제는 걷어낸다. 사진은 클라이언트가 탈퇴 직전에 Storage API로 지운다
-- (그 경로만이 지원되는 방식이다). 지우지 못한 사진은 참조가 끊긴 채 버킷에 남을 수 있고,
-- 이는 TODO_BACKLOG.md에 남긴 알려진 한계다.

create or replace function public.delete_account()
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
