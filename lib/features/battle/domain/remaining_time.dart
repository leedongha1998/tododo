/// 남은 시간 한 덩어리의 서식. 대결 상세 헤더와 내 대결 목록 카드가 **같은 규칙**으로 말해야
/// 같은 시각이 화면마다 달라 보이지 않는다(mobile-ux M1에서 상세 화면의 지역 함수를 여기로 옮겼다).
///
/// 떨어지는 가장 큰 단위 하나만 말한다("1일 3시간"처럼 이어 붙이지 않는다). 목록 카드는
/// 한 줄이 짧아야 하고, 사용자가 알아야 하는 것은 "급한가"뿐이다.
String formatRemaining(Duration gap) {
  if (gap.inDays > 0) return '${gap.inDays}일';
  if (gap.inHours > 0) return '${gap.inHours}시간';
  if (gap.inMinutes > 0) return '${gap.inMinutes}분';
  return '${gap.inSeconds}초';
}
