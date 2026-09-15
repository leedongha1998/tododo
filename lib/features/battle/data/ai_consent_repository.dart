import 'package:supabase_flutter/supabase_flutter.dart';

import 'ai_consent.dart';

class AiConsentRepository {
  AiConsentRepository(this._client);

  /// 동의 화면 문안 버전. 문안(받는 자·항목·목적·보유 기간·거부 권리)을 바꾸면 올린다.
  static const currentVersion = '2026-09-14';

  final SupabaseClient _client;

  /// 내 동의 기록. 동의하지 않았거나 철회했으면 null.
  Future<AiConsent?> fetchMyConsent() async {
    final myId = _client.auth.currentUser!.id;
    final row = await _client.from('ai_consents').select().eq('user_id', myId).maybeSingle();
    return row == null ? null : AiConsent.fromMap(row);
  }

  Future<void> giveConsent() {
    return _client.rpc('give_ai_consent', params: {'p_version': currentVersion});
  }

  Future<ConsentWithdrawalImpact> fetchWithdrawalImpact() async {
    final result = await _client.rpc('get_consent_withdrawal_impact');
    return ConsentWithdrawalImpact.fromMap(Map<String, dynamic>.from(result as Map));
  }

  // 진행 중 대결은 포기, 모집 중 대결은 취소가 한 트랜잭션에서 함께 처리된다(서버).
  Future<void> withdrawConsent() {
    return _client.rpc('withdraw_ai_consent');
  }
}
