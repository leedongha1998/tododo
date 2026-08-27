class BattleParticipant {
  const BattleParticipant({
    required this.battleId,
    required this.userId,
    this.evidenceType,
    this.evidenceContent,
    this.evidenceSubmittedAt,
    this.decision,
    this.decisionAt,
  });

  final String battleId;
  final String userId;
  final String? evidenceType;
  final String? evidenceContent;
  final DateTime? evidenceSubmittedAt;
  final String? decision;
  final DateTime? decisionAt;

  factory BattleParticipant.fromMap(Map<String, dynamic> map) => BattleParticipant(
        battleId: map['battle_id'] as String,
        userId: map['user_id'] as String,
        evidenceType: map['evidence_type'] as String?,
        evidenceContent: map['evidence_content'] as String?,
        evidenceSubmittedAt: map['evidence_submitted_at'] == null
            ? null
            : DateTime.parse(map['evidence_submitted_at'] as String),
        decision: map['decision'] as String?,
        decisionAt:
            map['decision_at'] == null ? null : DateTime.parse(map['decision_at'] as String),
      );
}
