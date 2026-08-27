import 'package:flutter/material.dart';

import '../../../core/strings.dart';
import '../data/battle.dart';
import '../domain/battle_summary.dart';
import 'battle_detail_screen.dart';

String battleTypeLabel(String type) {
  return type == 'speed' ? AppStrings.battleTypeSpeed : AppStrings.battleTypeQuality;
}

String battleStatusLabel(String status) {
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

class BattleSummaryList extends StatelessWidget {
  const BattleSummaryList({super.key, required this.summaries});

  final List<BattleSummary> summaries;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: summaries.length,
      itemBuilder: (context, index) {
        final summary = summaries[index];
        final Battle battle = summary.battle;
        return ListTile(
          title: Text(battle.title),
          subtitle: Text(
            '${summary.otherPartyName} · ${battleTypeLabel(battle.type)} · ${battleStatusLabel(battle.status)}',
          ),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => BattleDetailScreen(battleId: battle.id)),
          ),
        );
      },
    );
  }
}
