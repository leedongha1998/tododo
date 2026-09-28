/// 대결 참가자 한 명의 진행 요약과 결과.
///
/// 이 행은 상대 참가자도 읽는다. 그래서 진행 중에 상대에게 보여도 되는 값만 담는다 —
/// 제출 시각·사진·판정 내용은 `battle_submissions`·`battle_judgments`에 있고,
/// 서버가 시점에 맞춰서만 내준다.
class BattleParticipant {
  const BattleParticipant({
    required this.battleId,
    required this.userId,
    this.hasSubmitted = false,
    this.hasJudged = false,
    this.outcome,
    this.scoreDeltaApplied,
  });

  final String battleId;
  final String userId;

  /// 증거 사진을 냈는지. 시각은 담지 않는다(속도전 승부와 교체 횟수가 새지 않게).
  final bool hasSubmitted;

  /// 판정 창에서 상대 증거를 판정했는지(판정 기한 경과로 자동 승인된 경우 포함). 내용은 담지 않는다.
  final bool hasJudged;

  /// 종결 시 서버가 기록한 결과(`win`, `completed_loss`, `loss`, `forfeit`, `draw`).
  /// 무효·취소면 null.
  final String? outcome;

  /// 점수 하한(0)을 적용한 뒤 실제로 바뀐 점수.
  final int? scoreDeltaApplied;

  factory BattleParticipant.fromMap(Map<String, dynamic> map) => BattleParticipant(
        battleId: map['battle_id'] as String,
        userId: map['user_id'] as String,
        hasSubmitted: (map['has_submitted'] as bool?) ?? false,
        hasJudged: (map['has_judged'] as bool?) ?? false,
        outcome: map['outcome'] as String?,
        scoreDeltaApplied: map['score_delta_applied'] as int?,
      );
}
