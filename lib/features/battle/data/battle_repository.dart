import 'package:supabase_flutter/supabase_flutter.dart';

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
}
