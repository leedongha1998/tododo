import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/navigation/app_tab.dart';
import '../../../core/strings.dart';
import '../../../core/widgets/pixel_loader.dart';
import '../domain/battle_providers.dart';
import 'battle_summary_list.dart';

/// `내 대결` 탭. 진행 중(active/judging)인 대결만 올라온다.
/// 끝난 대결은 프로필 전적으로 간다.
class MyBattlesScreen extends ConsumerWidget {
  const MyBattlesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final battlesAsync = ref.watch(myBattlesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.battleMyBattles)),
      // 빈 상태와 에러까지 감싸야 한다. 목록이 비었을 때야말로 새로고침이 필요하다.
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(myBattlesProvider.future),
        child: battlesAsync.when(
          data: (summaries) => summaries.isEmpty
              ? _ScrollableMessage(
                  message: AppStrings.battleMyBattlesEmpty,
                  hint: AppStrings.battleFinishedInProfile,
                  // 대결이 없을 때 할 일은 하나뿐이다 - 상대를 찾으러 가는 것.
                  action: FilledButton(
                    onPressed: () =>
                        ref.read(selectedTabProvider.notifier).select(AppTab.find),
                    child: const Text(AppStrings.battleFind),
                  ),
                )
              : BattleSummaryList(summaries: summaries),
          loading: () => const Center(child: PixelLoader.medium()),
          error: (error, stackTrace) {
            debugPrint('myBattlesProvider error: $error');
            return _ScrollableMessage(
              message: AppStrings.battleLoadListFailed,
              action: TextButton(
                onPressed: () => ref.invalidate(myBattlesProvider),
                child: const Text(AppStrings.retry),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// 당겨 새로고침이 먹으려면 안내 문구도 스크롤 가능한 위젯이어야 한다.
class _ScrollableMessage extends StatelessWidget {
  const _ScrollableMessage({required this.message, this.hint, this.action});

  final String message;
  final String? hint;
  final Widget? action;

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
        if (action != null) ...[
          const SizedBox(height: 12),
          Center(child: action),
        ],
      ],
    );
  }
}
