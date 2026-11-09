import 'package:flutter_test/flutter_test.dart';
import 'package:todododo/core/strings.dart';
import 'package:todododo/features/todo/data/todo.dart';
import 'package:todododo/features/todo/domain/due_date_rules.dart';

/// 목록 순서를 만드는 자리는 `sortedForList` 하나이고(design 원칙 3), 앱 목록과 홈 위젯 캐시가
/// 그 결과를 함께 쓴다. 그래서 순서 규칙의 유일한 자동 검증 지점이 이 파일이다.
void main() {
  final created = DateTime(2026, 11, 9, 8);

  // spec "P0. 남은 시간 문구 — 전체 규칙"의 8구간 표를 그대로 칸으로 옮긴다.
  // 투두 목록이 쓰는 유일한 문구 규칙이고, 수량 부분은 대결과 공유한다(core/remaining_time).
  group('formatDueLabel', () {
    final now = DateTime(2026, 11, 9, 12, 0, 0);
    String labelOf(Duration gap) => formatDueLabel(now.add(gap), now).label;
    bool overdueOf(Duration gap) => formatDueLabel(now.add(gap), now).overdue;

    test('1구간 — 1일 이상 남으면 일+시간', () {
      expect(
        labelOf(const Duration(days: 3, hours: 12, minutes: 30)),
        '3일 12시간 남음',
      );
      expect(labelOf(const Duration(days: 2, minutes: 40)), '2일 남음');
      expect(labelOf(const Duration(hours: 24)), '1일 남음');
    });

    test('2구간 — 1시간 이상 1일 미만이면 시간+분', () {
      expect(labelOf(const Duration(hours: 1, minutes: 42)), '1시간 42분 남음');
      expect(labelOf(const Duration(hours: 5, seconds: 30)), '5시간 남음');
      expect(labelOf(const Duration(minutes: 60)), '1시간 남음');
    });

    test('3구간 — 1분 이상 1시간 미만이면 분만(초를 병기하지 않는다)', () {
      expect(labelOf(const Duration(minutes: 43, seconds: 12)), '43분 남음');
      expect(labelOf(const Duration(seconds: 60)), '1분 남음');
    });

    test('4구간 — 1분 미만 남으면 초', () {
      expect(labelOf(const Duration(seconds: 12)), '12초 남음');
      expect(labelOf(const Duration(seconds: 1)), '1초 남음');
    });

    test('5구간 — 기한 == 지금과 지난 지 1분 미만은 방금 지남(0초 지남이 없다)', () {
      expect(formatDueLabel(now, now).label, AppStrings.todoDueJustPassed);
      expect(
        labelOf(const Duration(seconds: -30)),
        AppStrings.todoDueJustPassed,
      );
      // 1초 미만 남은 상태도 `0초 남음`을 만들지 않고 방금 지남으로 묶는다.
      expect(
        labelOf(const Duration(milliseconds: 400)),
        AppStrings.todoDueJustPassed,
      );
    });

    test('6구간 — 1분 이상 1시간 미만 지나면 분', () {
      expect(labelOf(const Duration(minutes: -7)), '7분 지남');
    });

    test('7구간 — 1시간 이상 1일 미만 지나면 시간+분', () {
      expect(labelOf(const Duration(hours: -12, minutes: -34)), '12시간 34분 지남');
      expect(labelOf(const Duration(hours: -3)), '3시간 지남');
    });

    test('8구간 — 1일 이상 지나면 일+시간', () {
      expect(labelOf(const Duration(days: -3, hours: -5)), '3일 5시간 지남');
      expect(labelOf(const Duration(days: -3)), '3일 지남');
    });

    test('한 문구에 단위가 세 개 이상 쓰이지 않는다', () {
      final labels = [
        labelOf(const Duration(days: 1, hours: 3, minutes: 20)),
        labelOf(const Duration(days: -1, hours: -3, minutes: -20)),
        labelOf(const Duration(hours: 2, minutes: 20, seconds: 20)),
      ];

      for (final label in labels) {
        final units = ['일', '시간', '분', '초'].where(label.contains).length;
        expect(units, lessThanOrEqualTo(2), reason: label);
      }
      expect(labels[0], '1일 3시간 남음');
      expect(labels[1], '1일 3시간 지남');
      expect(labels[2], '2시간 20분 남음');
    });

    // 문구와 색이 **같은 판정** 하나에서 나온다는 것을 고정한다. 화면이 지남 여부를 따로
    // 계산하면(`!dueAt.isAfter(now)` 류) 아래 경계에서 "방금 지남인데 색은 보조색"이 된다.
    test('지남 여부가 문구와 함께 나오고 경계가 어긋나지 않는다', () {
      expect(overdueOf(const Duration(seconds: 1)), isFalse);
      // 기한까지 0.4초 — 문구가 `방금 지남`이므로 색도 경고여야 한다.
      final nearly = formatDueLabel(
        now.add(const Duration(milliseconds: 400)),
        now,
      );
      expect(nearly.label, AppStrings.todoDueJustPassed);
      expect(nearly.overdue, isTrue);

      expect(formatDueLabel(now, now).overdue, isTrue);
      expect(overdueOf(const Duration(seconds: -1)), isTrue);
      expect(overdueOf(const Duration(days: -3)), isTrue);
      expect(overdueOf(const Duration(days: 3)), isFalse);
    });

    test('UTC끼리 비교해도 같은 결과다(기준만 같으면 된다)', () {
      final nowUtc = DateTime.utc(2026, 11, 9, 12);
      expect(
        formatDueLabel(
          nowUtc.add(const Duration(hours: 1, minutes: 42)),
          nowUtc,
        ).label,
        '1시간 42분 남음',
      );
    });
  });

  group('formatDueValue', () {
    test('연·월·일과 오전/오후 시:분을 모두 적는다', () {
      expect(
        formatDueValue(DateTime(2026, 11, 12, 18)),
        '2026년 11월 12일 오후 6:00',
      );
      expect(formatDueValue(DateTime(2026, 1, 2, 9, 5)), '2026년 1월 2일 오전 9:05');
    });

    test('자정과 정오를 12시로 말한다', () {
      expect(formatDueValue(DateTime(2026, 11, 12)), '2026년 11월 12일 오전 12:00');
      expect(
        formatDueValue(DateTime(2026, 11, 12, 12, 30)),
        '2026년 11월 12일 오후 12:30',
      );
    });

    test('기한의 기본 시각(23:59)이 그대로 읽힌다', () {
      expect(
        formatDueValue(DateTime(2026, 11, 12, 23, 59)),
        '2026년 11월 12일 오후 11:59',
      );
    });
  });

  group('sortedForList', () {
    test('기한이 있는 것이 이른 순으로 위, 기한 없는 것은 그 아래 생성순', () {
      final sorted = sortedForList([
        _todo('n1', createdAt: created),
        _todo('d2', dueAt: DateTime(2026, 11, 12, 18)),
        _todo('n2', createdAt: created.add(const Duration(hours: 1))),
        _todo('d1', dueAt: DateTime(2026, 11, 10, 9)),
      ]);

      expect(sorted.map((todo) => todo.id), ['d1', 'd2', 'n1', 'n2']);
    });

    test('기한을 넘긴 할 일이 맨 위에 온다', () {
      final sorted = sortedForList([
        _todo('future', dueAt: DateTime(2026, 11, 20)),
        _todo('none'),
        _todo('overdue', dueAt: DateTime(2026, 11, 1)),
      ]);

      expect(sorted.first.id, 'overdue');
      expect(sorted.last.id, 'none');
    });

    test('기한이 같으면 생성순으로 가른다', () {
      final due = DateTime(2026, 11, 12, 18);
      final sorted = sortedForList([
        _todo(
          'late',
          dueAt: due,
          createdAt: created.add(const Duration(days: 1)),
        ),
        _todo('early', dueAt: due, createdAt: created),
      ]);

      expect(sorted.map((todo) => todo.id), ['early', 'late']);
    });

    test('기한과 생성 시각까지 같으면 id로 가른다(동순위를 남기지 않는다)', () {
      final due = DateTime(2026, 11, 12, 18);
      final sorted = sortedForList([
        _todo('b', dueAt: due, createdAt: created),
        _todo('a', dueAt: due, createdAt: created),
      ]);

      expect(sorted.map((todo) => todo.id), ['a', 'b']);
    });

    // List.sort는 안정 정렬이 아니다. 같은 입력이 매번 같은 순서로 나와야 "위젯과 앱이 같은
    // 목록을 보여 준다"고 말할 수 있다(spec "기한이 같은 두 할 일의 순서가 매번 같다").
    test('같은 입력을 여러 번 정렬해도 결과가 같다', () {
      final due = DateTime(2026, 11, 12, 18);
      final todos = [
        for (var i = 0; i < 20; i++)
          _todo('id$i', dueAt: due, createdAt: created),
      ];

      final first = sortedForList(todos).map((todo) => todo.id).toList();
      for (var i = 0; i < 5; i++) {
        expect(sortedForList(todos).map((todo) => todo.id).toList(), first);
      }
    });

    test('완료 여부는 자리를 바꾸지 않는다', () {
      final sorted = sortedForList([
        _todo('none-done', createdAt: created, isDone: true),
        _todo('due', dueAt: DateTime(2026, 11, 12, 18), isDone: true),
        _todo('none', createdAt: created.add(const Duration(hours: 1))),
      ]);

      // 완료한 할 일이 아래로 내려가거나 위로 올라가지 않는다 — 기한과 생성순만 본다.
      expect(sorted.map((todo) => todo.id), ['due', 'none-done', 'none']);
    });

    test('받은 리스트를 제자리에서 바꾸지 않는다', () {
      final todos = [
        _todo('n', createdAt: created),
        _todo('d', dueAt: DateTime(2026, 11, 10)),
      ];

      sortedForList(todos);

      expect(todos.map((todo) => todo.id), ['n', 'd']);
    });
  });
}

Todo _todo(
  String id, {
  DateTime? dueAt,
  DateTime? createdAt,
  bool isDone = false,
}) {
  return Todo(
    id: id,
    title: id,
    isDone: isDone,
    createdAt: createdAt ?? DateTime(2026, 11, 9, 8),
    dueAt: dueAt,
  );
}
