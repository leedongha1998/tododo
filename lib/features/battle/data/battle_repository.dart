import 'package:supabase_flutter/supabase_flutter.dart';

import 'battle.dart';
import 'battle_participant.dart';
import 'profile.dart';

class BattleRepository {
  BattleRepository(this._client);

  final SupabaseClient _client;

  Future<List<Profile>> searchProfiles(String query) async {
    final myId = _client.auth.currentUser!.id;
    final rows = await _client
        .from('profiles')
        .select()
        .ilike('display_name', '%$query%')
        .neq('id', myId)
        .limit(20);
    return rows.map(Profile.fromMap).toList();
  }

  Future<void> createBattle({
    required String opponentId,
    required String type,
    required String title,
  }) {
    final myId = _client.auth.currentUser!.id;
    return _client.from('battles').insert({
      'creator_id': myId,
      'opponent_id': opponentId,
      'type': type,
      'title': title,
    });
  }

  Future<List<Battle>> fetchReceivedInvites() => _fetchPendingBattles('opponent_id');

  Future<List<Battle>> fetchSentInvites() => _fetchPendingBattles('creator_id');

  Future<List<Battle>> _fetchPendingBattles(String myColumn) async {
    final myId = _client.auth.currentUser!.id;
    final rows = await _client
        .from('battles')
        .select()
        .eq(myColumn, myId)
        .eq('status', 'pending')
        .order('created_at');
    return rows.map(Battle.fromMap).toList();
  }

  Future<Map<String, String>> fetchDisplayNames(Iterable<String> ids) async {
    final uniqueIds = ids.toSet().toList();
    if (uniqueIds.isEmpty) return {};
    final rows = await _client.from('profiles').select().inFilter('id', uniqueIds);
    return {for (final row in rows) row['id'] as String: row['display_name'] as String};
  }

  Future<void> acceptBattle(String battleId) {
    return _client.rpc('accept_battle', params: {'p_battle_id': battleId});
  }

  Future<void> cancelBattle(String battleId) {
    return _client.rpc('cancel_battle', params: {'p_battle_id': battleId});
  }

  Future<List<Battle>> fetchMyBattles() async {
    final myId = _client.auth.currentUser!.id;
    final rows = await _client
        .from('battles')
        .select()
        .or('creator_id.eq.$myId,opponent_id.eq.$myId')
        .not('status', 'in', '(pending,cancelled)')
        .order('created_at', ascending: false);
    return rows.map(Battle.fromMap).toList();
  }

  Future<Battle> fetchBattle(String battleId) async {
    final row = await _client.from('battles').select().eq('id', battleId).single();
    return Battle.fromMap(row);
  }

  Future<List<BattleParticipant>> fetchParticipants(String battleId) async {
    final rows = await _client.from('battle_participants').select().eq('battle_id', battleId);
    return rows.map(BattleParticipant.fromMap).toList();
  }

  Future<void> completeSpeedTask(String battleId) {
    return _client.rpc('complete_speed_task', params: {'p_battle_id': battleId});
  }

  Future<void> submitQualityEvidence(String battleId, String content) {
    return _client.rpc('submit_quality_evidence', params: {
      'p_battle_id': battleId,
      'p_evidence_type': 'text',
      'p_evidence_content': content,
    });
  }

  Future<void> decideQualityEvidence(String battleId, String targetUserId, String decision) {
    return _client.rpc('decide_quality_evidence', params: {
      'p_battle_id': battleId,
      'p_target_user_id': targetUserId,
      'p_decision': decision,
    });
  }
}
