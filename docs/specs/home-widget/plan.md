# home-widget 구현 계획

입력: `docs/specs/home-widget/spec.md`(오너 승인, 2026-11-03 확정 + 2026-11-04 시점 변경),
`docs/specs/home-widget/design.md`(오너 승인, 끝의 "## 결정 기록" 2건 포함). 순서는 design.md
13장 "구현 단계 분할" 7단계를 그대로 따른다. 문서 형식·운영 규칙은 `docs/specs/push-notification/plan.md`를
선례로 삼는다.

**이번 작업 범위는 1~3단계다.** 4~7단계는 아래에 계획만 적어 두고 구현하지 않는다.

## 공통 규칙
- 각 단계 끝: `flutter analyze` 이슈 0 + `flutter test` 전부 통과. 네이티브가 바뀐 단계(2)는
  `flutter build apk --debug`까지.
- **스키마 변경이 없다**(design 11.1). 마이그레이션·Edge Function·SQL을 만들지 않고 `supabase/`를
  건드리지 않는다. 그래서 **원격 적용 승인 지점이 없다**(design 결정 기록: 구현 중 오너에게 다시 물을
  승인 지점이 없다).
- 커밋은 `<type>: <한국어 설명>` + 이유 본문 + `Co-Authored-By` 줄. 새 화면 하나 = 커밋 하나.
  **이 세션은 커밋하지 않는다** — 오너 승인을 받아 메인 세션이 단계별로 나눠 커밋한다. 그래서 각 단계의
  "파일" 목록이 커밋 분할의 기준이다.
- 사용자에게 보이는 문자열은 한국어, 전부 `lib/core/strings.dart`. 식별자는 영어.
- **다른 세션이 같은 작업 트리에서 `push-notification` 4단계를 작업 중이다.** 건드리지 않는 것:
  `lib/core/push/`, `supabase/` 전체, `lib/main.dart`. `pubspec.yaml`은 한 줄(+주석)만,
  `lib/core/strings.dart`는 **파일 끝의 새 구역**, `lib/core/navigation/main_shell.dart`는 **독립 블록**만
  고친다(design 10장이 `main.dart`를 열지 않는 설계를 이미 만들어 두었다).

## 착수 전 확인 (2026-11-04)
- 기준선: `flutter analyze` 이슈 0, `flutter test` **427개 통과**(push-notification 4단계 상태).
- 이름 충돌 없음: `todo_widget`·`TodoWidgetPayload`·`TodoWidgetProvider`·`home_widget`이 `lib/`·`android/`에
  하나도 없다(첫 배선).
- `home_widget`을 해석해 보면 **0.10.0**이 온다(`flutter pub add home_widget --dry-run`). 이 판은 JNI
  바인딩(`jni`, `code_assets`, `hooks`, `record_use`, `objective_c`, `path_provider`)을 함께 끌고 온다 —
  **AGP 9.1.0 / Kotlin 2.4.0 / Flutter 3.47.0(Dart 3.13) 조합에서 실제로 빌드되는지가 2단계의 첫
  검증 항목이다**(design 1.1). 안 되면 같은 자리에서 더 낮은 판으로 내리거나 design 1.1의 후퇴 경로
  (값 전달만 `shared_preferences`, 나머지는 Kotlin 직접)로 간다.
- **폰트는 넣지 않는다**(design 2.5가 미리 정한 기준에 따른 분기, 임의 판단이 아니다):
  `assets/fonts/galmuri/Galmuri11.ttf`가 **5.37MB**로 design이 못 박은 2.5MB 한도를 넘는다. 따라서
  `res/font/`와 `android/app/build.gradle.kts`의 폰트 복사 과제를 **만들지 않고**, 위젯은 시스템 폰트 +
  레트로 색만 맞춘다. 결과적으로 2단계에서 Gradle 파일을 전혀 건드리지 않는다.
- 작업 트리: `docs/specs/home-widget/`, `.claude/agent-memory/`가 미추적. `supabase/functions/_shared/`에
  다른 세션의 미추적 파일이 있다(건드리지 않는다).

## CLAUDE.md·dev-standards와의 관계 (충돌 점검 결과)
대조한 결과 **구현을 멈춰야 하는 충돌은 없다.** 확인한 항목:
- CLAUDE.md "배포 전 별도 feature" 목록에 `home-widget`이 이미 들어가 있다(2026-11-04 오너 결정). spec
  본문에 남은 "배포 후 첫 업데이트" 서술은 spec의 결정 기록이 덮는다.
- 도메인 규칙(판정·상태 전이·점수·한도·탈퇴)을 이 feature가 한 줄도 바꾸지 않는다. 위젯은 `todos`만
  읽고 `todos.is_done = true`만 쓴다(design 원칙 1, 11.2). 대결 테이블에 닿는 경로를 만들지 않는다.
- "판정 로직은 클라이언트가 아니라 DB/Edge" — 위젯에 판정·승패·점수가 없으므로 해당 사항이 없다.
- "테스트 없이 판정 로직 수정 금지" — 판정 로직을 수정하지 않는다. 대신 위젯의 모든 판단(상태 선택·
  문구·줄 수·Uri 해석)을 Dart 순수 함수로 모아 유닛 테스트한다(design 원칙 2, 12장).
- RLS·RPC 권한·`auth.uid()` 가드·`is distinct from` 규칙은 **새 SQL이 없어** 적용 지점이 없다.
- dev-standards: `lib/features/todo/{data,domain}` 3분할, `fromMap`/`toJson`은 data, provider는 domain,
  provider 이름은 `<대상><역할>Provider`, 네이티브 경계는 얇은 래퍼 + provider로 감싸 테스트에서 가짜로
  바꾼다(`PushMessaging` 선례), 단순 CRUD는 RPC 없이 `from(table)` 직접(이미 그렇다), 테스트는
  `test/features/todo/...`에 미러링 — 모두 그대로 따른다.
- **의도된 예외 2건은 design이 7단계에 CLAUDE.md 갱신을 배정해 해소한다**(임의 판단이 아니다):
  1. **위젯 캐시 발행·갱신 실패는 `debugPrint`만 남기고 토스트를 띄우지 않는다**(design 원칙 4, 3.2).
     위젯은 관문이 아니고 발행이 일어나는 자리(`MainShell`의 `ref.listen`, 백그라운드 isolate)에 토스트를
     띄울 맥락이 없다. VS 인트로 예외와 같은 성격이다. CLAUDE.md 코딩 규칙의 예외 목록에 한 줄 더하는
     것은 **7단계 몫**이고 이번 범위에서 하지 않는다.
     - 단, **체크(쓰기) 실패는 삼키지 않는다** — 위젯 안 한 줄(`체크하지 못했어요...`)로 말한다(spec P0).
  2. 네이티브가 가져야 하는 문자열 3개(위젯 선택기 이름·설명·캐시 없을 때의 한 줄)는 XML 리소스로만
     전달할 수 있다. 손으로 중복 정의하지 않고 **생성기가 `AppStrings`에서 뽑아** 쓰므로 "문자열은
     `lib/core/strings.dart`에 모은다"는 규칙의 취지(출처가 한 곳)를 지킨다(design 2.4).

---

## 1단계 — 투두 위젯 캐시 페이로드 (스키마 변경 없음)

### 파일
1. `lib/features/todo/data/todo_widget_payload.dart` (신규) — 순수 함수만. 플랫폼 타입이 섞이지 않는다.
   - `TodoWidgetItem`(id, title), `TodoWidgetNoteTone { muted, danger }`
   - `TodoWidgetPayload` — design 2.2의 JSON 스키마 그대로(`v`·`items`·`totalCount`·`centerText`·
     `note`·`noteTone`·`moreFormat`·`pendingId`·`pendingAtMs`·`pendingLabel`·`tapTarget`·`updatedAtMs`)
   - 상태 팩토리 6종(design 2.3의 8가지 상태를 만든다): `fromTodos(todos, now:)`(정상·할 일 없음·
     전부 완료 세 갈래를 안에서 가른다), `loggedOut(now:)`, `loading(now:)`, `fetchFailed(previous, now:)`
     (이전 목록 있음/없음 두 갈래), `checkFailed(previous)`, `pending(previous, id, now)`
   - `toJson()`/`fromJson()`/`encode()`/`decode()` — 왕복
   - `visibleRows(items, totalCount, rowCount)` → `(rows, moreCount)`. 네이티브가 그대로 옮길 규칙을
     Dart에 둔다(design 12장)
   - `todoWidgetActionOf(Uri?)` → `TodoWidgetAction`(`check(id)` / `none`), `widgetTargetOf(Uri?)` →
     `TodoWidgetTarget`(`todo` / `none`). uuid 모양 검사(선례: `notification_payload.dart`의 `battleIdOf`)
   - 기준 시각 문장(`오전 9:14`) 만들기
2. `lib/core/strings.dart` — **파일 끝에 새 구역 `// 홈 화면 위젯`** 추가. design 2.3·6.3·2.4의 문구
   전부(로그아웃·조회 중·빈 목록·전부 완료·조회 실패·체크 실패·`쓰는 중`·`그 외 %d개`·note 두 종·
   오전/오후·위젯 이름·위젯 설명·캐시 없을 때의 한 줄).
3. `test/features/todo/todo_widget_payload_test.dart` (신규) — design 12장 표의 1~3행.

### 커밋
- `feat: 투두 위젯 캐시 페이로드` — Dart 2파일 + 테스트. 앱 동작은 그대로다(아무도 아직 부르지 않는다).

### 검증
- `flutter analyze` 이슈 0, `flutter test` 전부 통과(기준선 + 신규 유닛).
- 유닛이 덮는 것: 미완료만 담기, 생성순 유지, 8개 상한, 제목 80자 자르기, `totalCount`, 상태 8종의
  문구·tone 선택, 기준 시각 문장(오전/오후 경계 0시·12시 포함), `visibleRows`의 "그 외 N개" 계산,
  JSON 왕복, Uri 해석(정상·uuid 아님·키 없음·엉뚱한 스킴·null).

---

## 2단계 — 홈 화면 투두 위젯 추가 (네이티브, 스키마 변경 없음)

### 파일
1. `pubspec.yaml` — `home_widget: ^0.10.0` **한 줄** + 이유 주석 2줄(design 1.1의 문장). `pubspec.lock`도
   함께 바뀐다(다른 세션과 겹치면 머지 후 `flutter pub get`을 다시 돌린다).
2. `android/app/src/main/kotlin/com/todododo/todododo/TodoWidgetProvider.kt` (신규) — `AppWidgetProvider`.
   `onUpdate`·`onAppWidgetOptionsChanged`에서 `HomeWidgetPreferences`의 `todo_widget_payload`를 읽어
   그린다. 네이티브의 판단은 둘뿐이다: 높이 → 줄 수(design 6.2 표), `%d` 끼우기. 캐시가 없거나 `v`를
   모르면 대체 한 줄(`@string/todo_widget_no_cache`).
3. `android/app/src/main/res/layout/todo_widget.xml` (신규) — design 6.1의 고정 6줄 레이아웃 + 더 있음 줄 +
   note + 가운데 안내.
4. `android/app/src/main/res/xml/todo_widget_info.xml` (신규) — design 6.2의 메타데이터
   (`updatePeriodMillis=1800000`, 설정 화면 없음).
5. `android/app/src/main/res/drawable/widget_frame.xml`·`widget_row.xml`·`widget_check.xml` (신규) —
   2dp 선 + 바닥 두께(`PixelFrame.raised` 흉내).
6. `tool/generate_widget_resources.dart` (신규) + 생성 결과
   `android/app/src/main/res/values/widget_resources.xml` — 색은 `RetroPalette`, 문자열 3개는
   `AppStrings`에서 뽑는다. `res/values/colors.xml`(아이콘 생성기 소유)을 덮지 않는 별도 파일이다.
7. `android/app/src/main/AndroidManifest.xml` — `<receiver android:name=".TodoWidgetProvider"
   android:exported="false">` 블록 하나. 새 권한 없음.
8. `lib/features/todo/data/todo_widget_host.dart` (신규) — `home_widget` 호출을 감싼 얇은 계층
   (`save`/`read`/`update`). 테스트에서 가짜로 바꿀 지점.
- **만들지 않는 것**: `res/font/`, `android/app/build.gradle.kts` 변경(폰트 한도 초과, 위 "착수 전 확인"),
  `android/settings.gradle.kts` 변경, 체크 PendingIntent(6단계), 런치 Uri 처리(5단계).

### 커밋
- `feat: 홈 화면 투두 위젯 추가` — 이유 본문에 `home_widget`을 넣는 근거(design 1.1)를 적는다.

### 검증
- `flutter pub get` 성공, `flutter analyze` 이슈 0, `flutter test` 전부 통과.
- **`flutter build apk --debug` 통과**(AGP/Kotlin 호환, `minSdk`, manifest 등록, 리소스 이름).
  깨지면 그 자리에서 해결하고, 못 하면 멈추고 보고한다 — 깨진 상태로 3단계로 가지 않는다.
- `flutter test tool/generate_widget_resources.dart`로 XML을 생성하고, 생성 결과가 커밋에 들어간다.
- 실기기·에뮬레이터에서 위젯을 올려 보는 것은 오너 몫(design 14장). 이 단계에서는 캐시가 없어
  대체 한 줄만 보이는 것이 정상이다.

---

## 3단계 — 앱의 할 일 변경을 위젯에 반영 (스키마 변경 없음)

### 파일
1. `lib/features/todo/domain/todo_widget_service.dart` (신규) — `publish(payload)` = `host.save` +
   `host.update`. 직전 JSON을 들고 같은 값은 다시 발행하지 않는다. 실패는 `debugPrint`만.
   `lastPublished`를 들고 있어 `fetchFailed`·`checkFailed`·`pending`이 "직전 목록"을 쓸 수 있다.
2. `lib/features/todo/domain/todo_providers.dart` — `todoWidgetHostProvider`,
   `todoWidgetServiceProvider` 추가(파일 끝).
3. `lib/core/navigation/main_shell.dart` — `initState`에서 `publish(loading())`,
   `build`에 `ref.listen(todosProvider, ...)` **독립 블록** 하나(데이터→`fromTodos`, 에러→`fetchFailed`).
4. `test/features/todo/todo_widget_publish_test.dart` (신규) + `test/features/todo/todo_widget_fakes.dart`
   (신규, 가짜 host + override 묶음. 선례: `test/core/push/push_fakes.dart`).
5. `test/widget_test.dart` — `MainShell`을 띄우는 기존 두 테스트에 가짜 host override를 넣는다
   (플러그인이 없는 테스트에서 발행이 조용히 실패하는 것을 막는다. push 2단계의 `pushOverrides()`와 같은 이유).

### 커밋
- `feat: 앱의 할 일 변경을 위젯에 반영`

### 검증
- `flutter analyze` 이슈 0, `flutter test` 전부 통과.
- 위젯 테스트가 덮는 것: 할 일 목록이 오면 발행이 일어난다, 조회 실패 때 직전 목록을 유지하고 note만
  바뀐다, 같은 상태를 두 번 발행하지 않는다, `MainShell`이 뜨는 순간 `loading()`이 먼저 간다.
- **여기까지 끝나면 읽기 전용 위젯이 동작한다**(spec의 "읽기 전용 후퇴" 지점).

---

## 4단계 — 로그아웃·탈퇴 시 위젯 캐시 비우기 (계획만, 이번 범위 아님)
- 파일: `lib/features/auth/data/auth_repository.dart`(`signOut`·`deleteAccount` 두 경로 모두),
  `lib/features/auth/presentation/auth_gate.dart`(`ConsumerStatefulWidget`으로 바꿔 세션 소멸 감지),
  테스트.
- 커밋: `feat: 로그아웃·탈퇴 시 위젯 캐시 비우기`.
- 검증: 세 방어선(로그아웃·탈퇴·세션 소멸) 각각에서 `loggedOut()`이 발행되는지 위젯 테스트.

## 5단계 — 위젯 탭으로 할 일 화면 열기 (계획만)
- 파일: `lib/features/todo/data/todo_widget_host.dart`(런치 Uri·`widgetClicked` 스트림 추가),
  `lib/features/auth/presentation/auth_gate.dart`(`initState`에서 초기 Uri + 구독, `dispose`에서 해제),
  `TodoWidgetProvider.kt`(`HomeWidgetLaunchIntent`), 테스트.
- 커밋: `feat: 위젯 탭으로 할 일 화면 열기`. manifest에 새 `intent-filter`를 더하지 않는다(design 5장).

## 6단계 — 위젯에서 할 일 완료 처리 (계획만, 위험이 몰린 단계)
- **먼저 정리할 것(2026-11-05 리뷰)**: `TodoWidgetPayload.checkFailed(null)`은 `updatedAtMs: 0`을 쓴다 —
  이 갈래가 note를 갖게 되면 1970년 기준 시각(`오전 12:00 기준`)이 찍힐 수 있다. 같은 갈래의
  `noteTone: danger`도 지금은 아무 데도 쓰이지 않는다(`centerText`만 쓴다). 체크 경로를 붙일 때 함께 고친다.
- 파일: `lib/features/todo/data/todo_widget_callback.dart`(`@pragma('vm:entry-point')` 진입점,
  **`main.dart`가 아니다**), 결정 부분을 뗀 순수 함수(`TodoWidgetCheckDecision`),
  `auth_gate.dart`(콜백 등록 + `IsolateNameServer` 포트 등록/해제), `main_shell.dart` 또는 포트 수신자가
  쓰기를 맡는 배선, `TodoWidgetProvider.kt`(체크 칸 PendingIntent), 테스트.
- 커밋: `feat: 위젯에서 할 일 완료 처리`.
- **design 4.2의 W5(포트 핸드오프)를 그대로 쓴다.** 백그라운드에서 무조건 `Supabase.initialize`하는
  설계로 바꾸지 않는다 — 앱이 조용히 로그아웃되는 경로가 생긴다.
- design 4.4의 실기기 검증에서 하나라도 재현되면 **다시 묻지 않고 이 단계를 되돌려 3단계 상태(읽기
  전용)로 낸다**(오너가 미리 승인).

## 7단계 — 안내와 문서 (계획만)
- 파일: `lib/features/todo/presentation/todo_list_screen.dart`(한 번만 뜨는 안내 블록, 화면이라 커밋
  분리), `lib/core/strings.dart`, `shared_preferences` 플래그 저장소, `DEPLOY.md`, `CLAUDE.md`
  (개발 명령어에 생성기 한 줄 + 코딩 규칙에 위젯 발행 실패 예외 한 줄), `TODO_BACKLOG.md`에서 항목 빼기.
- 커밋: `feat: 위젯 홈 화면 노출 안내` + `docs: 위젯 배포 준비`.
- **여기로 넘긴 것(2026-11-05 리뷰)**:
  - `res/values/widget_resources.xml`의 **생성물 대조 테스트** 한 줄. 지금은 `AppStrings`·`RetroPalette`를
    고치고 생성기를 안 돌리면 조용히 어긋난다(리뷰 시점에는 문구 3개·색 7개가 모두 일치). CLAUDE.md
    개발 명령어에 생성기를 더하는 그 단계에서 "생성 결과 == 지금 파일"을 함께 박는다.
  - `DEPLOY.md` 실기기 체크리스트에 **"위젯 폰트는 앱과 다르다(의도, 용량 한도)"** 한 줄. 그리고
    체크리스트 **첫 줄로 "정상 상태에서 할 일 줄이 그려지는지"**(C1이 깨지면 바로 보이는 자리).
  - `android/app/build.gradle.kts`에 R8 minify 설정이 없어 release에도 `glance-appwidget` dex가 그대로
    실린다 — 배포 전에 **AAB 증가분을 한 번 재 보고** 거슬리면 minify를 켠다(폰트를 포기한 것보다 큰 절약).
  - `TODO_BACKLOG.md` 후보: 서브셋 한글 폰트(수백 KB)로 위젯 폰트 재시도.

---

## 진행 기록

### 1단계 (구현 완료, 커밋 전, 2026-11-04)
- 파일: `lib/features/todo/data/todo_widget_payload.dart`(신규), `lib/core/strings.dart`(파일 끝
  `// 홈 화면 위젯` 구역 추가), `test/features/todo/todo_widget_payload_test.dart`(신규, 30개).
- 검증: `flutter analyze` 이슈 0, `flutter test` **457개 통과**(기준선 427 + 신규 30).
- 계획한 순서 그대로 진행했다(plan → 1단계 → 2단계 → 3단계).
- 설계와 달라진 점
  - **`updatedAtMs`의 뜻을 "발행 시각"에서 "목록을 받아온 기준 시각"으로 좁혔다.** design 2.2는
    디버깅·중복 발행 판단용 발행 시각으로 적었지만, 그러면 (1) note의 `오전 9:14 기준`이 목록의
    나이를 말하지 못하고(조회 실패가 반복되면 실패한 시각이 "기준"으로 찍힌다), (2) 직전 JSON과
    비교해 같은 값을 다시 발행하지 않는다는 design 3.2의 장치가 **항상 다른 값**이 되어 무력해진다.
    **보정(2026-11-05 리뷰 W3)**: (2)의 효과는 절반이다 — `fromTodos`는 여전히 매번 `now`를 찍어
    목록이 그대로여도 다시 발행된다. 되살아난 것은 목록을 물려받는 발행(`fetchFailed`·`checkFailed`·
    `pending`)과 `primeFromCache`로 되읽은 캐시뿐이다. 틀리는 방향은 **과다 발행**이라 안전하고
    (바뀐 것을 안 보내는 일은 없다) 지금 비용은 브로드캐스트 몇 번이라 그대로 둔다.
    그래서 목록을 그대로 물려받는 발행(`fetchFailed`·`checkFailed`·`pending`)은 이 값도 물려받는다.
    JSON 키는 설계 그대로다(새 키를 더하지 않았다).
  - **`moreFormat`·`pendingLabel`은 객체의 필드로 두지 않고 `toJson`에서 `AppStrings`를 직접 쓴다.**
    앱 판마다 고정인 문구라 상태로 들고 다닐 이유가 없다. JSON 키는 설계 그대로 실린다(네이티브가
    한국어 문자열을 갖지 않는다는 목적은 그대로 달성된다).
  - **`visibleRows`에 "줄이 1개면 그 줄을 할 일에 쓴다"는 규칙을 더했다.** design 6.2는 "마지막 줄
    하나를 더 있음 줄로 바꿔 쓴다"만 적었는데, 그 규칙을 1줄 위젯(4x1)에 그대로 적용하면 유일한 줄이
    `그 외 N개`가 되어 할 일을 하나도 못 보는 위젯이 된다. design 6.1의 "1줄일 때도 note는 남긴다"와
    같은 취지로 읽었다. 네이티브도 같은 규칙을 옮겼다.
  - `todo_widget_payload.dart`가 `core/strings.dart`를 읽는다. `data/`에서 `AppStrings`를 쓰는 첫
    사례지만(기존에는 `domain/`만), 파일 자리는 design 3.2가 정한 그대로 두었다.

### 2단계 (구현 완료, 커밋 전, 2026-11-04)
- 파일(신규): `android/app/src/main/kotlin/com/todododo/todododo/TodoWidgetProvider.kt`,
  `android/app/src/main/res/layout/todo_widget.xml`, `android/app/src/main/res/xml/todo_widget_info.xml`,
  `android/app/src/main/res/drawable/{widget_frame,widget_row,widget_check}.xml`,
  `android/app/src/main/res/values/widget_resources.xml`(**생성물**),
  `tool/generate_widget_resources.dart`, `lib/features/todo/data/todo_widget_host.dart`.
  파일(수정): `pubspec.yaml`(+`pubspec.lock`), `android/app/src/main/AndroidManifest.xml`.
- 검증: `flutter analyze` 이슈 0, `flutter test` 457개 통과,
  **`flutter build apk --debug` 성공**(`home_widget` 0.10.0 × AGP 9.1.0 × Kotlin 2.4.0 × Flutter 3.47).
  `flutter test tool/generate_widget_resources.dart`로 XML을 생성했다.
- **AGP/minSdk 호환 확인 결과**(1.1의 검증 항목): 통과했다. 근거와 남은 소음:
  - `home_widget`의 안드로이드 모듈이 AGP 9를 스스로 감지해(`isAgp9OrAbove`) built-in Kotlin과
    `kotlin-android` 적용을 가른다. `minSdkVersion 23`이라 Flutter 기본값(24)보다 낮아 손댈 것이 없다.
  - 빌드 로그에 `WARNING: Your app uses the following plugins that apply Kotlin Gradle Plugin (KGP):
    firebase_core, home_widget`가 남는다. **이미 `firebase_core`로 나던 경고에 이름 하나가 붙은 것**이고
    오류가 아니다(플러그인 저자 몫의 마이그레이션 안내다).
  - `home_widget`이 `compileSdk 35`라 빌드 중 Android SDK Platform 35와 CMake 3.22.1이 자동 설치됐다
    (이 기기에 없었다). 다른 기기에서 첫 빌드가 느릴 수 있다.
  - `androidx.glance:glance-appwidget`가 `home_widget`의 `api` 의존성이라 APK에 **함께 들어온다.**
    우리는 Glance를 쓰지 않지만(design 1.2의 안 C 기각) 그 용량은 패키지를 쓰는 대가로 받아들였다.
- 설계와 달라진 점
  - **폰트를 넣지 않았다**(design 2.5가 정한 2.5MB 기준에 따른 분기). `Galmuri11.ttf`가 5.37MB다.
    그래서 `res/font/`와 `android/app/build.gradle.kts`의 복사 과제가 없고, **Gradle 파일을 한 줄도
    건드리지 않았다.** 위젯은 시스템 폰트 + 레트로 색으로 나간다 — 장식이 기능을 막지 않는다.
  - **위젯을 눌러 앱을 여는 PendingIntent를 2단계에 넣었다**(계획에는 5단계로 적었다). design 9장이
    PendingIntent 배선을 `TodoWidgetProvider.kt`(2단계 파일)에 배정했고, Dart 쪽 수신(어느 탭으로
    보낼지)이 없어도 "눌러서 앱 열기"는 그대로 올바르게 동작한다. **5단계에 남는 것은 Dart 쪽 런치
    Uri 해석·탭 이동**이다. 체크 칸의 PendingIntent는 그대로 6단계다.
  - `AppWidgetProvider` 대신 `home_widget`의 `HomeWidgetProvider`를 상속했다(캐시 `SharedPreferences`를
    인자로 받는 그 패키지의 정식 경로다). 읽는 파일·키는 design 2.1 그대로다.
  - 줄마다 `쓰는 중` 표시를 위해 TextView 하나를 더 선언했다(체크 칸을 숨기고 그 자리에 label을
    보인다). design 6.1 그림의 `[쓰는 중]`을 RemoteViews로 옮긴 결과이고, 그리기는 6단계가 쓴다.
- 함정 메모
  - RemoteViews는 `View`를 허용하지 않는다. 체크 칸은 `ImageView`(배경 shape만)로 뒀다.
  - `android/.kotlin/`이 빌드 중 새로 생긴다. `android/.gitignore` 9번 줄이 비어 있어(CRLF)
    `.kotlin/`이 **무시되지 않고 미추적으로 뜬다** — 커밋에 넣지 말 것. 무시 규칙 추가는 이 feature의
    몫이 아니라 따로 판단할 일이다.

### 3단계 (구현 완료, 커밋 전, 2026-11-04)
- 파일(신규): `lib/features/todo/domain/todo_widget_service.dart`,
  `test/features/todo/todo_widget_fakes.dart`, `test/features/todo/todo_widget_publish_test.dart`.
  파일(수정): `lib/features/todo/domain/todo_providers.dart`(provider 2개, 파일 끝),
  `lib/core/navigation/main_shell.dart`(`initState` 발행 + `build`의 `ref.listen` 독립 블록),
  `test/widget_test.dart`(기존 `MainShell` 테스트 2개에 가짜 host override + 신규 3개 + 헬퍼).
- 검증: `flutter analyze` 이슈 0, `flutter test` **466개 통과**(457 + 신규 9).
  `flutter build apk --debug` 재확인 성공.
- 설계와 달라진 점
  - **발행이 실패하면 "직전 발행"으로 기억하지 않는다.** design은 중복 발행 방지만 적었는데, 실패한
    발행을 직전으로 기억하면 같은 값이 다시 와도 건너뛰어 **위젯이 옛 내용으로 영구히 남는다.**
    성공한 발행만 기억해 다음 기회에 다시 시도하게 했다.
  - **`ref.listen`이 `isLoading`일 때는 아무것도 발행하지 않는다.** 설계에 없던 가드다. 새로고침
    중에 "불러오는 중"이나 "못 불러왔어요"를 깜빡이면 위젯이 낡은 목록을 그대로 두는 것보다 나쁘다.
  - 상태 8종 중 **`loggedOut`은 발행 지점이 4단계(로그아웃·탈퇴·세션 소멸)**라 이번 단계에서는
    서비스 유닛 테스트로만 덮었다. `checkFailed`·`pending`은 6단계의 발행 지점을 기다린다 —
    지금 부르는 자리를 만들면 아무도 읽지 않는 코드가 된다(push 2단계의 같은 판단).
- 함정 메모
  - 위젯 테스트에서 `todoWidgetHostProvider`를 override하지 않으면 플러그인이 없어 발행이 던지고
    서비스가 로그로 삼킨다 — 통과하지만 아무것도 검증되지 않고 출력만 더러워진다
    (`pushOverrides()`와 같은 함정). `MainShell`을 띄우는 테스트에는 `todoWidgetOverrides()`를 넣는다.
  - 실패 경로를 보는 테스트는 `ProviderContainer(retry: (count, error) => null)`로 리버포드 자동
    재시도를 꺼야 타이머가 남지 않는다(기존 선례 그대로).

### 리뷰 1차 반영 (2026-11-05, 커밋 전. `review-1.md` 대응)
반드시 고칠 것 2건 + 값싼 개선 5건을 고쳤다. **단계 경계는 바꾸지 않았다** — 아래 수정은 모두 원래
그 코드가 속한 단계의 커밋에 들어간다(새 파일은 없다).

- **C1(2단계·1단계) — 정상 상태에서 위젯이 `null` 네 글자를 그리던 문제.** 안드로이드(AOSP)의
  `org.json`은 `optString(name, fallback)`이 **명시적 null에 fallback이 아니라 `"null"`** 을 돌려준다.
  두 곳 모두에서 막았다: ① Dart `toJson()`이 **null인 키를 아예 싣지 않는다**(`centerText`·`pendingId`·
  `pendingAtMs`), ② Kotlin에 `JSONObject.text(name, fallback)` 헬퍼를 두고 `isNull`을 먼저 검사해
  모든 문자열(`centerText`·`note`·`noteTone`·`moreFormat`·`pendingLabel`·`title`·`id`)을 그것으로 읽는다.
  Kotlin 전체를 훑어 남은 `optString`은 없다. `optInt`/`optLong`/`optJSONArray`/`optJSONObject`는
  AOSP에서도 명시적 null에 fallback·null을 돌려주므로 그대로 뒀다.
  **테스트로 박았다**: "null인 키는 캐시에 넣지 않는다"(상태 7종을 돌며 `toJson()`에 null 값이 하나도
  없음을 단언 + 왕복이 그대로임을 확인). 네이티브는 테스트하지 않으므로 이 단언이 유일한 방어선이다.
- **C2(3단계) — 앱을 다시 켜면 오프라인에서 지난 목록이 사라지던 문제.** 설계가 둔
  `TodoWidgetHost.read()`를 아무도 부르지 않고 있었다. `TodoWidgetService.primeFromCache(now:)`를
  만들어 ① 기기 캐시를 되읽어 `_lastPublished`·`_lastJson`을 씨딩하고, ② **되읽은 캐시에 items가
  없을 때만** `loading()`을 발행한다. `MainShell.initState`가 `publish(loading())` 대신 이것을 부른다.
  되읽는 동안 실제 목록이 먼저 발행됐으면(`_publishCount > 0`) 되읽은 값으로 덮지 않는다.
  읽기 실패는 `debugPrint`만 남기고 `loading()`으로 계속 간다.
  **테스트로 박았다**: 캐시에 지난 목록이 있으면 `loading()`을 발행하지 않는다 / 되읽은 목록이 조회
  실패의 직전 목록이 된다 / 캐시에 보여 줄 것이 없거나 되읽기가 실패하면 `loading()`을 발행한다 /
  `MainShell`에 지난 캐시 + 조회 실패를 주면 `loading()` 없이 `지난 목록 + 지금은 못 불러왔어요 ·
  오전 9:14 기준`으로 끝난다.
- **W1(2단계)**: Kotlin `moreCount`에 `shown > 0 &&`를 더해 Dart `visibleRows`와 전수 일치시켰다.
- **W2(2단계)**: `showRows`가 그린 줄 수를, `showNote`가 note를 그렸는지를 돌려주게 하고,
  **셋 다 비면 반드시 `todo_widget_no_cache`로 떨어진다**(design 6.3의 "반드시"가 코드로 성립).
- **W4(1단계)**: `visibleRows` 경계 테스트 3칸 추가 — `totalCount == rowCount`(6/6),
  `totalCount == rowCount + 1`(7/6), 줄 수 2(9개/2줄).
- **W5(3단계)**: `main_shell.dart`의 조회 실패 중복 로그를 지웠다(화면의 error 갈래가 이미 남긴다).
- **W6(3단계)**: 가짜에 `readError`·`stored`(생성자 인자)·`readCount`를 두고 전부 테스트에서 쓴다.
  `updateError`도 "다시 그리기가 실패하면 직전으로 기억하지 않는다"로 쓰인다.
- 검증: `flutter analyze` 이슈 0, `flutter test` **475개 통과**(466 + 신규 9: payload 3 · service 5 ·
  MainShell 1), `flutter build apk --debug` 성공.
- 문서: `design.md` 2.5에 폰트 미적용 각주(실측 5,376,428바이트 > 2.5MB 한도)를 넣고 2.4·9장 행이 그
  각주를 가리키게 했다. 위 ①의 근거를 W3에 맞춰 보정했다. 7단계·6단계 항목에 리뷰가 넘긴 것들을 적었다.

### 커밋 분할용 파일 목록 (리뷰 반영 뒤 최종)
- **1단계** `feat: 투두 위젯 캐시 페이로드`: `lib/features/todo/data/todo_widget_payload.dart`,
  `lib/core/strings.dart`(파일 끝 구역), `test/features/todo/todo_widget_payload_test.dart`,
  `docs/specs/home-widget/plan.md`(또는 별도 docs 커밋), `docs/specs/home-widget/design.md`(각주),
  `docs/specs/home-widget/review-1.md`
- **2단계** `feat: 홈 화면 투두 위젯 추가`: `pubspec.yaml`, `pubspec.lock`,
  `android/app/src/main/kotlin/com/todododo/todododo/TodoWidgetProvider.kt`,
  `android/app/src/main/res/layout/todo_widget.xml`, `android/app/src/main/res/xml/todo_widget_info.xml`,
  `android/app/src/main/res/drawable/widget_frame.xml`·`widget_row.xml`·`widget_check.xml`,
  `android/app/src/main/res/values/widget_resources.xml`, `android/app/src/main/AndroidManifest.xml`,
  `tool/generate_widget_resources.dart`, `lib/features/todo/data/todo_widget_host.dart`
- **3단계** `feat: 앱의 할 일 변경을 위젯에 반영`: `lib/features/todo/domain/todo_widget_service.dart`,
  `lib/features/todo/domain/todo_providers.dart`, `lib/core/navigation/main_shell.dart`,
  `test/features/todo/todo_widget_fakes.dart`, `test/features/todo/todo_widget_publish_test.dart`,
  `test/widget_test.dart`

