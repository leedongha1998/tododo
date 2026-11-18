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
- 유닛이 덮는 것: 미완료만 담기, 받은 순서 보존(순서는 2026-11-10 `todo-reorder` 뒤로 **서버의 `order by position`**이 만든다 — 그 전에는 `todosProvider`의 `sortedForList`, 더 전에는 "생성순 유지"였다), 8개 상한, 제목 80자 자르기, `totalCount`, 상태 8종의
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


### 릴리스 빌드 깨짐과 해결 (2026-11-05)

1~3단계 커밋 뒤 실기기 설치를 위해 릴리스 APK를 만들려다 **릴리스 빌드만 깨지는 것**을 발견했다.
구현 중에는 `flutter build apk --debug`를 두 번 통과시켰고 그것으로 네이티브 빌드를 검증했다고
봤는데, **디버그는 통과하고 릴리스는 깨지는 종류**였다.

- 증상: `:app:compileReleaseJavaWithJavac`에서 `cannot find symbol` — 처음에는
  `image_picker_android`의 `ImagePickerApi`, 캐시가 바뀐 뒤에는 `FlutterFirebaseCorePlugin`.
  **에러에 찍히는 플러그인 이름이 범인이 아니다.**
- 원인: `home_widget` 0.10.0의 `android/build.gradle`이 buildscript classpath에
  `kotlin-gradle-plugin:1.9.0`(+ AGP 8.1.2)을 박아 둔다. 이 프로젝트는 Kotlin 2.4.0 / AGP 9.1.0이고
  `android/gradle.properties`의 `android.builtInKotlin=false`(Flutter 템플릿 기본값) 때문에
  `firebase_core`와 `home_widget` 둘 다 자체 `kotlin-android`를 적용하는 분기로 들어간다.
  그 상태에서 1.9.0이 끼어들면 app 모듈의 javac가 플러그인들의 Kotlin 클래스를 못 본다.
- 범인 가리기: 별도 워크트리(`git worktree add --detach`)에 **위젯 직전 커밋 `1e8a511`**(firebase는
  이미 들어간 지점)을 꺼내 릴리스 빌드를 돌려 **성공**(54.8MB)하는 것을 확인했다. 즉 다른 세션의
  firebase 작업이 아니라 `home_widget` 추가가 방아쇠다. 이어서 같은 워크트리를 내 HEAD로 옮기고
  `android.builtInKotlin=true`만 바꿔 **성공**(56.0MB)하는 것까지 확인한 뒤 본 트리에 적용했다.
- 해결: `android/gradle.properties`의 `android.builtInKotlin`을 `true`로 바꿨다(이유를 그 파일의
  주석과 `CLAUDE.md` "개발 환경"에 남겼다). AGP 9의 Built-in Kotlin이 컴파일해 `firebase_core`·
  `home_widget` 둘 다 통과한다. **프로젝트 전체에 걸리는 플래그**라 같은 트리에서 작업 중인
  `push-notification` 세션에 알렸다.
- 남긴 규칙: 네이티브를 가진 패키지를 추가하는 변경은 **릴리스 빌드까지** 돌려야 한다. 그리고
  빌드 로그를 `tail`로 파이프하면 종료 코드가 가려져 실패를 성공으로 읽게 된다(실제로 그래서
  11월 3일자 옛 APK를 폰에 설치했다) — `EXIT=$?`를 따로 찍는다.

---

# 2026-11-18 추가 범위 — design 13.1의 4~8단계

입력: `docs/specs/home-widget/design.md`의 **13.1**(현재 기준의 단계 분할)과 그것이 가리키는 장
(원칙 2의 2026-11-18 각주 · 2.2.1 · 4.5 · 6.1.1 · 6.2.1 · 6.3 추가분 · 8.1 · 12.1 · 12.2),
`docs/specs/home-widget/spec.md`의 `## 2026-11-18 추가 범위`(수용 기준 + 확정된 결정 3건).
**결정 필요는 하나도 남아 있지 않다**(design "## 결정 필요 → 2026-11-18 추가 범위에 대해: 없음").

**이번 작업 범위는 4~8단계 전부다**(오너 2026-11-18 확정). 순서를 바꾸지 않는다 —
4(줄 두께) → 5(기한) → 6(로그아웃 비우기) → 7(체크) → 8(안내·문서). 그 순서 자체가
"깨지면 그 커밋만 되돌린다"는 설계 결정이다(spec 권고 작업 순서, design 13.1).

## 공통 규칙 (위 `## 공통 규칙`에 더하는 것)
- **단계 끝마다** `flutter analyze` 이슈 0 + `flutter test` 전부 통과. **네이티브가 바뀐 단계
  (4·5·7)는 `flutter build apk --release --dart-define-from-file=env.json`까지** — 디버그만으로는
  검증되지 않는다(1~3단계가 실제로 그래서 깨졌다. 아래 "릴리스 빌드 깨짐과 해결" 참고).
  로그를 `tail`로 파이프하면 종료 코드가 가려지므로 `EXIT=$?`를 따로 찍는다.
- **스키마 변경 없음, 새 패키지 없음.** `supabase/`·`pubspec.yaml`의 의존성 목록을 건드리면
  범위를 잘못 읽은 것이다(spec 범위 밖).
- 네이티브가 직접 갖는 문자열·색은 손으로 XML에 적지 않는다 —
  `flutter test tool/generate_widget_resources.dart`로 생성한다. 생성 파일을 직접 고치지 않는다.
- 이 세션도 **커밋하지 않는다**. 단계별 파일 목록이 커밋 분할의 기준이다.

## 착수 전 확인 (2026-11-18)
- 기준선: `flutter analyze` 이슈 0, `flutter test` **813개 통과**.
- `env.json`이 저장소 루트에 있다 → 릴리스 빌드를 돌릴 수 있다.
- 1~3단계는 커밋됐고(`567d968`까지), 미추적·수정 중인 것은 `docs/specs/home-widget/{spec,design}.md`뿐이다.

## CLAUDE.md·dev-standards와의 충돌 점검 (2026-11-18)
**구현을 멈춰야 하는 충돌은 없다.** 새로 확인한 항목만 적는다(나머지는 위 같은 제목의 절과 같다).
- **"판정 로직은 DB/Edge"·"클라이언트에서 승패 계산 금지"** — 이번 범위는 `todos`만 읽고
  `todos.is_done = true`만 쓴다. 대결 테이블·점수·전적에 닿는 경로가 없다.
- **"위젯이 기기 시계로 마감 경과를 판단하지 않는다"(도메인 경계)** — 그 조항은 **대결의
  마감·판정 기한**에 대한 것이고, 개인 할 일 기한(`todos.due_at`)은 spec이 2026-11-18에 예외로
  명시했다(그 자리에 추기돼 있다). 이번에 네이티브가 비교하는 값은 `dueAtMs` 하나뿐이고 대결
  데이터는 캐시에 들어오지도 않는다.
- **"테스트 없이 판정 로직 수정 금지"** — 판정 로직을 수정하지 않는다. 대신 이번에 늘어나는
  판단(기한 서식·"지남" 경계·줄 수 공식·중복 탭 결정)을 전부 Dart 순수 함수로 두고 유닛
  테스트로 고정한다(design 12.1).
- **CLAUDE.md 코딩 규칙의 "위젯 캐시 발행 실패는 `debugPrint`만"** 예외와 **개발 명령어의
  `flutter test tool/generate_widget_resources.dart`** 는 **이미 들어가 있다**(옛 7단계가 넘긴 두
  줄이 그 뒤에 반영됐다). 8단계에서 확인만 하고 그대로 둔다.
- `TODO_BACKLOG.md`의 home-widget 항목도 **이미 빠져 있다**(`45a860e`). 8단계에서 확인만 한다.

---

## 4단계 — 위젯 줄을 두껍게 하고 체크 칸을 키운다 (네이티브)

### 파일
1. `android/app/src/main/res/layout/todo_widget.xml` — 줄 6개를 design 6.1.1 구조로:
   체크 `ImageView` **48×40dp**(`background` → `src` + 좌우 14dp·위아래 10dp 패딩 → 그림 20×20dp),
   `widget_text_<i>`(세로 `LinearLayout`, `0dp`+`weight 1`)에 제목 + **`widget_due_<i>`(신규,
   `gone`)**, 줄 `minHeight=40dp`, 루트 여백 좌우 8dp·위아래 4dp, note `includeFontPadding=false`.
   `paddingHorizontal`/`paddingVertical`은 **쓰지 않는다**(API 26, `minSdk 24`).
2. `android/app/src/main/kotlin/.../TodoWidgetProvider.kt` — `rowCountFor`를 6.2.1의 **공식**
   (`((h − 24) / 42)`을 1~6으로 가둠, 상수 `FIXED_DP`·`ROW_PITCH_DP`·`MAX_ROWS`)으로 교체,
   `widget_text_<i>`에 앱 열기 PendingIntent(제목·기한에 따로 걸지 않는다).
3. `lib/features/todo/data/todo_widget_payload.dart` — `widgetRowCount(int heightDp)` 순수 함수
   + 상수 셋(규칙의 주인은 Dart다. `visibleRows`와 같은 방식) + `items` 상한 8의 근거 주석.
4. `test/features/todo/todo_widget_payload_test.dart` — 줄 수 경계 전수(design 12.1).

### 커밋
- `feat: 위젯 줄을 두껍게 하고 체크 칸을 키운다`

### 검증
- analyze 0 / test 전부 / **릴리스 APK 빌드**.
- 기한 TextView는 이 커밋 끝에서 **언제나 `GONE`** 이다(죽은 코드가 아니라 5단계가 쓰는 자리 —
  design 13.1의 마지막 각주).

---

## 5단계 — 위젯에 할 일 기한 표시

### 파일
1. `lib/core/strings.dart` — `// 홈 화면 위젯` 구역에 `widgetDueDate`·`widgetDueDateYear`·
   `widgetDueOverdue` 셋. `widgetTime`은 **재사용**하고 `todoDuePassed`는 **재사용하지 않는다**.
2. `lib/features/todo/data/todo_widget_payload.dart` — `TodoWidgetItem`에 `due`·`dueOver`·
   `dueAtMs`(없으면 **키째로 싣지 않는다**), `formatWidgetDue(dueAtUtc, now)`(세 꼴·12시간제,
   `내일` 같은 낱말 없음).
3. `lib/features/todo/domain/due_date_rules.dart` — **주석 한 줄만**(서식의 세 번째 자리를 가리킨다).
4. `android/app/src/main/kotlin/.../TodoWidgetProvider.kt` — 줄을 그릴 때 기한 세 분기(design 6.3):
   `dueAtMs` 없음/0 → `GONE`, `now < dueAtMs` → `due` + `widget_ink_muted`,
   `now >= dueAtMs` → `dueOver` + `widget_danger`. 제목 색은 건드리지 않는다.
5. `test/features/todo/todo_widget_payload_test.dart` — design 12.1 표의 기한 칸 전부
   (세 꼴·날 경계·12시간제 두 함정·분 0 패딩·키 없음 단언·시간대 무관·"지남이 굳지 않는다").
6. `flutter test tool/generate_widget_resources.dart` 한 번(생성물이 어긋나지 않는지 확인).

### 커밋
- `feat: 위젯에 할 일 기한 표시`

### 검증
- analyze 0 / test 전부 / **릴리스 APK 빌드**.

---

## 6단계 — 로그아웃·탈퇴 시 위젯 캐시 비우기 (Dart만)

### 파일
1. `lib/features/todo/domain/todo_widget_service.dart` — `publishLoggedOut({DateTime? now})`
   (auth 쪽이 `todo/data`의 페이로드 타입을 import하지 않게 하는 얇은 창구).
2. `lib/features/auth/data/auth_repository.dart` — `typedef ClearWidgetCache`를 두고 생성자로
   받는다(`CancelDeviceAlarms` 선례와 **같은 모양**). `signOut()`·`deleteAccount()` 둘 다에서
   `_client.auth.signOut()` **앞**에 부른다.
3. `lib/features/auth/domain/auth_providers.dart` — 조립 한 줄.
4. `lib/features/auth/presentation/auth_gate.dart` — `build`에 `ref.listen(authStateProvider)`
   **한 블록**(세션 소멸 감지). **`ConsumerWidget`을 그대로 둔다** — Stateful 전환은 7단계다.
5. `test/features/todo/todo_widget_publish_test.dart`, `test/widget_test.dart` — 세 방어선.

### 커밋
- `feat: 로그아웃·탈퇴 시 위젯 캐시 비우기`

### 검증
- analyze 0 / test 전부(네이티브 변경 없음 → 릴리스 빌드 불필요).

---

## 7단계 — 위젯에서 할 일 완료 처리 (위험이 몰린 단계)

**design 4.2의 W5(포트 핸드오프)를 그대로 쓴다.** 백그라운드에서 무조건 `Supabase.initialize`하는
설계로 바꾸지 않는다 — 앱이 조용히 로그아웃되는 경로가 생긴다(4.2가 소스로 확인한 토큰 회전).

### 파일
1. `lib/features/todo/data/todo_widget_payload.dart` — 중복 탭·포트 유무의 **결정만** 떼어 낸
   순수 함수(`TodoWidgetCheckDecision` + `todoWidgetCheckDecisionOf`), `checkFailed`가 `now`를
   받게(4.5 (3) 정리 1건).
2. `lib/features/todo/data/todo_widget_callback.dart` (신규) — `@pragma('vm:entry-point')`
   진입점(`main.dart`가 아니다) + 포트 이름 상수. 흐름은 design 4.3 그대로.
3. `lib/features/todo/data/todo_widget_host.dart` — `registerCallback` 한 줄.
4. `lib/features/auth/presentation/auth_gate.dart` — **여기서 `ConsumerStatefulWidget`으로 전환**
   (`initState`에서 콜백 등록 + `IsolateNameServer` 포트 등록, `dispose`에서 해제).
5. `android/app/src/main/kotlin/.../TodoWidgetProvider.kt` — 체크 칸 PendingIntent
   (`HomeWidgetBackgroundIntent.getBroadcast`, Uri data가 줄마다 다르다), `centerText`에도
   `noteTone` 색(4.5 (3) 정리 2건).
6. `android/app/src/main/AndroidManifest.xml` — `HomeWidgetBackgroundReceiver` 등록
   (design 9.1의 "manifest 변경 없음"이 틀렸다. 아래 진행 기록 참고).
7. 테스트 — 결정 순수 함수 전수 + 기한이 지난 할 일도 같은 결정.

### 커밋
- `feat: 위젯에서 할 일 완료 처리`
- **design 4.4의 실기기 검증에서 하나라도 재현되면 다시 묻지 않고 이 커밋만 되돌린다**
  (오너 미리 승인). 그래도 4·5·6단계가 남는다.

### 검증
- analyze 0 / test 전부 / **릴리스 APK 빌드**. 백그라운드 경로는 실기기에서만 검증된다(12.2의 11번).

---

## 8단계 — 홈 화면 노출 안내와 문서

### 파일
1. `lib/core/strings.dart` — 안내 블록 문구(**"제목과 기한"**이 보인다는 사실까지 말한다).
2. `lib/features/todo/data/todo_widget_notice_store.dart` (신규) — 처음 한 번만 뜨게 하는 기기·
   계정별 플래그(선례: `VsIntroSeenStore`).
3. `lib/features/todo/presentation/todo_list_screen.dart` — 목록 맨 위 안내 블록 + 닫기.
4. `DEPLOY.md` — 위젯 실기기 확인을 **design 12.2 목록으로** 넓혀 적는다.
5. `CLAUDE.md`·`TODO_BACKLOG.md` — 확인만(위 충돌 점검 참고).
6. `test/tool/widget_resources_test.dart` (신규) — 옛 7단계가 넘긴 **생성물 대조** 한 자리.
7. 테스트 — 안내가 한 번만 뜨고 닫으면 다시 뜨지 않는다.

### 커밋
- `feat: 위젯 홈 화면 노출 안내` + `docs: 위젯 배포 준비` (화면과 문서를 나눈다)

### 검증
- analyze 0 / test 전부(네이티브 변경 없음).

---

## 진행 기록 (2026-11-18 추가 범위)

### 4단계 — 줄 두께·체크 칸 (구현 완료, 커밋 전, 2026-11-18)
- 파일(수정): `android/app/src/main/res/layout/todo_widget.xml`(줄 6개를 6.1.1 구조로 다시 씀),
  `android/app/src/main/kotlin/com/todododo/todododo/TodoWidgetProvider.kt`(`rowCountFor` 공식 교체,
  `TEXT_IDS`에 앱 열기 PendingIntent, 상수 `FIXED_DP`·`ROW_PITCH_DP` 신설),
  `lib/features/todo/data/todo_widget_payload.dart`(`widgetRowCount` + 상수 셋 + 상한 8의 근거),
  `test/features/todo/todo_widget_payload_test.dart`(줄 수 4칸 추가).
  **신규 파일 없음.**
- 검증: `flutter analyze` 이슈 0, `flutter test` **817개 통과**(기준선 813 + 4),
  **릴리스 APK 빌드 성공**(62.2MB, `flutter build apk --release --dart-define-from-file=env.json`).
- 설계와 달라진 점
  - **줄에 `paddingRight="8dp"`를 더했다.** design 6.1.1은 줄의 **세로** 여백만 0으로 못 박았고
    가로는 적지 않았다. 패딩이 전혀 없으면 제목의 생략 기호가 줄 테두리에 붙어 그 자리만 넣었다
    (왼쪽은 체크 칸 48dp가 이미 여백 구실을 한다).
  - **제목 TextView를 `layout_width="match_parent"`로 두었다**(감싼 칸이 `0dp`+`weight 1`이므로
    결과 폭은 설계가 센 그대로다). 세로 `LinearLayout`의 자식이라 `weight`를 다시 줄 수 없다.
- 함정 메모
  - `android:background`를 그대로 두고 뷰만 키우면 **48×40dp 전체가 칠해진다.** `src`로 옮겨야
    그림(content box 20×20dp)과 터치 영역(뷰 전체)이 갈린다. shape는 고유 크기가 없어 `src`로
    쓰면 content box를 채운다.
  - `paddingHorizontal`/`paddingVertical`은 API 26부터다(`minSdk 24`) — 네 방향을 따로 적었다.
  - Kotlin `/`와 Dart `~/`는 둘 다 0 쪽으로 버리므로 높이가 고정 비용보다 작을 때도 결과가 같다
    (둘 다 0 → 하한 1로 가둔다).
  - 편집 훅의 `dart format` 실패 보고는 이번에도 거짓 경보였다(`git diff`가 내가 더한 줄뿐이다).

### 5단계 — 기한 표시 (구현 완료, 커밋 전, 2026-11-18)
- 파일(수정): `lib/core/strings.dart`(`widgetDueDate`·`widgetDueDateYear`·`widgetDueOverdue` 셋을
  `// 홈 화면 위젯` 구역 끝에), `lib/features/todo/data/todo_widget_payload.dart`
  (`TodoWidgetItem`에 `due`·`dueOver`·`dueAtMs` + `_itemOf` + `formatWidgetDue`, 머리 주석의
  "네이티브 판단 둘"을 넷으로 고침), `lib/features/todo/domain/due_date_rules.dart`(주석 한 줄),
  `android/app/src/main/kotlin/.../TodoWidgetProvider.kt`(`showDue` 세 분기 + `DUE_IDS`, 클래스
  주석의 판단 목록), `test/features/todo/todo_widget_payload_test.dart`(기한 14칸 추가).
  **신규 파일 없음.** `android/app/src/main/res/values/widget_resources.xml`은 생성기를 돌려
  **생성물이 지금 파일과 같다**(새 색·새 문자열이 없다 — 기한은 `widget_ink_muted`/`widget_danger`를
  쓰고 문구는 캐시로 간다)는 것만 확인했다.
- 검증: `flutter analyze` 이슈 0, `flutter test` **831개 통과**(817 + 14), 릴리스 APK 빌드 성공.
- 설계와 달라진 점: 없다(서식 세 꼴·12시간제·`내일` 금지·키 셋·판 번호 유지 전부 design 그대로).
  - 기한 서식 함수의 자리도 design 6.1.1 그대로 `data/todo_widget_payload.dart`다. `due_date_rules.dart`
    에는 "거기 있다"는 주석만 남겼다(함수를 옮기지 않았다).
- 함정 메모
  - **테스트의 "오늘"**: 기존 파일의 기준 시각(`now`)은 11/4인데 "같은 날" 칸을 쓰려면 기한과 같은
    날짜가 필요하다. 두 묶음 안에서 `now`를 11/18로 **가려 두고**(shadow) 그 이유를 주석에 적었다.
  - `item.text("dueOver", due)`처럼 **fallback을 `due`로 둔다.** AOSP `org.json`은 키가 없거나
    명시적 null일 때 fallback을 주므로, 빈 문자열을 그려 줄이 반쯤 비는 경우가 생기지 않는다.
  - `dueAtMs`는 `optLong("dueAtMs", 0L)`로 읽고 **0 이하를 "없음"으로** 다룬다(1970년을 기한으로
    둔 할 일은 없다). 문자열 헬퍼(`text`)를 쓰지 않는 유일한 기한 키다.
  - 생성기를 돌리면 `widget_resources.xml`이 `git status`에 **M으로 뜨는데 `git diff`는 비어 있다** —
    생성기가 LF로 쓰고 이 저장소는 `core.autocrlf=true`라 줄바꿈만 다른 것이다(내용은 같다).

### 6단계 — 로그아웃·탈퇴 시 위젯 캐시 비우기 (구현 완료, 커밋 전, 2026-11-18)
- 파일(신규): `test/features/auth/logout_widget_cache_test.dart`(이 저장소의 첫 `test/features/auth/`).
  파일(수정): `lib/features/todo/domain/todo_widget_service.dart`(`publishLoggedOut({DateTime? now})`),
  `lib/features/auth/data/auth_repository.dart`(`ClearWidgetCache` typedef + 생성자 인자 +
  `signOut`·`deleteAccount` 두 경로), `lib/features/auth/domain/auth_providers.dart`(조립 한 줄),
  `lib/features/auth/presentation/auth_gate.dart`(`ref.listen` 한 블록).
- 검증: `flutter analyze` 이슈 0, `flutter test` **837개 통과**(831 + 6). 네이티브 변경이 없어
  릴리스 빌드는 돌리지 않았다.
- 설계와 달라진 점
  - **`AuthGate`를 `ConsumerWidget`으로 그대로 두었다**(design 8.1이 지시한 그대로). Stateful
    전환은 7단계가 한다.
  - 세션 소멸 감지의 조건을 `next.value?.session == null`로 적었다(design이 적은
    `valueOrNull`은 이 riverpod 판(3.4.2)의 `AsyncValue`에 없다 — `value`가 nullable이고
    `AsyncError`는 직전 값을 들고 있다). 뜻은 설계 그대로다: **loading에서는 아무것도 하지 않고**,
    스트림이 실패했는데 직전에 세션이 있었으면 그대로 둔다(스트림 오류는 로그아웃이 아니다).
  - **탈퇴 경로의 비우기 호출은 유닛 테스트로 덮지 못했다.** 그 줄은 `delete_account` RPC 뒤에
    있어 서버가 있어야 도달하고, 오프라인 유닛에서는 세션 가드에서 끝난다. 그래서 그 자리에는
    "실패한 탈퇴가 캐시를 건드리지 않는다"만 고정하고, 호출 자체는 **실기기 확인 10번**
    (design 12.2)에 맡긴다 — 보고에 적었다. 로그아웃 경로는 진짜로 덮었다(비우기가 `auth.signOut()`
    **앞**이라 세션이 없어 마지막 단계가 던져도 이미 불린 것을 확인한다).
- 함정 메모
  - `AuthRepository`는 `SupabaseClient('http://localhost:54321', 'key')`로 **테스트에서 그냥 만들 수
    있다**(세션이 없으면 `auth.signOut()`이 네트워크를 타지 않고 던진다). `PushService`는
    `implements` + `noSuchMethod`로 가짜를 만든다.
  - `AuthGate`를 띄우는 테스트는 `authStateProvider`를 `StreamController`로 override하고
    **`todoWidgetOverrides()`를 함께 넣는다**(없으면 발행이 던지고 서비스가 로그로 삼켜 아무것도
    검증되지 않는다).

### 7단계 — 위젯에서 할 일 완료 처리 (구현 완료, 커밋 전, 2026-11-18)
- 파일(신규): `lib/features/todo/data/todo_widget_callback.dart`(백그라운드 진입점 + 포트 이름·답
  상수 + 핸드오프 상한).
  파일(수정): `lib/features/todo/data/todo_widget_payload.dart`(`TodoWidgetCheckDecision` +
  `todoWidgetCheckDecisionOf`, `checkFailed(now:)`), `lib/features/todo/data/todo_widget_host.dart`
  (`registerCallback`), `lib/features/auth/presentation/auth_gate.dart`(**`ConsumerStatefulWidget`
  전환** + 콜백 등록 + 포트 등록/해제 + 쓰기 수행), `android/app/src/main/kotlin/.../TodoWidgetProvider.kt`
  (체크 칸 PendingIntent, `centerText`에도 톤 색), `android/app/src/main/AndroidManifest.xml`
  (`HomeWidgetBackgroundReceiver`), `test/features/todo/todo_widget_fakes.dart`(가짜에
  `registerCallback`), `test/features/auth/logout_widget_cache_test.dart`(콜백 등록 한 칸),
  `test/features/todo/todo_widget_payload_test.dart`(결정 9칸 + `checkFailed` 2칸).
- 검증: `flutter analyze` 이슈 0, `flutter test` **846개 통과**(837 + 9), 릴리스 APK 빌드 성공
  (62.3MB). **백그라운드 경로(포트 핸드오프·직접 쓰기)는 실기기에서만 검증된다** —
  design 12.2의 11번과 4.4 표가 그 자리다.
- 설계와 달라진 점
  - **manifest를 고쳐야 했다.** design 9.1은 "체크의 백그라운드 리시버는 `home_widget`이 자기
    manifest에 이미 선언해 둔 것을 쓴다(변경 없음)"고 적었지만 **그 패키지의 매니페스트는 비어
    있다**(`<manifest package="es.antonborri.home_widget" />`). 예제 앱이 앱 쪽에 적어 두는 구조라
    우리도 `<receiver es.antonborri.home_widget.HomeWidgetBackgroundReceiver>` 한 블록을 넣었다 —
    없으면 체크를 눌러도 **아무 일도 일어나지 않는다**(실기기에서만 드러날 종류의 누락이었다).
    새 권한은 여전히 없고 `exported="false"`다(우리 PendingIntent가 우리 자격으로 발송된다).
  - **줄마다 요청 코드를 다르게 주지 못한다.** design 1.2·4.5가 "요청 코드를 줄 번호로 구분"을
    두 번째 겹으로 적었는데 `HomeWidgetBackgroundIntent.getBroadcast(context, uri)`가 요청 코드를
    **0으로 고정**한다(패키지 API에 그 인자가 없다). 설계가 적어 둔 **첫 번째 겹(Uri data가 줄마다
    다르다 → `Intent.filterEquals`가 다른 것으로 본다)이 그대로 유효**하므로 그것만으로 구분된다.
    직접 PendingIntent를 만들려면 패키지의 private 액션 상수를 베껴야 해서 쓰지 않았다.
  - **백그라운드 직접 쓰기에서 만료된 액세스 토큰을 먼저 갱신한다**(`session.isExpired`면
    `refreshSession()`). `Supabase.initialize`는 저장된 세션을 메모리에 올리기만 하고 갱신
    (`recoverSession`)을 **기다리지 않아서**(소스 확인: `supabase.dart:155-160`가 unawaited), 그대로
    쓰면 하루에 한 번 앱을 여는 사용자의 체크가 거의 항상 401이 된다 — design 4.4의 검증 항목
    "1시간 이상 앱을 열지 않은 뒤 체크"가 바로 그 경우다. W5의 "죽은 앱에서는 refresh 허용"
    안쪽이고, gotrue가 같은 refresh token의 갱신을 하나로 합치므로(`_pendingRefreshes`) 토큰이 두 번
    돌지 않는다.
  - **핸드오프의 답에 `loggedOut`을 두었다.** 앱이 떠 있지만 로그인 화면인 경우다(design 4.3은 그
    답을 받는다고만 적고 처리를 적지 않았다) — 그때 백그라운드가 `publishLoggedOut()`으로 캐시를
    덮어 이전 사용자의 목록을 홈 화면에 남기지 않는다.
  - `data/`의 진입점이 같은 feature의 `domain/TodoWidgetService`를 쓴다. 백그라운드 isolate의
    `main` 같은 자리라 조립을 직접 하는 것이고(앱에서는 provider가 한다), 파일 자리는 design 4.3이
    정한 그대로 두었다. 그 이유를 파일 머리에 적었다.
- 함정 메모
  - `home_widget`의 `callbackDispatcher`가 `WidgetsFlutterBinding.ensureInitialized()`를 **이미**
    부르고, 백그라운드 engine은 `FlutterEngine(context)`로 만들어져 플러그인이 자동 등록된다 —
    그래서 콜백에서 `shared_preferences`·`home_widget` 채널이 그대로 동작한다.
  - `Supabase.initialize`는 **멱등**이다(이미 초기화돼 있으면 로그만 남기고 돌아온다). 같은
    백그라운드 engine이 두 번 깨어나도 안전하다.
  - `IsolateNameServer.registerPortWithName`은 같은 이름이 남아 있으면 **false를 돌려주고 등록되지
    않는다.** 핫 리스타트 대비로 `removePortNameMapping`을 먼저 부른다.
  - `TodoWidgetPayload.checkFailed`의 서명이 바뀌어(`now` 필수) 기존 테스트 4곳을 함께 고쳤다.

### 8단계 — 홈 화면 노출 안내와 문서 (구현 완료, 커밋 전, 2026-11-18)
- 파일(신규): `lib/features/todo/data/todo_widget_notice_store.dart`,
  `test/features/todo/todo_widget_notice_test.dart`, `test/tool/widget_resources_test.dart`.
  파일(수정): `lib/core/strings.dart`(`widgetNoticeTitle`·`widgetNotice`·`widgetNoticeDismiss`),
  `lib/features/todo/domain/todo_providers.dart`(`todoWidgetNoticeStoreProvider`),
  `lib/features/todo/presentation/todo_list_screen.dart`(안내 블록 + 닫기),
  `DEPLOY.md`(위젯 실기기 확인을 design 12.2 목록으로 넓힘), `CLAUDE.md`(안내 기록 실패 예외 한 줄).
- 검증: `flutter analyze` 이슈 0, `flutter test` **850개 통과**(846 + 4). 네이티브 변경 없음.
- 문서 확인 결과(고치지 않은 것)
  - CLAUDE.md의 **개발 명령어에 생성기 한 줄**(`flutter test tool/generate_widget_resources.dart`)과
    **코딩 규칙의 "위젯 캐시 발행 실패는 로그만"** 예외는 **이미 들어가 있었다** — 그대로 두었다.
  - CLAUDE.md의 범위 서술도 이미 맞다("투두 위젯 하나만 배포 전에 낸다 … 위젯에서 할 일 체크까지 허용").
  - `TODO_BACKLOG.md`의 home-widget 항목은 **이미 빠져 있다**(`45a860e`). 남아 있는
    "홈 위젯 줄에 기한 임박 표시"는 **다른 항목**이다(남은 시간 숫자 = 상대 표현이고 이번 범위는
    절대 시각이다. spec 범위 밖 조항 그대로라 그대로 둔다).
  - 개인정보처리방침(별도 저장소)의 보유·삭제 서술 확인은 **오너 몫**이다(design 14장 3번). 이번
    범위가 수집 항목을 늘리지 않았고(기한은 이미 서버에 있는 내 데이터다) 기기 캐시는 로그아웃·탈퇴
    때 덮어쓴다 — 방침 표를 바꿀 일은 없다.
- 설계와 달라진 점
  - **CLAUDE.md 코딩 규칙에 예외 한 줄을 더했다**(설계는 "생성기·발행 실패 예외"만 적었다).
    안내의 "봤음" 기록 읽기·쓰기 실패가 **새로 생긴 로그만 남기는 경로**라서, 적어 두지 않으면
    "에러는 삼키지 않는다"와 코드가 어긋난 채로 남는다. 같은 줄에 **위젯 체크 실패는 삼키지 않는다**
    (위젯 안 한 줄로 말한다)도 함께 적었다.
  - 안내 블록을 **목록 위 자기 자리**에 두었다(design 7.1은 "목록 맨 위"). 목록 안에 넣으면
    `ReorderableListView`의 인덱스와 섞이고(끌어 옮기기가 이 화면의 기능이다) 빈 목록·조회 실패
    갈래에서는 아예 보이지 않는다. 그래서 `body`를 `Column(안내, Expanded(목록))`으로 바꿨고
    목록 본체는 `_todoBody`로 뽑았다(내용은 그대로다).
- 함정 메모
  - `KeepWordsText`는 `Text`가 아니라서 `find.text`가 못 찾는다. 이 저장소의
    `test/helpers/text_finders.dart`의 `findText`를 쓴다(안 쓰면 "0 widgets with text"로 실패한다).
  - `test/tool/widget_resources_test.dart`는 생성기의 색 지도·escape 규칙을 **일부러 베껴** 둔다 —
    한쪽이 바뀌면 이 테스트가 깨져 둘을 함께 보게 하는 것이 목적이다. 깨지면 XML을 손으로 고치지
    말고 생성기를 돌릴 것.
  - 생성기를 돌리면 `widget_resources.xml`이 줄바꿈 때문에 `M`으로 뜬다. 내용이 같으면
    `git checkout --`로 되돌려 커밋 목록을 깨끗하게 둔다.

---

## 커밋 분할용 파일 목록 (2026-11-18 추가 범위, 4~8단계)

커밋 메시지는 design 13.1의 "커밋 제안"을 그대로 쓴다. 단계 경계를 넘는 파일은 없다.

- **4단계** `feat: 위젯 줄을 두껍게 하고 체크 칸을 키운다`:
  `android/app/src/main/res/layout/todo_widget.xml`(줄 구조),
  `android/app/src/main/kotlin/com/todododo/todododo/TodoWidgetProvider.kt`(줄 수 공식·TEXT_IDS),
  `lib/features/todo/data/todo_widget_payload.dart`(`widgetRowCount`),
  `test/features/todo/todo_widget_payload_test.dart`
  → **4·5·7단계는 같은 세 파일을 이어 고치므로 커밋을 나눌 때 `git add -p`가 필요하다.**
- **5단계** `feat: 위젯에 할 일 기한 표시`: `lib/core/strings.dart`,
  `lib/features/todo/data/todo_widget_payload.dart`(기한 키·`formatWidgetDue`),
  `lib/features/todo/domain/due_date_rules.dart`, `TodoWidgetProvider.kt`(`showDue`·`DUE_IDS`),
  `test/features/todo/todo_widget_payload_test.dart`
- **6단계** `feat: 로그아웃·탈퇴 시 위젯 캐시 비우기`:
  `lib/features/todo/domain/todo_widget_service.dart`, `lib/features/auth/data/auth_repository.dart`,
  `lib/features/auth/domain/auth_providers.dart`, `lib/features/auth/presentation/auth_gate.dart`
  (`ref.listen` 블록만), `test/features/auth/logout_widget_cache_test.dart`
- **7단계** `feat: 위젯에서 할 일 완료 처리`:
  `lib/features/todo/data/todo_widget_callback.dart`(신규),
  `lib/features/todo/data/todo_widget_host.dart`, `lib/features/todo/data/todo_widget_payload.dart`
  (결정 함수·`checkFailed(now:)`), `lib/features/auth/presentation/auth_gate.dart`(Stateful 전환),
  `android/app/src/main/kotlin/.../TodoWidgetProvider.kt`(체크 PendingIntent·centerText 톤),
  `android/app/src/main/AndroidManifest.xml`, `test/features/todo/todo_widget_fakes.dart`,
  `test/features/todo/todo_widget_payload_test.dart`
- **8단계** `feat: 위젯 홈 화면 노출 안내`:
  `lib/features/todo/data/todo_widget_notice_store.dart`(신규), `lib/core/strings.dart`,
  `lib/features/todo/domain/todo_providers.dart`,
  `lib/features/todo/presentation/todo_list_screen.dart`,
  `test/features/todo/todo_widget_notice_test.dart`
  / `docs: 위젯 배포 준비`: `DEPLOY.md`, `CLAUDE.md`, `test/tool/widget_resources_test.dart`,
  `docs/specs/home-widget/{spec,design,plan}.md`
