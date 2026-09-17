import '../../../core/strings.dart';

/// 종결된 대결이 **나에게** 어떤 결과였는지.
///
/// 승패는 AI 판정 사실로 서버(DB 함수)가 정한다. 이 파일은 서버가 기록한
/// `battles.status`와 `battle_participants.outcome`을 화면이 쓰는 키 하나로 옮길 뿐이며
/// 승패를 계산하지 않는다(CLAUDE.md "클라이언트에서 승패 계산" 금지).
///
/// 속도전 "완료한 패배"(`completed_loss`)는 전적에서 그냥 `패`다 — 감면은 점수에만 있고,
/// 그 점수는 서버가 `score_delta_applied`에 적어 둔 값을 그대로 보여 준다.
enum BattleResult { win, loss, draw, voided }

/// 서버 값 → 결과 키. 아직 끝나지 않았거나(모집·진행 중) 취소된 대결은 null이다.
///
/// [outcome]은 `battle_participants.outcome`(win / completed_loss / loss / forfeit / draw),
/// [winnerId]는 outcome을 아직 읽지 못한 자리에서 쓰는 갈음 값이다.
BattleResult? battleResultOf({
  required String status,
  String? outcome,
  String? winnerId,
  String? myId,
}) {
  switch (status) {
    // AI 판정이 끝내 실패한 대결. 점수·전적에 반영되지 않아 무승부와 구분한다.
    case 'voided':
      return BattleResult.voided;
    case 'draw':
      return BattleResult.draw;
    case 'finished':
      return switch (outcome) {
        'win' => BattleResult.win,
        // 완료한 패배·기준 미달 패배·포기는 전적에서 모두 "패"다.
        'completed_loss' || 'loss' || 'forfeit' => BattleResult.loss,
        'draw' => BattleResult.draw,
        // outcome을 함께 읽지 않은 자리에서는 서버가 적은 승자로 갈음한다.
        // finished는 서버 제약상 항상 승자가 있다.
        _ => winnerId != null && winnerId == myId ? BattleResult.win : BattleResult.loss,
      };
    // pending/active/judging은 아직 결과가 없고, cancelled·disputed는 전적에 넣지 않는다.
    default:
      return null;
  }
}

/// 결과 키 → 사용자에게 보이는 라벨.
String battleResultLabel(BattleResult result) {
  return switch (result) {
    BattleResult.win => AppStrings.battleRecordWin,
    BattleResult.loss => AppStrings.battleRecordLose,
    BattleResult.draw => AppStrings.battleRecordDraw,
    BattleResult.voided => AppStrings.battleRecordVoided,
  };
}
