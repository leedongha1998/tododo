class Battle {
  const Battle({
    required this.id,
    required this.type,
    required this.status,
    required this.title,
    required this.creatorId,
    required this.opponentId,
    required this.createdAt,
    this.winnerId,
    this.startedAt,
    this.finishedAt,
  });

  final String id;
  final String type;
  final String status;
  final String title;
  final String creatorId;
  final String opponentId;
  final DateTime createdAt;
  final String? winnerId;
  final DateTime? startedAt;
  final DateTime? finishedAt;

  factory Battle.fromMap(Map<String, dynamic> map) => Battle(
        id: map['id'] as String,
        type: map['type'] as String,
        status: map['status'] as String,
        title: map['title'] as String,
        creatorId: map['creator_id'] as String,
        opponentId: map['opponent_id'] as String,
        createdAt: DateTime.parse(map['created_at'] as String),
        winnerId: map['winner_id'] as String?,
        startedAt: map['started_at'] == null ? null : DateTime.parse(map['started_at'] as String),
        finishedAt:
            map['finished_at'] == null ? null : DateTime.parse(map['finished_at'] as String),
      );
}
