import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/strings.dart';
import '../domain/battle_providers.dart';
import 'battle_summary_list.dart';

/// 홈 화면 상단에 붙는 "내 대결" 요약 영역.
class HomeBattleSection extends ConsumerWidget {
  const HomeBattleSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final battlesAsync = ref.watch(myBattlesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(AppStrings.battleMyBattles, style: Theme.of(context).textTheme.titleMedium),
        ),
        Expanded(
          child: battlesAsync.when(
            data: (summaries) => summaries.isEmpty
                ? Center(child: Text(AppStrings.battleMyBattlesEmpty))
                : RefreshIndicator(
                    onRefresh: () => ref.refresh(myBattlesProvider.future),
                    child: BattleSummaryList(summaries: summaries),
                  ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stackTrace) {
              debugPrint('myBattlesProvider error: $error');
              return Center(child: Text(AppStrings.battleLoadListFailed));
            },
          ),
        ),
      ],
    );
  }
}
