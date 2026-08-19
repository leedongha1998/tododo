import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_init.dart';
import '../data/battle_repository.dart';
import 'battle_invite.dart';

final battleRepositoryProvider = Provider<BattleRepository>((ref) {
  return BattleRepository(supabase);
});

final receivedInvitesProvider = FutureProvider<List<BattleInvite>>((ref) async {
  final repo = ref.watch(battleRepositoryProvider);
  final battles = await repo.fetchReceivedInvites();
  final names = await repo.fetchDisplayNames(battles.map((b) => b.creatorId));
  return battles
      .map((b) => BattleInvite(battle: b, otherPartyName: names[b.creatorId] ?? '알 수 없음'))
      .toList();
});

final sentInvitesProvider = FutureProvider<List<BattleInvite>>((ref) async {
  final repo = ref.watch(battleRepositoryProvider);
  final battles = await repo.fetchSentInvites();
  final names = await repo.fetchDisplayNames(battles.map((b) => b.opponentId));
  return battles
      .map((b) => BattleInvite(battle: b, otherPartyName: names[b.opponentId] ?? '알 수 없음'))
      .toList();
});
