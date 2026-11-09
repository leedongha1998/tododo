# todo-due-date 구현 계획

- 기준 문서: `docs/specs/todo-due-date/spec.md`(오너 승인), `docs/specs/todo-due-date/design.md`(오너 승인).
  **설계 11장의 단계 분할을 확정판으로 옮긴 것이 아래 표다.** 설계와 달라진 것은 맨 아래
  "## 설계와 다른 점"에 쌓는다(이 저장소 선례: `docs/specs/redesign/plan.md`).
- **1차 작업(2026-11-09)의 범위는 1~6단계(P0)였다.** 그 단계들은 구현·리뷰 반영이 끝났고
  커밋·푸시됐으며 `todos.due_at` 마이그레이션도 원격에 적용됐다.
- **2차 작업(2026-11-10)의 범위는 7~11단계(P1 기한 알림·문서)다.** 아래 표의 7~11행을
  구현 직전에 파일 단위까지 풀어 적었다. 오너가 설계 "결정 기록"에서 확정한 네 건(부정확 예약,
  권한 사전 안내 없음, 앱 안 끄기 설정 없음·채널 분리, 위젯 체크 공백 대비 금지)은 다시
  판단하지 않는다. 범위 밖(스누즈·알림에서 완료·요약 알림·투두별 시점 설정·알림 설정 화면)에
  쓸 코드·추상화를 미리 만들지 않는다.
- 커밋은 **메인 세션이 오너 승인을 받아 단계별로 나눠 한다.** 이 작업에서는 작업 트리에만
  변경을 남긴다(`git add`/`commit`/`push` 없음).
- 마이그레이션은 **파일만 만든다.** 원격 적용은 오너 승인 뒤 메인 세션이 한다(설계 12장 1번).

---

## 단계 표 (1~6은 1차 작업에서 완료, 7~11이 2차 작업의 범위)

| # | 단계 | 변경 파일 | 끝 조건 | 테스트 |
|---|---|---|---|---|
| 1 | 남은 시간 두 단위 병기 | `lib/core/remaining_time.dart`(신규·이동), `lib/features/battle/domain/remaining_time.dart`(삭제), `battle_summary.dart`·`battle_detail_screen.dart` import 한 줄씩, `test/core/remaining_time_test.dart`(이동·확장), `test/features/battle/domain/remaining_time_test.dart`(삭제), `battle_summary_test.dart` 기대값 1줄, `TODO_BACKLOG.md` 1줄 삭제 | 대결 화면에서 숫자·단위만 달라진다. 라벨·접미·상태 문구·판정·승부·마감 계산은 그대로 | `test/core/remaining_time_test.dart`(두 단위 병기, 아래 단위 0 생략, 초는 1분 미만만, 1일/1시간/1분 경계, `Duration.zero`). `my_battles_sections_test.dart`는 고치지 않고 통과하는지 확인(설계 3.4) |
| 2 | 기한 컬럼 마이그레이션 | `supabase/migrations/20261109120000_todos_due_at.sql`(신규) | **파일만.** 원격 적용·`supabase db push` 없음. 코드 변경 없음 | 없음(로컬 Docker 없음 → SQL 테스트 수단 없음, 설계 1.2·CLAUDE.md) |
| 3 | 모델·레포지토리·정렬 + 위젯 정합 | `todo.dart`(`dueAt`), `todo_repository.dart`(`updateTodo`, `addTodo` 기한, `fetchTodos`가 `sortedForList`), `lib/features/todo/domain/due_date_rules.dart`(신규: `compareForList`·`sortedForList`), `todo_providers.dart`(`todosProvider`가 정렬 적용 — 리뷰 지적 3), `todo_list_screen.dart`(호출부 컴파일 유지), `todo_widget_payload.dart` 주석 2곳, `test/features/todo/todo_widget_payload_test.dart`, `docs/specs/home-widget/{spec.md,design.md}` 각주 | 목록 순서가 기한 우선으로 바뀌고 위젯이 같은 순서를 따라온다. 화면에 새 문구는 아직 없다 | `test/features/todo/domain/due_date_rules_test.dart`(신규, 정렬): 기한 있음·없음 섞임, 같은 기한은 생성순, 생성 시각까지 같으면 id, 넘긴 기한이 맨 위, 완료가 자리를 바꾸지 않음, 같은 입력을 여러 번 정렬해도 같은 결과 |
| 4 | 로케일 한 벌(ko 고정) | `pubspec.yaml`(`flutter_localizations: {sdk: flutter}`), `pubspec.lock`, `lib/main.dart`(4줄) | 달력·시간 선택이 한국어로 뜬다(**육안 확인은 오너 몫** — 설계 12장 2번) | 자동 테스트 없음. `flutter analyze`·`flutter test`로 회귀만 확인 |
| 5 | 추가·수정 대화상자의 기한 자리 | `todo_list_screen.dart`(`TodoDraft`, `_TodoInputDialog`, 추가·수정 호출부), `lib/core/strings.dart`(입력 문구) | 기한 넣기·바꾸기·지우기가 되고, 제목 그대로 기한만 바꿔도 저장된다. **제목 적고 엔터 = 지금과 같은 타수** | `flutter test` 회귀(기존 투두 위젯 테스트가 그대로 통과해야 한다 — 엔터 경로·수정 경로가 살아 있다는 뜻) |
| 6 | 목록 줄의 남은 시간 | `due_date_rules.dart`(`formatDueLabel`), `lib/core/strings.dart`(목록 문구), `todo_list_screen.dart`(`subtitle`) | 8구간이 화면에 보이고 완료한 줄·기한 없는 줄에는 없다. **여기까지가 P0 = 알림 없이 완결** | `test/features/todo/domain/due_date_rules_test.dart`에 설계 3.2의 8구간 표 + 지남 판정 경계(0.4초). 위젯 테스트: 기한 없는 줄에 둘째 줄이 없다 / 완료한 줄에 기한 문구가 없다 / 넘긴 줄이 경고색이다. 대화상자 `test/features/todo/todo_input_dialog_test.dart`(엔터 경로·기한만 변경·변화 없으면 저장 안 함·기한 지우기), `test/features/todo/data/todo_test.dart`(`due_at` 파싱 3종) |
| 7 | 알림 패키지·채널만 | `pubspec.yaml`+`pubspec.lock`(`flutter_local_notifications`, `timezone`), `android/app/build.gradle.kts`(core library desugaring), `lib/features/todo/data/due_alarm_host.dart`(신규: 초기화·채널 생성만), `lib/features/todo/domain/todo_providers.dart`(`dueAlarmHostProvider`), `lib/core/strings.dart`(채널 이름), `MainShell.initState` 초기화 한 줄 | **`flutter build apk --release --dart-define-from-file=env.json` 종료 코드 0** + 병합 매니페스트에 `RECEIVE_BOOT_COMPLETED`·`ScheduledNotificationBootReceiver` 확인. 이 단계에 예약 코드는 없다 | `test/features/todo/data/due_alarm_host_test.dart`(`tz.UTC`가 `initializeTimeZones()` 없이 쓰이는지 — 설계 8.1의 "확인 한 줄") |
| 8 | 예약 계획 순수 함수 | `lib/features/todo/domain/due_alarm_plan.dart`(신규: `DueAlarmKind`, `dueAlarmIdOf`, payload 인코딩·디코딩, `DueAlarm`, `PendingDueAlarm`, `planDueAlarms`, `reconcileDueAlarms`, `dueAlarmLeadTime`, `maxDueAlarms`) | 호출자 없이 테스트만(선례: push 2단계). Flutter 의존 없음 | `test/features/todo/domain/due_alarm_plan_test.dart`: 미래 기한→2건 / 1시간 이내→1건 / 지난 기한→0건 / 완료→0건 / 기한 없음→0건 / 임박한 것부터 상한만큼 / id의 시점 비트 / id 충돌 비켜 앉기 / payload 왕복 / 제목을 자르지 않음 / 보정 6갈래(추가만·취소만·기한 변경·변화 없음·모르는 id·같은 id 다른 payload) |
| 9 | 예약 배선·보정·권한 | `due_alarm_host.dart`(`pending`·`schedule`·`cancel`·`cancelAll`), `lib/features/todo/domain/due_alarm_service.dart`(신규), `todo_providers.dart`(`dueAlarmServiceProvider`), `main_shell.dart`(`ref.listen(todosProvider)` 안 한 줄), `auth_repository.dart`+`auth_providers.dart`(로그아웃·탈퇴 때 `cancelAll`), `todo_list_screen.dart`(`_TodoInputDialog` → `ConsumerStatefulWidget`, 권한 요청·꺼짐 안내), `lib/core/strings.dart`(알림 제목 2개·꺼짐 안내) | spec의 알림 수용 기준(권한·취소·보정). 예약·취소 실패가 저장·수정·완료·삭제를 막지 않는다 | `test/features/todo/domain/due_alarm_service_test.dart`(가짜 호스트: 실패해도 예외가 밖으로 안 나감 / 서명이 같으면 플랫폼 호출 없음 / `cancelAll` / 권한은 `notDetermined`일 때만 요청), `test/features/todo/due_alarm_wiring_test.dart`(셸 리스너가 목록 변경에 보정을 돌린다, 로그아웃이 전부 취소한다) |
| 10 | 알림 탭 처리 | `due_alarm_host.dart`(`launchedByNotification`, 탭 콜백), `due_alarm_service.dart`(탭 → `selectedTabProvider`), `main_shell.dart` | 알림 탭 → 할 일 탭. 미로그인에서 탭해도 오류 화면 없음 | `test/features/todo/due_alarm_wiring_test.dart`에 추가(종료 상태에서 시작 / 떠 있는 동안 탭) |
| 11 | 문서 | `CLAUDE.md`의 **알림 실패 예외** 한 줄, 이 `plan.md`의 진행 기록, 개인정보처리방침·Play 데이터 보안 확인 결과 기록 (※ i18n 예외 한 줄은 **1차 작업에서 완료**) | spec "문서" 항목 | — |

각 단계 끝에 `flutter analyze`(이슈 0) + `flutter test`(전부 통과)를 돌리고, 6단계 뒤에 전체를
한 번 더 돌린다(설계 10장). **P1에서는 7단계와 11단계 뒤에 릴리스 빌드까지 돌린다** — 7단계는
새 네이티브 플러그인이 릴리스만 깨뜨린 전력 때문이고(CLAUDE.md 개발 환경), 11단계는 배선이 모두
올라간 최종 상태를 확인하기 위해서다.

---

## CLAUDE.md·dev-standards와의 접점 (충돌 없음을 확인한 기록)

구현을 멈춰야 하는 충돌은 **없다.** 스치는 두 곳은 모두 오너가 이미 확정했다.

| 접점 | 결론 |
|---|---|
| CLAUDE.md "다국어(i18n) 세팅" 금지 ↔ 4단계의 `flutter_localizations` | **오너가 2026-11-09에 확정했다**(design.md "결정 기록" 1번). `locale`을 `ko`로 **고정**하고 `.arb`·`gen-l10n`·언어 분기를 만들지 않으므로 다국어 구조가 생기지 않는다. 앱 문구의 출처는 여전히 `lib/core/strings.dart` 하나다 |
| CLAUDE.md "에러를 삼키지 않는다" ↔ 알림 실패를 로그로만 끝내는 설계 원칙 4 | **충돌이 아니라 예외 추가다.** CLAUDE.md의 그 조항은 이미 예외 목록(VS 인트로 표시 실패 등)을 갖고 있고, 위젯 캐시 발행 실패도 같은 성격으로 로그만 남긴다. 알림 예약·취소 실패를 그 목록에 한 줄 더하는 일이 11단계다(설계 9장이 지시한 문서 변경). 저장·수정·삭제 실패는 P0 그대로 토스트를 띄운다 |
| CLAUDE.md "판정 로직은 DB/Edge Function" ↔ P1이 기기에서 하는 판단 | 충돌 없다. 알림이 판단하는 것은 "언제 울릴지"뿐이고 승패·점수·상태에 닿지 않는다. 서버 변경(새 cron·Edge Function·마이그레이션)이 **하나도 없다** — 이번 작업에서 `supabase/` 아래는 건드리지 않는다 |
| dev-standards "data는 domain을 import하지 않는다" ↔ 설계 8.12의 `due_alarm_host.schedule(DueAlarm)` | **설계의 서명을 바꿨다**(아래 "설계와 다른 점" 13번). `DueAlarm`은 `AppStrings`를 읽는 domain 값이라 호스트가 그것을 받으면 `data`가 `domain`과 사용자 문구에 전이 의존한다 — P0 리뷰 지적 3과 같은 모양이다. 호스트는 원시값(id·시각·제목·본문·payload)만 받는다 |
| CLAUDE.md "판정 로직은 DB/Edge Function" / "테스트 없이 판정 로직 수정 금지" | 이 기능은 대결 테이블을 읽지도 쓰지도 않는다. 1단계가 바꾸는 것은 `formatRemaining`의 **출력 문자열 하나**이고, 그 함수의 유닛 테스트를 새 규칙으로 갱신해 함께 고정한다. `settle_expired_battles()`·상태 전이·점수·한도·제출 시각 비교는 한 줄도 바뀌지 않는다 |
| CLAUDE.md "새 RPC/RLS/SECURITY DEFINER" 규칙 | 해당 없음. 새 테이블·RPC·Edge Function·cron이 없고 2단계는 `alter table ... add column` 하나다. 기존 정책 4개는 컬럼 목록을 갖지 않아 그대로 적용된다(설계 1.3) |
| dev-standards "RPC vs 직접 CRUD" | 개인 투두는 지금처럼 `_client.from('todos')` 직접 CRUD를 쓴다(판정·상태 전이가 걸리지 않는다) |
| dev-standards "순서를 만드는 자리는 하나" / data는 domain을 import하지 않는다 / 테스트는 lib 구조 미러링 | 정렬은 `due_date_rules.dart` 순수 함수 하나이고 적용 자리는 **`todosProvider`** 하나다(레포지토리는 서버 순서를 그대로 돌려준다 — "설계와 다른 점" 10번). 테스트는 `test/features/todo/domain/due_date_rules_test.dart`·`test/features/todo/data/todo_test.dart`·`test/core/remaining_time_test.dart` |

---

## 설계와 다른 점

구현하면서 설계와 달라진 것만 적는다. 없으면 "없다".

1. **3단계에서 `todo_list_screen.dart`를 함께 고친다**(설계 11장은 화면 변경을 5단계로 적었다).
   `updateTitle` → `updateTodo` 서명 교체가 3단계에 있어서, 같은 단계에서 호출부를 고치지 않으면
   컴파일이 깨져 "각 단계 끝에 `flutter analyze`·`flutter test` 통과"라는 끝 조건을 지킬 수 없다.
   3단계의 화면 변경은 **기존 기한 값을 그대로 다시 보내는 한 줄**
   (`updateTodo(todo.id, title: title, dueAt: todo.dueAt)`)로 제한하고, 대화상자 자체는 5단계에서
   바꾼다. 화면에 보이는 변화는 3단계에서 없다.
2. **`AppStrings.todoDueNone`(`기한 없음`)을 만들지 않았다.** 설계 4.1이 더할 문구로 열거했지만
   설계 5.1의 대화상자 레이아웃에는 그 문구가 나오는 자리가 없다(기한이 없을 때는 `기한 추가`
   버튼만 그린다). 목록 줄에도 "기한 없음"을 쓰지 않는 것이 spec의 요구다. 쓰이지 않는 상수를
   미리 두지 않는다(CLAUDE.md "미래 대비 금지"). 필요한 자리가 생기면 그때 넣는다.
3. **`formatDueLabel`은 6단계에서 추가했다**(정렬과 같은 파일 `due_date_rules.dart`에 들어가지만
   설계 11장이 목록 표시를 6단계로 묶었고, 그 문구 상수도 6단계 몫이다). 3단계의
   `due_date_rules.dart`에는 정렬만 들어간다.
4. **4단계에서 `GlobalCupertinoLocalizations.delegate`를 함께 등록했다.** 설계 5.2는
   "Cupertino 위젯을 쓰지 않으니 넣지 않는다"로 적었는데, `WidgetsApp`의 **디버그 검사**가
   `supportedLocales`를 Cupertino까지 포함한 고정 목록으로 확인한다 — 빼면 디버그 빌드와 위젯
   테스트에서 `Warning: This application's locale, ko, is not supported by all of its
   localization delegates`가 예외로 터진다(`test/widget_test.dart`의 "Supabase 미설정" 테스트가
   실제로 깨졌다). Flutter 자신이 권하는 `GlobalMaterialLocalizations.delegates`(복수)를 쓰는
   대신 세 delegate를 **명시적으로** 적고 그 이유를 주석으로 박았다. 앱 문구·범위에는 영향이
   없다(SDK가 이미 가진 번역을 지목하는 것뿐).
5. **6단계의 선택 위젯 테스트를 `test/widget_test.dart`에 넣었다**(새 파일을 만들지 않았다).
   이 저장소는 화면 위젯 테스트를 그 파일 하나에 모으는 선례를 갖고 있다(dev-standards).
   남은 시간 쪽 픽스처는 `dueAt`에 **30초를 더해** 둔다 — 화면이 그려지는 순간의
   `DateTime.now()`가 테스트의 `now`보다 조금 뒤이고 각 단위가 내림이라, 정확히 `1시간 42분`을
   넣으면 `1시간 41분 남음`이 나와 테스트가 간헐적으로 깨진다(실제로 겪어 고친 자리다).
6. **`_TodoInputDialog`를 `StatefulWidget`으로 만들었다**(설계 5.1은 `ConsumerStatefulWidget`).
   `ref`가 필요한 이유가 **P1의 권한 상태 읽기 하나**뿐이라 이번 범위에서는 쓸 자리가 없다.
   9단계에서 권한·꺼짐 안내를 붙일 때 `ConsumerStatefulWidget`으로 바꾼다(미리 만들지 않는다).
7. **`formatDueValue(DateTime local)`을 `due_date_rules.dart`에 더했다.** 설계 4.1은
   `AppStrings.todoDueValue(...)`의 서명만 정했고 `DateTime` → (연·월·일·오전/오후·12시제 시·분)
   변환을 어디에 둘지는 적지 않았다. `todo_widget_payload.dart`의 `formatWidgetTime` 선례대로
   **순수 함수**로 두어 유닛 테스트로 고정했다(자정·정오의 12시 처리, 기본 시각 23:59).
8. **`lib/main.dart`의 `MaterialApp`에 로케일 3줄이 아니라 delegate 3개가 들어갔다**(위 4번과
   같은 이유). 그 밖에 `main.dart`에서 바뀐 것은 없다.
9. **`showTodoInputDialog`는 비공개 `_showTodoInputDialog`로 두었다**(설계 5.1은 공개 서명으로
   적었다). 부르는 곳이 같은 파일의 추가·수정 두 자리뿐이라 공개할 이유가 없고, 지금 함수도
   비공개였다. `TodoDraft`는 테스트·다른 파일에서 읽을 수 있게 공개로 둔다.
10. **`sortedForList` 호출 자리를 `TodoRepository.fetchTodos`에서 `todosProvider`로 옮겼다**
    (설계 2.1은 레포지토리의 반환 직전으로 적었다 — P0 리뷰 지적 3). 이유: `due_date_rules.dart`가
    `core/strings.dart`를 import하므로 레포지토리가 **사용자 문구에 전이 의존**하게 되고,
    `lib/features/*/data`에서 domain을 import하는 파일이 이 저장소에서 그것 하나뿐이어서 계층
    규칙이 깨진다. **설계 원칙 3("순서를 만드는 자리는 하나")은 그대로다** — `fetchTodos`를 부르는
    곳이 `todosProvider` 하나이고, 홈 위젯 발행도 `MainShell`의 `ref.listen(todosProvider)`를
    지나므로 앱과 위젯이 여전히 같은 리스트를 본다. 이 이동에 맞춰 `due_date_rules.dart`·
    `todo_widget_payload.dart`의 "정렬은 `fetchTodos`가 한다"는 주석과 `home-widget/design.md`의
    각주도 새 자리로 고쳤다.
11. **`formatDueLabel`의 반환형을 `({String label, bool overdue})`로 바꿨다**(설계 3.1은
    `String`). 이유: 화면이 색을 고르려고 `!dueAt.isAfter(now)`로 "지났는지"를 **따로** 판정하고
    있었는데 그 술어가 함수 안의 `gap.inSeconds > 0`과 달라, **기한까지 1초 미만 남은 구간에서
    문구는 `방금 지남`인데 색은 보조색**이 됐다(spec 8구간 표 5행의 색은 경고다). 판정을 한
    함수에 모아 다시 어긋날 수 없게 했고, 경계(0.4초 남음)를 덮는 테스트를 더했다.
12. **테스트 자리**: `due_date_rules_test.dart`는 lib 구조를 미러링해
    `test/features/todo/domain/`에 둔다(dev-standards, battle feature 선례). 대화상자 위젯 테스트는
    `test/features/todo/todo_input_dialog_test.dart`(battle feature의 `recruit_sheet_test.dart`·
    `ai_consent_test.dart`처럼 feature 폴더에 둔 화면 테스트 선례), `Todo.fromMap` 유닛은
    `test/features/todo/data/todo_test.dart`. 목록 줄의 두 위젯 테스트만 `test/widget_test.dart`에
    남겼다(그 파일에 이미 투두 목록 테스트가 모여 있다).

13. **`DueAlarmHost`가 `DueAlarm`을 받지 않는다**(설계 8.12는 `schedule(DueAlarm)`·
    `pending() → List<PendingDueAlarm>`로 적었다). 두 값 다 `domain`에 있고 `DueAlarm`은
    `AppStrings`로 제목을 만들므로, 호스트가 그것을 받으면 `data`가 `domain`과 사용자 문구에
    전이 의존한다 — P0 리뷰 지적 3(정렬 호출 자리)과 **같은 모양의 계층 위반**이다. 그래서
    호스트는 원시값(`id`·`at`·`title`·`body`·`payload`)만 받고, 걸려 있는 예약은 구조적 레코드
    `List<({int id, String? payload})>`로 돌려준다. `DueAlarm` → 원시값 풀기와 레코드 →
    `PendingDueAlarm` 담기는 `DueAlarmService`(domain)가 한다. **설계의 뜻은 그대로다** —
    "payload가 진실이고 id는 자리 번호"라는 계약이 레코드에도 그대로 실린다.
14. **매니페스트에 `RECEIVE_BOOT_COMPLETED`와 리시버 두 개를 직접 적었다**(설계 8.2는
    "우리 매니페스트에 적지 않는다 — 패키지가 자기 매니페스트에 넣어 주고 병합으로 들어온다"로
    적었다). **그 서술은 15판까지만 맞다.** `flutter_local_notifications`는 **16판부터** 자기
    매니페스트에 `POST_NOTIFICATIONS`·`VIBRATE`만 남기고 예약 알림용 권한·리시버를 앱 몫으로
    돌렸다(패키지 README "AndroidManifest.xml setup"에서 확인, 설치된 23판의 매니페스트에도
    실제로 둘뿐이다). 적지 않으면 **예약은 되는데 알림이 뜨지 않고** 재부팅 뒤 예약이 사라진다.
    적은 것은 `ScheduledNotificationReceiver`, `ScheduledNotificationBootReceiver`(부팅·패키지
    교체 인텐트 필터), `RECEIVE_BOOT_COMPLETED` 셋이다. **정확 알람 권한은 여전히 적지
    않는다**(오너 확정). 병합 결과(release)에 셋이 모두 들어간 것을 확인했다.
15. **`flutter_local_notifications`는 23.0.0, `timezone`은 0.11.2로 해석됐다**(설계 8.1은
    19/0.10을 예시로 적고 "실제 해석 판을 적는다"고 했다). 23판은 API가 **전부 named 인자**다
    (`initialize(settings:)`, `zonedSchedule(id:, scheduledDate:, notificationDetails:,
    androidScheduleMode:)`, `cancel(id:)`) — 설계가 적어 둔 호출 목록을 그 이름으로 옮겼다.
    `tz.UTC`가 `initializeTimeZones()` 없이 쓸 수 있다는 설계 8.1의 전제는 **사실로 확인했고**
    (`timezone/src/env.dart`의 지연 초기화 top-level) 유닛 테스트로 고정했다 —
    그래서 `flutter_timezone`을 넣지 않았다.
16. **23판을 쓰려고 `android/settings.gradle.kts`의 AGP를 9.1.0 → 9.1.1로, `app/build.gradle.kts`의
    `compileSdk`를 `flutter.compileSdkVersion`(36) → **37 고정**으로 올렸다.** 설계에 없던 변경이고
    **오너가 알아야 할 항목**이라 아래 "오너가 확인할 것"에 따로 적었다. 경위:
    ① 23판의 안드로이드 모듈이 `compileSdk = 37`로 컴파일된다. AGP 9.1.0은 그 요구를
    `android-37`이라는 옛 이름으로 찾는데, 지금 SDK에는 그 패키지가 없다(`platforms;android-37`은
    사라지고 `android-37.0`/`37.1`/`37.2`만 있다) → `Failed to find target with hash string
    'android-37'`. ② AGP 9.1.1(패키지 README가 **최소**로 권하는 판)로 올리니 `android-37.0`을
    base SDK로 알아보고 넘어갔고, 그 다음엔 "이 라이브러리에 의존하는 앱은 37 이상으로 컴파일해야
    한다"로 바뀌었다. ③ 앱 `compileSdk`를 37로 올려 **릴리스 빌드가 통과했다**.
    `targetSdk`·`minSdk`는 **건드리지 않았다**(36/24 그대로) — 런타임 동작과 설치 가능 기기는
    그대로다. `android.builtInKotlin=true`도 그대로다. 대안은 패키지를 설계가 예시로 든 19판대로
    내려 고정하는 것인데, 그러면 AGP·compileSdk는 그대로 두는 대신 보안 수정이 끊긴 옛 판을
    쓰게 되고 **16판부터의 매니페스트 요구(위 14번)는 어차피 같다**.

17. **로그아웃·탈퇴의 예약 취소를 `AuthRepository`가 서비스 객체가 아니라 함수로 받는다**
    (설계 8.12는 "`AuthRepository`에 `dueAlarmServiceProvider`를 함께 넘긴다"로 적었다). 위 13번과
    같은 이유다 — `features/auth/data`가 `features/todo/domain`을 import하면 계층이 거꾸로 선다.
    `auth_repository.dart`에 `typedef CancelDeviceAlarms = Future<void> Function()`을 두고
    조립은 `auth_providers.dart`가 한다(`() => ref.read(dueAlarmServiceProvider).cancelAll()`).
    **취소 자리는 설계 그대로다** — `signOut()`은 `forgetCurrentToken()` 바로 뒤, `deleteAccount()`는
    `delete_account` RPC 뒤이고, 둘 다 실패해도 로그아웃·탈퇴를 막지 않는다(서비스가 삼킨다).
18. **`due_alarm_host.dart`를 7단계에서 통째로 썼다**(단계 표는 `pending`·`schedule`·`cancel`·
    `cancelAll`을 9단계로 적었다). 새 파일은 메인 세션이 커밋을 쪼갤 때 어차피 통째로 한 커밋에
    들어가고, 플러그인 API 이름이 설계가 가정한 판과 달라진 것을 7단계의 릴리스 빌드 자리에서
    한 번에 확인하는 쪽이 안전했다. **7단계의 존재 이유(릴리스 빌드 선검증)는 그대로 지켰다** —
    호스트를 다 쓴 상태에서 릴리스 빌드를 돌려 통과를 확인한 뒤 8단계로 넘어갔다.
19. **9·10단계의 화면 쪽 테스트를 새 파일 대신 기존 파일에 넣었다**(단계 표는
    `test/features/todo/due_alarm_wiring_test.dart`를 적었다). 셸 리스너 테스트는
    `test/widget_test.dart`의 `_pumpMainShellForWidgetCache`(네 탭을 모두 가짜로 고정하는 헬퍼)를
    그대로 쓰는 쪽이 픽스처 중복보다 낫고, 대화상자의 권한·꺼짐 안내 테스트는
    `test/features/todo/todo_input_dialog_test.dart`에 이미 같은 대화상자의 테스트가 모여 있다.
    순수 함수·서비스 테스트는 계획대로 `test/features/todo/domain/`에 두었다.
20. **알림 탭 처리(10단계)가 `MainShell`이 아니라 `DueAlarmService`에 들어갔다**(설계 8.11은
    "둘 다 `MainShell`에서 받아"로 적었다). 탭 콜백은 `initialize`에 넘기는 것이라 호스트를 부르는
    자리(서비스)가 콜백의 주인이고, 셸이 다시 받으면 초기화와 탭 처리가 두 파일로 갈린다.
    셸이 하는 일은 `start()` 한 줄이고, 서비스가 `selectedTabProvider`를 `AppTab.todo`로 바꾼다 —
    **보이는 동작과 "payload를 해석하지 않는다"는 계약은 설계 그대로다.**

21. **`DueAlarmHost.cancelFor(todoId)`를 만들지 않았다**(설계 8.12의 메서드 목록에 있었다).
    쓸 자리가 **위젯에서 체크한 경우의 백그라운드 취소** 하나였고 그 경로는 오너 확정 4번으로
    범위 밖이다(위젯 체크 자체가 아직 없다) — 미리 만들지 않는다(CLAUDE.md).
    설계 8.4가 `cancelFor`에 기대했던 안전장치("payload로 찾아 지우므로 해시 충돌에도 남의 알림을
    지우지 않는다")는 **다른 것이 대신 준다**: `reconcileDueAlarms`는 id가 같아도 payload가 다르면
    취소 대상으로 보고, `DueAlarmService.sync`가 **취소를 전부 돌린 뒤에 예약한다.** 그 순서가
    뒤집히면 보장이 깨지므로 `due_alarm_service.dart`의 그 자리와 `dueAlarmIdOf` 주석에 이유를
    박고 호출 순서를 테스트로 고정했다.
22. **`sync`와 `cancelAll`을 한 줄(`_queue`)로 직렬화했다**(설계에 없던 장치, P1 리뷰 지적 1).
    `sync`는 `pending()` 조회 → 취소 → 예약의 **read-modify-write**인데 `MainShell`이 `unawaited`로
    쏘기 때문에, 두 보정이 겹치면 뒤에 온 쪽이 앞의 중간 상태를 읽어 **완료·삭제한 할 일의 예약이
    남고**, 그 상태에 서명이 기록되면 다음 보정이 조회조차 건너뛰어 **일시적 경합이 영구 오상태로
    굳었다.** 같은 뿌리로 로그아웃이 기다린 `cancelAll` **뒤에** 진행 중이던 `sync`가 예약을
    되살렸다. 서명 비교도 사슬 안으로 옮겼다(밖에서 걸러내면 같은 중간 상태를 두 번 읽는다).
    `TodoWidgetService._lastJson`을 그대로 베낄 수 없는 이유(위젯 발행은 멱등한 단일 쓰기, 예약은
    읽고 고쳐 쓰는 집합)를 코드 주석에 남겼고, 느린 가짜 호스트(`delay`)로 두 증상을 테스트로
    고정했다 — 직렬화를 빼면 그 테스트 셋이 실패하는 것까지 확인했다.
23. **`MainShell`이 셸 시작에 "이미 받아 둔 목록"으로 한 번 더 보정한다**(설계에 없던 한 줄,
    P1 리뷰 지적 2). `ref.listen`은 `fireImmediately`가 아니고 `todosProvider`는 autoDispose가
    아니라 로그아웃 뒤에도 값이 살아 있어서, 같은 프로세스에서 재로그인하면 **리스너가 한 번도
    울리지 않아** 할 일을 건드릴 때까지 예약이 비어 있었다(투두 화면에 당겨서 새로고침도 없다).
    `fireImmediately: true`는 위젯 발행까지 함께 다시 돌리므로 쓰지 않았다. 조회 실패 상태의
    옛 값으로 맞추지 않게 `hasError`를 먼저 본다.

### 알아 둘 것 (고치지 않고 받아들인 것)

- **로그아웃·탈퇴의 예약 취소는 유닛 테스트 + 한 줄 조립으로만 검증된다.** `DueAlarmService.cancelAll`
  자체는 테스트로 고정했지만(취소가 실패해도 예외가 나가지 않는 것까지), `AuthRepository`를 통한
  end-to-end 경로는 자동 테스트가 없다 — `signOut()`이 실제 `SupabaseClient`를 지나므로 테스트에서
  세션을 만들 수단이 없다(기존 테스트들도 전부 `AuthRepository`를 가짜로 바꿔 쓴다). 수동 확인
  항목으로 돌렸다(`docs/manual-test-plan.md` 2-20).
- **`sync`의 서명 건너뛰기는 한 번의 앱 실행 안에서만 유효하다.** 직전에 맞춘 집합과 같으면
  플랫폼을 건드리지 않으므로, 앱이 떠 있는 동안 OS가 예약을 외부에서 비우면 다음 실행까지
  비어 있다. 위젯 캐시(`_lastJson`)가 같은 선택을 했고, 앱을 다시 켜면 보정이 전부 다시 건다.
  (겹친 보정이 서명을 잘못 굳히는 문제는 위 22번에서 직렬화로 막았다.)
- **셸 시작의 보정이 쓰는 캐시가 이전 사용자의 목록일 수 있다**(위 23번). 로그인·로그아웃 때
  `todosProvider`를 무효화하는 자리가 없는 **기존 버그** 때문이다(`TODO_BACKLOG.md`에 남겼다).
  그 상황에서는 화면에도 이미 이전 사용자의 할 일이 보이고 있으므로 이 보정이 새로운 유출을
  만들지는 않으며, 그 무효화가 들어오면 둘이 함께 해결된다.
- **세션이 조용히 끊긴 경우(토큰 만료 등)에는 예약이 남는다**(설계 8.7이 드러낸 틈 그대로).
  명시적 로그아웃·탈퇴만 다루고, 이 틈을 메우려고 세션 감시 경로를 새로 만들지 않았다.
- **위젯에서 체크한 경우의 알림 취소는 여전히 경로가 없다.** 위젯 체크(쓰기) 자체가 구현되지
  않았으므로(home-widget 6단계 몫) 이번에 아무 대비도 만들지 않았다(오너 확정 4번).
- **`locale: ko` 고정의 부수효과**: Material 내장 문구가 **앱 전체에서** 한국어가 된다 — 글자
  선택 메뉴(`복사`·`붙여넣기`), 앱바 뒤로가기 툴팁, 접근성 라벨, 기본 대화상자 버튼까지.
  대결 화면도 그 영향을 받는다. spec이 금지한 "대결 문구 변경"(라벨·접미·상태 한 줄·판정 문구)은
  하나도 바뀌지 않지만, **"대결 쪽 변화는 숫자·단위뿐"이라는 서술에는 이 한 줄을 덧붙여야
  한다**(그 전까지 영어로 보였던 SDK 문구가 한국어로 보인다).
- **수정 대화상자에서 제목을 전부 지우고 저장하면 기한 변경까지 함께 버려진다.** 호출부가
  `draft.title.isEmpty`면 아무 일도 하지 않는 기존 "빈 제목 무시" 동작의 연장이다(빈 제목으로
  저장하는 길을 새로 만들지 않았다). spec에 이 경우의 요구가 없어 기존 동작을 유지했다.
- `firstDate = DateTime(now.year - 1)`은 설계 5.1이 고른 값 그대로 둔다(이미 가진 기한이 그 밖이면
  그쪽으로 넓혀 수정이 막히지 않는다).
- `addTodo`·`updateTodo`가 `dueAt`이 null일 때도 `due_at` 키를 보내는 것은 **설계 의도**다
  (그래야 "기한 지우기"가 PostgREST에서 NULL 쓰기로 성립한다). 조건부로 키를 빼지 않는다.

---

## 오너가 확인할 것 (P1에서 새로 생긴 것)

설계 12장의 목록에 더해, **이번 구현이 설계에 없던 빌드 설정을 건드렸다.** 커밋하기 전에 봐 주길
바라는 것은 이 셋이다.

1. **`android/settings.gradle.kts`의 AGP 9.1.0 → 9.1.1, `android/app/build.gradle.kts`의
   `compileSdk` 36 → 37**(위 "설계와 다른 점" 16번). `flutter_local_notifications` 23을 쓰려면
   둘 다 필요했고, 릴리스 빌드로 통과를 확인했다. `targetSdk`(36)·`minSdk`(24)·
   `android.builtInKotlin=true`는 건드리지 않았다. 받아들이기 어렵다면 대안은 **패키지를 옛 판으로
   내려 고정하는 것**이고(설계가 예시로 든 19판대), 그 경우 AGP·`compileSdk`는 지금 값으로 되돌릴
   수 있다 — 다만 보안 수정이 끊긴 판을 쓰게 되고 매니페스트 요구(14번)는 어차피 같다.
   빌드 머신에 **Android SDK Platform 37.0이 새로 설치됐다**(AGP가 자동으로 받았다).
2. **매니페스트에 리시버 둘과 `RECEIVE_BOOT_COMPLETED`가 들어갔다**(위 14번). 정확 알람 권한은
   들어가지 않았다(오너 확정 그대로). 병합된 release 매니페스트로 둘 다 확인했다.
3. **실기기 확인**: `docs/manual-test-plan.md`의 2-9~2-21(기한·기한 알림). 자동 테스트로 덮을 수
   없는 것만 적었다 — **2-9(릴리스 APK가 실기기에서 그냥 뜨는지)를 가장 먼저** 보고(패키지
   README에 desugaring이 Android 12L 이하에서 Flutter 앱을 죽인 보고가 있다), 그 뒤에 알림이
   실제로 오는지, OS 설정에 `기한 알림` 채널이 따로 보이는지, 권한 다이얼로그가 기한을 처음
   정할 때 한 번만 뜨는지, 재부팅·로그아웃 뒤의 동작을 본다.

---

## 진행 기록

- **2026-11-09: 1~6단계(P0) 구현 완료.** 커밋하지 않았다(작업 트리에만 변경).
- **2026-11-09: P0 리뷰 지적 9건 반영.** 지남 판정을 한 함수로 모음(위 11번), 정렬 호출 자리
  이동(10번), 테스트 자리 정리(12번), 빠진 테스트 셋 3종 추가, 위젯 문서 3곳·`CLAUDE.md` i18n
  예외 1줄, 아래 마이그레이션 순서 서술 수정.
  검증: `flutter analyze` 이슈 0, `flutter test` **646개 전부 통과**(변경 전 612개),
  `flutter build apk --release --dart-define-from-file=env.json` **종료 코드 0**
  (`app-release.apk` 61.5MB). 릴리스 빌드를 P0에서 돌린 이유는 `pubspec.lock`에
  `flutter_localizations`와 전이 의존 `intl`이 들어왔기 때문이다(CLAUDE.md: 새 패키지 추가는
  디버그 빌드만으로 검증되지 않는다). `android.builtInKotlin=true`는 그대로 두었고,
  빌드 로그의 KGP 경고는 `firebase_core`·`home_widget`에 대한 **기존 경고**로 이번 변경과 무관하다.
- **11단계에 있던 `CLAUDE.md` i18n 예외 한 줄은 P0에서 완료했다**(`flutter_localizations`가 P0
  코드로 먼저 나가므로 그 사이 규칙서와 코드가 모순이면 안 된다).
- **2026-11-10: 7~11단계(P1 기한 알림) 구현 완료.** 커밋하지 않았다(작업 트리에만 변경).
  마이그레이션을 새로 만들지 않았고 `supabase/` 아래를 건드리지 않았다 — 이 기능의 서버 변경은
  P0의 컬럼 하나로 끝이고 새 cron·Edge Function·서버 발송 경로가 없다(spec 도메인 경계).
  - 7단계: `flutter_local_notifications` 23.0.0 + `timezone` 0.11.2, `app/build.gradle.kts`의
    desugaring·multiDex·`compileSdk = 37`, `settings.gradle.kts`의 AGP 9.1.1, 매니페스트의
    `RECEIVE_BOOT_COMPLETED`+리시버 둘, `due_alarm_host.dart`, `dueAlarmHostProvider`,
    `AppStrings.todoDueAlarmChannel`, `MainShell` 초기화. 경위는 위 14~16번·18번.
  - 8단계: `due_alarm_plan.dart`(계획·보정 순수 함수) + 테스트 24개. 구현 중 **버그 하나를
    테스트가 잡았다** — payload가 null인 예약을 "원하는 집합에 없음"과 구별하지 못해 영원히
    취소하지 못하는 자리였다(`containsKey`를 먼저 보게 고쳤다).
  - 9단계: `due_alarm_service.dart`, `dueAlarmServiceProvider`, `MainShell`의 리스너 한 줄,
    로그아웃·탈퇴 취소(위 17번), 대화상자의 권한 요청·꺼짐 안내(`_TodoInputDialog`가
    `ConsumerStatefulWidget`이 됐다 — P0의 "설계와 다른 점" 6번이 예고한 자리다).
  - 10단계: 알림 탭 → 할 일 탭(위 20번).
  - 11단계: `CLAUDE.md`의 알림 실패 예외 한 줄 + `compileSdk`·AGP 함정 한 단락,
    `docs/manual-test-plan.md`에 기한·기한 알림 수동 확인 13항목(2-9~2-21), 이 기록,
    아래 "서류 확인 결과".
- **2026-11-10: P1 리뷰 지적 11건 반영.** 보정·전체 취소 직렬화(위 22번), 셸 시작의 재로그인
  보정(23번), 호스트가 `AppStrings`를 읽지 않게 `channelName`을 인자로(13번의 빈 구멍 메우기),
  `cancelFor` 미작성 근거와 취소→예약 순서 주석(21번), `_ensureInitialized`의 동기 throw 처리,
  울릴 시각 식 한 곳으로(`dueAlarmFireTime`), 자리 비켜 앉기를 `freeDueAlarmId`로 떼어 테스트,
  호스트 테스트가 `DueAlarmHost.toScheduleTime`을 직접 부르게, `MainShell`의 중복 try/catch를
  앞단(provider 읽기)만 감싸게 좁힘,
  `CLAUDE.md` 두 곳(AGP 근거·탭 실패 예외), `manual-test-plan.md`에 2-9(실기기에서 앱이 뜨는지),
  `multiDexEnabled` 주석 축소, `TODO_BACKLOG.md`에 `todosProvider` 무효화 누락 한 줄.
  - 검증: `flutter analyze` 이슈 0, `flutter test` **704개 전부 통과**(P1 시작 전 646개 → 새 58개),
    `flutter build apk --release --dart-define-from-file=env.json` **종료 코드 0**
    (`app-release.apk` 61.9MB). 병합된 release 매니페스트에 `RECEIVE_BOOT_COMPLETED`·
    `ScheduledNotificationReceiver`·`ScheduledNotificationBootReceiver`가 들어간 것을 확인했고,
    정확 알람 권한은 들어가지 않은 것도 확인했다. KGP 경고는 `firebase_core`·`home_widget`에
    대한 **기존 경고**로 이번 변경과 무관하다.

### 서류 확인 결과 (11단계, 설계 12장 4번) — 둘 다 **변경 없음**

- **개인정보처리방침**(`C:\workspaces\todododo-legal\privacy.html`): 고칠 것이 없다. 수집 항목
  "나. 이용자가 직접 입력·업로드하는 항목"의 첫 줄이 **`할 일(투두)의 내용`**이고, 기한은 사용자가
  자기 할 일에 직접 적는 그 내용의 한 칸이다. 새 항목·새 목적·새 위탁이 생기지 않는다 —
  **기한 알림은 기기 로컬이라 기기 밖으로 나가는 데이터가 하나도 없다.**
- **Play 데이터 보안(Data safety)**(`DEPLOY.md` 5장의 작성 내용): 고칠 것이 없다. 수집 항목은
  "사용자 생성 콘텐츠"에 그대로 포함되고, 알림 권한(`POST_NOTIFICATIONS`)은 **이미 선언돼 쓰이고
  있었다**(대결 알림). 새로 더한 `RECEIVE_BOOT_COMPLETED`는 데이터를 수집·전송하지 않고 양식이
  묻는 항목도 아니다. 광고·분석 SDK도 그대로 없다.
- 확인하다 눈에 띈 **기존 공백 하나**(이 기능의 범위 밖, 오너 판단 필요): `privacy.html`에
  **알림·FCM 토큰 이야기가 한 줄도 없다.** 기한 알림은 기기 로컬이라 무관하지만, 대결 알림
  (`push-notification`)은 FCM 등록 토큰을 서버(`push_tokens`)에 저장하므로 그 기능을 배포할 때는
  방침에 한 줄이 필요하다. `TODO_BACKLOG.md`에 남겼다.

### 배포 순서 — 마이그레이션 원격 적용이 **앱 배포보다 먼저**다 (선행 조건)

**마이그레이션은 파일만 만들었다** — `supabase/migrations/20261109120000_todos_due_at.sql`.
적용은 오너 승인 뒤 메인 세션이 한다(설계 12장 1번).

`todos.due_at`이 없는 상태에 이 앱 코드가 올라가면 **기한을 쓰지 않는 사용자의 추가·수정까지
전부 실패한다.** `addTodo`·`updateTodo`는 `dueAt`이 null일 때도 본문에 `due_at` 키를 넣으므로
(그래야 "기한 지우기"가 성립한다 — 설계 의도이고 고치지 않는다) PostgREST가 모든 쓰기를
`PGRST204`(column not found)로 거부한다. 읽기(`select()`)는 멀쩡하고 `Todo.fromMap`도 키가 없으면
기한 없음으로 읽으므로, 증상은 **"목록은 보이는데 추가·수정만 전부 실패"**다.

그래서 순서는 **① 마이그레이션 원격 적용 → ② 앱 배포**다. 뒤바뀌면 spec 수용 기준의
"기존 동작 보존"(완료·삭제·수정·체크가 지금과 같다)이 깨진다. 컬럼은 nullable이고 기본값이 없어
**앱보다 먼저 적용해도 옛 앱에는 아무 영향이 없다**(옛 앱은 `due_at`을 보내지도 읽지도 않는다).
