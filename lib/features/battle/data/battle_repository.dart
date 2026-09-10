import 'dart:typed_data';

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
  }) {
    final myId = _client.auth.currentUser!.id;
    return _client.from('battles').insert({
      'creator_id': myId,
      'type': type,
      'title': title,
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

  // 진행 중인 대결만 돌려준다. 끝난 대결(finished/disputed)은 프로필 전적에서 본다 —
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

  // 사진 증거를 비공개 버킷에 올리고 오브젝트 경로를 돌려준다.
  // 이 경로가 그대로 evidence_content에 저장된다. 재제출이 허용되므로 upsert.
  Future<String> uploadEvidencePhoto(String battleId, Uint8List bytes) async {
    final myId = _client.auth.currentUser!.id;
    final path = '$battleId/$myId/evidence.jpg';
    await _client.storage.from(_evidenceBucket).uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: true, contentType: 'image/jpeg'),
        );
    return path;
  }

  // 비공개 버킷이라 매번 짧은 수명의 서명 URL을 받아 화면에 그린다.
  Future<String> createEvidencePhotoUrl(String path) {
    return _client.storage.from(_evidenceBucket).createSignedUrl(path, _signedUrlSeconds);
  }

  Future<void> submitEvidence(String battleId, String evidenceType, String content) {
    return _client.rpc('submit_evidence', params: {
      'p_battle_id': battleId,
      'p_evidence_type': evidenceType,
      'p_evidence_content': content,
    });
  }

  Future<void> decideEvidence(String battleId, String targetUserId, String decision) {
    return _client.rpc('decide_evidence', params: {
      'p_battle_id': battleId,
      'p_target_user_id': targetUserId,
      'p_decision': decision,
    });
  }
}
