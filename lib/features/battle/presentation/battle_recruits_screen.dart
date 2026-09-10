import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/strings.dart';
import '../domain/battle_providers.dart';
import 'create_battle_screen.dart';

class BattleRecruitsScreen extends ConsumerWidget {
  const BattleRecruitsScreen({super.key});

  String _typeLabel(String type) {
    return type == 'speed' ? AppStrings.battleTypeSpeed : AppStrings.battleTypeQuality;
  }

  Future<void> _join(BuildContext context, WidgetRef ref, String battleId) async {
    try {
      await ref.read(battleRepositoryProvider).joinBattle(battleId);
      ref.invalidate(openRecruitsProvider);
      ref.invalidate(myBattlesProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text(AppStrings.battleJoined)));
      }
    } catch (e) {
      debugPrint('joinBattle failed: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text(AppStrings.battleJoinFailed)));
      }
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
                            subtitle:
                                Text('${recruit.creatorName} · ${_typeLabel(recruit.battle.type)}'),
                            trailing: FilledButton(
                              onPressed: () => _join(context, ref, recruit.battle.id),
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
                            subtitle: Text(_typeLabel(battle.type)),
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
