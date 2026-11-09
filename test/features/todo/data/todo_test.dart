import 'package:flutter_test/flutter_test.dart';
import 'package:todododo/features/todo/data/todo.dart';

/// 서버 행 → 모델 변환. `due_at`은 **세 가지 모양**으로 들어온다 —
/// 키가 아예 없음(마이그레이션 적용 전 캐시·옛 응답), 명시적 null(기한 없음),
/// ISO8601 문자열(기한 있음). 셋 다 예외 없이 "기한 없음 / 기한 있음"으로만 갈려야 한다.
void main() {
  Map<String, dynamic> row({Object? dueAt = _absent}) => {
    'id': 't1',
    'title': '보고서 쓰기',
    'is_done': false,
    'created_at': '2026-11-08T00:00:00Z',
    if (dueAt != _absent) 'due_at': dueAt,
  };

  group('Todo.fromMap', () {
    test('due_at 키가 없으면 기한 없음이다', () {
      expect(Todo.fromMap(row()).dueAt, isNull);
    });

    test('due_at이 null이면 기한 없음이다', () {
      expect(Todo.fromMap(row(dueAt: null)).dueAt, isNull);
    });

    test('due_at 문자열은 UTC로 들고 다닌다', () {
      final todo = Todo.fromMap(row(dueAt: '2026-11-12T09:00:00Z'));

      expect(todo.dueAt, isNotNull);
      expect(todo.dueAt!.isUtc, isTrue);
      expect(todo.dueAt, DateTime.utc(2026, 11, 12, 9));
    });

    test('시간대 오프셋이 붙은 문자열도 같은 순간의 UTC가 된다', () {
      // 서버가 timestamptz를 오프셋 표기로 줄 수도 있다. 절대 시각이 보존되어야 한다.
      final todo = Todo.fromMap(row(dueAt: '2026-11-12T18:00:00+09:00'));

      expect(todo.dueAt!.isUtc, isTrue);
      expect(todo.dueAt, DateTime.utc(2026, 11, 12, 9));
    });

    test('기한과 무관한 나머지 필드는 그대로 읽는다', () {
      final todo = Todo.fromMap(row());

      expect(todo.id, 't1');
      expect(todo.title, '보고서 쓰기');
      expect(todo.isDone, isFalse);
      expect(todo.createdAt, DateTime.parse('2026-11-08T00:00:00Z'));
    });
  });
}

/// "키가 아예 없음"을 null과 구분하기 위한 표식.
const _absent = Object();
