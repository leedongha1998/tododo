# todo-due-date 설계

## 참고

- spec.md: `docs/specs/todo-due-date/spec.md` (2026-11-09 오너 승인, **이 설계의 유일한 요구사항**). 특히 "P0. 남은 시간 문구 — 전체 규칙"의 8구간 표, "P0. 정렬", "P1. 기한 알림", "P1. 도메인 경계", "## 크기 판단", "## 범위 밖", "## 결정 기록"이 기준이다.
- 선례로 읽은 문서: `docs/specs/home-widget/design.md`(네이티브가 섞인 설계의 형식·원칙·단계 분할·"위젯은 관문이 아니다"는 실패 처리 태도, 4장의 백그라운드 isolate 분석), `docs/specs/push-notification/design.md` 계열의 권한 요청 시점 규칙(코드로 확인: `PushService.ensureNotificationPermissionAfterFirstBattle`).
- 근거로 읽은 현재 구현: `lib/features/todo/`(7파일 전부), `lib/features/battle/domain/{remaining_time.dart,battle_summary.dart}`, `lib/features/battle/presentation/battle_detail_screen.dart`(384~419), `lib/core/{strings.dart,navigation/main_shell.dart,push/*,theme/app_palette.dart,theme/app_text.dart,theme/app_icons.dart}`, `lib/features/auth/{data/auth_repository.dart,domain/auth_providers.dart}`, `lib/features/profile/presentation/notification_section.dart`, `lib/main.dart`, `pubspec.yaml`, `pubspec.lock`, `android/{gradle.properties,app/build.gradle.kts,app/src/main/AndroidManifest.xml,app/src/main/kotlin/.../TodoWidgetProvider.kt}`, `supabase/migrations/20260818220000_profiles_and_todos.sql`, `test/`(remaining_time·battle_summary·my_battles_sections·todo_widget_payload), `TODO_BACKLOG.md`.
- **코드를 읽고 확인한 사실 4건**(설계가 여기에 걸려 있다):
  1. `lib/main.dart`에 **로케일 설정이 전혀 없다**(`localizationsDelegates`·`supportedLocales`·`locale` 모두 없음). 저장소 전체에 `flutter_localizations`·`showDatePicker`·`showTimePicker`가 **한 번도 등장하지 않는다** → 5.2가 이 상태에서 출발한다.
  2. `pubspec.lock`에 `flutter_local_notifications`·`timezone`·`intl`이 **없다**. 로컬 알림 수단이 저장소에 하나도 없다 → 8.1.
  3. `android/app/src/main/AndroidManifest.xml:4`에 **`POST_NOTIFICATIONS`가 이미 선언돼 있다**. 권한 요청 경로(`PushMessaging.requestPermission`)도 이미 있다 → 8.2·8.9에서 새로 만들지 않는다.
  4. **홈 위젯의 체크(쓰기) 경로는 아직 구현되지 않았다.** `home-widget` plan의 1~3단계만 구현됐고(4~7단계는 계획만), `todoWidgetActionOf`는 **아무도 부르지 않으며** `registerInteractivityCallback`·`@pragma('vm:entry-point')`가 저장소에 없다. `TodoWidgetProvider.kt`의 `CHECK_IDS`는 선언만 돼 있고 체크 칸 PendingIntent는 6단계 몫이다 → 8.8이 이 사실 위에 서 있다.

---

## 설계 원칙 (전체를 관통하는 5가지)

1. **기한은 개인 투두 안에서만 뜻을 갖는다.** 판정·승부·마감·점수·한도 계산에 닿는 경로를 만들지 않는다. 대결 쪽 변경은 **남은 시간 숫자를 글자로 바꾸는 함수 하나**이고, 그 함수는 서버가 준 시각을 읽어 문장을 만들 뿐이다(spec "P1. 도메인 경계").
2. **판단은 순수 함수에, 표시는 화면에.** 문구 규칙(8구간)·정렬 규칙·알림 예약 계획을 전부 Flutter에 의존하지 않는 순수 함수로 떼어 내 유닛 테스트로 고정한다. 선례는 `todo_widget_payload.dart`(위젯이 그릴 내용을 Dart가 전부 정하고 테스트가 고정한다).
3. **순서를 만드는 자리는 하나다.** 앱 목록·홈 위젯 캐시·알림 예약이 **같은 리스트 객체**를 쓴다. 정렬이 두 곳에서 일어나면 "위젯 첫 줄 ≠ 앱 첫 줄"이 설명할 수 없는 어긋남으로 남는다.
4. **알림은 관문이 아니다.** 예약·취소·권한·초기화의 어떤 실패도 할 일 저장·수정·완료·삭제를 막지 않는다. `debugPrint`만 남기고 토스트를 띄우지 않는다(위젯 캐시 발행과 같은 성격의 예외 — CLAUDE.md 코딩 규칙의 예외 목록에 한 줄 더한다).
5. **기한을 쓰지 않는 사용자의 화면과 타수는 이 기능 전과 똑같다.** 기한 없는 할 일 줄에는 글자가 한 자도 늘지 않고, 제목 적고 엔터 = 지금과 같은 타수다. 이 원칙이 5.1·5.3의 모양을 결정했다.

---

## CLAUDE.md 규칙 대조

| 규칙 | 이 설계에서 |
|---|---|
| 대결 상태 전이·판정 로직은 DB/Edge에서, 화면은 표시만 | 이 기능은 대결 테이블을 **읽지도 쓰지도 않는다**. 대결 쪽 변경은 `formatRemaining`의 출력 문자열 하나뿐이고 `settle_expired_battles()`·상태 전이·점수·한도에 손대지 않는다 |
| 스키마 변경은 마이그레이션 파일로만 | 1.1의 파일 하나(`alter table ... add column due_at`). 대시보드 수정 없음 |
| RLS는 테이블 만들 때 같이 | 새 테이블이 없다. 기존 정책 4개가 컬럼을 열거하지 않으므로 그대로 적용된다(1.3) |
| 새 RPC는 `revoke ... from public, anon` | **새 RPC·새 Edge Function·새 cron이 없다**. 기한 때문에 서버가 하는 일은 값 저장뿐이다 |
| 사용자 FK는 `public.profiles`를 가리킬 것 | 새 테이블이 없어 해당 없음. `todos.user_id`가 `auth.users`를 가리키는 기존 상태는 **건드리지 않는다**(이 기능의 범위가 아니다) |
| 사용자에게 보이는 문자열은 한국어, `lib/core/strings.dart`에 모은다 | 4장에 새 문구 전부와 이름을 적었다. 달력·시간 선택 화면의 한국어화는 5.2 |
| 하드코딩 색은 테마에서 | `AppPalette.inkMuted`(남음)·`AppPalette.danger`(지남). **새 색 토큰을 만들지 않는다**(4.2) |
| 에러는 삼키지 않는다 | 저장·수정·삭제 실패는 기존 토스트 그대로. 알림 관련 실패만 로그로 끝낸다(원칙 4, 예외로 CLAUDE.md에 한 줄 추가) |
| 새 패키지는 기존 것으로 되는지 먼저 확인하고 이유를 커밋에 | 8.1(알림)·5.2(로케일)에서 각각 "기존 것으로 되는가"를 먼저 따졌다. 알림 권한은 **이미 있는 `firebase_messaging`**으로 처리해 `permission_handler`를 넣지 않는다 |
| 새 화면 하나 = 새 커밋 하나 | 11장의 단계가 커밋 단위다(확정은 plan.md) |
| 테스트 없이 판정 로직 수정 금지 | 판정 로직을 수정하지 않는다. 대결 쪽 기존 유닛 테스트는 3.4에서 **지우지 않고 새 기대값으로 고친다** |
| iOS·i18n·미래 대비 추상화 금지 | Android 전용. 반복 일정·태그·알림 시점 설정을 위한 자리를 만들지 않는다. 로케일은 5.2에서 **다국어 구조가 아님**을 따로 논증했다 |
| 릴리스 빌드까지 검증(새 네이티브 패키지) | 8.2·11장·12장에 `flutter build apk --release`와 `android.builtInKotlin` 함정을 박았다 |

---

## 0. 전체 그림과 P0/P1 경계

```
P0 (네이티브 변경 없음, 알림 없이 완결)
  ├ 남은 시간 문구 두 단위 병기            → lib/core/remaining_time.dart (대결 2곳이 함께 바뀜)
  ├ todos.due_at 컬럼                      → 마이그레이션 1개
  ├ Todo 모델 / 레포지토리 / 정렬 순수 함수 → 앱·위젯·(나중에)알림이 쓰는 한 줄기
  ├ 추가·수정 대화상자의 기한 자리          → flutter_localizations(ko) 한 벌
  └ 목록 줄의 남은 시간 한 마디             → subtitle

P1 (네이티브 패키지 1 + Gradle 1줄, 위 위에 올라감)
  ├ flutter_local_notifications + timezone
  ├ 채널 `기한 알림`, 부정확 예약, 부팅 복구
  ├ 예약 계획·보정 순수 함수
  ├ 보정 지점 = MainShell의 todosProvider 리스너(위젯 발행과 같은 자리)
  └ 권한 요청(기한을 처음 정하는 순간) · 꺼짐 안내 한 줄 · 탭하면 할 일 탭
```

**P0만 올라간 상태에서도 기능은 완결된다**(기한 입력·수정·삭제·표시·정렬 + 대결 표기 통일). 릴리스는 P0·P1을 함께 낸다(spec 결정 기록 3차 1번). P1의 릴리스 빌드가 끝내 깨지면 그때 (b)로 분리하는 길이 남아 있고, 그 판단에 필요한 정보는 11장 7단계에서 가장 먼저 나온다.

---

## 1. 데이터·서버

### 1.1 마이그레이션 (파일 하나, 이게 서버 변경의 전부다)

`supabase/migrations/20261109120000_todos_due_at.sql`

```sql
-- 개인 투두의 기한(todo-due-date P0).
--
-- 선택 입력이라 nullable이고 기본값을 두지 않는다 — 기존 행은 전부 null(기한 없음)로 남는다.
-- 생성 시각으로 기한을 추정해 채우는 백필을 하지 않는다(spec "기존 할 일은 모두 기한 없는 상태").
--
-- 대결의 마감(battles.deadline_at, judge_deadline_at)과 아무 관계가 없다. 이 컬럼은
-- settle_expired_battles()·판정·점수·한도 어디에서도 읽히지 않고, 이 컬럼 때문에 생기는
-- cron·Edge Function·서버 발송 경로도 없다(spec "P1. 도메인 경계").
alter table public.todos
  add column due_at timestamptz;

comment on column public.todos.due_at is
  '개인 투두의 기한(UTC). null이면 기한 없음. 기한이 지나도 서버는 아무 일도 하지 않는다(자동 완료·삭제 없음).';
```

- **이 파일에 더 들어가는 것은 없다.** 인덱스·정책·트리거·함수·grant를 함께 넣지 않는다(근거는 1.2·1.3).
- 원격 적용은 오너가 승인한 뒤 메인 세션이 한다(12장).

### 1.2 인덱스: 추가하지 않는다

| 후보 | 판단 |
|---|---|
| `create index todos_user_due_idx on public.todos (user_id, due_at)` | **만들지 않는다** |

근거:
1. **쿼리가 바뀌지 않는다.** `fetchTodos`는 지금처럼 `where user_id = ? order by created_at`이다. 기한 순서는 **서버가 아니라 Dart가 만든다**(2장). 즉 `due_at`으로 정렬·필터하는 SQL이 생기지 않는다.
2. 필터 컬럼은 여전히 `user_id` 하나이고 그 인덱스(`todos_user_id_idx`)가 이미 있다.
3. 한 사용자의 할 일은 수십 행 규모다. 이 크기에서 Postgres는 추가 인덱스를 선택하지도 않고, 쓰기(추가·체크·수정)마다 유지 비용만 든다 — 쓰기가 읽기보다 흔한 테이블이다.
4. **나중에 정렬을 서버로 옮기기로 하면 그때 추가할 인덱스가 정확히 위 후보다**(이 줄이 그 메모다). 미리 만들지 않는다(CLAUDE.md "미래 대비 금지").

### 1.3 RLS·트리거에 영향이 없다는 확인

| 기존 장치 | 새 컬럼의 영향 |
|---|---|
| 정책 4개(select/insert/update/delete, 모두 `auth.uid() = user_id`) | **없음.** Postgres의 RLS 정책은 행 조건식이고 컬럼 목록을 갖지 않는다. 식에 쓰인 컬럼은 `user_id`뿐이라 `due_at`이 생겨도 그대로 평가된다 |
| 테이블 권한(Supabase가 `authenticated`에 테이블 단위로 부여) | **없음.** `grant`가 컬럼 목록 없이 테이블 단위로 걸려 있으면 새 컬럼은 자동으로 포함된다. 컬럼 단위 grant를 쓰는 곳이 없다 |
| `todos_set_updated_at`(before update, `set_updated_at()`) | **없음.** 행 단위 트리거이고 `new.updated_at = now()`만 한다. 기한만 고친 업데이트도 `updated_at`이 올라간다 — 의도한 동작이다 |
| `delete_account` RPC / `auth.users` on delete cascade | **없음.** 행이 지워지면 컬럼도 함께 사라진다 |

### 1.4 `Todo` 모델

`lib/features/todo/data/todo.dart`

```dart
class Todo {
  const Todo({
    required this.id,
    required this.title,
    required this.isDone,
    required this.createdAt,
    this.dueAt,                       // 기한 없음이 기본값이다
  });

  final String id;
  final String title;
  final bool isDone;
  final DateTime createdAt;

  /// 기한. null이면 기한 없음. **UTC로 들고 다니고** 보여 줄 때만 `toLocal()`한다
  /// (서버가 timestamptz를 ISO8601 UTC로 주고, 비교·정렬·알림 예약이 전부 절대 시각이면 된다).
  final DateTime? dueAt;

  factory Todo.fromMap(Map<String, dynamic> map) => Todo(
        id: map['id'] as String,
        title: map['title'] as String,
        isDone: map['is_done'] as bool,
        createdAt: DateTime.parse(map['created_at'] as String),
        dueAt: switch (map['due_at']) {
          final String raw => DateTime.parse(raw).toUtc(),
          _ => null,
        },
      );
}
```

- `copyWith`·`==`를 만들지 않는다(지금도 없고, 쓰는 곳이 없다).

### 1.5 레포지토리 시그니처 — "기한만 지우기"가 "값을 안 보냄"과 구분되는 방법

`lib/features/todo/data/todo_repository.dart`

```dart
Future<List<Todo>> fetchTodos(String userId) async {
  // 서버 정렬은 지금 그대로 둔다(created_at). 화면 순서는 sortedForList가 만든다(2장).
  final rows = await _client
      .from('todos')
      .select()
      .eq('user_id', userId)
      .order('created_at');
  return sortedForList(rows.map(Todo.fromMap).toList());
}

Future<void> addTodo(String userId, String title, {DateTime? dueAt}) {
  return _client.from('todos').insert({
    'user_id': userId,
    'title': title,
    // insert에서 null은 "컬럼 기본값(= null)"과 같다. 둘을 구분할 필요가 없는 유일한 경로다.
    'due_at': dueAt?.toUtc().toIso8601String(),
  });
}

/// 제목과 기한을 **언제나 함께** 쓴다. `updateTitle`을 대신한다.
///
/// 기한을 지우는 길이 이 서명 안에 이미 있다: `dueAt: null`을 넘기면 본문에
/// `"due_at": null`이 **키로 들어가** PostgREST가 컬럼을 NULL로 바꾼다. "값을 안 보냄"은
/// 아예 표현할 수 없다 — 두 인자가 모두 required이므로 호출자가 둘 다 정해야 한다.
/// 부분 업데이트(제목만/기한만)를 만들지 않은 이유: 대화상자가 늘 두 값을 손에 들고 닫히고,
/// 부분 업데이트를 두면 "기한을 지운다"와 "기한을 건드리지 않는다"를 구분하는 센티널이 필요해진다.
Future<void> updateTodo(String id, {required String title, required DateTime? dueAt}) {
  return _client.from('todos').update({
    'title': title,
    'due_at': dueAt?.toUtc().toIso8601String(),
  }).eq('id', id);
}

Future<void> setDone(String id, bool isDone)  // 그대로
Future<void> deleteTodo(String id)            // 그대로
```

- `updateTitle`은 **삭제한다**(호출자는 수정 대화상자 한 곳뿐이다).
- 마지막 쓰기가 이긴다. 다른 기기가 그 사이 기한을 바꿨으면 덮어쓴다 — 지금 제목이 이미 그렇고, 개인 투두에 충돌 해결을 들이지 않는다.

---

## 2. 정렬 — 서버가 아니라 Dart에서, 자리는 레포지토리 하나

> **이 장의 정렬 조항은 2026-11-10 `todo-reorder`로 폐기됐다.** 목록 순서는 기한이 아니라
> **사용자가 끌어 정하고**, 그 순서를 만드는 자리는 Dart가 아니라 **서버의 `order by position`**이다
> (`sortedForList`·`compareForList`는 지워졌다). 아래 본문과, 이 문서에서 "순서는 Dart가 만든다"로
> 읽히는 서술(1.5·4·5장·데이터 흐름·테스트 표의 정렬 관련 줄)은 **그 결정의 이력으로만** 읽을 것 —
> 지금 참인 것은 `docs/specs/todo-reorder/design.md` 2장이다. 이 장에서 **살아 있는 것은 "정렬 규칙을
> 두 곳에 두지 않는다"는 원칙 하나**이고, 그 원칙이 이번에는 "서버 쿼리 한 줄"로 지켜진다.
> 기한의 **표시**(남은 시간 문구·색·8구간 표)와 기한 알림은 이 문서 그대로 유효하다.

### 2.1 서버 `order`로 표현할 수 있는가: 할 수 있다. 그래도 Dart로 한다

`.order('due_at', ascending: true, nullsFirst: false).order('created_at')` 로 "기한 있는 것이 이른 순으로 위, 없는 것은 아래 생성순"을 **정확히** 표현할 수 있다(PostgREST의 `nullslast`, supabase_flutter의 `nullsFirst` 인자).

| 안 | 판단 | 이유 |
|---|---|---|
| A. 서버 `order` 두 개 | 기각 | 순서 규칙이 **유닛 테스트로 고정되지 않는다**. spec "빌드·테스트"가 "정렬 규칙이 유닛 테스트된다"를 요구하고, 로컬 Docker가 없어 DB 테스트를 돌릴 수단도 없다 |
| **B. 서버는 `created_at`만, Dart가 정렬** | **채택** | 규칙이 순수 함수 하나(`compareForList`)가 되어 "기한 있음/없음 섞임·같은 기한·넘긴 기한" 전부 테스트로 박힌다. 앱·위젯·알림이 **같은 리스트 객체**를 받으므로 순서를 만드는 자리가 물리적으로 하나다(원칙 3) |
| C. 둘 다(서버 정렬 + Dart 재정렬) | 기각 | 규칙이 두 곳에 적히고, 한쪽만 고치면 어긋난 줄 아무도 모른다 |

덧붙여: Dart 정렬은 **동순위를 완전히 없앨 수 있다**(`id`까지 내려가는 비교). `List.sort`는 Dart에서 안정 정렬이 **아니므로** 이 전수 비교가 필요하다 — spec "기한이 같은 두 할 일의 순서가 매번 같다"를 지키는 방법이다.

### 2.2 순수 함수

`lib/features/todo/domain/due_date_rules.dart` (신규, Flutter 의존 없음)

```dart
/// 앱 목록·홈 위젯 캐시·기한 알림 예약이 모두 이 순서를 쓴다.
/// **순서를 만드는 자리는 여기 하나다**(design 원칙 3).
///
/// 1) 기한이 있는 것이 기한이 이른 순으로 위
/// 2) 기한이 없는 것은 그 아래, 생성순
/// 3) 기한이 같으면 생성순, 생성 시각까지 같으면 id — 동순위를 남기지 않는다
///    (List.sort는 안정 정렬이 아니라서 매번 같은 순서를 보장하려면 끝까지 갈라야 한다)
/// 4) **완료 여부는 보지 않는다.** 완료한 할 일은 자기 자리에 그대로 남는다(spec).
/// 5) 정렬은 "기한 시각" 자체로 한다 — "남은 시간"으로 하지 않으므로 시간이 흘러도 순서가
///    스스로 바뀌지 않는다.
List<Todo> sortedForList(List<Todo> todos) => [...todos]..sort(compareForList);

int compareForList(Todo a, Todo b) { ... }
```

적용 자리: `TodoRepository.fetchTodos`의 반환 직전(1.5). `todosProvider`가 그 값을 그대로 들고, `TodoListScreen`과 `TodoWidgetPayload.fromTodos`와 `planDueAlarms`가 같은 리스트를 본다. **위젯 쪽 코드는 한 줄도 바뀌지 않는다** — `fromTodos`는 받은 순서를 보존하므로(`where`→`take`) 새 순서가 그대로 캐시에 실린다. 바뀌는 것은 그 사실을 적어 둔 주석·테스트·문서다(9장).

---

## 3. 남은 시간 문구

### 3.1 함수 두 개, 자리 두 곳

지금 `formatRemaining`은 `lib/features/battle/domain/`에 있다. 투두가 함께 쓰게 됐으니 **`lib/core/remaining_time.dart`로 옮긴다**(`lib/core/app_links.dart`처럼 core 바로 아래 평면 배치 — 기존 레이아웃에 맞춘다). 투두 feature가 battle feature를 import하는 모양은 만들지 않는다.

```dart
// lib/core/remaining_time.dart  (대결·투두 공용. 수량만 만든다)

/// 남은(또는 지난) 시간의 **수량 부분**. `남음`·`지남` 같은 접미는 호출자가 붙인다 —
/// 대결은 `AppStrings.battleDeadlineLeft`, 투두는 `formatDueLabel`이 그 자리다.
///
/// 단위 두 개까지 병기하고 각 단위는 내림이며 **아래 단위가 0이면 생략한다**
/// (spec "남은 시간 문구 — 전체 규칙"). 초는 1분 미만 구간에서만 쓴다.
String formatRemaining(Duration gap) {
  if (gap.inDays > 0) {
    final hours = gap.inHours - gap.inDays * 24;
    return hours > 0 ? '${gap.inDays}일 $hours시간' : '${gap.inDays}일';
  }
  if (gap.inHours > 0) {
    final minutes = gap.inMinutes - gap.inHours * 60;
    return minutes > 0 ? '${gap.inHours}시간 $minutes분' : '${gap.inHours}시간';
  }
  if (gap.inMinutes > 0) return '${gap.inMinutes}분';
  return '${gap.inSeconds}초';
}
```

- **이름·서명을 그대로 둔다.** 대결 호출부 두 곳은 import 경로만 바뀌고 조립 코드가 그대로다(3.3).
- 단위 낱말(`일`·`시간`·`분`·`초`)은 지금처럼 이 파일에 둔다. 서식 규칙의 일부이고 이미 그 자리에 있던 것이라 옮기지 않는다 — **문장 단위 문구**(`남음`/`지남`/`방금 지남`)는 전부 `AppStrings`로 간다(4.1).
- `Duration.zero` → `'0초'`(기존 동작·기존 테스트 유지). 음수는 호출자가 먼저 가른다.

```dart
// lib/features/todo/domain/due_date_rules.dart  (투두 전용. 문장을 완성한다)

/// 목록 줄에 쓰는 한 마디. 투두만 쓴다 — "지남"(표 5~8)은 투두 전용이다(spec).
///
/// 경계: 기한 − 지금 > 0이면 "남음", 0 이하면 "지남". 1초 미만 남은 상태도 "방금 지남"으로
/// 묶는다 — `0초 남음`이라는 무의미한 문구를 만들지 않기 위해서다(표 4번의 최솟값은 `1초 남음`).
String formatDueLabel(DateTime dueAt, DateTime now) {
  final gap = dueAt.difference(now);
  if (gap.inSeconds > 0) return AppStrings.todoDueRemaining(formatRemaining(gap));
  final passed = -gap;
  if (passed.inMinutes < 1) return AppStrings.todoDueJustPassed;   // 표 5
  return AppStrings.todoDuePassed(formatRemaining(passed));        // 표 6·7·8
}
```

**"지남" 쪽에 두 번째 함수가 필요하지 않은 이유**(spec 조항을 한 함수로 담는 방법): 표 6·7·8은 표 1·2·3과 **수량 규칙이 완전히 같다**(분 / 시간+분 / 일+시간, 내림, 0 생략). 다른 점은 둘뿐이고 둘 다 `formatDueLabel`이 흡수한다 — ① 1분 미만은 숫자 대신 `방금 지남`이므로 `formatRemaining`의 초 분기에 **도달하지 않는다**, ② 접미가 `지남`이다. 그래서 **수량 함수는 하나, 라벨 조립만 두 곳**이다.

### 3.2 8구간 대조 (구현이 표와 1:1인지 확인하는 표)

| # | 입력 | `formatRemaining` | 최종 문구 |
|---|---|---|---|
| 1 | +3일 12시간 30분 | `3일 12시간` | `3일 12시간 남음` |
| 1 | +2일 0시간 40분 | `2일` | `2일 남음` |
| 1 | 정확히 +24시간 | `1일` | `1일 남음` |
| 2 | +1시간 42분 | `1시간 42분` | `1시간 42분 남음` |
| 2 | +5시간 0분 30초 | `5시간` | `5시간 남음` |
| 2 | 정확히 +60분 | `1시간` | `1시간 남음` |
| 3 | +43분 12초 | `43분` | `43분 남음` (초 병기 없음) |
| 3 | 정확히 +60초 | `1분` | `1분 남음` |
| 4 | +12초 | `12초` | `12초 남음` |
| 5 | 0 (기한 == 지금) | — | `방금 지남` |
| 5 | −30초 | — | `방금 지남` |
| 6 | −7분 | `7분` | `7분 지남` |
| 7 | −12시간 34분 | `12시간 34분` | `12시간 34분 지남` |
| 7 | −3시간 0분 | `3시간` | `3시간 지남` |
| 8 | −3일 5시간 | `3일 5시간` | `3일 5시간 지남` |
| 8 | −3일 0시간 | `3일` | `3일 지남` |

세 단위가 나오는 입력이 없고(`1일 3시간 20분` 같은 문구가 만들어질 경로가 없다), `N일 0시간`·`N시간 0분`이 나올 경로도 없다.

### 3.3 기존 호출자 두 곳 — 무엇이 바뀌고 무엇이 그대로인가

| 자리 | 바뀌는 것 | 그대로인 것 |
|---|---|---|
| `lib/features/battle/domain/battle_summary.dart:113`(`deadlineLineAt`) | import 경로(`../../../core/remaining_time.dart`) | `'$label · $left'` 조립, `battleSubmitDeadlineLabel`·`battleJudgeDeadlineLabel`, `AppStrings.battleDeadlineLeft(...)`의 `남음` 접미, "마감이 지났으면 null" 규칙 |
| `lib/features/battle/presentation/battle_detail_screen.dart:404,418` | import 경로 | `_formatDateTime`(`11월 12일 18:00`), `battleDeadlineClosed`(`마감됨`)·`battleJudgeDeadlineClosed`, 두 라벨, `남음` 접미, 상태 한 줄 문구 전부 |
| `lib/features/battle/domain/remaining_time.dart` | **파일 삭제**(core로 이동) | — |

→ **대결 화면에서 눈에 보이는 변화는 숫자·단위 부분 하나뿐이다**(`1시간 남음` → `1시간 42분 남음`). 마감이 지난 대결은 기존 문구를 그대로 쓴다(지난 시간을 숫자로 말하는 경로가 대결에 없다 — 두 호출부 모두 `isNegative`/`isAfter`로 먼저 가른다. spec "표의 1~4번만 대결에 쓴다"가 코드 구조로 이미 지켜진다).

### 3.4 기존 유닛 테스트가 어떻게 바뀌는지

| 파일 | 조치 |
|---|---|
| `test/features/battle/domain/remaining_time_test.dart` | **`test/core/remaining_time_test.dart`로 옮기고 기대값을 새 규칙으로 고친다**(지우지 않는다). `3일 5시간`→`'3일 5시간'`, `5시간 30분`→`'5시간 30분'`, `30분 30초`→`'30분'`, `24시간`→`'1일'`, `60분`→`'1시간'`, `Duration.zero`→`'0초'`. 새로 더하는 칸: 아래 단위 0 생략 3개(`3일`·`5시간`·`1분`), 1분 미만 초, 1분/1시간/1일 경계 |
| `test/features/battle/domain/battle_summary_test.dart:234` | **기대값 한 줄을 고친다.** 픽스처가 `+90분`이라 `battleDeadlineLeft('1시간')` → `battleDeadlineLeft('1시간 30분')` |
| `test/features/battle/my_battles_sections_test.dart:362,389` | **고치지 않아도 통과한다**(확인함). 픽스처가 `now + 2시간 1분`·`now + 5시간 1분`이라 아래 단위가 0으로 떨어져 `'2시간'`·`'5시간'`이 그대로 나온다. 단계 끝에 실제로 돌려 확인한다 |
| 그 밖 | `test/` 전체에서 `남음`을 쓰는 기대값은 위 둘뿐이다(그 외 2건은 주석) |

---

## 4. 새 문구와 색

### 4.1 `lib/core/strings.dart`에 더하는 것 (전부)

```dart
// ── 개인 투두 기한(todo-due-date) ──
static const todoDueLabel = '기한';
static const todoDueNone = '기한 없음';
static const todoDueAdd = '기한 추가';
static const todoDueClear = '기한 지우기';

/// 목록 줄. 수량은 formatRemaining이 만든다. 값이 battleDeadlineLeft와 같지만 **따로 둔다** —
/// 대결 문구를 고칠 때 투두 문구가 조용히 함께 바뀌지 않게 하려는 것이다.
static String todoDueRemaining(String remaining) => '$remaining 남음';
static String todoDuePassed(String passed) => '$passed 지남';
static const todoDueJustPassed = '방금 지남';

/// 대화상자에서 보여 주는 기한 값: `2026년 11월 12일 오후 6:00`.
/// 올해/작년을 가르지 않고 연도를 늘 적는다(spec).
static String todoDueValue({
  required int year,
  required int month,
  required int day,
  required bool isAm,
  required int hour12,
  required int minute,
}) => '$year년 $month월 $day일 ${isAm ? '오전' : '오후'} $hour12:${minute.toString().padLeft(2, '0')}';

// ── 기한 알림(P1) ──
static const todoDueAlarmChannel = '기한 알림';
static const todoDueAlarmBeforeTitle = '1시간 뒤 기한이에요';
static const todoDueAlarmAtTitle = '지금이 기한이에요';
static const todoDueNotificationsOff = '알림이 꺼져 있어 기한 알림을 보낼 수 없어요.';
```

- `기한 알림을 받으려면 알림을 허용해 주세요.`(spec의 권한 안내 문구)는 **상수를 만들지 않는다.** 권한 다이얼로그는 OS가 그리고 우리가 문장을 끼워 넣을 자리가 없다(`firebase_messaging.requestPermission()`에 rationale 인자가 없다). 거부 상태의 안내는 `todoDueNotificationsOff`가 맡는다 — 이 결정은 "결정 필요" 3번에 올렸다.
- `알림 설정 열기` 문구도 만들지 않는다(8.9에서 그 버튼을 두지 않기로 했다).
- 알림 **채널 설명**도 만들지 않는다(API에서 선택 항목이고, spec에 없는 문구를 새로 지어내지 않는다). OS 설정에는 채널 이름 `기한 알림`만 보인다.

### 4.2 색 — `AppPalette`에 새 토큰을 만들지 않는다

| 상태 | 토큰 | 근거 |
|---|---|---|
| 기한이 남음 | `AppPalette.inkMuted` (#4A5168) | "보조 글자" 역할 그대로. 흰 면 위 대비 8.0 |
| 기한을 넘김 | `AppPalette.danger` (#CC2F3F) | 토큰 설명에 **"위험 텍스트 버튼 글자, 오류 글자"**가 이미 있다 = 글자로 쓰는 경고색이 이미 존재한다. 흰 면 위 대비 약 5.1로 본문 기준 통과 |
| 완료한 할 일 | — | **아무 문구도 그리지 않는다**(spec). 그래서 가라앉은 면(`sunken`) 위의 경고색 대비를 따질 일이 없다 |

`warning`(#A65A00)은 "미결 칩" 전용이고 spec이 말한 "경고색(빨강)"이 아니므로 쓰지 않는다. 단계적 임박색을 만들지 않는다.

---

## 화면

## 5. 화면

화면은 **새로 생기지 않는다.** 바뀌는 자리는 두 곳이다 — 할 일 목록 줄, 추가·수정 대화상자. 로딩·빈 상태·에러 화면은 지금 그대로다(`StatusMessage.loading/empty/error`, 문구 변화 없음).

### 5.1 추가·수정 대화상자 (지금의 공유 다이얼로그를 그대로 확장)

지금 `_showTodoInputDialog`는 `String?`을 돌려주는 무상태 `AlertDialog`다. 기한은 사용자가 고르는 동안 화면에 남아야 하므로 **상태가 필요하다.**

```dart
// lib/features/todo/presentation/todo_list_screen.dart

/// 대화상자가 돌려주는 값. null은 취소다.
class TodoDraft {
  const TodoDraft({required this.title, required this.dueAt});
  final String title;
  final DateTime? dueAt;      // 기기 시간대의 local DateTime(분 단위). 저장 직전에 toUtc().
}

Future<TodoDraft?> showTodoInputDialog(
  BuildContext context, {
  required String dialogTitle,
  String initialTitle = '',
  DateTime? initialDueAt,     // 수정에서 todo.dueAt?.toLocal()을 넘긴다
});
```

내부는 `_TodoInputDialog`(`ConsumerStatefulWidget` — P1에서 권한 상태를 읽어야 한다). 들고 있는 상태는 `TextEditingController`와 `DateTime? _dueAt` 둘뿐이다.

```
AlertDialog
├ title    : '할 일 추가' | '할 일 수정'            (그대로)
└ content  : SingleChildScrollView > Column(mainAxisSize.min, stretch)
   ├ TextField(autofocus: true, hintText: 할 일을 입력하세요,
   │           onSubmitted: → _submit())             ← 지금과 100% 같다
   ├ SizedBox(height: 8)
   ├ ── 기한이 없을 때 ──
   │   Align(centerLeft, TextButton.icon(
   │       icon: AppIcons.clock, label: '기한 추가', onPressed: _pickDue))
   ├ ── 기한이 있을 때 ──
   │   Row
   │     ├ Expanded(TextButton(onPressed: _pickDue,
   │     │      child: Align(centerLeft, KeepWordsText('기한 · 2026년 11월 12일 오후 6:00'))))
   │     └ IconButton(icon: AppIcons.close, tooltip: '기한 지우기',
   │              onPressed: () => setState(() => _dueAt = null))
   └ (P1, 조건부) KeepWordsText('알림이 꺼져 있어 기한 알림을 보낼 수 없어요.', bodySmall/inkMuted)
       └ _dueAt != null && 권한 == denied 일 때만 그린다
actions   : [취소, 저장]                              (그대로)
```

**"기한을 쓰지 않는 사용자의 타수가 늘지 않는다"를 지키는 방식**:
- `TextField`가 여전히 `autofocus: true`이고 `onSubmitted`가 그대로 저장으로 간다 → **제목 적고 엔터 = 1타, 지금과 같다.**
- 기한 줄은 입력 칸 **아래**에 있고 포커스 순서에 끼어들지 않는다. 날짜를 고르라고 막는 단계가 없다.
- `저장`을 누를 때 `_dueAt`이 null이면 기한 없는 할 일이 된다(추가 확인·경고 없음).
- 새 요소는 **버튼 한 개**(기한 없음 상태)뿐이라 대화상자 높이가 한 줄 늘어난다. `SingleChildScrollView`로 감싸는 이유는 1.5배 글자 + 키보드에서 내용이 잘리지 않게 하는 것이다.

`_pickDue()`의 흐름:

```dart
final base = _dueAt ?? DateTime.now();
final date = await showDatePicker(
  context: context,
  initialDate: base,
  // 규칙상의 한도가 아니라 달력 위젯이 요구하는 범위다(spec "기한의 하한·상한을 두지 않는다").
  // 이미 가진 기한이 범위를 벗어나면 그 값까지 넓혀 수정이 막히지 않게 한다.
  firstDate: ..., lastDate: ...,
);
if (date == null) return;                       // 날짜 취소 → 아무것도 바뀌지 않는다
final time = await showTimePicker(
  context: context,
  // 날짜만 생각하고 들어온 사용자를 위해 23:59. 확인만 눌러도 "그 날 안에"가 된다(spec).
  initialTime: _dueAt == null
      ? const TimeOfDay(hour: 23, minute: 59)
      : TimeOfDay.fromDateTime(_dueAt!),
);
if (time == null) return;                       // 시간 취소 → 아무것도 바뀌지 않는다(취소는 취소다)
setState(() => _dueAt = DateTime(date.year, date.month, date.day, time.hour, time.minute));
await _ensureNotificationPermissionOnce();      // P1만. 8.9
```

- 범위: `firstDate = DateTime(now.year - 1)`, `lastDate = DateTime(now.year + 5, 12, 31)`, 그리고 `_dueAt`이 그 밖이면 그쪽으로 넓힌다. 과거 입력을 허용해야 하므로 `firstDate`를 `now`로 두지 않는다.
- 초·밀리초는 0이다(분 단위). 수정 시 "안 바뀌었는지" 비교가 흔들리지 않는다.

호출부(같은 파일):

```dart
// 추가
final draft = await showTodoInputDialog(context, dialogTitle: AppStrings.addTodo);
if (draft == null || draft.title.isEmpty) return;
await repo.addTodo(userId, draft.title, dueAt: draft.dueAt);     // 레포가 toUtc()한다

// 수정 — 제목이 그대로여도 기한이 바뀌면 저장한다(spec, 지금의 early return을 고치는 자리)
final draft = await showTodoInputDialog(context,
    dialogTitle: AppStrings.editTodo,
    initialTitle: todo.title,
    initialDueAt: todo.dueAt?.toLocal());
if (draft == null || draft.title.isEmpty) return;
final sameTitle = draft.title == todo.title;
final sameDue = _sameInstant(draft.dueAt, todo.dueAt);           // 둘 다 null도 '같다'
if (sameTitle && sameDue) return;                                // **둘 다** 그대로일 때만 건너뛴다
await repo.updateTodo(todo.id, title: draft.title, dueAt: draft.dueAt);
```

실패 문구는 기존 `AppStrings.saveTodoFailed` 그대로(새 오류 문구를 만들지 않는다 — spec).

### 5.2 날짜·시간 선택을 무엇으로 구현하나 — `flutter_localizations` + `ko` 한 벌 (CLAUDE.md와 충돌하지 않는다)

**사실 확인**: `main.dart`에 로케일 설정이 없다. 이 상태에서 `showDatePicker`를 띄우면 `DefaultMaterialLocalizations`(영어 전용)가 쓰여 `Select date`·`CANCEL`·`OK`·`November 2026`·`M T W T F S S`가 뜬다. spec의 "달력·시간 선택 화면의 문구도 한국어여야 한다"를 위반한다.

| 안 | 내용 | 판단 |
|---|---|---|
| **L1** | `flutter_localizations`(**Flutter SDK 패키지**) + `localizationsDelegates: [GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate]` + `supportedLocales: [Locale('ko')]` + `locale: Locale('ko')` | **채택** |
| L2 | `MaterialLocalizations`를 직접 구현해 `Localizations.override`로 끼우기 | 기각. 구현해야 하는 멤버가 수십 개이고(월 이름·요일·접근성 라벨·날짜 서식 전부) Flutter를 올릴 때마다 추상 멤버가 늘어 깨진다. "한국어 문구 몇 줄"을 위해 SDK 인터페이스를 손으로 추적하는 유지 비용이 가장 크다 |
| L3 | 달력·시간 선택을 직접 만든다 | 기각. 월 그리드·윤년·주 시작·스와이프·접근성·시간 입력(다이얼/키보드)을 새로 만들고 테스트해야 한다. 가장 큰 코드 증가이고, `CalendarDatePicker`만 떼어 써도 월 이름·요일 약어가 **여전히 `MaterialLocalizations`에서 온다**(= 영어 그대로). 즉 L3은 "부분 직접 제작"으로 줄일 수도 없다 |
| L4 | 기한을 날짜 텍스트 입력으로 받는다 | 기각. 오너 확정 1("달력에서 고르고 시간도 지정")에 어긋난다 |

**CLAUDE.md "다국어(i18n) 세팅" 금지와 충돌하지 않는다고 판단한 근거**(메인 세션의 해석에 동의하고, 그 이유를 아래로 바꿔 적는다):

1. **i18n 구조의 구성 요소가 하나도 생기지 않는다.** `.arb` 파일·`gen-l10n`·`flutter_intl`·`AppLocalizations` 생성·`l10n.yaml`·번역 키 테이블이 없다. 앱 문구는 여전히 `lib/core/strings.dart`의 **한국어 상수 하나**뿐이고, 이 기능도 그 규칙을 따른다(4.1).
2. **로케일이 둘이 되지 않는다.** `locale: Locale('ko')`를 **고정**하므로 기기 언어가 영어여도 한국어로 나온다. 분기·fallback·언어 선택 설정이 생기지 않는다 — 다국어의 반대, "한국어 하나로 못 박기"다.
3. 이 변경이 하는 일은 **Material 위젯 자신이 들고 있는 문구를 한국어로 고르는 것**이다. 금지 조항의 목적은 "번역 체계를 만들어 유지 비용과 범위를 늘리지 말 것"인데, 이 변경은 번역을 만들지 않고 **이미 SDK에 있는 번역을 지목**한다.
4. `flutter_localizations`는 **SDK에 포함된 패키지**다(`sdk: flutter`). 외부 의존성·네이티브 코드가 없으므로 이 저장소의 아픈 지점(릴리스 빌드만 깨지는 네이티브 플러그인)과 무관하다. 비용은 앱 용량 수백 KB 정도의 로케일 데이터뿐이다.

그래도 금지 조항의 **글자**와 스치므로 "결정 필요" 1번에 확인 항목으로 올렸다(채택 권고 + 대안 비교 포함).

`main.dart`에 더해지는 것(4줄):

```dart
import 'package:flutter_localizations/flutter_localizations.dart';
...
MaterialApp(
  locale: const Locale('ko'),              // 기기 언어와 무관하게 한국어 하나로 고정한다
  supportedLocales: const [Locale('ko')],
  localizationsDelegates: const [
    GlobalMaterialLocalizations.delegate,  // 달력·시간 선택·대화상자 기본 문구
    GlobalWidgetsLocalizations.delegate,   // 글 방향(LTR)
  ],
  ...
)
```

`GlobalCupertinoLocalizations`는 넣지 않는다(Cupertino 위젯을 쓰지 않는다). `pubspec.yaml`에 `flutter_localizations: {sdk: flutter}`를 더한다.

### 5.3 목록 줄 — 남은 시간은 제목 아래 둘째 줄(`subtitle`)

| 안 | 판단 |
|---|---|
| `trailing`에 둔다 | 기각. 삭제 버튼이 이미 `trailing`이고, 옆에 붙이면 **제목 칸 198dp를 깎는다**(spec "제목을 잘라서 자리를 만드는 해법은 받지 않는다") |
| 제목과 한 줄에 이어 붙인다 | 기각. 같은 이유 + 제목 길이에 따라 문구가 잘린다 |
| **`subtitle`(제목 아래 작은 줄)** | **채택.** 제목 칸 폭을 1dp도 건드리지 않는다 |

```dart
// data: (todos) 갈래의 맨 위에서 한 번만 읽는다 — 모든 줄이 같은 "지금"을 쓴다.
final now = DateTime.now();
...
final showDue = todo.dueAt != null && !todo.isDone;      // 완료한 할 일에는 표시가 없다(spec)
final dueLabel = showDue ? formatDueLabel(todo.dueAt!.toLocal(), now) : null;
final overdue = showDue && !todo.dueAt!.toLocal().isAfter(now);

ListTile(
  minTileHeight: 60,                                      // 그대로
  contentPadding: const EdgeInsetsDirectional.symmetric(horizontal: 4),   // 그대로
  horizontalTitleGap: 8, minLeadingWidth: 0,              // 그대로
  leading: ...,                                           // 그대로(24dp 체크박스)
  title: KeepWordsText(todo.title, ...),                  // 그대로
  subtitle: dueLabel == null ? null : KeepWordsText(
    dueLabel,
    style: Theme.of(context).textTheme.bodySmall!
        .merge(AppText.tabular)                           // 고정폭 숫자 — 숫자가 바뀌어도 폭이 안 흔들린다
        .copyWith(color: overdue ? AppPalette.danger : AppPalette.inkMuted),
  ),
  trailing: ...,                                          // 그대로(삭제 버튼)
)
```

- **기한이 없거나 완료한 줄은 `subtitle: null`** → `ListTile`이 한 줄 타일로 그려져 **지금과 픽셀 단위로 같다**(원칙 5). `-`·`기한 없음` 같은 자리표시를 두지 않는다.
- 줄 높이: `subtitle`이 있는 줄만 `minTileHeight 60`을 넘겨 약 62~64dp(1.5배에서 약 86dp)가 된다. **`minTileHeight`를 올리지 않는다** — 올리면 기한 없는 줄까지 같이 커져 원칙 5가 깨진다. 결과적으로 목록에 두 가지 줄 높이가 섞이는데, 카드가 각자 떠 있는(`AppPanel`) 디자인이라 높이가 다른 카드가 섞여도 어긋나 보이지 않는다. 받아들이는 비용은 spec "트레이드오프"가 이미 적어 둔 "한 화면에 보이는 할 일 수가 줄어든다"다.
- `AppPanel.raised`/`inset` 사용과 카드 간격 12는 **그대로**다(`padding: EdgeInsets.zero`로 타일을 그대로 감싼다).
- 가장 긴 문구 `12시간 34분 지남`(11자)은 13dp에서 약 130dp로 198dp 칸에 한 줄로 들어간다. 1.5배(19.5dp)에서 약 193dp로 아슬하게 들어가고, 넘치면 `KeepWordsText`가 어절 단위로 두 줄이 된다(글자가 잘리지 않는다).
- 완료 토글 직후: `invalidate(todosProvider)` → 그 줄의 `subtitle`이 사라진다. 자리는 바뀌지 않는다(2.2의 규칙 4).

---

## 데이터 흐름

## 6. 데이터 흐름

```
[기한 있는 할 일 추가]
  FAB → showTodoInputDialog → (날짜·시간 선택, P1: 권한 1회 요청)
    → TodoRepository.addTodo(userId, title, dueAt)        // insert, due_at = UTC ISO8601
    → ref.invalidate(todosProvider)
    → todosProvider: fetchTodos → sortedForList(...)       // 순서는 여기서 결정된다
    → ① TodoListScreen 다시 그림(줄이 기한 순 자리로 들어가고 subtitle이 붙는다)
       ② MainShell의 ref.listen(todosProvider) →
            - TodoWidgetService.publish(fromTodos(...))    // 위젯도 같은 순서
            - DueAlarmService.sync(todos, now)             // P1: 예약 보정
```

| 사용자 동작 | 쓰기 | 다시 읽기 | 알림(P1) |
|---|---|---|---|
| 기한 넣어 추가 | `insert{title, due_at}` | `invalidate(todosProvider)` | 보정이 2건 예약(1시간 전·기한) |
| 기한만 수정 | `update{title, due_at}` | 같음 | 보정이 옛 2건 취소 + 새 2건 예약 |
| 기한 지우기 | `update{title, due_at: null}` | 같음 | 보정이 2건 취소 |
| 제목만 수정 | `update{title, due_at(그대로)}` | 같음 | 본문이 바뀌므로 보정이 재예약 |
| 완료/해제 | `update{is_done}` | 같음 | 완료 → 취소 / 해제 → 미래면 재예약 |
| 삭제 | `delete` | 같음 | 보정이 2건 취소 |
| 당겨서 새로고침·탭 복귀 | 없음 | 같음 | 보정(= 기기 성질 교정) |
| 로그아웃·탈퇴 | — | — | `cancelAll()` |

**핵심 단순화**: spec이 열거한 "예약을 취소·갱신해야 하는 경우" 6가지가 모두 `invalidate(todosProvider)`를 지나간다. 그래서 **취소 호출을 6곳에 흩지 않고 보정 한 곳**만 둔다(8.5·8.6). 목록을 거치지 않는 경로는 두 개뿐이고 따로 다룬다 — 로그아웃·탈퇴(8.7), 앱이 죽은 상태의 위젯 체크(8.8).

---

## API 계약

## 7. API 계약

### 7.1 스키마 변경: 1.1의 컬럼 하나. 새 RPC·Edge Function·cron 없음

### 7.2 쓰는 호출 (전부 기존 테이블 접근, RLS 그대로)

| 자리 | 호출 | 변경 |
|---|---|---|
| 목록 | `todos.select().eq('user_id', uid).order('created_at')` | **그대로**(반환값만 Dart에서 정렬) |
| 추가 | `todos.insert({user_id, title, due_at})` | `due_at` 키 추가 |
| 수정 | `todos.update({title, due_at}).eq('id', id)` | `updateTitle` → `updateTodo` |
| 완료 | `todos.update({is_done}).eq('id', id)` | 그대로 |
| 삭제 | `todos.delete().eq('id', id)` | 그대로 |

세 쓰기 모두 기존 RLS(`auth.uid() = user_id`)로 통한다. `due_at`을 읽거나 쓰는 서버 코드는 없다.

---

## 8. P1 — 기한 알림

### 8.1 패키지: `flutter_local_notifications` + `timezone` 둘. 그 밖은 추가하지 않는다

먼저 **지금 의존성으로 되는지** 따졌다(CLAUDE.md).

| 필요한 일 | 기존 의존성으로 되는가 |
|---|---|
| 미래 시각에 기기가 스스로 알림을 띄우게 예약 | **안 된다.** `firebase_messaging`은 서버가 보내는 메시지를 받는 것이고 로컬 예약 API가 없다. `shared_preferences`·`home_widget`에도 `AlarmManager` 경로가 없다. 직접 만들면 Kotlin으로 `AlarmManager` + `BroadcastReceiver` + `NotificationManager` + 부팅 복구 + Dart 채널까지 써야 한다(이 앱 도메인과 무관한 배관) |
| 알림 채널 분리 | 패키지의 `createNotificationChannel` |
| 지금 예약된 것 조회 | 패키지의 `pendingNotificationRequests()` — **보정 설계가 이 API 하나에 걸려 있다**(8.5) |
| 부팅 후 예약 복구 | 패키지가 자기 매니페스트에 부팅 리시버를 넣어 준다(8.2) |
| 알림 권한 요청 | **된다 — 이미 있다.** `PushMessaging.requestPermission()`(`firebase_messaging`). **`permission_handler`를 넣지 않는다** |
| 예약 시각 타입 | `zonedSchedule`이 `TZDateTime`을 요구한다 → `timezone`(순수 Dart) |

- `pubspec.yaml`: `flutter_local_notifications: ^19.0.0`, `timezone: ^0.10.0`(둘 다 `flutter pub add`로 받은 **실제 해석 판을 적는다** — 19/0.10보다 높으면 그쪽을 쓰고, API 이름이 바뀌었으면 아래 호출 목록을 그 판 이름으로 옮긴다. 판 번호와 함께 `pubspec.lock`을 커밋한다).
- **`flutter_timezone`(기기 시간대 조회)은 넣지 않는다.** 예약은 **절대 시각**이고 알림 본문에 시각을 적지 않으므로(제목은 고정 문구, 본문은 할 일 제목) 기기의 IANA 시간대 이름을 알 필요가 없다. `tz.TZDateTime.from(dueAtUtc, tz.UTC)`로 넘기면 같은 순간에 울린다. 이 한 줄이 네이티브 패키지 하나를 없앴다.
  - 구현 시 확인 한 줄: `tz.UTC`가 `initializeTimeZones()` 없이 쓰이는지 유닛 테스트로 확인하고, 필요하면 호스트 초기화에 `initializeTimeZones()`를 더한다(순수 Dart라 네이티브 위험이 없다).
- 커밋 메시지에 적을 이유: "기한 알림(기기 로컬)을 위해 추가. 미래 시각 예약·채널 분리·예약 목록 조회·부팅 복구를 대신한다. 기존 firebase_messaging은 서버 발신 메시지 수신용이라 로컬 예약 경로가 없고, 직접 만들면 AlarmManager·BroadcastReceiver·부팅 리시버·채널을 Kotlin으로 써야 한다. timezone은 zonedSchedule의 인자 타입 때문에만 쓴다(기기 시간대 조회 패키지는 넣지 않았다)."

### 8.2 안드로이드 매니페스트·권한·예약 모드

| 항목 | 결정 |
|---|---|
| `POST_NOTIFICATIONS` | **이미 선언돼 있다**(manifest:4). 추가 변경 없음 |
| `SCHEDULE_EXACT_ALARM` / `USE_EXACT_ALARM` | **쓰지 않는다** |
| 예약 모드 | `AndroidScheduleMode.inexactAllowWhileIdle` |
| `RECEIVE_BOOT_COMPLETED` + 부팅 리시버 | **우리 매니페스트에 적지 않는다.** 패키지가 자기 매니페스트에 권한과 `ScheduledNotificationBootReceiver`를 선언하고 매니페스트 병합으로 들어온다. 병합 결과(`android/app/build/.../merged_manifests/.../AndroidManifest.xml`)에 둘이 있는지 **눈으로 확인한다** |
| `app/build.gradle.kts` | `compileOptions`에 `isCoreLibraryDesugaringEnabled = true`, `dependencies { coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4") }`. 이 패키지가 요구하는 유일한 Gradle 변경이다(AGP 9에서 설정 이름이 다르면 그 자리에서 맞춘다) |
| `minSdk` | `flutter.minSdkVersion`이 패키지 요구치 이상인지 확인. 미달이면 올리지 말고 멈추고 보고한다 |

**정확 알람을 피하는 이유**: ① Play 정책상 `USE_EXACT_ALARM`은 알람시계·캘린더 성격의 앱에만 허용되고, 심사에서 정당화를 요구받는다 — 개인 투두 기한 알림은 그 묶음이 아니다. ② `SCHEDULE_EXACT_ALARM`은 Android 14+에서 기본 거부라 사용자를 OS 설정로 보내는 안내가 하나 더 생긴다. ③ **기한 알림은 몇 분 늦어도 뜻이 상하지 않는다**(spec은 이 알림을 "목록을 열지 않는 날의 신호"로 정의했고 승부·점수가 걸려 있지 않다). 대가: 절전(Doze) 상태에서 수 분~수십 분 늦을 수 있다 → "결정 필요" 2번에 수용 확인으로 올렸다.

**릴리스 빌드 위험 (이 저장소의 아픈 지점)**: `home_widget`은 디버그는 통과하고 **릴리스만** 깨뜨렸고, 증상이 `FlutterFirebaseCorePlugin not found`처럼 **엉뚱한 플러그인 이름**으로 나왔다(원인: 플러그인이 buildscript classpath에 Kotlin 1.9.0을 박아 둠, 해결: `android.builtInKotlin=true`). 그래서:
- `android/gradle.properties`의 `android.builtInKotlin=true`를 **그대로 둔다**(절대 false로 되돌리지 않는다).
- 패키지 추가 + Gradle 한 줄 + 채널 생성까지를 **별도의 첫 커밋**으로 끊고, 그 자리에서 `flutter build apk --release --dart-define-from-file=env.json`을 돌린다(11장 7단계). 기능 코드를 올리기 전에 빌드 가능성을 확인하는 것이 쪼개는 목적이다.
- 로그를 `tail`로 파이프하면 종료 코드가 가려지므로 `EXIT=$?`를 따로 찍는다(CLAUDE.md).
- 릴리스 실패 시 의심 순서: ① 새 플러그인의 Kotlin/AGP classpath, ② desugaring 설정 이름, ③ 경로의 비-ASCII. 끝내 안 되면 **멈추고 보고한다**(spec 결정 기록 3차의 (b) 분리 릴리스가 그때의 길이다).

### 8.3 채널·초기화

```dart
const dueAlarmChannelId = 'todo_due';   // FCM 기본 폴백 채널과 다른 id → OS에서 따로 끌 수 있다
AndroidNotificationChannel(
  dueAlarmChannelId,
  AppStrings.todoDueAlarmChannel,        // '기한 알림'
  importance: Importance.defaultImportance,   // 소리 있음, 화면을 가로채는 헤드업은 쓰지 않는다
)
```

- 대결 알림(FCM)은 매니페스트에 기본 채널을 지정하지 않아 `fcm_fallback_notification_channel`로 간다 → **채널이 확실히 분리된다**(spec의 조건). OS 알림 설정에서 `기한 알림`만 끌 수 있다.
- 앱 안 알림 끄기 설정을 만들지 않는다(spec).
- 잠금화면 가리기 설정을 만들지 않는다 → `visibility`를 지정하지 않고 OS 기본에 맡긴다(spec: 제목 노출 허용).
- 초기화 자리: **`MainShell.initState`**(이미 `primeFromCache`를 부르는 자리). `main.dart`를 건드리지 않는 이유는 home-widget 설계와 같다(다른 세션과의 충돌 회피, 그리고 알림이 뜻을 갖는 것은 로그인 뒤다). 어떤 경로로 들어오든 늦게 초기화되는 일이 없게 `DueAlarmService`의 모든 메서드가 `_ensureInitialized()`를 먼저 지난다.

### 8.4 예약 id와 payload — uuid를 32비트에 담고, 충돌을 어떻게 다루나

```dart
enum DueAlarmKind { hourBefore, atDue }            // index 0, 1

/// uuid → 31비트 양수 id. 아래 한 비트가 시점(1시간 전/기한 시각)이다.
/// `String.hashCode`를 쓰지 않는다 — Dart 판이 바뀌어도 같은 값이어야 하므로 FNV-1a를 직접 돈다.
int dueAlarmIdOf(String todoId, DueAlarmKind kind) =>
    ((_fnv1a(todoId) & 0x3FFFFFFF) << 1) | kind.index;    // 0 .. 2^31-1

/// 알림에 함께 싣는 뜻. **id가 아니라 이것이 진실이다**(아래 충돌 처리).
/// '<todoId>|<kindIndex>|<기한 epochMs>'
String encodeDueAlarmPayload({required String todoId, required DueAlarmKind kind, required DateTime dueAt});
String? todoIdOfPayload(String? payload);
```

- **두 번 예약의 구별**: 같은 todo의 두 알림은 id의 최하위 비트와 payload의 `kindIndex`로 갈린다. 알림 제목도 서로 다르다(spec).
- **해시 충돌을 다루는 방법 — 세 겹**:
  1. **취소는 id가 아니라 payload로 한다.** 특정 할 일의 예약을 지울 때 `pendingNotificationRequests()`를 훑어 **payload의 todoId가 일치하는 것만** 취소한다. 그래서 충돌이 나도 **남의 알림을 지우는 일이 구조적으로 불가능하다**(이 조항이 이 설계에서 id 규칙보다 중요하다).
  2. **계획 단계에서 슬롯이 겹치면 비켜 앉는다.** `planDueAlarms`가 임박한 순으로 id를 배정하다 이미 쓰인 id를 만나면 +1씩 밀어 빈 슬롯을 찾는다. 밀린 id는 "자리 번호"일 뿐이고 뜻은 payload가 들고 있다.
  3. **보정이 모르는 id를 정리한다.** 예약된 것 중 "지금 원하는 집합"에 없는 id는 전부 취소된다(8.5). 밀린 자리나 옛 예약이 떠돌지 않는다.
- 충돌 확률: 30비트 공간에 동시 예약 50건이면 약 1.2e-6. 위 세 겹이 없어도 거의 안 일어나지만, 일어났을 때의 증상("남의 알림이 사라진다")이 사용자가 원인을 알 수 없는 종류라서 막아 둔다.

### 8.5 예약 계획과 보정 — 순수 함수 둘

`lib/features/todo/domain/due_alarm_plan.dart` (신규, Flutter 의존 없음)

```dart
const dueAlarmLeadTime = Duration(hours: 1);
const maxDueAlarms = 100;                 // 8.10

class DueAlarm {                          // 예약 하나
  final int id;                            // 8.4
  final String todoId;
  final DueAlarmKind kind;
  final DateTime at;                       // 울릴 절대 시각(UTC)
  final String body;                       // 할 일 제목 — **자르지 않는다**(spec)
  String get title => kind == DueAlarmKind.hourBefore
      ? AppStrings.todoDueAlarmBeforeTitle : AppStrings.todoDueAlarmAtTitle;
  String get payload => ...;
}

class PendingDueAlarm {                    // 지금 OS에 걸려 있는 것(플러그인 타입을 테스트에 들이지 않기 위한 우리 레코드)
  final int id;
  final String? payload;
}

/// 지금 있어야 하는 예약의 전체 집합. 이 함수가 spec의 알림 규칙 전부를 들고 있다.
///
/// - 완료한 할 일·기한 없는 할 일은 제외(완료하면 알림이 안 간다)
/// - 기한이 이미 지났으면 **하나도** 만들지 않는다(저장하는 순간 울리지 않는다)
/// - 기한 − 1시간이 이미 지났으면 그 한 건만 건너뛴다(기한 시각 알림만 남는다)
/// - 울릴 시각이 이른 것부터 [limit]개까지만 남긴다(임박한 것 우선)
/// - id 배정과 충돌 비켜 앉기(8.4)
List<DueAlarm> planDueAlarms(List<Todo> todos, {required DateTime now, int limit = maxDueAlarms});

/// 원하는 집합과 실제 걸려 있는 것을 맞춘다. **이 함수가 "추가·수정·삭제"를 한 번에 낸다.**
///
/// - 취소: 걸려 있는데 원하는 집합에 **id가 없거나 payload가 다른** 것 전부
///         (기한이 바뀌면 payload의 epochMs가 달라져 자동으로 "다른 것"이 된다)
/// - 예약: 원하는데 같은 id·같은 payload로 걸려 있지 않은 것 전부
/// - 둘 다 비면 플랫폼 호출이 한 번도 일어나지 않는다(가장 흔한 경우)
({List<int> cancel, List<DueAlarm> schedule}) reconcileDueAlarms({
  required List<DueAlarm> desired,
  required List<PendingDueAlarm> pending,
});
```

이 두 함수로 spec의 알림 조항들이 **한 경로**에 모인다: 기한 변경·삭제·완료·완료 해제·다른 기기에서의 수정·기기 교체·재설치가 전부 "원하는 집합이 달라졌다"로 같게 표현된다. `pending`에 들어오는 값은 전부 우리가 예약한 것이다(대결 알림은 FCM이 직접 그려서 이 플러그인을 거치지 않는다) → **모르는 id를 취소해도 안전하다.**

### 8.6 보정이 일어나는 지점 — `MainShell`의 `todosProvider` 리스너

자리: `lib/core/navigation/main_shell.dart`의 기존 `ref.listen(todosProvider, ...)` **안**, 위젯 발행 바로 뒤.

```dart
ref.listen(todosProvider, (previous, next) {
  if (next.isLoading) return;                     // 기존 그대로
  ... 위젯 발행(기존 그대로) ...
  final todos = next.value;
  if (todos == null) return;
  unawaited(service.publish(TodoWidgetPayload.fromTodos(todos, now: now)));   // ① 먼저
  unawaited(ref.read(dueAlarmServiceProvider).sync(todos, now: now));         // ② 그 뒤
});
```

- **왜 이 자리인가**: ① 목록이 바뀌는 모든 경로(추가·수정·완료·삭제·새로고침·탭 복귀)가 여기를 지난다 = spec의 "목록을 받아올 때 미래 기한 예약을 다시 맞춘다"와 "취소해야 하는 6가지"가 한 자리에서 해결된다. ② 할 일 화면에 두면 탭을 떠난 뒤의 변경을 놓친다(위젯 발행을 이 자리에 둔 것과 같은 이유). ③ 세션이 있을 때만 떠 있는 화면이라 "남의 알림" 문제가 없다.
- **순서**: 위젯 발행이 먼저다. 사용자 눈에 보이는 캐시가 알림 예약을 기다리지 않게 한다. 둘 다 `unawaited`이고 서로를 막지 않는다.
- 조회 실패(error)·로딩에서는 **예약을 건드리지 않는다**. 네트워크가 없을 때 예약을 지우면 "서버가 안 될 때 알림이 사라진다"가 된다.
- **화면이 느려지지 않는 이유**: `sync`는 리스너 안에서 `await`되지 않고(프레임을 잡지 않는다), 목록은 이미 provider 값으로 그려진 뒤다. 안에서 하는 일은 `pendingNotificationRequests()` **한 번**(안드로이드에서 prefs JSON 읽기)과 달라진 것만큼의 schedule/cancel이다. 보통 패스는 **쓰기 0건**이다. 더해서 `DueAlarmService`가 직전에 맞춘 "원하는 집합의 서명"을 기억해 같으면 플랫폼 호출도 건너뛴다(`TodoWidgetService._lastJson`과 같은 수법).
- **관문이 아니다**: `sync` 전체가 `try/catch`로 감싸여 `debugPrint`만 남긴다. 실패해도 목록·저장·완료는 아무 영향이 없다.

### 8.7 취소 경로 한눈에

| spec이 요구하는 경우 | 이 설계에서 지켜지는 방법 |
|---|---|
| 기한을 바꾸면 옛 예약이 안 울린다 | 보정(payload의 epochMs가 달라져 취소 후 재예약) |
| 기한을 지우면 | 보정(원하는 집합에서 빠진다) |
| 할 일을 삭제하면 | 보정 |
| **할 일을 완료하면** | 보정(`isDone`은 계획에서 제외된다) |
| 완료를 해제하면, 기한이 미래면 재예약 / 과거면 예약 없음 | 보정(`planDueAlarms`의 "지난 기한은 하나도 만들지 않는다") |
| **로그아웃·탈퇴하면 그 기기 예약 전부 취소** | `AuthRepository.signOut()`·`deleteAccount()`에서 `DueAlarmService.cancelAll()`. `_push.forgetCurrentToken()` 옆에 한 줄 더하고, 같은 태도로 실패를 삼켜 로그아웃을 막지 않는다. 걸려 있는 알림이 전부 이 기능의 것이라 `cancelAll()`로 충분하다 |
| 기기 교체·재설치·다른 기기에서의 수정 | 보정(앱을 한 번 열면 맞는다. 받아들이는 한계 = spec 그대로) |
| 위젯에서 체크 | 8.8 |

받아들이는 틈 하나(spec에 없고 설계가 드러낸 것): **토큰 만료 등으로 세션이 조용히 끊긴 경우**에는 `signOut()`을 지나지 않아 예약이 남는다. 다음 로그인·앱 실행의 보정이 정리하지만, 그 전에 울릴 수 있다. 명시적 로그아웃·탈퇴만 다루는 것이 spec의 요구이고, 이 틈을 메우려고 세션 감시 경로를 새로 만들지 않는다.

### 8.8 위젯에서 체크한 경우 — 지금은 경로 자체가 없고, 올 때의 계약을 못 박는다

**사실**: 홈 위젯의 체크(쓰기) 경로는 **아직 구현되지 않았다**(home-widget 1~3단계만 구현, 체크는 6단계). `todoWidgetActionOf`를 부르는 코드도, 백그라운드 콜백 등록도 저장소에 없다. 그래서 지금 시점에 "위젯에서 체크한 할 일의 알림이 온다"는 일이 **일어날 수 없고**, spec의 그 수용 기준은 자동으로 충족된다. **이 기능에서 위젯 체크 경로를 만들지 않는다**(home-widget의 범위다).

6단계가 올 때 지켜야 할 계약(home-widget design 4.2의 W5 분기를 그대로 따른다):

| 분기 | 알림 취소가 되는가 |
|---|---|
| **앱 프로세스가 살아 있다**(포트 핸드오프 → main isolate가 `setDone` + `invalidate(todosProvider)`) | **된다.** 보정이 main isolate에서 돌아 그 할 일의 예약 2건이 취소된다. 추가 코드가 필요 없다 |
| **앱 프로세스가 죽어 있다**(백그라운드 isolate가 직접 쓴다) | **보장할 수 없다.** 백그라운드 FlutterEngine에서 플러그인이 등록되는지가 `home_widget` 쪽 배관에 달려 있고(이 저장소에는 "백그라운드 Dart에서 플러그인을 쓴다"는 선례가 없다), 등록되지 않으면 `MethodChannel` 호출이 그대로 실패한다 |

죽은 상태 분기의 설계:
1. 백그라운드 콜백에서 **취소를 시도한다**(`cancelFor(todoId)` — payload로 찾아 취소, 8.4). 성공하면 즉시 해결된다.
2. 실패하면 **`debugPrint`만 남기고 넘어간다.** 위젯 체크 자체(서버 쓰기·캐시 발행)를 이 실패로 막지 않는다(원칙 4).
3. 그 경우 **다음에 앱을 열 때의 보정이 치운다.** 그 사이에 기한이 오면 **이미 끝낸 할 일의 알림이 한 번 울린다** — 받아들이는 지연이고, 사용자에게 설명하지 않는다(설명해도 할 수 있는 일이 없다. spec이 기기 성질에 같은 태도를 취했다).
4. 6단계 구현 때 실기기에서 "앱 종료 상태로 위젯 체크 → 기한 알림이 안 온다"를 검증 항목에 넣는다(home-widget design 4.4 표에 한 줄 더하는 일이고, 그 단계의 몫이다).

이 한계는 spec 수용 기준의 글자("홈 위젯에서 체크한 할 일의 알림도 오지 않는다")와 스칠 수 있어 "결정 필요" 4번에 올렸다.

### 8.9 권한 요청 흐름

| 항목 | 결정 |
|---|---|
| 묻는 시점 | **날짜·시간 선택이 끝나 `_dueAt`이 처음 정해진 직후**(대화상자로 돌아온 그 자리, 저장 전). 앱 첫 실행·투두 화면 진입·저장 성공 뒤가 아니다 |
| "처음"의 기록 | **앱이 따로 기록하지 않는다.** `permissionStatus() == notDetermined`가 그 기록이다(`PushService.ensureNotificationPermissionAfterFirstBattle`의 선례 그대로) → 반복해 묻지 않는다 |
| 수단 | `PushMessaging.requestPermission()`(이미 있는 `firebase_messaging`). 플러그인의 `requestNotificationsPermission()`을 쓰지 않는다 — 같은 OS 권한 하나를 두 패키지가 각자 묻게 하면 상태를 읽는 자리가 둘이 된다 |
| 거부 상태 표시 | 기한이 정해져 있고 권한이 `denied`일 때 **대화상자 안 한 줄**: `알림이 꺼져 있어 기한 알림을 보낼 수 없어요.`(bodySmall·`inkMuted`). 기한을 정하는 길은 막지 않는다 |
| 요청 뒤 | `ref.invalidate(notificationPermissionProvider)` — 프로필의 "알림이 꺼져 있어요" 칸과 이 줄이 같은 값을 본다 |
| `알림 설정 열기` | **두지 않는다.** 선례가 이미 같은 결정을 명시적으로 했다(`notification_section.dart`: "기기 설정으로 바로 보내는 버튼도 두지 않는다 — 새 패키지가 필요해지고 안내 문구만으로 목적이 달성된다"). OS 알림 설정 화면을 열려면 `app_settings`류 패키지나 새 MethodChannel + Kotlin이 필요하고, 프로필 안내 문구(`기기 설정 > 앱 > 투두두두 > 알림에서 켤 수 있어요.`)가 이미 길을 알려 준다. 같은 앱에서 한 자리는 버튼이 있고 한 자리는 없는 것이 더 나쁘다 |
| 권한이 없어도 | 입력·표시·정렬·저장 전부 그대로 동작한다. 예약만 OS가 조용히 버린다(그래서 예약 호출을 권한으로 가르지 않는다 — 가르면 권한을 나중에 켠 사용자의 예약이 비어 있게 된다. 보정이 다음 실행에 다시 건다) |

### 8.10 예약 상한

- `maxDueAlarms = 100`(= 임박한 할 일 최대 50개 × 2건). 안드로이드는 앱당 예약 수에 한계가 있고(판에 따라 수백 건), 플러그인이 부팅 복구를 위해 예약 전부를 한 파일에 적어 두므로 수가 커지면 그 읽기·쓰기도 커진다. 100은 개인 투두 규모에서 사실상 닿지 않고, 닿아도 안전한 수다.
- **임박한 것이 먼저 예약된다**: `planDueAlarms`가 울릴 시각 오름차순으로 정렬한 뒤 앞에서 잘라낸다(그래서 잘리는 것은 늘 가장 먼 기한이다).
- 상한에 걸린 사실을 **사용자에게 보이지 않는다**(토스트·배지·안내 없음). `debugPrint`만 남긴다(spec: "오류로 보이지 않아야 한다").
- 잘렸던 먼 기한은 가까워지면 다음 보정에서 자동으로 들어온다 — 따로 재시도 장치가 필요 없다.

### 8.11 탭 처리

- 알림을 탭하면 **앱의 할 일 화면**이 열린다. 특정 할 일로 스크롤·강조하지 않는다(위젯 탭 선례).
- 수단: `initialize(onDidReceiveNotificationResponse: ...)`(앱이 떠 있거나 백그라운드) + `getNotificationAppLaunchDetails()`(종료 상태에서 시작). 둘 다 `MainShell`에서 받아 `selectedTabProvider.select(AppTab.todo)` **한 줄**만 한다.
- payload를 해석하지 않는다(어느 할 일인지로 분기하지 않으므로 필요가 없다). 뜻을 모르는 알림이어도 아무 일도 하지 않는다.
- 미로그인 상태에서 탭하면 `AuthGate`가 로그인 화면을 띄운다. 기록해 둔 탭 값은 로그인 뒤에 쓰인다 — **오류 화면이 보이지 않는다**(spec, push·위젯과 같은 태도).
- 백그라운드 탭 핸들러(`onDidReceiveBackgroundNotificationResponse`)를 **등록하지 않는다**. 동작 버튼이 없으므로 탭은 늘 앱을 띄우고, 띄워진 앱이 위 두 경로로 집어 간다.

### 8.12 새로 생기는 파일과 provider

| 파일 | 내용 |
|---|---|
| `lib/features/todo/domain/due_alarm_plan.dart` | 순수 함수·값 객체(8.4·8.5). Flutter 의존 없음 |
| `lib/features/todo/data/due_alarm_host.dart` | 플러그인 접점(얇은 래퍼). `initialize`·`pending()`·`schedule(DueAlarm)`·`cancel(int)`·`cancelFor(String todoId)`·`cancelAll()`·`launchedByNotification()`. **예외를 삼키지 않는다**(호출자가 로그를 남긴다) — `TodoWidgetHost`·`PushMessaging`과 같은 모양 |
| `lib/features/todo/domain/due_alarm_service.dart` | `sync(List<Todo>, {now})`·`cancelAll()`·`ensurePermissionWhenSettingDue()`. 모든 실패를 `debugPrint`로 끝낸다. 직전 서명 기억 |
| `lib/features/todo/domain/todo_providers.dart`(기존) | `dueAlarmHostProvider`(테스트에서 가짜로 바꾸는 지점), `dueAlarmServiceProvider`(앱 수명 동안 하나) 추가 |
| `lib/features/auth/domain/auth_providers.dart`(기존) | `AuthRepository`에 `dueAlarmServiceProvider`를 함께 넘긴다(8.7) |

---

## 9. 홈 위젯과 문서 정합 (spec이 이 기능의 범위에 넣은 일)

위젯이 보여 줄 **내용·문구·상태 처리·캐시 스키마는 하나도 바뀌지 않는다.** 순서만 앱과 함께 바뀐다(2.2). 남은 시간은 위젯에 넣지 않는다(spec의 근거 그대로).

고칠 자리(거짓이 되는 문장들):

| 자리 | 조치 |
|---|---|
| `lib/features/todo/data/todo_widget_payload.dart:88`(`items` 주석), `:124`의 설명 | "앱과 같은 순서(`created_at` 오름차순)" → "앱과 같은 순서(`sortedForList` — 기한 이른 순, 기한 없는 것은 그 뒤 생성순)" |
| `test/features/todo/todo_widget_payload_test.dart:12` | 테스트 이름·본문의 "앱과 같은 순서" 뜻을 새 규칙으로 고친다. `_todo` 헬퍼에 `dueAt` 선택 인자를 더하고, **기한 섞인 입력이 들어온 순서대로 캐시에 실리는지**를 고정한다(정렬은 레포지토리가 하고 `fromTodos`는 보존한다는 경계를 테스트가 말해야 한다) |
| `docs/specs/home-widget/spec.md:112`, `:216` / `design.md:124`, `:458` | 승인된 과거 문서의 문장을 지우지 않고 **각주 한 줄**을 덧붙인다: "(2026-11-09 `todo-due-date`로 앱 목록 순서가 기한 우선으로 바뀌었다. 위젯은 여전히 '앱과 같은 순서'를 쓴다 — `docs/specs/todo-due-date/design.md` 2장)" |
| `TODO_BACKLOG.md:14` | 해소된 "남은 시간이 내림으로 표시된다" 줄을 **지운다**(이미 취소선 + 사유가 적혀 있다). 18번 줄(위젯 임박 표시)은 남긴다 |
| `CLAUDE.md` 코딩 규칙의 "에러를 삼키지 않는다" 예외 목록 | 기한 알림 예약·취소 실패를 한 줄 더한다(위젯 발행 실패와 같은 성격) |

---

## 10. 테스트 계획

유닛 테스트가 닿도록 **설계가 떼어 낸 순수 함수**: `formatRemaining`, `formatDueLabel`, `compareForList`/`sortedForList`, `dueAlarmIdOf`, `encode/decodeDueAlarmPayload`, `planDueAlarms`, `reconcileDueAlarms`. 선례는 `todo_widget_payload.dart`(위젯이 그릴 내용을 전부 순수 함수로 내려 유일한 자동 검증 지점을 만든 것).

| 파일 | 고정하는 것 |
|---|---|
| `test/core/remaining_time_test.dart` (이동+확장) | 두 단위 병기, 아래 단위 0 생략, 초는 1분 미만만, 경계(정확히 1일/1시간/1분), `Duration.zero` |
| `test/features/todo/due_date_rules_test.dart` (신규) | **8구간 전부 + 경계값**(3.2 표를 그대로 테스트 칸으로 옮긴다): 기한 == 지금 → `방금 지남`, −30초 → `방금 지남`, 1시간 42분 → `1시간 42분 남음`, `3일 0시간`→`3일 남음`, 세 단위가 나오지 않음, 43분 12초에 초가 안 붙음 / **정렬**: 기한 있음·없음 섞임, 같은 기한은 생성순, 생성 시각까지 같으면 id, 넘긴 기한이 맨 위, 완료가 자리를 바꾸지 않음, 같은 입력을 여러 번 정렬해도 같은 결과(불안정 정렬 회귀 방지) |
| `test/features/todo/due_alarm_plan_test.dart` (신규) | 미래 기한 → 2건, 1시간 이내 기한 → 기한 시각 1건, 지난 기한 → 0건, 완료 → 0건, 기한 없음 → 0건, 임박한 것부터 상한만큼, id의 시점 비트, payload 왕복, 보정(추가만/취소만/기한 변경 → 취소+재예약/변화 없음 → 빈 결과/모르는 id는 취소/같은 id 다른 payload는 취소) |
| `test/features/todo/due_alarm_service_test.dart` (신규) | 가짜 호스트로: 실패해도 예외가 밖으로 안 나감, 서명이 같으면 플랫폼 호출을 안 함, `cancelAll`, 권한이 `notDetermined`일 때만 요청(`denied`에 다시 안 묻는다) |
| `test/features/todo/todo_widget_payload_test.dart` (갱신) | 9장 |
| `test/features/battle/domain/battle_summary_test.dart` (갱신) | 3.4 — 90분 기대값 한 줄 |
| `test/core/remaining_time_test.dart`·`my_battles_sections_test.dart` | 3.4 |
| 위젯 테스트(선택, MVP 강제 아님) | 기한 없는 할 일 줄에 **둘째 줄이 없다**(원칙 5의 회귀 방지), 완료한 할 일에 경고색 문구가 없다, 제목만 적고 엔터 → 기한 없는 할 일이 추가된다 |

알림 호스트(플러그인) 자체와 `showDatePicker`의 한국어 문구는 **실기기·에뮬레이터 육안 확인**이다(12장). `flutter analyze` 이슈 0, `flutter test` 전부 통과를 각 단계의 끝 조건으로 둔다.

---

## 11. 단계 분할 (커밋 단위 제안 — 확정은 plan.md)

P0을 먼저 끝내 검증하고 그 위에 P1을 올린다(spec 결정 기록 3차 1번). 릴리스는 함께 나간다.

| # | 단계 | 범위 | 끝 조건 |
|---|---|---|---|
| 1 | 남은 시간 두 단위 병기 | `lib/core/remaining_time.dart`(이동+규칙), 대결 호출부 2곳 import, 테스트 이동·갱신, `TODO_BACKLOG.md` 한 줄 삭제 | `flutter test` 통과. 대결 화면 문구는 숫자만 달라진다 |
| 2 | 기한 컬럼 | 마이그레이션 1개(적용은 오너 승인 뒤) | 원격 적용 전까지는 코드 변경 없음 |
| 3 | 모델·레포지토리·정렬 | `todo.dart`, `todo_repository.dart`(`updateTodo`), `due_date_rules.dart`, 위젯 주석·테스트·문서 정합(9장) | 목록 순서가 바뀌고 위젯이 따라온다. 화면에 새 문구는 아직 없다 |
| 4 | 로케일 한 벌 | `pubspec.yaml`(`flutter_localizations`), `main.dart` 4줄 | 달력·시간 선택이 한국어로 뜬다(육안) |
| 5 | 대화상자의 기한 자리 | `todo_list_screen.dart`(`TodoDraft`, `_TodoInputDialog`, 추가·수정 호출부), `AppStrings` 입력 문구 | 넣기·바꾸기·지우기, 제목 그대로 기한만 저장, 엔터 경로 보존 |
| 6 | 목록 줄 표시 | `todo_list_screen.dart` subtitle, `AppStrings` 목록 문구 | 8구간이 화면에 보이고 완료한 줄에는 없다. **여기까지가 P0 = 알림 없이 완결** |
| 7 | 알림 패키지·채널만 | `pubspec.yaml`+`lock`, `app/build.gradle.kts`(desugaring), `due_alarm_host.dart` 초기화·채널, `MainShell` 초기화 한 줄 | **`flutter build apk --release --dart-define-from-file=env.json` 통과**(이 단계의 존재 이유). 병합 매니페스트에 부팅 리시버 확인 |
| 8 | 예약 계획 순수 함수 | `due_alarm_plan.dart` + 테스트 | 호출자 없이 테스트만(선례: push 2단계) |
| 9 | 예약 배선·보정·권한 | `due_alarm_service.dart`, providers, `MainShell` 리스너 한 줄, `AuthRepository` 취소, 대화상자의 권한 요청·꺼짐 안내 | spec의 알림 수용 기준(권한·취소·보정) |
| 10 | 탭 처리 | `MainShell`의 launch/response → 할 일 탭 | 알림 탭으로 할 일 화면, 미로그인에서 오류 없음 |
| 11 | 문서 | `CLAUDE.md` 예외 한 줄, 개인정보처리방침·Play 데이터 보안 확인 기록 | spec "문서" 항목 |

---

## 12. 오너가 손수 해야 할 일

1. **마이그레이션 원격 적용 승인**(2단계). 로컬 Docker가 없어 원격 프로젝트에 적용해야 하고, 이 저장소는 단계마다 오너 승인을 받는 규칙이다.
2. **실기기/에뮬레이터 육안 확인**: 달력·시간 선택의 한국어 문구(4단계), 기한 알림이 실제로 오는지·채널이 OS 설정에서 따로 보이는지·잠금화면 표시(9단계), 권한 다이얼로그가 기한을 처음 정할 때 한 번만 뜨는지.
3. **릴리스 빌드 확인**(7단계). 깨지면 8.2의 의심 순서를 따르고, 끝내 안 되면 릴리스 분리(spec 3차 (b))를 판단한다.
4. **서류 확인 2건**(11단계): 개인정보처리방침의 수집 항목 서술과 어긋나지 않는지, Play 데이터 보안 양식에 변화가 있는지. 설계상 **둘 다 변화 없을 것으로 본다** — 기한은 사용자가 자기 할 일에 적는 내용이고 기기 밖으로 새로 나가는 데이터가 없으며(알림이 기기 로컬이다), `POST_NOTIFICATIONS`는 이미 선언돼 쓰이고 있다. 확인만 한다.

---

## 결정 기록 (2026-11-09 오너, 메인 세션)

아래 네 건은 전부 **설계의 권고대로 확정**됐다. 미결 없음.

1. **`flutter_localizations`(ko 고정)를 넣는다.** CLAUDE.md의 "다국어(i18n) 세팅 금지"와 충돌하지 않는 것으로 본다 — 언어를 ko 하나로 고정하는 것은 다국어의 반대이고, `.arb`·`gen-l10n`·언어 분기가 생기지 않는다. 직접 제작 대안은 기각(월·요일 이름이 여전히 `MaterialLocalizations`에서 오므로 줄일 수도 없다).
2. **부정확 예약으로 간다.** 절전 상태에서 알림이 수십 분 늦을 수 있는 것을 받아들인다. 정확 알람 권한(`USE_EXACT_ALARM`/`SCHEDULE_EXACT_ALARM`)을 쓰지 않는다 — Play 심사에서 정당화를 요구받는 쪽을 피한다.
3. **권한 사전 안내를 두지 않는다.** 기한을 처음 정하는 순간 OS 권한 다이얼로그만 띄우고, 허용을 두 번 묻는 모양을 만들지 않는다. **`AppStrings`의 사전 안내 문구(`기한 알림을 받으려면 알림을 허용해 주세요.`)는 만들지 않는다.** 거부 상태의 안내(`알림이 꺼져 있어 기한 알림을 보낼 수 없어요.`)만 둔다.
4. **위젯 체크 때의 알림 취소 보장 공백을 받아들인다.** 지금은 위젯 체크 경로 자체가 없어 발생하지 않는 문제이고, home-widget 6단계가 올 때 "끝낸 할 일의 알림이 최대 한 번 울릴 수 있다"를 그 단계에서 다시 다룬다. **그를 위한 대비를 지금 미리 만들지 않는다.**

<details>
<summary>답을 받은 질문 (기록용)</summary>

1. **`flutter_localizations`(ko 한 벌)를 넣는 것이 CLAUDE.md "다국어(i18n) 세팅 금지"와 충돌하지 않는다고 봐도 되는가?**
   설계의 결론은 **충돌하지 않는다(채택 권고)**다. 근거는 5.2의 네 가지 — `.arb`·`gen-l10n`·번역 테이블이 생기지 않고, `locale`을 `ko`로 **고정**하므로 언어가 둘이 되지 않으며(다국어의 반대다), 하는 일은 SDK가 이미 가진 Material 위젯 문구를 한국어로 지목하는 것이고, SDK 패키지라 네이티브 위험이 없다. 대안은 둘 다 더 비싸다 — `MaterialLocalizations` 직접 구현(수십 개 멤버, Flutter 올릴 때마다 깨짐), 달력·시간 선택 직접 제작(월 이름·요일이 여전히 `MaterialLocalizations`에서 오므로 부분 제작으로 줄일 수도 없다). 금지 조항의 **글자**와 스치므로 확인만 받는다.
2. **기한 알림이 몇 분(절전 상태에서는 수십 분) 늦을 수 있는 것을 받아들이는가?**
   정확 알람(`USE_EXACT_ALARM`/`SCHEDULE_EXACT_ALARM`)을 쓰지 않기로 했다(8.2). Play 정책상 알람시계·캘린더 성격이 아닌 앱은 정당화를 요구받고, Android 14+에서는 사용자를 OS 설정로 보내는 안내가 하나 더 생긴다. 대가는 Doze에서의 지연이다. "기한 1시간 전"이 50분 전에 와도 뜻이 상하지 않는다고 보았는데, 오너가 "기한 시각 알림은 정확해야 한다"고 보면 정확 알람 + 정책 대응으로 바꿔야 한다.
3. **권한 요청 안내 문구(`기한 알림을 받으려면 알림을 허용해 주세요.`)를 띄울 자리가 없는 것을 받아들이는가?**
   OS 권한 다이얼로그에 우리 문장을 끼울 자리가 없고(`requestPermission()`에 rationale 인자가 없다), 요청 **전에** 우리 대화상자를 하나 더 띄우면 "허용하겠습니까?"를 두 번 묻는 모양이 된다(권한 다이얼로그가 두 겹으로 겹친다). 그래서 이 문구를 쓰지 않고, 거부 상태의 안내(`알림이 꺼져 있어 기한 알림을 보낼 수 없어요.`)만 둔다. 사전 안내를 꼭 보여야 한다면 대화상자 안 한 줄로 **요청 전에 상시 노출**하는 방식이 가능하다(기한을 정하지 않은 사용자에게도 보이는 비용이 있다).
4. **위젯에서 체크한 할 일의 알림 취소가 "앱 프로세스가 죽은 상태"에서는 보장되지 않는 것을 받아들이는가?**
   지금은 **위젯 체크 경로 자체가 구현돼 있지 않아 이 문제가 발생하지 않는다**(8.8). home-widget 6단계가 올 때, 앱이 살아 있으면 보정이 정확히 처리하지만, 프로세스가 죽은 분기에서는 백그라운드 isolate에서 알림 플러그인을 쓸 수 있는지가 검증되지 않은 위험이다. 실패하면 **다음에 앱을 열 때까지 최대 한 번, 이미 끝낸 할 일의 기한 알림이 울릴 수 있다.** 그 지연을 받아들이면 지금 설계대로 가고, 받아들이지 않으면 6단계에서 "위젯 체크는 앱이 살아 있을 때만 허용" 같은 축소가 필요해진다(= home-widget 쪽 범위 변경).

</details>
