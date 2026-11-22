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
///
/// [isBot]이면 교체 잠김의 이유가 "상대가 제출했다"가 아니라 "봇이 완료했다"다. 같은 코드이고
/// 같은 서버 판단인데 사용자가 읽는 사실이 다르므로 문구만 갈린다.
/// `CONSENT_REQUIRED`는 봇전에서 발생하지 않는다(서버가 봇전의 동의 검사를 건너뛴다).
String submissionErrorMessage(Object error, {bool isBot = false}) {
  return switch (submissionErrorCodeOf(error)) {
    'CAPTURED_BEFORE_START' => AppStrings.battleErrorCapturedBeforeStart,
    'CAPTURE_TIME_MISMATCH' => AppStrings.battleErrorCaptureTimeMismatch,
    'DEADLINE_PASSED' => AppStrings.battleErrorDeadlinePassed,
    'SUBMISSION_LOCKED' => isBot
        ? AppStrings.botBattleErrorSubmissionLocked
        : AppStrings.battleErrorSubmissionLocked,
    'CONSENT_REQUIRED' => AppStrings.aiConsentRequired,
    _ => AppStrings.battleEvidenceSubmitFailed,
  };
}
