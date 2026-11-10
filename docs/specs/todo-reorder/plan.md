# todo-reorder 구현 계획

- 기준 문서: `docs/specs/todo-reorder/spec.md`(2026-11-10 오너 승인), `docs/specs/todo-reorder/design.md`(2026-11-10 오너 승인).
  **설계 10장의 단계 분할을 확정판으로 옮긴 것이 아래 표다.** 설계와 달라진 것은 맨 아래
  "## 설계와 다른 점"에 쌓는다(선례: `docs/specs/todo-due-date/plan.md`).
- 오너가 확정해 **다시 판단하지 않는 것**: ① 손 순서가 유일한 순서(기한 임박 순 정렬 폐기),
  ② 완료한 할 일도 끌 수 있다, ③ 기존 행 백필은 **생성순 한 줄**, ④ "기한 지난 N개" 같은 보완
  수단을 만들지 않는다, ⑤ 목록 좌우 여백 20 → 8dp + 손잡이 48dp(제목 칸 **198dp 유지** — design이
  적은 "200dp로 는다"는 `AppPanel` 테두리 2dp를 빼지 않은 계산이었다. 실측·테스트 하한 모두 198),
  ⑥ 자리 값 계산은 **SQL(RPC)**에 두고 재번호 갈래가 자동 테스트에 안 닿는 것을 받아들인다.
- 커밋은 **메인 세션이 단계별로 나눠 한다.** 이 작업에서는 작업 트리에만 변경을 남긴다
  (`git add`/`commit`/`push` 없음).
- 마이그레이션은 **파일만 만든다**(그 뒤 **2026-11-10에 메인 세션이 원격에 적용했다** —
  `supabase db push` + `supabase migration list`의 `remote: 20261110130000`으로 확인. 아래
  "오너가 해야 할 일" 1번 참고). 원격 적용(`supabase db push`·`link`)은 오너 승인 뒤
  **구현이 끝나고 기기 설치 직전에** 메인 세션이 한다(spec 결정 기록 3, 설계 11장 1번).
- 범위 밖(섹션·그룹, 하위 작업, 고정, 다중 선택 이동, Undo, 정렬 기준 전환 설정, 위젯에서
  순서 바꾸기)에 쓸 코드·추상화를 미리 만들지 않는다.
- **기한 알림은 건드리지 않는다.** `due_alarm_*`의 코드·테스트를 한 줄도 수정하지 않는 것이
  "순서가 알림에 닿지 않는다"의 증거다(설계 참고 3번, 9장).

---

## 단계 표

| # | 단계 | 변경 파일 | 끝 조건 | 테스트 |
|---|---|---|---|---|
| 1 | 끌기 좌표 순수 함수 | `lib/features/todo/domain/todo_order.dart`(신규: `planTodoMove`) | 호출자 없이 테스트만 통과(선례: 기한 알림 8단계). Flutter 의존 없음, 자리 값(`position`·1024·중간값)이라는 말이 Dart에 없다 | `test/features/todo/domain/todo_order_test.dart`(신규): 아래로/위로, 맨 위(afterId null), 맨 아래, 가운데, 제자리(0→0·0→1) `changed == false`, 1개 목록, 범위 밖 좌표, 다른 줄의 상대 순서 유지, 입력 리스트 불변, 완료·기한 있는 줄도 같게 |
| 2 | 마이그레이션 파일 | `supabase/migrations/20261110130000_todos_position.sql`(신규: 컬럼·백필·시퀀스·유일 제약·`move_todo`) | **파일만.** 원격 적용 없음. 코드 변경 없음 | 없음(로컬 Docker 없어 SQL 테스트 수단이 없다 — 설계 9장, 11장 3번의 수동 절차로 본다) |
| 3 | 기한 정렬 폐기 + 서버 정렬 | `due_date_rules.dart`(`sortedForList`·`compareForList`·`todo.dart` import 삭제, 머리 주석), `todo_providers.dart`(import·래핑 삭제, 주석 갱신), `todo_repository.dart`(`fetchTodos`가 `order('position', ascending: true).order('id', ascending: true)`, 주석 교체), `todo_widget_payload.dart` 주석 2곳, `test/features/todo/domain/due_date_rules_test.dart`(`group('sortedForList')`·헬퍼·import 삭제, 머리 주석), `test/features/todo/todo_widget_payload_test.dart`(정렬 함수 호출 제거) | `flutter test` 통과. 화면은 아직 끌 수 없지만 순서를 만드는 자리가 **서버 쿼리 한 줄**로 옮겨간다. **이 단계 뒤에는 원격에 컬럼이 없으면 목록 조회가 실패한다**(설치 전 적용이 전제) | 기존 테스트 축소·갱신. `ascending: true`는 자동 테스트가 닿지 않으므로 레포지토리 주석과 11장 수동 확인에 박는다 |
| 4 | 손잡이와 줄 구조 | `todo_list_screen.dart`(`ConsumerStatefulWidget`, `ReorderableListView.builder`, 네 칸 `Row`, `todoDragHandleKey`·`todoCheckCellKey`, `_liftedCard`), `lib/core/theme/app_icons.dart`(`dragHandle`), `lib/core/strings.dart`(문구 2개), `test/core/theme/app_icons_test.dart`(34 → 35), `test/widget_test.dart`(겹침 판정을 **칸** 기준으로, 손잡이 칸 48dp, 스크롤 드래그 대상) | 손잡이에서 끌면 화면 순서가 바뀐다(서버 쓰기는 다음 단계). 360dp·1.5배에서 제목 칸 ≥196dp(= 200), 체크·삭제·수정 제스처 보존 | `test/widget_test.dart` 갱신분 + `app_icons_test` |
| 5 | 저장·되돌리기 | `todo_repository.dart`(`moveTodo`), `todo_list_screen.dart`(`_dragged` 네 규칙·토스트·`ref.listen`), `test/features/todo/todo_input_dialog_test.dart`(가짜에 `moveTodo` 한 줄) | spec "저장 실패" 수용 기준 전부. 실패해도 같은 화면의 완료·수정·삭제가 함께 되돌아가지 않는다 | `test/features/todo/todo_reorder_test.dart`(신규): 손잡이 끌기 → `moveTodo(id, afterId:)` 한 번(인자까지), 제목에서 끌면 호출 없음(= 스크롤), 실패 시 끌기 전 순서로 복귀 + `todoReorderFailed` 토스트, 실패가 체크를 되돌리지 않음, 완료한 줄에도 손잡이 |
| 6 | 새 할 일 자리 안내 | `todo_list_screen.dart`(`ScrollController` + 추가 성공 뒤 맨 아래로) | 목록이 길어도 방금 적은 할 일이 보인다. 실패는 `debugPrint`만(스크롤은 관문이 아니다) | `test/features/todo/todo_reorder_test.dart`에 한 건(추가 뒤 목록이 맨 아래로 간다) |
| 7 | 문서 정합 | 설계 8.3의 문서 11곳(`todo-due-date/spec.md` 6곳, `home-widget/{spec,design,plan}.md` 6곳) + 이 `plan.md`의 진행 기록 | "앱과 같은 순서"를 약속한 문서·주석·테스트가 모두 **사용자 순서**로 읽힌다 | — |

각 단계 끝에 `flutter analyze`(이슈 0) + `flutter test`(전부 통과)를 돌리고, **마지막에 전체를
한 번 더 돌린 뒤 `flutter build apk --release --dart-define-from-file=env.json`까지 확인한다**
(`EXIT=$?`를 따로 찍는다 — CLAUDE.md). 새 패키지가 없어 릴리스 위험은 낮지만 확인은 한다.

3·4단계를 쪼갠 이유(설계 10장 그대로): 3단계가 끝나면 기한 정렬이 사라진 상태로 앱이 동작하므로
화면 작업이 길어져도 폐기 작업이 함께 막히지 않는다.

---

## CLAUDE.md·dev-standards와의 접점 (충돌 없음을 확인한 기록)

구현을 멈춰야 하는 충돌은 **없다.** 확인한 자리를 남긴다.

| 접점 | 결론 |
|---|---|
| "판정 로직은 클라이언트가 아니라 DB/Edge Function" | 이 기능은 대결을 읽지도 쓰지도 않는다(판정·점수·상태 전이·cron·Edge Function 변경 0). 개인 투두의 **자리 값 계산도** 클라이언트가 아니라 `move_todo`(DB)가 한다 — 규칙의 방향과 같다 |
| "테스트 없이 판정 로직 수정 금지" | 판정 로직을 수정하지 않는다. 끌기 좌표 변환(`planTodoMove`)은 순수 함수로 떼어 유닛 테스트한다(1단계) |
| "새 RPC는 `revoke execute ... from public, anon`" | `move_todo`가 지킨다(설계 1.4 그대로). 시퀀스도 `revoke all ... from public, anon` + `grant usage to authenticated` |
| "SECURITY DEFINER 첫 줄에 `auth.uid() is null` 가드" | `move_todo` 첫 문장이 그 가드다. Edge/cron 전용이 아니므로 예외에 해당하지 않는다 |
| "참가자 검사에 `not in` 금지" | 대결이 아니라 해당 없음. 소유 검사는 `where id = ? and user_id = auth.uid()` + `not found` |
| "새 테이블의 사용자 FK는 `public.profiles`" | **새 테이블이 없다.** 기존 `todos.user_id`가 `auth.users`를 가리키는 상태는 이 기능의 범위가 아니라 건드리지 않는다 |
| "RLS는 테이블 만들 때 같이" | 새 테이블이 없고, 기존 정책 4개는 `auth.uid() = user_id` 행 조건식이라 새 컬럼의 영향을 받지 않는다. 새로 필요한 권한은 시퀀스 usage 하나이고 같은 마이그레이션에 함께 적는다 |
| "스키마 변경은 마이그레이션 파일로만" | 파일 하나(2단계). 대시보드 수정 없음 |
| "에러를 삼키지 않는다" | 순서 저장 실패는 **토스트**다(설계 원칙 4). CLAUDE.md의 로그-전용 예외 목록에 순서를 **넣지 않는다** — 이 기능으로 `CLAUDE.md`를 고칠 줄이 없다. 6단계의 스크롤 실패만 `debugPrint`(위젯 캐시 발행과 같은 성격이고, 저장은 이미 끝났다) |
| "사용자 문구는 한국어·`lib/core/strings.dart`" | 새 문구 2개(`todoReorderHandle`, `todoReorderFailed`)를 거기에 모은다 |
| "새 패키지 추가 전 기존 것으로 되는지" | **새 패키지가 없다.** `ReorderableListView.builder` + `ReorderableDragStartListener`는 Flutter SDK다 |
| "새 화면 하나 = 새 커밋 하나" | 새 화면이 없다. 단계 표가 커밋 단위이고 커밋은 메인 세션이 한다 |
| iOS·i18n·미래 대비 금지 | Android 전용, 새 로케일·`.arb` 없음, 범위 밖을 위한 자리를 만들지 않는다 |
| dev-standards "`data`가 `domain`·`AppStrings`를 import하지 않는다" | `todo_repository.dart`는 `todo.dart`와 supabase만 본다. `planTodoMove`는 `domain`에 있고 `Todo`(data 모델)만 받는다 — 방향이 domain → data라 기존 구조와 같다 |
| dev-standards "RPC vs 직접 CRUD" | 추가·수정·완료·삭제는 지금처럼 직접 CRUD, **순서 이동만 RPC**다(한 번의 끌기가 한 트랜잭션이어야 하고 자리 값을 서버가 만들어야 하므로 `from().update()`로 표현할 수 없다) |
| dev-standards "테스트는 lib 구조 미러링" | `test/features/todo/domain/todo_order_test.dart`. 끌기 위젯 테스트는 선례(`todo_input_dialog_test.dart`·`todo_widget_publish_test.dart`)와 같은 자리인 `test/features/todo/todo_reorder_test.dart` |
| "같은 값을 두 곳에서 각자 판정하지 않는다"(이전 리뷰 지적) | 순서를 만드는 자리는 서버 쿼리 한 줄뿐이다. Dart 재정렬을 남기지 않고(3단계에서 삭제), 화면의 `_dragged`는 "서버가 답할 때까지 사는 복사본"이라 판정이 아니다 |
| "읽고-고쳐-쓰는 비동기 경로는 직렬화"(이전 리뷰 지적) | 끌기는 읽고-고쳐-쓰기가 아니다(기준 id 하나만 보내고 서버가 잠금 안에서 계산한다). 같은 사용자의 두 끌기는 `for update`로 직렬화된다 |

---

## 설계와 다른 점

구현하면서 설계와 달라진 것만 적는다. 단계 순서는 바꾸지 않았다(표의 1~7을 그 순서로 했다).

1. **`onReorder` → `onReorderItem`으로 바꾸고, `planTodoMove`가 off-by-one을 더 이상 보정하지
   않는다.** 설계 3장·4.1은 `onReorder`(옮길 줄을 아직 빼지 않은 좌표)를 전제로 "newIndex >
   oldIndex면 1을 뺀다"를 순수 함수에 두었다. 그런데 이 저장소의 Flutter 3.47에서 `onReorder`는
   **폐기됐고**(`deprecated_member_use` → `flutter analyze` 이슈 0이라는 끝 조건을 못 지킨다),
   후임인 `onReorderItem`은 **이미 1을 뺀 좌표**를 준다. 두 곳에서 빼면 아래로 내릴 때 한 칸 덜
   내려가므로 함수에서 보정을 걷어냈다. **그 off-by-one은 이제 SDK가 맡는다** — 대신 "두 좌표계를
   섞지 않는다"를 함수 주석과 테스트 이름에 박았다(`test/features/todo/domain/todo_order_test.dart`
   첫 두 테스트).
2. **줄의 `Row`를 `IntrinsicHeight`로 감쌌다.** 설계 4.2의 `crossAxisAlignment: stretch`는 그대로
   쓰면 **죽는다**: 목록 줄의 높이 제약이 무한(`maxHeight: infinity`)이고 `RenderFlex`는 stretch에서
   `BoxConstraints.tightFor(height: constraints.maxHeight)`를 자식에게 주기 때문이다(무한 높이 강제).
   `IntrinsicHeight`가 높이를 "가장 높은 칸의 높이"로 묶어 주어 stretch가 성립한다.
   `ConstrainedBox(minHeight: 60)`은 그 위에 그대로 있어 지금까지의 `minTileHeight 60`이 유지된다.
3. **손잡이 칸을 `ColoredBox(color: Colors.transparent)`로 덮었다.** 설계 4.2의 `SizedBox` + `Center`
   + `Icon`만으로는 **아이콘이 그려진 24dp만 잡힌다** — 히트 테스트는 그림이 있는 자리로만 내려가고
   `SizedBox`의 빈 자리는 통과시킨다. 그러면 "손잡이의 터치 영역 48dp"(spec 수용 기준)가 거짓이 된다.
   `ColoredBox`는 `HitTestBehavior.opaque`라 칸 전체가 잡힌다(새 색·새 위젯 없음, 투명이다).
4. **추가 직후 스크롤은 "한 프레임 뒤 한 번"이 아니라 "더 내려갈 곳이 없을 때까지 몇 번"이다.**
   설계 4.5는 "다음 프레임에 `animateTo(maxScrollExtent)`"였는데, 줄을 게으르게 만드는 목록에서
   **`maxScrollExtent`가 추정값**이라 한 번만 내려가면 모자란 자리에서 멈춘다(20개 목록에서 실측
   1088 vs 실제 1164 — 한 줄 남짓 모자랐고, 하필 **새로 생긴 그 줄**이 안 보인다). 새 목록을 받고
   한 프레임을 넘긴 뒤, 목표에 닿지 못했으면 최대 5번까지 다시 내려간다. 실패는 설계대로
   `debugPrint`만 남긴다.
5. **`plan.todos[_indexOfMoved].id` → `current[oldIndex].id`.** 설계 4.4 코드의 `_indexOfMoved`는
   이름만 있는 자리였다. 옮긴 할 일은 끌기 전 목록의 `oldIndex`에 있던 줄이므로 그것을 그대로 쓴다.
6. **화면의 기존 메서드에서 `(BuildContext, WidgetRef)` 인자를 뺐다.** `ConsumerWidget` →
   `ConsumerStatefulWidget`이 되어 `context`·`ref`가 멤버이기 때문이다(`context.mounted` →
   `mounted`). 동작은 한 줄도 바뀌지 않았다.
7. **칸 폭 48을 `_cellWidth` 상수 하나로 모았다.** 설계 4.2는 네 자리에 `48`을 적었다. 세 칸이
   같은 값이어야 폭 산수(제목 칸 198dp)가 성립하므로 한 자리에서 읽는다.
8. **`test/widget_test.dart`의 "기한 없는 줄에는 둘째 줄이 없다" 단언을 바꿨다**(설계 8.2에 없던
   자리다). `ListTile.subtitle`을 읽던 단언인데 줄이 네 칸 `Row`가 되어 `ListTile`이 사라졌다.
   같은 것을 "그 줄의 글자 위젯이 하나뿐"으로 본다(`ValueKey(todo.id)` 아래 `KeepWordsText` 1개).
9. **끌기 위젯 테스트의 가짜 레포지토리가 목록을 들고 있고, `todosProvider` override가 그
   `fetchTodos`를 지난다.** 설계 9장은 "가짜 `todoRepositoryProvider`"만 적었는데, `todosProvider`를
   **고정 목록**으로 끼우면 성공 경로에서 `invalidate` 뒤 화면이 늘 원래 순서로 돌아와 "끌어 옮긴
   순서가 보인다"를 볼 수 없다(서버가 순서를 안 바꾸는 가짜이기 때문이다). 그래서 가짜가 `moveTodo`에
   **"기준 바로 아래로 옮긴다"는 서버의 약속만** 흉내 낸다 — 자리 값 산수(1024·중간값·재번호)는
   흉내 내지 않는다. 그건 SQL의 몫이고 테스트가 볼 수 있는 것이 아니다(설계 9장의 그 대가는 그대로).
10. **테스트에서 손잡이를 끄는 방법**: 20dp 남짓씩 나눠 움직이고 걸음마다 프레임을 흘려 준다.
    한 번에 크게 밀면 **목록이 한 칸만 비켜 주고 끝나고**(220dp를 밀어도 한 줄), 걸음마다
    `pumpAndSettle`을 하면 **끌기 자체가 인정되지 않는다**. 둘 다 실측으로 확인해 헬퍼 주석에 적었다.
11. 설계 8.2가 지시한 **`test/widget_test.dart`의 겹침 판정 기준 교체**(그려지는 상자 → 칸)는 그대로
    했고, 그 자리에서 **손잡이 칸 48dp와 "손잡이가 체크박스 칸 왼쪽"**까지 함께 본다.
12. `CLAUDE.md`는 설계가 적은 대로 **한 줄도 고치지 않았다**(로그-전용 예외 목록에 순서를 넣지
    않는다). `supabase/migrations/20261109120000_todos_due_at.sql`도 고치지 않았다 — 새 마이그레이션
    주석이 그 파일의 낡은 서술을 받아 적는다.

### 리뷰 반영 (2026-11-10, 메인 세션 리뷰 뒤)

13. **`move_todo`의 "맨 아래로" 분기가 시퀀스를 밀어 둔다**(반드시 고칠 것으로 지적됨). 설계 1.4의
    `v_new_pos := v_after_pos + 1024;` 하나만으로는 그 행이 **새 할 일 자리와 같은 값**을 가져가
    다음 insert가 유일 제약에 걸린다 — 증상은 "맨 아래로 끌면 그 다음 할 일 추가가 실패"다.
    `perform setval('public.todos_position_seq', greatest(nextval(...), v_new_pos / 1024))`를 덧붙이고
    1.2의 근거 주석이 **두 분기(재번호/맨 아래)를 모두** 말하게 고쳤다. **아직 원격에 적용하지
    않았으므로 같은 마이그레이션 파일을 직접 고쳤다**(새 파일을 덧붙이지 않았다). `design.md` 1.5에도
    같은 내용을 적었다.
14. **`moveTodo` 호출을 `Future` 사슬로 직렬화했다**(설계 4.4에는 없던 것). 겹친 끌기에서 앞 끌기의
    재조회가 뒤 끌기의 낙관적 순서를 지워 화면이 한 번 튄다 — ① `_moveQueue`로 보낸 순서를
    사용자가 끈 순서와 같게 하고, ② 리스너가 `_pendingMoves > 0`인 동안 `_dragged`를 지우지 않게
    했다. 직전 기능(기한 알림)에서 같은 종류를 같은 방법으로 고쳤다(메모 `riverpod-async-pitfalls` 6번).
    새 테스트 2건을 넣고 **가드를 지우면 각각 실패하는 것까지 확인**했다.
15. **`Semantics(container: true)`** — 기본값이 false라 손잡이 라벨이 줄 전체 노드에 병합될 수 있었다.
16. **제목 칸은 198dp다**(설계 4.2가 적은 200dp가 아니다). 차이 2dp는 `AppPanel` 테두리 1dp × 2이고
    설계의 `344 − 144` 계산이 그걸 빼지 않았다. 수용 기준("198dp를 깎지 않는다")은 충족이므로 문서만
    고치고, `test/widget_test.dart`의 하한을 **196 → 198**로 올려 1dp만 깎여도 울게 했다.
17. `move_todo`의 잠금에 **`order by id`**를 붙였다(주석이 "같은 순서로만 잠근다"고 단정하는데 실제
    순서가 계획에 달려 있었다). `position`으로 정렬하지 않는 이유는 그 값이 이 함수가 바꾸는 값이라서다.
18. `docs/specs/todo-due-date/design.md` **2장 머리에 폐기 한 줄**을 넣었다(본문은 결정의 이력으로
    남긴다). 저장소에서 "기한이 순서를 만든다"로 읽히던 마지막 자리다.
19. `docs/manual-test-plan.md`에 **순서 바꾸기 수동 확인 10건(2-22~2-31)**을 넣었다. 13번 버그가
    드러나는 자리(**맨 아래로 끌고 나서 추가**)를 2-25로 따로 박고, 재번호 강제(2-31)에도 같은 확인을
    덧붙였다. 2-2의 기대도 "맨 위(또는 정렬 위치)" → **맨 아래**로 고쳤다.

---

## 진행 기록

2026-11-10 (developer 세션). 7단계 전부 구현. **커밋하지 않았다** — 작업 트리에만 있다.

| # | 한 일 | 검증 |
|---|---|---|
| 1 | `lib/features/todo/domain/todo_order.dart`(`planTodoMove`) + `test/features/todo/domain/todo_order_test.dart`(12건) | analyze 0, test 716 |
| 2 | `supabase/migrations/20261110130000_todos_position.sql`(컬럼·생성순 백필·시퀀스 기본값·`unique (user_id, position) deferrable`·`move_todo`) — **파일만, 원격 적용 안 함** | 코드 변경 없음 |
| 3 | `sortedForList`·`compareForList` 삭제(+`todo.dart` import), `todosProvider` 래핑·import 제거, `fetchTodos`가 `order('position', ascending: true).order('id', ascending: true)`, `todo_widget_payload.dart` 주석 2곳, `due_date_rules_test.dart`의 `group('sortedForList')`·헬퍼·import 삭제, `todo_widget_payload_test.dart`의 정렬 함수 호출 제거 | analyze 0, test 709(정렬 테스트 7건 폐기) |
| 4 | `AppIcons.dragHandle`, `AppStrings` 2개, 화면을 `ConsumerStatefulWidget` + `ReorderableListView.builder` + 네 칸 `Row`(손잡이 48/체크 48/제목/삭제 48, 좌우 여백 8), `_liftedCard`, 키 2개, `app_icons_test`(35개), `widget_test`의 칸 기준 판정·스크롤 대상 | analyze 0, test 709 |
| 5 | `TodoRepository.moveTodo`, `_dragged` 네 규칙·토스트·`ref.listen`, `todo_input_dialog_test`의 가짜에 `moveTodo`, `test/features/todo/todo_reorder_test.dart`(8건) | analyze 0, test 717 |
| 6 | 추가 성공 뒤 맨 아래로(`_showNewTodo`), 끌기 테스트에 1건 추가 | analyze 0, test 718 |
| 7 | `todo-due-date/spec.md` 6곳(절 제목·조항 3개·수정 수용 기준·정렬 수용 기준 4개·기존 동작 보존·사용자 스토리·트레이드오프), `home-widget/spec.md` 2곳, `home-widget/design.md` 3곳, `home-widget/plan.md` 1곳 | — |

**마지막 전체 확인(리뷰 반영 뒤)**: `flutter analyze` 이슈 0, `flutter test` **720개 전부 통과**
(시작 기준선 704 → 새로 31건, 폐기 7건, 갱신 4건), `flutter build apk --release
--dart-define-from-file=env.json` **종료 코드 0**(`app-release.apk` 62.2MB, `EXIT=$?`로 따로 확인).
새 패키지가 없어 네이티브 쪽 변화는 없다(KGP 경고는 `firebase_core`·`home_widget`의 기존 경고).

**기한 알림은 한 줄도 건드리지 않았다** — `due_alarm_host.dart`·`due_alarm_plan.dart`·
`due_alarm_service.dart`와 그 테스트 3개가 그대로이고 전부 통과한다(설계 9장이 말한 "안 바뀌는 것
자체가 증거"다).

### 오너가 해야 할 일 (설계 11장 그대로, 이 세션에서 하지 않은 것)

1. ~~**마이그레이션 원격 적용**~~ → **2026-11-10에 적용됐다**(메인 세션이 `supabase db push`로
   올리고 `supabase migration list`로 `remote: 20261110130000`까지 확인했다). 아래는 그때의
   확인 항목으로 남긴다: ① `select id, title, position from todos order by position`이 적용 전
   순서(= 생성순)와 같고 값이 1024·2048…인지, ② 앱에서 할 일을 추가하면 그 다음 번호로
   **맨 아래**에 붙는지. 되돌릴 때는 `move_todo` → 제약 → 기본값·시퀀스 → 컬럼 순으로 떼면 된다.
2. **육안 확인 6건**(실기기/에뮬레이터. **2026-11-10에 제스처가 바뀌어 ①·④를 고쳤다** —
   아래 "2026-11-10 변경 2" 참고): ① **꾹 누르면 집히고** 짧게 누르면 수정, 쥐지 않고 밀면 스크롤,
   ② 맨 위·맨 아래로 옮기기, ③ **완료한 줄**(가라앉은 면)이 들렸을 때의 모습, ④ 1.5배 글자에서
   체크박스·삭제가 겹치거나 잘리지 않는지(손잡이는 없다), ⑤ 순서를 바꾼 뒤 **홈 위젯**의 첫 줄이
   앱의 첫 줄과 같은지, ⑥ 비행기 모드에서 끌면 목록이 끌기 전으로 돌아가며 토스트가 뜨는지.
3. **재번호(틈 고갈) 갈래를 한 번 강제해 보기** — 자동 테스트가 닿지 않는 유일한 분기(오너 확정).
   대시보드에서 인접한 두 할 일의 `position`을 `k`·`k+1`로 바꿔 둔 뒤 그 사이로 다른 줄을 끌어
   놓고 ① 성공하는지 ② 1024 간격으로 다시 매겨졌는지 ③ **상대 순서가 그대로인지**를 본다.
   여기서 `set constraints todos_user_position_key deferred` 한 줄이 환경에 거부되면 그 갈래를
   마이그레이션 주석의 두 문장 대안(전체를 위로 비켜 둔 뒤 1024부터 다시 매기기)으로 바꾼다.
4. **개인정보처리방침·Play 데이터 보안**: 변경 없음으로 본다(순서는 사용자가 자기 할 일을 배치한
   결과이고 기기 밖으로 새로 나가는 데이터가 없다). **확인만** 하면 된다.
5. **백로그 반영**(spec "백로그로 넘길 것" 6줄)은 메인 세션의 몫이다 — `TODO_BACKLOG.md`의 새 줄은
   메인 세션이 넣었고 이 세션은 그 파일을 건드리지 않았다.
6. **커밋**은 메인 세션이 단계별로 나눈다(위 표의 1~7이 커밋 단위다).

---

## 2026-11-10 변경 2 — 끌기 시작을 **꾹 누르기**로 바꾼다 (오너가 기획을 뒤집음)

> 오너 지시 원문(2026-11-10, 메인 세션): "위치 옮기는 것도 모바일 사용자 친화적으로 꾹 누르면
> 호버되어서 이동시킬 수 있게 해. 좌측에 이동하는 아이콘은 없어도 되고"

**무엇이 뒤집혔나.** spec "P0. 끌기 제스처 — **전용 손잡이를 둔다**"는 길게 누르기를 두 가지
이유로 기각했다(① 줄 전체 누르기가 이미 수정이라 겹친다, ② 보이지 않는 제스처라 발견성이 0이고
오너 요청이 "잡을 곳이 보여야"였다). 오너가 그 판단을 뒤집었다 — **모바일 관례를 택하고
발견성을 포기한다.** 설계 4.1·4.2의 손잡이 칸과 폭 산수(좌우 여백 8dp)가 그 결정에 딸린
것이라 함께 되돌아간다. 기획 단계의 판단을 이 세션에서 다시 재지 않는다(오너 확정 사항이다).

**CLAUDE.md·dev-standards와의 충돌은 없다.** 확인한 자리: 판정 로직·대결·서버·마이그레이션을
한 줄도 건드리지 않는다(화면 제스처와 여백뿐이다), 새 패키지가 없다
(`ReorderableDelayedDragStartListener`는 Flutter SDK다), 새 문구가 늘지 않고 오히려 하나 줄며
(`todoReorderHandle` 삭제) 남는 문구는 `lib/core/strings.dart`에 그대로 있다, 에러 처리는
`todoReorderFailed` 토스트 그대로다. 멈춰야 하는 충돌이 없으므로 그대로 구현했다.

### 함께 정한 것 (메인 세션)

- **짧게 누르기 = 수정, 꾹 누르기 = 집기.** 꾹 눌러 집었다가 놓았을 때 수정 대화상자가
  **열리면 안 된다**(제스처가 겹치는 지점이라 테스트로 고정한다).
- **체크박스·삭제는 짧게 누르면 그대로 동작한다.** 그 위에서 꾹 누르면 줄이 집힌다(아래 1번).
- **좌우 여백 20dp 복구.** 8dp로 줄인 이유(손잡이 48dp 자리)가 사라졌다. 제목 칸은 그만큼
  넓어져 198dp보다 커진다 — spec의 "198dp를 깎지 않는다"는 더 넉넉하게 지켜진다.
- **완료한 할 일도 꾹 눌러 옮길 수 있다**(확정 결정 2 그대로).
- 범위 밖(Undo·다중 선택·섹션·정렬 전환·접근성 전용 UI)을 만들지 않는다.

### 작업 순서 (이 순서로 했다)

| # | 단계 | 변경 | 끝 조건 |
|---|---|---|---|
| 1 | 제스처 교체 | `todo_list_screen.dart`: 손잡이 칸 삭제, 줄 전체를 `ReorderableDelayedDragStartListener`로 감싼다, 좌우 여백 8 → 20, 네 칸 → 세 칸 | 꾹 누르면 집히고 짧게 누르면 수정이 열린다 |
| 2 | 쓰이지 않게 된 것 정리 | `AppIcons.dragHandle`, `AppStrings.todoReorderHandle`, `todoDragHandleKey` 삭제, `app_icons_test`(35 → 34) | analyze 이슈 0(미사용 상수가 남지 않는다) |
| 3 | 테스트 갱신 | `todo_reorder_test.dart`(끌기 헬퍼를 꾹 누르기로, 새 테스트 5건), `widget_test.dart`(손잡이 단언 제거·제목 칸 하한) | `flutter test` 전부 통과 |
| 4 | 문서 정합 | `spec.md`·`design.md`의 해당 조항에 폐기 표시 + 새 결정, `docs/manual-test-plan.md` 2-22~2-31 | 손잡이를 전제한 서술이 저장소에 남지 않는다 |
| 5 | 마지막 확인 | `flutter analyze`, `flutter test`, `flutter build apk --release` | 이슈 0 / 전부 통과 / 종료 코드 0 |

### 설계와 다른 점 (이번 변경분)

1. **`buildDefaultDragHandles: true`(SDK 기본 길게 누르기)를 쓰지 않고
   `ReorderableDelayedDragStartListener`로 직접 감쌌다.** 근거: SDK의 기본값은
   `Theme.of(context).platform`을 보고 갈라져 **모바일에서만** 길게 누르기이고
   데스크톱(linux/windows/macOS)에서는 **줄 오른쪽에 손잡이 아이콘을 다시 그린다**
   (`ReorderableListView._itemBuilder`). 방금 없앤 손잡이가 플랫폼에 따라 되살아나는 구조를
   남기지 않고, 끌기 입구를 코드 한 자리에서 읽게 한다. 덤으로 위젯 테스트가 플랫폼 기본값에
   매달리지 않는다.
2. **제스처가 갈리는 방식은 SDK의 제스처 경기장(arena)이 정한다 — 우리가 분기를 쓰지 않는다.**
   `DelayedMultiDragGestureRecognizer`(500ms)와 `AppPanel`의 `TapGestureRecognizer`가 같은
   경기장에 들어가, ① 빨리 떼면 탭이 이기고(수정이 열린다) ② 500ms를 넘겨 쥐면 끌기가 이겨
   탭이 **취소**되고(`onTapCancel` → 눌린 면이 돌아온다, 수정이 열리지 않는다) ③ 500ms 전에
   움직이면 둘 다 지고 `Scrollable`이 이긴다(스크롤). 체크박스·삭제는 줄보다 안쪽이라 짧은
   탭에서 먼저 이기고, 그 위에서 꾹 누르면 줄이 집힌다. 세 갈래를 테스트로 고정했다.
3. **`IntrinsicHeight`는 남긴다.** 손잡이가 사라져도 `Row(crossAxisAlignment: stretch)`가
   남아 있고(체크박스 칸이 줄 높이 전체를 히트 영역으로 갖게 하려는 것이다 — 1.5배 글자에서
   두 줄이 되는 줄에서도 가장 자주 쓰는 표적이 작아지지 않는다), stretch는 목록 줄의 무한
   높이 제약 때문에 `IntrinsicHeight` 없이는 죽는다(위 "설계와 다른 점" 2번). 걷어내면
   체크박스 칸이 48x48로 줄어든다 — 손잡이 때문이 아니라 체크박스 때문에 남긴다.
4. **제목 칸 실측 222dp**(360dp·1.5배). 산수: 카드 폭 320(= 360 − 20 − 20) − 체크 48 − 삭제 48
   − `AppPanel` 테두리 2 = **222**. `test/widget_test.dart`의 하한을 198 → **222**로 올렸다
   (spec의 요구는 198이고 24dp 여유가 생겼다 — 하한을 실측에 붙여 1dp만 깎여도 울게 한다).
5. **접근성 — 잃은 수단이 없다(SDK 소스로 확인).** 손잡이의 `Semantics` 라벨이 사라진 자리에
   **접근성 전용 UI를 만들지 않았다**(범위 밖·오너 지시). 대신 `SliverReorderableList._itemBuilder`가
   **모든 줄을** `_wrapWithSemantics`로 감싸 `CustomSemanticsAction`("맨 앞으로 / 위로 / 아래로 /
   맨 뒤로")을 붙이고, 그 액션들이 `_handleReorderItem` → **우리가 쓰는 `onReorderItem`**
   으로 들어간다(`packages/flutter/lib/src/widgets/reorderable_list.dart` 1138~1202행에서 확인).
   **수는 줄 위치에 따라 다르다 — 가운데 줄은 넷이지만 첫 줄·마지막 줄은 둘이다**(첫 줄에
   "위로"가 없는 것이 맞는 동작이다. 2·4·2를 테스트로 재서 확인했다).
   즉 스크린리더로 고른 "위로 이동"도 `planTodoMove` → `moveTodo`를 그대로 지나 **서버에 저장된다**
   (라벨만 있고 동작하지 않는 길이 아니다). 문구는 `WidgetsLocalizations`의 ko 번역에서 오고
   (앱이 `locale: ko` 고정이다) 우리가 `AppStrings`에 쓸 것이 없다. 이 액션은 **손잡이 유무와
   무관하게** 붙었으므로, 꾹 누르기로 바꿔 잃은 접근성 수단은 없다.

### 진행 기록 (이 변경분)

2026-11-10 (developer 세션 2). **표의 1~5단계를 그 순서로 했고 순서를 바꾼 곳은 없다.**
**커밋하지 않았다** — 작업 트리에만 있다(메인 세션이 나눠 커밋한다).

| # | 한 일 | 검증 |
|---|---|---|
| 1 | `todo_list_screen.dart`: 손잡이 칸 삭제, 줄을 `ReorderableDelayedDragStartListener`로 감쌈, 좌우 여백 8 → 20, 셋으로 줄어든 칸 번호 정리, 주석 갱신 | analyze 0 |
| 2 | `AppIcons.dragHandle`·`AppStrings.todoReorderHandle`·`todoDragHandleKey` 삭제, `app_icons_test` 35 → 34 | analyze 0 |
| 3 | `todo_reorder_test.dart`: 끌기 헬퍼를 꾹 누르기로(`kLongPressTimeout` 넘겨 쥔 뒤 20dp씩), 새 테스트 **5건**(끌고 놓아도 수정 안 열림 / 집었다 제자리에 놓아도 안 열림 / 짧게 누르면 열림 / 체크·삭제의 **짧은 탭** / 체크·삭제 위에서의 **꾹 누르기**), 이름·단언에서 손잡이 제거. `widget_test.dart`: 손잡이 칸 단언 제거, 제목 칸 하한 198 → **222**, 스크롤 테스트 주석 | 그 파일 16건 통과 |
| 4 | `spec.md`(절 머리글·수용 기준 4곳·트레이드오프 3곳·결정 기록 0번), `design.md`(4.1·4.2 머리글, 0장 그림, CLAUDE.md 대조 2줄, 5장 흐름, 7·8·9장 머리글, 10장 4단계, 11장 육안 확인, 결정 기록 0번), `docs/manual-test-plan.md`(2-22·2-23·2-26·2-27·2-30) | 저장소에 "손잡이가 있다"로 읽히는 서술이 남지 않았다(남은 `손잡이`는 전부 폐기 표시이거나 바텀시트 손잡이다) |
| 5 | 전체 확인 | `flutter analyze` **이슈 0**, `flutter test` **725개 전부 통과**(이 변경 전 720 → 새 테스트 5건. 손잡이 관련 단언은 지우지 않고 **제스처 기준으로 바꿨다**), `flutter build apk --release --dart-define-from-file=env.json` **종료 코드 0**(`EXIT=$?`로 따로 확인, `app-release.apk` 62.2MB) |

**실측 두 가지**(테스트로 고정): 제목 칸 **222.0dp**(하한을 223으로 올리면 실패하는 것까지 확인했다),
삭제 버튼 위에서 꾹 누르면 **끌기도 삭제도 일어나지 않는다**(툴팁이 긴 누르기를 가져간다) /
체크박스 위에서 꾹 누르면 **줄이 집히고 완료 토글은 일어나지 않는다**.

**건드리지 않은 것**: 마이그레이션(`20261110130000_todos_position.sql`)·`move_todo`·`position`·
`fetchTodos`·`moveTodo`·`planTodoMove`·`_dragged`/`_moveQueue`/`_pendingMoves`/`_sameOrder` 규칙·
기한 알림(`due_alarm_*`)·위젯 캐시. 서버는 한 줄도 바뀌지 않았다.

### 리뷰 반영 2 (2026-11-10, 꾹 누르기 변경에 대한 메인 세션 리뷰 뒤)

**반드시 고칠 것은 없었고** 셋을 넣었다. 커밋하지 않았다.

20. **체크박스 위에서 "꾹 눌렀다 움직이지 않고 떼면 아무 일도 안 난다"를 받아들이고 고정했다.**
    끌기 인식기가 탭을 가져가면서 **"느린 탭으로 완료 체크"가 사라졌다**(손잡이가 있던 때는
    600ms를 눌러도 토글됐다). 대안인 "끌기 입구를 제목 칸으로 좁히기"는 **줄을 옮기려고 왼쪽을
    잡았을 때 할 일이 완료 처리되는** 더 비싼 사고를 만들어 기각했다(메인 세션 판단). 받아들인
    동작이므로 **보이게** 했다 — `spec.md`의 "깨지면 안 되는 것" 체크박스 줄과 수용 기준에 단서,
    `docs/manual-test-plan.md`에 **2-23b** 신설, 테스트 1건 추가(집어 제자리에 놓으면 `doneCalls`가
    비어 있고 **짧게 누르면 그 자리에서 바로 토글된다**까지 같은 테스트에서 본다).
21. **접근성 액션을 자동 테스트로 고정했다**(손잡이 라벨이 없어진 뒤 **유일한** 수단이라 리스너를
    감싸는 자리나 `onReorderItem`을 손대면 조용히 깨진다). `tester.ensureSemantics()` →
    시맨틱 트리에서 `customSemanticsActionIds`를 가진 노드를 줄 순서로 모아 →
    `owner.performAction(node.id, SemanticsAction.customAction, 액션 id)` → **레포지토리 호출과
    화면 순서**를 단정한다(= 라벨 확인이 아니라 **서버 저장까지** 본다. 끌기와 같은
    `planTodoMove` → `moveTodo` 길을 지난다). 함께 잰 것: 액션 수가 **2·4·2**(첫 줄에 "위로"가
    없는 것이 맞는 동작이다 — 앞서 "모든 줄에 넷"이라고 보고한 것은 부정확했고 문서도 고쳤다).
    함정 둘을 주석에 박았다: ① `pipelineOwner`는 폐기됐으므로 주인은 아무 노드의 `owner`에서
    얻는다, ② `SemanticsHandle`을 `addTearDown`으로 치우면 **테스트 끝 검사가 먼저 돌아 실패한다**
    (본문 끝에서 직접 `dispose`).
22. **집히는 순간 햅틱 한 줄**(`onReorderStart` → `HapticFeedback.selectionClick()`, 새 패키지
    없음). 입구가 보이지 않는 제스처라 "집혔다"는 신호가 시각적 들림 하나뿐이었다.
    **관문이 아니다** — 실패는 `debugPrint`만 남기고 끌기를 막지 않는다(VS 인트로 같은 장식
    연출의 실패와 같은 성격이고, 방금 집은 줄 위로 스낵바를 띄우면 끌기를 방해한다).
    `CLAUDE.md`는 고치지 않았다 — 로그-전용 예외 목록에 새 항목을 더하지 않고, 기존 "장식 연출"
    조항의 성격으로 읽는다(근거는 `spec.md`·`design.md`의 해당 줄과 코드 주석에 적었다).
23. **사실 정정**: 마이그레이션은 **2026-11-10에 원격에 적용됐다**(메인 세션 `supabase db push`
    + `supabase migration list`의 `remote: 20261110130000`). "아직 적용 안 됨"으로 읽히던
    plan.md 두 자리(머리 규칙·"오너가 해야 할 일" 1번)를 고쳤다. 같은 자리의 ①②는 적용 직후
    확인 항목으로 남겼다.

**이 반영 뒤 전체 확인**: `flutter analyze` **이슈 0**, `flutter test` **727개 전부 통과**
(앞 단계 725 → 새 테스트 2건), `flutter build apk --release --dart-define-from-file=env.json`
**종료 코드 0**. 만들지 않은 것(메인 세션 지시): 500ms 경계값 테스트, 자동 스크롤 테스트,
끌기 입구 좁히기.
