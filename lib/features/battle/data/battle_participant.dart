/// 대결 참가자 한 명의 진행 요약과 결과.
///
/// 이 행은 진행 중에도 상대에게 보이는 값만 담는다(정책 "participants can view their
/// battle progress"가 행 단위라 user_id로 좁히지 않고 양쪽 다 전부 읽는다). 사진 경로와
/// 판정 사유·판정 내용은 `battle_submissions`·`battle_judgments`에 있고, 서버가 시점에 따라
/// 가린다 — 이 테이블에 컬럼을 더하면 상대에게 자동으로 공개된다.
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

  /// 이 사람이 증거를 제출했는지. 시각·사진·통과 여부는 담지 않는다.
  final bool hasSubmitted;

  /// 이 사람이 판정(자동 승인 포함)을 마쳤는지. 무엇으로 판정했는지는 담지 않는다.
  final bool hasJudged;

  /// 종결 시 서버가 기록한 결과(`win`, `completed_loss`, `loss`, `forfeit`, `draw`).
  /// 무효·취소면 null.
  final String? outcome;

  /// 점수 하한(0)을 적용한 뒤 실제로 바뀐 점수.
  final int? scoreDeltaApplied;

  factory BattleParticipant.fromMap(Map<String, dynamic> map) => BattleParticipant(
        battleId: map['battle_id'] as String,
        userId: map['user_id'] as String,
        hasSubmitted: map['has_submitted'] as bool? ?? false,
        hasJudged: map['has_judged'] as bool? ?? false,
        outcome: map['outcome'] as String?,
        scoreDeltaApplied: map['score_delta_applied'] as int?,
      );
}
