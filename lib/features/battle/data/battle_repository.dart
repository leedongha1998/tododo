import 'package:supabase_flutter/supabase_flutter.dart';

import 'battle.dart';
import 'battle_participant.dart';
import 'criteria_check_result.dart';
import 'open_recruit.dart';
import 'player_card.dart';

class BattleRepository {
  BattleRepository(this._client);

  static const _evidenceBucket = 'battle_evidence';
  static const _signedUrlSeconds = 300;

  final SupabaseClient _client;

  /// 검사를 통과한 기준 증서로만 대결을 만든다. 제목·유형·기준은 서버가 증서에서 복사하므로
  /// 클라이언트가 보낸 텍스트는 쓰이지 않는다.
  Future<String> createBattle({required String checkId, required int durationHours}) async {
    final id = await _client.rpc(
      'create_battle',
      params: {'p_check_id': checkId, 'p_duration_hours': durationHours},
    );
    return id as String;
  }

  /// 모집 중(상대 없음)인 내 대결의 기준을 바꾼다. 새 버전 번호를 돌려준다.
  Future<int> updateBattleCriteria({required String battleId, required String checkId}) async {
    final version = await _client.rpc(
      'update_battle_criteria',
      params: {'p_battle_id': battleId, 'p_check_id': checkId},
    );
    return (version as num).toInt();
  }

  Future<MyLimits> fetchMyLimits() async {
    final row = await _client.rpc('get_my_limits');
    return MyLimits.fromMap(Map<String, dynamic>.from(row as Map));
  }

  /// 남이 올린 모집 + 기준 두 목록 + 기준 버전 + 생성자 전적을 한 번에 받는다.
  Future<List<OpenRecruit>> fetchOpenRecruits() async {
    final rows = await _client.rpc('list_open_recruits');
    return (rows as List)
        .map((row) => OpenRecruit.fromMap(Map<String, dynamic>.from(row as Map)))
        .toList();
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

  /// 내가 확인한 기준 버전으로만 참가한다. 그 사이 생성자가 기준을 바꿨으면 서버가 거부한다.
  Future<void> joinBattle(String battleId, int criteriaVersion) {
    return _client.rpc(
      'join_battle',
      params: {'p_battle_id': battleId, 'p_criteria_version': criteriaVersion},
    );
  }

  /// 대결 상대나 모집 생성자의 전적. 그 외 사용자는 서버가 거부한다.
  Future<PlayerCard> fetchPlayerCard(String userId) async {
    final row = await _client.rpc('get_player_card', params: {'p_user_id': userId});
    return PlayerCard.fromMap(Map<String, dynamic>.from(row as Map));
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
