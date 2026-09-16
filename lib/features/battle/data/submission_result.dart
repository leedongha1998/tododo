/// 증거 제출 Edge Function(`submit-evidence`)이 오류 코드로 알려 준 실패.
/// 앱은 코드로 문구를 고른다(서버 메시지를 그대로 보여 주지 않는다).
class SubmissionException implements Exception {
  const SubmissionException(this.code);

  final String code;

  @override
  String toString() => 'SubmissionException($code)';
}

/// 제출과 (속도전이면) 판정 결과. 승패는 서버가 정하므로 여기에는 판정 사실만 담긴다.
class SubmissionResult {
  const SubmissionResult({
    required this.submissionId,
    this.verdict,
    this.reason,
    this.battleStatus,
  });

  final int submissionId;

  /// `passed` / `failed` / `error`. 품질전은 판정이 대결 단위라 null이다.
  final String? verdict;

  /// AI 한 줄 사유. 합격·불합격에만 있다.
  final String? reason;

  /// 판정을 기록한 뒤의 대결 상태. 화면은 이 값을 표시에만 쓰고 승패를 계산하지 않는다.
  final String? battleStatus;

  bool get isPassed => verdict == 'passed';

  bool get isFailed => verdict == 'failed';

  /// AI 호출이 실패한 제출. 판정 횟수에서 빠지므로 다시 낼 수 있다.
  bool get isError => verdict == 'error';

  factory SubmissionResult.fromMap(Map<String, dynamic> map) => SubmissionResult(
        submissionId: (map['submission_id'] as num).toInt(),
        verdict: map['verdict'] as String?,
        reason: map['reason'] as String?,
        battleStatus: map['battle_status'] as String?,
      );
}
