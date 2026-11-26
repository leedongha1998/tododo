import 'package:supabase_flutter/supabase_flutter.dart';

import '../../battle/data/battle.dart';
import '../../battle/data/profile.dart';
import 'nickname_state.dart';
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

  /// 내 별명 관문 상태. 본인만 RPC로 읽는다(`nickname_states`는 테이블을 직접 읽을 수 없다).
  Future<NicknameState> fetchMyNicknameState() async {
    final result = await _client.rpc('get_my_nickname_state');
    return NicknameState.fromMap(Map<String, dynamic>.from(result as Map));
  }

  /// 별명 확정·바꾸기(관문과 프로필이 같은 RPC). **원문 그대로** 보낸다 — 다듬기(공백 정리)와 규칙
  /// 검사는 서버(`check_nickname`) 한 자리에만 있다. 저장된 정규화 값을 돌려준다.
  /// 규칙 위반은 `PostgrestException`(hint = `NICKNAME_*`)으로 온다.
  Future<String> setNickname(String raw) async {
    final result = await _client.rpc('set_nickname', params: {'p_nickname': raw});
    return result as String;
  }

  /// 무작위 별명 하나(아무것도 쓰지 않는다). 관문의 "다른 별명 추천받기".
  Future<String> suggestNickname() async {
    final result = await _client.rpc('suggest_nickname');
    return result as String;
  }
}
