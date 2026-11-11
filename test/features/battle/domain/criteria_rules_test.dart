import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:todododo/core/strings.dart';
import 'package:todododo/features/battle/data/battle_criteria_repository.dart';
import 'package:todododo/features/battle/data/criteria_check_result.dart';
import 'package:todododo/features/battle/domain/criteria_rules.dart';

MyLimits _limits({bool consented = true, int criteriaCallsLeft = 10}) {
  return MyLimits(consented: consented, criteriaCallsLeft: criteriaCallsLeft);
}

void main() {
  group('validateCriteriaList', () {
    test('1~5개, 각 100자 이내면 통과한다', () {
      expect(validateCriteriaList(['책상이 비어 있다']), isNull);
      expect(validateCriteriaList(List.filled(5, '기준')), isNull);
    });

    test('비어 있거나 6개 이상이면 막는다', () {
      expect(validateCriteriaList([]), AppStrings.battleCriteriaTooFew);
      expect(validateCriteriaList(List.filled(6, '기준')), AppStrings.battleCriteriaTooMany);
    });

    test('빈 항목과 100자 초과 항목을 막는다', () {
      expect(validateCriteriaList(['기준', '   ']), AppStrings.battleCriteriaItemEmpty);
      expect(validateCriteriaList(['가' * 101]), AppStrings.battleCriteriaItemTooLong);
    });
  });

  group('criteriaListsEqual', () {
    test('앞뒤 공백만 다르면 같은 목록으로 본다', () {
      expect(criteriaListsEqual([' 기준 '], ['기준']), isTrue);
    });

    test('내용이나 개수가 다르면 다르다', () {
      expect(criteriaListsEqual(['기준'], ['다른 기준']), isFalse);
      expect(criteriaListsEqual(['기준'], ['기준', '하나 더']), isFalse);
    });
  });

  group('criteriaErrorMessage', () {
    test('Edge Function 오류 코드를 문구로 바꾼다', () {
      expect(
        criteriaErrorMessage(const CriteriaException('CRITERIA_CALL_LIMIT')),
        AppStrings.battleErrorCriteriaCallLimit,
      );
      expect(
        criteriaErrorMessage(const CriteriaException('AI_FAILED')),
        AppStrings.battleErrorAiFailed,
      );
      expect(
        criteriaErrorMessage(const CriteriaException('CONSENT_REQUIRED')),
        AppStrings.aiConsentRequired,
      );
    });

    test('RPC 힌트도 같은 방식으로 읽는다', () {
      expect(
        criteriaErrorMessage(PostgrestException(message: '...', hint: 'CHECK_INVALID')),
        AppStrings.battleErrorCheckInvalid,
      );
      expect(
        criteriaErrorMessage(PostgrestException(message: '...', hint: 'NOT_PENDING')),
        AppStrings.battleErrorNotPending,
      );
    });

    test('참가 흐름의 오류 코드도 문구로 바꾼다', () {
      expect(
        criteriaErrorMessage(PostgrestException(message: '...', hint: 'CRITERIA_CHANGED')),
        AppStrings.battleCriteriaChanged,
      );
      expect(
        criteriaErrorMessage(PostgrestException(message: '...', hint: 'ALREADY_MATCHED')),
        AppStrings.battleErrorAlreadyMatched,
      );
    });

    test('기준 변경만 따로 가려낸다(시트를 닫지 않고 기준을 다시 보여 주기 위해)', () {
      expect(
        isCriteriaChangedError(PostgrestException(message: '...', hint: 'CRITERIA_CHANGED')),
        isTrue,
      );
      expect(
        isCriteriaChangedError(PostgrestException(message: '...', hint: 'ALREADY_MATCHED')),
        isFalse,
      );
      expect(isCriteriaChangedError(Exception('network')), isFalse);
    });

    test('모르는 오류는 일반 문구로 안내한다', () {
      expect(criteriaErrorMessage(Exception('network')), AppStrings.battleErrorUnknown);
    });
  });

  group('createBattleBlockMessage', () {
    test('한도가 남아 있으면 막지 않는다', () {
      expect(createBattleBlockMessage(_limits()), isNull);
    });

    // criteria-cache: 남은 사전 차단 사유는 **동의 하나뿐이다.** 한도 소진으로 막으면
    // "한도를 다 쓴 사용자도 캐시 적중이면 기준을 받을 수 있다"가 깨진다(적중은 한도를 쓰지 않는다).
    test('동의 전에만 막고 한도 소진으로는 막지 않는다', () {
      expect(createBattleBlockMessage(_limits(consented: false)), AppStrings.aiConsentRequired);
      expect(createBattleBlockMessage(_limits(criteriaCallsLeft: 0)), isNull);
      // 동의도 없고 한도도 없으면 동의를 먼저 말한다.
      expect(
        createBattleBlockMessage(_limits(consented: false, criteriaCallsLeft: 0)),
        AppStrings.aiConsentRequired,
      );
    });
  });

  group('criteriaCallsExhaustedNotice', () {
    test('0회에서만 안내 문구를 주고, 그 문구가 차단 문구와 다르다', () {
      expect(criteriaCallsExhaustedNotice(_limits(criteriaCallsLeft: 1)), isNull);
      expect(
        criteriaCallsExhaustedNotice(_limits(criteriaCallsLeft: 0)),
        AppStrings.battleCriteriaCallsExhausted,
      );
      // 버튼을 누를 수 있게 됐으므로 "내일 다시 시도해주세요"라고 조언하지 않는다.
      expect(
        AppStrings.battleCriteriaCallsExhausted == AppStrings.battleErrorCriteriaCallLimit,
        isFalse,
      );
    });
  });
}
