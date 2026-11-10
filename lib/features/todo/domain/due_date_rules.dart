// 개인 투두의 기한 규칙(todo-due-date). Flutter에 의존하지 않는 순수 함수만 둔다 —
// 문구를 유닛 테스트로 고정하기 위해서다(design 원칙 2, 선례: todo_widget_payload.dart).
//
// **목록 순서는 이 파일이 만들지 않는다.** 기한 우선 정렬(sortedForList·compareForList)은
// 2026-11-10 todo-reorder로 폐기됐다 — 순서는 사용자가 끌어 정하고 서버의 order by position이
// 만든다. 여기 남은 것은 남은 시간 문구와 기한 값 서식, 즉 **표시**뿐이다.

import '../../../core/remaining_time.dart';
import '../../../core/strings.dart';

/// 목록 줄에 쓰는 한 마디와 **그 줄이 기한을 넘겼는지**. 투두만 쓴다 — "지남"(spec 표 5~8)은
/// 투두 전용이고 대결은 마감이 지나면 기존 문구(`마감됨` 등)를 쓴다.
///
/// **문구와 색을 한 함수가 한 번에 판정한다.** 화면이 `dueAt.isAfter(now)` 같은 술어로 색을
/// 따로 고르면 경계에서 둘이 어긋난다 — 기한까지 1초 미만 남은 구간은 문구가 `방금 지남`인데
/// 색만 보조색으로 남는 식이다(spec 8구간 표 5행의 색은 경고다). 그래서 [overdue]를 돌려주고
/// 화면은 그것만 읽는다.
///
/// 두 인자 모두 **같은 기준**(둘 다 기기 시간대의 local 또는 둘 다 UTC)이면 된다 — 차이만 본다.
///
/// 경계: 기한 − 지금이 **1초 이상이면 "남음"**, 그 밖은 전부 "지남"이다(기한은 그 시각까지다).
/// 1초 미만 남은 상태를 `방금 지남`으로 묶는 이유는 `0초 남음`이라는 무의미한 문구를 만들지
/// 않기 위해서다(표 4번의 최솟값은 `1초 남음`).
///
/// "지남" 쪽에 두 번째 수량 함수가 필요하지 않은 이유: 표 6·7·8은 표 1·2·3과 수량 규칙이
/// 완전히 같다(분 / 시간+분 / 일+시간, 내림, 0 생략). 다른 점은 둘뿐이고 둘 다 이 함수가
/// 흡수한다 — ① 1분 미만은 숫자 대신 `방금 지남`이라 `formatRemaining`의 초 분기에 도달하지
/// 않는다, ② 접미가 `지남`이다.
({String label, bool overdue}) formatDueLabel(DateTime dueAt, DateTime now) {
  final gap = dueAt.difference(now);
  if (gap.inSeconds > 0) {
    return (
      label: AppStrings.todoDueRemaining(formatRemaining(gap)),
      overdue: false,
    );
  }
  final passed = -gap;
  if (passed.inMinutes < 1) {
    return (label: AppStrings.todoDueJustPassed, overdue: true);
  }
  return (
    label: AppStrings.todoDuePassed(formatRemaining(passed)),
    overdue: true,
  );
}

/// 대화상자에서 보여 주는 기한 값(`2026년 11월 12일 오후 6:00`). 인자는 **기기 시간대의
/// local DateTime**이다.
///
/// 목록 줄에는 쓰지 않는다 — 목록은 남은 시간 한 마디만 말하고, 정확한 기한은 줄을 눌러 본다
/// (spec "몇 월 며칠 몇 시인지는 목록에 쓰지 않는다"). 서식 조립은 `formatWidgetTime`과 같은
/// 모양으로 순수 함수에 둔다.
String formatDueValue(DateTime dueAtLocal) {
  final isAm = dueAtLocal.hour < 12;
  final hour12 = dueAtLocal.hour % 12 == 0 ? 12 : dueAtLocal.hour % 12;
  return AppStrings.todoDueValue(
    year: dueAtLocal.year,
    month: dueAtLocal.month,
    day: dueAtLocal.day,
    isAm: isAm,
    hour12: hour12,
    minute: dueAtLocal.minute,
  );
}
