import '../data/battle.dart';
import '../data/battle_participant.dart';

/// 대결 상세 화면이 쓰는 상태 판별 모음.
///
/// 승패는 AI 판정 사실로 서버(DB 함수)가 정한다. 여기서는 서버가 기록한 `status`,
/// `winner_id`, `forfeited_by`를 화면 분기용 이름으로 옮길 뿐 승패를 계산하지 않는다.
/// 품질전도 승자가 있으므로 결과 판별은 유형과 상관없이 같다.
class BattleDetail {
  const BattleDetail({
    required this.battle,
    required this.me,
    required this.opponent,
    required this.myName,
    required this.opponentName,
  });

  final Battle battle;
  final BattleParticipant me;
  final BattleParticipant opponent;
  final String myName;
  final String opponentName;

  /// 매칭된 뒤 종결 전. 속도전은 한쪽이 먼저 통과해도 여기에 속한다(spec "진행 중" 표시).
  bool get isOngoing => battle.status == 'active' || battle.status == 'judging';

  // 매칭된 대결에서 빠져나가는 유일한 길. 끝난 대결은 서버도 거부한다.
  bool get canForfeit => isOngoing;

  bool get didIForfeit => battle.forfeitedBy != null && battle.forfeitedBy == me.userId;

  bool get didOpponentForfeit =>
      battle.forfeitedBy != null && battle.forfeitedBy == opponent.userId;

  bool get isFinished => battle.status == 'finished';

  // finished는 서버 제약상 항상 승자가 있다(속도전·품질전·포기 공통).
  bool get didIWin => isFinished && battle.winnerId == me.userId;

  bool get didILose => isFinished && battle.winnerId != null && battle.winnerId != me.userId;

  // 속도전 아무도 통과 못 함, 품질전 제출 없음·둘 다 기준 미달.
  bool get isDraw => battle.status == 'draw';

  // AI 판정이 끝내 실패해 승자 없이 끝난 대결. 점수·전적에 반영되지 않는다.
  bool get isVoided => battle.status == 'voided';
}
