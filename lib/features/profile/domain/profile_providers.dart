import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/strings.dart';
import '../../../core/supabase/supabase_init.dart';
import '../data/profile_repository.dart';
import 'battle_record.dart';

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ProfileRepository(supabase);
});

final myProfileProvider = FutureProvider((ref) {
  return ref.watch(profileRepositoryProvider).fetchMyProfile();
});

final battleRecordsProvider = FutureProvider<List<BattleRecord>>((ref) async {
  final repo = ref.watch(profileRepositoryProvider);
  final myId = supabase.auth.currentUser!.id;
  final battles = await repo.fetchCompletedBattles();
  final otherIds = battles.map((b) => b.creatorId == myId ? b.opponentId! : b.creatorId);
  final names = await repo.fetchDisplayNames(otherIds);
  return battles.map((b) {
    final otherId = b.creatorId == myId ? b.opponentId! : b.creatorId;
    final resultLabel = b.type == 'speed'
        ? (b.winnerId == myId ? AppStrings.battleRecordWin : AppStrings.battleRecordLose)
        : (b.status == 'finished' ? AppStrings.battleStatusFinished : AppStrings.battleStatusDisputed);
    return BattleRecord(
      battle: b,
      otherPartyName: names[otherId] ?? '알 수 없음',
      resultLabel: resultLabel,
    );
  }).toList();
});
