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

    // 대결 개수 한도가 사라져(daily-limit-removal) 남은 사전 조건은 동의와 기준 생성 횟수뿐이다.
    test('동의·기준 횟수 순서로 이유를 알려 준다', () {
      expect(createBattleBlockMessage(_limits(consented: false)), AppStrings.aiConsentRequired);
      expect(
        createBattleBlockMessage(_limits(criteriaCallsLeft: 0)),
        AppStrings.battleErrorCriteriaCallLimit,
      );
    });
  });
}
