/// AI 기준 생성·재검사 결과(Edge Function `battle-criteria` 응답).
class CriteriaCheckResult {
  const CriteriaCheckResult({
    required this.checkId,
    required this.provable,
    this.blockReason,
    this.minCriteria = const [],
    this.superiorityCriteria,
    required this.callsLeft,
  });

  /// 이 결과로 대결을 만들거나 기준을 바꿀 때 서버에 넘기는 증서 id.
  final String checkId;

  /// 사진으로 증명할 수 있는 미션인지. false면 대결로 만들 수 없다.
  final bool provable;

  /// 차단 사유 한 줄(provable이 false일 때만).
  final String? blockReason;

  final List<String> minCriteria;

  /// 품질전만. 속도전은 null.
  final List<String>? superiorityCriteria;

  /// 오늘 남은 기준 생성·재검사 횟수.
  final int callsLeft;

  static List<String> _listOf(Object? value) {
    if (value == null) return const [];
    return (value as List).map((item) => item as String).toList();
  }

  factory CriteriaCheckResult.fromMap(Map<String, dynamic> map) => CriteriaCheckResult(
        checkId: map['check_id'] as String,
        provable: map['provable'] as bool,
        blockReason: map['block_reason'] as String?,
        minCriteria: _listOf(map['min_criteria']),
        superiorityCriteria:
            map['superiority_criteria'] == null ? null : _listOf(map['superiority_criteria']),
        callsLeft: (map['calls_left'] as num?)?.toInt() ?? 0,
      );
}

/// 오늘 무엇을 할 수 있는지(생성 화면 사전 안내용). 판단은 서버가 다시 한다.
class MyLimits {
  const MyLimits({
    required this.consented,
    required this.hasPending,
    required this.dailyBattleUsed,
    required this.criteriaCallsLeft,
  });

  final bool consented;

  /// 모집 중인 내 대결이 이미 있는지(사용자당 1개).
  final bool hasPending;

  /// 오늘(KST) 매칭된 대결이 있는지(하루 1대결).
  final bool dailyBattleUsed;

  final int criteriaCallsLeft;

  factory MyLimits.fromMap(Map<String, dynamic> map) => MyLimits(
        consented: map['consented'] as bool,
        hasPending: map['has_pending'] as bool,
        dailyBattleUsed: map['daily_battle_used'] as bool,
        criteriaCallsLeft: (map['criteria_calls_left'] as num).toInt(),
      );
}
