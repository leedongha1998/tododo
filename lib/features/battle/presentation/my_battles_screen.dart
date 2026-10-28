import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/navigation/app_tab.dart';
import '../../../core/strings.dart';
import '../../../core/widgets/pixel_frame.dart';
import '../../../core/widgets/pixel_tag.dart';
import '../../../core/widgets/status_message.dart';
import '../data/battle.dart';
import '../domain/battle_providers.dart';
import '../domain/battle_summary.dart';
import 'battle_chips.dart';
import 'battle_summary_list.dart';
import 'edit_recruit_criteria_screen.dart';

/// `내 대결` 탭. "내가 지금 걸어 둔 것 전부"가 모이는 자리다.
///
/// 두 구역을 **섞지 않는다.** 모집 중은 "기다린다 / 고친다 / 취소한다"이고 상대도 마감도 없으며,
/// 진행 중은 "사진을 낸다 / 상대 증거를 판정한다"이고 마감이 흐른다. 같은 카드 모양으로 끼워 넣으면
/// 상대·상태 줄이 빈칸이 되어 목록이 말하려는 것이 흐려진다.
/// 끝난 대결은 지금처럼 프로필 전적으로 간다.
class MyBattlesScreen extends ConsumerWidget {
  const MyBattlesScreen({super.key});

  Future<void> _cancel(
    BuildContext context,
    WidgetRef ref,
    String battleId,
  ) async {
    try {
      await ref.read(battleRepositoryProvider).cancelBattle(battleId);
      ref.invalidate(myRecruitsProvider);
      ref.invalidate(myLimitsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(AppStrings.battleRecruitCancelled)),
        );
      }
    } catch (e) {
      debugPrint('cancelBattle failed: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(AppStrings.battleRecruitCancelFailed)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final battlesAsync = ref.watch(myBattlesProvider);
    final recruitsAsync = ref.watch(myRecruitsProvider);
    final recruits = recruitsAsync.value ?? const <Battle>[];

    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.battleMyBattles)),
      // 빈 상태와 에러까지 감싸야 한다. 목록이 비었을 때야말로 새로고침이 필요하다.
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(myRecruitsProvider);
          ref.invalidate(myLimitsProvider);
          final refreshed = ref.refresh(myBattlesProvider.future);
          try {
            await refreshed;
          } catch (error) {
            debugPrint('myBattlesProvider refresh failed: $error');
          }
        },
        child: ListView(
          // 목록이 비었을 때도 당겨지게 한다.
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            ..._buildRecruitSection(context, ref, recruitsAsync),
            ..._buildBattleSection(context, ref, battlesAsync, recruits),
          ],
        ),
      ),
    );
  }

  /// 구역 A — 내가 등록한 모집. 모집 중 대결은 사용자당 1개라 **항상 0건 또는 1건**이고,
  /// 0건이면 구역 자체가 보이지 않는다. 한 구역의 실패가 다른 구역을 가리지 않는다.
  List<Widget> _buildRecruitSection(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<Battle>> recruitsAsync,
  ) {
    // 이전 값이 남아 있어도 실패를 숨기지 않는다(riverpod은 실패해도 직전 값을 들고 있다).
    // 모집은 취소·매칭으로 사라지는 것이라, 낡은 값을 그대로 두면 없는 모집에 기준 수정을 시도하게 된다.
    if (recruitsAsync.hasError) {
      debugPrint('myRecruitsProvider error: ${recruitsAsync.error}');
      return [
        StatusMessage.error(
          message: AppStrings.battleLoadRecruitsFailed,
          action: TextButton(
            onPressed: () => ref.invalidate(myRecruitsProvider),
            child: const Text(AppStrings.retry),
          ),
        ),
        const SizedBox(height: 16),
      ];
    }

    final recruits = recruitsAsync.value;
    if (recruits == null) {
      return const [StatusMessage.loading(), SizedBox(height: 16)];
    }
    if (recruits.isEmpty) return const [];

    return [
      for (final battle in recruits) ...[
        // 제목 띠가 있는 창이 "여기부터 다른 성격"을 말하므로 구분선을 따로 긋지 않는다.
        PixelFrame.flat(
          title: AppStrings.battleMyRecruits,
          child: _MyRecruitBody(
            battle: battle,
            onCancel: () => _cancel(context, ref, battle.id),
          ),
        ),
        const SizedBox(height: 16),
      ],
    ];
  }

  /// 구역 B — 진행 중인 대결. 카드와 상세 진입은 그대로다. 머리글은 두지 않는다 —
  /// 탭 이름이 이미 `내 대결`이고, 이 목록이 지금과 똑같이 보이는 것이 변화가 가장 적다.
  List<Widget> _buildBattleSection(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<BattleSummary>> battlesAsync,
    List<Battle> recruits,
  ) {
    return [
      battlesAsync.when(
        data: (summaries) {
          if (summaries.isNotEmpty) {
            return Column(children: battleSummaryCards(summaries));
          }
          // 모집 1건이 있으면 "비었다"가 아니다. 그 구역이 이미 "기다리는 중"을 말하고 있으므로
          // 찾기 탭으로 보내는 버튼을 두 번 권하지 않는다.
          if (recruits.isNotEmpty) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                AppStrings.battleNoActiveBattlesYet,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            );
          }
          // 대결도 모집도 없을 때 할 일은 하나뿐이다 — 상대를 찾으러 가는 것.
          return StatusMessage.empty(
            message: AppStrings.battleMyBattlesEmpty,
            detail: AppStrings.battleFinishedInProfile,
            action: FilledButton(
              onPressed: () =>
                  ref.read(selectedTabProvider.notifier).select(AppTab.find),
              child: const Text(AppStrings.battleFind),
            ),
          );
        },
        loading: () => const StatusMessage.loading(),
        error: (error, stackTrace) {
          debugPrint('myBattlesProvider error: $error');
          return StatusMessage.error(
            message: AppStrings.battleLoadListFailed,
            action: TextButton(
              onPressed: () => ref.invalidate(myBattlesProvider),
              child: const Text(AppStrings.retry),
            ),
          );
        },
      ),
    ];
  }
}

/// 모집 구역의 안쪽. 할 수 있는 일은 지금과 같다(기준 수정, 모집 취소) — 새 기능을 더하지 않는다.
class _MyRecruitBody extends StatelessWidget {
  const _MyRecruitBody({required this.battle, required this.onCancel});

  final Battle battle;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          battle.title,
          style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            BattleTypeBadge(type: battle.type),
            const SizedBox(width: 8),
            // 점선 = 빈 자리(아직 상대가 없다).
            PixelTag(
              label: battleStatusLabel('pending'),
              style: battleStatusTagStyle('pending'),
            ),
            const SizedBox(width: 8),
            PixelTag(
              label: battleDurationLabel(battle.durationMinutes),
              style: battleStatusTagStyle('draw'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // "아직 아무도 안 들어왔다"는 사실 자체가 이 구역의 의미다.
        Text(AppStrings.battleMyRecruitWaiting, style: textTheme.bodySmall),
        const SizedBox(height: 12),
        // 매칭 전까지는 기준을 고칠 수 있다. 매칭된 뒤에는 서버가 거부한다.
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            OutlinedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => EditRecruitCriteriaScreen(battle: battle),
                ),
              ),
              child: const Text(AppStrings.battleCriteriaEditRecruit),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: onCancel,
              child: const Text(AppStrings.battleRecruitCancel),
            ),
          ],
        ),
      ],
    );
  }
}
