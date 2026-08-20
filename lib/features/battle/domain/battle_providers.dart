import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_init.dart';
import '../data/battle.dart';
import '../data/battle_repository.dart';
import 'battle_detail.dart';
import 'battle_recruit.dart';
import 'battle_summary.dart';

final battleRepositoryProvider = Provider<BattleRepository>((ref) {
  return BattleRepository(supabase);
});

final openRecruitsProvider = FutureProvider<List<BattleRecruit>>((ref) async {
  final repo = ref.watch(battleRepositoryProvider);
  final battles = await repo.fetchOpenRecruits();
  final names = await repo.fetchDisplayNames(battles.map((b) => b.creatorId));
  return battles
      .map((b) => BattleRecruit(battle: b, creatorName: names[b.creatorId] ?? '알 수 없음'))
      .toList();
});

final myRecruitsProvider = FutureProvider<List<Battle>>((ref) async {
  return ref.watch(battleRepositoryProvider).fetchMyRecruits();
});

final myBattlesProvider = FutureProvider<List<BattleSummary>>((ref) async {
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

final battleDetailProvider = FutureProvider.family<BattleDetail, String>((ref, battleId) async {
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
