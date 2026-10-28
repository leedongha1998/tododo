/// 증거 제출 Edge Function(`submit-evidence`)이 오류 코드로 알려 준 실패.
/// 앱은 코드로 문구를 고른다(서버 메시지를 그대로 보여 주지 않는다).
class SubmissionException implements Exception {
  const SubmissionException(this.code);

  final String code;

  @override
  String toString() => 'SubmissionException($code)';
}

/// 제출(또는 교체) 결과. 제출 즉시 AI가 판정하지 않으므로 여기에는 판정 사실이 없다 —
/// 승패는 상호 판정 창에서 결정된다.
class SubmissionResult {
  const SubmissionResult({
    required this.submissionId,
    this.replacedObjectPath,
    this.judgingOpened = false,
    this.battleStatus,
  });

  final int submissionId;

  /// 교체로 밀려난 옛 사진 경로. 있으면 이 제출로 대체됐다는 뜻이고, 앱은 더 쓸 일이 없다
  /// (삭제는 서버가 service 롤로 한다).
  final String? replacedObjectPath;

  /// 이 제출로 양쪽이 모두 냈다 — 같은 트랜잭션에서 판정 창이 열렸다는 뜻이다.
  final bool judgingOpened;

  /// 제출을 기록한 뒤의 대결 상태. 화면은 이 값을 표시에만 쓰고 승패를 계산하지 않는다.
  final String? battleStatus;

  factory SubmissionResult.fromMap(Map<String, dynamic> map) => SubmissionResult(
        submissionId: (map['submission_id'] as num).toInt(),
        replacedObjectPath: map['replaced_object_path'] as String?,
        judgingOpened: map['judging_opened'] as bool? ?? false,
        battleStatus: map['battle_status'] as String?,
      );
}
