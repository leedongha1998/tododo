import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_init.dart';
import '../data/battle.dart';
import '../data/battle_repository.dart';
import '../data/vs_intro_seen_store.dart';
import 'battle_detail.dart';
import 'battle_recruit.dart';
import 'battle_summary.dart';

final battleRepositoryProvider = Provider<BattleRepository>((ref) {
  return BattleRepository(supabase);
});

// 대결 목록류 provider는 화면을 떠나면 캐시를 비우는 autoDispose를 쓴다.
// 그래야 상대가 참가/제출하는 등 서버 쪽 변화가 있어도 화면에 다시 들어올 때 최신 상태를 가져온다.
final openRecruitsProvider = FutureProvider.autoDispose<List<BattleRecruit>>((ref) async {
  final repo = ref.watch(battleRepositoryProvider);
  final battles = await repo.fetchOpenRecruits();
  final names = await repo.fetchDisplayNames(battles.map((b) => b.creatorId));
  return battles
      .map((b) => BattleRecruit(battle: b, creatorName: names[b.creatorId] ?? '알 수 없음'))
      .toList();
});

final myRecruitsProvider = FutureProvider.autoDispose<List<Battle>>((ref) async {
  return ref.watch(battleRepositoryProvider).fetchMyRecruits();
});

final myBattlesProvider = FutureProvider.autoDispose<List<BattleSummary>>((ref) async {
  final repo = ref.watch(battleRepositoryProvider);
  final myId = supabase.auth.currentUser!.id;
  final battles = await repo.fetchMyBattles();
  final otherIds = battles.map((b) => b.creatorId == myId ? b.opponentId! : b.creatorId);
  final names = await repo.fetchDisplayNames(otherIds);
  return battles.map((b) {
    final otherId = b.creatorId == myId ? b.opponentId! : b.creatorId;
    return BattleSummary(battle: b, otherPartyName: names[otherId] ?? '알 수 없음');
  }).toList();
});

final battleDetailProvider = FutureProvider.autoDispose.family<BattleDetail, String>((ref, battleId) async {
  final repo = ref.watch(battleRepositoryProvider);
  final myId = supabase.auth.currentUser!.id;
  final battle = await repo.fetchBattle(battleId);
  final participants = await repo.fetchParticipants(battleId);
  final me = participants.firstWhere((p) => p.userId == myId);
  final opponent = participants.firstWhere((p) => p.userId != myId);
  final names = await repo.fetchDisplayNames([me.userId, opponent.userId]);
  return BattleDetail(
    battle: battle,
    me: me,
    opponent: opponent,
    myName: names[me.userId] ?? '나',
    opponentName: names[opponent.userId] ?? '알 수 없음',
  );
});

/// VS 인트로 "봤음" 기록. 위젯 테스트에서 가짜로 바꿀 수 있게 provider로 둔다.
final vsIntroSeenStoreProvider = Provider<VsIntroSeenStore>((ref) => const VsIntroSeenStore());
