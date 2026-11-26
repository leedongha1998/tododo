import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_init.dart';
import '../data/nickname_state.dart';
import '../data/player_stats.dart';
import '../data/profile_repository.dart';
import 'battle_record.dart';

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ProfileRepository(supabase);
});

final myProfileProvider = FutureProvider.autoDispose((ref) {
  return ref.watch(profileRepositoryProvider).fetchMyProfile();
});

/// 내 별명 관문 상태(design 7.1). **userId로 나눈다** — 로그아웃 뒤 다른 계정으로 들어오면 새로 읽고,
/// 토큰 갱신으로 `AuthGate`가 다시 그려져도 같은 키라 다시 조회하지 않는다.
///
/// **자동 재시도를 끈다.** riverpod 3은 실패한 provider를 스스로 다시 부르는데, 조회 실패로 본 화면에
/// 들어간 사용자가 몇 초 뒤 재시도 성공으로 관문에 끌려 나가면 안 된다(관문의 래치와 두 겹이다).
/// 미확정 사용자는 다음 실행에 다시 관문을 본다.
final myNicknameStateProvider = FutureProvider.autoDispose.family<NicknameState, String>(
  (ref, userId) => ref.watch(profileRepositoryProvider).fetchMyNicknameState(),
  retry: (retryCount, error) => null,
);

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
