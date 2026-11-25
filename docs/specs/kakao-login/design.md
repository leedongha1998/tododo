# kakao-login 설계

> 작성 2026-11-25 (designer). 입력은 `docs/specs/kakao-login/spec.md` 하나다(오너 승인 완료, 결정 1~5 확정 —
> 이 문서는 그 결정을 다시 열지 않는다).
> **[확인 필요]** 표시는 이 문서를 쓰는 시점에 카카오·Supabase 공식 문서로 사실을 확인하지 못한 것이다.
> 설계는 그 값이 어느 쪽으로 나와도 깨지지 않게 방어하고, 확인 방법은 §0 "검증 게이트"에 모았다.

## 참고
- spec: `docs/specs/kakao-login/spec.md` (294행 오너 확정: 이메일 안 받음 / 탈퇴 시 연결 끊기 P0 / 재로그인 강제 안 함 /
  카카오톡 앱 전환 로그인은 P0 아님 / 카카오는 수집 출처로만 / 웹 삭제 요청은 앱 안 삭제가 확실한 경로 / FCM 토큰
  항목 같은 개정)
- 결정 근거: `docs/specs/ai-judge/decisions.md` 26(Google+카카오), 28(친구 목록 API 안 씀), 29(계정 연결 없음)
- 지금 코드에서 읽은 사실(설계가 기대는 것)
  - `lib/features/auth/data/auth_repository.dart` — `signInWithOAuth(OAuthProvider.google, redirectTo:
    'com.todododo.todododo://login-callback/', queryParams: {'prompt': 'select_account'})`. 브라우저 경유라 SHA-1 미등록.
  - `lib/features/auth/presentation/auth_gate.dart` — `authStateProvider`의 `error` 갈래도 `LoginScreen`을 그린다
    (`debugPrint`만, 토스트 없음).
  - `lib/features/auth/presentation/login_screen.dart` — 토스트는 `signInWithGoogle()`이 **던질 때만** 뜬다.
  - `supabase/migrations/20260915120100_ai_judge_schema.sql:171` — 지금 살아 있는 `handle_new_user()`:
    `coalesce(new.raw_user_meta_data ->> 'full_name', new.email)` + `player_stats` 행. `profiles.display_name`은 `not null`.
  - `supabase/functions/delete-account/index.ts` — JWT 확인 → 참가 대결 id 수집 → `delete_account` RPC(호출자 JWT) →
    증거 사진 삭제(실패는 로그만) → `{deleted: true}`. `delete_account`가 `auth.users` 행을 지우므로 **그 뒤에는
    `auth.identities`(카카오 회원번호가 들어 있는 곳)도 함께 사라진다.**
  - `lib/features/todo/domain/todo_providers.dart:24` — `todosProvider`는 `FutureProvider`(autoDispose 아님).
    `lib/core/navigation/main_shell.dart:79-88`이 그 사실과 백로그 버그를 이미 적어 두었다.
  - 다른 계정 데이터 provider(`myProfileProvider`, `myPlayerStatsProvider`, `battleRecordsProvider`, `myBattlesProvider`,
    `myRecruitsProvider`, 알림 provider 등)는 **전부 `autoDispose`**다. `todosProvider` 하나만 예외다.
  - 정책 문서는 이 저장소 밖(`C:\workspaces\todododo-legal`)에 있다. 이 설계는 **바꿀 목록**만 적고 문구는 오너 승인 대상이다.

---

## 설계 원칙 (전체를 관통하는 다섯 가지)

1. **Google 경로는 건드리지 않는다.** 로그인 호출(`prompt=select_account` 포함), 표시 이름 규칙, 버튼 모양·문구가
   그대로다. 이 기능에서 Google 쪽에 닿는 변경은 P0-5(계정 전환 잔상, 양쪽 공통 버그)와 "결정 필요" 1에 올린 오류
   토스트 하나뿐이다.
2. **카카오가 무엇을 주든 가입은 성공하고, 이메일은 이름이 되지 않는다.** 메타데이터 키가 무엇으로 오는지 확신할 수
   없으므로(아래 [확인 필요]) 트리거가 여러 키를 순서대로 보고, 하나도 없으면 고정 기본 이름으로 떨어진다.
3. **새 패키지 없음.** 로그인은 이미 쓰는 `supabase_flutter`의 `signInWithOAuth(OAuthProvider.kakao)`, 연결 끊기는
   Edge Function의 `fetch` 한 번이다. 카카오 SDK(네이티브)는 들이지 않는다 — 결정 5(앱 전환 로그인 P0 아님)와
   CLAUDE.md의 "네이티브 플러그인은 릴리스 빌드를 깨뜨린다" 경험 때문이다. 카카오 버튼 심볼은 **이미지 에셋**이지
   패키지가 아니다(§1.1).
4. **연결 끊기는 관문이 아니다.** 탈퇴는 지금과 똑같이 끝나고, 연결 끊기는 그 **뒤에** 한 번 시도한다. 실패하면 서버 로그를
   남기고 사용자에게는 "직접 끊을 수 있는 곳"을 알린다(사용자가 할 수 있는 일이 있으므로 토스트로 말한다).
5. **로그인 수단은 본인에게만, 그리고 서버 왕복 없이.** 세션에 이미 있는 `app_metadata.provider`를 읽는다. 새 테이블·
   컬럼·RPC를 만들지 않으므로 다른 사용자에게 새는 경로가 원천적으로 없다.

---

## 0. 검증 게이트 — UI 작업 전에 developer가 먼저 확인할 것

spec "전제 리스크"(결정 1의 (A)가 Supabase 설정상 성립하지 않으면 다시 올린다)를 **구현 첫 단계의 관문**으로 만든다.
오너가 §7의 콘솔 설정 중 G1~G5를 끝낸 뒤, developer가 **디버그 빌드에서 `signInWithOAuth(OAuthProvider.kakao)` 한 줄만
붙여** 아래를 확인하고 결과를 plan.md에 적는다. 화면 작업은 이 관문을 통과한 뒤 한다.

| # | 확인할 것 | 통과 조건 | 실패하면 |
|---|---|---|---|
| V1 | 카카오 동의 화면에 뜨는 항목 | **닉네임 하나**(합격선 3) | 아래 "게이트 실패" |
| V2 | 카카오가 `KOE205`(설정하지 않은 동의항목 요청) 류 오류를 내는가 | 오류 없이 앱으로 돌아온다 | 아래 "게이트 실패" |
| V3 | 이메일 없이 가입이 되는가 | `auth.users` 행이 생기고 `email`이 null | Supabase 카카오 공급자의 "이메일 없는 사용자 허용" 류 설정을 켜고 다시 본다 [확인 필요]. 그래도 안 되면 "게이트 실패" |
| V4 | 그 행의 `raw_app_meta_data`, `raw_user_meta_data`에 **어떤 키가** 있는가 | 키 이름만 기록(값은 기록하지 않는다). 특히 `provider`, `iss`, 닉네임이 들어 있는 키 | §3.2의 후보 키 목록을 그 결과에 맞춰 고친다(목록에 없는 키면 추가) |
| V5 | `auth.identities`의 카카오 행에서 회원번호가 어느 필드에 있는가 | `identity_data.sub` / `identity_data.provider_id` / `provider_id` 중 어디인지 기록 | §4.3의 추출 순서를 그 결과에 맞춘다 |
| V6 | 가입 직후 `profiles.display_name` | 카카오 닉네임 | §3 트리거 수정 전이면 기존 규칙 결과를 기록만 한다(아래 주의) |

- **주의(V6)**: 새 트리거 마이그레이션을 원격에 올리기 **전에** 카카오로 가입하면 기존 규칙(`full_name`, 없으면 이메일)이
  돈다. 이메일을 받지 않으므로 `full_name`이 없으면 **그 가입은 not null 위반으로 실패한다** — 그것 자체가 V4를 알려 주는
  신호다. 실패가 싫으면 §3 마이그레이션을 먼저 올리고 게이트를 돈다(트리거는 키가 없어도 성공하게 설계돼 있다). 권장 순서는
  **마이그레이션 먼저**다.
- 게이트에서 만든 테스트 계정은 확인 뒤 앱의 계정 삭제로 지운다(그게 §4의 탈퇴 경로 첫 실험이 된다).
- 설계자가 기억하는 사실(확인 안 됨, 게이트가 판정한다): Supabase Auth의 카카오 공급자는 기본 요청 범위에
  `account_email`·`profile_image`·`profile_nickname`을 넣고, 클라이언트의 `scopes` 인자는 **덧붙이기만** 하고 빼지
  못한다 [확인 필요]. 사실이면 V1·V2가 실패할 수 있다. 닉네임은 `full_name`·`name`·`preferred_username` 류에 함께
  담긴다 [확인 필요].

**게이트 실패**(V1·V2·V3이 콘솔·대시보드 설정으로 해결되지 않음): 구현을 멈추고 메인 세션이 오너에게 spec 결정 1을
다시 올린다(spec이 그렇게 정해 두었다). 이 설계는 그 경우의 대안을 미리 고르지 않는다 — 이메일을 받게 되면 합격선 2·5,
§3의 규칙, §6의 방침 목록이 함께 바뀐다.

---

## 1. 화면

### 1.1 로그인 화면 (`LoginScreen`) — 버튼 둘 + 안내 한 줄

```
          [ 앱 마크 112dp ]
               24
             투두두두
               40
   ┌──────────────────────────┐
   │       구글로 로그인        │   ← 지금 버튼 그대로(위치·모양·문구·동작)
   └──────────────────────────┘
               12
   ┌──────────────────────────┐
   │ (말풍선)  카카오로 로그인   │   ← 신규. 카카오 노란 면 + 검은 글자
   └──────────────────────────┘
               16
  구글과 카카오 계정은 서로 연결되지 않아요.
  처음 가입한 방법으로 로그인해 주세요.        ← bodySmall, onSurfaceVariant, 가운데 정렬
```

- **순서: 구글 위, 카카오 아래.** 근거: 지금 가입자는 전부 Google이다(보안 점검 시점 44명). 그 사람들의 손이 기억하는 자리에
  카카오를 올리면 spec 사용자 스토리 4("실수로 카카오를 눌러 빈 새 계정")를 이 화면이 직접 만든다. 카카오만 쓰는 신규
  사용자는 노란 버튼을 위치와 상관없이 찾는다.
- **크기**: 두 버튼 모두 `minimumSize: Size(240, 56)`(지금 구글 버튼 값). 글자 배율이 커지면 높이가 따라 늘고 너비는 같다.
- **카카오 버튼 모양**: `FilledButton`에 배경·글자색만 바꿔 앱 테마의 모양(둥근 정도·두께)을 그대로 쓴다 — 두 버튼이 한
  묶음으로 보이게. 색은 `AppPalette`에 브랜드 상수 둘로 둔다: 면 `#FEE500`, 글자·심볼 `#000000`의 85% 불투명.
  **카카오 로그인 디자인 가이드의 준수 의무와 정확한 규격(색·모서리·심볼·허용 문구)** [확인 필요] — developer가 카카오
  개발자 사이트의 "디자인 가이드"를 확인해 규격이 위와 다르면 **가이드를 따른다**(spec P0-1이 그렇게 정했다). 모서리
  값이 가이드에 고정돼 있으면 카카오 버튼만 그 값으로 둔다.
- **심볼(말풍선)**: 카카오가 배포하는 공식 리소스의 PNG를 `assets/`에 1x/2x/3x로 넣는다(새 패키지 아님. SVG는
  `flutter_svg`가 필요해 쓰지 않는다). 손으로 그리지 않는다 — 브랜드 심볼을 근사하면 가이드 위반 위험만 생긴다.
  크기 20dp, `ExcludeSemantics`(버튼 라벨이 의미를 다 말한다).
- **문구**: `카카오로 로그인`(구글 버튼 `구글로 로그인`과 짝). 가이드가 허용 문구를 고정하면(예: `카카오 로그인`) 그 문구로
  바꾸고 보고한다 — 이것이 이 화면에서 유일하게 가이드에 양보하는 문구다.
- **안내 한 줄**: 버튼 묶음 아래 16dp, 최대 너비 280dp, `KeepWordsText`. 항상 보인다(처음 온 사람도, 돌아온 사람도 읽을
  자리가 같다). 문구는 §1.3.
- **눌렀을 때**: 지금 구글 버튼과 같다 — 로딩 상태를 만들지 않는다. 브라우저(카카오 웹 로그인)로 나갔다가 앱으로 돌아오면
  `AuthGate`가 세션을 보고 본 화면으로 바꾼다. 연타는 막지 않는다(지금도 막지 않는다. 브라우저가 한 번 뜬다).
- **재로그인**(결정 3): 카카오에는 `prompt` 같은 재인증 인자를 **붙이지 않는다**. 브라우저에 카카오 로그인이 남아 있으면
  그대로 통과한다.

**상태별 화면**

| 상황 | 보이는 것 |
|---|---|
| 처음 열기 / 로그아웃 뒤 | 위 그림 그대로 |
| 카카오 화면에서 취소·동의 거부 후 돌아옴 | 위 그림 그대로. **토스트 없음**(취소는 사용자가 한 일이라 알릴 것이 없다) |
| 브라우저를 그냥 닫고 돌아옴 | 위 그림 그대로(앱은 아무것도 받지 않는다 — 지금 구글과 같다) |
| 브라우저를 띄우지 못함(`signInWith…`가 던짐) | 토스트 `로그인에 실패했습니다. 다시 시도해주세요.`(기존 `signInFailed`, 구글과 공유) |
| 돌아왔는데 세션 교환이 실패(네트워크 등) | 토스트 `signInFailed` — **"결정 필요" 1** (지금은 구글도 이 경우 아무 말이 없다) |
| 새 계정 생성 성공 | 본 화면(할 일 탭). 빈 목록 안내는 기존 그대로 |

### 1.2 프로필 화면 — 로그인 수단 한 줄

```
  홍길동                         ← 표시 이름(기존, titleLarge)
  카카오 계정으로 로그인했어요       ← 신규, bodySmall · onSurfaceVariant, 이름 바로 아래 4dp
          24
  [ 전적 패널 ] ...
```

- 자리: 표시 이름 **바로 아래**. 근거: 사용자 스토리 4의 순간은 "빈 목록을 보고 놀라 프로필을 연다"이고, 그때 가장 먼저
  읽는 곳이 이름이다. 계정 패널(로그아웃 위)에 두면 스크롤 아래라 알아차림이 늦다.
- 문구: `구글 계정으로 로그인했어요` / `카카오 계정으로 로그인했어요`. 이메일·회원번호 등 식별값은 없다(spec P0-4).
- **수단을 알 수 없으면 줄 자체를 그리지 않는다**(빈 줄·`알 수 없음`을 쓰지 않는다). 지금 세션 구조상 일어나지 않지만,
  잘못된 안내보다 없는 편이 낫다.
- 이 줄은 **프로필 조회와 무관**하다(세션에서 읽는다, §2.3). 프로필 조회가 로딩·실패여도 그 아래에 그대로 보인다.
- **다른 사람에게 보이는 곳**(모집 목록, 대결 상대 카드, 지난 대결)은 **바꾸지 않는다.** 그 화면들은 `profiles`만 읽고,
  로그인 수단은 `profiles`에 없다.

### 1.3 문구 (`lib/core/strings.dart`에 추가, 전부 신규)

| 키(제안) | 문구 |
|---|---|
| `kakaoSignIn` | `카카오로 로그인` (가이드가 허용 문구를 고정하면 그 문구) |
| `signInAccountsNotLinked` | `구글과 카카오 계정은 서로 연결되지 않아요. 처음 가입한 방법으로 로그인해 주세요.` |
| `loginMethodGoogle` | `구글 계정으로 로그인했어요` |
| `loginMethodKakao` | `카카오 계정으로 로그인했어요` |
| `accountDeleteDoneKakaoUnlinkFailed` | `계정을 삭제했습니다. 카카오 연결은 끊지 못했어요. 카카오 계정 설정의 연결된 서비스에서 직접 끊을 수 있어요.` |

- 기존 `googleSignIn`·`signInFailed`·`accountDeleteDone`·`accountDeleteConfirmMessage`는 **그대로**.
- 기본 표시 이름(§3)은 **서버 문자열**이다(트리거가 넣는다). 앱 문자열 파일에 두지 않는다 — 앱은 `display_name`을 표시만 한다.
- 카카오 설정 메뉴의 정확한 이름("연결된 서비스 관리" 등) [확인 필요] — 확인되면 마지막 문구를 그 이름에 맞춘다.

---

## 2. 데이터 흐름

### 흐름 1. 카카오로 로그인(가입 포함)

```
[카카오로 로그인] 탭
  → AuthRepository.signInWithKakao()
      = supabase.auth.signInWithOAuth(OAuthProvider.kakao, redirectTo: 'com.todododo.todododo://login-callback/')
        (queryParams 없음 — 결정 3. scopes 인자도 넘기지 않는다 — 요청 범위는 콘솔이 정한다)
  → 브라우저: 카카오 로그인·동의(닉네임) → Supabase /auth/v1/callback → 앱 딥링크
  → supabase_flutter가 코드 교환 → onAuthStateChange(signedIn)
      [처음이면] auth.users INSERT → 트리거 handle_new_user (§3) → profiles(닉네임 또는 기본 이름) + player_stats
  → authStateProvider data(session) → AuthGate가 MainShell을 그린다
  → todosProvider는 새로 만들어진다(흐름 4) → 빈 목록 또는 내 목록
```

- 리디렉트 주소는 **구글과 같은 상수**를 쓴다(매니페스트 intent-filter와 일치해야 하는 값이 하나뿐이도록). 지금 상수 이름이
  `_googleRedirectUrl`이라 두 공급자가 함께 쓰게 되면 이름만 일반화한다(값 불변).
- `signInWithGoogle()`은 **한 글자도 바꾸지 않는다**(합격선 4).
- 같은 카카오 계정으로 다시 오면 Supabase가 `auth.identities`의 (provider=kakao, 회원번호)로 기존 사용자를 찾는다 —
  트리거가 돌지 않으니 이름도 바뀌지 않는다(spec P0-3 "가입 뒤 닉네임을 바꿔도 따라가지 않는다"가 저절로 지켜진다).
- **계정 합침이 일어나지 않는 이유**(합격선 5): 카카오 사용자에게 이메일이 없으므로 Supabase의 같은 이메일 자동 연결이 걸릴
  재료가 없다. 앱은 `linkIdentity`를 부르지 않는다. 게이트 V3이 "카카오 사용자의 `email`이 null"을 확인한다.

### 흐름 2. 취소·오류가 돌아왔을 때

```
카카오에서 취소/거부 → (카카오) error=access_denied → Supabase → 앱 딥링크에 error 파라미터
  → supabase_flutter가 AuthException을 onAuthStateChange 스트림에 오류로 흘린다 [확인 필요: 정확한 code/message]
  → authStateProvider = AsyncError → AuthGate의 error 갈래 → LoginScreen(지금 그대로)
  → LoginScreen의 ref.listen(authStateProvider):
        isOAuthCancellation(error) == true  → 아무것도 하지 않음(debugPrint만)
        그 밖                               → 토스트 signInFailed + debugPrint   ← "결정 필요" 1
```

- `isOAuthCancellation(Object error)`는 순수 함수다(auth/domain). 판정: `AuthException`이고 `code`가 `access_denied`이거나,
  `message`/`code`에 `access_denied`가 들어 있으면 취소. 그 밖은 전부 실제 오류. **애매하면 오류 쪽**(토스트가 한 번 더 뜨는
  쪽이 오류를 삼키는 쪽보다 낫다 — CLAUDE.md "에러는 삼키지 않는다").
- 카카오 취소가 실제로 어떤 모양으로 오는지는 실기기에서 확인한다(§8.4 M3). 다르면 판정 함수의 조건만 고친다.
- LoginScreen은 `AuthGate`의 `data`·`error` 두 갈래 모두에서 같은 자리·같은 타입이라 같은 element로 유지되고, 그
  `ref.listen`이 오류 전이를 받는다. 토스트는 `ScaffoldMessenger.of(context)`(지금 구글 실패 토스트와 같은 자리).

### 흐름 3. 프로필의 로그인 수단

```
ProfileScreen build
  → ref.read(authRepositoryProvider).currentUser?.appMetadata
  → loginMethodFrom(appMetadata) : LoginMethod? (google | kakao | null)
  → null이면 줄 없음, 아니면 loginMethodGoogle / loginMethodKakao
```

- **읽는 곳: 세션 `User.appMetadata['provider']`**(Supabase가 가입한 공급자를 적는 값). 서버가 쓰고 사용자가 바꿀 수 없는
  `app_metadata`라 신뢰할 수 있고, 이미 기기에 있어 서버 왕복이 없다. 계정 연결이 없으므로(결정 29) 한 계정의 공급자는 평생
  하나이고 이 값이 바뀌지 않는다.
- `loginMethodFrom` 규칙: `provider`가 `'google'` → google, `'kakao'` → kakao. `provider`가 없으면 `providers` 목록이
  **정확히 하나**이고 그것이 둘 중 하나일 때만 그 값. 그 밖(`email` 등 알 수 없는 값, 목록이 둘 이상)은 null.
- 새 테이블·컬럼·RPC 없음. 다른 사용자는 `auth.users`를 읽을 수 없으므로(Supabase 기본) 남의 수단을 알아낼 길이 새로
  생기지 않는다.

### 흐름 4. 계정을 바꿔 로그인해도 이전 계정의 데이터가 보이지 않는다 (P0-5)

**방법: `todosProvider`를 `FutureProvider.autoDispose`로 바꾼다.** 그 밖의 계정 데이터 provider는 이미 전부
`autoDispose`라 손대지 않는다.

```
로그아웃(또는 탈퇴, 세션 소멸)
  → authStateProvider data(session == null) → AuthGate가 MainShell 대신 LoginScreen
  → MainShell·TodoListScreen이 사라지며 todosProvider의 마지막 구독자가 빠진다
  → autoDispose가 todosProvider 상태를 **통째로 버린다**(진행 중이던 조회 결과도 버려진다)
다른 계정으로 로그인
  → MainShell이 새로 뜨며 todosProvider를 처음부터 만든다: AsyncLoading(**이전 값 없음**) → 새 계정 목록
```

**`invalidate(todosProvider)`로는 부족한 이유**(백로그 23행이 제안한 방법을 쓰지 않는 근거): Riverpod은 무효화·의존성
변경으로 다시 계산하는 동안 **직전 값을 들고 있다**. `TodoListScreen`의 `todosAsync.when(...)`은 기본값
(`skipLoadingOnRefresh: true`)이라 새로고침 중에 **직전 데이터를 그린다** — 즉 B로 로그인한 직후 A의 목록이 조회가 끝날
때까지 보인다(수용 기준 "한 순간도 보이지 않는다" 위반). `MainShell._startDueAlarms`도 `todos.value`를 읽어 A의 목록으로
기한 알림을 맞춘다. 세션 id를 `ref.watch`하게 하는 방법도 같은 이유(직전 값 보존)로 부족하고, 로그아웃 순간 아직 떠 있는
`MainShell`의 리스너가 빈 목록·오류를 홈 위젯에 발행해 "로그인 안내"를 덮는 위험까지 생긴다. 구독자가 없어지는 시점에 상태를
버리는 `autoDispose`만이 "이전 값이 남지 않는다"를 구조로 보장한다.

**바뀌는 것과 바뀌지 않는 것**
- 로그인한 동안에는 `MainShell`이 늘 `ref.listen(todosProvider)`로 붙어 있으므로 탭을 오가도 목록이 버려지지 않는다
  (조회 횟수 불변). 버려지는 것은 `MainShell`이 사라질 때, 곧 로그아웃·탈퇴·세션 소멸 때뿐이다.
- `MainShell._startDueAlarms`의 "이미 받아 둔 목록으로 한 번 맞추기"는 이제 늘 `cached == null`이 되고, 첫 조회가 끝나는
  순간 기존 `ref.listen(todosProvider)`(loading → data 전이)가 보정을 맡는다. 그 코드는 무해하게 남거나 developer 판단으로
  주석만 고친다(79-88행 주석의 "받아들이는 한계" 문단은 사실이 아니게 되므로 **고쳐야 한다**).
- `TodoWidgetTapSettler`(일반 `Provider`)는 `todosProvider`를 `read`·`invalidate`만 하고 `watch`하지 않는다 —
  autoDispose provider를 비-autoDispose provider가 `watch`하면 안 되는 제약에 걸리지 않는다. developer는 그 밖에
  `todosProvider`를 `watch`하는 **provider**가 없는지 확인한다(지금은 `TodoListScreen` 위젯 하나뿐).
- 테스트 가능성을 위해 `todosProvider` 본문의 사용자 id를 전역 `supabase.auth.currentUser!` 대신
  `ref.read(authRepositoryProvider).currentUser!`에서 읽는다(`read` — 인증 변화에 다시 계산되지 않게). 테스트가
  `authRepositoryProvider`를 가짜로 바꿔 계정 전환을 재현할 수 있다(§8.3).
- 그대로 두는 것: `selectedTabProvider`(마지막 탭 위치 — 계정 데이터가 아니다), 기기 로컬 기록(VS 인트로 봤음, 위젯 안내 봤음).
  로그아웃 때의 위젯 캐시 비우기·기한 알림 취소·푸시 토큰 정리는 이미 있고 바꾸지 않는다.

### 흐름 5. 카카오 가입자의 탈퇴 (P0-7)

```
[계정 삭제] → 확인 대화상자(문구 그대로) → AuthRepository.deleteAccount()
  → functions.invoke('delete-account')
     Edge delete-account (§4)
       1. JWT로 호출자 확인 — 이때 사용자 레코드(identities 포함)를 함께 받는다
       2. 카카오 회원번호 추출(카카오 identity가 없으면 '해당 없음')        ← 신규, delete_account **전에**
       3. 참가 대결 id 수집                                              (그대로)
       4. delete_account RPC(호출자 JWT) — 실패하면 오류 응답, 끊기도 하지 않는다 (그대로)
       5. 증거 사진 삭제, 실패는 로그만                                   (그대로)
       6. 카카오면 연결 끊기 1회 시도(5초 제한), 실패는 로그만               ← 신규
       7. 응답 { deleted: true, kakaoUnlink: 'done' | 'failed' | 'notKakao' }
  → 앱: 기한 알림 취소 · 위젯 캐시 비우기 · auth.signOut()            (그대로)
  → kakaoUnlink == 'failed' 이면 토스트 accountDeleteDoneKakaoUnlinkFailed,
    그 밖(필드 없음 포함)은 기존 accountDeleteDone
```

- 회원번호를 **`delete_account` 전에** 읽는 이유: 그 RPC가 `auth.users`를 지우면 `auth.identities`도 함께 사라져 끊을
  대상을 알 수 없다.
- 끊기를 **`delete_account` 뒤에** 하는 이유: 탈퇴가 실패하면 "아무것도 바뀌지 않음"을 지키기 위해서다(끊기만 먼저 되고
  탈퇴가 실패하면 사용자는 계정이 남았는데 카카오 연결만 끊긴 어정쩡한 상태가 된다).
- 사용자에게 실패를 **알리는** 이유: 사용자가 할 수 있는 일(카카오 설정에서 직접 끊기)이 있고, 알리지 않으면 spec 사용자
  스토리 6의 "탈퇴가 덜 된 것 같은" 경험을 설명 없이 남긴다. 탈퇴 자체는 성공이므로 실패 토스트(`accountDeleteFailed`)가
  아니라 **완료 토스트의 다른 판**이다.
- 앱 쪽 응답 해석은 순수 함수 `accountDeletionResultFrom(data)` → `done | doneKakaoUnlinkFailed`. 응답에 필드가 없거나
  모양이 다르면 `done`(구버전 Edge와도 맞는다 — 배포 순서에 묶이지 않는다).

---

## 3. 표시 이름 규칙과 새 마이그레이션

### 3.1 규칙

| 가입 경로 | 표시 이름 |
|---|---|
| Google (지금 그대로) | `raw_user_meta_data.full_name`, 없으면 `email` — **식과 순서 그대로** |
| 카카오 | 닉네임 후보 키 중 첫 "쓸 수 있는 값", 없으면 기본 이름 **`이름 없는 도전자`** |
| 그 밖·판별 불가 | Google 식을 그대로 쓰고, **그 결과가 null일 때만** 기본 이름(가입 실패 대신) |

**기본 이름 `이름 없는 도전자`를 고른 근거**(spec P0-3이 디자이너에게 맡겼다)
- 이메일·빈 문자열·숫자가 아니다(합격선 2).
- `연습 봇`(역할 명사 + 봇), `탈퇴한 사용자`(상태 + 사용자)와 어휘가 겹치지 않는다. "사용자"를 쓰지 않아 묘비와 헷갈리지 않고,
  "봇"을 쓰지 않아 봇과 헷갈리지 않는다.
- **로그인 수단을 드러내지 않는다.** `카카오 사용자` 같은 이름은 모집 목록·상대 카드에 수단을 공개하는데, spec P0-4가 그것을
  본인 프로필에만 두라고 했다.
- 일련번호·임의 꼬리표를 붙이지 않는다 — 식별 번호처럼 보이고(합격선 2의 취지), 이름 바꾸기 화면이 없어 사용자에게 뜻 없는
  값이 평생 붙는다. 같은 이름이 여럿일 수 있는 것은 Google 실명이 겹치는 것과 같은 한계로 받아들인다.

**"쓸 수 있는 값"**(카카오 후보 하나하나에 적용)
1. 앞뒤 공백을 걷어 낸 뒤 비어 있지 않다.
2. 이메일 꼴(`^[^@\s]+@[^@\s]+\.[^@\s]+$`)이 아니다 — 어떤 경로로든 이메일이 닉네임 키에 실려 와도 이름이 되지 않게.
3. 사용자의 `email` 값과 같지 않다(대소문자 무시).
4. 카카오 회원번호(`sub`·`provider_id` 키의 값)와 같지 않다 — 식별 번호가 이름이 되지 않게.
5. ("결정 필요" 2를 추천대로 받으면) `연습 봇`·`탈퇴한 사용자`와 정확히 같지 않다.

**닉네임 후보 키 순서**(게이트 V4로 확정 [확인 필요]): `full_name` → `name` → `preferred_username` → `user_name` →
`nickname`. 길이 상한은 두지 않는다(Google 쪽에도 없다. 카카오 닉네임 길이는 카카오가 제한한다).

**카카오 판별**(둘 중 하나라도 참이면 카카오):
- `new.raw_app_meta_data ->> 'provider' = 'kakao'` — 가입 INSERT 시점에 이미 채워져 있는지 [확인 필요, 게이트 V4]
- `new.raw_user_meta_data ->> 'iss'`에 `kakao.com`이 들어 있다 — 위가 INSERT 뒤에 채워지는 경우의 보험

두 판별이 다 빗나가도 셋째 줄("그 밖")이 가입 실패를 막는다. 이메일이 없는 카카오 사용자에게 Google 식은 `full_name`(=닉네임일
가능성이 큼) 또는 null을 주고, null이면 기본 이름이 된다 — **어느 경우에도 이메일이 이름이 되지 않는다**(카카오에서 이메일을
받지 않으므로 `new.email`이 null).

**Google 동작이 바뀌지 않는다는 근거**: Google 가입은 판별에서 카카오가 아니고, 셋째 줄의 식은 지금 식과 같다. 결과가 달라지는
유일한 입력은 "이름도 이메일도 없음"인데 그것은 지금 **가입 실패**였고 Google은 늘 이메일을 준다 — 성공하던 Google 가입의 결과는
하나도 바뀌지 않는다.

### 3.2 마이그레이션 (새 파일 하나, 예: `supabase/migrations/20261125120000_kakao_login.sql`)

| 대상 | 내용 |
|---|---|
| `public.kakao_display_name(p_meta jsonb, p_email text) returns text` (신규) | §3.1 후보·검사 규칙을 적용해 첫 쓸 수 있는 값, 없으면 `'이름 없는 도전자'`. `immutable`, 순수. **트리거 내부용**: `revoke execute ... from public, anon, authenticated`(앱이 부를 이유가 없다). SECURITY DEFINER 아님 → `auth.uid()` 가드 대상 아님 |
| `public.is_kakao_signup(p_app_meta jsonb, p_user_meta jsonb) returns boolean` (신규) | §3.1 판별 두 조건. 권한은 위와 같다 |
| `public.handle_new_user()` (`create or replace`) | 이름 계산만 바뀐다. `player_stats` 행 생성은 **그대로**. 트리거 함수라 `auth.uid()` 가드가 없는 것도 그대로(기존 함수와 같은 예외) |
| 권한 | `create or replace` 뒤 `revoke execute on function public.handle_new_user() from public, anon, authenticated;`를 다시 적는다(20260915120100과 같은 모양) |
| 트리거 `on_auth_user_created` | 바꾸지 않는다(함수만 교체) |
| 백필 | **없다.** 기존 사용자의 이름을 건드리지 않는다(spec P0-3, 백로그 44행은 별도 결정) |

`handle_new_user()`의 새 모양(의사 코드, 최종 SQL은 developer):

```sql
v_name := case
  when public.is_kakao_signup(new.raw_app_meta_data, new.raw_user_meta_data)
    then public.kakao_display_name(new.raw_user_meta_data, new.email)
  else coalesce(new.raw_user_meta_data ->> 'full_name', new.email)   -- 지금 식 그대로
end;
v_name := coalesce(v_name, '이름 없는 도전자');                          -- 실패 대신 기본 이름
insert into public.profiles (id, display_name) values (new.id, v_name);
insert into public.player_stats (user_id) values (new.id);
```

- 헬퍼 둘을 따로 두는 이유는 **표로 시험하기 위해서**다(§8.1) — 규칙의 경우가 많은데 매번 `auth.users`에 행을 넣어 보는 것보다
  함수 호출 하나로 고정하는 편이 읽기 쉽다. 트리거 자체는 대표 경우를 실제 INSERT로 따로 시험한다.
- 새 테이블이 없으므로 RLS 추가 없음. 봇 행(seed로 직접 넣음)은 이 트리거를 지나지 않는다 — 영향 없음.
- 기본 이름 상수가 SQL 두 자리(헬퍼, 트리거의 마지막 coalesce)에 나오지 않게 developer가 한 자리로 모으면 더 좋다
  (예: 트리거가 헬퍼에 `null` 메타를 넘겨 기본값을 받기). 표현은 developer 몫.

---

## 4. 탈퇴 시 카카오 연결 끊기 (Edge Function)

### 4.1 어디서, 무엇으로
- **자리: 기존 Edge `delete-account` 안.** 새 함수를 만들지 않는다(탈퇴 한 번에 호출 한 번, 앱 변경 최소).
- **카카오 API**: 사용자 연결 끊기 — `POST https://kapi.kakao.com/v1/user/unlink`,
  헤더 `Authorization: KakaoAK {앱 Admin 키}`, `Content-Type: application/x-www-form-urlencoded;charset=utf-8`,
  본문 `target_id_type=user_id&target_id={회원번호}`. 성공 응답 본문 `{"id": 회원번호}` [확인 필요 — 카카오 REST API 문서의
  "연결 끊기" 항목으로 주소·헤더·본문·성공 모양·"이미 연결이 끊긴 사용자" 오류 코드를 확인한다].
- **왜 Admin 키인가**: 사용자 액세스 토큰으로 끊는 방법도 있지만, Supabase는 카카오가 준 공급자 토큰을 서버에 보관하지 않고
  앱에서도 로그인 직후 한 번만 받을 수 있다 [확인 필요]. 탈퇴 시점에 그 토큰을 가진 곳이 없으므로 **서버가 Admin 키 + 회원번호로**
  끊는다.
- **시크릿**: Admin 키는 앱의 모든 사용자에 대해 관리 API를 부를 수 있는 강한 키다.
  - `supabase secrets set KAKAO_ADMIN_KEY=...`로만 넣는다(계정 소유자, CLAUDE.md 규칙). 코드·커밋·`env.json`·앱에 두지 않는다.
  - 함수는 `Deno.env.get('KAKAO_ADMIN_KEY')`로만 읽고, **어떤 로그에도 키·요청 헤더를 찍지 않는다.**
  - 요청 주소는 코드에 고정된 `kapi.kakao.com` 하나뿐이다(입력에서 주소를 받지 않는다).
  - 키가 설정되지 않았으면 요청을 보내지 않고 `failed`로 본다(로그 `KAKAO_ADMIN_KEY 미설정`) — 조용히 건너뛰지 않는다.

### 4.2 함수 흐름의 변경점

| 단계 | 지금 | 바뀐 뒤 |
|---|---|---|
| 호출자 확인 | `getUserId(req)` → id | 같은 `auth.getUser()` 호출로 **사용자 레코드 전체**(identities 포함)를 받는 헬퍼를 `_shared/auth.ts`에 하나 더 둔다. 기존 `getUserId`는 그대로(다른 함수가 쓴다) |
| 회원번호 추출 | — | `kakaoTargetId(user)` (§4.3). 카카오가 아니면 `null` + `notKakao` |
| `delete_account` | 그대로 | 그대로. 실패하면 지금처럼 `SERVER_ERROR`, 끊기는 시도하지 않는다 |
| 증거 사진 | 그대로 | 그대로 |
| 연결 끊기 | — | 카카오면 `unlinkKakaoUser(fetch, adminKey, targetId)` 1회, `AbortSignal.timeout(5000)`. 재시도 없음 |
| 응답 | `{deleted: true}` | `{deleted: true, kakaoUnlink: 'done' \| 'failed' \| 'notKakao'}` |

- 카카오인데 회원번호를 뽑지 못했으면(레코드 모양이 예상과 다름) `failed` + 로그. 탈퇴는 계속한다.
- **재시도·대기열을 두지 않는다.** 실패는 드물 것이고, 사용자에게 직접 끊는 길을 알리며, 운영자는 로그로 수동 처리할 수 있다.
  재시도 장치는 새 테이블·cron이 필요해 범위가 커진다.
- `verify_jwt` 설정은 바꾸지 않는다(지금처럼 JWT 필요).

### 4.3 순수 함수 (`supabase/functions/_shared/kakao_unlink.ts`, deno test 대상)

| 함수 | 계약 |
|---|---|
| `kakaoTargetId(user): string \| null` | `user.identities` 중 `provider === 'kakao'`인 첫 행에서 `identity_data.sub` → `identity_data.provider_id` → 행의 `id` 순으로 첫 값(게이트 V5로 순서 확정). **숫자만으로 된 1~20자**가 아니면 null. 카카오 행이 없으면 null |
| `buildUnlinkRequest(adminKey, targetId): {url, init}` | §4.1의 주소·헤더·본문. 본문은 `URLSearchParams`로 인코딩 |
| `interpretUnlinkResponse(status, body, targetId): 'done' \| 'failed'` | 200이고 `body.id`가 `targetId`와 같으면 `done`. "이미 연결되지 않은 사용자" 오류 코드면 `done`(끊으려던 상태가 이미 이뤄져 있다) [확인 필요: 코드 값]. 그 밖 전부 `failed` |
| `unlinkKakaoUser(fetcher, adminKey, targetId): Promise<'done' \| 'failed'>` | 키가 비면 요청 없이 `failed`. `fetcher`가 던지거나(네트워크·시간 초과) 본문이 JSON이 아니면 `failed`. **로그 문구에 키를 넣지 않는다** |

`fetcher`를 인자로 받는 것은 `EvidenceStore`를 가짜로 바꿔 끼우는 기존 방식과 같은 이유다(네트워크 없이 deno test).

### 4.4 운영자가 알 수 있는 기록
- 실패 시 `console.error('delete-account: 카카오 연결 끊기 실패 - <사유>, target_id=<회원번호>')`. 사유는 HTTP 상태·카카오 오류
  코드까지만(응답 본문 전체·헤더는 남기지 않는다).
- 회원번호를 남기는 이유: 운영자가 같은 API로 손수 다시 끊으려면 그 값이 필요하다. 계정은 이미 지워져 다른 곳에 그 값이 없다.
  → 이 판단은 **"결정 필요" 3**에 올린다(탈퇴 뒤 식별자가 로그에 남는 것이므로).
- Supabase Edge 로그 보존 기간 [확인 필요 — 플랜별]. 오너는 배포 후 주기적으로 `delete-account` 로그에서 이 문구를 찾는다
  (DEPLOY.md 8번 "에러 로그 확인"에 한 줄 추가).

---

## 5. API 계약 요약

### 5.1 앱 → Supabase Auth
| 호출 | 인자 | 비고 |
|---|---|---|
| `auth.signInWithOAuth(OAuthProvider.google, …)` | **불변** | |
| `auth.signInWithOAuth(OAuthProvider.kakao, redirectTo: 'com.todododo.todododo://login-callback/')` | `queryParams`·`scopes` 없음 | 신규 |
| `auth.currentUser.appMetadata['provider']` | 읽기만 | 로그인 수단 표시 |

### 5.2 DB
| 대상 | 종류 | 권한 |
|---|---|---|
| `handle_new_user()` | 트리거 함수 교체 | public·anon·authenticated 회수(기존과 같음) |
| `kakao_display_name(jsonb, text)` | 신규 순수 함수 | public·anon·authenticated 회수 |
| `is_kakao_signup(jsonb, jsonb)` | 신규 순수 함수 | public·anon·authenticated 회수 |

새 테이블·컬럼·RPC·RLS 없음. `delete_account()` 불변.

### 5.3 Edge `delete-account`
- 요청: 지금 그대로(POST, 본문 없음, `Authorization: Bearer <사용자 JWT>`).
- 응답(성공): `200 {"deleted": true, "kakaoUnlink": "done" | "failed" | "notKakao"}`. 실패 응답은 지금 그대로.
- 새 시크릿: `KAKAO_ADMIN_KEY`.

### 5.4 도메인 규칙과의 대조 (CLAUDE.md)
- 대결 상태 전이·판정·점수: 손대지 않는다.
- 탈퇴 규칙(묘비, 끝나지 않은 대결 `cancelled`, 사용자 FK는 `profiles`): `delete_account`를 바꾸지 않으므로 그대로다.
- "AI 데이터 제공 동의"는 로그인 수단과 무관 — 카카오에서 받은 값(닉네임·회원번호)은 표시 이름으로만 쓰이고 Gemini 요청에
  들어가는 값(대결 제목·기준·증거 사진)에 섞이지 않는다. 동의 고지 문구 불변(spec P0-6의 5).
- 판정 로직 위치: 표시 이름 결정은 서버 트리거, 로그인 수단은 서버가 쓴 `app_metadata`를 앱이 표시만 한다.
- 범위 밖 미리 만들기 없음: 계정 연결용 추상화, 공급자 목록 테이블, 프로필 사진 칼럼, 연결 끊기 알림 수신 엔드포인트를 만들지
  않는다. `LoginMethod`는 지금 있는 두 값뿐이다.

---

## 6. 정책 문서 변경 목록 (문구는 오너 승인 사항)

### 6.1 `privacy.html` (`todododo-legal`)
1. **수집 항목**을 로그인 수단별로 가른다.
   - Google 로그인 시: 이메일, 이름(지금 문구를 이 줄로 옮긴다)
   - **카카오 로그인 시: 카카오 회원번호, 닉네임**(이메일 받지 않음 — 결정 1)
2. **수집 방법(출처)**: "카카오 로그인 과정에서 주식회사 카카오로부터 제공받음". **위탁 표에는 올리지 않는다**(결정 4-1).
3. **이용 목적**: 회원 식별·로그인 유지. 닉네임은 다른 이용자에게 보이는 표시 이름으로 쓰인다(모집 목록·대결 상대). 가입 뒤
   카카오 닉네임을 바꿔도 앱의 이름은 따라 바뀌지 않는다.
4. **탈퇴 시 처리 표**: 카카오 회원번호는 계정과 함께 삭제, **카카오 연결은 탈퇴 시 자동으로 끊는다.** 자동 끊기가 실패하면
   이용자가 카카오 계정 설정에서 직접 끊을 수 있다(앱이 그 사실을 알린다). ("결정 필요" 3을 받으면: 실패 시 운영자가 처리하기
   위해 회원번호가 서버 로그에 [보존 기간] 남는다.)
5. **알림 토큰(결정 4-3, 같은 개정)**: "대결 알림을 받는 경우 기기 알림 토큰(FCM)" — 이용 목적 대결 알림 발송, 로그아웃·탈퇴 시
   삭제(`delete_account`가 `device_push_tokens`를 지운다). FCM 제공자(Google)를 위탁 표에서 어떻게 적을지는 오너가 지금 표의
   "Google" 행과 맞춰 정한다.
6. **바꾸지 않는 것**: AI 데이터 제공 동의 관련 항목(국외 이전·Google LLC 제공 항목).
7. **시행일** 갱신(한 번).

### 6.2 `account-deletion.html`
1. 삭제/보존 표에 "카카오 연결 — 탈퇴 시 자동 끊기(실패 시 카카오 설정에서 직접)" 한 줄.
2. **로그인 수단별 삭제 경로**: 카카오 가입자는 "앱에서 카카오로 로그인 → 프로필 → 계정 삭제"가 **확실한 경로**임을 맨 앞에 둔다
   (결정 4-2).
3. 이메일 요청 양식: 카카오 가입자는 표시 이름·대략의 가입 시기·로그인 수단(카카오)을 적어 요청할 수 있되, **본인 확인이 되지
   않으면 처리하지 못할 수 있다**고 적는다(결정 4-2).

### 6.3 Play Console 데이터 보안 양식 (`DEPLOY.md` 5번의 초안)
- 이름: Google 이름 **또는 카카오 닉네임**.
- 이메일 주소: **Google 가입자만**.
- 사용자 ID: **카카오 회원번호** — "결정 필요" 4(Google 쪽 식별자도 함께 적을지).
- 기기 또는 기타 ID: FCM 알림 토큰(결정 4-3과 짝) — 해당 분류가 맞는지 오너 확인.
- 그 밖(사용자 생성 콘텐츠, 사진, 암호화, 삭제 요청 가능) 그대로.

### 6.4 `DEPLOY.md`·기타 (메인 세션 몫)
- 1번 "Play 앱 서명 참고": 카카오도 브라우저 경유라 키 해시 등록이 필요 없는지 게이트 결과로 한 줄([확인 필요]가 풀리면).
- 5번 "이 앱이 수집하는 것" 문장: 카카오 회원번호·닉네임, 알림 토큰 추가.
- 7번 최종 확인: "Redirect URLs" 줄에 카카오도 같은 주소를 쓴다는 것, `KAKAO_ADMIN_KEY` 시크릿 설정 확인, §8.4의 릴리스 빌드
  실기기 항목.
- 8번 배포 후: `delete-account` 로그에서 "카카오 연결 끊기 실패" 찾기.
- `TODO_BACKLOG.md` 23행(todosProvider 무효화) 삭제 — 흐름 4로 해소. 44행(Google 기본 이름)은 **그대로 남긴다**.
- `CLAUDE.md` 도메인 규칙의 탈퇴 조항에 "카카오 가입자는 탈퇴 뒤 연결 끊기를 한 번 시도한다(실패는 탈퇴를 막지 않는다)" 한 구절을
  더할지 메인 세션이 판단.

---

## 7. 오너가 할 콘솔 설정 ↔ 이 설계의 연결

| ID | 콘솔 작업 (spec "오너가 직접 해야 할 설정") | 설계가 기대는 자리 | 확인 방법 |
|---|---|---|---|
| G1 | 카카오: 애플리케이션 생성, 카카오 로그인 활성화 | 흐름 1 전체 | 게이트 V2 |
| G2 | 카카오: Redirect URI = Supabase 카카오 공급자 화면에 표시되는 콜백 주소 그대로 (`https://<project-ref>.supabase.co/auth/v1/callback` 꼴로 알려져 있다 [확인 필요]) | 흐름 1의 "→ Supabase /auth/v1/callback" | 게이트 V2(틀리면 `KOE006` 류) |
| G3 | 카카오: 동의항목 — 닉네임 **필수 동의**, 그 외 전부 사용 안 함(이메일 포함) | 합격선 3, §3 규칙, 흐름 1 "합침 없음" | 게이트 V1·V3 |
| G4 | 카카오: 보안 → Client Secret 생성·활성화. Supabase에 넣을 Client ID가 **REST API 키**인지 [확인 필요] | 흐름 1 | 게이트 V2 |
| G5 | Supabase: Authentication → Providers → Kakao 활성화, G4 값 입력. "이메일 없는 사용자 허용" 류 설정이 있으면 **켠다** [확인 필요] | 합격선 1 | 게이트 V3 |
| G6 | Supabase: Redirect URLs에 `com.todododo.todododo://login-callback/`(이미 Google용으로 있어야 함) | 흐름 1 마지막 딥링크 | 게이트 V2 |
| G7 | 카카오: 앱 키 중 **Admin 키**를 `supabase secrets set KAKAO_ADMIN_KEY=<값>`으로 등록. 값은 어디에도 붙여 넣지 않는다 | §4 연결 끊기 | §8.4 M6 |
| G8 | `supabase functions deploy delete-account` | §4 | §8.4 M6 |
| G9 | 카카오: 플랫폼(Android 패키지명·키 해시) — **브라우저 경유 방식에 필요한지** [확인 필요]. 필요하다고 나오면 디버그·업로드·Play 앱 서명 키 **세 벌** 해시 | 합격선 6 | §8.4 M1(Play에서 받은 빌드) |
| G10 | 카카오: 개인정보처리방침 URL 등록 요구 여부 [확인 필요]. 요구되면 `todododo-legal` 게시(DEPLOY 0번)가 선행 | 출시 | 콘솔에서 확인 |
| G11 | 카카오: 비즈 앱 아닌 상태의 인원·기능 제한 여부 [확인 필요] | 합격선(사업자 등록 없이) | 콘솔 문서 |

- 순서: G1~G6 → (마이그레이션 원격 적용) → 게이트 V1~V6 → 화면 작업 → G7·G8 → 탈퇴 확인 → 정책 문서(G10) → 릴리스 빌드 확인.
- 콘솔 작업과 시크릿 등록은 **계정 소유자만** 한다. developer는 값을 보지 않는다.

---

## 8. 테스트 계획

### 8.1 마이그레이션 — `supabase/tests/kakao_signup_smoke.sql` (신규, 기존 스모크와 같은 롤백 방식)
`supabase db query --linked -f supabase/tests/kakao_signup_smoke.sql` → `SMOKE RESULT ok=true`.

**헬퍼 표 시험** (`kakao_display_name`, `is_kakao_signup`)

| # | 입력 | 기대 |
|---|---|---|
| H1 | `{"full_name":"두두"}` | `두두` |
| H2 | `{"name":"두두"}` / `{"preferred_username":"두두"}` / `{"nickname":"두두"}` 각각 | `두두` |
| H3 | `{"full_name":"  두두  "}` | `두두`(공백 걷음) |
| H4 | `{}` / `null` | `이름 없는 도전자` |
| H5 | `{"full_name":"   "}` | `이름 없는 도전자` |
| H6 | `{"full_name":"a@b.co"}` | `이름 없는 도전자`(이메일 꼴) |
| H7 | `{"full_name":"x"}`이 아니라 `{"full_name":"Me@X.com"}` + `p_email='me@x.com'` | `이름 없는 도전자` |
| H8 | `{"full_name":"4411","sub":"4411"}` | `이름 없는 도전자`(회원번호와 같음) |
| H9 | `{"full_name":"   ","name":"두두"}` | `두두`(첫 쓸 수 있는 값) |
| H10 | ("결정 필요" 2 채택 시) `{"full_name":"연습 봇"}` / `{"full_name":"탈퇴한 사용자"}` | `이름 없는 도전자` |
| K1 | app `{"provider":"kakao"}` | true |
| K2 | app `{}`, user `{"iss":"https://kapi.kakao.com/v2/user/me"}` | true |
| K3 | app `{"provider":"google"}`, user `{"iss":"https://accounts.google.com"}` | false |
| K4 | 둘 다 null | false |

**트리거 실제 INSERT 시험** (`auth.users`에 행을 넣고 `profiles`·`player_stats` 확인)

| # | 행 | 기대 |
|---|---|---|
| T1 | Google 꼴: app `{"provider":"google"}`, user `{"full_name":"구글이"}`, email 있음 | `구글이` (불변) |
| T2 | Google 꼴: `full_name` 없음, email 있음 | **그 이메일** (불변 — 합격선 4가 지키는 것) |
| T3 | 기존 스모크 꼴: `raw_app_meta_data` 없음, `{"full_name":"스모크U"}` | `스모크U` (기존 스모크들이 깨지지 않는다) |
| T4 | 카카오: app `{"provider":"kakao"}`, user `{"full_name":"카카오닉"}`, email null | `카카오닉`, `player_stats` 행 있음 |
| T5 | 카카오: 닉네임 키 없음, email null | 가입 성공, `이름 없는 도전자` (합격선 1·2) |
| T6 | 카카오: 닉네임 없음, **email 있음** | `이름 없는 도전자` (이메일이 이름이 되지 않는다) |
| T7 | 판별 불가: app·user 메타 모두 `{}`, email null | 가입 성공, `이름 없는 도전자` |
| T8 | Google 꼴 `{"full_name":"연습 봇"}` | `연습 봇` (Google 규칙은 이 기능이 바꾸지 않는다) |

### 8.2 Edge 순수 함수 — `supabase/functions/_shared/kakao_unlink_test.ts` (`deno test supabase/functions/_shared/`)
- `kakaoTargetId`: 카카오 identity(`identity_data.sub` 숫자) → 그 값 / `sub` 없고 `provider_id`만 → 그 값 / Google identity만 → null /
  identities 없음 → null / 값이 숫자가 아님(`"abc"`, `""`, 21자) → null / Google·카카오가 함께 있으면(일어나지 않지만) 카카오 값.
- `buildUnlinkRequest`: 주소가 정확히 `https://kapi.kakao.com/v1/user/unlink`, 메서드 POST, `Authorization`이
  `KakaoAK <키>`, 본문이 `target_id_type=user_id&target_id=<id>`.
- `interpretUnlinkResponse`: 200 + 같은 id → done / 200 + 다른 id → failed / 이미 끊긴 사용자 코드 → done / 401·400·500 → failed.
- `unlinkKakaoUser`: 빈 키 → 요청 0회 + failed / fetcher가 던짐 → failed / 시간 초과(던지는 가짜) → failed / 본문 JSON 아님 → failed /
  정상 → done. **찍힌 로그 문자열 어디에도 키가 없다**(console.error를 가로채 검사).

### 8.3 Dart 유닛·위젯
- `loginMethodFrom`(auth/domain): `{"provider":"google"}`→google, `{"provider":"kakao"}`→kakao, `{"provider":"email"}`→null,
  `{}`→null, `null`→null, `{"providers":["kakao"]}`→kakao, `{"providers":["google","kakao"]}`→null.
- `isOAuthCancellation`: `AuthException(code: 'access_denied')`→true, message에 `access_denied`→true, 네트워크류 예외→false,
  `AuthException('invalid flow state')`→false.
- `accountDeletionResultFrom`: `{"deleted":true,"kakaoUnlink":"failed"}`→doneKakaoUnlinkFailed, `"done"`·`"notKakao"`·필드 없음·
  `null`·문자열 → done.
- **P0-5 회귀 테스트(필수)**: `ProviderContainer`에 `authRepositoryProvider`(현재 사용자 A↔B를 바꿀 수 있는 가짜)와
  `todoRepositoryProvider`(id별 목록을 주는 가짜)를 덮어쓴다. ① 구독 → A 목록 확인 ② 구독 해제 + 한 틱(폐기) ③ 사용자 B로 바꿈
  ④ 다시 구독 → **첫 상태가 값 없는 로딩이고(`value == null`) 이어서 B 목록**. A의 목록이 한 번이라도 관측되면 실패. 지금
  코드(autoDispose 아님)에서는 ④에서 A가 보여 실패해야 한다 — developer는 수정 전에 이 테스트가 실패하는 것을 먼저 확인한다.
- 위젯(선택이지만 권장): `LoginScreen` — 버튼 둘과 안내 한 줄이 보이고, 구글 버튼이 위다 / 덮어쓴 `authStateProvider` 스트림에
  취소 오류를 흘리면 SnackBar 없음, 다른 오류를 흘리면 `signInFailed` SnackBar(“결정 필요” 1 채택 시). 기존
  `test/features/auth/logout_widget_cache_test.dart`의 덮어쓰기 방식을 따른다.
- 프로필의 수단 줄은 위젯 테스트 선택 사항(MVP 규칙).

### 8.4 수동 확인 — **Play 내부 테스트 트랙에서 받은 릴리스 빌드**, 실기기 (합격선 6)
카카오톡 **설치된 기기와 설치되지 않은 기기 각각**에서:
- M1 처음 카카오 로그인 → 동의 화면에 닉네임만 → 할 일 탭(빈 목록) → 프로필에 닉네임과 `카카오 계정으로 로그인했어요`.
- M2 로그아웃 → 카카오로 다시 → **같은 계정**(방금 만든 할 일이 있다). 계정 선택을 다시 묻지 않는 것이 정상(결정 3).
- M3 카카오 동의 화면에서 취소 → 로그인 화면, 토스트 없음, 다시 누르면 정상 진행. 이때 `debugPrint`에 찍힌 오류 모양을 적어
  `isOAuthCancellation`과 맞는지 본다(디버그 빌드로 한 번).
- M4 Google 계정으로 할 일 몇 개 → 로그아웃(앱 끄지 않음) → 카카오 로그인 → **이전 할 일이 한 순간도 보이지 않는다.** 반대 방향도.
- M5 Google 로그인이 이전과 같다 — 매번 계정 선택이 뜨고 기존 계정·이름 그대로.
- M6 카카오 계정 탈퇴 → `계정을 삭제했습니다.` → 카카오 계정 설정의 연결된 서비스에서 투두두두가 사라졌다 → 같은 카카오로 다시
  로그인하면 **빈 새 계정**(닉네임으로 새로 만들어짐, 동의 화면이 다시 뜬다).
- M7 (가능하면) `KAKAO_ADMIN_KEY`를 일부러 비운 스테이징이 없으므로 **생략 가능**: 실패 토스트 문구는 위젯·유닛 테스트로 대신한다.
- M8 카카오톡 설치 기기에서 브라우저 로그인 체감(아이디·비밀번호를 쳐야 하는지)을 기록해 보고한다 — 결정 5의 후속(백로그).
- 각 항목 뒤 `flutter analyze` 0, `flutter test` 통과, `deno test supabase/functions/_shared/` 통과.
- 새 패키지가 없으므로 릴리스 빌드 위험은 낮지만, 에셋(카카오 심볼) 추가가 있으므로 `flutter build apk --release
  --dart-define-from-file=env.json`을 한 번 돌리고 **종료 코드를 따로 찍는다**(CLAUDE.md).

---

## 9. 범위 밖으로 확인하고 만들지 않는 것
- 계정 연결·통합, 공급자 추상화 계층, 카카오 SDK·카카오톡 앱 전환 로그인(결정 5 → 백로그), 카카오 친구·공유·메시지,
  프로필 사진, 표시 이름 바꾸기 화면, Google 기본 이름 변경(백로그 44행), 카카오 "연결 끊기 알림" 수신, 연결 끊기 재시도 대기열,
  로그인 수단의 타인 공개, 자기 자신과의 대결 방지.

---

## 결정 필요

> 2026-11-25 오너 확정: 1번 두 공급자 모두 적용, 2번 예약 이름과 같으면 기본 이름으로 바꾼다, 3번 연결 끊기 실패 시 회원번호를 로그에 남긴다(방침에 한 줄 추가), 4번 Google 식별자(사용자 ID)를 같은 개정에 적는다. 5번은 §0 게이트 결과에 따른다. **design 승인.**

1. **돌아온 로그인이 실패했을 때(딥링크 오류) 토스트를 Google에도 띄울까요?**
   - 사실: 지금은 브라우저에서 돌아온 뒤의 실패(코드 교환 실패·네트워크 등)가 `AuthGate`에서 `debugPrint`만 되고 아무 말이 없다.
     구글도 마찬가지다. 카카오는 **취소도 이 경로로 돌아오므로** 취소와 실제 오류를 가르는 판정(흐름 2)이 어차피 필요하다.
   - (A) 판정을 두 공급자에 똑같이 쓴다 — 취소는 조용히, 그 밖은 `signInFailed` 토스트. **추천.** 근거: spec 수용 기준
     "실제 실패는 토스트로 알린다(에러를 삼키지 않는다)"와 CLAUDE.md 규칙을 지금 어기고 있는 자리를 함께 고치는 것이고, 로그인
     흐름(계정 선택·이름 규칙)은 바뀌지 않는다. 오류가 공급자별로 갈리지 않아 구현도 하나다.
   - (B) 카카오로 시작한 시도에만 적용한다 — 합격선 4를 문자 그대로 지킨다. 대가: 마지막으로 누른 버튼을 기억하는 상태가 생기고,
     구글의 오류 삼킴이 남는다.

2. **카카오 닉네임이 시스템 이름(`연습 봇`, `탈퇴한 사용자`)과 정확히 같으면 기본 이름으로 바꿀까요?**
   - (A) 바꾼다(카카오 가입에만, 정확히 같을 때만). **추천.** 근거: 카카오 닉네임은 사용자가 마음대로 정하므로 이 기능이 처음으로
     "가입만으로 시스템 이름을 쓰는 길"을 연다. 상대 카드에서 사람이 봇이나 묘비로 보이면 판정·결과 화면을 오해하게 된다.
     비용은 SQL 한 줄과 시험 한 줄이다.
   - (B) 그대로 둔다 — 표시 이름 사칭 문제는 백로그 45행(UPDATE 정책)과 함께 별도로 다룬다. Google 실명이 `연습 봇`인 경우도
     막지 않으므로 일관성은 이쪽이 낫다.

3. **카카오 연결 끊기가 실패하면 서버 로그에 그 사람의 카카오 회원번호를 남길까요?**
   - (A) 남긴다. **추천.** 근거: spec P0-7이 "운영자가 알 수 있게 기록"을 요구했고, 계정이 이미 지워져 운영자가 손으로 다시 끊으려면
     이 값밖에 없다. Edge 로그는 플랫폼이 정한 짧은 기간만 보존된다. 대가: 방침의 탈퇴 처리 표에 "연결 끊기 실패 시 회원번호가
     서버 로그에 일정 기간 남는다"를 적어야 한다(§6.1-4).
   - (B) 남기지 않는다 — 실패 사실과 사유만 남긴다. 운영자는 실패를 알지만 처리할 수 없고, 사용자 스스로 끊는 안내(토스트)에만
     기댄다.

4. **Play 데이터 보안의 "사용자 ID"와 방침의 수집 항목에 Google 쪽 식별자도 함께 적을까요?**
   - 사실: 카카오 회원번호를 "수집"으로 적는 근거(spec P0-2: 로그인에 따라오는 식별자)는 Google에도 똑같이 적용된다 — Supabase가
     `auth.identities`에 Google 계정 식별자를 이미 저장하고 있다. 지금 방침·데이터 보안 초안에는 그 항목이 없다.
   - (A) 같은 개정에서 함께 적는다. **추천.** 시행일을 한 번만 바꾸고, 카카오만 적으면 두 수단의 서술이 어긋난다.
   - (B) 카카오만 적고 Google 쪽은 오너가 따로 판단한다.

5. **(조건부 — 지금 답할 필요 없음)** §0 검증 게이트의 V1~V3이 콘솔·대시보드 설정으로 통과되지 않으면(예: Supabase가 이메일
   범위를 빼지 못하게 요청해 카카오가 오류를 내거나 동의 화면에 이메일이 뜬다), 구현을 멈추고 spec 결정 1을 다시 올린다. 그때
   메인 세션은 게이트 결과(동의 화면에 무엇이 떴는지, 오류 코드)를 함께 보여 준다.
