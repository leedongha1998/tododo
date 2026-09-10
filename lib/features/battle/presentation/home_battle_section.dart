import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/strings.dart';
import '../domain/battle_providers.dart';
import 'battle_summary_list.dart';

/// 홈 화면 상단에 붙는 "내 대결" 요약 영역.
///
/// 진행 중(active/judging)인 대결만 올라온다. 끝난 대결은 프로필 전적으로 간다.
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
          // 빈 상태와 에러까지 감싸야 한다. 목록이 비었을 때야말로 새로고침이 필요하다.
          child: RefreshIndicator(
            onRefresh: () => ref.refresh(myBattlesProvider.future),
            child: battlesAsync.when(
              data: (summaries) => summaries.isEmpty
                  ? const _ScrollableMessage(
                      message: AppStrings.battleMyBattlesEmpty,
                      hint: AppStrings.battleFinishedInProfile,
                    )
                  : BattleSummaryList(summaries: summaries),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stackTrace) {
                debugPrint('myBattlesProvider error: $error');
                return _ScrollableMessage(
                  message: AppStrings.battleLoadListFailed,
                  onRetry: () => ref.invalidate(myBattlesProvider),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// 당겨 새로고침이 먹으려면 안내 문구도 스크롤 가능한 위젯이어야 한다.
class _ScrollableMessage extends StatelessWidget {
  const _ScrollableMessage({required this.message, this.hint, this.onRetry});

  final String message;
  final String? hint;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
      children: [
        Text(message, textAlign: TextAlign.center),
        if (hint != null) ...[
          const SizedBox(height: 4),
          Text(
            hint!,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        if (onRetry != null) ...[
          const SizedBox(height: 8),
          Center(child: TextButton(onPressed: onRetry, child: const Text(AppStrings.retry))),
        ],
      ],
    );
  }
}
