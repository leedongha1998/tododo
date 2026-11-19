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

---

# 2026-11-18 추가 범위 2 — design 13.2의 9~13단계

입력: `docs/specs/home-widget/design.md`의 **13.2**(현재 기준의 단계 분할)와 그것이 가리키는 장
(원칙 2의 추가 범위 2 각주 · 2.2.2 · 2.3.1 · 2.4의 둘째 각주 · 4.6 · 5장 끝 각주 · 6.1.2 · 6.2.2 ·
6.3.1 · 6.4 · 7.2 · 9.2 · 11.3 · 12.3 · 12.4), `docs/specs/home-widget/spec.md`의
`## 2026-11-18 추가 범위 2`(F·G·H·I + 수용 기준 + **오너 확정 4건**).
**결정 필요는 하나도 남아 있지 않다**(design "## 결정 필요 → 2026-11-18 추가 범위 2에 대해: 없음").

**이번 작업 범위는 9~13단계 전부다.** 순서를 바꾸지 않는다 — 9(머리 줄·개수) → 10(완료 줄) →
11(판 경계) → 12(되돌리기) → 13(안내·문서). 그 순서 자체가 "깨지면 그 커밋만 되돌린다"는 설계
결정이고(spec 후퇴 경로 `I → H`), **9와 10을 합치지 않는 이유**도 design 13.2에 적혀 있다
(합치면 실기기에서 "줄이 한 줄 줄었다"와 "완료 줄 규칙이 틀렸다"가 한 커밋에 섞인다).

## 공통 규칙 (위 두 `## 공통 규칙`에 더하는 것)
- **단계 끝마다** `flutter analyze` 이슈 0 + `flutter test` 전부 통과. **네이티브·리소스가 바뀐
  단계(9·10·11·12)는 `flutter build apk --release --dart-define-from-file=env.json`까지** 돌리고
  종료 코드를 `EXIT=$?`로 **따로 찍는다**(`tail`로 파이프하면 종료 코드가 가려진다).
- **스키마 변경 없음, 새 패키지 없음**(design 11.3). `supabase/`·`pubspec.yaml`의 의존성을 건드리면
  범위를 잘못 읽은 것이다.
- 위젯 색·문구 네이티브 리소스는 **생성기로만** 만든다(`flutter test tool/generate_widget_resources.dart`).
  `widget_resources.xml`을 손으로 고치지 않고, 생성기를 고치면 `test/tool/widget_resources_test.dart`도
  함께 맞춘다(그 테스트는 생성기 규칙을 일부러 베껴 둔 대조판이다).
- **캐시 판 번호 `v`를 올리지 않는다**(design 2.2.2). 옛 캐시가 옛 규칙과 같게 읽히게 하는 장치가
  `rank`의 기본값을 **배열 index**로 두는 것(`optInt("rank", index)`)이다 — 그 동작을 바꾸지 않는다.
- **고정비 24dp · 줄 피치 42dp · 상한 6을 바꾸지 않는다**(design 6.2.2). 머리 줄이 옛 아래 note의
  자리를 물려받고 2dp를 루트 아래 여백에서 뺀다.
- 이 세션도 **커밋하지 않는다**. 단계별 파일 목록이 커밋 분할의 기준이다.

## 착수 전 확인 (2026-11-18, 추가 범위 2)
- 기준선: `flutter analyze` 이슈 0, `flutter test` **850개 통과**.
- `env.json`이 저장소 루트에 있다 → 릴리스 빌드를 돌릴 수 있다.
- 1차 범위(4~8단계)는 커밋까지 끝났다(`0de54cc`까지). 작업 트리에서 수정 중인 것은
  `docs/specs/home-widget/{spec,design}.md`뿐이다.

## CLAUDE.md·dev-standards와의 충돌 점검 (2026-11-18, 추가 범위 2)
**구현을 멈춰야 하는 충돌은 없다.** 새로 확인한 항목만 적는다.
- **"판정 로직은 DB/Edge"·"클라이언트에서 승패 계산 금지"** — 이번에도 `todos`만 읽고
  `todos.is_done`만 쓴다(값이 `true` 하나에서 `true|false`로 넓어질 뿐이다. design 11.3).
  대결 테이블·점수·전적에 닿는 경로가 없다.
- **"테스트 없이 판정 로직 수정 금지"** — 판정 로직을 수정하지 않는다. 이번에 늘어나는 판단
  (랭크 규칙·줄 자리 계산·헤더 문장·되돌리기 결정)을 전부 Dart 순수 함수로 두고 유닛 테스트로
  고정한다(design 12.3).
- **"사용자에게 보이는 문자열은 `lib/core/strings.dart`"** — 헤더·개수 문장도 거기서 나간다.
  네이티브가 직접 갖는 `todo_widget_header`는 **생성기가 `AppStrings`에서 뽑는다**(출처가 한 곳).
- **"새 화면 하나 = 새 커밋 하나"** — 새 화면이 없다. 커밋은 13.2의 다섯 단계다.
- **범위 밖 확인**: 다크 모드·완료 자동 정리·완료 시각 열·진도율을 만들지 않는다(spec 범위 밖).

---

## 9단계 — 위젯 머리 줄에 할 일과 개수를 적는다

### 파일
1. `lib/core/strings.dart` — `widgetHeader`(`할 일`), `widgetHeaderCount({done, total})`
   (`할 일 $done/$total`, **낱말을 덧붙이지 않는다** — 오너 확정 2). note 세 문구 단축:
   `widgetNoteFresh` → `$time 기준`, `widgetNoteStale` → `못 불러왔어요 · $time 기준`,
   `widgetCheckFailed` → `체크하지 못했어요 · 앱에서 확인해요`(design 6.1.2의 폭 계산).
2. `lib/features/todo/data/todo_widget_payload.dart` — 최상위 `header` 키 + 상태별 채우기
   (3·3b·4·8만 개수를 적고 1·2·5·6은 `할 일`. 4·8은 **직전 header를 물려받는다**).
3. `android/app/src/main/res/layout/todo_widget.xml` — 머리 줄 `widget_header_row` 신설(헤더 +
   `widget_note` **이사**, id 유지), 루트 `paddingBottom` 4dp → **2dp**, 아래 note 삭제.
4. `android/app/src/main/kotlin/.../TodoWidgetProvider.kt` — 머리 줄 그리기(`header`가 비면 **손대지
   않는다** → 레이아웃 기본값 `할 일`이 남는다).
5. `tool/generate_widget_resources.dart` + 생성물 — `todo_widget_header` 문자열,
   `widget_primary_deep` 색(헤더 글자색).
6. `test/tool/widget_resources_test.dart` — 새 문자열·색 한 칸씩.
7. `test/features/todo/todo_widget_payload_test.dart` — 헤더 문장·note 문구·`widgetRowCount` 225dp.

### 검증
`flutter analyze` 이슈 0 / `flutter test` 통과 / **릴리스 APK 빌드**.

---

## 10단계 — 위젯에서 체크한 줄이 선 그어진 완료 줄로 남는다 (이번 범위의 본체)

### 파일
1. `lib/features/todo/data/todo_widget_payload.dart` — `TodoWidgetItem`에 `done`·`rank`,
   완료 캐시 상한 `todoWidgetMaxDoneItems = 6`, 랭크 규칙(2.2.2), `visibleRows`의 새 몸(6.2.2),
   `fromTodos(justCheckedId:)`, 상태 3b, 머리 주석의 **"판단 넷 → 여섯"**.
2. `lib/features/todo/domain/todo_widget_service.dart` — `markJustChecked`·`publishTodos`(7.2 (1)).
3. `lib/core/navigation/main_shell.dart` — 성공 갈래 한 줄(`publishTodos`). 실패·로딩 갈래는 그대로.
4. `lib/features/auth/presentation/auth_gate.dart` — `_onWidgetCheck`가 `setDone` **앞에서**
   `markJustChecked(todoId)`.
5. `lib/features/todo/data/todo_widget_callback.dart` — `_writeHere`의 `justCheckedId`.
6. `android/app/src/main/res/drawable/widget_row_done.xml`·`widget_check_done.xml`(**신규**).
7. `tool/generate_widget_resources.dart` + 생성물 — `widget_primary` 색.
8. `test/tool/widget_resources_test.dart` — 그 색 한 칸.
9. `android/app/src/main/kotlin/.../TodoWidgetProvider.kt` — `rank` 걸러 내기 + **`rowIndex` 분리**,
   완료 모양 셋(면·제목 색+취소선 span·체크 그림), 클래스 주석의 판단 목록 넷 → 여섯.
10. `test/features/todo/todo_widget_payload_test.dart` — 12.3의 절반(랭크·`visibleRows`·3b·왕복).
11. `test/features/auth/logout_widget_cache_test.dart` 또는 새 테스트 — `markJustChecked`·`publishTodos`.

### 검증
`flutter analyze` 이슈 0 / `flutter test` 통과 / **릴리스 APK 빌드**.

---

## 11단계 — 위젯 판의 경계를 또렷하게
`android/app/src/main/res/drawable/widget_frame.xml`에 1dp `widget_line` `<stroke>` 한 줄(6.4).
검증: analyze / test / **릴리스 APK 빌드**.

---

## 12단계 — 위젯 완료 줄을 다시 눌러 되돌린다

### 파일
1. `lib/features/todo/data/todo_widget_payload.dart` — `TodoWidgetAction.setDone(id, done:)`,
   `todoWidgetActionOf`의 `done`(없거나 모르는 값이면 **완료**로 읽는다 — 옛 PendingIntent 호환),
   결정 함수의 `ignore` 조건(**이미 목표 값이면 무시**).
2. `lib/features/todo/data/todo_widget_callback.dart` — 포트 메시지 셋 + `_writeHere`.
3. `lib/features/auth/presentation/auth_gate.dart` — `_onWidgetCheck`가 길이 3 + 타입 셋 검사.
4. `android/app/src/main/kotlin/.../TodoWidgetProvider.kt` — 체크 Uri에 `done=1|0`.
5. 테스트 — `todoWidgetActionOf`·결정 함수(12.3).

### 검증
analyze / test / **릴리스 APK 빌드**.

---

## 13단계 — 위젯 노출 안내 문구를 넓힌다 + 배포 준비
1. `lib/core/strings.dart` — `widgetNotice`에 "끝낸 할 일과 개수"(7.2 (2)). **"봤음" 키는 바꾸지
   않는다**(아직 배포 전이라 안내를 닫은 사용자가 없다).
2. `DEPLOY.md` — 위젯 확인 줄을 **12.4까지** 넓힌다.
3. `CLAUDE.md` — 범위 서술의 "체크까지 허용"을 **체크·되돌리기**로 한 단어 넓힌다.
4. 생성물 대조 테스트가 새 색·문자열을 덮는지 확인(9·10단계에서 이미 더했으면 확인만).
검증: analyze / test. 릴리스 빌드 불필요.

---

## 진행 기록 (2026-11-18 추가 범위 2)

### 9단계 — 머리 줄(헤더·개수) (구현 완료, 커밋 전, 2026-11-18)
- 파일(수정): `lib/core/strings.dart`(`widgetHeader`·`widgetHeaderCount` 신설, `widgetNoteFresh`·
  `widgetNoteStale`·`widgetCheckFailed` 단축), `lib/features/todo/data/todo_widget_payload.dart`
  (`header` 필드 + 상태별 채우기 + 왕복 + 고정비 주석 갱신),
  `android/app/src/main/res/layout/todo_widget.xml`(머리 줄 신설 + `widget_note` 이사 +
  루트 `paddingBottom` 2dp + 아래 note 삭제),
  `android/app/src/main/kotlin/.../TodoWidgetProvider.kt`(`showHeader` + `FIXED_DP` 주석),
  `tool/generate_widget_resources.dart`(`todo_widget_header`·`widget_primary_deep`),
  `android/app/src/main/res/values/widget_resources.xml`(**생성물**),
  `test/tool/widget_resources_test.dart`, `test/features/todo/todo_widget_payload_test.dart`,
  `lib/core/navigation/main_shell.dart`(주석 한 줄).
  **신규 파일 없음.**
- 검증: `flutter analyze` 이슈 0, `flutter test` **858개 통과**(기준선 850 + 8),
  **릴리스 APK 빌드 성공**(`EXIT=0`, 62.3MB).
- 설계와 달라진 점: 없다(머리 줄 수치·문구 단축·고정비 24dp 유지 전부 design 6.1.2·6.2.2 그대로).
  - 헤더 글자색은 **레이아웃이 `@color/widget_primary_deep`을 직접 참조**하게 뒀다(네이티브가
    `setTextColor`로 칠하지 않는다). design 6.4가 둘 중 어느 쪽이어도 좋다고 적었고, 캐시가 없을
    때·옛 캐시일 때도 색이 맞는 쪽이 레이아웃 참조다.
- 함정 메모
  - **note 문구를 줄이면 네 자리가 함께 깨진다.** `지금은 못 불러왔어요 · …`를 하드코딩한 테스트가
    세 파일(`todo_widget_payload_test`·`todo_widget_publish_test`·`widget_test`)에 있었다.
    문구를 고칠 때 `grep`으로 먼저 찾을 것.
  - 문구 길이를 **글자 수로 테스트하지 말 것.** design이 적은 "17자"는 한글 낱자만 센 값이고 공백·
    가운뎃점을 넣으면 20자다. `startsWith`/`isNot(contains(...))`로 **성질**을 고정했다.
  - `widget_note`의 **id를 그대로 두는 것**이 네이티브 `showNote`와 옛 캐시 호환의 전제다. 머리 줄은
    `widget_rows`를 감싼 `FrameLayout` **밖**(루트의 첫 자식)이어야 한다 — 안에 넣으면
    `widget_center`(match_parent)가 머리 줄을 덮는다.
  - 편집 훅의 `dart format` 실패 보고는 이번에도 거짓 경보였다(`git diff`가 더한 줄뿐이다).

### 10단계 — 완료 줄(`done`·`rank`) (구현 완료, 커밋 전, 2026-11-18)
- 파일(신규): `android/app/src/main/res/drawable/widget_row_done.xml`,
  `android/app/src/main/res/drawable/widget_check_done.xml`.
  파일(수정): `lib/features/todo/data/todo_widget_payload.dart`(`TodoWidgetItem.done`·`rank`,
  `todoWidgetMaxDoneItems`, `_keepDone`·`_ranksOf`, `fromTodos(justCheckedId:)`, 상태 3b,
  `visibleRows` 새 몸, `_itemOf`, 머리 주석 **넷 → 여섯**),
  `lib/features/todo/domain/todo_widget_service.dart`(`markJustChecked`·`publishTodos`),
  `lib/core/navigation/main_shell.dart`(성공 갈래 한 줄),
  `lib/features/auth/presentation/auth_gate.dart`(`markJustChecked` 호출),
  `lib/features/todo/data/todo_widget_callback.dart`(`justCheckedId`),
  `android/app/src/main/kotlin/.../TodoWidgetProvider.kt`(`rank` 걸러 내기 + `rowIndex` 분리 +
  `showRow`·`struckThrough` + 클래스 주석 넷 → 여섯),
  `tool/generate_widget_resources.dart`(`widget_primary`) + 생성물,
  `test/tool/widget_resources_test.dart`, `test/features/todo/todo_widget_payload_test.dart`,
  `test/features/todo/todo_widget_publish_test.dart`, `test/widget_test.dart`.
- 검증: `flutter analyze` 이슈 0, `flutter test` **875개 통과**(858 + 17), 릴리스 APK 빌드(아래).
- 설계와 달라진 점: 없다(랭크 규칙·두 상한·`visibleRows` 새 몸·판 번호 유지 전부 design 2.2.2·6.2.2
  그대로). 다만 **테스트 기대값 하나를 설계의 보기와 맞추며 고쳤다**: design 6.2.2의 보기는
  `justChecked`가 있는 경우이고, 같은 목록에서 `justChecked`가 **없으면** 미완료 4개가 4줄에 딱 들어가
  `그 외` 줄이 아예 생기지 않는다(처음에 `['A','C','D']`를 기대해 실패했다). 두 경우를 **각각** 칸으로
  두었다.
- 함정 메모
  - **`rowIndex`와 항목 index를 겹쳐 쓰지 말 것.** `rank`로 걸러 내므로 "배열 3번째 항목"이
    "2번째 줄"에 들어간다. 겹쳐 쓰면 걸러진 항목 자리에 **빈 줄**이 남는다(design 6.3.1의 경고).
  - 취소선은 `SpannableString` + `StrikethroughSpan`이다. `setInt(id, "setPaintFlags", …)`는
    **컴파일은 되고 적용 시점에 위젯 전체가 깨진다**(`@RemotableViewMethod`가 아니다).
  - 완료 모양은 `setInt(id, "setBackgroundResource", …)` + `setTextColor` + `setImageViewResource`
    셋이고 **미완료 줄에서는 되돌려 쓰지 않는다**(매 그리기가 새 `RemoteViews`라 레이아웃 기본값이
    곧 미완료 모양이다).
  - `ranks.putIfAbsent(id, () => ranks.length)`는 **삽입 전 길이**를 쓴다(Dart의 `putIfAbsent`가
    `ifAbsent()`를 먼저 부른다) — 그래서 0부터 빈틈 없이 매겨진다.
  - `TodoWidgetItem.rank`를 **required로** 두면 기존 테스트의 손으로 만든 항목이 컴파일에서
    걸린다(그게 의도다. 기본값 0을 주면 모든 줄이 rank 0이 되어 조용히 깨진다).
  - `TodoWidgetItem.fromJson`에 **index 인자**가 생겼다(옛 캐시의 `rank` 기본값). 네이티브의
    `optInt("rank", index)`와 같은 규칙이고, 이 둘이 판 번호를 올리지 않아도 되는 근거다.
  - 완료 줄에 기한을 숨기는 일은 **Dart가 캐시에서 끝낸다**(`_itemOf`가 `isDone`이면 기한 키를
    만들지 않는다). 네이티브에 완료 전용 분기를 만들지 말 것.

### 11단계 — 판의 경계 (구현 완료, 커밋 전, 2026-11-18)
- 파일(수정): `android/app/src/main/res/drawable/widget_frame.xml`(1dp `widget_line` `<stroke>` 한 줄
  + 2026-11-04의 "테두리 없음"을 뒤집는 근거 주석). **그 파일 하나뿐이다.**
- 검증: `flutter analyze` 이슈 0, `flutter test` 875개 통과(변화 없음 — Dart가 바뀌지 않았다),
  릴리스 APK 빌드(아래 표).
- 설계와 달라진 점: 없다(모서리 16dp·면 색·그라데이션 없음 전부 그대로).
- 함정 메모: 이 커밋은 **되돌리기가 한 줄**이다(design 13.2가 11단계를 따로 둔 이유). 오너가
  "이건 아니다"라고 하면 색 포인트 셋(9·10단계)을 건드리지 않고 이 줄만 지운다.

### 12단계 — 되돌리기 (구현 완료, 커밋 전, 2026-11-18)
- 파일(수정): `lib/features/todo/data/todo_widget_payload.dart`(`TodoWidgetAction.setDone(id, done:)`
  + `isWrite`, `todoWidgetActionOf`의 `done` 해석, 결정 함수의 바뀐 `ignore` 조건),
  `lib/features/todo/data/todo_widget_callback.dart`(포트 메시지 셋 + `_writeHere`가 목표 값을 쓴다),
  `lib/features/auth/presentation/auth_gate.dart`(길이 3 + 타입 셋 검사 → `setDone(todoId, done)`),
  `android/app/src/main/kotlin/.../TodoWidgetProvider.kt`(체크 Uri에 `&done=1|0`, `CHECK_URI_DONE`),
  `test/features/todo/todo_widget_payload_test.dart`.
- 검증: `flutter analyze` 이슈 0, `flutter test` **879개 통과**(875 + 4), 릴리스 APK 빌드(아래 표).
- 설계와 달라진 점: 없다(목표 값 Uri·`done` 없으면 완료·`ignore` 조건 전부 design 4.6 그대로).
- 함정 메모
  - **`TodoWidgetAction.check`를 지우면 이름이 네 자리에서 걸린다**(`isCheck`까지). `sed`로 한 번에
    고치되 **마지막 한 자리**(`todoWidgetActionOf(null).isCheck`)가 패턴에서 빠지기 쉽다.
  - `done`은 `!= '0'`으로 읽는다(모르는 값·없는 값이 전부 완료로 떨어진다) — 옛 PendingIntent
    호환이 그 기본값의 이유이고, 테스트 칸으로 박아 두었다.
  - **포트 메시지 길이가 2 → 3으로 바뀌는 것이 isolate 경계의 깨지기 쉬운 자리다.** 받는 쪽이
    길이·타입을 검사해 어긋나면 **아무 일도 하지 않으므로**(답할 곳도 모른다) 한쪽만 고치면
    "눌렀는데 아무 일도 안 난다"가 된다. 두 파일을 같은 커밋에 둔다.

### 13단계 — 노출 안내 문구와 배포 준비 (구현 완료, 커밋 전, 2026-11-18)
- 파일(수정): `lib/core/strings.dart`(`widgetNotice`에 "끝낸 할 일과 개수" + "봤음" 키를 바꾸지 않는
  근거 주석), `DEPLOY.md`(위젯 실기기 확인을 **design 12.4까지** 넓힘 — 13칸 추가),
  `CLAUDE.md`(범위 서술의 "체크까지 허용" → **"체크·되돌리기까지 허용"**).
- 문서 확인 결과(고치지 않은 것)
  - **생성물 대조 테스트**(`test/tool/widget_resources_test.dart`)는 9·10단계에서 이미 새 문자열
    하나와 새 색 둘을 덮도록 고쳤다. 13단계에서는 확인만 했다(생성기를 다시 돌려도 결과가 같다).
  - CLAUDE.md의 **개발 명령어 생성기 한 줄**과 **코딩 규칙의 위젯 예외들**은 이미 들어가 있다.
  - 개인정보처리방침 확인은 **오너 몫**이다(design 14장 3번). 이번 범위도 수집 항목을 늘리지 않았다
    (완료 여부는 이미 서버에 있는 내 데이터이고, 기기 캐시는 로그아웃·탈퇴 때 덮어쓴다).
- 검증: `flutter analyze` 이슈 0, `flutter test` **879개 통과**(변화 없음). 네이티브 변경 없음.
- 설계와 달라진 점: 없다.
- 함정 메모: `widgetNotice`는 어느 테스트도 **문장을 하드코딩하지 않는다**(`AppStrings`를 참조한다) —
  그래서 문구를 넓혀도 테스트가 깨지지 않았다. note 문구와 달랐던 자리다.

---

## 커밋 분할용 파일 목록 (2026-11-18 추가 범위 2, 9~13단계)

커밋 메시지는 design 13.2의 "커밋 제안"을 그대로 쓴다. **단계 경계를 넘는 파일이 다섯 있다** —
아래에 표시했고, 그 자리는 `git add -p`로 나눠야 한다.

- **9단계** `feat: 위젯 머리 줄에 할 일과 개수를 적는다`:
  `lib/core/strings.dart`(헤더 둘 + note 셋 단축) ※9·13단계가 이어 고침,
  `lib/features/todo/data/todo_widget_payload.dart`(`header`) ※9·10·12단계가 이어 고침,
  `android/app/src/main/res/layout/todo_widget.xml`(머리 줄·이사·여백),
  `android/app/src/main/kotlin/com/todododo/todododo/TodoWidgetProvider.kt`(`showHeader`·주석)
  ※9·10·12단계가 이어 고침,
  `tool/generate_widget_resources.dart`(문자열 하나 + 색 하나) ※9·10단계가 이어 고침,
  `android/app/src/main/res/values/widget_resources.xml`(**생성물**) ※9·10단계가 이어 고침,
  `test/tool/widget_resources_test.dart` ※9·10단계가 이어 고침,
  `test/features/todo/todo_widget_payload_test.dart` ※9·10·12단계가 이어 고침,
  `lib/core/navigation/main_shell.dart`(주석 한 줄) ※9·10단계가 이어 고침,
  그리고 **문구 단축에 딸린 테스트 세 자리**:
  `test/features/todo/todo_widget_publish_test.dart`(※10단계도 고침), `test/widget_test.dart`
  (※10단계도 고침)
- **10단계** `feat: 위젯에서 체크한 줄이 선 그어진 완료 줄로 남는다`:
  `lib/features/todo/data/todo_widget_payload.dart`(`done`·`rank`·랭크 규칙·`visibleRows`·3b),
  `lib/features/todo/domain/todo_widget_service.dart`,
  `lib/core/navigation/main_shell.dart`(성공 갈래 한 줄),
  `lib/features/auth/presentation/auth_gate.dart`(`markJustChecked`) ※10·12단계가 이어 고침,
  `lib/features/todo/data/todo_widget_callback.dart`(`justCheckedId`) ※10·12단계가 이어 고침,
  `android/app/src/main/res/drawable/widget_row_done.xml`(**신규**),
  `android/app/src/main/res/drawable/widget_check_done.xml`(**신규**),
  `tool/generate_widget_resources.dart`(`widget_primary`) + 생성물,
  `test/tool/widget_resources_test.dart`, `TodoWidgetProvider.kt`(`rank`·`rowIndex`·완료 모양·취소선),
  `test/features/todo/todo_widget_payload_test.dart`,
  `test/features/todo/todo_widget_publish_test.dart`(`markJustChecked` 묶음), `test/widget_test.dart`
- **11단계** `feat: 위젯 판의 경계를 또렷하게`:
  `android/app/src/main/res/drawable/widget_frame.xml` **하나뿐이다**(되돌리기가 한 줄이다)
- **12단계** `feat: 위젯 완료 줄을 다시 눌러 되돌린다`:
  `lib/features/todo/data/todo_widget_payload.dart`(`TodoWidgetAction.setDone`·`done` 해석·`ignore`),
  `lib/features/todo/data/todo_widget_callback.dart`(포트 메시지·목표 값),
  `lib/features/auth/presentation/auth_gate.dart`(길이 3 검사),
  `TodoWidgetProvider.kt`(`&done=1|0`·`CHECK_URI_DONE`),
  `test/features/todo/todo_widget_payload_test.dart`
- **13단계** `feat: 위젯 노출 안내 문구를 넓힌다`: `lib/core/strings.dart`(`widgetNotice`)
  / `docs: 2차 범위 배포 준비`: `DEPLOY.md`, `CLAUDE.md`,
  `docs/specs/home-widget/{spec,design,plan}.md`

**커밋에 넣지 말 것**: `android/.kotlin/`(Kotlin 2.x가 릴리스 빌드 중에 만드는 캐시 디렉터리.
`errors/`·`sessions/`뿐이고 이번 작업과 무관하다 — 무시하거나 별도 커밋에서 `.gitignore`에 올린다).

---

# 2026-11-19 시안 C — design 13.3의 14~16단계

입력: `docs/specs/home-widget/design.md`의 **13.3**(현재 기준의 단계 분할)과 그것이 가리키는 절
(**6.1.3** 레이아웃·수치 · **6.2.3** 세로 예산 · **6.3.2** 네이티브가 한 번 그릴 때 하는 일 +
`reapply()` 전수 표 · **6.4.1** 색 · **9.3** 건드리는 파일 표 · 12.5 · 12.6),
그리고 `.claude/agent-memory/developer/remoteviews_gotchas.md`.
**결정 필요는 남아 있지 않다**(design "## 결정 필요 → 2026-11-19 시안 C에 대해: 묻는 것은 없다").

**이번 작업 범위는 14~16단계 전부고 순서를 바꾸지 않는다** — 14(구분선) → 15(브랜드 띠) →
16(흰 판). 그 순서가 설계 결정이다: 세로 예산을 건드리는 유일한 커밋(14)을 먼저 둬야 실기기에서
"줄 수가 줄지 않았는가"(12.6의 26·28번)를 **그 커밋 하나로** 판정할 수 있고, 되돌리기가 싼
커밋(16은 한 줄)을 뒤에 둬야 후퇴가 `16 → 15 → 14`로 떨어진다.

## 공통 규칙 (위 세 `## 공통 규칙`에 더하는 것)
- **Dart를 한 줄도 건드리지 않는다**(design 9.3). `lib/**`·`test/**`·`tool/**`·`pubspec.yaml`에
  변경이 생기면 범위를 잘못 읽은 것이다. `flutter test`는 **그대로 통과해야 하는** 쪽이고,
  특히 `widgetRowCount`가 빨개지면 세로 예산을 잘못 건드린 것이므로 **멈추고 보고한다**(12.5).
- **고정비 24dp · 줄 피치 42dp · 상한 6을 바꾸지 않는다**(design 6.2.3). 띠 안쪽 패딩은 **4dp가
  상한**이고(6.2.3의 민감도 표: 5dp는 1줄 위젯에서, 6dp는 2줄에서 깨진다) 그 이상을 쓰려면
  `FIXED_DP`를 함께 올려야 하므로 **쓰지 않는다**.
- **단계마다** `flutter analyze` 이슈 0 + `flutter test` 통과 + **`flutter build apk --release
  --dart-define-from-file=env.json`**(세 단계 모두. 이번 범위는 전부 네이티브·리소스라 디버그
  빌드로는 검증되지 않는다). 종료 코드는 `EXIT=$?`로 **따로 찍는다**.
- `res/values/widget_resources.xml`은 **변경 없음**이 정상이다. 단계마다
  `flutter test tool/generate_widget_resources.dart`를 돌려 **diff가 비어 있는지** 보고,
  비어 있지 않으면 멈추고 보고한다(9.3).
- **스키마 변경·새 패키지·새 권한·새 컴포넌트가 하나도 없다.** 필요해 보이면 멈추고 묻는다.
- `design.md`·`redesign-options.md`는 **건드리지 않는다**(메인 세션이 따로 커밋한다). 커밋은
  **경로를 명시해** 스테이징한다.
- **커밋은 단계마다 하나**이고 제목은 13.3 표의 "커밋 제안"을 그대로 쓴다. **푸시하지 않는다.**

## 착수 전 확인 (2026-11-19, 시안 C)
- 기준선: `flutter analyze` 이슈 0, `flutter test` **879개 통과**.
- `env.json`이 저장소 루트에 있다 → 릴리스 빌드를 돌릴 수 있다.
- 추가 범위 2(9~13단계)는 커밋까지 끝났다(`a9a92c3`까지). 작업 트리에서 수정 중인 것은
  `docs/specs/home-widget/design.md`와 새 파일 `redesign-options.md`뿐이고 **둘 다 건드리지 않는다**.
- 필요한 색 넷(`widget_primary`·`widget_danger`·`widget_surface`·`widget_line`)과 `widget_sunken`이
  `widget_resources.xml`에 **이미 있다** → 생성기를 돌릴 일이 없다.

## CLAUDE.md·dev-standards와의 충돌 점검 (2026-11-19, 시안 C)
**구현을 멈춰야 하는 충돌은 없다.** 이번 범위에서 새로 확인한 것만 적는다.
- **"판정 로직은 DB/Edge"·"클라이언트에서 승패 계산 금지"** — 서버·DB·판정에 닿는 경로가 전혀
  없다. 바뀌는 것은 drawable 넷·레이아웃 한 개·Kotlin 그리기 세 자리뿐이다.
- **"테스트 없이 판정 로직 수정 금지"** — 판정 로직을 수정하지 않는다. 이번 범위에 **새 유닛
  테스트가 없는 것이 정상**이고(12.5) 그 근거는 "순수 함수·상수·문구가 하나도 바뀌지 않는다"이다.
- **"사용자에게 보이는 문자열은 `lib/core/strings.dart`"** — 새 문구가 없다.
- **"새 화면 하나 = 새 커밋 하나"** — 새 화면이 없다. 커밋은 13.3의 세 단계다.
- **에러 처리 규칙** — 에러를 다루는 코드를 건드리지 않는다(`showNote`에서 지우는 것은
  `setTextColor` 두 줄뿐이고, 실패를 말하는 일은 **띠 면**이 물려받는다. 6.4.1).
- `remoteviews_gotchas.md` 4번(`reapply()`)이 이번 범위의 **최대 위험**이다 — 칠하는 자리가
  하나(띠) 늘어나므로 6.3.2 (4)의 전수 표를 체크리스트로 훑는다.

---

## 14단계 — 위젯 줄 사이를 구분선으로 바꾼다

### 파일
1. `android/app/src/main/res/drawable/widget_row_line.xml`(**신규**) — `<layer-list>` 한 층:
   `gravity="bottom" height="1dp" left="8dp" right="8dp"` + `solid @color/widget_line`.
   **면을 깔지 않는다**(판의 색이 보여야 한다).
2. `android/app/src/main/res/drawable/widget_row_done_line.xml`(**신규**) — `<layer-list>` 한 층:
   `left="8dp" right="8dp"` + `<shape>` `solid @color/widget_sunken` + `corners 8dp`.
   **구분선 층을 넣지 않는다**(면 자체가 경계다).
3. `android/app/src/main/res/layout/todo_widget.xml` — **줄 6개 전부**에서
   `layout_marginBottom="2dp"` 제거 + `paddingLeft="8dp"` 추가 + `background`를 새 drawable로.
   **하나라도 빠지면 그 줄만 2dp 내려가거나 8dp 왼쪽으로 붙는다**(9.3의 함정).
4. `android/app/src/main/kotlin/.../TodoWidgetProvider.kt` — `showRow`의 drawable 이름 둘을
   `widget_row_line`·`widget_row_done_line`으로. **`else` 가지를 지우지 않는다.**
5. `android/app/src/main/res/drawable/widget_row.xml`·`widget_row_done.xml` — **삭제**
   (9.3 권고: 지우면 참조가 컴파일 에러로 드러나 안전하다).

### 검증
`flutter analyze` 이슈 0 / `flutter test` 통과(`widgetRowCount` 포함) / **릴리스 APK 빌드** /
생성기 diff 비어 있음.

---

## 15단계 — 위젯 머리 줄을 브랜드 띠로

### 파일
1. `android/app/src/main/res/drawable/widget_band.xml`(**신규**) — `solid @color/widget_primary` +
   `<corners>` **위 16dp / 아래 0dp**(판 `widget_frame`의 16dp와 **같은 값**이어야 한다).
2. `android/app/src/main/res/drawable/widget_band_danger.xml`(**신규**) — 같은 모양,
   `solid @color/widget_danger`. 두 파일의 모서리 값이 **반드시 같다**.
3. `android/app/src/main/res/layout/todo_widget.xml` — 루트 `paddingLeft/Right` 8dp → **0**,
   `paddingTop` 4dp → **0**(`paddingBottom` 2dp 유지) / `widget_header_row`에
   `background=@drawable/widget_band` + `paddingLeft/Right=10dp` + `paddingTop/Bottom=4dp`
   (옛 `paddingBottom="2dp"`는 없앤다) / `widget_header` 색 → `@color/widget_surface`,
   `paddingStart=0` / `widget_note` 색 → `@color/widget_surface`, `paddingEnd=0`(**id 유지**) /
   `widget_more` `paddingStart` 2dp → **10dp** / `widget_center`에 `paddingLeft/Right=8dp`.
4. `android/app/src/main/kotlin/.../TodoWidgetProvider.kt` — ① `render` **맨 앞**(캐시를 읽기 전,
   `payload == null`로 돌아가기 **전**)에 띠 배경 `setInt`를 **if/else 양쪽** 분기로,
   ② `showNote`의 `setTextColor` 두 줄 **삭제**, ③ 클래스 주석 한 줄.
   `showCenter`의 색 분기는 **그대로 둔다**(가운데 안내는 띠가 아니라 판 위다).
   판단 목록 "여섯"을 고치지 않는다(새 비교가 아니라 `isDanger()`를 그대로 쓴다).

### 검증
14단계와 같다. 더해서 6.3.2 (4)의 **전수 표를 훑어** 칠하는 자리마다 반대 분기가 있는지 본다.

---

## 16단계 — 위젯 판을 흰 면으로

### 파일
1. `android/app/src/main/res/drawable/widget_frame.xml` — `<solid>`를 `@color/widget_background` →
   **`@color/widget_surface`** 한 줄 + 2026-11-04 주석("앱 화면 배경과 같은 면")을 고친다.
   `<stroke>`·`<corners>`는 **그대로**(흰 판에서 1dp `widget_line`이 밝은 벽지에서 경계를 만드는
   유일한 수단이 되어 더 중요해졌다. 6.4.1).

### 검증
14단계와 같다.

---

## 진행 기록 (2026-11-19 시안 C, 14~16단계)

**세 단계 모두 구현·검증·커밋까지 끝났다. 푸시하지 않았다.** 순서는 계획대로 14 → 15 → 16이고
바꾼 곳이 없다.

| 단계 | 커밋 | analyze | test | 릴리스 APK |
|---|---|---|---|---|
| 기준선 | `a9a92c3` | 이슈 0 | 879개 통과 | — |
| 14 | `242fe24` `feat: 위젯 줄 사이를 구분선으로 바꾼다` | 이슈 0 | 879개 통과 | `EXIT=0` |
| 15 | `fefb6f7` `feat: 위젯 머리 줄을 브랜드 띠로` | 이슈 0 | 879개 통과 | `EXIT=0` |
| 16 | `6fd7872` `feat: 위젯 판을 흰 면으로` | 이슈 0 | 879개 통과 | `EXIT=0` |

- **`flutter test`는 879개가 세 번 다 그대로 통과했다**(12.5가 말한 "그대로 통과해야 하는" 쪽).
  `widgetRowCount` 쪽이 한 번도 빨개지지 않았다 = 세로 예산 상수를 건드리지 않았다는 뜻이다.
- **`flutter test tool/generate_widget_resources.dart`를 단계마다 돌려 `widget_resources.xml`의
  diff가 비어 있음을 확인했다**(9.3의 확인 방법). 세 번 모두 비었다.
- 줄 6개는 `grep`으로 **여섯 자리가 모두 같은 모양**임을 확인하고 커밋했다(9.3의 첫 함정).
- `reapply()` 점검은 6.3.2 (4)의 전수 표를 `setInt`/`setTextColor`/`setViewVisibility`/
  `setImageViewResource`/`setTextViewText` 호출 목록과 **한 줄씩 대조**해 끝냈다. 칠하는 자리마다
  반대 분기가 있고, 띠는 `render` 맨 앞·`payload == null`보다 먼저 양쪽 분기로 칠한다.

### 설계와 다르게 한 곳 (셋, 전부 주석·죽은 인자 수준)
1. **`showNote(context, views, payload)` → `showNote(views, payload)`** — 9.3은 `setTextColor` 두
   줄 삭제만 적었는데, 그러면 `context` 인자가 쓰이지 않게 되어 Kotlin 경고가 남는다. 쓰이지 않는
   인자를 지우고 호출 한 자리를 같이 고쳤다. **동작은 한 자도 바뀌지 않는다.**
2. **`todo_widget.xml` 머리 주석의 줄 수치**(옛 "줄 minHeight 40dp + 아래 여백 2dp(= 간격 42dp)")를
   6.1.3·6.2.3 기준으로 고쳤다. 아래 여백을 없앤 커밋에서 그 설명이 **틀린 설명**이 되기 때문이고,
   9.3이 `widget_frame.xml` 주석에 대해 요구한 것과 같은 성질이다.
3. **머리 줄·헤더·note·showNote·클래스 주석**에 시안 C의 근거를 적었다(9.3이 요구한 클래스 주석 한
   줄보다 길다). 네이티브는 유닛 테스트가 없어 주석이 유일한 안전장치라는 이 파일의 기존 태도를 따랐다.

- 새 패키지·새 권한·새 컴포넌트·스키마 변경은 **하나도 없다**(확인함).
- `design.md`·`redesign-options.md`는 **건드리지 않았다.** 이 `plan.md`의 변경은 커밋하지 않고
  작업 트리에 남겨 둔다 — 문서 커밋(`docs: 시안 C 설계 반영`)은 메인 세션이 따로 한다.
- **남은 일은 오너의 실기기 확인뿐이다**(12.6). 특히 설계가 스스로 확인할 수 없는 칸:
  26·28번(줄 수가 줄지 않았는가), 3번(밝은 벽지에서 흰 판의 경계), 4번(판 모서리 밖으로 띠가
  삐져나오지 않는가), 그리고 `체크하지 못했어요 · 앱에서 확인해요`가 띠에서 몇 글자나 잘리는가
  (6.1.3 (4)의 경계 칸 — 보기 싫으면 미리 정해 둔 조정은 띠 안쪽 가로 패딩 10dp → 8dp다).

---

# 2026-11-19 추가 범위 3 — 체크 반응 속도 (17~20단계)

입력은 `spec.md`의 `## 2026-11-19 추가 범위 3 — 체크 반응 속도`와 `design.md`의 2.2.3 · 4.7 ·
6.3.3 · 9.4 · 11.4 · 12.7 · 12.8 · 13.4(+ 원칙 2 · 3.2 · 3.3 · 4.3 · 4.4 · 4.6의 2026-11-19 추기)다.
**순서·커밋 제목은 13.4 표 그대로**이고 바꾸지 않는다.

## 착수 전 확인

- **충돌 없음.** CLAUDE.md·dev-standards와 spec/design이 어긋나는 자리를 찾지 못했다. 근거:
  - 판정 로직은 그대로 서버에 있다 — 이 범위가 쓰는 것은 `todos.is_done` 하나이고 대결에 닿지 않는다.
  - "테스트 없이 판정 로직 수정 금지"는 걸리지 않는다(판정이 아니다). 그래도 **새 순수 함수 둘
    (`applyCheck`·`todosWithDone`)에는 유닛 테스트를 먼저 박는다**(12.7).
  - "새 화면 하나 = 새 커밋 하나" → 13.4가 이미 네 커밋으로 쪼개 두었고 그대로 따른다.
  - 스키마 변경·새 패키지·새 문구·생성기 변경이 **하나도 없다**(11.4 · 9.4). 생성기는 단계마다 돌려
    `widget_resources.xml`의 diff가 비어 있는지만 확인한다.
  - 네이티브가 캐시를 쓰는 것(탭 자국 네 키)은 원칙 2의 선을 넓히는 일이지만 **design이 그 사실과
    근거·대가를 명시적으로 적고 넓혔다**(원칙 2의 2026-11-19 각주, 결정 필요 3번). 구현이 임의로
    고를 자리가 아니다.
- **오너 확정이 전제다**: L 허용(조건 ①·② 포함) / 절전 모드는 고치지 않고 배포 / 배포 전에 넣는다.

## 공통 규칙 (앞의 `## 공통 규칙`들에 더하는 것)

1. **단계마다** `flutter analyze`(이슈 0) + `flutter test` 통과 + 생성 리소스 diff 비어 있음.
2. **18·19단계는 릴리스 APK까지** 돌린다(`flutter build apk --release --dart-define-from-file=env.json`,
   `EXIT=$?`를 따로 찍는다). 17단계는 Dart만이라 설계가 요구하지 않지만 **19단계가 끝난 뒤 한 번 더**
   돌려 최종 상태를 확인한다.
3. **수명 상수 둘은 Dart·Kotlin 두 사본**(6초 `todoWidgetTapMarkFreshSeconds`/`TAP_MARK_FRESH_MS`,
   60초 `todoWidgetPendingTimeoutSeconds`/`PENDING_TIMEOUT_MS`). `ROW_PITCH_DP`와 같은 규칙이고
   **테스트로 잡히지 않으므로 양쪽 주석에 서로를 적는다**(2.2.3 · 12.7).
4. **`reapply()` 전수 표(6.3.3 (3))를 체크리스트로 훑고 커밋한다.** 행은 하나도 늘지 않고
   **자국이 입력을 바꾸는 자리가 아홉**이다.

## 17단계 — `feat: 위젯 체크 결말을 왕복 한 번으로` (K)

### 파일
| 파일 | 하는 일 |
|---|---|
| `lib/features/todo/data/todo_widget_payload.dart` | `applyCheck`(신규 순수 함수) · `todosWithDone`(신규 순수 함수) · `fromTodos(basisAt:)` · 키 셋 추가(`headerAfterCheck`·`headerAfterUncheck`·`failNote`) |
| `lib/features/todo/domain/todo_widget_service.dart` | `publishChecked(todos, todoId:, done:, now:)` — `_justCheckedId`를 **소비하지 않는다** |
| `lib/features/auth/presentation/auth_gate.dart` | `_onWidgetCheck`에 결말 발행 한 줄(`markJustChecked` → `setDone` → **발행** → `invalidate`) |
| `lib/features/todo/data/todo_widget_callback.dart` | 결말을 `applyCheck`로 · 보정 재조회를 **별도 try**로 · 핸드오프 상한 8초 → **6초**(직접 쓰기에도 같은 상한) |
| `test/features/todo/todo_widget_payload_test.dart` · `todo_widget_publish_test.dart` | 12.7의 칸들 |

### 검증
`flutter analyze` · `flutter test` · 생성기 diff.

## 18단계 — `feat: 위젯 체크 탭을 그 자리에서 그린다` (J)

### 파일
| 파일 | 하는 일 |
|---|---|
| `.../TodoWidgetProvider.kt` | `onReceive` 오버라이드(ACTION_CHECK·ACTION_SWEEP, 나머지 `super`) · 탭 처리(자국 `commit` → `renderAll` → 쓸어내기 알람 → `home_widget` 브로드캐스트) · 체크 PendingIntent를 **우리 리시버**로 · 자국 셋(FRESH/LAPSED/NONE) 렌더 · `failNote`로 되돌림 설명 · 각주 여섯 → 여덟 |
| `lib/features/todo/data/todo_widget_payload.dart` | `pending` 팩토리 **삭제** · `toJson`에서 `pendingId`·`pendingAtMs` **제외**(`fromJson`은 계속 읽는다) · 6초 상수 · 중복 탭 가드가 그 창을 쓰게 |
| `lib/features/todo/data/todo_widget_callback.dart` | `쓰는 중` 발행 **삭제** + 파일 머리 주석에 2026-11-19 추기 |
| 테스트 | `pending` 팩토리 칸을 지우고 "어떤 Dart 발행도 자국 네 키를 싣지 않는다"로 바꾼다 · 6초 창 경계 |

### 함정(9.4)
`super.onReceive` 누락 → 주기 갱신이 통째로 멈춘다 / `FLAG_IMMUTABLE` 필수 / 자국은 `commit()` /
알람은 **부정확**(`set`) / `getAppWidgetIds`에 `ComponentName`.

### 검증
`flutter analyze` · `flutter test` · 생성기 diff · **릴리스 APK**.

## 19단계 — `feat: 위젯 체크를 낙관적으로 보여 준다` (L, 조건 ①·② 포함)

### 파일
| 파일 | 하는 일 |
|---|---|
| `.../TodoWidgetProvider.kt` | 모드 판정 셋(절전 · 활성 네트워크 없음 · 데이터 세이버, **OR**) = 조건 ② · `effectiveDone` 헬퍼 · `totalCount` 보정 · 대체 헤더 고르기 · 낙관 완료 줄의 기한 `GONE` · 체크 Uri 뒤집기 |
| `android/app/src/main/AndroidManifest.xml` | `ACCESS_NETWORK_STATE` 한 줄 + 이유 주석 |

### 함정
`effectiveDone`을 **`undoneShown`에도** 쓸 것(안 쓰면 `그 외 N개`가 1 늘어 "숨은 할 일"이 생긴다 —
설계가 "가장 틀리기 쉬운 한 줄"로 꼽았다) / 읽기가 예외면 `optimistic`(모르는 것을 실패로 단정하지
않는다) / 판정은 **끄는 쪽으로만 틀린다**.

### 검증
`flutter analyze` · `flutter test` · 생성기 diff · **릴리스 APK**(끝난 뒤 최종 상태로 한 번 더).

## 20단계 — `docs: 반응 속도 배포 준비`

- `DEPLOY.md`의 위젯 실기기 확인 줄에 **두 줄**("체크 칸을 누르면 그 자리에서 즉시 반응한다",
  "비행기 모드에서 누르면 줄이 되돌아가고 그 이유가 보인다").
- `TODO_BACKLOG.md`의 절전 모드 줄에 **한 줄 덧붙이기**("2026-11-19: 이 상태에서는 낙관적 반영을
  끈다 — 즉시 반응은 `쓰는 중`"). **그 줄 자체는 지우지 않는다**(spec 확정 2).

---

## 진행 기록 (2026-11-19 추가 범위 3, 17~20단계)

**네 단계 모두 구현·검증·커밋까지 끝났다. 푸시하지 않았다.** 순서는 계획대로 17 → 18 → 19 → 20이고
바꾼 곳이 없다.

| 단계 | 커밋 | analyze | test | 릴리스 APK |
|---|---|---|---|---|
| 기준선 | `4906631` | 이슈 0 | 879개 통과 | — |
| 17 (K) | `d720d1d` `feat: 위젯 체크 결말을 왕복 한 번으로` | 이슈 0 | **903개**(+24) | 불필요(Dart만) |
| 18 (J) | `b9f0924` `feat: 위젯 체크 탭을 그 자리에서 그린다` | 이슈 0 | **904개**(+1) | `EXIT=0` |
| 19 (L) | `1cb3ca5` `feat: 위젯 체크를 낙관적으로 보여 준다` | 이슈 0 | 904개 통과 | `EXIT=0` |
| 20 | `cfeaf08` `docs: 반응 속도 배포 준비` | — | — | 불필요(문서만) |

- **새 유닛 테스트는 25개다**(17단계 24 + 18단계 +1 = `pending` 팩토리 칸 하나를 지우고 자국 칸 둘을
  더했다). 12.7의 칸을 전부 덮었다: `applyCheck` 열둘(①~⑫), `todosWithDone` 둘, `basisAt` 둘,
  새 키 셋 넷, 대체 문장 왕복, 자국의 `toJson` 제외·`fromJson` 유지, 중복 탭 가드의 **6초 경계
  전수**(5.9초 → ignore / 6.1초 → 쓴다 / 59초 → 쓴다), `publishChecked` 셋.
- **생성기(`flutter test tool/generate_widget_resources.dart`)를 단계마다 돌려 `widget_resources.xml`의
  diff가 비어 있음을 확인했다.** 세 번 모두 비었다 — 이번 범위에 새 문구가 한 줄도 없다는 증거다.
- **`reapply()` 점검은 6.3.3 (3)의 전수 표를 체크리스트로 훑었다.** 행이 하나도 늘지 않았고(새로
  칠하는 뷰가 0개) 자국이 입력을 바꾸는 아홉 자리를 `grep`으로 하나씩 대조했다. `effectiveDone`을
  부르는 자리는 **셋뿐**이고(`showRow`·`undoneShown`·`totalCount` 보정) `isDone()`을 직접 부르는
  자리는 **그 헬퍼 안 하나만** 남았다.
- **수명 상수 둘을 양쪽에 같은 값으로 두고 주석으로 묶었다**: `todoWidgetTapMarkFreshSeconds`(6) ↔
  `TAP_MARK_FRESH_MS`(6_000), `todoWidgetPendingTimeoutSeconds`(60) ↔ `PENDING_TIMEOUT_MS`(60_000).
  쓸어내기는 7초(`SWEEP_DELAY_MS`)이고 Dart 핸드오프 상한은 6초다.
- **`ACCESS_NETWORK_STATE`가 Play 권한 목록을 바꾸지 않는 것을 릴리스 병합 결과로 다시 확인했다**
  (`build/app/intermediates/merged_manifests/release/processReleaseManifest/AndroidManifest.xml`):
  권한 집합이 이전과 같고 그 줄은 **한 번만** 나온다.

### 설계와 다르게 한 곳 (셋, 전부 주석·죽은 인자 수준이거나 설계의 근거를 따른 것)

1. **`applyCheck`에서 `danger` 톤이던 note는 톤만 내리지 않고 문장까지 바꾼다.** 4.7 (2)의 표는
   "직전 문장 그대로, 단 tone이 `danger`였으면 `muted`로 내린다"고 적었는데, 그러면 성공한 화면에
   `체크하지 못했어요 · 앱에서 확인해요`가 **색만 흐려진 채 남는다.** 같은 칸이 근거로 적은
   "앞선 체크 실패가 이번 성공으로 지워진다"를 따라 **note를 `… 기준`으로 되돌렸다**(톤은 `muted`).
   `못 불러왔어요 · … 기준`은 표 그대로 **남긴다.** 유닛 테스트로 둘 다 박았다.
2. **`applyCheck`는 대체 머리 줄 둘(`headerAfterCheck`/`headerAfterUncheck`)을 싣지 않는다.**
   4.7 (2)의 표에 출력으로 적혀 있지 않고, 셀 목록이 손에 없어 다시 만들 수도 없다(캐시를 되읽은
   재료에는 개수가 없다). 그 결과 **앱이 죽어 있는 경로에서 1~2초 안에 같은 위젯을 또 누르면 머리
   줄 개수가 그 탭에서는 늦게 맞는다** — 2.2.3이 "없으면 머리 줄을 그대로 둔다"로 이미 정의한
   갈래이고, 뒤따르는 보정 발행이 채워 준다.
3. **`tapMode()`가 18단계에서는 인자를 받지 않는다**(19단계에서 `tapMode(context)`가 된다).
   18단계에 `context`를 받아 두면 쓰이지 않는 인자가 되어 Kotlin 경고가 남는다 — 14~16단계에서
   `showNote`의 죽은 인자를 지운 것과 같은 성질이다. 동작은 한 자도 다르지 않다.

- 그 밖에 **새 패키지·스키마 변경·새 문구·생성기 변경·새 리시버·새 intent-filter는 하나도 없다**
  (확인함). `spec.md`·`design.md`는 **건드리지 않았다.**
- 이 `plan.md`의 변경은 커밋하지 않고 작업 트리에 남겨 둔다 — 문서 커밋은 메인 세션이 따로 한다
  (14~16단계와 같은 방식).
- **남은 일은 오너의 실기기 확인뿐이다**(12.8의 36~48번). 설계가 자동으로 확인할 수 없는 칸이
  이번에는 특히 많다 — 네이티브의 모드 판정·자국·알람·`effectiveDone`은 유닛 테스트로 덮이지
  않는다(12.7이 적어 둔 그대로다).

---

## 21단계 (2026-11-20) — 긴급 회귀 수정: 위젯 체크가 중복 탭으로 버려졌다

**17~20단계(추가 범위 3)가 만든 회귀다.** 오너가 실기기 로그로 원인까지 확정해 넘겼고, 이 단계는
**커밋 하나**로 끝낸다(화면이 늘지 않고 한 버그를 고치는 변경이라 단계별로 쪼개지 않는다).

### 증상 → 원인

- 위젯에서 체크를 누르면 줄이 즉시 완료 모양으로 바뀌고(낙관적 반영은 정상) **7초 뒤 되돌아가며
  `체크하지 못했어요`가 뜬다.** 앱 목록에서는 그 할 일이 계속 미완료 — **서버 쓰기가 아예 일어나지
  않는다.**
- 로그 근거: `HomeWidgetBackgroundWorker`가 **11ms 만에 SUCCESS**(네트워크 왕복이 있을 수 없는
  시간 = Dart가 `ignore`로 바로 돌아 나왔다). 그 뒤 자국이 `FRESH → LAPSED`로 넘어가며 되돌림이
  그려진다.
- 원인은 **순서**다: 네이티브 `onCheckTap`이 자국(`pendingId` 등)을 **먼저 `commit()`하고** 그 다음
  Dart를 깨우므로, 깨어난 `todoWidgetCheckDecisionOf`가 읽는 `pendingId`는 **언제나 이번 탭의
  것**이다 → 중복 탭 가드가 **모든 탭**을 중복으로 판정했다. design 4.7 (6)의 첫 칸("늦게 뜬 쪽이
  언제나 더 새 것")이 보장한 그 순서가, 같은 문서가 Dart에 남겨 둔 중복 탭 가드를 **구조적으로**
  무력화한 것이다(설계가 틀린 자리다 — design 2.2.3 · 4.7 (6)에 추기했다).

### 작업 순서

1. **테스트 먼저**(판정이 아니라 쓰기 경로이지만 같은 태도로 간다 — 지금 코드에서 빨개지는 테스트를
   먼저 둔다):
   - `todoWidgetCheckDecisionOf`에 "네이티브가 **이번 탭의** 자국을 찍은 캐시"를 넣어도
     `handOff`/`writeHere`가 나오는지(양방향). **지금 코드면 `ignore`로 실패한다.**
   - 자국 기반 `ignore`를 기대하던 기존 칸 셋(`같은 줄을 연속으로 두 번…`, `6초가 지난 자국은…`,
     `중복 탭은 방향과 무관하게…`)은 **규칙이 네이티브로 옮겨 가므로** 새 규칙의 칸으로 바꾼다.
   - 옮겨 간 규칙을 **Dart 순수 함수로 뽑아** 테스트한다: `isDuplicateWidgetTap`(id·목표 값·신선도
     비교)과 `widgetTapMarkFresh`(6초 창). 네이티브는 그 둘을 `markOf` + `isDuplicateTap`으로
     그대로 따르고 **주석으로 묶는다**(네이티브는 유닛 테스트가 없다).
2. **Dart** `todo_widget_payload.dart`: `todoWidgetCheckDecisionOf`에서 `pendingId` 기반 가드를
   **없앤다**(나머지 두 조건 — 목록에 없는 id, 이미 목표 값인 줄 — 은 그대로). `_tapMarkStale`는
   `widgetTapMarkFresh`로 흡수되어 사라진다. doc 주석을 사실에 맞게 고친다(지금 주석은 중복 탭을
   여기서 막는다고 적혀 있다).
3. **네이티브** `TodoWidgetProvider.kt`: `onCheckTap`이 **자국을 쓰기 전에** 기존 자국을
   읽어(`markOf`) **같은 id · 같은 목표 값 · `FRESH`면 그 탭을 버린다** — 자국도 다시 쓰지 않고,
   다시 그리지도 않고, 브로드캐스트도 쏘지 않는다. **방향이 다른 탭(같은 id, 다른 `done`)은 중복이
   아니다**(낙관 반영 때문에 사용자는 이미 바뀐 줄을 보고 있고, 그 줄을 다시 누르는 것은
   "되돌리겠다"는 뜻이다). 캐시를 한 번만 읽어 `markTap`에 넘긴다(읽기 두 번을 만들지 않는다).
4. 문서: design **2.2.3**·**4.7 (6)**(+ 4.3 흐름 2, 4.6 (2)의 표, 12.x 테스트 칸)에서 "Dart가 자국을
   읽어 중복 탭을 가른다"고 적힌 자리를 고치고 **왜 틀렸는지**를 한 줄로 남긴다.
5. 검증: `flutter analyze`(이슈 0) · `flutter test`(전부 통과) ·
   `flutter build apk --release --dart-define-from-file=env.json`(네이티브를 건드리므로 필수).

### 진행 기록

- 순서를 바꾼 곳 없음(1 → 5 그대로).
- 커밋: `fix: 위젯 체크가 중복 탭으로 버려지던 것을 고친다` **하나**. 푸시하지 않았다.
- 결과는 아래 "검증 결과"에 적는다.

### 검증 결과

| 항목 | 결과 |
|---|---|
| 테스트 먼저(빨강) | 새 칸 둘(`네이티브가 이번 탭의 자국을 찍은 캐시여도 쓰기로 간다`, `되돌리기 탭도 자국에 막히지 않는다`)이 **고치기 전 코드에서 실패**하는 것을 확인했다(`ignore`가 나왔다) |
| `flutter analyze` | **이슈 0** |
| `flutter test` | **909개 전부 통과**(904 − 3 + 8: 자국 기반 `ignore`를 기대하던 칸 셋을 버리고 여덟을 더했다) |
| `flutter build apk --release --dart-define-from-file=env.json` | **`EXIT=0`**(62.4MB) |

- 바꾼 자리: `lib/features/todo/data/todo_widget_payload.dart`(가드 제거 · 순수 함수 둘 추가 ·
  주석 정정), `android/.../TodoWidgetProvider.kt`(`onCheckTap` 0단계 · `isDuplicateTap` ·
  `markTap`이 캐시를 인자로 받는다), `lib/features/todo/data/todo_widget_callback.dart`(주석 한 줄),
  `test/features/todo/todo_widget_payload_test.dart`, `docs/specs/home-widget/design.md`.
- **네이티브 판단이 여덟에서 아홉이 된다**(두 파일 머리 각주와 design 원칙 2의 각주를 함께 고쳤다).
  새 판단이 늘어난 것이 아니라 **Dart에 있던 판단이 자리를 옮긴** 것이다.
- **규칙을 뽑는 것이 억지가 아니었다**: `isDuplicateWidgetTap`(비교 셋)과
  `widgetTapMarkFresh`(6초 창) 둘로 떨어진다. 네이티브는 `markOf`(FRESH) + `isDuplicateTap`으로
  그 둘을 그대로 따르고, 양쪽 주석이 서로를 가리킨다 — `ROW_PITCH_DP` 쌍과 같은 방식이다.
  **Dart에는 이 둘을 부르는 코드가 없다**(테스트만 부른다). 네이티브를 테스트할 수단이 없으므로
  의도한 비대칭이고, 그 사실을 함수 doc에 적어 두었다.
- 실기기에서 고쳐진 것을 보는 방법: **위젯 체크를 누르면 완료 모양이 7초 뒤 되돌아가지 않고 그대로
  남고, 앱 목록에도 그 할 일이 완료로 들어 있다**(되돌리기도 같다).
- 계획에 없던 정리 하나: `todoWidgetCheckDecisionOf`의 **`now` 인자를 지웠다**(가드가 둘로 줄며
  쓰이지 않게 됐다). 18단계에서 `showNote`의 죽은 인자를 지운 것과 같은 성질이고, 덤으로 **자국의
  나이를 볼 수 없다는 사실이 시그니처에 남는다.** 호출하는 자리는 백그라운드 콜백 하나다.
