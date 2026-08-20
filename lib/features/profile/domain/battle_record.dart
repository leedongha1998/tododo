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
}
