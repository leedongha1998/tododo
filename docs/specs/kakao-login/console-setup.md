# kakao-login 콘솔 설정 순서 (오너가 직접 한다)

작성 2026-11-26. 근거 표기:
- **[S]** Supabase 공식 문서 원본에서 확인했다(`supabase/supabase` 저장소
  `apps/docs/content/guides/auth/social-sign-in/auth-kakao.mdx`).
- **[A]** Supabase Auth 서버 소스에서 확인했다(`supabase/auth`, `internal/api/provider/kakao.go`).
- **[기억]** 확인하지 못했다. 이 컨테이너에서는 developers.kakao.com에 접속할 수 없었다. 화면에서 다르면 화면을 따른다.

카카오 콘솔의 메뉴 이름은 Supabase 문서의 영문 표기 그대로 적었다. 한국어 화면에서는 괄호 안 이름일 가능성이 높다(그 대응은 [기억]).

이 프로젝트의 값:
- Supabase 프로젝트: `https://xskasyzbsnctycaxpbsr.supabase.co` (`DEPLOY.md` 83행)
- 카카오 Redirect URI: `https://xskasyzbsnctycaxpbsr.supabase.co/auth/v1/callback`
  — 형식은 [S]. **Supabase 대시보드 Kakao 항목에 뜨는 Callback URL과 한 글자라도 다르면 대시보드 쪽 값을 쓴다**
- 앱 딥링크: `com.todododo.todododo://login-callback/` (`AndroidManifest.xml`, Google과 같이 쓴다)

---

## 0. spec과 어긋나는 사실 (먼저 읽을 것)

Supabase의 카카오 공급자는 **`account_email`, `profile_image`, `profile_nickname` 세 범위를 언제나 요청한다.**
앱이 범위를 넘겨도 뒤에 덧붙을 뿐 뺄 수 없다 [A]. Supabase 문서가 동의항목으로 켜라고 한 것은
`profile_image`와 `profile_nickname`이고, `account_email`은 선택이다. 이메일을 받지 않으면 Supabase의
**Allow users without an email**을 켜라고 한다 [S]. 또 `account_email` 동의항목은 **비즈 앱만** 쓸 수 있다 [S].

그래서 spec 결정 1의 "카카오에서 받는 것은 **닉네임 하나**"는 그대로는 성립하지 않을 가능성이 크다.
- 이메일은 결정대로 받지 않을 수 있다: 동의항목을 설정하지 않고 Supabase 토글을 켠다.
- 프로필 사진은 **동의항목에 넣지 않으면 카카오가 오류를 낼 수 있다** [기억: 설정하지 않은 동의항목을 요청하면
  `KOE205`]. 그렇다면 프로필 사진을 **선택 동의**로 넣는 것이 남은 길이다. 사용자가 체크를 풀 수 있고,
  동의하면 Supabase가 사진 URL을 `auth.users`의 메타데이터(`avatar_url`)에 저장한다 [A]. 앱 화면은 그 값을
  쓰지 않는다.

아래 3단계에서 **먼저 프로필 사진 없이** 시도한다(spec에 가장 가깝다). 오류가 나면 선택 동의로 바꾼다. 그 경우
개인정보처리방침의 수집 항목에 "프로필 사진 URL(선택)"을 더해야 하므로, 결과를 메인 세션에 알려 준다.

---

## 1. 카카오 앱 만들기

1. https://developers.kakao.com 에 로그인한다.
2. **App**(내 애플리케이션) → **Create app**(애플리케이션 추가하기).
3. 앱 아이콘, 앱 이름(`투두두두`), 회사명(개인이면 본인 이름), 카테고리를 넣고 **Save**(저장) [S].
   - Supabase 문서에는 "App primary domain"도 있다 [S]. 웹사이트가 없으면 정책 문서를 게시할 GitHub Pages
     주소(`DEPLOY.md` 0번)를 쓰거나 비워 둔다. 비워 둘 수 없다면 알려 준다.

## 2. 카카오 로그인 켜기 + 키 확인

1. **Product Settings → Kakao Login → General**(제품 설정 → 카카오 로그인 → 일반)에서 **Usage settings**의
   **State**를 **ON**으로 바꾼다 [S].
2. **App Settings → App → Platform Key**(앱 설정 → 앱 → 플랫폼 키)에서 **REST API key**를 연다 [S].
   - 이 값이 Supabase의 **Client ID**다 [S]. 메모장에만 옮기고, 채팅·코드·커밋에는 붙이지 않는다.
3. 같은 REST API 키 편집 화면에서:
   - **Kakao Login Redirect URI**(카카오 로그인 리다이렉트 URI)에
     `https://xskasyzbsnctycaxpbsr.supabase.co/auth/v1/callback`을 넣고 **Save** [S].
   - **Kakao Login Client Secret code**를 확인하고 **Kakao Login Client Secret**을 **활성화**한다 [S].
     이 값이 Supabase의 **Client Secret**이다.
4. **Android 플랫폼·키 해시는 등록하지 않는다.** 이 앱은 카카오 SDK가 아니라 브라우저로 로그인한다.
   Supabase 문서의 설정 단계에도 플랫폼 등록은 없다 [S]. 키 해시는 카카오 네이티브 SDK를 쓸 때 필요하다 [기억].

## 3. 동의항목

**Product Settings → Kakao Login → Consent Items**(제품 설정 → 카카오 로그인 → 동의항목) [S]:

| 항목 | 설정 | 근거 |
|---|---|---|
| 닉네임(`profile_nickname`) | **필수 동의**. 동의 목적: "대결 상대에게 보이는 표시 이름" | spec P0-2, [S] |
| 프로필 사진(`profile_image`) | **처음에는 설정하지 않는다.** 5단계 확인에서 오류가 나면 **선택 동의**로 바꾼다 | 위 0절 |
| 카카오계정(이메일)(`account_email`) | 설정하지 않는다 | spec 결정 1, 비즈 앱 전용 [S] |
| 그 밖의 항목(친구 목록, 전화번호 등) | 전부 설정하지 않는다 | spec 합격선 3 |

동의항목을 설정할 때 개인정보처리방침 URL을 요구하면 정책 문서부터 게시해야 한다(`DEPLOY.md` 0번).
요구하는지는 [기억]에도 없다. 요구하면 알려 준다.

## 4. Supabase 대시보드

1. 대시보드 → 이 프로젝트 → **Authentication → Sign In / Providers** → **Kakao**를 연다 [S].
2. **Kakao Enabled**를 ON으로 바꾼다 [S].
3. **Kakao Client ID**에 REST API 키, **Kakao Client Secret**에 Client Secret 코드를 넣는다 [S].
4. **Allow users without an email**을 **켠다** [S].
5. 이 화면의 **Callback URL**이 2-3에서 카카오에 넣은 주소와 같은지 본다. 다르면 카카오 쪽을 고친다 [S].
6. **Save**.
7. **Authentication → URL Configuration → Redirect URLs**에 `com.todododo.todododo://login-callback/`이
   이미 있는지 본다. Google이 쓰고 있으므로 있어야 한다. 없으면 추가한다.

## 5. 원격 DB 마이그레이션 → 실기기 확인(게이트)

5단계부터는 Windows 컴퓨터에서 한다.

```
supabase db push                      # 20261125120000_kakao_login.sql 적용
supabase db query --linked -f supabase/tests/kakao_signup_smoke.sql   # SMOKE RESULT ok=true 확인
flutter run                           # 디버그 빌드
```

앱에서 **카카오로 로그인**을 누르고 아래를 적어 메인 세션에 알려 준다(plan.md 게이트 V1~V6).
1. 카카오 동의 화면에 뜬 항목이 무엇인가(닉네임만? 사진도?).
2. 오류 화면이나 `KOE...` 코드가 뜨는가. 뜨면 그 코드 그대로.
3. 앱으로 돌아와 본 화면이 뜨는가. 프로필에 "카카오 계정으로 로그인했어요"가 보이는가. 표시 이름이 카카오
   닉네임인가.
4. 대시보드 **Authentication → Users**에서 그 사용자의 Email이 비어 있는가. Provider가 kakao인가.
5. 그 사용자의 **Raw user meta data**에 어떤 키가 있는가(값 말고 **키 이름만**: `full_name`, `avatar_url` 등).

2번에서 오류가 나면 3단계의 프로필 사진을 **선택 동의**로 바꾸고 다시 해 본다.

확인이 끝나면 그 테스트 계정은 앱의 계정 삭제로 지운다. 다음 단계(연결 끊기)를 처음 시험하는 자리가 된다.

## 6. 탈퇴 시 연결 끊기

1. 카카오 콘솔 **App Settings → App → Platform Key**(앱 설정 → 앱 → 플랫폼 키)에서 **Admin 키**를 찾는다
   (위치는 [기억]이다. 예전 콘솔에서는 "앱 키" 화면에 있었다). **이 키는 모든 사용자에 대한 관리 권한을 가진다.**
   앱·코드·채팅에 절대 넣지 않는다.
2. Windows 터미널에서:
   ```
   supabase secrets set KAKAO_ADMIN_KEY=<Admin 키>
   supabase functions deploy delete-account
   ```
   셸 기록에 남는 것이 싫으면 Supabase 대시보드 **Edge Functions → Secrets**에서 넣어도 된다.
3. 5단계에서 만든 테스트 계정을 앱에서 삭제한다. "카카오 연결은 끊지 못했어요" 토스트가 **뜨지 않으면** 성공이다.
   카카오톡 → 설정 → 카카오계정 → 연결된 서비스 관리에서 투두두두가 사라졌는지도 본다 [기억: 메뉴 위치].

## 7. 출시 전

- 로그인 버튼 **심볼**: 카카오 개발자 사이트 디자인 가이드에서 공식 리소스(말풍선 심볼 PNG)를 받아
  `assets/kakao/`에 넣는다. 그 뒤 메인 세션이 버튼에 붙인다. 지금 버튼은 글자만 있다.
  디자인 가이드가 버튼 문구를 고정하는지(`카카오 로그인`), 모서리 값을 고정하는지도 함께 확인한다.
- **비즈 앱이 아닌 상태의 제한**(이용자 수·기능)이 있는지 콘솔 안내를 본다 [기억에 없음].
- 정책 문서(`C:\workspaces\todododo-legal`): plan.md "정책 문서 변경 목록". 5단계에서 프로필 사진을 선택 동의로
  넣었다면 수집 항목에 "프로필 사진 URL(선택)"을 더한다.
- 릴리스 빌드: `flutter build apk --release --dart-define-from-file=env.json`. `EXIT=$?`를 따로 찍는다.
