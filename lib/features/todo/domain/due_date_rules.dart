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

/// [formatDueLabel]이 돌려주는 한 마디가 **달라지는 가장 이른 순간**까지의 간격.
///
/// 화면은 이 값으로 타이머 하나를 건다 — 1초마다 다시 그리는 것이 아니라 **글자가 실제로
/// 바뀌는 때 딱 한 번** 깨어난다. 기한이 사흘 뒤면 한 시간에 한 번, 한 시간 뒤면 1분에 한 번,
/// 1분 미만이면 1초에 한 번이다. 비용이 문구의 해상도를 그대로 따라간다.
///
/// 규칙은 하나다: **보이는 가장 작은 단위가 한 칸 넘어가는 순간**이다. 그 단위는
/// [formatRemaining]의 분기가 정한다(1일 이상이면 시간, 1분 이상이면 분, 그 밖은 초).
/// `방금 지남`만 예외로 "지난 지 1분"이 될 때까지 통째로 유지되는 한 구간이다.
///
/// 남음은 줄고 지남은 늘기 때문에 같은 나머지를 **반대로** 쓴다 — 남음은 나머지만큼 지나면
/// 아래 칸으로 내려가고(`43분 12초`는 12초 뒤에 `42분`), 지남은 단위에서 나머지를 뺀 만큼
/// 지나야 위 칸으로 올라간다(`5분 20초 지남`은 40초 뒤에 `6분 지남`).
///
/// 돌려주는 값은 **글자가 달라지는 첫 밀리초**다. 즉 `now + 결과`의 문구는 `now`의 문구와
/// 다르고, 그보다 1밀리초라도 이르면 아직 같다. 이 한 문장이 테스트가 보는 전부다.
///
/// 남음 쪽에만 1밀리초가 붙는 이유가 그 때문이다 — 남음은 경계를 **지나야** 아래 칸으로
/// 내려가므로(`43분`은 gap이 43분 미만이 되어야 `42분`이다) 나머지만큼만 기다리면 경계에
/// 정확히 앉아 아직 같은 글자를 본다. 지남은 경계 **그 순간** 위 칸으로 올라가므로 더할 것이 없다.
///
/// 이 함수가 [formatDueLabel]·[formatRemaining]의 분기와 어긋나면 문구가 멈춘 것처럼 보인다.
/// 그래서 테스트는 값을 적어 두고 비교하지 않고 **그 함수들을 직접 불러** 경계 앞뒤를 본다.
Duration nextDueLabelChange(DateTime dueAt, DateTime now) {
  final gap = dueAt.difference(now);
  // 남음(1~4구간). 경계는 [formatDueLabel]과 같은 `inSeconds > 0`이어야 한다 — `gap > 0`으로
  // 보면 1초 미만 남은 구간을 초 분기로 잘못 세어, 실제로는 `방금 지남`인 동안 1초마다 깨어난다.
  if (gap.inSeconds > 0) {
    return remainingLabelRest(gap) + const Duration(milliseconds: 1);
  }

  // 5구간 `방금 지남`. 기한 1초 전부터 이 구간이라 passed가 음수일 수 있다 — 그래도 식은
  // 그만큼 더 기다리게 되어 맞는다(기한까지 0.5초 남았으면 60.5초 뒤에 `1분 지남`이 된다).
  final passed = -gap;
  if (passed.inMinutes < 1) return const Duration(minutes: 1) - passed;

  // 6~8구간. 수량 규칙은 1~3구간과 같고 방향만 반대다.
  return remainingLabelUnit(passed) - remainingLabelRest(passed);
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
