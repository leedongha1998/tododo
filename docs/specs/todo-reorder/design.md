# todo-reorder 설계

## 참고

- spec.md: `docs/specs/todo-reorder/spec.md` (2026-11-10 오너 승인, **이 설계의 유일한 요구사항**). 특히 "## 확정 결정" 2건, "## 결정 기록" 3건, "P0. 순서를 어디에 두는가"의 **성질 5개**, "P0. 끌기 제스처"의 **깨지면 안 되는 것 8개**, "P1. 폐기 목록", "## 범위 밖"이 기준이다.
- 선례로 읽은 설계: `docs/specs/todo-due-date/design.md`(이 저장소의 설계 형식·원칙·단계 분할의 기준. 1장 데이터·5장 화면·10장 테스트를 그대로 따랐다), `docs/specs/home-widget/design.md`(11.2의 "앱·백그라운드 isolate가 같은 `fetchTodos`를 쓴다", 12장 테스트 전략).
- 근거로 읽은 현재 구현: `lib/features/todo/`(11파일 전부), `lib/core/{strings.dart,theme/{app_icons.dart,app_theme.dart},widgets/app_panel.dart,navigation/main_shell.dart}`, `supabase/migrations/{20260818220000_profiles_and_todos.sql,20261109120000_todos_due_at.sql,20260910120000_forfeit_battle.sql}`, `test/{widget_test.dart,features/todo/**}`, `pubspec.yaml`.
- **코드를 읽고 확인한 사실 5건**(설계가 여기에 걸려 있다):
  1. **`fetchTodos`의 `.order('created_at')`는 내림차순이다.** postgrest Dart의 `order(column, {bool ascending = false})` 기본값이 **내림차순**이고, 지금까지는 `sortedForList`가 Dart에서 다시 정렬해 덮었기 때문에 드러나지 않았다. 정렬을 서버로 옮기는 순간 이 기본값이 **그대로 화면 순서**가 된다 → 1.6에서 `ascending: true`를 반드시 적는다. 이 설계에서 가장 조용히 깨질 수 있는 한 줄이다.
  2. **위젯 체크의 백그라운드 경로는 아직 없다.** `lib/features/todo/`에 `todo_widget_callback.dart`가 없고 `fetchTodos`를 부르는 곳은 `todosProvider` **하나뿐**이다(home-widget 4~7단계는 계획만). 그 경로가 올 때 `fetchTodos`를 그대로 쓰기로 이미 정해져 있다(home-widget design 11.2 458행) → 2장이 이 사실 위에 선다.
  3. **`planDueAlarms`는 목록 순서를 보지 않는다.** 내부에서 "울릴 시각 오름차순 → todoId → 시점"으로 다시 정렬한다(`due_alarm_plan.dart:164~174`). 줄을 옮겨도 예약 집합·순서가 **한 비트도** 바뀌지 않는다 → 기한 알림을 건드리지 않는다는 요구가 코드 구조로 이미 지켜진다.
  4. **`todosProvider`는 16곳의 테스트가 `overrideWith((ref) async => todos)`로 가짜를 끼운다**(`FutureProvider` 형태). 이 사실이 4.6의 상태 배치 결정을 갈랐다.
  5. **`Transform.scale`은 레이아웃이 아니라 그림만 키운다.** 지금 체크박스의 "터치 상자 64dp"는 **그려지는 상자**이고 실제 히트 영역은 `ListTile`의 48dp 칸이다(부모 `RenderBox`가 자기 크기 밖의 좌표를 먼저 거른다). 4.2의 폭 산수와 9장의 테스트 수정이 이 구분 위에 선다.

---

## 설계 원칙 (전체를 관통하는 5가지)

1. **순서를 만드는 자리는 `order by position` 한 줄이다.** 이번에는 그 자리를 **서버**에 둔다. 앱 목록·홈 위젯 캐시 발행·(나중에 올) 위젯 체크 백그라운드 isolate는 모두 `fetchTodos` 하나를 지나므로, 순서를 만드는 자리가 물리적으로 둘이 될 수 없다(2장).
2. **자리 값은 클라이언트가 계산하지 않는다.** 끌기가 서버에 보내는 것은 "이 할 일을 저 할 일 바로 아래에 둔다"는 **기준 하나**이고, 자리 값은 서버가 **그 순간의 실제 이웃**에서 만든다. 낡은 좌표가 같은 자리 값을 만들 수 없다(1.4).
3. **끌기 한 번 = 트랜잭션 한 번.** 보통 한 행, 틈이 고갈된 드문 갈래에서는 그 사용자의 전체 행을 쓰지만 **언제나 한 함수 안**이다. "절반만 반영된 순서"가 남을 경로가 없다.
4. **순서 저장 실패는 삼키지 않는다.** 위젯 캐시 발행·기한 알림 예약과 **다르다** — 순서는 사용자가 방금 한 조작 그 자체다. 끌기 전 순서로 되돌리고 토스트를 띄운다(`CLAUDE.md`의 로그-전용 예외 목록에 순서를 **넣지 않는다**).
5. **기한은 표시만 남는다.** `formatDueLabel`·`formatDueValue`·8구간 표·색 규칙·기한 알림은 한 줄도 바뀌지 않고, `compareForList`/`sortedForList`만 사라진다. 이 기능이 지우는 것은 **정렬**이지 기한이 아니다.

---

## CLAUDE.md 규칙 대조

| 규칙 | 이 설계에서 |
|---|---|
| 대결 상태 전이·판정 로직은 DB/Edge에서, 화면은 표시만 | 이 기능은 **대결 테이블을 읽지도 쓰지도 않는다.** `battles`·`settle_expired_battles()`·점수·한도·서버 시각 기준에 손대지 않는다. 개인 투두 한 테이블에만 닿는다 |
| 스키마 변경은 마이그레이션 파일로만 | 1.2의 파일 하나(컬럼 1 + 시퀀스 1 + 유일 제약 1 + RPC 1). 대시보드 수정 없음 |
| RLS 정책은 테이블 만들 때 같이 | 새 테이블이 없다. 기존 정책 4개는 `auth.uid() = user_id` 행 조건식이라 새 컬럼의 영향을 받지 않는다(1.3) |
| 새 RPC는 `revoke execute ... from public, anon` + `auth.uid()` 가드 | `move_todo`가 둘 다 지킨다(1.4). SECURITY DEFINER라 RLS가 안 걸리므로 `user_id = auth.uid()`를 함수 안에서 직접 본다 |
| 참가자 검사에 `not in` 금지 | 해당 없음(대결이 아니다). 소유 검사는 `where id = ? and user_id = auth.uid()` + `not found`로 한다 |
| 사용자 FK는 `public.profiles`를 가리킬 것 | 새 테이블이 없어 해당 없음. `todos.user_id`가 `auth.users`를 가리키는 기존 상태는 **건드리지 않는다**(이 기능의 범위가 아니다) |
| 사용자에게 보이는 문자열은 한국어, `lib/core/strings.dart`에 모은다 | 7장에 새 문구 2개 전부 |
| 하드코딩 색은 테마에서 | `AppPalette.edge`(들린 줄의 그림자). ~~`AppPalette.inkMuted`(손잡이 아이콘)~~은 2026-11-10에 손잡이가 없어져 이 기능이 쓰지 않는다(삭제 아이콘이 여전히 그 색이다). **새 색 토큰을 만들지 않는다** |
| 에러는 삼키지 않는다 | 원칙 4. 순서 저장 실패는 토스트를 띄운다. 위젯 발행·기한 알림의 기존 로그-전용 예외는 그대로 |
| 새 패키지는 기존 것으로 되는지 먼저 확인 | **새 패키지가 없다.** 끌기는 Flutter SDK의 `ReorderableListView.builder` + `ReorderableDelayedDragStartListener`(2026-11-10 전에는 `ReorderableDragStartListener`)로 끝난다(4.1) → 릴리스 빌드 위험(네이티브)이 이 기능에는 없다 |
| 새 화면 하나 = 새 커밋 하나 | 10장의 단계가 커밋 단위다(확정은 plan.md) |
| 테스트 없이 판정 로직 수정 금지 | 판정 로직을 수정하지 않는다. 끌기 좌표 변환은 순수 함수로 떼어 유닛 테스트한다(3장) |
| iOS·i18n·미래 대비 추상화 금지 | Android 전용. 섹션·계층·다중 선택·순서 기준 설정을 가정한 자리를 만들지 않는다(spec "범위 밖") |

---

## 0. 전체 그림

```
서버 (마이그레이션 파일 하나)
  ├ todos.position bigint not null  (1024 간격 띄운 정수, 기본값 = 시퀀스 * 1024)
  ├ unique (user_id, position) deferrable        ← 동순위 금지 + 목록 쿼리의 인덱스
  └ move_todo(p_todo_id, p_after_id) RPC         ← 끌기 한 번 = 이 호출 한 번

Dart
  ├ fetchTodos: order('position', ascending: true).order('id')   ← 순서를 만드는 유일한 자리
  ├ moveTodo(todoId, afterId: ...)                               ← 레포지토리 한 메서드
  ├ planTodoMove(todos, oldIndex, newIndex) (순수 함수)          ← 좌표 → 결과 목록 + 기준 id
  └ TodoListScreen: ReorderableListView.builder + 줄 전체를 꾹 눌러 집기
                     (2026-11-10 오너 확정. 그 전에는 전용 손잡이였다)
       └ 낙관적 적용 → 실패 시 끌기 전 순서로 되돌리고 토스트

지우는 것
  └ sortedForList / compareForList + 그 테스트 + "기한이 순서를 만든다"고 적힌 문서·주석 9곳
```

**새로 생기는 화면이 없고, 새 패키지가 없고, 새 cron·Edge Function이 없다.** 서버 변경은 파일 하나이고 그 적용 시점은 오너가 확정했다(구현 완료 후 기기 설치 직전 — spec 결정 기록 3, 11장).

---

## 1. 데이터·서버

### 1.1 자리 값의 모양 — **띄운 정수**(1024 간격)를 고른다

spec이 비교한 네 방식을 성질 5개(동순위 없음 / 다른 줄의 상대 순서 불변 / 부분 적용 없음 / 순서를 만드는 자리 하나 / 100개에서도 안 느림)로 다시 본 결과다.

| 방식 | 끌기 한 번의 쓰기 | 판단 |
|---|---|---|
| 촘촘한 정수(0,1,2…) | 옮긴 구간 전체 | **기각.** 맨 위로 끌면 사실상 전체를 다시 쓴다. 쓰기량이 목록 길이에 비례해 성질 5를 위태롭게 하고, 한 번의 끌기가 늘 여러 행을 건드려 **부분 적용을 막는 일이 기본 경로**가 된다 |
| **띄운 정수(1024, 2048…)** | **보통 한 행** | **채택.** 평소 쓰기가 한 행이라 원자성이 공짜고(성질 3), 100개든 1000개든 한 행이다(성질 5). 사람이 읽는 값이라 대시보드에서 순서를 눈으로 확인할 수 있다(로컬 DB가 없는 이 저장소에서 작지 않은 이점이다). 대가는 **재번호 경로가 반드시 있어야 한다**는 것이고, 그 길을 `move_todo` 안의 한 갈래로 두어 트랜잭션 밖으로 새지 않게 했다(1.4) |
| 소수/분수 자리값 | 항상 한 행 | 기각. `numeric`이면 고갈이 사실상 없지만 같은 틈에 반복해 끼울 때 **자릿수가 끝없이 자란다**(사람이 못 읽는 값 = 대시보드로 확인할 수 없는 순서). `double precision`을 쓰면 정밀도 고갈이 **조용히** 동순위를 만들어 성질 1을 깬다 — 재번호 경로는 결국 또 필요하고, 그때 "언제 고갈됐는지"를 판정하는 규칙이 더 어렵다 |
| 앞·뒤를 가리키는 연결 구조 | 세 행 | 기각(spec도 "이 규모에 과하다"고 적었다). 한 군데만 깨져도 목록이 끊기거나 순환하고, 목록을 받을 때마다 순서를 복원하는 비용이 생긴다. **`order by` 한 줄로 끝나는 성질 4의 이점을 통째로 잃는다** |

채택안이 성질 5개를 지키는 방식:

| spec의 성질 | 이 설계에서 |
|---|---|
| 동순위가 없다 / 두 번 받으면 같은 순서 | `unique (user_id, position)`을 **DB가** 강제한다(1.2). 쿼리도 `order by position, id`로 전순서를 만든다(1.6) |
| 한 번의 끌기가 다른 줄의 상대 순서를 흔들지 않는다 | 보통 갈래는 **옮긴 한 행만** 쓴다. 재번호 갈래도 값만 바뀌고 상대 순서는 그대로다(`row_number()`가 지금 순서를 그대로 읽는다) |
| 부분 적용이 남지 않는다 | 끌기 한 번 = RPC 한 번 = 트랜잭션 한 번(PostgREST). 재번호도 그 안이다 |
| 순서를 만드는 자리는 하나다 | 2장 |
| 100개에서도 안 느리다 | 조회 2회(인덱스) + 쓰기 1행. 재번호는 O(n) 쓰기이지만 "같은 틈에 열 번 남짓 연달아 끼워 넣어야" 닿는다 |

### 1.2 마이그레이션 (파일 하나, 이게 서버 변경의 전부다)

`supabase/migrations/20261110130000_todos_position.sql`

```sql
-- 개인 투두의 손 순서(todo-reorder P0).
--
-- 지금까지 목록 순서는 서버가 아니라 Dart가 만들었다(todo-due-date의 sortedForList — 기한 이른
-- 순). 그 규칙을 걷어내고 **사용자가 끌어 정한 순서**를 이 컬럼 하나로 옮긴다. 이 뒤로 목록
-- 순서를 만드는 자리는 "order by position" 한 줄뿐이다.
--
-- 20261109120000_todos_due_at.sql의 주석은 "기한 순서는 서버가 아니라 Dart(sortedForList)가
-- 만든다 / 정렬을 서버로 옮기면 그때 (user_id, due_at) 인덱스를 추가한다"고 적혀 있다.
-- 그 파일은 이미 원격에 적용돼 고치지 않는다. 지금 상태는 이렇다: **정렬은 서버로 왔지만
-- 기한으로 정렬하지 않으므로 그 인덱스는 끝내 만들지 않는다.** due_at은 표시용이고, 순서는
-- 이 컬럼이다. 두 파일을 함께 읽으면 현재 상태가 보인다.
--
-- 자리 값은 1024 간격의 띄운 정수다(design 1.1). 끌기 한 번은 보통 한 행만 쓰고(옮긴 행의
-- position을 두 이웃의 중간값으로), 틈이 고갈되면 move_todo 안에서 다시 번호를 매긴다.
-- 대결과 아무 관계가 없다 — 이 컬럼을 읽는 판정·점수·cron·Edge Function 경로는 없다.

-- 1) 컬럼. 백필 전까지만 nullable이다(3번에서 not null로 닫는다).
alter table public.todos
  add column position bigint;

-- 2) 기존 행 백필 — **생성순 한 줄**(오너 확정, spec 결정 기록 1).
--    기한을 보는 백필을 만들지 않는다: 한 번 쓰고 버릴 정렬 규칙을 SQL에 다시 구현하는 비용만
--    남는다. 배포 전이라 쌓인 데이터가 오너 테스트 계정뿐이고 그 할 일은 전부 기한이 없어
--    두 방식의 결과가 같다.
--    사용자별로 나누지 않아도 된다 — 번호를 전역 생성순으로 매겨도 각 사용자 안에서는 생성순이다.
with ordered as (
  select id, row_number() over (order by created_at, id) as rn
  from public.todos
)
update public.todos t
set position = ordered.rn * 1024
from ordered
where ordered.id = t.id;

-- 3) 새 행의 자리 = 맨 아래. **시퀀스**로 정한다.
--    "max(position) + 1024"을 트리거로 계산하지 않는 이유: 두 기기가 같은 순간에 추가하면 같은
--    max를 읽어 같은 자리 값을 만들고, 아래 유일 제약에 걸려 **추가 자체가 실패**한다. 시퀀스는
--    동시 호출에도 서로 다른 값을 주므로 둘 다 성공하고 둘 다 맨 아래로 간다(호출된 순서대로).
--    "맨 아래"가 깨지지 않는 근거: nextval은 단조 증가하고, 지금까지 발급한 수는 언제나 그
--    사용자의 행 수 이상이므로 재번호가 만드는 최댓값(행 수 * 1024)보다 다음 발급 값이 크다.
create sequence public.todos_position_seq as bigint;

select setval(
  'public.todos_position_seq',
  coalesce((select max(position) / 1024 from public.todos), 0) + 1,
  false  -- 다음 nextval이 이 값을 돌려준다(= 백필한 마지막 번호 바로 뒤)
);

alter table public.todos
  alter column position set default (nextval('public.todos_position_seq') * 1024),
  alter column position set not null;

-- 컬럼 기본값의 nextval은 **삽입하는 역할의 권한**으로 평가된다. authenticated에 usage가 없으면
-- 할 일 추가가 전부 실패한다. public·anon에는 주지 않는다(RLS로도 막히지만 권한까지 닫아 둔다).
revoke all on sequence public.todos_position_seq from public, anon;
grant usage on sequence public.todos_position_seq to authenticated;

comment on column public.todos.position is
  '개인 투두 목록의 손 순서(작은 값이 위). 1024 간격의 띄운 정수. 사용자 안에서만 뜻이 있고 값의 크기 자체에는 뜻이 없다 — 맨 위로 반복해 끌면 음수가 될 수 있고 정상이다.';

-- 4) 동순위를 **DB가** 막는다. 덤으로 목록 쿼리(where user_id = ? order by position)가 쓰는
--    인덱스가 여기서 생긴다 — 그래서 인덱스를 따로 만들지 않는다(기존 todos_user_id_idx는 이
--    인덱스의 접두사가 되어 사실상 중복이지만, 지우는 것은 이 기능의 범위가 아니라 그대로 둔다).
--    deferrable인 이유는 재번호(move_todo의 드문 갈래)가 한 문장 안에서 값을 돌려 끼우기 때문이다.
--    행별 즉시 검사에 헛되게 부딪히므로 그 갈래에서만 commit 시점으로 미룬다(1.4).
alter table public.todos
  add constraint todos_user_position_key unique (user_id, position)
  deferrable initially immediate;
```

- **이 파일에 더 들어가는 것은 1.4의 RPC뿐이다.** 트리거·새 정책·cron을 넣지 않는다.
- 원격 적용은 오너 승인 뒤 **구현이 끝나고 기기 설치 직전**이다(spec 결정 기록 3). 컬럼이 없는 동안 새 앱을 깔면 `fetchTodos`의 `order('position')`과 `move_todo` 호출이 전부 실패한다.

### 1.3 인덱스·RLS·트리거

| 항목 | 판단 |
|---|---|
| 인덱스 | **`unique (user_id, position)`이 그 인덱스다.** 이번에는 **서버가 정렬하므로**(2장) `where user_id = ? order by position`을 인덱스로 받아야 하고, 그 인덱스가 동순위 금지와 같은 물건이다. 별도 `create index`를 쓰지 않는다. (직전 기능이 인덱스를 안 만든 이유는 "Dart가 정렬해서 `due_at`으로 정렬·필터하는 SQL이 없다"였다 — 그 전제가 이번에 바뀌었다) |
| RLS 정책 4개 | **영향 없음.** 행 조건식(`auth.uid() = user_id`)이고 컬럼 목록을 갖지 않는다. `move_todo`는 SECURITY DEFINER라 정책을 지나지 않으므로 소유 검사를 함수 안에서 직접 한다 |
| 테이블 권한 | **영향 없음**(테이블 단위 grant에 새 컬럼이 자동 포함된다). 새로 필요한 권한은 시퀀스 usage 하나다(1.2) |
| `todos_set_updated_at` 트리거 | 순서를 바꾸면 `updated_at`이 올라간다. **의도한 동작**이고 읽는 곳이 없다. 재번호 갈래에서는 그 사용자의 모든 행의 `updated_at`이 함께 올라간다 — 역시 읽는 곳이 없다 |
| `delete_account` RPC / cascade | 영향 없음. 행이 지워지면 컬럼도 사라진다. 시퀀스는 전역이고 값이 재사용되지 않아도 무해하다 |

### 1.4 `move_todo` — 끌기 한 번이 서버에 하는 일 전부

같은 파일에 이어 적는다.

```sql
-- 끌기 한 번 = 이 함수 한 번 = 트랜잭션 한 번. "절반만 반영된 순서"가 남을 경로가 없다.
--
-- 클라이언트는 **자리 값을 계산하지 않는다.** 보내는 것은 "이 할 일을 p_after_id 바로 아래에
-- 둔다"(null이면 맨 위)뿐이고, 자리 값은 서버가 **그 순간의 실제 이웃**에서 만든다. 그래서 다른
-- 기기가 그 사이 순서를 바꿔 좌표가 낡았어도 같은 자리 값이 생기지 않는다. 결과가 "이상한
-- 순서"일 수는 있고 그것은 spec이 받아들인 것이다(마지막 쓰기가 이긴다).
create function public.move_todo(p_todo_id uuid, p_after_id uuid default null)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_after_pos bigint;
  v_next_pos bigint;
  v_new_pos bigint;
begin
  if v_user is null then
    raise exception '로그인이 필요합니다.';
  end if;

  -- 내 할 일 전부를 잠근다. 같은 사용자의 두 끌기가 겹쳐 같은 틈의 중간값을 각자 계산하는 것을
  -- 막는다(뒤에 온 트랜잭션은 잠금이 풀린 뒤 READ COMMITTED의 새 스냅샷으로 다시 계산한다).
  -- 두 트랜잭션이 같은 조건으로 같은 순서로만 잠그므로 교착이 없다. 행 수는 수십 규모다.
  perform 1 from public.todos where user_id = v_user for update;

  -- SECURITY DEFINER라 RLS가 적용되지 않는다. 내 행인지 여기서 직접 본다.
  perform 1 from public.todos where id = p_todo_id and user_id = v_user;
  if not found then
    raise exception '할 일을 찾을 수 없습니다.';
  end if;

  if p_after_id is not null then
    if p_after_id = p_todo_id then
      raise exception '옮길 자리가 잘못됐습니다.';
    end if;
    select position into v_after_pos
    from public.todos
    where id = p_after_id and user_id = v_user;
    -- position은 not null이므로 "값이 비었다"는 경우가 없다. not found는 그 행이 없다는 뜻이다
    -- (다른 기기에서 지웠다). 조용히 맨 위로 보내지 않고 실패로 알린다 — 화면은 끌기 전 순서로
    -- 되돌리고 다음 조회에서 진실을 받는다(design 4.6).
    if not found then
      raise exception '옮길 자리를 찾을 수 없습니다.';
    end if;
  end if;

  -- 놓일 자리의 아래쪽 이웃. 옮기는 행 자신은 뺀다. 집계라서 행이 없으면 null이다.
  select min(position) into v_next_pos
  from public.todos
  where user_id = v_user
    and id <> p_todo_id
    and (v_after_pos is null or position > v_after_pos);

  if v_after_pos is null then
    -- 맨 위. 1024씩 내려가며 음수가 될 수 있고 그래도 무해하다(정렬에만 쓰는 값이다).
    -- 여기서 재번호를 걸지 않는 이유: 재번호 직후 맨 위는 1024이므로, 음수를 막으려 들면
    -- "맨 위로 끌기"가 매번 전체 재번호가 된다.
    v_new_pos := coalesce(v_next_pos, 1024) - 1024;
  elsif v_next_pos is null then
    v_new_pos := v_after_pos + 1024;                             -- 맨 아래
  elsif v_next_pos - v_after_pos >= 2 then
    v_new_pos := v_after_pos + (v_next_pos - v_after_pos) / 2;   -- 정수 나눗셈(내림)
  else
    -- 틈 고갈. 같은 틈에 열 번 남짓 연달아 끼워 넣으면 닿는다. 이 사용자의 목록을 **원하는 최종
    -- 순서 그대로** 1024 간격으로 다시 매긴다 — 상대 순서는 하나도 바뀌지 않고 값만 바뀐다.
    -- 유일 제약을 commit까지 미루는 이유: 한 문장 안에서 값을 돌려 끼우면 행별 즉시 검사가
    -- 헛되게 부딪힌다. (이 한 줄을 쓸 수 없는 환경이면 대안은 두 문장이다 —
    --  ① 모든 행을 greatest(max, 행수*1024) - min + 1024 만큼 올려 기존·목표 값 위로 비켜 두고
    --  ② 1024부터 다시 매긴다.)
    set constraints todos_user_position_key deferred;

    with ordered as (
      select id,
             row_number() over (
               -- 옮긴 행은 기준 행과 같은 키를 갖고 보조 키 1로 **바로 뒤**에 선다. 기준 행의
               -- 아래쪽 이웃은 position > v_after_pos라 자연히 그 다음이다.
               order by case when id = p_todo_id then v_after_pos else position end,
                        case when id = p_todo_id then 1 else 0 end
             ) as rn
      from public.todos
      where user_id = v_user
    )
    update public.todos t
    set position = ordered.rn * 1024
    from ordered
    where ordered.id = t.id;

    return;
  end if;

  update public.todos set position = v_new_pos where id = p_todo_id;
end;
$$;

-- Postgres는 PUBLIC에, Supabase는 anon에 EXECUTE를 기본으로 준다. 둘 다 회수한 뒤 부여한다.
revoke execute on function public.move_todo(uuid, uuid) from public, anon;
grant execute on function public.move_todo(uuid, uuid) to authenticated;

comment on function public.move_todo is
  '개인 투두 하나를 p_after_id 바로 아래로 옮긴다(p_after_id가 null이면 맨 위). 자리 값은 서버가 그 순간의 실제 이웃에서 만들고, 틈이 고갈되면 그 사용자의 목록을 다시 번호 매긴다.';
```

**쓰기량과 실패 모드**

| 상황 | 쓰는 행 | 결과 |
|---|---|---|
| 보통(틈이 있다) | **1행** | 성공 |
| 맨 위 / 맨 아래로 | **1행** | 성공 |
| 틈 고갈 | 그 사용자의 전체 행 | 성공(한 트랜잭션) |
| 기준 할 일이 지워졌다(다른 기기) | 0행 | 예외 → 화면이 되돌리고 토스트 |
| 내 할 일이 아니다 / 비로그인 | 0행 | 예외 |
| 같은 사용자의 두 끌기가 겹침 | 1행씩 차례로 | 둘 다 성공(잠금으로 직렬화). 나중 것이 이긴다 |

### 1.5 새 할 일이 맨 아래로 가는 방법 — `addTodo`는 아무것도 하지 않는다

- `addTodo`는 지금처럼 `insert {user_id, title, due_at}`만 보낸다. **`position`을 보내지 않는다** → 컬럼 기본값(`nextval * 1024`)이 맨 아래를 만든다.
- **동시에 두 기기에서 추가하면?** 시퀀스가 서로 다른 값을 주므로 **둘 다 성공하고 둘 다 맨 아래**에 생기며, 둘 사이의 순서는 서버가 `nextval`을 내준 순서다. 동순위도, 추가 실패도 없다. (이 한 문장이 1.2에서 트리거 대신 시퀀스를 고른 이유 전부다.)
- **다만 `move_todo`의 "맨 아래로" 분기가 같은 값 공간을 쓴다**(2026-11-10 리뷰 지적, 반드시 고칠 것). 그 분기는 `max + 1024`를 그 행에 주므로 **시퀀스를 앞질러** 다음 insert가 받을 값(`nextval * 1024`)과 같아질 수 있고, 그러면 `unique (user_id, position)`에 걸려 **다음 "할 일 추가"가 실패한다**(백필 직후 예: position 1024·2048·3072·4096, 시퀀스의 다음 값 5 → 맨 아래로 한 번 끌면 그 행이 5120, 다음 추가도 5120). 맨 아래로 k번 끌면 k번 연달아 실패한다. 그래서 **그 분기가 시퀀스를 자기 값 위로 밀어 둔다**: `perform setval('public.todos_position_seq', greatest(nextval(...), v_new_pos / 1024))`. `greatest`로 감싸 시퀀스를 뒤로 되돌리지 않고, 정수 나눗셈이 내림이어도 다음 발급 값은 언제나 `v_new_pos`보다 크다. 1.4의 SQL과 1.2의 근거 주석이 **두 분기를 모두** 말한다.
- 기한을 넣어 추가해도 자리는 맨 아래다(기한이 자리를 결정하는 경로가 코드에 남지 않는다).
- 화면에서 "어디 생겼는지" 보이게 하는 것은 4.5다.

### 1.6 레포지토리 — 바뀌는 메서드 둘

`lib/features/todo/data/todo_repository.dart`

```dart
  /// 목록 순서는 **서버가 만든다**(todo-reorder design 2장). 앱 목록·홈 위젯 캐시 발행·위젯
  /// 체크를 처리할 백그라운드 경로가 이 메서드 하나를 지나므로, 순서를 만드는 자리가 둘이 될 수
  /// 없다. `position`은 사용자가 끌어 정한 값이고(1024 간격), 같은 사용자의 두 행이 같은 값을
  /// 가질 수 없다(unique (user_id, position)).
  ///
  /// **`ascending: true`를 반드시 적는다.** postgrest의 `order`는 기본이 **내림차순**이다 —
  /// 지금까지 `order('created_at')`로 적혀 있던 것도 내림차순이었고, Dart가 다시 정렬해 덮었기
  /// 때문에 드러나지 않았다. 그 정렬을 걷어낸 지금은 이 한 줄이 그대로 화면 순서다.
  /// id까지 적는 이유: 동순위는 제약이 막지만, 순서의 보장을 제약 하나에 매달지 않고 쿼리 자체를
  /// 전순서로 만든다(수십 행 규모에서 비용이 없다).
  Future<List<Todo>> fetchTodos(String userId) async {
    final rows = await _client
        .from('todos')
        .select()
        .eq('user_id', userId)
        .order('position', ascending: true)
        .order('id', ascending: true);
    return rows.map(Todo.fromMap).toList();
  }

  /// 끌기 한 번. [afterId]가 null이면 맨 위다.
  ///
  /// **자리 값을 클라이언트가 계산하지 않는다** — 서버가 그 순간의 실제 이웃에서 만든다(design
  /// 원칙 2). 그래서 보내는 것이 "기준 할 일 하나"뿐이고, 한 번의 호출이 한 트랜잭션이라
  /// 절반만 반영된 순서가 남지 않는다. 실패는 호출자가 토스트로 알린다(삼키지 않는다).
  Future<void> moveTodo(String todoId, {required String? afterId}) {
    return _client.rpc(
      'move_todo',
      params: {'p_todo_id': todoId, 'p_after_id': afterId},
    );
  }
```

- `addTodo`·`setDone`·`updateTodo`·`deleteTodo`는 **한 줄도 바뀌지 않는다**.
- `Todo` 모델도 바뀌지 않는다. **`position`을 모델에 싣지 않는다** — 화면·위젯·알림이 그 값을 쓸 일이 없고(순서는 리스트의 차례로 이미 표현된다), 실으면 "클라이언트가 자리 값을 다룬다"는 오해가 생긴다(원칙 2). 서버가 보낸 `position` 키는 `Todo.fromMap`이 그냥 무시한다.

---

## 2. 정렬을 **서버**에서 하는 이유 (직전 기능과 반대로 가는 결정)

`todo-due-date`는 "서버 `order`로 표현할 수 있지만 Dart로 한다"를 택했다. 그 근거는 **규칙을 유닛 테스트로 고정하기 위해서**였다(로컬 Docker가 없어 DB 테스트를 돌릴 수단이 없다). 이번에는 전제가 둘 다 바뀐다.

| 안 | 판단 | 이유 |
|---|---|---|
| A. Dart가 `position`으로 정렬(`todosProvider`에서) | 기각 | **위젯 체크 백그라운드 경로가 `todosProvider`를 지나지 않는다.** 그 경로는 레포지토리를 직접 부르기로 이미 정해져 있다(home-widget design 11.2). 정렬이 provider에 있으면 그 경로는 정렬 함수를 **따로 불러야** 하고, 부르지 않아도 아무도 모른다 — spec이 "순서를 만드는 자리는 하나다"를 성질로 못 박은 이유가 정확히 이것이다 |
| **B. 서버 `order by position, id`** | **채택** | `fetchTodos`를 부르는 모두가 **같은 SQL 한 줄**을 받는다. 자리를 잊을 수 있는 호출자가 존재하지 않는다. 인덱스는 동순위 금지 제약이 이미 만들어 둔다(1.3) |
| C. 둘 다(서버 정렬 + Dart 재정렬) | 기각 | 규칙이 두 곳에 적히고 한쪽만 고쳐도 아무도 모른다(직전 설계가 같은 이유로 기각했다) |

**"그럼 순서 규칙의 유닛 테스트는 어디로 가는가"** — 규칙이 "정렬 비교 함수"에서 "컬럼 값과 그 값을 정하는 서버 함수"로 옮겨갔으므로, 테스트해야 하는 판단도 달라졌다.

- 유닛 테스트가 **닿는** 것: 끌기 좌표 → 결과 목록·기준 id 변환(3장. `ReorderableListView`의 `newIndex` off-by-one이 이 기능에서 가장 흔한 버그다), 낙관적 적용·되돌리기 규칙(위젯 테스트, 9장).
- 유닛 테스트가 **닿지 않는** 것: 중간값 계산·재번호·백필(SQL). 대가를 받아들이고 **산수를 극단적으로 단순하게** 유지했다(중간값은 정수 나눗셈 한 줄, 백필은 `row_number()` 한 줄) + 11장의 수동 확인 절차로 본다. 재번호 갈래는 평소 돌지 않으므로 **일부러 강제해 한 번 보는 절차**를 11장에 적었다.
- 받아들이는 위험 하나: `.order(..., ascending: true)`를 빼먹으면 목록이 **조용히 뒤집힌다**(참고 1번). 유닛 테스트가 닿지 않는 자리이므로 레포지토리 주석과 11장 수동 확인에 함께 박았다.

위젯 캐시는 **한 줄도 바뀌지 않는다.** `TodoWidgetPayload.fromTodos`는 받은 순서를 보존만 하므로(`where`→`take`) 새 순서가 그대로 캐시에 실린다. 바뀌는 것은 그 사실을 적어 둔 주석·테스트·문서다(8장).

---

## 3. 순수 함수 — `planTodoMove`

`lib/features/todo/domain/todo_order.dart` (신규, Flutter 의존 없음. 선례: `due_alarm_plan.dart`의 `plan*`)

```dart
/// 끌어 놓은 좌표를 **화면에 바로 적용할 목록**과 **서버에 보낼 기준 할 일**로 바꾼다.
///
/// `ReorderableListView.onReorder`의 [newIndex]는 **옮길 줄을 아직 빼지 않은 좌표**다 — 아래로
/// 내릴 때(newIndex > oldIndex) 1을 빼야 실제로 놓이는 자리가 된다. 이 off-by-one이 끌기
/// 기능에서 가장 흔한 버그이므로 변환을 화면에서 떼어 테스트로 고정한다.
///
/// [afterId]는 "옮긴 줄의 바로 위에 있는 할 일"의 id이고, 맨 위에 놓였으면 null이다. 서버는 이
/// 기준 하나만 받아 자리 값을 스스로 만든다(design 원칙 2) — 클라이언트는 자리 값을 모른다.
///
/// [changed]가 false면 제자리다. 그때는 서버를 부르지 않는다(끌었다가 같은 자리에 놓는 일은
/// 흔하고, 그걸로 쓰기와 재조회를 일으킬 이유가 없다).
({List<Todo> todos, String? afterId, bool changed}) planTodoMove(
  List<Todo> todos, {
  required int oldIndex,
  required int newIndex,
}) {
  if (oldIndex < 0 || oldIndex >= todos.length) {
    return (todos: todos, afterId: null, changed: false);
  }
  final target = (newIndex > oldIndex ? newIndex - 1 : newIndex)
      .clamp(0, todos.length - 1);
  if (target == oldIndex) {
    return (todos: todos, afterId: null, changed: false);
  }
  final moved = [...todos];
  moved.insert(target, moved.removeAt(oldIndex));
  return (
    todos: moved,
    afterId: target == 0 ? null : moved[target - 1].id,
    changed: true,
  );
}
```

- **완료 여부·기한을 보지 않는다.** 모든 줄이 같은 규칙으로 옮겨진다(spec 확정 결정 2).
- 받은 리스트를 제자리에서 바꾸지 않는다(`[...todos]`).
- 이 파일에 자리 값 계산이 **없다.** `position`·1024·중간값이라는 말이 Dart에 한 번도 등장하지 않는 것이 원칙 2의 모습이다.

---

## 화면

## 4. 화면

**새 화면이 없다.** 바뀌는 자리는 `lib/features/todo/presentation/todo_list_screen.dart` 하나이고, 빈 상태·로딩·에러 화면과 추가·수정 대화상자는 **그대로**다(`StatusMessage.empty/loading/error`, 문구 변화 없음).

### 4.1 무엇으로 구현하나 — `ReorderableListView.builder` + ~~전용 손잡이~~ **꾹 눌러 집기**

> **2026-11-10 오너가 손잡이를 없앴다**(spec "P0. 끌기 제스처" 절 머리글 참고). 4.1~4.2의
> 아래 서술은 **결정의 이력으로 남긴다.** 지금 참인 것은 이렇다:
> - 끌기 시작: 줄 전체를 `ReorderableDelayedDragStartListener`로 감싼다(= 꾹 누르면 집힌다).
>   `buildDefaultDragHandles`는 **여전히 false**다 — SDK 기본값은 `Theme.of(context).platform`을
>   보고 갈라져 데스크톱에서 **줄 오른쪽에 손잡이 아이콘을 다시 그리기** 때문에, 방금 없앤
>   손잡이가 플랫폼에 따라 되살아나는 구조를 남기지 않는다.
> - 짧게 누르기(수정)와의 공존: 분기를 쓰지 않고 **제스처 경기장**이 시간으로 가른다.
>   `DelayedMultiDragGestureRecognizer`(500ms) vs `AppPanel`의 `TapGestureRecognizer` —
>   빨리 떼면 탭이 이기고(수정), 500ms를 넘겨 쥐면 끌기가 이겨 **탭이 취소**되며(수정이 열리지
>   않는다), 500ms 전에 움직이면 둘 다 지고 `Scrollable`이 이긴다(스크롤).
> - 줄의 칸은 **넷 → 셋**(체크박스 48 / 제목 / 삭제 48), 목록 좌우 여백은 **8 → 20dp**,
>   제목 칸은 **198 → 222dp**(실측). `todoDragHandleKey`·`AppIcons.dragHandle`·
>   `AppStrings.todoReorderHandle`은 **삭제**했다.
> - `IntrinsicHeight`는 남겼다 — 손잡이가 아니라 **체크박스 칸**이 줄 높이 전체를 히트 영역으로
>   갖게 하려는 것이다(`crossAxisAlignment: stretch`는 목록 줄의 무한 높이 제약 때문에
>   `IntrinsicHeight` 없이는 죽는다).
> - **집히는 순간 햅틱 하나**(`onReorderStart` → `HapticFeedback.selectionClick()`, 새 패키지
>   없음). 입구가 보이지 않으므로 "집혔다"는 신호를 시각적 들림 하나에만 맡기지 않는다.
>   **관문이 아니다** — 실패는 `debugPrint`만 남기고 끌기를 막지 않는다(장식 연출의 실패와 같은
>   성격이고, 방금 집은 줄 위로 스낵바를 띄우면 끌기를 방해한다).
> - 체크박스 위에서 **꾹 눌렀다 움직이지 않고 떼면 아무 일도 일어나지 않는다**(끌기 인식기가
>   탭을 가져간다). 끌기 입구를 제목 칸으로 좁히면 줄을 옮기려고 왼쪽을 잡았을 때 **할 일이
>   완료 처리되는** 더 비싼 사고가 생기므로 **이 동작을 택했고**, 그 갈래도 테스트로 고정했다.

| 안 | 판단 |
|---|---|
| `ReorderableListView`(비-builder) | 기각. 모든 줄을 미리 만든다. 지금이 `ListView.builder`이고 100개 이상에서도 느리지 않아야 한다(spec) |
| **`ReorderableListView.builder`** | **채택.** 지금의 `ListView.builder`와 호출 모양이 거의 같다(`itemCount`·`itemBuilder`·`padding`·`scrollController`). 끌기 중 자리 미리보기·자동 스크롤·애니메이션을 SDK가 준다 → **새 패키지가 없다**(릴리스 빌드 위험이 없다) |
| 직접 구현(`Draggable`+`DragTarget`) | 기각. 자리 미리보기·스크롤 중재·자동 스크롤·접근성을 새로 만들어야 하고, 그 전부가 SDK에 이미 있다 |

고정하는 인자:

```dart
ReorderableListView.builder(
  // 좌우는 8로 줄인다(4.2의 폭 산수). 위 16·아래 fabClearance는 그대로.
  padding: const EdgeInsets.fromLTRB(8, 16, 8, AppTheme.fabClearance),
  scrollController: _scrollController,          // 4.5(추가 직후 맨 아래로)
  itemCount: todos.length,
  // **길게 누르기를 쓰지 않는다**(오너 확정). 기본값(true)이면 모바일에서 줄 전체가 길게 눌러
  // 집히는 손잡이가 되어 "줄 전체 누르기 = 수정"과 싸운다.
  buildDefaultDragHandles: false,
  proxyDecorator: _liftedCard,                  // 4.3
  onReorder: (oldIndex, newIndex) => _onReorder(context, ref, todos, oldIndex, newIndex),
  itemBuilder: (context, index) { ... },         // 아래 4.2
)
```

- 줄의 키는 `ValueKey(todo.id)`를 **itemBuilder가 돌려주는 가장 바깥 위젯**에 둔다(`ReorderableListView`의 요구).
- 카드 간격 12는 그대로지만 **모든 줄이 같은 값**(`EdgeInsets.only(bottom: 12)`)을 쓴다. 지금은 마지막 줄만 0인데, 끌고 있는 동안 "마지막 줄"이 바뀌어 12dp가 튀기 때문이다. 늘어난 12dp는 `fabClearance` 아래에 묻힌다(목록 끝 여백이 12dp 넉넉해지는 것뿐이고 FAB 가림 테스트는 그대로 통과한다).
- 빈 목록은 지금처럼 리스트를 만들기 전에 `StatusMessage.empty`로 끝난다(`ReorderableListView`에 0개를 주지 않는다).

### 4.2 줄의 구조와 **폭 산수** — ~~제목 칸을 1dp도 깎지 않는 48dp를 만들어 온다~~

> **2026-11-10: 손잡이 칸과 여백 줄이기가 모두 폐기됐다**(4.1 머리글). 지금의 폭 산수는 이렇다 —
> 360dp 화면·1.5배 글자에서 **카드 320**(= 360 − 20 − 20) **− 체크 48 − 삭제 48 −
> `AppPanel` 테두리 2 = 제목 칸 222dp**(실측. `test/widget_test.dart`의 하한이 222다).
> 아래 표의 "이 설계" 칸(여백 8dp·손잡이 48dp·제목 198dp)은 **더 이상 참이 아니고 이력으로만**
> 남는다. `ListTile`을 쓰지 않는 이유(칸 폭을 산수로 보일 수 없다)는 그대로 유효하다.

`ListTile`을 **쓰지 않고** 네 칸의 `Row`로 바꾼다. 이유는 하나다: `ListTile`은 칸 폭을 자기 규칙으로 정하므로(leading 칸 + `horizontalTitleGap` + trailing 칸 + 내부 여백) 손잡이 48dp를 넣고도 제목 칸이 198dp 이상임을 **산수로 보일 수 없다.** 칸을 직접 쓰면 폭이 더하기 한 줄이 된다.

```dart
// 줄 하나(기한 있는 줄은 Column이 두 줄이 된다 — 지금과 같다)
Padding(
  key: ValueKey(todo.id),
  padding: const EdgeInsets.only(bottom: 12),
  child: panel(                                     // raised | inset, padding: EdgeInsets.zero
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 60),   // 지금의 minTileHeight 60
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ① 손잡이 48dp. 줄 높이 전체를 차지해 터치 영역은 48 x (60 이상)이다.
          ReorderableDragStartListener(
            index: index,
            child: Semantics(
              label: AppStrings.todoReorderHandle,
              child: const SizedBox(
                key: todoDragHandleKey,
                width: 48,
                child: Center(
                  child: Icon(AppIcons.dragHandle, size: 24, color: AppPalette.inkMuted),
                ),
              ),
            ),
          ),
          // ② 체크박스 48dp. 그림은 지금처럼 24dp(Transform.scale 24/18)이고, **히트 영역은
          //    이 칸 48dp**다(부모 RenderBox가 자기 크기 밖의 좌표를 먼저 거른다).
          SizedBox(
            key: todoCheckCellKey,
            width: 48,
            child: Center(child: Transform.scale(scale: 24 / 18, child: Checkbox(...))),
          ),
          // ③ 제목(+기한 줄). 남은 폭 전부.
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  KeepWordsText(todo.title, style: ...),       // 지금과 같다(취소선 포함)
                  if (due != null) ...[
                    const SizedBox(height: 2),
                    KeepWordsText(due.label, style: ...),      // 지금과 같다(tabular, 색 규칙)
                  ],
                ],
              ),
            ),
          ),
          // ④ 삭제 48dp. 상자를 48x48로 두어 지금과 같은 크기를 유지한다(줄 높이로 늘리지 않는다 —
          //    잘못 눌렸을 때 가장 비싼 동작이라 영역을 키우지 않는다).
          SizedBox(
            width: 48,
            child: Center(child: IconButton(icon: Icon(AppIcons.delete, ...), tooltip: AppStrings.delete, onPressed: ...)),
          ),
        ],
      ),
    ),
  ),
)
```

칸을 테스트가 집을 수 있게 **키 두 개**를 같은 파일의 최상위 상수로 둔다(위젯 테스트에서 "칸"과 "그려지는 상자"를 구분해 재야 하기 때문이다 — 9장·8.2).

```dart
// lib/features/todo/presentation/todo_list_screen.dart (최상위)
/// 손잡이 칸·체크박스 칸. 터치 영역과 겹침을 재는 기준은 **그려지는 상자가 아니라 이 칸**이다
/// (Transform.scale은 그림만 키운다 — 히트 테스트는 칸이 결정한다).
const todoDragHandleKey = Key('todoDragHandle');
const todoCheckCellKey = Key('todoCheckCell');
```

**폭 산수(360dp 화면, 1.5배 글자 — 이 앱의 기준 설정)**

| | 지금 | 이 설계 |
|---|---|---|
| 화면 폭 | 360 | 360 |
| 목록 좌우 여백 | 20 + 20 = 40 | **8 + 8 = 16** |
| 카드 폭 | 320 | **344** |
| `ListTile` `contentPadding` | 4 + 4 = 8 | 0 (칸을 직접 쓴다) |
| 손잡이 칸 | — | **48** |
| 체크박스 칸 | 48(+`horizontalTitleGap` 8) | 48 |
| 삭제 칸(+`ListTile` 내부 여백) | 48 + 약 10 | 48 |
| `AppPanel` 테두리(좌우 1dp씩) | 포함돼 있었다 | **2** |
| **제목 칸** | **198** | **344 − 48 − 48 − 48 − 2 = 198**(실측 확인) |

→ **제목 칸이 198dp로 1dp도 줄지 않는다.** 손잡이 48dp의 자리는 **카드 바깥 여백(20→8, 24dp)과 `ListTile`이 쓰던 내부 여백(contentPadding 8 + 제목 간격 8 + trailing 내부 약 10, 합 약 24dp)**에서 온다. (2026-11-10 구현·리뷰: 이 표가 처음에 **200**이라고 적었는데 `AppPanel`의 테두리 1dp × 2를 빼지 않은 계산이었다. 360dp·1.5배 실측은 손잡이 9→57, 체크 57→105, **제목 105→303(198)**, 삭제 303→351이고 `test/widget_test.dart`가 하한 198로 고정한다.) 제목을 잘라 만든 자리가 한 뼘도 없다. 360dp에서 산수가 이렇게만 성립한다는 사실이 "좌우 여백 8dp"의 근거이고, 그 한 가지가 오너 확인이 필요한 유일한 시각적 변화라 **"## 결정 필요" 1번**에 올렸다.

**보이는 간격은 좁아지지 않는다**: 제목 글자는 체크박스 칸(48) 바로 옆에서 시작하지만 체크박스 그림은 그 칸 가운데 24dp이므로 글자와 그림 사이에 **12dp의 빈 자리**가 남는다(지금은 간격 8 + 확대된 그림이 그 간격을 먹어 사실상 2dp였다). 손잡이 아이콘(24dp)과 체크박스 그림 사이도 24dp다.

**1.5배에서 깨지지 않는 근거**: 세 칸(48·48·48)은 글자 배율과 무관한 고정 폭이고, 늘어나는 것은 제목 칸의 **높이**뿐이다(`Expanded` + `Column` + `KeepWordsText`가 어절 단위로 줄을 늘린다). 줄 높이가 늘면 손잡이 터치 영역도 함께 커진다(`stretch`). 글자가 커져 칸이 좁아지는 자리가 구조적으로 없다.

**spec "깨지면 안 되는 것 8개" 대조**

| spec 조항 | 이 설계에서 |
|---|---|
| 체크박스 터치가 끌기로 오해되지 않는다 / "글자 앞을 눌러도 체크되지 않는다"가 유지된다 | 체크박스는 **자기 48dp 칸 안에서만** 눌린다(히트 테스트는 칸이 결정한다 — 참고 5번). 손잡이는 그 왼쪽의 **다른 칸**이고 겹치지 않는다. 글자 칸은 체크박스 칸 **오른쪽**이라 글자 앞을 눌러도 체크되지 않는다. 지금은 확대된 그림 상자가 간격을 넘어왔는데(그림 기준 56~60dp) 이 설계는 칸 경계가 곧 히트 경계라 **보장이 더 단단해진다**. 9장에서 테스트의 판정 기준을 "그려지는 상자"에서 "칸"으로 바로잡는다 |
| 삭제 버튼이 끌기로 오해되지 않는다 | 삭제는 오른쪽 끝 48x48에 그대로 있고, 손잡이는 **반대쪽 끝**이다(손잡이를 겨냥해 미끄러져도 닿는 것은 체크박스이고, 그 실수는 한 번 더 눌러 되돌린다. 삭제 옆에 손잡이를 두는 배치를 일부러 피했다) |
| 줄 전체 누르기 = 수정 | `AppPanel`의 `onTap`이 그대로 묶음을 받는다. 손잡이·체크박스·삭제는 안쪽이라 제스처 경쟁에서 먼저 이긴다(지금과 같은 구조). 손잡이를 **짧게 눌렀을 때**는 끌기 중재에 먹혀 아무 일도 일어나지 않을 수 있다 — spec이 "수정이 열려도 된다(필수는 아니다)"로 둔 자리이므로 어느 쪽이든 받고, 손잡이에 별도 `onTap`을 **붙이지 않는다** |
| 손잡이가 제목 칸(198dp)을 깎지 않는다 | 위 표. **198dp 그대로**(실측) |
| 손잡이 터치 영역 최소 48dp, 1.5배에서도 | 48 x 줄 높이(≥60, 1.5배 두 줄이면 약 90) |
| 스크롤과 싸우지 않는다 | 손잡이의 `ReorderableDragStartListener`는 즉시 인정되는 드래그 인식기라 **손잡이에서 시작한** 세로 이동만 재배치가 된다. 그 밖(제목·카드 여백·빈 곳)에서 시작한 세로 이동은 `Scrollable`이 받아 지금처럼 스크롤이다. `buildDefaultDragHandles: false`가 "줄 어디서나 길게 눌러 집기"를 없애 두 입구가 생기지 않게 한다 |
| 완료한 줄에도 손잡이가 있다 | 줄 구조가 하나다. `AppPanel.raised`/`inset`만 갈리고 그 **안**은 같다 — 손잡이를 완료 여부로 감추는 분기가 없다 |
| 끌고 있는 동안 어디에 놓이는지 보인다 | 4.3 |

### 4.3 끄는 동안의 모습

- **자리 미리보기**: `SliverReorderableList`가 끌고 있는 줄이 놓일 자리를 **빈 자리로 벌려** 보여 준다(SDK 기본). 카드 사이가 원래 12dp 떠 있는 디자인이라 벌어진 자리가 그대로 "여기 놓인다"로 읽힌다 — 점선·삽입선 같은 장치를 따로 그리지 않는다.
- **들린 줄**: 기본 `proxyDecorator`는 모서리를 모르는 직사각형 그림자를 그린다. 카드가 16 반경이므로 한 줄짜리 데코레이터를 둔다.

```dart
// 들린 줄은 카드가 책상에서 떠오른 모습이다 — 면·테두리·내용은 그대로 두고 그림자만 더한다.
// AppPanel의 두께(DepthBorder)는 그 아래에 그대로 있다.
Widget _liftedCard(Widget child, int index, Animation<double> animation) {
  return AnimatedBuilder(
    animation: animation,
    builder: (context, _) => Material(
      color: Colors.transparent,
      elevation: 6 * Curves.easeOut.transform(animation.value),
      shadowColor: AppPalette.edge,
      borderRadius: BorderRadius.circular(16),   // AppPanel의 모서리와 같다
      child: child,
    ),
  );
}
```

- **완료한 줄도 같다.** `AppPanel.inset`(가라앉은 면)이 들리는 모습이 "가라앉은 것이 떠오른다"로 어색하지 않은지는 11장 육안 확인 항목이다. 들렸을 때만 면을 바꾸는 분기를 만들지 않는다(어떤 줄은 다르게 들리는 목록을 만들지 않는다).
- 끌고 있는 동안 그 줄의 체크박스·삭제는 눌리지 않는다(포인터가 드래그에 잡혀 있다). 따로 막지 않는다.
- 애니메이션 줄이기 설정은 SDK가 알아서 짧게 처리한다. `AppPanel`의 눌림 애니메이션은 이미 `MediaQuery.disableAnimationsOf`를 본다.

### 4.4 끌기의 상태 — 어디에 두고 어떻게 되돌리나

`TodoListScreen`을 `ConsumerWidget` → **`ConsumerStatefulWidget`**으로 바꾸고, 끌어 놓은 결과(낙관적 순서)를 **화면 상태 하나**에 둔다.

| 안 | 판단 |
|---|---|
| `todosProvider`를 `AsyncNotifier`로 바꿔 `move()`를 두기 | 기각. 더 Riverpod답지만 **`todosProvider.overrideWith((ref) async => …)`로 가짜를 끼우는 테스트가 16곳**이라 전부 가짜 Notifier로 고쳐야 한다(참고 4번). 배포 직전 구간에 끌기와 무관한 테스트를 16개 건드리는 변경이고, 얻는 것은 "성공 직후 위젯 발행이 한 번의 재조회만큼 빠르다"뿐이다. `CLAUDE.md`("리팩토링은 요청받았을 때만")에도 어긋난다 |
| 별도 `StateProvider`에 낙관적 순서 | 기각. 순서를 들고 있는 provider가 둘이 되고, 그 둘이 어긋나는 상태를 아무도 보지 않는다 |
| **화면 상태 `List<Todo>? _dragged`** | **채택.** 서버 순서는 여전히 `todosProvider` 하나이고, 이 값은 "서버가 답할 때까지만 사는 복사본"이다. 끌기를 쓰지 않는 코드는 한 줄도 바뀌지 않는다 |

규칙 네 줄(이 네 줄이 4.6의 전부다):

1. **그리는 목록** = `_dragged ?? data`.
2. **끌어 놓으면** `planTodoMove` → `changed`가 false면 아무것도 하지 않는다. true면 `setState(_dragged = 결과)` → `repo.moveTodo(id, afterId: ...)`.
3. **성공하면** `ref.invalidate(todosProvider)`. `_dragged`는 **새 데이터가 도착할 때까지 그대로 둔다**(바로 지우면 재조회 동안 끌기 전 순서가 한 번 보였다가 다시 바뀌어, 저장에 성공했는데도 화면이 두 번 튄다). 새 데이터가 오면 리스너가 `_dragged = null`로 돌리고, 그 값은 방금 저장한 순서와 같으므로 화면은 꿈쩍하지 않는다. 그 재조회가 `MainShell`의 `ref.listen`을 지나며 **홈 위젯 캐시도 같은 순서로 발행된다**(기존 경로 그대로).
4. **실패하면** 토스트(`AppStrings.todoReorderFailed`) + 끌기 전 순서로 되돌린다. 되돌리는 방법은 **`_dragged = null`**이다 — `todosProvider`는 건드리지 않았으므로 그 값이 곧 끌기 전 순서다(오프라인에서 재조회를 시도하지 않는 이유이기도 하다. 실패한 끌기 때문에 목록이 에러 화면으로 사라지면 안 된다). **단, 그 사이 사용자가 또 끌었으면 되돌리지 않는다**: `_dragged`의 id 순서가 내가 적용했던 것과 다르면 나중 끌기가 이미 화면을 바꿨다는 뜻이라, 그 조작을 내 실패로 덮지 않고 토스트만 띄운다(나중 끌기의 성공·실패가 자기 결말을 낸다).

```dart
Future<void> _onReorder(..., List<Todo> current, int oldIndex, int newIndex) async {
  final plan = planTodoMove(current, oldIndex: oldIndex, newIndex: newIndex);
  if (!plan.changed) return;
  final before = current;                       // 끌기 전 순서(= todosProvider의 값)
  setState(() => _dragged = plan.todos);
  try {
    await ref.read(todoRepositoryProvider).moveTodo(
      plan.todos[_indexOfMoved].id, afterId: plan.afterId,
    );
    ref.invalidate(todosProvider);              // _dragged는 새 데이터가 오면 리스너가 지운다
  } catch (e) {
    debugPrint('moveTodo failed: $e');
    if (!mounted) return;
    // 그 사이 또 끌었으면 그 조작을 덮지 않는다.
    if (_sameOrder(_dragged, plan.todos)) setState(() => _dragged = null);
    _showErrorSnackBar(context, AppStrings.todoReorderFailed);
  }
  // before는 되돌림이 todosProvider의 값으로 이뤄진다는 사실을 읽는 사람에게 보이기 위한 이름이다.
}
```

- `ref.listen(todosProvider, ...)`은 `build` 안에 둔다(이 화면의 기존 `ref.watch` 옆). `next`가 **데이터**(로딩·에러 아님)일 때만 `_dragged = null`.
- **다른 조작은 함께 되돌아가지 않는다**(spec). `_dragged`는 순서만 들고 있고, 완료·수정·삭제는 지금처럼 각자 서버에 쓰고 `invalidate`한다. 순서 저장이 실패해도 그 쓰기들은 이미 서버에 있다.
- 받아들이는 틈 하나: 끌기 저장이 **아직 날아가는 중**에 체크·삭제가 `invalidate`를 일으키고 그 재조회가 끌기 커밋보다 빠르면, 화면이 한 번 옛 순서로 돌아갔다가 끌기 성공 뒤 다시 새 순서로 온다. 밀리초 단위의 경합이고 결과는 늘 서버의 진실이라 보완 장치를 만들지 않는다(spec "재시도·오프라인 큐를 만들지 않는다"와 같은 태도).
- 자동 재시도·재시도 버튼·Undo 스택을 만들지 않는다(spec "범위 밖").

### 4.5 새 할 일이 어디 생겼는지 — **맨 아래로 스크롤**

- 추가가 성공하면(`addTodo` → `invalidate`) 새 목록이 그려진 **다음 프레임에** `_scrollController.animateTo(maxScrollExtent)`로 맨 아래를 보여 준다. 새 할 일은 언제나 마지막 줄이므로 그것만으로 "여기 생겼다"가 된다.
- 다른 수단을 고르지 않은 이유: 잠깐 강조(하이라이트)는 연출 장치와 타이머가 새로 생기고, 안내 한 줄은 문구가 늘며 끌기와 무관한 자리에 설명을 더한다. 스크롤은 **새 코드가 컨트롤러 하나와 세 줄**이고 사용자가 이미 아는 동작이다.
- 목록이 화면에 다 들어가면 `maxScrollExtent`가 0이라 아무 일도 일어나지 않는다(새 줄은 이미 보인다).
- 실패는 `debugPrint`만 남긴다 — 스크롤은 관문이 아니고, 저장은 이미 끝났으며 사용자가 직접 내릴 수 있다(위젯 캐시 발행과 같은 성격이다. 반대로 **추가 자체의 실패는 지금처럼 토스트**다).
- 수정·완료·삭제·끌기 뒤에는 스크롤하지 않는다(보고 있던 자리를 흔들지 않는다).

---

## 데이터 흐름

## 5. 데이터 흐름

```
[줄을 끌어 놓음]
  줄을 꾹 눌러 끌기 → ReorderableListView.onReorderItem(oldIndex, newIndex)
    → planTodoMove(...)                        // 순수 함수: 결과 목록 + 기준 id
    → setState(_dragged = 결과)                 // 화면이 먼저 바뀐다(낙관적)
    → TodoRepository.moveTodo(id, afterId)     // rpc('move_todo') — 보통 1행, 한 트랜잭션
    ├ 성공 → ref.invalidate(todosProvider)
    │          → fetchTodos: order by position  // 순서를 만드는 유일한 자리
    │          → ① 화면 다시 그림(_dragged 해제, 같은 순서라 꿈쩍하지 않는다)
    │             ② MainShell의 ref.listen → TodoWidgetService.publish(fromTodos(...))
    │                                        → DueAlarmService.sync(...)  // 집합 불변(참고 3)
    └ 실패 → _dragged = null(= 끌기 전 순서) + 토스트 '순서를 바꾸지 못했습니다...'
```

| 사용자 동작 | 서버 쓰기 | 다시 읽기 | 순서가 바뀌는가 | 기한 알림 |
|---|---|---|---|---|
| 줄을 끌어 옮김 | `rpc move_todo` (1행) | `invalidate` | **그렇다**(사용자가 정한 자리) | 바뀌지 않는다(참고 3) |
| 할 일 추가 | `insert`(position은 **기본값**) | `invalidate` + 맨 아래로 스크롤 | 맨 아래에 새 자리 | 지금과 같다 |
| 제목·기한 수정 | `update {title, due_at}` | `invalidate` | **아니다**(자리 그대로) | 지금과 같다 |
| 완료/해제 | `update {is_done}` | `invalidate` | **아니다**(자리 그대로) | 지금과 같다 |
| 삭제 | `delete` | `invalidate` | 그 줄만 사라진다 | 지금과 같다 |
| 당겨서 새로고침·탭 복귀·앱 재시작 | 없음 | `fetchTodos` | 서버 순서를 그대로 받는다 | 지금과 같다 |
| 위젯에서 체크(home-widget 6단계가 올 때) | `update {is_done}` | 그 경로가 `fetchTodos`를 그대로 쓴다 | **아니다**(자리 그대로) | 그 단계의 몫(todo-due-date 8.8) |

**두 기기에서 동시에 바꾸면**: 마지막 쓰기가 이긴다(제목·기한의 기존 태도와 같다). 그래도 "깨진 목록"이 되지 않는 근거 — ① 자리 값은 서버가 그 순간의 실제 이웃에서 만들고 ② `unique (user_id, position)`이 동순위를 막고 ③ 한 사용자의 끌기는 행 잠금으로 직렬화된다. 실시간 동기화·충돌 안내를 만들지 않는다. 당겨 새로고침하면 서버 순서를 다시 받는다.

---

## API 계약

## 6. API 계약

### 6.1 스키마 변경

| 대상 | 내용 |
|---|---|
| `public.todos.position` | `bigint not null default (nextval('public.todos_position_seq') * 1024)` |
| `public.todos_position_seq` | 시퀀스 1개. `grant usage ... to authenticated`, `revoke all ... from public, anon` |
| `todos_user_position_key` | `unique (user_id, position) deferrable initially immediate` (목록 쿼리의 인덱스 겸용) |

### 6.2 RPC

| 이름 | 파라미터 | 반환 | 권한 | 뜻 |
|---|---|---|---|---|
| `move_todo` | `p_todo_id uuid`, `p_after_id uuid default null` | `void` | `revoke execute from public, anon` + `grant execute to authenticated`, SECURITY DEFINER + `auth.uid()` 가드 | `p_todo_id`를 `p_after_id` 바로 아래로 옮긴다. null이면 맨 위 |

예외 문구(서버): `로그인이 필요합니다.` / `할 일을 찾을 수 없습니다.` / `옮길 자리를 찾을 수 없습니다.` / `옮길 자리가 잘못됐습니다.` — **화면은 이 문구를 보여 주지 않는다.** 어느 이유든 사용자가 할 일은 같으므로(다시 끌면 된다) `AppStrings.todoReorderFailed` 하나로 말하고 원문은 `debugPrint`에만 남긴다(대결의 `judgmentErrorMessage`처럼 코드를 문구로 옮기는 표를 만들지 않는다 — 개인 투두에 그만한 갈래가 없다).

### 6.3 테이블 접근 (전부 기존 RLS로 통한다)

| 자리 | 호출 | 변경 |
|---|---|---|
| 목록 | `todos.select().eq('user_id', uid).order('position', ascending: true).order('id', ascending: true)` | **`created_at` → `position`**(그리고 `ascending: true` 명시) |
| 추가 | `todos.insert({user_id, title, due_at})` | **없음**(position은 컬럼 기본값) |
| 수정·완료·삭제 | 지금 그대로 | 없음 |

새 Edge Function·새 cron·새 테이블이 없다. `position`은 Gemini로 보내지 않고(기준 생성 호출의 입력에 투두가 들어가는 경로가 없다) AI 데이터 제공 동의와 무관하게 순서를 바꿀 수 있다.

---

## 7. 새 문구와 아이콘

> **2026-11-10 손잡이가 없어지면서 이 장의 둘이 사라졌다**(4.1 머리글):
> `AppStrings.todoReorderHandle`(= 손잡이의 `Semantics` 라벨)과 `AppIcons.dragHandle`을 **지웠다**
> (`app_icons_test`의 개수도 35 → 34로 되돌렸다). 남는 새 문구는 **`todoReorderFailed` 하나**다.
> 라벨을 지워도 스크린리더 사용자의 수단은 남는다 — `ReorderableListView`가 줄마다 붙여 주는
> "위로/아래로 이동" 시맨틱 액션이고, 그 문구는 Flutter의 ko 번역에서 온다(9장).

### 7.1 `lib/core/strings.dart`에 더하는 것 (전부)

`todoDueNotificationsOff`(64행) 바로 뒤, `battleCreate`(66행) 앞의 새 구역에 넣는다.

```dart
  // 개인 투두의 순서(todo-reorder). 사용자에게는 **"순서"**로만 말한다 — 대결의 "마감"·"판정"과
  // 섞이는 말이 아니다. 순서를 설명하는 안내 문구·빈 상태 문구를 새로 만들지 않는다(손잡이가
  // 보이면 설명이 필요 없고, 설명을 더하면 줄에 글자가 늘어난다).
  static const todoReorderHandle = '순서 바꾸기';
  static const todoReorderFailed = '순서를 바꾸지 못했습니다. 다시 시도해주세요.';
```

- ~~`todoReorderHandle`은 **화면에 글자로 보이지 않는다** — 손잡이의 `Semantics(label:)`이다. `Tooltip`을 쓰지 않는 이유: 툴팁은 길게 눌러 뜨는데 그 제스처가 끌기와 겹친다.~~ (2026-11-10 삭제 — 라벨을 붙일 요소가 없어졌다. 참고로 **삭제 버튼의 `Tooltip`은 그대로 두었고**, 그 툴팁이 긴 누르기를 가져가 "삭제 버튼 위에서 꾹 눌러도 아무 일도 없다"가 됐다)
- `todoReorderFailed`는 `saveTodoFailed`(`저장에 실패했습니다. 다시 시도해주세요.`)와 **따로 둔다**. 실패한 것이 "저장"이 아니라 "순서 바꾸기"이고, 한 화면에서 둘이 같은 말을 하면 무엇이 안 됐는지 알 수 없다.

### 7.2 아이콘

`lib/core/theme/app_icons.dart`에 한 줄. `Icons.*` 상수를 그대로 대입하는 규칙을 따른다.

```dart
  // 2026-11-10 삭제됨(손잡이가 없어졌다). 아래는 이력이다.
  /// 할 일 순서 바꾸기 손잡이(todo-reorder).
  static const dragHandle = Icons.drag_indicator_rounded;
```

- 세로로 늘어선 점 여섯 개라 "위아래로 움직인다"가 그림으로 읽힌다(`drag_handle`의 가로줄 두 개보다 세로 재배치에 맞다).
- `test/core/theme/app_icons_test.dart`가 상수 개수를 세므로 함께 고친다(8장).
- 새 색 토큰을 만들지 않는다: 아이콘은 `AppPalette.inkMuted`(삭제 아이콘과 같은 보조색), 들린 줄의 그림자는 `AppPalette.edge`.

---

## 8. 폐기 목록 — 파일·줄 단위로 확정

> **2026-11-10 손잡이 폐기로 이 장의 세 줄이 반대로 돌아갔다**(4.1 머리글):
> ① `lib/core/theme/app_icons.dart`의 `dragHandle` **추가 → 삭제**,
> ② `lib/core/strings.dart`의 문구 **2개 → 1개**(`todoReorderHandle` 삭제),
> ③ `test/core/theme/app_icons_test.dart`의 개수 **34 → 35 → 다시 34**.
> `test/widget_test.dart`의 겹침 판정은 **칸 기준 그대로**이고 손잡이 칸 단언만 빠졌으며,
> 제목 칸 하한은 **198 → 222**로 올라갔다(여백이 20dp로 돌아와 칸이 넓어졌다).

다음 단계가 **이 표만 보고** 지울 수 있게 적는다. 줄 번호는 2026-11-10 기준이다(앞 단계에서 줄이 밀리면 인용한 문장으로 찾는다).

### 8.1 코드

| 파일 | 자리 | 조치 |
|---|---|---|
| `lib/features/todo/domain/due_date_rules.dart` | 1~2행(파일 머리 주석) | `"정렬과 문구를 유닛 테스트로 고정하기 위해서다"` → `"문구를 유닛 테스트로 고정하기 위해서다"` |
| 같은 파일 | **8~33행**(`sortedForList` 문서 주석 + `sortedForList` + `compareForList`) | **전부 삭제** |
| 같은 파일 | 6행 `import '../data/todo.dart';` | **삭제**(남는 두 함수는 `DateTime`만 받는다. 남기면 `unused_import`로 analyze가 깨진다) |
| 같은 파일 | `formatDueLabel`(35~69행)·`formatDueValue`(71~88행) | **유지**(한 글자도 고치지 않는다) |
| `lib/features/todo/domain/todo_providers.dart` | 10행 `import 'due_date_rules.dart';` | **삭제** |
| 같은 파일 | 17~25행(`todosProvider`) | 주석을 갱신하고 `sortedForList(todos)` 래핑을 없앤다: <br>`/// 할 일 목록. **순서는 서버가 만든다**(order by position — todo-reorder design 2장).`<br>`/// 이 provider는 그 결과를 그대로 들고, 홈 위젯 캐시도 MainShell의 ref.listen(todosProvider)를`<br>`/// 지나므로 앱 목록과 위젯이 **같은 리스트 객체**를 본다. 위젯 체크의 백그라운드 경로는 이`<br>`/// provider를 지나지 않고 레포지토리를 직접 부르는데, 정렬이 서버에 있어 그쪽도 같은 순서를 본다.`<br>본문: `return ref.watch(todoRepositoryProvider).fetchTodos(userId);` |
| `lib/features/todo/data/todo_repository.dart` | 10~12행(`fetchTodos` 주석)과 13~20행(본문) | 1.6의 주석·본문으로 교체(`order('created_at')` → `order('position', ascending: true).order('id', ascending: true)`) |
| 같은 파일 | `moveTodo` | **추가**(1.6) |
| `lib/features/todo/data/todo_widget_payload.dart` | 88~92행(`items` 주석) | `/// 그릴 줄. **미완료만**, 앱과 같은 순서로 최대 [todoWidgetMaxItems]개.`<br>`///`<br>`/// "앱과 같은 순서"는 **사용자가 끌어 정한 순서**다(todos.position, todo-reorder design 2장).`<br>`/// 그 순서를 만드는 자리는 서버 쿼리 하나이고 [fromTodos]는 받은 순서를 보존하기만 한다.` |
| 같은 파일 | 127~128행(`fromTodos` 주석) | `"정렬은 todosProvider가 이미 했다"` → `"순서는 서버가 order by position으로 이미 정했다"` |
| `lib/features/todo/presentation/todo_list_screen.dart` | 112~184행(목록 본문), 19행(클래스 선언) | 4장으로 교체(`ConsumerStatefulWidget`, `ReorderableListView.builder`, 네 칸 `Row`, `_dragged`, 스크롤 컨트롤러). 대화상자 관련 코드(202~402행)는 **건드리지 않는다** |
| `lib/core/strings.dart` | 64행 뒤 | 7.1의 두 상수 추가 |
| `lib/core/theme/app_icons.dart` | 114행 뒤(`edit` 다음) | 7.2의 상수 추가 |

### 8.2 테스트

| 파일 | 자리 | 조치 |
|---|---|---|
| `test/features/todo/domain/due_date_rules_test.dart` | **141~224행** `group('sortedForList')` 전체 | **삭제** |
| 같은 파일 | 227~240행 `Todo _todo(...)` 헬퍼, 9행 `final created = ...`, 3행 `import '.../todo.dart';` | **삭제**(남는 두 group이 쓰지 않는다 — 남기면 `unused_element`/`unused_import`) |
| 같은 파일 | 6~7행 머리 주석 | `"목록 순서를 만드는 자리는 sortedForList 하나이고…"` → `"기한 문구 규칙(8구간 표)의 유일한 자동 검증 지점이다. 목록 순서는 이 기능이 만들지 않는다(todo-reorder로 position이 가져갔다)."` |
| 같은 파일 | `group('formatDueLabel')`·`group('formatDueValue')` | **유지**(그대로 통과해야 한다 — spec 수용 기준) |
| `test/features/todo/todo_widget_payload_test.dart` | 5행 `import '.../due_date_rules.dart';` | **삭제** |
| 같은 파일 | 29~46행(`기한이 섞여 있어도 순서를 다시 만들지 않고…`) | 테스트 이름과 본문을 고친다: `sortedForList(...)` 호출을 없애고 **손으로 적은 순서**(예: `['전화하기','장보기','책 반납']`을 기한이 섞인 채로 그 순서대로)를 그대로 넘겨 캐시에 같은 순서로 실리는지 본다. 이름: `'들어온 순서를 그대로 싣는다(순서는 서버가 정한다)'`. 주석: 정렬은 서버의 `order by position`이고 `fromTodos`는 보존만 한다 |
| `test/widget_test.dart` | 491행 `await tester.drag(find.byType(ListView), ...)` | `find.byType(ReorderableListView)`로 바꾼다. 드래그 시작점은 목록 위젯의 **가운데**(= 제목 칸)라 손잡이(왼쪽 끝 48dp)가 아니므로 **스크롤이 된다** — 손잡이를 양 끝 중 왼쪽에 둔 결정이 이 테스트를 그대로 통과시킨다 |
| 같은 파일 | 455~463행(체크박스·삭제 상자와 겹침 판정) | 판정 기준을 **칸**으로 바로잡는다: `find.byType(Checkbox)`의 사각형은 `Transform.scale` 때문에 **그려지는 상자**(약 53~64dp)라 칸보다 넓다. 히트 영역을 정하는 것은 칸이므로 `find.byKey(todoCheckCellKey)`로 48dp 이상·`titleRect.left >= 칸.right`를 본다. 삭제는 지금처럼 `find.byTooltip`(48x48) 그대로. 손잡이 칸(`todoDragHandleKey`)의 48dp 이상도 같은 자리에서 함께 본다 |
| 같은 파일 | 465행 `expect(titleRect.width, greaterThanOrEqualTo(196))` | **하한을 198로 올린다**(새 구조의 실측이 198dp다 — 196이면 2dp 깎여도 통과해 여유가 없다). 이 줄이 "제목 칸을 깎지 않았다"의 자동 검증이다 |
| `test/core/theme/app_icons_test.dart` | 41행 뒤 지도, 44~45행(`'34개 상수가…'`, `expect(icons.length, 34)`) | `'dragHandle': AppIcons.dragHandle` 추가, 34 → **35**(테스트 이름도) |

**`todosProvider`를 `overrideWith((ref) async => …)`로 끼우는 16곳은 고치지 않는다**(4.4에서 `FutureProvider`를 유지한 이유). 가짜 레포지토리가 필요한 새 테스트만 9장에서 추가한다.

### 8.3 문서 (지우지 않고 **폐기됨**을 남긴다 — 결정의 이력은 이 저장소의 방식이다)

| 파일·줄 | 조치 |
|---|---|
| `docs/specs/todo-due-date/spec.md:128` 절 제목 | `### P0. 정렬 — 기한이 있는 것이 임박한 순으로 위에` 뒤에 한 줄 덧붙인다: `> **2026-11-10 `todo-reorder`로 폐기됨.** 목록 순서는 사용자가 끌어 정한다(`todos.position`). 아래 조항 중 살아남는 것은 132행(완료 여부로 재배치하지 않는다)·133행(정렬 기준 설정을 만들지 않는다)·134행(시간이 흘러도 순서가 바뀌지 않는다 — 근거가 "기한으로 정렬하지 않는다"로 더 강해졌다)뿐이다.` |
| 같은 파일 129~131행 | 각 줄 끝에 `(todo-reorder로 폐기)` |
| 같은 파일 232행 | `"…기한 없는 할 일의 자리로 내려간다"`의 **뒷부분 폐기**: `- [ ] 기한을 지워 "기한 없음"으로 되돌릴 수 있고, 되돌린 뒤 남은 시간 표시가 사라진다. ~~기한 없는 할 일의 자리로 내려간다~~(todo-reorder로 폐기 — 기한을 지워도 자리는 그대로다)` |
| 같은 파일 268~272행 | `### 정렬 (P0)` 제목 뒤에 `> **todo-reorder로 폐기됨**(아래 네 항목). 273·274행은 유지된다.`, 269~272행에 취소선·`(폐기)` |
| 같은 파일 317행 | `"(생성순, 표시 추가 없음)"` → `"(순서 그대로 — 이제 생성순이 아니라 사용자가 정한 순서이고, 기능 적용 시점의 첫 순서는 생성순으로 채워졌다. 표시 추가 없음)"` |
| 같은 파일 47행(사용자 스토리) | 줄 끝에 `(todo-reorder로 폐기 — 손 순서가 유일한 순서가 됐다. 그 대가는 docs/specs/todo-reorder/spec.md "## 트레이드오프" 첫 항목)` |
| 같은 파일 351행(트레이드오프) | 줄 끝에 `(todo-reorder로 해소 — 기한이 자리를 만들지 않으므로 목록이 뒤집히지 않는다)` |
| `docs/specs/home-widget/spec.md:113` | 괄호 설명을 갱신: `- 그 순서는 2026-11-10 `todo-reorder`로 **사용자가 끌어 정한 순서**가 됐다(2026-11-09 `todo-due-date`의 기한 우선 정렬은 폐기). 위젯은 순서를 스스로 만들지 않고 앱이 받아 둔 순서를 그대로 받는다. `docs/specs/todo-reorder/design.md` 2장 참고` |
| `docs/specs/home-widget/spec.md:217` | 괄호를 `(2026-11-10 `todo-reorder`로 그 순서가 사용자가 정한 순서가 됐다 — `docs/specs/todo-reorder/design.md` 2장)`로 |
| `docs/specs/home-widget/design.md:124` | `items` 행의 괄호를 `(2026-11-09 todo-due-date → 2026-11-10 todo-reorder: 앱과 같은 순서 = 사용자가 끌어 정한 순서. 서버의 order by position이 그 순서를 만든다. docs/specs/todo-reorder/design.md 2장)`으로 |
| `docs/specs/home-widget/design.md:458` | 괄호를 갱신: `(2026-11-10 todo-reorder: 쿼리의 order만 position으로 바뀌었다. 레포지토리를 그대로 쓰므로 **이 백그라운드 경로도 앱과 같은 순서를 본다** — Dart 정렬이 없어져 정렬 함수를 따로 부를 일이 없다)` |
| `docs/specs/home-widget/design.md:470` | `"받은 순서 보존"` 괄호를 `(2026-11-10 todo-reorder 기준: 순서는 서버의 order by position이 만들고 페이로드는 보존만 한다)`로 |
| `docs/specs/home-widget/plan.md:93` | 같은 취지로 한 구절 갱신(`todosProvider의 sortedForList가 만든다` → `서버의 order by position이 만든다`) |
| `supabase/migrations/20261109120000_todos_due_at.sql` | **고치지 않는다**(이미 원격에 적용됐다). 그 파일의 주석이 거짓이 되는 것을 1.2의 새 마이그레이션 주석이 받아 적는다 — 두 파일을 함께 읽으면 현재 상태가 보인다 |
| `CLAUDE.md` | 이 기능으로 **고칠 줄이 없다.** 개인 투두 CRUD는 이미 범위 안이고, 로그-전용 예외 목록에 순서를 **넣지 않는다**(원칙 4). 범위·금지 조항과 충돌하는 것도 없다 |

---

## 9. 테스트 계획

유닛이 닿도록 설계가 떼어 낸 순수 함수: **`planTodoMove`** 하나다(자리 값 계산은 SQL에 있다 — 2장에서 그 대가와 보완을 적었다).

> **2026-11-10 손잡이 폐기로 아래 표의 끌기 테스트가 제스처 기준으로 바뀌었다.** 끌기는
> `kLongPressTimeout`을 넘겨 쥔 뒤 20dp씩 나눠 움직여 재현하고(쥐기 전에 움직이면 스크롤이 된다),
> 새로 고정한 것은 넷이다: ① **꾹 눌러 끌어 놓아도 수정 대화상자가 열리지 않는다**,
> ② **꾹 눌러 집었다가 제자리에 놓아도** 열리지 않는다(서버도 부르지 않는다),
> ③ **짧게 누르면 열린다**, ④ **체크박스·삭제는 짧은 탭에서 그대로 동작하고**, 그 위에서 꾹
> 누르면 체크박스에서는 줄이 집히고 삭제 버튼에서는 아무 일도 없다(실측을 고정했다).
> "손잡이 개수 == 줄 개수"는 **"줄마다 꾹 누르기 묶음이 하나"**로 바뀌었다.

| 파일 | 고정하는 것 |
|---|---|
| `test/features/todo/domain/todo_order_test.dart` (신규) | **아래로 내릴 때 newIndex가 1 큰 좌표라는 것**(3줄 목록에서 0→3이 맨 아래, 0→1은 제자리), 위로 올릴 때, 맨 위로(afterId == null), 맨 아래로(afterId == 마지막 바로 앞), 가운데로(afterId == 바로 위 줄), **제자리면 changed == false**(0→0, 0→1), 1개짜리 목록, 좌표가 범위를 벗어나면 changed == false, **다른 줄의 상대 순서가 유지된다**(5개 목록에서 하나만 옮기고 나머지 순서 비교), 받은 리스트를 제자리에서 바꾸지 않는다, 완료한 줄·기한 있는 줄도 똑같이 옮겨진다 |
| `test/features/todo/todo_reorder_test.dart` (신규, 위젯 테스트) | 가짜 `todoRepositoryProvider`로: ① **손잡이에서 끌면** 그 할 일의 `moveTodo(id, afterId: ...)`가 **한 번** 불린다(인자까지 확인), ② **손잡이 밖(제목)에서 세로로 끌면** `moveTodo`가 불리지 않는다(= 스크롤이다), ③ 저장이 실패하면 **목록이 끌기 전 순서로 돌아가고** `todoReorderFailed` 토스트가 보인다, ④ 실패해도 그 화면의 다른 쓰기(체크)가 함께 되돌아가지 않는다, ⑤ **완료한 줄에도 손잡이가 있다**(손잡이 개수 == 줄 개수) |
| `test/widget_test.dart` (갱신) | 8.2 — 칸 기준 겹침 판정, 손잡이 칸 48dp, 제목 칸 ≥196dp(= 200), 1.5배 줄 수, 스크롤 드래그 대상 |
| `test/features/todo/todo_widget_payload_test.dart` (갱신) | 8.2 — 받은 순서 보존(정렬 함수를 부르지 않는다) |
| `test/features/todo/domain/due_date_rules_test.dart` (축소) | 8.2 — 문구·서식만 남고 그대로 통과 |
| `test/features/todo/domain/due_alarm_plan_test.dart`·`due_alarm_service_test.dart` | **건드리지 않는다.** 예약 집합은 목록 순서와 무관하다(참고 3번). 이 파일이 안 바뀌는 것 자체가 "기한 알림을 건드리지 않았다"의 증거다 |

- SQL(중간값·재번호·백필·시퀀스 기본값)은 **자동 테스트가 없다**(로컬 Docker가 없다). 11장의 수동 확인 절차로 본다. `supabase/tests/*.sql` 스모크 파일을 새로 만들지 않는다 — 돌릴 환경이 없고(`recruit_browse_smoke.sql`도 수동 실행본이다) 이 기능의 SQL은 한 함수·세 분기다.
- 각 단계의 끝 조건은 `flutter analyze` 이슈 0 + `flutter test` 전부 통과다. **새 패키지가 없어 릴리스 빌드 위험이 없지만**, 마지막 단계에서 `flutter build apk --release --dart-define-from-file=env.json`을 한 번 돌려 둔다(`EXIT=$?`를 따로 찍는다 — `CLAUDE.md`).

---

## 10. 단계 분할 (커밋 단위 제안 — 확정은 plan.md)

| # | 단계 | 범위 | 끝 조건 |
|---|---|---|---|
| 1 | 끌기 좌표 순수 함수 | `lib/features/todo/domain/todo_order.dart` + `test/.../todo_order_test.dart` | 호출자 없이 테스트만 통과(선례: 기한 알림 8단계) |
| 2 | 마이그레이션 파일 | `supabase/migrations/20261110130000_todos_position.sql`(컬럼·백필·시퀀스·제약·`move_todo`) | 파일만. **원격 적용은 하지 않는다**(11장 1번) |
| 3 | 기한 정렬 폐기 + 서버 정렬 | `due_date_rules.dart`(두 함수 삭제), `todo_providers.dart`, `todo_repository.dart`(`order('position', ascending: true)`), `todo_widget_payload.dart` 주석, 테스트 삭제·갱신(8.1·8.2의 코드·테스트 칸) | `flutter test` 통과. **이 커밋 뒤에는 원격에 컬럼이 없으면 목록 조회가 실패한다** → 2·3단계 사이에 적용 시점을 잡는 것이 11장 1번의 판단 |
| 4 | 손잡이와 줄 구조(**2026-11-10에 손잡이가 빠지고 꾹 누르기로 바뀌었다** — 4.1 머리글) | `todo_list_screen.dart`의 줄을 네 칸 `Row`로, `ReorderableListView.builder`, `AppIcons.dragHandle`, `AppStrings` 두 줄, `app_icons_test`·`widget_test` 갱신 | 끌어 옮기면 화면 순서가 바뀐다(아직 서버에 쓰지 않는다면 다음 단계와 합쳐도 된다). 1.5배·360dp에서 제목 칸 ≥196 유지 |
| 5 | 저장·되돌리기 | `TodoRepository.moveTodo`, `_dragged` 상태와 네 규칙(4.4), 토스트, `test/.../todo_reorder_test.dart` | spec "저장 실패" 수용 기준 전부 |
| 6 | 새 할 일 자리 안내 | `ScrollController` + 추가 직후 맨 아래로(4.5) | 목록이 길어도 방금 적은 할 일이 보인다 |
| 7 | 문서 정합 | 8.3의 문서 11곳 | "앱과 같은 순서"를 약속한 문서·주석·테스트가 모두 **사용자 순서**로 읽힌다 |

3·4단계를 쪼갠 이유: 3단계가 끝나면 **기한 정렬이 사라진 상태로 앱이 동작한다**(순서는 서버의 `position`). 손잡이가 깨지더라도 목록은 멀쩡하므로, 화면 작업이 길어질 때 폐기 작업이 함께 막히지 않는다.

---

## 11. 오너가 손수 해야 할 일

1. **마이그레이션 원격 적용**(2단계 파일, 시점은 오너 확정대로 **구현 완료 후 기기 설치 직전**). 적용 전에 새 앱을 깔면 목록 조회·끌기가 전부 실패한다. 적용 직후 확인할 것: ① `select id, title, position from todos order by position` 결과가 **적용 전에 보던 순서(생성순)**와 같고 `position`이 1024·2048…로 채워졌는지, ② 앱에서 할 일을 하나 추가하면 `position`이 그 다음 번호로 **맨 아래**에 붙는지.
2. **육안 확인 6건**(실기기/에뮬레이터. **2026-11-10 제스처가 바뀌어 ①·④를 고쳤다**): ① **꾹 누르면 집히고**(짧게 누르면 수정, 바로 밀면 스크롤), ② 맨 위·맨 아래로 옮기기, ③ **완료한 줄**(가라앉은 면)이 들렸을 때의 모습이 어색하지 않은지(4.3), ④ 1.5배 글자에서 체크박스·삭제가 겹치거나 잘리지 않는지(손잡이는 없다), ⑤ 순서를 바꾼 뒤 **홈 위젯**의 첫 줄이 앱의 첫 줄과 같은지, ⑥ 비행기 모드에서 끌었을 때 목록이 끌기 전으로 돌아가며 토스트가 뜨는지.
3. **재번호 갈래를 한 번 강제해 보기**(자동 테스트가 닿지 않는 유일한 분기). 대시보드에서 인접한 두 할 일의 `position`을 `k`·`k+1`로 바꿔 둔 뒤 그 사이로 다른 줄을 끌어 놓고, ① 끌기가 성공하는지 ② 그 사용자의 `position`이 1024 간격으로 다시 매겨졌는지 ③ **상대 순서가 그대로인지**를 본다. 여기서 `set constraints` 한 줄이 환경에서 거부되면 1.4 주석의 두 문장 대안으로 바꾼다.
4. **개인정보처리방침·Play 데이터 보안**: 변화 없음으로 본다(순서는 사용자가 자기 할 일을 배치한 결과이고 기기 밖으로 새로 나가는 데이터가 없다). **확인만** 한다.
5. **백로그 반영**(spec "백로그로 넘길 것" 6줄)은 메인 세션의 몫이다 — 이 설계가 `TODO_BACKLOG.md`를 쓰지 않는다.

---

## 결정 기록 (2026-11-10 오너, 메인 세션)

미결 없음. 두 건 모두 **설계 권고대로 확정**됐다.

0. **(2026-11-10, 구현이 끝난 뒤) 전용 손잡이를 없애고 줄을 꾹 눌러 집는다.** 아래 1번(여백 8dp)은 그 결정에 딸린 것이어서 **함께 폐기되고 여백이 20dp로 돌아갔다.** 제목 칸은 222dp다. 근거·대가는 `spec.md`의 "P0. 끌기 제스처" 절 머리글, 구현 판단은 `plan.md`의 "2026-11-10 변경 2"에 있다.
1. ~~**할 일 목록의 좌우 여백을 20 → 8dp로 줄인다**~~ (2026-11-10 폐기 — 위 0번) (아래 1번의 (a)). 손잡이가 48dp 터치 영역을 갖고 제목 칸은 **198dp 그대로**다(구현·리뷰 실측. 이 문서가 처음에 적은 "200dp로 는다"는 `AppPanel` 테두리 2dp를 빼지 않은 계산이었다 — 4.2 참고). 할 일 탭의 카드만 다른 탭보다 화면 가장자리에 가까워지는 것을 대가로 받는다.
2. **재번호(틈 고갈) 갈래는 자동 테스트가 닿지 않는 채로 둔다**(아래 2번의 (a)). 자리 값 계산을 SQL에 두어 **낡은 좌표가 동순위를 만들 수 없게** 하는 쪽을 택했고, 대신 그 갈래를 **강제로 재현해 한 번 수동 확인**한다. 자리 값을 Dart로 옮기는 대안은 기각한다.

<details>
<summary>답을 받은 질문 (기록용)</summary>

1. **할 일 목록의 좌우 여백을 20 → 8dp로 줄이는 것을 받아들이는가?** (설계 권고: 받는다)
   spec은 "손잡이가 제목 칸 198dp를 깎지 않는다"와 "손잡이 터치 영역 최소 48dp"를 **둘 다** 요구한다. 360dp 화면에서 그 둘이 함께 성립하는 배치는 하나뿐이고, 48dp의 자리는 **카드 바깥 여백(24dp)과 `ListTile`이 쓰던 내부 여백(약 24dp)**에서만 나온다(4.2의 표). 그래서 카드가 화면 가장자리에서 8dp 떨어지게 되고, **할 일 목록만** redesign이 정한 "좌우 20"에서 벗어난다(다른 탭은 그대로다. 이 목록은 이미 `contentPadding 4`·`horizontalTitleGap 8`로 같은 이유의 예외를 갖고 있다).
   - (a) **8dp로 줄인다**(권고) — 제목 칸이 **198dp로 유지되고**(이 문서가 처음 적은 200dp는 테두리 2dp를 빼지 않은 계산이다), 손잡이가 48dp 터치 영역을 갖는다. 대가는 할 일 탭의 카드가 다른 탭보다 화면 가장자리에 가까워지는 것.
   - (b) 여백을 12dp로 두고 손잡이를 **40dp 폭**으로 한다 — 보기에는 덜 바뀌지만 spec의 "최소 48dp"와 수용 기준을 어긴다(터치 영역 40 x 60).
   - (c) 여백 20을 지키고 제목 칸을 176dp로 줄인다 — **spec이 받지 않는다고 명시한 해법**이다.
2. **재번호(틈 고갈) 갈래에 자동 테스트가 닿지 않는 것을 받아들이는가?** (설계 권고: 받는다)
   자리 값 계산을 서버에 둔 대가다(원칙 2 — 그래야 낡은 좌표가 같은 자리 값을 만들 수 없다). 로컬 Docker가 없어 SQL 테스트를 돌릴 수단이 없고, 그 갈래는 "같은 틈에 열 번 남짓 연달아 끼워 넣어야" 도는 길이라 평소 검증되지 않는다. 그래서 11장 3번에 **일부러 강제해 한 번 보는 절차**를 넣었다.
   - (a) **지금 안대로 간다**(권고) — 분기 하나가 수동 확인에 걸린다. 평소 경로(한 행 쓰기)는 매일 쓰이므로 깨지면 바로 드러난다.
   - (b) 자리 값 계산을 Dart로 옮겨 유닛 테스트한다 — 테스트는 늘지만 클라이언트가 보낸 **낡은 좌표**가 같은 자리 값을 만들 수 있어 "동순위 없음"을 서버가 보장하지 못한다(제약 위반으로 끌기가 실패하는 경로가 새로 생긴다).
   - (c) 소수 자리값(`numeric`)으로 바꿔 재번호 갈래 자체를 없앤다 — 분기가 사라지지만 값이 사람이 못 읽는 길이로 자라고(대시보드로 순서를 확인할 수 없다), 정밀도를 어떻게 다루는지가 숨은 함정이 된다(1.1).

</details>
