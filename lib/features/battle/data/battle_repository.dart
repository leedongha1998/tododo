import 'package:supabase_flutter/supabase_flutter.dart';

import 'battle.dart';
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
}
