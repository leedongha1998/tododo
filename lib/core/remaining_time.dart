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
/// - **초는 1분 미만 구간에서만 쓴다.** 1분 미만에서만 초가 "지금 당장"이라는 뜻을 전한다.
///   (2026-11-12까지는 "화면이 주기적으로 다시 그리지 않아 초는 보는 순간 낡는다"가 근거였다.
///   이제 화면은 글자가 달라지는 때에 맞춰 다시 그리지만 — `TimeTicker` — 규칙은 그대로 둔다.
///   한 시간 남은 일에 초를 병기해도 읽는 사람이 쓸 일이 없다.)
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

/// [formatRemaining]의 문구에 **보이는 가장 작은 단위**. 위 분기와 짝이다 — `3일 5시간`의
/// 끝자리는 시간, `5시간 30분`과 `43분`은 분, `12초`는 초다.
///
/// 이 값이 곧 "언제 글자가 달라지는가"를 정한다. 다시 그릴 때를 재는 쪽(`TimeTicker`에 넘기는
/// 함수들)이 모두 여기서 출발하므로, 위 분기를 고치면 이 함수도 함께 고쳐야 한다.
Duration remainingLabelUnit(Duration magnitude) {
  if (magnitude.inDays > 0) return const Duration(hours: 1);
  if (magnitude.inMinutes > 0) return const Duration(minutes: 1);
  return const Duration(seconds: 1);
}

/// [magnitude]가 [remainingLabelUnit] 칸을 넘어선 나머지(`3일 5시간 30분`이면 30분).
///
/// 줄어드는 쪽(남은 시간)은 이만큼 지나면 아래 칸으로 내려가고, 늘어나는 쪽(지난 시간)은
/// 단위에서 이것을 뺀 만큼 지나야 위 칸으로 올라간다.
Duration remainingLabelRest(Duration magnitude) => Duration(
  microseconds: magnitude.inMicroseconds % remainingLabelUnit(magnitude).inMicroseconds,
);

/// 마감까지 남은 시간을 말하는 화면이 **다음에 다시 그려야 할 때**까지의 간격.
/// 이미 지난 마감이면 null — 더 바뀔 것이 없다(대결은 `지남`을 세지 않고 `마감됨`에서 멈춘다).
///
/// 투두의 `nextDueLabelChange`와 다른 점은 그 하나다. 투두는 기한이 지나도 `N분 지남`을 계속
/// 세므로 null이 없다.
///
/// 1밀리초를 더하는 것은 경계를 **넘기기 위한** 것이다 — 나머지만큼만 기다리면 아직 같은
/// 글자인 경계에 정확히 앉는다.
///
/// 마감 직전(1초 미만)에서는 그 1밀리초가 더 중요하다. 그 구간의 문구는 `0초`로 멈춰 있고
/// 다음에 달라지는 것이 수량이 아니라 **마감 그 자체**인데, 나머지가 곧 마감까지의 거리라
/// 1밀리초를 더해야 경계를 넘는다. 경계에 정확히 앉으면 `_submitDeadlineText`가 보는
/// `left.isNegative`는 아직 거짓이라 `0초 남음`이 그대로 남고, 그 자리에서 이 함수가 null을
/// 주어 **영원히 `마감됨`으로 넘어가지 못한다.**
Duration? nextDeadlineTick(DateTime deadline, DateTime now) {
  final gap = deadline.difference(now);
  if (gap <= Duration.zero) return null;
  return remainingLabelRest(gap) + const Duration(milliseconds: 1);
}
