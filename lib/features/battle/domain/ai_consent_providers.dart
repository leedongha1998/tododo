import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_init.dart';
import '../data/ai_consent.dart';
import '../data/ai_consent_repository.dart';

final aiConsentRepositoryProvider = Provider<AiConsentRepository>((ref) {
  return AiConsentRepository(supabase);
});

/// 내 AI 데이터 제공 동의. null이면 동의하지 않은 상태(철회 포함).
final myAiConsentProvider = FutureProvider.autoDispose<AiConsent?>((ref) {
  return ref.watch(aiConsentRepositoryProvider).fetchMyConsent();
});
