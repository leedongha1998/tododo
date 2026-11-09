# todo-due-date 구현 계획

- 기준 문서: `docs/specs/todo-due-date/spec.md`(오너 승인), `docs/specs/todo-due-date/design.md`(오너 승인).
  **설계 11장의 단계 분할을 확정판으로 옮긴 것이 아래 표다.** 설계와 달라진 것은 맨 아래
  "## 설계와 다른 점"에 쌓는다(이 저장소 선례: `docs/specs/redesign/plan.md`).
- **이번 작업 범위는 1~6단계(P0)까지다.** 7~11단계(P1 기한 알림·문서)는 이 문서에 적어 두되
  이번에 구현하지 않는다. P1에 쓸 코드·문구·추상화를 미리 만들지 않는다(spec "범위 밖",
  설계 결정 기록 3·4).
- 커밋은 **메인 세션이 오너 승인을 받아 단계별로 나눠 한다.** 이 작업에서는 작업 트리에만
  변경을 남긴다(`git add`/`commit`/`push` 없음).
- 마이그레이션은 **파일만 만든다.** 원격 적용은 오너 승인 뒤 메인 세션이 한다(설계 12장 1번).

---

## 단계 표 (1~6이 이번 범위, 7~11은 다음)

| # | 단계 | 변경 파일 | 끝 조건 | 테스트 |
|---|---|---|---|---|
| 1 | 남은 시간 두 단위 병기 | `lib/core/remaining_time.dart`(신규·이동), `lib/features/battle/domain/remaining_time.dart`(삭제), `battle_summary.dart`·`battle_detail_screen.dart` import 한 줄씩, `test/core/remaining_time_test.dart`(이동·확장), `test/features/battle/domain/remaining_time_test.dart`(삭제), `battle_summary_test.dart` 기대값 1줄, `TODO_BACKLOG.md` 1줄 삭제 | 대결 화면에서 숫자·단위만 달라진다. 라벨·접미·상태 문구·판정·승부·마감 계산은 그대로 | `test/core/remaining_time_test.dart`(두 단위 병기, 아래 단위 0 생략, 초는 1분 미만만, 1일/1시간/1분 경계, `Duration.zero`). `my_battles_sections_test.dart`는 고치지 않고 통과하는지 확인(설계 3.4) |
| 2 | 기한 컬럼 마이그레이션 | `supabase/migrations/20261109120000_todos_due_at.sql`(신규) | **파일만.** 원격 적용·`supabase db push` 없음. 코드 변경 없음 | 없음(로컬 Docker 없음 → SQL 테스트 수단 없음, 설계 1.2·CLAUDE.md) |
| 3 | 모델·레포지토리·정렬 + 위젯 정합 | `todo.dart`(`dueAt`), `todo_repository.dart`(`updateTodo`, `addTodo` 기한, `fetchTodos`가 `sortedForList`), `lib/features/todo/domain/due_date_rules.dart`(신규: `compareForList`·`sortedForList`), `todo_providers.dart`(`todosProvider`가 정렬 적용 — 리뷰 지적 3), `todo_list_screen.dart`(호출부 컴파일 유지), `todo_widget_payload.dart` 주석 2곳, `test/features/todo/todo_widget_payload_test.dart`, `docs/specs/home-widget/{spec.md,design.md}` 각주 | 목록 순서가 기한 우선으로 바뀌고 위젯이 같은 순서를 따라온다. 화면에 새 문구는 아직 없다 | `test/features/todo/domain/due_date_rules_test.dart`(신규, 정렬): 기한 있음·없음 섞임, 같은 기한은 생성순, 생성 시각까지 같으면 id, 넘긴 기한이 맨 위, 완료가 자리를 바꾸지 않음, 같은 입력을 여러 번 정렬해도 같은 결과 |
| 4 | 로케일 한 벌(ko 고정) | `pubspec.yaml`(`flutter_localizations: {sdk: flutter}`), `pubspec.lock`, `lib/main.dart`(4줄) | 달력·시간 선택이 한국어로 뜬다(**육안 확인은 오너 몫** — 설계 12장 2번) | 자동 테스트 없음. `flutter analyze`·`flutter test`로 회귀만 확인 |
| 5 | 추가·수정 대화상자의 기한 자리 | `todo_list_screen.dart`(`TodoDraft`, `_TodoInputDialog`, 추가·수정 호출부), `lib/core/strings.dart`(입력 문구) | 기한 넣기·바꾸기·지우기가 되고, 제목 그대로 기한만 바꿔도 저장된다. **제목 적고 엔터 = 지금과 같은 타수** | `flutter test` 회귀(기존 투두 위젯 테스트가 그대로 통과해야 한다 — 엔터 경로·수정 경로가 살아 있다는 뜻) |
| 6 | 목록 줄의 남은 시간 | `due_date_rules.dart`(`formatDueLabel`), `lib/core/strings.dart`(목록 문구), `todo_list_screen.dart`(`subtitle`) | 8구간이 화면에 보이고 완료한 줄·기한 없는 줄에는 없다. **여기까지가 P0 = 알림 없이 완결** | `test/features/todo/domain/due_date_rules_test.dart`에 설계 3.2의 8구간 표 + 지남 판정 경계(0.4초). 위젯 테스트: 기한 없는 줄에 둘째 줄이 없다 / 완료한 줄에 기한 문구가 없다 / 넘긴 줄이 경고색이다. 대화상자 `test/features/todo/todo_input_dialog_test.dart`(엔터 경로·기한만 변경·변화 없으면 저장 안 함·기한 지우기), `test/features/todo/data/todo_test.dart`(`due_at` 파싱 3종) |
| 7 | (다음) 알림 패키지·채널만 | `pubspec.yaml`+`lock`, `android/app/build.gradle.kts`, `due_alarm_host.dart`, `MainShell` 초기화 | **`flutter build apk --release --dart-define-from-file=env.json` 통과** | — |
| 8 | (다음) 예약 계획 순수 함수 | `due_alarm_plan.dart` | 호출자 없이 테스트만 | `due_alarm_plan_test.dart` |
| 9 | (다음) 예약 배선·보정·권한 | `due_alarm_service.dart`, providers, `MainShell` 리스너, `AuthRepository`, 대화상자 권한·꺼짐 안내 | spec 알림 수용 기준 | `due_alarm_service_test.dart` |
| 10 | (다음) 알림 탭 처리 | `MainShell` | 알림 탭 → 할 일 탭 | — |
| 11 | (다음) 문서 | `CLAUDE.md`의 **알림 실패 예외** 한 줄, 개인정보처리방침·Play 데이터 보안 확인 기록 (※ i18n 예외 한 줄은 **P0에서 완료** — 4단계가 P0 코드로 먼저 나가므로) | spec "문서" 항목 | — |

각 단계 끝에 `flutter analyze`(이슈 0) + `flutter test`(전부 통과)를 돌리고, 6단계 뒤에 전체를
한 번 더 돌린다(설계 10장).

---

## CLAUDE.md·dev-standards와의 접점 (충돌 없음을 확인한 기록)

구현을 멈춰야 하는 충돌은 **없다.** 스치는 두 곳은 모두 오너가 이미 확정했다.

| 접점 | 결론 |
|---|---|
| CLAUDE.md "다국어(i18n) 세팅" 금지 ↔ 4단계의 `flutter_localizations` | **오너가 2026-11-09에 확정했다**(design.md "결정 기록" 1번). `locale`을 `ko`로 **고정**하고 `.arb`·`gen-l10n`·언어 분기를 만들지 않으므로 다국어 구조가 생기지 않는다. 앱 문구의 출처는 여전히 `lib/core/strings.dart` 하나다 |
| CLAUDE.md "에러를 삼키지 않는다" ↔ 알림 실패를 로그로만 끝내는 설계 원칙 4 | **이번 범위 밖**이다(P1). 7~11단계에서 `CLAUDE.md` 예외 목록에 한 줄 더하는 일이 11단계다. P0에서는 저장·수정·삭제 실패가 지금처럼 토스트를 띄운다 |
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

### 알아 둘 것 (고치지 않고 받아들인 것)

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
- 7~11단계(P1 기한 알림)는 시작하지 않았다. **11단계에 있던 `CLAUDE.md` i18n 예외 한 줄은
  P0에서 완료했다**(`flutter_localizations`가 P0 코드로 먼저 나가므로 그 사이 규칙서와 코드가
  모순이면 안 된다). 11단계에 남은 것은 알림 실패 예외 한 줄과 서류 확인 2건이다.

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
