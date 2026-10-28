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
    this.durationMinutes = 1440,
    this.deadlineAt,
    this.judgingOpenedAt,
    this.judgeDeadlineAt,
    this.minCriteria = const [],
    this.superiorityCriteria,
    this.criteriaVersion = 1,
    this.verdictReason,
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

  /// 대결을 만든 사람이 고른 제출 창의 길이(분 단위, 1~10080). 사진을 내는 시간이고,
  /// 마감 뒤의 판정 창은 이 값과 무관하다.
  final int durationMinutes;

  /// 제출 창의 마감 시각. 매칭되는 순간 정해지므로 모집 중에는 null이다.
  final DateTime? deadlineAt;

  /// 판정 창이 열린 서버 시각. null이면 아직 제출 창(active)이다.
  final DateTime? judgingOpenedAt;

  /// 판정 기한(판정 창이 열린 시각 + 24시간). 지나면 미판정은 자동 승인으로 채워진다.
  final DateTime? judgeDeadlineAt;

  /// 합격/불합격을 가르는 최소 기준. 두 유형 공통이고 참가 전에 공개된다.
  final List<String> minCriteria;

  /// 품질전에서 둘 다 통과했을 때 승자를 가르는 우열 기준. 속도전은 null.
  final List<String>? superiorityCriteria;

  /// 두 기준 목록의 공통 버전. 참가자는 자기가 확인한 버전으로만 참가할 수 있다.
  final int criteriaVersion;

  /// 품질전 AI 판정의 한 줄 사유. 둘 다 최소 기준을 통과했으면 우열 기준에 근거한 승패 사유,
  /// 한쪽만 통과했으면 미달 쪽 사진의 사유다. 판정과 동시에 종결되므로 종결 뒤에만 값이 있다.
  final String? verdictReason;

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
        durationMinutes: (map['duration_minutes'] as int?) ?? 1440,
        deadlineAt:
            map['deadline_at'] == null ? null : DateTime.parse(map['deadline_at'] as String),
        judgingOpenedAt: map['judging_opened_at'] == null
            ? null
            : DateTime.parse(map['judging_opened_at'] as String),
        judgeDeadlineAt: map['judge_deadline_at'] == null
            ? null
            : DateTime.parse(map['judge_deadline_at'] as String),
        minCriteria: _criteriaOf(map['min_criteria']) ?? const [],
        superiorityCriteria: _criteriaOf(map['superiority_criteria']),
        criteriaVersion: (map['criteria_version'] as int?) ?? 1,
        verdictReason: map['verdict_reason'] as String?,
      );
}
