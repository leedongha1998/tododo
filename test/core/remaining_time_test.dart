import 'package:flutter_test/flutter_test.dart';
import 'package:todododo/core/remaining_time.dart';

/// 대결 상세 헤더·내 대결 목록 카드·개인 투두 목록이 **같은 서식**을 쓴다
/// (todo-due-date spec "남은 시간 문구 — 전체 규칙"). 한쪽만 바뀌면 같은 시각이 화면마다
/// 다르게 읽힌다.
void main() {
  group('formatRemaining', () {
    test('단위 두 개까지 병기한다', () {
      expect(formatRemaining(const Duration(days: 3, hours: 5)), '3일 5시간');
      expect(
        formatRemaining(const Duration(days: 3, hours: 12, minutes: 30)),
        '3일 12시간',
      );
      expect(formatRemaining(const Duration(hours: 5, minutes: 30)), '5시간 30분');
      expect(formatRemaining(const Duration(hours: 1, minutes: 42)), '1시간 42분');
    });

    test('아래 단위가 0이면 생략한다', () {
      expect(formatRemaining(const Duration(days: 2, minutes: 40)), '2일');
      expect(formatRemaining(const Duration(hours: 5, seconds: 30)), '5시간');
      expect(formatRemaining(const Duration(days: 3)), '3일');
    });

    test('세 번째 단위는 버린다', () {
      expect(
        formatRemaining(const Duration(days: 1, hours: 3, minutes: 59)),
        '1일 3시간',
      );
      expect(
        formatRemaining(const Duration(hours: 2, minutes: 20, seconds: 59)),
        '2시간 20분',
      );
    });

    test('초는 1분 미만 구간에서만 쓴다', () {
      expect(formatRemaining(const Duration(minutes: 43, seconds: 12)), '43분');
      expect(formatRemaining(const Duration(minutes: 1, seconds: 30)), '1분');
      expect(formatRemaining(const Duration(seconds: 30)), '30초');
      expect(formatRemaining(const Duration(seconds: 12)), '12초');
    });

    test('단위 경계에서 한 단계 아래로 내려간다', () {
      expect(formatRemaining(const Duration(hours: 24)), '1일');
      expect(
        formatRemaining(const Duration(hours: 23, minutes: 59)),
        '23시간 59분',
      );
      expect(formatRemaining(const Duration(minutes: 60)), '1시간');
      expect(formatRemaining(const Duration(minutes: 59)), '59분');
      expect(formatRemaining(const Duration(seconds: 60)), '1분');
      expect(formatRemaining(const Duration(seconds: 59)), '59초');
    });

    // 호출부가 "지나지 않았다"를 먼저 확인하므로 0은 사실상 오지 않지만,
    // 와도 빈 문자열이나 음수가 보이지 않아야 한다.
    test('0이면 0초로 말한다', () {
      expect(formatRemaining(Duration.zero), '0초');
    });
  });

  /// `nextDeadlineTick`은 "마감 줄의 글자가 다음에 달라지는 때"를 말한다. 그 약속을 **값으로
  /// 적어 두고 비교하지 않는다** — `formatRemaining`을 직접 불러 경계 앞뒤를 본다. 둘 중
  /// 하나의 분기가 바뀌어 어긋나면 적어 둔 숫자는 그대로 통과하지만 화면에서는 남은 시간이
  /// 멈춘 것처럼 보이기 때문이다.
  group('nextDeadlineTick', () {
    final now = DateTime(2026, 11, 12, 12, 0, 0);

    /// 돌려준 간격만큼 지나면 문구가 **달라지고**, 1밀리초 이르면 아직 **같다**.
    /// 그 둘이 곧 "가장 이른 순간"의 정의다.
    void expectFirstChange(Duration gap) {
      final deadline = now.add(gap);
      final delay = nextDeadlineTick(deadline, now);
      expect(delay, isNotNull, reason: '$gap에서 null');

      String labelAt(DateTime at) {
        final left = deadline.difference(at);
        // 화면이 하는 것과 같은 갈림이다 — 마감이 지나면 수량을 말하지 않고 `마감됨`이다.
        return left <= Duration.zero ? '마감됨' : formatRemaining(left);
      }

      expect(delay, greaterThan(Duration.zero), reason: '$gap에서 0 이하');
      expect(
        labelAt(now.add(delay! - const Duration(milliseconds: 1))),
        labelAt(now),
        reason: '$gap에서 $delay보다 이르게 바뀐다',
      );
      expect(
        labelAt(now.add(delay)),
        isNot(labelAt(now)),
        reason: '$gap에서 $delay이 지나도 그대로다',
      );
    }

    test('남은 구간 전부에서 "글자가 달라지는 첫 순간"을 말한다', () {
      const gaps = [
        // 일+시간 — 끝자리가 시간이라 시간 경계까지
        Duration(days: 3, hours: 12, minutes: 30),
        Duration(days: 1),
        Duration(days: 2, minutes: 40),
        // 시간+분, 분 — 분 경계까지
        Duration(hours: 5, minutes: 30, seconds: 12),
        Duration(hours: 1),
        Duration(minutes: 43, seconds: 12),
        Duration(minutes: 1),
        // 초 — 1초마다
        Duration(seconds: 12, milliseconds: 700),
        Duration(seconds: 1),
      ];
      for (final gap in gaps) {
        expectFirstChange(gap);
      }
    });

    test('마감 직전에는 마감을 **막 지난** 순간에 깨어난다', () {
      // 1초 미만 구간의 문구는 `0초`로 멈춰 있고, 다음에 달라지는 것은 수량이 아니라 마감
      // 그 자체다. 그래서 이 구간만 위 단정의 "1밀리초 이르면 아직 같다"가 성립하지 않는다 —
      // 경계가 마감이기 때문이다.
      //
      // 경계를 **넘겨서** 깨는 것이 중요하다. 경계에 정확히 앉으면 `_submitDeadlineText`는
      // `left.isNegative`가 아직 거짓이라 `0초 남음`을 그대로 보여 주는데, 그 자리에서 다음
      // 간격이 null이 되어 **영원히 `마감됨`으로 넘어가지 못한다.**
      final deadline = now.add(const Duration(milliseconds: 500));
      final delay = nextDeadlineTick(deadline, now);
      expect(delay, const Duration(milliseconds: 501));
      expect(deadline.difference(now.add(delay!)), lessThan(Duration.zero));
      // 넘긴 뒤로는 더 깰 일이 없다.
      expect(nextDeadlineTick(deadline, now.add(delay)), isNull);
    });

    test('깨어나는 잦기가 문구의 끝자리를 따라간다', () {
      // 사흘 뒤 마감은 한 시간에 한 번으로 충분하다 — 1분 주기보다도 덜 깨어난다.
      expect(
        nextDeadlineTick(now.add(const Duration(days: 3, minutes: 20)), now),
        const Duration(minutes: 20, milliseconds: 1),
      );
      expect(
        nextDeadlineTick(
          now.add(const Duration(hours: 5, minutes: 30, seconds: 12)),
          now,
        ),
        const Duration(seconds: 12, milliseconds: 1),
      );
      // 1분 미만만 초 단위로 깨어난다(1분 속도전의 마지막 1분).
      expect(
        nextDeadlineTick(now.add(const Duration(seconds: 12)), now),
        const Duration(milliseconds: 1),
      );
    });

    test('이미 지난 마감이면 null이다 — 더 바뀔 것이 없으니 타이머를 두지 않는다', () {
      expect(nextDeadlineTick(now, now), isNull);
      expect(nextDeadlineTick(now.subtract(const Duration(seconds: 1)), now), isNull);
      expect(nextDeadlineTick(now.subtract(const Duration(days: 30)), now), isNull);
    });

    test('마감이 한참 뒤여도 한 시간을 넘겨 기다리지 않는다', () {
      for (final gap in const [
        Duration(days: 400),
        Duration(days: 365, hours: 7, minutes: 59, seconds: 59),
      ]) {
        final delay = nextDeadlineTick(now.add(gap), now);
        expect(delay, isNotNull, reason: '$gap');
        expect(
          delay,
          lessThanOrEqualTo(const Duration(hours: 1, milliseconds: 1)),
          reason: '$gap',
        );
      }
    });
  });
}
