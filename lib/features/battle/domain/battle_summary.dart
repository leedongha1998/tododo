import '../data/battle.dart';

class BattleSummary {
  const BattleSummary({required this.battle, required this.otherPartyName});

  final Battle battle;
  final String otherPartyName;
}
