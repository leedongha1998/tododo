import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/strings.dart';
import '../data/submission_result.dart';

/// 속도전 판정은 참가자당 대결마다 5회다(서버와 같은 값). AI 실패는 세지 않는다.
const speedJudgeMaxAttempts = 5;

/// 서버가 준 오류 코드. Edge Function 응답과 RPC 힌트를 같은 방식으로 읽는다.
String? submissionErrorCodeOf(Object error) {
  if (error is SubmissionException) return error.code;
  if (error is PostgrestException) return error.hint;
  return null;
}

/// 오류 코드 → 사용자 문구. 거부는 사용자가 무엇을 고쳐야 하는지로 말한다.
String submissionErrorMessage(Object error) {
  return switch (submissionErrorCodeOf(error)) {
    'CAPTURED_BEFORE_START' => AppStrings.battleErrorCapturedBeforeStart,
    'CAPTURE_TIME_MISMATCH' => AppStrings.battleErrorCaptureTimeMismatch,
    'DEADLINE_PASSED' => AppStrings.battleErrorDeadlinePassed,
    'SUBMISSION_LOCKED' => AppStrings.battleErrorSubmissionLocked,
    'JUDGING_IN_PROGRESS' => AppStrings.battleErrorJudgingInProgress,
    'ATTEMPTS_EXHAUSTED' => AppStrings.battleErrorAttemptsExhausted,
    'CONSENT_REQUIRED' => AppStrings.aiConsentRequired,
    _ => AppStrings.battleEvidenceSubmitFailed,
  };
}

/// 제출 상태 → 이력에 붙는 라벨. 서버 값을 글자로 옮길 뿐 판정하지 않는다.
String submissionStatusLabel(String status) {
  return switch (status) {
    'passed' => AppStrings.battleEvidenceVerdictPassed,
    'failed' => AppStrings.battleEvidenceVerdictFailed,
    'error' => AppStrings.battleEvidenceVerdictError,
    'judging' => AppStrings.battleEvidenceVerdictJudging,
    _ => AppStrings.battleEvidenceVerdictSubmitted,
  };
}
