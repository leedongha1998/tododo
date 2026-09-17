import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_init.dart';
import '../data/player_stats.dart';
import '../data/profile_repository.dart';
import 'battle_record.dart';

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ProfileRepository(supabase);
});

final myProfileProvider = FutureProvider.autoDispose((ref) {
  return ref.watch(profileRepositoryProvider).fetchMyProfile();
});

/// 내 점수와 승/패/무. 서버가 종결 때 반영한 값을 그대로 읽는다.
final myPlayerStatsProvider = FutureProvider.autoDispose<PlayerStats>((ref) {
  return ref.watch(profileRepositoryProvider).fetchMyStats();
});

final battleRecordsProvider = FutureProvider.autoDispose<List<BattleRecord>>((ref) async {
  final repo = ref.watch(profileRepositoryProvider);
  final myId = supabase.auth.currentUser!.id;
  final battles = await repo.fetchCompletedBattles();
  final otherIds = battles.map((b) => b.creatorId == myId ? b.opponentId! : b.creatorId);
  final names = await repo.fetchDisplayNames(otherIds);
  // 결과 라벨은 서버가 적어 둔 outcome에서 나온다. 목록을 보고 승패를 다시 정하지 않는다.
  final outcomes = await repo.fetchMyOutcomes(battles.map((b) => b.id));
  return battles
      .map((b) {
        final otherId = b.creatorId == myId ? b.opponentId! : b.creatorId;
        return BattleRecord.fromBattle(
          b,
          myId: myId,
          otherPartyName: names[otherId] ?? '알 수 없음',
          outcome: outcomes[b.id],
        );
      })
      .whereType<BattleRecord>()
      .toList();
});
