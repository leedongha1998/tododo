import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:todododo/core/strings.dart';
import 'package:todododo/features/battle/data/ai_consent.dart';
import 'package:todododo/features/battle/domain/ai_consent_rules.dart';

void main() {
  group('isConsentRequiredError', () {
    test('서버가 CONSENT_REQUIRED 힌트를 주면 동의 없음으로 본다', () {
      final error = PostgrestException(
        message: 'AI 데이터 제공 동의가 필요합니다.',
        hint: consentRequiredHint,
      );
      expect(isConsentRequiredError(error), isTrue);
    });

    test('다른 힌트나 힌트 없는 오류는 동의 문제가 아니다', () {
      expect(
        isConsentRequiredError(PostgrestException(message: '이미 매칭되었습니다.', hint: 'ALREADY_MATCHED')),
        isFalse,
      );
      expect(isConsentRequiredError(PostgrestException(message: '알 수 없는 오류')), isFalse);
      expect(isConsentRequiredError(Exception('network')), isFalse);
    });
  });

  group('consentWithdrawalMessage', () {
    test('처리될 대결이 없으면 다시 동의하기 전까지 막힌다는 문장만 보여 준다', () {
      const impact = ConsentWithdrawalImpact(activeCount: 0, pendingCount: 0);
      expect(consentWithdrawalMessage(impact), AppStrings.aiConsentWithdrawAfter);
    });

    test('처리될 대결이 있으면 개수와 함께 포기·취소를 안내한다', () {
      const impact = ConsentWithdrawalImpact(activeCount: 2, pendingCount: 1);
      final message = consentWithdrawalMessage(impact);

      expect(message, contains('진행 중인 대결 2개'));
      expect(message, contains('모집 중인 대결 1개'));
      expect(message, contains(AppStrings.aiConsentWithdrawAfter));
    });

    test('진행 중이 0이어도 모집 중이 있으면 개수를 안내한다', () {
      const impact = ConsentWithdrawalImpact(activeCount: 0, pendingCount: 1);
      expect(consentWithdrawalMessage(impact), contains('모집 중인 대결 1개'));
    });
  });
}
