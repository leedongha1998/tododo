import 'package:flutter_test/flutter_test.dart';
import 'package:todododo/core/strings.dart';
import 'package:todododo/features/battle/domain/duration_rules.dart';
import 'package:todododo/features/battle/presentation/battle_chips.dart';

void main() {
  test('직접 입력은 단위를 분으로 환산한다', () {
    expect(durationMinutesOf('1', DurationUnit.minutes), 1);
    expect(durationMinutesOf('30', DurationUnit.minutes), 30);
    expect(durationMinutesOf('2', DurationUnit.hours), 120);
    expect(durationMinutesOf('7', DurationUnit.days), 10080);
    // 앞뒤 공백은 무시한다.
    expect(durationMinutesOf('  3 ', DurationUnit.days), 4320);
  });

  test('숫자가 아니거나 비어 있으면 값이 없는 것으로 본다', () {
    expect(durationMinutesOf('', DurationUnit.minutes), isNull);
    expect(durationMinutesOf('   ', DurationUnit.hours), isNull);
    expect(durationMinutesOf('한 시간', DurationUnit.hours), isNull);
    expect(durationMinutesOf('1.5', DurationUnit.hours), isNull);
    // 자릿수가 너무 크면 단위 환산 전에 막는다(곱해서 넘치게 두지 않는다).
    expect(durationMinutesOf('1234567', DurationUnit.days), isNull);
  });

  test('범위 검증은 1분에서 10080분까지만 통과시킨다', () {
    expect(validateDurationMinutes(1), isNull);
    expect(validateDurationMinutes(30), isNull);
    expect(validateDurationMinutes(10080), isNull);

    expect(validateDurationMinutes(0), AppStrings.battleDurationOutOfRange);
    expect(validateDurationMinutes(-5), AppStrings.battleDurationOutOfRange);
    expect(validateDurationMinutes(10081), AppStrings.battleDurationOutOfRange);
    expect(validateDurationMinutes(null), AppStrings.battleDurationRequired);
  });

  test('범위 상수는 DB 제약과 같은 값이다', () {
    // 이 값이 서버(battles_duration_minutes_check, DURATION_MINUTES_MIN/MAX)와 어긋나면
    // 화면을 통과한 값이 서버에서 거부된다.
    expect(battleDurationMinMinutes, 1);
    expect(battleDurationMaxMinutes, 10080);
  });

  test('빠른 선택은 전부 허용 범위 안이다', () {
    for (final minutes in battleDurationQuickPicks) {
      expect(validateDurationMinutes(minutes), isNull, reason: '$minutes분');
    }
  });

  test('기간 라벨은 떨어지는 가장 큰 단위로 말한다', () {
    expect(battleDurationLabel(1), '1분');
    expect(battleDurationLabel(30), '30분');
    expect(battleDurationLabel(60), '1시간');
    expect(battleDurationLabel(90), '90분');
    expect(battleDurationLabel(1440), '1일');
    expect(battleDurationLabel(4320), '3일');
    expect(battleDurationLabel(10080), '7일');
  });
}
