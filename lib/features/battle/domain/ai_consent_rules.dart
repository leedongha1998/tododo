import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/strings.dart';
import '../data/ai_consent.dart';

/// 서버가 "AI 데이터 제공 동의가 없다"를 알릴 때 쓰는 오류 코드(`PostgrestException.hint`).
const consentRequiredHint = 'CONSENT_REQUIRED';

/// 서버 오류가 동의 없음 때문인지. 이 경우 동의 화면으로 유도한다.
bool isConsentRequiredError(Object error) =>
    error is PostgrestException && error.hint == consentRequiredHint;

/// 철회 확인 대화상자 본문. 처리될 대결이 없으면 뒷문장만 보여 준다(design.md 화면 2).
String consentWithdrawalMessage(ConsentWithdrawalImpact impact) {
  if (impact.activeCount == 0 && impact.pendingCount == 0) {
    return AppStrings.aiConsentWithdrawAfter;
  }
  return '${AppStrings.aiConsentWithdrawImpact(impact.activeCount, impact.pendingCount)}\n'
      '${AppStrings.aiConsentWithdrawAfter}';
}
