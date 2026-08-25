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

  // 속도전은 서버가 정한 winnerId로 승/패를, 품질전은 상태(finished/disputed)로 결과 라벨을 정한다.
  // CLAUDE.md 도메인 규칙: 품질전은 승자를 두지 않으므로 승/패가 아니라 완료/미결로만 표시한다.
  factory BattleRecord.fromBattle(
    Battle battle, {
    required String myId,
    required String otherPartyName,
  }) {
    final resultLabel = battle.type == 'speed'
        ? (battle.winnerId == myId ? AppStrings.battleRecordWin : AppStrings.battleRecordLose)
        : (battle.status == 'finished' ? AppStrings.battleStatusFinished : AppStrings.battleStatusDisputed);
    return BattleRecord(battle: battle, otherPartyName: otherPartyName, resultLabel: resultLabel);
  }
}
