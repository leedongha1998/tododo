import 'package:supabase_flutter/supabase_flutter.dart';

import 'battle.dart';
import 'battle_participant.dart';

class BattleRepository {
  BattleRepository(this._client);

  static const _evidenceBucket = 'battle_evidence';
  static const _signedUrlSeconds = 300;

  final SupabaseClient _client;

  Future<void> createBattle({
    required String type,
    required String title,
    required int durationHours,
  }) {
    final myId = _client.auth.currentUser!.id;
    return _client.from('battles').insert({
      'creator_id': myId,
      'type': type,
      'title': title,
      'duration_hours': durationHours,
    });
  }

  Future<List<Battle>> fetchOpenRecruits() async {
    final myId = _client.auth.currentUser!.id;
    final rows = await _client
        .from('battles')
        .select()
        .eq('status', 'pending')
        .neq('creator_id', myId)
        .order('created_at');
    return rows.map(Battle.fromMap).toList();
  }

  Future<List<Battle>> fetchMyRecruits() async {
    final myId = _client.auth.currentUser!.id;
    final rows = await _client
        .from('battles')
        .select()
        .eq('status', 'pending')
        .eq('creator_id', myId)
        .order('created_at');
    return rows.map(Battle.fromMap).toList();
  }

  Future<Map<String, String>> fetchDisplayNames(Iterable<String> ids) async {
    final uniqueIds = ids.toSet().toList();
    if (uniqueIds.isEmpty) return {};
    final rows = await _client.from('profiles').select().inFilter('id', uniqueIds);
    return {for (final row in rows) row['id'] as String: row['display_name'] as String};
  }

  Future<void> joinBattle(String battleId) {
    return _client.rpc('join_battle', params: {'p_battle_id': battleId});
  }

  Future<void> cancelBattle(String battleId) {
    return _client.rpc('cancel_battle', params: {'p_battle_id': battleId});
  }

  // 진행 중인 대결만 돌려준다. 끝난 대결(finished/draw/voided)은 프로필 전적에서 본다 —
  // 여기에 계속 쌓이면 지금 뭘 해야 하는지가 목록에서 묻힌다.
  Future<List<Battle>> fetchMyBattles() async {
    final myId = _client.auth.currentUser!.id;
    final rows = await _client
        .from('battles')
        .select()
        .or('creator_id.eq.$myId,opponent_id.eq.$myId')
        .inFilter('status', ['active', 'judging'])
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

  // 비공개 버킷이라 매번 짧은 수명의 서명 URL을 받아 화면에 그린다.
  // 서명 URL 발급도 Storage 조회 정책을 거치므로, 서버가 가린 사진은 여기서 실패한다.
  Future<String> createEvidencePhotoUrl(String path) {
    return _client.storage.from(_evidenceBucket).createSignedUrl(path, _signedUrlSeconds);
  }

  // 포기(기권). 유형과 상관없이 포기한 쪽이 지고 상대가 이긴다. 결과와 점수는 서버가 정한다.
  Future<void> forfeitBattle(String battleId) {
    return _client.rpc('forfeit_battle', params: {'p_battle_id': battleId});
  }
}
