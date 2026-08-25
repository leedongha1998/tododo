import '../data/battle.dart';
import '../data/battle_participant.dart';

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

  // 속도전: 내가 아직 완료하지 않았고 대결이 active일 때만 완료 버튼을 보여준다.
  bool get canCompleteSpeedTask => battle.status == 'active' && me.completedAt == null;

  // 속도전: 내가 이미 완료해서 상대 완료를 기다리는 중인지.
  bool get isWaitingForOpponentSpeed => battle.status == 'active' && me.completedAt != null;

  // 속도전: 종료됐고 내가 승자인지.
  bool get didIWinSpeedBattle => battle.status == 'finished' && battle.winnerId == me.userId;

  // 품질전: 내가 증거를 제출할 수 있는 상태인지(아직 제출 전 & active/judging).
  bool get canSubmitEvidence =>
      (battle.status == 'active' || battle.status == 'judging') && me.evidenceSubmittedAt == null;

  // 품질전: 상대 증거에 대해 내가 아직 승인/이의제기를 하지 않았는지.
  bool get canReviewOpponentEvidence =>
      opponent.evidenceSubmittedAt != null && opponent.decision == null;

  bool get isDisputed => battle.status == 'disputed';

  bool get isQualityFinished => battle.type == 'quality' && battle.status == 'finished';
}
