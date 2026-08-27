-- 앞 마이그레이션(20260827130000)의 `revoke ... from public`만으로는 anon이 막히지 않았다.
-- Supabase는 public 스키마에 default privileges로 anon/authenticated/service_role에 EXECUTE를
-- 직접 부여하기 때문에, PUBLIC에서 회수해도 anon의 별도 권한이 남는다. anon에서 직접 회수한다.
--
-- 확인 방법: anon 키만으로 REST RPC를 호출했을 때 함수 본문의 예외(로그인이 필요합니다.)가 아니라
-- 권한 오류가 떨어져야 한다.

revoke execute on function public.join_battle(uuid) from anon;
revoke execute on function public.cancel_battle(uuid) from anon;
revoke execute on function public.submit_evidence(uuid, text, text) from anon;
revoke execute on function public.decide_evidence(uuid, uuid, text) from anon;

revoke execute on function public.handle_new_user() from anon;
revoke execute on function public.set_updated_at() from anon;
revoke execute on function public.create_battle_participants() from anon;

-- 앞으로 마이그레이션으로 만드는 함수도 anon에게 자동으로 열리지 않게 한다.
-- (default privileges는 함수를 "만드는 롤" 기준이며, 마이그레이션은 postgres 롤로 실행된다.
--  supabase_admin에는 걸 수 없다 — permission denied.)
alter default privileges for role postgres in schema public revoke execute on functions from anon;
