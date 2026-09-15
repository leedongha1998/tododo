import '../../../core/strings.dart';
import '../../battle/data/battle.dart';

class BattleRecord {
  const BattleRecord({
    required this.battle,
    required this.otherPartyName,
    required this.resultLabel,
  });

  final Battle battle;
  final String otherPartyName;
  final String resultLabel;

  /// 서버가 정한 상태와 승자를 결과 라벨로 옮긴다. 승패를 계산하지 않는다.
  ///
  /// 기록 목록은 `finished`/`draw`/`voided`만 받는다(`ProfileRepository.fetchCompletedBattles`).
  /// 품질전도 승자가 있으므로 유형과 상관없이 같은 규칙이다.
  factory BattleRecord.fromBattle(
    Battle battle, {
    required String myId,
    required String otherPartyName,
  }) {
    final resultLabel = switch (battle.status) {
      'draw' => AppStrings.battleRecordDraw,
      // AI 판정 실패. 내 기록에만 보이고 승/패/무 집계에는 들어가지 않는다.
      'voided' => AppStrings.battleRecordVoided,
      _ => battle.winnerId == myId ? AppStrings.battleRecordWin : AppStrings.battleRecordLose,
    };
    return BattleRecord(battle: battle, otherPartyName: otherPartyName, resultLabel: resultLabel);
  }
}
