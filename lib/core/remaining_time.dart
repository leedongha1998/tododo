/// 남은 시간 한 덩어리의 **수량 부분**. 대결과 개인 투두가 같은 규칙으로 말해야 같은 시각이
/// 화면마다 달라 보이지 않는다(mobile-ux M1에서 대결 상세의 지역 함수를 모았고,
/// todo-due-date에서 투두가 함께 쓰게 되어 `lib/core`로 올렸다).
///
/// `남음`·`지남` 같은 접미는 호출자가 붙인다 — 대결은 `AppStrings.battleDeadlineLeft`,
/// 투두는 `formatDueLabel`이 그 자리다.
///
/// 규칙(spec "남은 시간 문구 — 전체 규칙"):
/// - **단위 두 개까지 병기한다.** 가장 큰 단위와 그 다음 단위를 함께 말한다.
/// - **아래 단위가 0이면 생략한다**(`3일 0시간`·`5시간 0분`을 쓰지 않는다 — 0은 글자만 늘린다).
/// - 각 단위는 **내림**이다. 버려지는 것은 셋째 단위뿐이라 "실제보다 많이 짧아 보인다"는
///   문제(1시간 42분 → `1시간`)가 사라진다.
/// - **초는 1분 미만 구간에서만 쓴다.** 이 화면들은 주기적으로 다시 그리지 않아 초는 보는 순간
///   이미 낡는다. 1분 미만에서만 초가 "지금 당장"이라는 뜻을 전한다.
///
/// `Duration.zero`는 `0초`다(호출자가 "지났는지"를 먼저 가르므로 사실상 오지 않는다).
/// 음수는 호출자가 먼저 가른다.
String formatRemaining(Duration gap) {
  if (gap.inDays > 0) {
    final hours = gap.inHours - gap.inDays * 24;
    return hours > 0 ? '${gap.inDays}일 $hours시간' : '${gap.inDays}일';
  }
  if (gap.inHours > 0) {
    final minutes = gap.inMinutes - gap.inHours * 60;
    return minutes > 0 ? '${gap.inHours}시간 $minutes분' : '${gap.inHours}시간';
  }
  if (gap.inMinutes > 0) return '${gap.inMinutes}분';
  return '${gap.inSeconds}초';
}
