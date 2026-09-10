import 'package:supabase_flutter/supabase_flutter.dart';

import '../../battle/data/battle.dart';
import '../../battle/data/profile.dart';

class ProfileRepository {
  ProfileRepository(this._client);

  final SupabaseClient _client;

  Future<Profile> fetchMyProfile() async {
    final myId = _client.auth.currentUser!.id;
    final row = await _client.from('profiles').select().eq('id', myId).single();
    return Profile.fromMap(row);
  }

  Future<List<Battle>> fetchCompletedBattles() async {
    final myId = _client.auth.currentUser!.id;
    final rows = await _client
        .from('battles')
        .select()
        .or('creator_id.eq.$myId,opponent_id.eq.$myId')
        .inFilter('status', ['finished', 'disputed', 'draw'])
        .order('created_at', ascending: false);
    return rows.map(Battle.fromMap).toList();
  }

  Future<Map<String, String>> fetchDisplayNames(Iterable<String> ids) async {
    final uniqueIds = ids.toSet().toList();
    if (uniqueIds.isEmpty) return {};
    final rows = await _client.from('profiles').select().inFilter('id', uniqueIds);
    return {for (final row in rows) row['id'] as String: row['display_name'] as String};
  }
}
