import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/strings.dart';
import '../data/battle.dart';
import '../domain/battle_providers.dart';
import 'battle_detail_screen.dart';

class MyBattlesScreen extends ConsumerWidget {
  const MyBattlesScreen({super.key});

  String _typeLabel(String type) {
    return type == 'speed' ? AppStrings.battleTypeSpeed : AppStrings.battleTypeQuality;
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'active':
        return AppStrings.battleStatusActive;
      case 'judging':
        return AppStrings.battleStatusJudging;
      case 'finished':
        return AppStrings.battleStatusFinished;
      case 'disputed':
        return AppStrings.battleStatusDisputed;
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final battlesAsync = ref.watch(myBattlesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.battleMyBattles)),
      body: battlesAsync.when(
        data: (summaries) {
          if (summaries.isEmpty) {
            return Center(child: Text(AppStrings.battleMyBattlesEmpty));
          }
          return RefreshIndicator(
            onRefresh: () => ref.refresh(myBattlesProvider.future),
            child: ListView.builder(
              itemCount: summaries.length,
              itemBuilder: (context, index) {
                final summary = summaries[index];
                final Battle battle = summary.battle;
                return ListTile(
                  title: Text(battle.title),
                  subtitle: Text(
                    '${summary.otherPartyName} · ${_typeLabel(battle.type)} · ${_statusLabel(battle.status)}',
                  ),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => BattleDetailScreen(battleId: battle.id)),
                  ),
                );
              },
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) {
          debugPrint('myBattlesProvider error: $error');
          return Center(child: Text(AppStrings.battleLoadListFailed));
        },
      ),
    );
  }
}
