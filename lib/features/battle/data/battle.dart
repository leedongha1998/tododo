class Battle {
  const Battle({
    required this.id,
    required this.type,
    required this.status,
    required this.title,
    required this.creatorId,
    this.opponentId,
    required this.createdAt,
    this.winnerId,
    this.startedAt,
    this.finishedAt,
    this.forfeitedBy,
    this.durationHours = 72,
    this.deadlineAt,
  });

  final String id;
  final String type;
  final String status;
  final String title;
  final String creatorId;
  final String? opponentId;
  final DateTime createdAt;
  final String? winnerId;
  final DateTime? startedAt;
  final DateTime? finishedAt;

  /// 포기(기권)한 참가자. 어떻게 끝났는지를 화면에서 설명하는 데만 쓴다.
  final String? forfeitedBy;

  /// 대결을 만든 사람이 고른 기간(시간 단위).
  final int durationHours;

  /// 마감 시각. 매칭되는 순간 정해지므로 모집 중에는 null이다.
  final DateTime? deadlineAt;

  factory Battle.fromMap(Map<String, dynamic> map) => Battle(
        id: map['id'] as String,
        type: map['type'] as String,
        status: map['status'] as String,
        title: map['title'] as String,
        creatorId: map['creator_id'] as String,
        opponentId: map['opponent_id'] as String?,
        createdAt: DateTime.parse(map['created_at'] as String),
        winnerId: map['winner_id'] as String?,
        startedAt: map['started_at'] == null ? null : DateTime.parse(map['started_at'] as String),
        finishedAt:
            map['finished_at'] == null ? null : DateTime.parse(map['finished_at'] as String),
        forfeitedBy: map['forfeited_by'] as String?,
        durationHours: (map['duration_hours'] as int?) ?? 72,
        deadlineAt:
            map['deadline_at'] == null ? null : DateTime.parse(map['deadline_at'] as String),
      );
}
