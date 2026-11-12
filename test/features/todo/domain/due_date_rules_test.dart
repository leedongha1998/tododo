import 'package:flutter_test/flutter_test.dart';
import 'package:todododo/core/strings.dart';
import 'package:todododo/features/todo/domain/due_date_rules.dart';

/// 기한 문구 규칙(8구간 표)의 **유일한 자동 검증 지점**이다. 목록 순서는 이 기능이 만들지
/// 않는다 — 2026-11-10 todo-reorder가 그 일을 todos.position(서버)으로 가져갔다.
void main() {
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

  /// `nextDueLabelChange`는 "다음에 글자가 달라지는 때"를 말한다. 그 약속을 **값으로 적어 두고
  /// 비교하지 않는다** — `formatDueLabel`을 직접 불러 경계 앞뒤를 본다. 둘 중 하나의 분기가
  /// 바뀌어 어긋나면(예: 초 구간이 사라지면) 적어 둔 숫자는 그대로 통과하지만 화면에서는
  /// 문구가 멈춘 것처럼 보이기 때문이다.
  group('nextDueLabelChange', () {
    final now = DateTime(2026, 11, 9, 12, 0, 0);

    /// 한 구간에서 약속이 지켜지는지: 돌려준 간격만큼 지나면 문구가 **달라지고**, 1밀리초
    /// 이르면 아직 **같다**. 이 둘이 곧 "가장 이른 순간"의 정의다.
    void expectFirstChange(Duration gap) {
      final dueAt = now.add(gap);
      final delay = nextDueLabelChange(dueAt, now);
      final before = formatDueLabel(dueAt, now).label;
      final justBefore = formatDueLabel(
        dueAt,
        now.add(delay - const Duration(milliseconds: 1)),
      ).label;
      final after = formatDueLabel(dueAt, now.add(delay)).label;

      expect(delay, greaterThan(Duration.zero), reason: '$gap에서 0 이하');
      expect(justBefore, before, reason: '$gap에서 $delay보다 이르게 바뀐다');
      expect(after, isNot(before), reason: '$gap에서 $delay이 지나도 그대로다');
    }

    test('남은 시간 — 8구간 전부에서 "글자가 달라지는 첫 순간"을 말한다', () {
      const gaps = [
        // 1구간(일+시간)
        Duration(days: 3, hours: 12, minutes: 30),
        Duration(days: 1),
        Duration(days: 2, minutes: 40),
        // 2구간(시간+분)
        Duration(hours: 5, minutes: 30),
        Duration(hours: 1),
        Duration(hours: 5, seconds: 30),
        // 3구간(분)
        Duration(minutes: 43, seconds: 12),
        Duration(minutes: 1),
        // 4구간(초)
        Duration(seconds: 12, milliseconds: 700),
        Duration(seconds: 1),
        // 5구간(방금 지남) — 기한 직전·기한·기한 직후가 모두 한 구간이다
        Duration(milliseconds: 500),
        Duration.zero,
        Duration(seconds: -30),
        // 6~8구간(지남)
        Duration(minutes: -1),
        Duration(minutes: -5, seconds: -20),
        Duration(hours: -2, minutes: -20),
        Duration(days: -1, hours: -5, minutes: -30),
      ];
      for (final gap in gaps) {
        expectFirstChange(gap);
      }
    });

    test('깨어나는 잦기가 문구의 끝자리를 따라간다(고정 주기가 아니다)', () {
      // 끝자리가 시간이면 한 시간에 한 번으로 충분하다 — 사흘 뒤 기한을 1분마다 다시 그릴
      // 이유가 없다는 것이 이 방식을 고른 이유다.
      expect(
        nextDueLabelChange(now.add(const Duration(days: 3, minutes: 20)), now),
        const Duration(minutes: 20, milliseconds: 1),
      );
      // 끝자리가 분이면 분 경계까지.
      expect(
        nextDueLabelChange(
          now.add(const Duration(hours: 5, minutes: 30, seconds: 12)),
          now,
        ),
        const Duration(seconds: 12, milliseconds: 1),
      );
      // 1분 미만만 초 단위로 깨어난다.
      expect(
        nextDueLabelChange(now.add(const Duration(seconds: 12)), now),
        const Duration(milliseconds: 1),
      );
      // 지남도 같다 — 하루를 넘긴 할 일은 한 시간에 한 번이다.
      expect(
        nextDueLabelChange(
          now.subtract(const Duration(days: 1, hours: 5, minutes: 30)),
          now,
        ),
        const Duration(minutes: 30),
      );
    });

    test('기한이 한참 뒤·한참 전이어도 한 시간을 넘겨 기다리지 않는다', () {
      // 상한이 한 시간인 것은 가장 큰 단위가 시간이기 때문이다(일+시간 표기의 끝자리).
      for (final gap in const [
        Duration(days: 400),
        Duration(days: -400),
        Duration(days: 365, hours: 7, minutes: 59, seconds: 59),
      ]) {
        final delay = nextDueLabelChange(now.add(gap), now);
        expect(delay, greaterThan(Duration.zero), reason: '$gap');
        expect(
          delay,
          lessThanOrEqualTo(const Duration(hours: 1, milliseconds: 1)),
          reason: '$gap',
        );
      }
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
}
