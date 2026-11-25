# kakao-login 구현 계획

## 이 문서의 범위

입력은 `docs/specs/kakao-login/spec.md`(294행 오너 확정)와 `design.md`(609행 오너 확정) 둘이다.
작업을 **두 차례**로 나눈다.

- **1차분(이번)** — 오너의 카카오·Supabase 콘솔 설정과 §0 검증 게이트 결과에 **기대지 않는 것만**.
  P0-5(계정 전환 잔상), 표시 이름 마이그레이션, 탈퇴 시 카카오 연결 끊기(Edge + 앱 응답 처리),
  로그인 실패 분류(구글·카카오 공통), 프로필 로그인 수단 한 줄.
- **2차분(오너 콘솔 설정 G1~G6 + 게이트 V1~V6 뒤)** — 카카오 버튼·안내 한 줄, `signInWithOAuth(kakao)`
  배선, 게이트 결과에 맞춘 후보 키·회원번호 추출 순서 조정, 실기기 확인, 정책 문서.

developer는 원격 DB·Edge를 건드리지 않는다(`db push`·`functions deploy`·`secrets set`은 전부 오너 몫).

---

## 설계·기획과의 충돌 — 없음

CLAUDE.md 도메인 규칙·코딩 규칙, dev-standards, spec.md, design.md를 대조했고 **구현을 멈춰야 할 충돌은 없다.**
판단을 남겨 두는 자리 세 곳:

1. **`handle_new_user()`에 `auth.uid()` 가드가 없다** — CLAUDE.md는 SECURITY DEFINER 함수 첫 줄에 가드를
   요구하지만, 이 함수는 `auth.users` INSERT 트리거라 호출자가 GoTrue(서비스 쪽)이고 `auth.uid()`가 없다.
   기존 함수(20260915120100)도 같은 이유로 가드가 없고 EXECUTE를 전부 회수해 두었다. 교체본도 같은 모양을
   유지한다(design §3.2 "기존 함수와 같은 예외"). 새 헬퍼 둘은 SECURITY DEFINER가 아니다.
2. **로그인 취소는 토스트 없이 `debugPrint`만 남긴다**(design 흐름 2, 오너 확정 1번). CLAUDE.md "에러는 삼키지
   않는다"의 대상이 아니라고 본다 — 취소는 사용자가 한 일이지 오류가 아니고, 애매하면 오류 쪽(토스트)으로
   떨어지게 판정 함수를 짰다. CLAUDE.md의 `debugPrint` 예외 목록에 한 줄을 더할지는 메인 세션 판단.
3. **카카오 연결 끊기 실패 시 회원번호를 서버 로그에 남긴다**(오너 확정 3번). 키·요청 헤더·응답 본문은 남기지 않는다.

---

## 1차분 — 작업 순서 (이번 세션, 구현 완료)

| # | 내용 | 파일 | 커밋 |
|---|---|---|---|
| 1 | 이 계획서 | `docs/specs/kakao-login/plan.md` | docs |
| 2 | **P0-5** `todosProvider`를 `FutureProvider.autoDispose`로. 사용자 id를 전역 `supabase.auth` 대신 `ref.read(authRepositoryProvider)`에서 읽는다(테스트에서 계정 전환 재현). 회귀 테스트(계정 A→구독 해제→B로 바꿈→재구독 시 첫 상태가 값 없는 로딩, A 목록이 한 번도 관측되지 않음). `MainShell._startDueAlarms` 주석의 "받아들이는 한계" 문단을 사실에 맞게 고침(코드는 무해하게 남김). 기존 테스트 둘의 전제 주석·구독 유지 보정. `TODO_BACKLOG.md` 23행 삭제 | `lib/features/todo/domain/todo_providers.dart`, `lib/core/navigation/main_shell.dart`, `test/features/todo/todos_account_switch_test.dart`(신규), `test/features/todo/todo_widget_settler_test.dart`, `test/widget_test.dart`, `TODO_BACKLOG.md` | fix |
| 3 | **표시 이름 마이그레이션**: `kakao_display_name(jsonb, text)`, `is_kakao_signup(jsonb, jsonb)`(둘 다 immutable SQL, EXECUTE 전부 회수), `handle_new_user()` 교체(Google 식 그대로, 카카오면 헬퍼, 결과가 null이면 기본 이름 `이름 없는 도전자`). 기본 이름 문자열은 헬퍼 한 자리에만 둔다(트리거는 `kakao_display_name(null, null)`로 받는다). 예약 이름(`연습 봇`·`탈퇴한 사용자`)과 같으면 기본 이름(오너 확정 2번, 카카오에만). 스모크 SQL(design §8.1의 H1~H10, K1~K4, T1~T8) | `supabase/migrations/20261125120000_kakao_login.sql`, `supabase/tests/kakao_signup_smoke.sql` | feat |
| 4 | **Edge `delete-account` 카카오 연결 끊기**: 순수 함수 `kakaoTargetId`/`buildUnlinkRequest`/`interpretUnlinkResponse`/`unlinkKakaoUser` + deno 테스트, `_shared/auth.ts`에 사용자 레코드를 받는 `getUser` 추가(기존 `getUserId` 불변), `delete_account` **전에** 회원번호 추출·**뒤에** 끊기 1회(5초), 응답에 `kakaoUnlink` | `supabase/functions/_shared/kakao_unlink.ts`, `kakao_unlink_test.ts`, `_shared/auth.ts`, `delete-account/index.ts` | feat |
| 5 | **앱의 탈퇴 응답 처리**: `accountDeletionResultFrom(data)` → `done`/`doneKakaoUnlinkFailed`(모양이 다르면 `done` — 구버전 Edge와도 맞는다), `AuthRepository.deleteAccount()`가 그 결과를 돌려줌, 프로필이 `accountDeleteDoneKakaoUnlinkFailed` 토스트 | `lib/features/auth/data/account_deletion_result.dart`, `auth_repository.dart`, `profile_screen.dart`, `strings.dart`, 테스트 | feat |
| 6 | **로그인 실패 분류**(오너 확정 1번 — 두 공급자 공통): `isOAuthCancellation(error)` 순수 함수, `LoginScreen`이 `authStateProvider`의 오류 전이를 듣고 취소면 `debugPrint`만, 그 밖은 `signInFailed` 토스트. 구글 버튼·호출(`prompt=select_account`)은 한 글자도 안 바꿈 | `lib/features/auth/domain/sign_in_failure.dart`, `login_screen.dart`, 테스트 | feat |
| 7 | **프로필 로그인 수단 한 줄**: `loginMethodFrom(appMetadata)` 순수 함수, `myLoginMethodProvider`(세션의 `app_metadata`를 `authStateProvider`에서 읽는다 — 서버 왕복 없음), 이름 바로 아래 `bodySmall`·`onSurfaceVariant`, 알 수 없으면 줄 없음 | `lib/features/auth/domain/login_method.dart`, `auth_providers.dart`, `profile_screen.dart`, `strings.dart`, 테스트 | feat |

### 1차분에서 design과 표현이 다른 곳 (판단 근거)
- **로그인 수단을 `authStateProvider`의 세션에서 읽는다**(design 흐름 3은 `ref.read(authRepositoryProvider).currentUser`).
  같은 값(세션의 `User.appMetadata`)이다. 이렇게 한 이유: `ProfileScreen`은 `MainShell`의 `IndexedStack`에
  늘 함께 그려지는데, 기존 위젯 테스트 여러 곳이 `authRepositoryProvider`를 덮어쓰지 않는다. `build`에서
  `authRepositoryProvider`를 직접 읽으면 그 테스트들이 Supabase 미초기화로 던진다. `authStateProvider`는
  `StreamProvider`라 그 실패를 `AsyncValue` 안에 담으므로 줄이 안 그려질 뿐 화면이 깨지지 않는다(design
  "수단을 알 수 없으면 줄을 그리지 않는다"와 같은 결과).
- **기본 이름 한 자리**: design §3.2 마지막 문단의 제안(트리거가 헬퍼에 `null` 메타를 넘겨 기본값을 받기) 그대로.
- **회귀 테스트가 "지금 코드에서 실패"하는지**: 이 컨테이너에 Flutter가 없어 **실행으로 확인하지 못했다.**
  순서를 2a(사용자 id 출처만 바꿈 — 테스트가 계정 전환을 흉내 낼 수 있게) → 2b(테스트) → 2c(autoDispose)로
  짜서 2b 시점의 코드에서 실패하도록 설계했고(구독 해제 뒤에도 비-autoDispose provider가 A의 `AsyncData`를
  들고 있어 재구독의 첫 값이 A다), 오너/다음 세션이 `git stash`로 2c만 빼고 돌려 확인할 수 있다. 셋은 한
  커밋에 묶었다(중간 상태가 빨간 테스트를 커밋에 남기지 않게).

---

## 2차분 — 작업 순서 (오너 콘솔 설정·게이트 뒤)

design §7의 순서를 그대로 쓴다.

1. **오너**: G1~G6(카카오 앱·로그인 활성화·Redirect URI·동의항목 닉네임만·Client Secret / Supabase Kakao 공급자,
   Redirect URLs). **카카오 로그인 디자인 가이드 준수 의무·규격**, **Admin 키 위치**, 개인정보처리방침 URL 요구 여부(G10)·
   비즈 앱 아닌 상태의 제한(G11)도 이때 확인.
2. **오너**: 1차분 마이그레이션 `20261125120000_kakao_login.sql`을 원격에 적용하고 스모크
   `supabase db query --linked -f supabase/tests/kakao_signup_smoke.sql` → `SMOKE RESULT ok=true` 확인.
   (design §0 주의: 마이그레이션을 **게이트보다 먼저** — 아니면 닉네임 키가 `full_name`이 아닐 때 가입이 not null 위반으로 실패한다.)
3. **developer**: `AuthRepository.signInWithKakao()` 한 줄(`OAuthProvider.kakao`, 구글과 같은 리디렉트 상수, `queryParams`·`scopes`
   없음 — 상수 이름 `_googleRedirectUrl`은 값 그대로 이름만 일반화)을 붙여 **디버그 빌드**로 게이트 V1~V6을 돌리고
   결과를 아래 "## 게이트 결과"에 적는다(키 이름만, 값은 적지 않는다).
   - V1·V2·V3 중 하나라도 콘솔 설정으로 해결되지 않으면 **멈추고** 메인 세션에 보고(spec 결정 1 재상정).
4. **developer**: 게이트 결과 반영
   - V4 → `kakao_display_name`의 후보 키 순서·`is_kakao_signup`의 판별 조건. 바뀌면 **새 마이그레이션**으로 `create or replace`
     (이미 적용된 1차분 파일은 고치지 않는다) + 스모크 표 갱신.
   - V5 → `kakaoTargetId`의 추출 순서(`identity_data.sub` → `identity_data.provider_id` → 행의 `id`) + deno 테스트.
   - 카카오 REST 문서 확인 → 연결 끊기 주소·헤더·본문·성공 모양, **"이미 연결이 끊긴 사용자" 오류 코드**를
     `ALREADY_UNLINKED_CODES`(지금 비어 있음 — 아래 참고)에 넣는다.
   - M3(실기기 취소)의 `debugPrint` 모양 → `isOAuthCancellation` 조건.
5. **developer**: 로그인 화면(design §1.1) — 카카오 버튼(구글 아래 12dp, `FilledButton` + `AppPalette` 브랜드 상수 둘
   `#FEE500`/`#000000` 85%, 공식 심볼 PNG 1x/2x/3x 에셋 20dp `ExcludeSemantics`), 안내 한 줄(16dp, 최대 280dp,
   `KeepWordsText`), 문구 `kakaoSignIn`·`signInAccountsNotLinked`. 가이드가 다르면 가이드를 따른다.
   위젯 테스트: 버튼 둘·안내 한 줄·구글이 위. 이 화면은 기존 화면 수정이라 한 커밋.
6. **오너**: G7 `supabase secrets set KAKAO_ADMIN_KEY=...`, G8 `supabase functions deploy delete-account`.
   - 배포 순서: 앱은 응답에 `kakaoUnlink`가 없어도 `done`으로 읽으므로 Edge와 앱 중 어느 쪽이 먼저 나가도 된다.
7. **실기기**(design §8.4 M1~M8) — **Play 내부 테스트 트랙에서 받은 릴리스 빌드**, 카카오톡 설치·미설치 기기 각각.
   카카오 심볼 에셋이 들어가므로 `flutter build apk --release --dart-define-from-file=env.json`을 돌리고 종료 코드를 따로 찍는다.
8. **정책 문서**(아래 목록) — 오너 문구 승인 뒤 게시. G10이 요구하면 카카오 콘솔 등록 전에.
9. `DEPLOY.md`·`CLAUDE.md` 한 줄씩(메인 세션 몫, design §6.4).

### `interpretUnlinkResponse`의 "이미 끊긴 사용자" 코드
카카오 문서로 확인하지 못해 **빈 목록으로 두었다**(추측한 코드를 넣으면 실제 실패를 성공으로 읽을 수 있다).
그동안은 이미 끊긴 사용자도 `failed`로 읽혀 사용자에게 "직접 끊을 수 있어요" 토스트가 한 번 더 뜰 뿐이다
(안전한 쪽). 2차분 4번에서 채운다.

---

## 정책 문서 변경 목록 (이 저장소 밖 `C:\workspaces\todododo-legal` — developer는 건드리지 않았다)

design §6을 그대로 옮긴다. 문구는 오너 승인 사항.

- `privacy.html`
  1. 수집 항목을 수단별로: Google 로그인 시 이메일·이름·**Google 계정 식별자**(오너 확정 4번) / 카카오 로그인 시
     **카카오 회원번호, 닉네임**(이메일 받지 않음).
  2. 수집 출처: "카카오 로그인 과정에서 주식회사 카카오로부터 제공받음". **위탁 표에는 올리지 않는다**(결정 4-1).
  3. 이용 목적: 회원 식별·로그인 유지, 닉네임은 다른 이용자에게 보이는 표시 이름(모집 목록·대결 상대). 가입 뒤 카카오
     닉네임을 바꿔도 따라 바뀌지 않음. 닉네임이 없거나 시스템 이름과 같으면 `이름 없는 도전자`.
  4. 탈퇴 처리 표: 회원번호는 계정과 함께 삭제, 카카오 연결은 탈퇴 시 자동으로 끊음. 실패하면 이용자가 카카오 설정에서
     직접 끊을 수 있고(앱이 알림), **운영자 처리를 위해 회원번호가 서버 로그에 [보존 기간] 남는다**(오너 확정 3번).
  5. 알림 토큰(FCM) 항목(결정 4-3, 같은 개정).
  6. AI 데이터 제공 동의 관련 항목은 바꾸지 않는다.
  7. 시행일 한 번 갱신.
- `account-deletion.html`: 삭제/보존 표에 카카오 연결 줄, 카카오 가입자는 "앱에서 카카오로 로그인 → 프로필 → 계정 삭제"를
  확실한 경로로 맨 앞에, 웹 요청은 표시 이름·가입 시기·수단을 받되 본인 확인이 안 되면 처리 못 할 수 있다(결정 4-2).
- Play 데이터 보안 초안(`DEPLOY.md` 5번): 이름 = Google 이름 또는 카카오 닉네임, 이메일 = Google 가입자만, 사용자 ID =
  카카오 회원번호 + Google 식별자(오너 확정 4번), 기기 ID = FCM 토큰(분류 오너 확인).

---

## 검증 기록 (1차분)

이 컨테이너에는 Flutter·Supabase CLI·Postgres가 없다. Deno는 npm 패키지(`deno` 2.9.6)로 설치했다.

| 검사 | 결과 |
|---|---|
| `deno test supabase/functions/_shared/` | 아래 "실행 결과" 참고 |
| `deno check supabase/functions/delete-account/index.ts` | 아래 참고 |
| 마이그레이션·스모크 SQL | 아래 참고 |
| `flutter analyze` / `flutter test` | **미실행**(Flutter 없음). 오너/다음 세션이 돌린다 |

실행 결과는 1차분 마지막 커밋에서 채운다.

---

## 게이트 결과 (2차분에서 채운다)

| # | 결과 | 비고 |
|---|---|---|
| V1 | | |
| V2 | | |
| V3 | | |
| V4 | | |
| V5 | | |
| V6 | | |
