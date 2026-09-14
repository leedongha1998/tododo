/// VS 인트로를 띄울지(design.md 4.1).
///
/// 상대가 매칭된 채 진행 중인 대결(`active`/`judging`)에서, 이 사람이 이 대결의 인트로를 아직
/// 안 봤을 때만 참이다. 모집 중(`pending`, 상대 없음)과 종결된 대결(`finished`/`disputed`/`draw`/
/// `cancelled`, ai-judge의 `voided`)에서는 뜨지 않는다.
bool shouldShowVsIntro({required String status, required bool alreadySeen}) {
  final isMatchedAndOngoing = status == 'active' || status == 'judging';
  return isMatchedAndOngoing && !alreadySeen;
}
