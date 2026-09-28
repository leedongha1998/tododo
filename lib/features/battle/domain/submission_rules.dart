import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/strings.dart';
import '../data/submission_result.dart';

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
    'CONSENT_REQUIRED' => AppStrings.aiConsentRequired,
    _ => AppStrings.battleEvidenceSubmitFailed,
  };
}

/// 제출의 최소 기준 결론 → 라벨. 서버가 기록한 값을 글자로 옮길 뿐 판정하지 않는다.
/// 결론이 아직 없으면(판정 창 전, 판정 대기, AI 재판정 대기) "판정 전"이다.
String submissionVerdictLabel(bool? meetsCriteria) {
  return switch (meetsCriteria) {
    true => AppStrings.battleEvidenceVerdictPassed,
    false => AppStrings.battleEvidenceVerdictFailed,
    null => AppStrings.battleEvidenceVerdictPending,
  };
}
