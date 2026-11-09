// 호스트가 예약 시각을 만드는 식(todo-due-date 7단계, design 8.1의 "확인 한 줄").
//
// 이 저장소는 기기 시간대 이름을 조회하는 패키지(flutter_timezone)를 넣지 않았다. 그 결정은
// `tz.UTC`가 **`initializeTimeZones()`(tzdb 적재) 없이도** 쓸 수 있다는 사실 하나에 걸려 있다 —
// 깨지면 예약이 조용히 엉뚱한 시각에 걸리거나 던진다. 그래서 여기서 못 박는다.
//
// **식을 테스트가 다시 적지 않고 `DueAlarmHost.toScheduleTime`을 직접 부른다** — 다시 적으면
// 호스트 쪽 식이 바뀌어도 테스트가 통과한다. 플러그인 자체(실제 예약·채널)는 실기기 육안 확인
// 몫이다(design 12장 2번, `docs/manual-test-plan.md` 2-9~2-21).

import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:todododo/features/todo/data/due_alarm_host.dart';

void main() {
  test('tz.UTC는 initializeTimeZones() 없이 쓸 수 있다', () {
    // 이 테스트 파일은 어디에서도 initializeTimeZones()를 부르지 않는다.
    expect(
      () => DueAlarmHost.toScheduleTime(DateTime.utc(2026)),
      returnsNormally,
    );
    expect(tz.UTC.name, 'Etc/UTC');
  });

  test('기한을 예약 시각으로 바꿔도 같은 순간이다', () {
    final dueAt = DateTime.utc(2026, 11, 12, 9);

    final scheduled = DueAlarmHost.toScheduleTime(dueAt);

    // 울리는 순간이 기한과 같아야 한다. 표시용 시간대와 무관하게 절대 시각으로 넘긴다.
    expect(scheduled.millisecondsSinceEpoch, dueAt.millisecondsSinceEpoch);
    expect(scheduled.isUtc, isTrue);
    expect(scheduled.location, tz.UTC);
  });

  test('기기 시간대의 local 기한도 같은 순간으로 넘어간다', () {
    // 대화상자가 만드는 값은 local DateTime이고 레포지토리가 UTC로 저장한다. 어느 쪽이 와도
    // 같은 순간이어야 한다(호스트가 toUtc()를 먼저 거친다).
    final local = DateTime(2026, 11, 12, 18);

    expect(
      DueAlarmHost.toScheduleTime(local).millisecondsSinceEpoch,
      local.millisecondsSinceEpoch,
    );
    expect(
      DueAlarmHost.toScheduleTime(local),
      DueAlarmHost.toScheduleTime(local.toUtc()),
    );
  });
}
