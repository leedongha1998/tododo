import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:todododo/core/strings.dart';
import 'package:todododo/features/battle/data/submission_result.dart';
import 'package:todododo/features/battle/domain/submission_rules.dart';

void main() {
  // 서버 메시지를 그대로 보여 주지 않는다. 코드로 문구를 고른다.
  group('제출 거부 문구', () {
    test('Edge Function이 준 거부 코드마다 무엇을 고쳐야 하는지 알려 준다', () {
      expect(
        submissionErrorMessage(const SubmissionException('CAPTURED_BEFORE_START')),
        AppStrings.battleErrorCapturedBeforeStart,
      );
      expect(
        submissionErrorMessage(const SubmissionException('CAPTURE_TIME_MISMATCH')),
        AppStrings.battleErrorCaptureTimeMismatch,
      );
      expect(
        submissionErrorMessage(const SubmissionException('DEADLINE_PASSED')),
        AppStrings.battleErrorDeadlinePassed,
      );
      expect(
        submissionErrorMessage(const SubmissionException('SUBMISSION_LOCKED')),
        AppStrings.battleErrorSubmissionLocked,
      );
      expect(
        submissionErrorMessage(const SubmissionException('JUDGING_IN_PROGRESS')),
        AppStrings.battleErrorJudgingInProgress,
      );
      expect(
        submissionErrorMessage(const SubmissionException('ATTEMPTS_EXHAUSTED')),
        AppStrings.battleErrorAttemptsExhausted,
      );
      expect(
        submissionErrorMessage(const SubmissionException('CONSENT_REQUIRED')),
        AppStrings.aiConsentRequired,
      );
    });

    test('RPC 힌트로 온 코드도 같은 방식으로 읽는다', () {
      final error = PostgrestException(message: '마감이 지났습니다.', hint: 'DEADLINE_PASSED');
      expect(submissionErrorCodeOf(error), 'DEADLINE_PASSED');
      expect(submissionErrorMessage(error), AppStrings.battleErrorDeadlinePassed);
    });

    test('모르는 오류는 일반 실패 문구로 떨어진다', () {
      expect(submissionErrorCodeOf(Exception('boom')), isNull);
      expect(submissionErrorMessage(Exception('boom')), AppStrings.battleEvidenceSubmitFailed);
      expect(
        submissionErrorMessage(const SubmissionException('SERVER_ERROR')),
        AppStrings.battleEvidenceSubmitFailed,
      );
    });
  });

  group('제출 상태 라벨', () {
    test('서버 상태 값을 글자로만 옮긴다', () {
      expect(submissionStatusLabel('passed'), AppStrings.battleEvidenceVerdictPassed);
      expect(submissionStatusLabel('failed'), AppStrings.battleEvidenceVerdictFailed);
      expect(submissionStatusLabel('error'), AppStrings.battleEvidenceVerdictError);
      expect(submissionStatusLabel('judging'), AppStrings.battleEvidenceVerdictJudging);
      expect(submissionStatusLabel('submitted'), AppStrings.battleEvidenceVerdictSubmitted);
    });
  });

  test('속도전 판정 상한은 서버와 같은 5회다', () {
    expect(speedJudgeMaxAttempts, 5);
  });
}
