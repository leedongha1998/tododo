import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/strings.dart';
import '../../auth/domain/auth_providers.dart';
import '../../profile/domain/profile_providers.dart';
import '../domain/battle_providers.dart';
import '../domain/battle_recruit.dart';
import 'battle_chips.dart';
import 'create_battle_screen.dart';
import 'vs_intro.dart';

class BattleRecruitsScreen extends ConsumerWidget {
  const BattleRecruitsScreen({super.key});

  Future<void> _join(BuildContext context, WidgetRef ref, BattleRecruit recruit) async {
    final battleId = recruit.battle.id;
    try {
      await ref.read(battleRepositoryProvider).joinBattle(battleId);
      ref.invalidate(openRecruitsProvider);
      ref.invalidate(myBattlesProvider);
    } catch (e) {
      debugPrint('joinBattle failed: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text(AppStrings.battleJoinFailed)));
      }
      return;
    }

    // 참가 성공 직후 VS 인트로. 인트로가 끝난 뒤에 성공 토스트를 띄워 인트로가 토스트를 가리지 않는다.
    // 서버가 방금 active로 바꿨으므로 status는 active로 판단한다.
    final userId = ref.read(authRepositoryProvider).currentUser?.id;
    if (userId != null && context.mounted) {
      final myName = await _myNameForIntro(ref);
      if (!context.mounted) return;
      await maybeShowVsIntro(
        context,
        store: ref.read(vsIntroSeenStoreProvider),
        userId: userId,
        battleId: battleId,
        status: 'active',
        myName: myName,
        opponentName: recruit.creatorName,
      );
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text(AppStrings.battleJoined)));
    }
  }

  // 내 표시 이름을 못 읽어도 인트로는 "나"로 띄운다. 장식이라 실패를 알리지 않는다.
  Future<String> _myNameForIntro(WidgetRef ref) async {
    try {
      final profile = await ref.read(myProfileProvider.future);
      return profile.displayName;
    } catch (e) {
      debugPrint('myProfileProvider for vs intro failed: $e');
      return AppStrings.battleMe;
    }
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref, String battleId) async {
    try {
      await ref.read(battleRepositoryProvider).cancelBattle(battleId);
      ref.invalidate(myRecruitsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text(AppStrings.battleRecruitCancelled)));
      }
    } catch (e) {
      debugPrint('cancelBattle failed: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text(AppStrings.battleRecruitCancelFailed)));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final openRecruits = ref.watch(openRecruitsProvider);
    final myRecruits = ref.watch(myRecruitsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.battleFind)),
      // 등록한 모집이 바로 아래 목록에 뜨므로 만들기 버튼도 이 화면에 있는 게 맞다.
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const CreateBattleScreen()),
        ),
        icon: const Icon(Icons.sports_kabaddi),
        label: const Text(AppStrings.battleCreate),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(AppStrings.battleOpenRecruits, style: Theme.of(context).textTheme.titleMedium),
          openRecruits.when(
            data: (recruits) => recruits.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(AppStrings.battleRecruitsEmpty),
                  )
                : Column(
                    children: recruits
                        .map(
                          (recruit) => ListTile(
                            title: Text(recruit.battle.title),
                            subtitle: Row(
                              children: [
                                BattleTypeBadge(type: recruit.battle.type),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    recruit.creatorName,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            trailing: FilledButton(
                              onPressed: () => _join(context, ref, recruit),
                              child: const Text(AppStrings.battleJoin),
                            ),
                          ),
                        )
                        .toList(),
                  ),
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, stackTrace) {
              debugPrint('openRecruitsProvider error: $error');
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(AppStrings.battleLoadRecruitsFailed),
              );
            },
          ),
          const SizedBox(height: 24),
          Text(AppStrings.battleMyRecruits, style: Theme.of(context).textTheme.titleMedium),
          myRecruits.when(
            data: (battles) => battles.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(AppStrings.battleRecruitsEmpty),
                  )
                : Column(
                    children: battles
                        .map(
                          (battle) => ListTile(
                            title: Text(battle.title),
                            subtitle: Align(
                              alignment: Alignment.centerLeft,
                              child: BattleTypeBadge(type: battle.type),
                            ),
                            trailing: TextButton(
                              onPressed: () => _cancel(context, ref, battle.id),
                              child: const Text(AppStrings.battleRecruitCancel),
                            ),
                          ),
                        )
                        .toList(),
                  ),
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, stackTrace) {
              debugPrint('myRecruitsProvider error: $error');
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(AppStrings.battleLoadRecruitsFailed),
              );
            },
          ),
        ],
      ),
    );
  }
}
