-- kakao-login: 가입할 때 정하는 표시 이름에 카카오 갈래를 더한다 (design §3).
--
-- 무엇이 문제였나
--   지금 handle_new_user()는 `coalesce(full_name, email)`이고 profiles.display_name은 not null이다.
--   카카오에서는 이메일을 받지 않으므로(spec 결정 1) 닉네임이 full_name 키로 오지 않으면 **가입 자체가
--   not null 위반으로 실패**한다(합격선 1). 반대로 어떤 경로로든 이메일이 실려 오면 그것이 모집 목록에
--   보이는 이름이 된다(합격선 2).
--
-- 규칙 (design §3.1)
--   | 가입 경로        | 표시 이름                                                              |
--   | Google           | full_name, 없으면 email — **지금 식과 순서 그대로**(합격선 4)            |
--   | 카카오           | 닉네임 후보 키 중 첫 "쓸 수 있는 값", 없으면 `이름 없는 도전자`          |
--   | 그 밖·판별 불가  | Google 식 그대로, **결과가 null일 때만** 기본 이름(가입 실패 대신)        |
--
--   Google 결과가 달라지는 입력은 "이름도 이메일도 없음" 하나뿐인데 그것은 지금 **가입 실패**였고
--   Google은 늘 이메일을 준다 — 성공하던 Google 가입의 결과는 하나도 바뀌지 않는다.
--
-- 닉네임 후보 키 순서와 카카오 판별 조건은 [확인 필요]다 — design §0 검증 게이트(V4)가 실제 키를
-- 알려 주면 **새 마이그레이션으로** 이 두 헬퍼를 create or replace한다(이 파일은 고치지 않는다).
--
-- 기존 사용자의 이름은 건드리지 않는다(백필 없음, spec P0-3). 새 테이블·컬럼·RLS 없음.
-- 봇 행(seed로 직접 넣음)은 이 트리거를 지나지 않는다.

-- ---------------------------------------------------------------------------
-- kakao_display_name: 카카오 가입자의 표시 이름 (신규, 순수 함수)
-- ---------------------------------------------------------------------------
-- 후보 키를 순서대로 보고 첫 "쓸 수 있는 값"을 앞뒤 공백을 걷어 돌려준다. 쓸 수 있는 값:
--   1. 공백을 걷은 뒤 비어 있지 않다.
--   2. 이메일 꼴이 아니다 — 어떤 경로로든 이메일이 닉네임 키에 실려 와도 이름이 되지 않게.
--   3. 사용자의 email과 같지 않다(대소문자 무시).
--   4. 카카오 회원번호(sub·provider_id 키의 값)와 같지 않다 — 식별 번호가 이름이 되지 않게.
--   5. 시스템이 쓰는 이름(`연습 봇`·`탈퇴한 사용자`)과 정확히 같지 않다(design 결정 2, 오너 확정) —
--      상대 카드에서 사람이 봇이나 묘비로 보이면 판정·결과 화면을 오해한다.
-- 하나도 없으면 기본 이름. **기본 이름 문자열이 SQL에 나오는 자리는 여기 하나뿐이다** — 트리거는
-- 기본 이름이 필요할 때 이 함수에 null을 넘겨 받는다.
--
-- 기본 이름 `이름 없는 도전자`의 근거(design §3.1): 이메일·빈 문자열·숫자가 아니고, `연습 봇`·
-- `탈퇴한 사용자`와 어휘가 겹치지 않으며, 로그인 수단을 드러내지 않는다(수단은 본인 프로필에만).
--
-- SECURITY DEFINER가 아니므로 auth.uid() 가드 대상이 아니다. 앱이 부를 이유가 없어 EXECUTE를
-- 전부 회수한다 — 트리거(SECURITY DEFINER, 소유자 권한)만 부른다.
create or replace function public.kakao_display_name(p_meta jsonb, p_email text)
returns text
language sql
immutable
set search_path = public
as $$
  select coalesce(
    (
      select candidate.value
      from unnest(array['full_name', 'name', 'preferred_username', 'user_name', 'nickname'])
             with ordinality as k(key, ord)
      cross join lateral (
        select regexp_replace(p_meta ->> k.key, '^\s+|\s+$', '', 'g') as value
      ) as candidate
      where candidate.value is not null
        and candidate.value <> ''
        and candidate.value !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'
        and (p_email is null or lower(candidate.value) <> lower(p_email))
        and candidate.value is distinct from (p_meta ->> 'sub')
        and candidate.value is distinct from (p_meta ->> 'provider_id')
        and candidate.value not in ('연습 봇', '탈퇴한 사용자')
      order by k.ord
      limit 1
    ),
    '이름 없는 도전자'
  );
$$;

comment on function public.kakao_display_name(jsonb, text) is
  '카카오 가입자의 표시 이름(kakao-login design §3.1). 닉네임 후보 키 중 첫 쓸 수 있는 값, 없으면 '
  '기본 이름 ''이름 없는 도전자''. 기본 이름 문자열의 유일한 자리이고, 트리거는 null을 넘겨 기본 '
  '이름을 받는다. handle_new_user 전용.';

revoke execute on function public.kakao_display_name(jsonb, text) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- is_kakao_signup: 이 가입이 카카오에서 왔는가 (신규, 순수 함수)
-- ---------------------------------------------------------------------------
-- 둘 중 하나라도 참이면 카카오:
--   - raw_app_meta_data.provider = 'kakao' — Supabase Auth가 INSERT 전에 채운다(supabase/auth
--     internal/api/signup.go ToUserModel이 AppMetaData["provider"]를 넣은 뒤 signupNewUser가 INSERT)
--   - raw_user_meta_data.iss의 호스트가 kakao.com이거나 그 하위 도메인 — 위가 빠지는 경우의 보험.
--     Supabase Auth는 iss를 scheme 없이 `kapi.kakao.com`으로 넣는다(kakao.go `Issuer: p.APIHost`)
--     그래서 scheme은 있어도 없어도 된다. 문자열 어디에 kakao.com이 들어 있기만 하면 되는 느슨한 검사 대신 호스트로 본다.
-- 둘 다 빗나가도 트리거의 "그 밖" 갈래가 가입 실패를 막는다(이메일이 없으면 기본 이름).
create or replace function public.is_kakao_signup(p_app_meta jsonb, p_user_meta jsonb)
returns boolean
language sql
immutable
set search_path = public
as $$
  select coalesce(p_app_meta ->> 'provider', '') = 'kakao'
      or coalesce(p_user_meta ->> 'iss', '') ~* '^(https?://)?([a-z0-9-]+\.)*kakao\.com(:[0-9]+)?(/|$)';
$$;

comment on function public.is_kakao_signup(jsonb, jsonb) is
  '가입이 카카오에서 왔는지(kakao-login design §3.1). app_meta.provider = kakao 또는 user_meta.iss의 '
  '호스트가 kakao.com. handle_new_user 전용.';

revoke execute on function public.is_kakao_signup(jsonb, jsonb) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- handle_new_user: 이름 계산만 바뀐다 (교체)
-- ---------------------------------------------------------------------------
-- player_stats 행 생성은 그대로다. auth.users INSERT 트리거라 호출자가 GoTrue이고 auth.uid()가 없어
-- 가드를 두지 않는 것도 기존 함수(20260915120100)와 같은 예외다 — 대신 EXECUTE를 전부 회수한다.
-- 트리거 on_auth_user_created는 바꾸지 않는다(함수만 교체).
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  v_name text;
begin
  if public.is_kakao_signup(new.raw_app_meta_data, new.raw_user_meta_data) then
    v_name := public.kakao_display_name(new.raw_user_meta_data, new.email);
  else
    -- Google(그리고 판별 불가) — 지금 식 그대로.
    v_name := coalesce(new.raw_user_meta_data ->> 'full_name', new.email);
  end if;

  -- 이름도 이메일도 없으면 예전에는 not null 위반으로 가입이 실패했다. 이제 기본 이름이 된다.
  if v_name is null then
    v_name := public.kakao_display_name(null, null);
  end if;

  insert into public.profiles (id, display_name) values (new.id, v_name);

  insert into public.player_stats (user_id) values (new.id);

  return new;
end;
$$;

-- create or replace는 권한을 유지하지만 트리거 전용 함수라는 점을 한 번 더 못박는다.
revoke execute on function public.handle_new_user() from public, anon, authenticated;
