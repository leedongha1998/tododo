import '../../battle/data/battle.dart';
import '../../battle/domain/battle_outcome.dart';

class BattleRecord {
  const BattleRecord({
    required this.battle,
    required this.otherPartyName,
    required this.result,
  });

  final Battle battle;
  final String otherPartyName;

  /// 서버가 정한 결과. 라벨·모양은 전부 이 값에서 나온다.
  final BattleResult result;

  String get resultLabel => battleResultLabel(result);

  /// 서버가 기록한 상태와 결과를 기록 한 줄로 옮긴다. 승패를 계산하지 않는다.
  ///
  /// [outcome]은 `battle_participants.outcome`이다. 기록 목록에 들어갈 결과가 아니면
  /// (진행 중·모집 중·취소) null을 돌려주고 목록에서 빠진다.
  static BattleRecord? fromBattle(
    Battle battle, {
    required String myId,
    required String otherPartyName,
    String? outcome,
  }) {
    final result = battleResultOf(
      status: battle.status,
      outcome: outcome,
      winnerId: battle.winnerId,
      myId: myId,
    );
    if (result == null) return null;
    return BattleRecord(battle: battle, otherPartyName: otherPartyName, result: result);
  }
}
