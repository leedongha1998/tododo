import 'package:flutter_test/flutter_test.dart';
import 'package:todododo/features/todo/data/todo.dart';
import 'package:todododo/features/todo/domain/todo_order.dart';

/// 끌기에서 클라이언트가 하는 판단의 **유일한 자동 검증 지점**이다(design 3·9장). 자리 값
/// 계산은 서버(`move_todo`)에 있어 여기서 볼 수 없고, 여기서 보는 것은 "놓인 좌표 → 결과
/// 목록 + 기준 할 일" 변환이다.
///
/// 좌표는 `ReorderableListView.onReorderItem`의 것이다 — **옮길 줄을 뺀 뒤의 자리**이고
/// 1을 더 빼면 안 된다(plan.md "설계와 다른 점" 1번).
void main() {
  group('planTodoMove', () {
    // onReorderItem이 주는 좌표는 이미 조정돼 있다. 3줄 목록에서 첫 줄을 맨 아래로 옮기면
    // newIndex가 2이고, 여기서 또 1을 빼면 한 칸 덜 내려간다(가장 흔한 버그).
    test('아래로 내릴 때 newIndex가 그대로 놓이는 자리다', () {
      final todos = _todos(['a', 'b', 'c']);

      final plan = planTodoMove(todos, oldIndex: 0, newIndex: 2);

      expect(plan.changed, isTrue);
      expect(_ids(plan.todos), ['b', 'c', 'a']);
      expect(plan.afterId, 'c');
    });

    test('아래로 한 칸 내리면 기준이 바로 아래였던 줄이다', () {
      final plan = planTodoMove(
        _todos(['a', 'b', 'c']),
        oldIndex: 0,
        newIndex: 1,
      );

      expect(_ids(plan.todos), ['b', 'a', 'c']);
      expect(plan.afterId, 'b');
    });

    test('같은 좌표에 놓으면 제자리다', () {
      final plan = planTodoMove(
        _todos(['a', 'b', 'c']),
        oldIndex: 1,
        newIndex: 1,
      );

      expect(plan.changed, isFalse);
      expect(plan.afterId, isNull);
      // 결과 목록도 받은 그대로다(화면이 헛되게 다시 그리지 않는다).
      expect(_ids(plan.todos), ['a', 'b', 'c']);
    });

    test('위로 올릴 때는 newIndex가 그대로 놓이는 자리다', () {
      final plan = planTodoMove(
        _todos(['a', 'b', 'c']),
        oldIndex: 2,
        newIndex: 1,
      );

      expect(_ids(plan.todos), ['a', 'c', 'b']);
      expect(plan.afterId, 'a');
    });

    test('맨 위로 옮기면 기준이 없다(afterId == null)', () {
      final plan = planTodoMove(
        _todos(['a', 'b', 'c']),
        oldIndex: 2,
        newIndex: 0,
      );

      expect(_ids(plan.todos), ['c', 'a', 'b']);
      expect(plan.afterId, isNull);
      expect(plan.changed, isTrue);
    });

    test('맨 아래로 옮기면 기준이 마지막이 된 줄의 바로 위 줄이다', () {
      final plan = planTodoMove(
        _todos(['a', 'b', 'c', 'd']),
        oldIndex: 1,
        newIndex: 3,
      );

      expect(_ids(plan.todos), ['a', 'c', 'd', 'b']);
      expect(plan.afterId, 'd');
    });

    test('가운데로 옮기면 기준이 바로 위 줄이다', () {
      final plan = planTodoMove(
        _todos(['a', 'b', 'c', 'd']),
        oldIndex: 3,
        newIndex: 1,
      );

      expect(_ids(plan.todos), ['a', 'd', 'b', 'c']);
      expect(plan.afterId, 'a');
    });

    // 한 번의 끌기가 다른 할 일들의 앞뒤를 흔들면 사용자는 앱이 순서를 제멋대로 만진다고
    // 읽는다(spec "P0. 순서를 어디에 두는가"의 성질 2).
    test('옮긴 줄 말고 나머지의 상대 순서가 유지된다', () {
      final plan = planTodoMove(
        _todos(['a', 'b', 'c', 'd', 'e']),
        oldIndex: 3,
        newIndex: 1,
      );

      final others = _ids(plan.todos).where((id) => id != 'd').toList();
      expect(others, ['a', 'b', 'c', 'e']);
    });

    test('한 줄짜리 목록은 어디에 놓아도 제자리다', () {
      final plan = planTodoMove(_todos(['a']), oldIndex: 0, newIndex: 1);

      expect(plan.changed, isFalse);
    });

    test('좌표가 범위를 벗어나면 목록이 깨지지 않는다', () {
      final todos = _todos(['a', 'b']);

      expect(planTodoMove(todos, oldIndex: -1, newIndex: 0).changed, isFalse);
      expect(planTodoMove(todos, oldIndex: 2, newIndex: 0).changed, isFalse);
      // newIndex가 너무 크면 맨 아래로 clamp된다(던지지도, 줄을 잃지도 않는다).
      final big = planTodoMove(todos, oldIndex: 0, newIndex: 99);
      expect(_ids(big.todos), ['b', 'a']);
      expect(big.afterId, 'b');
    });

    test('받은 리스트를 제자리에서 바꾸지 않는다', () {
      final todos = _todos(['a', 'b', 'c']);

      planTodoMove(todos, oldIndex: 0, newIndex: 2);

      expect(_ids(todos), ['a', 'b', 'c']);
    });

    // 완료한 줄도 기한이 있는 줄도 같은 규칙으로 옮겨진다(spec 확정 결정 2 — 어떤 줄은
    // 잡히고 어떤 줄은 안 잡히는 목록을 만들지 않는다).
    test('완료·기한 여부가 결과를 바꾸지 않는다', () {
      final todos = [
        _todo('done', isDone: true),
        _todo('due', dueAt: DateTime.utc(2026, 11, 12, 9)),
        _todo('plain'),
      ];

      final plan = planTodoMove(todos, oldIndex: 0, newIndex: 2);

      expect(_ids(plan.todos), ['due', 'plain', 'done']);
      expect(plan.afterId, 'plain');
    });
  });
}

List<Todo> _todos(List<String> ids) => ids.map((id) => _todo(id)).toList();

List<String> _ids(List<Todo> todos) => todos.map((todo) => todo.id).toList();

Todo _todo(String id, {bool isDone = false, DateTime? dueAt}) => Todo(
  id: id,
  title: id,
  isDone: isDone,
  createdAt: DateTime.utc(2026, 11, 10, 8),
  dueAt: dueAt,
);
