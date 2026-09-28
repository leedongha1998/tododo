/// 증거 제출 Edge Function(`submit-evidence`)이 오류 코드로 알려 준 실패.
/// 앱은 코드로 문구를 고른다(서버 메시지를 그대로 보여 주지 않는다).
class SubmissionException implements Exception {
  const SubmissionException(this.code);

  final String code;

  @override
  String toString() => 'SubmissionException($code)';
}

/// 제출 접수 결과. 제출 즉시 판정은 없으므로 판정 결과가 아니라 접수 사실만 담긴다.
class SubmissionResult {
  const SubmissionResult({
    required this.submissionId,
    this.replaced = false,
    this.judgingOpened = false,
    this.battleStatus,
  });

  final int submissionId;

  /// 앞서 낸 사진을 이 사진으로 바꿨는지(속도전, 상대가 아직 내지 않았을 때만).
  final bool replaced;

  /// 양쪽이 모두 제출해 이 제출로 판정 창이 열렸는지.
  final bool judgingOpened;

  /// 접수 뒤의 대결 상태. 화면은 이 값을 표시에만 쓰고 승패를 계산하지 않는다.
  final String? battleStatus;

  factory SubmissionResult.fromMap(Map<String, dynamic> map) => SubmissionResult(
        submissionId: (map['submission_id'] as num).toInt(),
        replaced: (map['replaced'] as bool?) ?? false,
        judgingOpened: (map['judging_opened'] as bool?) ?? false,
        battleStatus: map['battle_status'] as String?,
      );
}
