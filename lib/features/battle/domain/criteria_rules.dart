import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/strings.dart';
import '../data/battle_criteria_repository.dart';
import '../data/criteria_check_result.dart';

/// 기준 목록 한 개에 들어갈 수 있는 항목 수와 길이. 서버(Edge·DB 제약)와 같은 값이다.
const criteriaMinCount = 1;
const criteriaMaxCount = 5;
const criterionMaxLength = 100;
const battleTitleMaxLength = 60;

/// 편집한 기준 목록이 보낼 수 있는 모양인지. 문제가 없으면 null.
String? validateCriteriaList(List<String> items) {
  final trimmed = items.map((item) => item.trim()).toList();
  if (trimmed.length < criteriaMinCount) return AppStrings.battleCriteriaTooFew;
  if (trimmed.length > criteriaMaxCount) return AppStrings.battleCriteriaTooMany;
  if (trimmed.any((item) => item.isEmpty)) return AppStrings.battleCriteriaItemEmpty;
  if (trimmed.any((item) => item.length > criterionMaxLength)) {
    return AppStrings.battleCriteriaItemTooLong;
  }
  return null;
}

/// 두 목록이 (공백을 다듬은 뒤) 같은지. 수정 여부를 가려 "다시 검사하기"를 띄운다.
bool criteriaListsEqual(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].trim() != b[i].trim()) return false;
  }
  return true;
}

/// 서버가 준 오류 코드. Edge Function 응답과 RPC 힌트를 같은 방식으로 읽는다.
String? errorCodeOf(Object error) {
  if (error is CriteriaException) return error.code;
  if (error is PostgrestException) return error.hint;
  return null;
}

/// 참가자가 본 기준이 그 사이 바뀌었는지. 이 경우 시트를 닫지 않고 바뀐 기준을 다시 보여 준다.
bool isCriteriaChangedError(Object error) => errorCodeOf(error) == 'CRITERIA_CHANGED';

/// 오류 코드 → 사용자 문구. 서버 메시지를 그대로 보여 주지 않는다.
String criteriaErrorMessage(Object error) {
  return switch (errorCodeOf(error)) {
    'CONSENT_REQUIRED' => AppStrings.aiConsentRequired,
    'CRITERIA_CHANGED' => AppStrings.battleCriteriaChanged,
    'ALREADY_MATCHED' => AppStrings.battleErrorAlreadyMatched,
    'CRITERIA_CALL_LIMIT' => AppStrings.battleErrorCriteriaCallLimit,
    'CHECK_INVALID' => AppStrings.battleErrorCheckInvalid,
    'NOT_PENDING' => AppStrings.battleErrorNotPending,
    'AI_FAILED' => AppStrings.battleErrorAiFailed,
    _ => AppStrings.battleErrorUnknown,
  };
}

/// 대결을 만들 수 없는 이유(사전 안내). 만들 수 있으면 null.
/// 같은 검사를 Edge Function과 `create_battle`이 다시 하므로 이 값은 편의일 뿐이다.
///
/// **이제 동의 하나뿐이다**(criteria-cache). 한도 소진은 더 이상 차단 사유가 아니다 — 캐시 적중은
/// 하루 10회를 쓰지 않으므로 소진 상태에서도 기준이 나올 수 있고, 미적중이면 서버가
/// `CRITERIA_CALL_LIMIT`로 거절해 같은 문구가 그대로 뜬다. 여기서 버튼을 막으면
/// "한도를 다 쓴 사용자도 적중이면 기준을 받을 수 있다"가 클라이언트 한 줄 때문에 불가능해진다.
String? createBattleBlockMessage(MyLimits limits) {
  if (!limits.consented) return AppStrings.aiConsentRequired;
  return null;
}

/// 한도 소진 **안내**(차단이 아니다). 버튼을 막지 않고, 서버가 같은 판단을 다시 한다.
String? criteriaCallsExhaustedNotice(MyLimits limits) =>
    limits.criteriaCallsLeft <= 0 ? AppStrings.battleCriteriaCallsExhausted : null;
