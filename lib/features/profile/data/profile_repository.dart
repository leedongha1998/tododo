import 'package:supabase_flutter/supabase_flutter.dart';

import '../../battle/data/battle.dart';
import '../../battle/data/profile.dart';
import 'player_stats.dart';

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
        // 무효(voided)는 내 기록에만 보인다. 취소(cancelled)는 기록 목록에 넣지 않는다.
        .inFilter('status', ['finished', 'draw', 'voided'])
        .order('created_at', ascending: false);
    return rows.map(Battle.fromMap).toList();
  }

  /// 내 점수와 승/패/무. 서버(`finalize_battle`)가 정한 값이고 RLS가 본인 행만 내준다.
  /// 행이 아직 없는 계정은 0점·0전으로 본다.
  Future<PlayerStats> fetchMyStats() async {
    final myId = _client.auth.currentUser!.id;
    final row = await _client.from('player_stats').select().eq('user_id', myId).maybeSingle();
    return row == null ? PlayerStats.empty : PlayerStats.fromMap(row);
  }

  /// 기록 목록에 붙일 내 결과(`battle_participants.outcome`).
  /// 종결 시 서버가 적어 둔 값을 읽을 뿐이며 승패를 계산하지 않는다.
  Future<Map<String, String?>> fetchMyOutcomes(Iterable<String> battleIds) async {
    final uniqueIds = battleIds.toSet().toList();
    if (uniqueIds.isEmpty) return {};
    final myId = _client.auth.currentUser!.id;
    final rows = await _client
        .from('battle_participants')
        .select()
        .inFilter('battle_id', uniqueIds)
        .eq('user_id', myId);
    return {for (final row in rows) row['battle_id'] as String: row['outcome'] as String?};
  }

  Future<Map<String, String>> fetchDisplayNames(Iterable<String> ids) async {
    final uniqueIds = ids.toSet().toList();
    if (uniqueIds.isEmpty) return {};
    final rows = await _client.from('profiles').select().inFilter('id', uniqueIds);
    return {for (final row in rows) row['id'] as String: row['display_name'] as String};
  }
}
