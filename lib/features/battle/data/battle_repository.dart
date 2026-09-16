import 'dart:math';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'battle.dart';
import 'battle_participant.dart';
import 'battle_submission.dart';
import 'criteria_check_result.dart';
import 'open_recruit.dart';
import 'player_card.dart';
import 'submission_result.dart';

class BattleRepository {
  BattleRepository(this._client);

  static const _evidenceBucket = 'battle_evidence';
  static const _signedUrlSeconds = 300;
  static const _submitFunctionName = 'submit-evidence';

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

  /// 진행 중에는 내 제출만 돌아온다. 상대 제출(사진 경로·판정 사유)은 종결된 뒤에야 서버가 내준다.
  Future<List<BattleSubmission>> fetchSubmissions(String battleId) async {
    final rows = await _client
        .from('battle_submissions')
        .select()
        .eq('battle_id', battleId)
        .order('submitted_at');
    return rows.map(BattleSubmission.fromMap).toList();
  }

  /// 촬영한 사진을 내 폴더에 올리고 경로를 돌려준다.
  ///
  /// 제출마다 새 이름으로 올린다(덮어쓰기 없음) — 속도전 시도 이력의 사진을 보존해야 하고,
  /// Storage 정책에도 update가 없다.
  Future<String> uploadEvidencePhoto({
    required String battleId,
    required Uint8List bytes,
  }) async {
    final userId = _client.auth.currentUser!.id;
    final path = '$battleId/$userId/${_randomObjectName()}.jpg';
    await _client.storage.from(_evidenceBucket).uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(contentType: 'image/jpeg'),
        );
    return path;
  }

  /// 올린 사진을 제출로 접수시킨다. 속도전이면 같은 호출에서 AI 판정까지 끝나 결과가 돌아온다.
  /// 촬영 시각은 서버가 수신 시각과 대조하는 데만 쓰고, 승부 시각은 서버가 찍는다.
  Future<SubmissionResult> submitEvidence({
    required String battleId,
    required String objectPath,
    required DateTime capturedAt,
  }) async {
    try {
      final response = await _client.functions.invoke(
        _submitFunctionName,
        body: {
          'battle_id': battleId,
          'object_path': objectPath,
          'captured_at': capturedAt.toUtc().toIso8601String(),
        },
      );
      return SubmissionResult.fromMap(Map<String, dynamic>.from(response.data as Map));
    } on FunctionException catch (error) {
      // 함수가 4xx/5xx면 본문의 {error: CODE}로 분기한다(거부 사유도 코드로 온다).
      final details = error.details;
      if (details is Map) {
        final code = details['error'];
        if (code is String) {
          return Future.error(SubmissionException(code));
        }
      }
      return Future.error(const SubmissionException('SERVER_ERROR'));
    }
  }

  // uuid 패키지를 새로 넣지 않으려고 난수 16바이트를 16진수로 쓴다(파일명 충돌 방지 용도라 충분하다).
  String _randomObjectName() {
    final random = Random.secure();
    final buffer = StringBuffer();
    for (var i = 0; i < 16; i++) {
      buffer.write(random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  // 포기(기권). 유형과 상관없이 포기한 쪽이 지고 상대가 이긴다. 결과와 점수는 서버가 정한다.
  Future<void> forfeitBattle(String battleId) {
    return _client.rpc('forfeit_battle', params: {'p_battle_id': battleId});
  }
}
