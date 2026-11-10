// 개인 투두의 손 순서(todo-reorder P0)에서 **클라이언트가 하는 판단 전부**. Flutter에 의존하지
// 않는 순수 함수만 둔다 — 끌기 좌표 변환을 유닛 테스트로 고정하기 위해서다
// (design 3장, 선례: due_alarm_plan.dart).
//
// **자리 값 계산이 여기에 없다.** `position`·1024·중간값이라는 말이 Dart에 한 번도 나오지
// 않는 것이 설계 원칙 2의 모습이다 — 자리 값은 서버(`move_todo`)가 그 순간의 실제 이웃에서
// 만든다. 클라이언트가 보내는 것은 "이 할 일을 저 할 일 바로 아래에 둔다"는 기준 하나다.

import '../data/todo.dart';

/// 끌어 놓은 좌표를 **화면에 바로 적용할 목록**과 **서버에 보낼 기준 할 일**로 바꾼다.
///
/// [newIndex]는 `ReorderableListView.onReorderItem`이 주는 좌표다 — **옮길 줄을 빼고 난 뒤의
/// 자리**이므로 여기서 1을 더 빼지 않는다(빼면 아래로 내릴 때 한 칸 덜 내려간다). 옛
/// `onReorder`는 빼지 않은 좌표를 주지만 Flutter 3.47에서 폐기됐다 — 그 off-by-one을 이제 SDK가
/// 맡는다(plan.md "설계와 다른 점" 1번). **두 좌표계를 섞지 않는 것**이 이 함수의 요점이다.
///
/// [afterId]는 "옮긴 줄의 바로 위에 있는 할 일"의 id이고, 맨 위에 놓였으면 null이다. 서버는 이
/// 기준 하나만 받아 자리 값을 스스로 만든다(design 원칙 2) — 클라이언트는 자리 값을 모른다.
///
/// [changed]가 false면 제자리다. 그때는 서버를 부르지 않는다(끌었다가 같은 자리에 놓는 일은
/// 흔하고, 그걸로 쓰기와 재조회를 일으킬 이유가 없다).
///
/// **완료 여부·기한을 보지 않는다.** 모든 줄이 같은 규칙으로 옮겨진다(spec 확정 결정 2).
({List<Todo> todos, String? afterId, bool changed}) planTodoMove(
  List<Todo> todos, {
  required int oldIndex,
  required int newIndex,
}) {
  if (oldIndex < 0 || oldIndex >= todos.length) {
    return (todos: todos, afterId: null, changed: false);
  }
  final target = newIndex.clamp(0, todos.length - 1);
  if (target == oldIndex) {
    return (todos: todos, afterId: null, changed: false);
  }
  // 받은 리스트를 제자리에서 바꾸지 않는다(호출자가 "끌기 전 순서"로 되돌릴 때 쓴다).
  final moved = [...todos];
  moved.insert(target, moved.removeAt(oldIndex));
  return (
    todos: moved,
    afterId: target == 0 ? null : moved[target - 1].id,
    changed: true,
  );
}
