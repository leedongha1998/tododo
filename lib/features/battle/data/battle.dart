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
    this.minCriteria = const [],
    this.superiorityCriteria,
    this.criteriaVersion = 1,
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

  /// 합격/불합격을 가르는 최소 기준. 두 유형 공통이고 참가 전에 공개된다.
  final List<String> minCriteria;

  /// 품질전에서 둘 다 통과했을 때 승자를 가르는 우열 기준. 속도전은 null.
  final List<String>? superiorityCriteria;

  /// 두 기준 목록의 공통 버전. 참가자는 자기가 확인한 버전으로만 참가할 수 있다.
  final int criteriaVersion;

  bool get hasSuperiorityCriteria => (superiorityCriteria ?? const []).isNotEmpty;

  static List<String>? _criteriaOf(Object? value) {
    if (value == null) return null;
    return (value as List).map((item) => item as String).toList();
  }

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
        minCriteria: _criteriaOf(map['min_criteria']) ?? const [],
        superiorityCriteria: _criteriaOf(map['superiority_criteria']),
        criteriaVersion: (map['criteria_version'] as int?) ?? 1,
      );
}
