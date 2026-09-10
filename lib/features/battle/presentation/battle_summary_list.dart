import 'package:flutter/material.dart';

import '../../../core/strings.dart';
import '../data/battle.dart';
import '../domain/battle_summary.dart';
import 'battle_chips.dart';
import 'battle_detail_screen.dart';

/// 진행 중인 대결 목록.
///
/// 제목 · 상대 · 유형 · 상태를 한 줄에 이어 붙이면 무엇이 중요한지 사라진다.
/// 제목을 크게 두고, 상대와 유형은 아래로, 지금 상태는 오른쪽 칩으로 뗀다.
class BattleSummaryList extends StatelessWidget {
  const BattleSummaryList({super.key, required this.summaries});

  final List<BattleSummary> summaries;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: summaries.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) => _BattleCard(summary: summaries[index]),
    );
  }
}

class _BattleCard extends StatelessWidget {
  const _BattleCard({required this.summary});

  final BattleSummary summary;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final Battle battle = summary.battle;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => BattleDetailScreen(battleId: battle.id)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      battle.title,
                      style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        BattleTypeBadge(type: battle.type),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            '${AppStrings.battleVersus} ${summary.otherPartyName}',
                            style: textTheme.bodySmall,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              BattleStatusChip(status: battle.status),
            ],
          ),
        ),
      ),
    );
  }
}
