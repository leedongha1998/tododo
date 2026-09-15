/// 대결 참가자 한 명의 진행 요약과 결과.
///
/// 이 행은 진행 중에도 상대에게 보이는 값만 담는다. 사진 경로와 판정 사유는
/// `battle_submissions`에 있고, 서버가 대결 종결 전에는 상대에게 내주지 않는다.
class BattleParticipant {
  const BattleParticipant({
    required this.battleId,
    required this.userId,
    this.firstSubmittedAt,
    this.attemptsUsed = 0,
    this.lastVerdict,
    this.passedAt,
    this.outcome,
    this.scoreDeltaApplied,
  });

  final String battleId;
  final String userId;

  /// 처음으로 수락된 제출의 서버 시각. "제출했어요" 표시용.
  final DateTime? firstSubmittedAt;

  /// 속도전 AI 판정 사용 횟수(합격 + 불합격). AI 실패는 세지 않는다.
  final int attemptsUsed;

  /// 속도전 최근 판정 결과(`passed` / `failed`). 사유는 담지 않는다.
  final String? lastVerdict;

  /// 속도전 최소 기준을 통과한 제출의 서버 시각.
  final DateTime? passedAt;

  /// 종결 시 서버가 기록한 결과(`win`, `completed_loss`, `loss`, `forfeit`, `draw`).
  /// 무효·취소면 null.
  final String? outcome;

  /// 점수 하한(0)을 적용한 뒤 실제로 바뀐 점수.
  final int? scoreDeltaApplied;

  factory BattleParticipant.fromMap(Map<String, dynamic> map) => BattleParticipant(
        battleId: map['battle_id'] as String,
        userId: map['user_id'] as String,
        firstSubmittedAt: map['first_submitted_at'] == null
            ? null
            : DateTime.parse(map['first_submitted_at'] as String),
        attemptsUsed: (map['attempts_used'] as int?) ?? 0,
        lastVerdict: map['last_verdict'] as String?,
        passedAt: map['passed_at'] == null ? null : DateTime.parse(map['passed_at'] as String),
        outcome: map['outcome'] as String?,
        scoreDeltaApplied: map['score_delta_applied'] as int?,
      );
}
