/// AI 데이터 제공 동의 기록(본인 것만 읽힌다).
class AiConsent {
  const AiConsent({required this.version, required this.consentedAt});

  /// 동의한 동의서 문안 버전.
  final String version;
  final DateTime consentedAt;

  factory AiConsent.fromMap(Map<String, dynamic> map) => AiConsent(
        version: map['consent_version'] as String,
        consentedAt: DateTime.parse(map['consented_at'] as String),
      );
}

/// 동의를 철회하면 처리될 대결 수. 철회 확인 문구에 쓴다(서버 조회 결과).
class ConsentWithdrawalImpact {
  const ConsentWithdrawalImpact({required this.activeCount, required this.pendingCount});

  /// 포기 처리될 진행 중(active/judging) 대결 수.
  final int activeCount;

  /// 취소될 모집 중(pending) 대결 수.
  final int pendingCount;

  factory ConsentWithdrawalImpact.fromMap(Map<String, dynamic> map) => ConsentWithdrawalImpact(
        activeCount: (map['active_count'] as num).toInt(),
        pendingCount: (map['pending_count'] as num).toInt(),
      );
}
