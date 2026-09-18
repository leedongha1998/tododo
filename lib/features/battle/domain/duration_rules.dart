import '../../../core/strings.dart';

/// 대결 기간(제출 창) 입력 규칙. 화면이 직접 계산·검증하지 않고 이 순수 함수만 부른다.
///
/// 서버에는 **항상 분**으로 보낸다. 범위는 DB 제약(`battles_duration_minutes_check`)과
/// Edge Function 검증(`DURATION_MINUTES_MIN`/`MAX`)과 같은 값이어야 한다 —
/// 한쪽만 바뀌면 화면을 통과한 값이 서버에서 거부된다.
const battleDurationMinMinutes = 1;
const battleDurationMaxMinutes = 10080; // 7일

/// 자주 쓰는 기간(빠른 선택). 값은 분이다.
const battleDurationQuickPicks = <int>[30, 60, 1440, 4320, 10080];

/// 직접 입력에서 고르는 단위. 서버로 보낼 때는 전부 분으로 환산한다.
enum DurationUnit {
  minutes(1, AppStrings.battleDurationUnitMinute),
  hours(60, AppStrings.battleDurationUnitHour),
  days(1440, AppStrings.battleDurationUnitDay);

  const DurationUnit(this.minutesPerUnit, this.label);

  final int minutesPerUnit;
  final String label;
}

/// 직접 입력 텍스트 + 단위 → 분. 숫자가 아니거나 비어 있으면 null(= 아직 정해지지 않았다).
///
/// 곱한 값이 int 범위를 넘지 않게 단위 환산 전에 자릿수를 본다. 어차피 범위 검증에서 걸리지만
/// 여기서 막지 않으면 "0"이나 음수가 되어 오류 문구가 엉뚱해진다.
int? durationMinutesOf(String text, DurationUnit unit) {
  final trimmed = text.trim();
  if (trimmed.isEmpty || trimmed.length > 6) return null;
  final value = int.tryParse(trimmed);
  if (value == null) return null;
  return value * unit.minutesPerUnit;
}

/// 범위 검증. 통과하면 null, 아니면 사용자에게 보여 줄 한 줄.
String? validateDurationMinutes(int? minutes) {
  if (minutes == null) return AppStrings.battleDurationRequired;
  if (minutes < battleDurationMinMinutes || minutes > battleDurationMaxMinutes) {
    return AppStrings.battleDurationOutOfRange;
  }
  return null;
}
