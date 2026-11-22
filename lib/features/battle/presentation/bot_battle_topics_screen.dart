import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/strings.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/widgets/app_loader.dart';
import '../../../core/widgets/app_panel.dart';
import '../../../core/widgets/app_tag.dart';
import '../../../core/widgets/keep_words_text.dart';
import '../../../core/widgets/status_message.dart';
import '../data/bot_battle_topic.dart';
import '../domain/battle_providers.dart';
import '../domain/bot_battle_rules.dart';
import 'battle_chips.dart';
import 'battle_detail_screen.dart';
import 'criteria_views.dart';

/// 연습 대결(봇전) 주제 고르기.
///
/// **대결 만들기와 섞지 않는다** — 그 화면은 AI 기준 생성·동의·기간 선택이 있는 다른 흐름이고,
/// 여기는 운영자가 미리 검수한 묶음에서 하나를 고르는 자리다(AI 호출이 한 번도 없다).
class BotBattleTopicsScreen extends ConsumerWidget {
  const BotBattleTopicsScreen({super.key});

  /// 시작에 성공하면 그 대결 상세로 **갈아 끼운다**(주제 목록으로 돌아가지 않는다).
  /// 남은 횟수가 줄었고, 지금 할 일은 사진을 내는 것이기 때문이다.
  Future<void> _pick(BuildContext context, WidgetRef ref, BotBattleTopic topic) async {
    final battleId = await showBotBattleStartSheet(context, topic);
    if (battleId == null || !context.mounted) return;

    ref.invalidate(botBattleTopicsProvider);
    ref.invalidate(myBattlesProvider);
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => BattleDetailScreen(battleId: battleId)),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final topicsAsync = ref.watch(botBattleTopicsProvider);

    return Scaffold(
      appBar: AppBar(title: const KeepWordsText(AppStrings.botBattleTopicsTitle)),
      body: topicsAsync.when(
        data: (data) => RefreshIndicator(
          onRefresh: () async {
            final refreshed = ref.refresh(botBattleTopicsProvider.future);
            try {
              await refreshed;
            } catch (error) {
              // 여기서 다시 던지면 당겨서 새로고침 제스처가 그대로 터진다. 사용자에게 알리는 일은
              // 아래 error 갈래가 맡는다 — 삼키지 않는다.
              debugPrint('botBattleTopicsProvider refresh failed: $error');
            }
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            // 화면 가장자리 20, 묶음 사이 24(redesign design 4.1).
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            children: _buildBody(context, ref, data),
          ),
        ),
        loading: () => const StatusMessage.loading(message: AppStrings.loading, fill: true),
        error: (error, stackTrace) {
          debugPrint('botBattleTopicsProvider error: $error');
          return StatusMessage.error(
            message: AppStrings.botBattleLoadTopicsFailed,
            fill: true,
            action: TextButton(
              onPressed: () => ref.invalidate(botBattleTopicsProvider),
              child: const KeepWordsText(AppStrings.retry),
            ),
          );
        },
      ),
    );
  }

  List<Widget> _buildBody(BuildContext context, WidgetRef ref, BotBattleTopics data) {
    final textTheme = Theme.of(context).textTheme;

    return [
      KeepWordsText(AppStrings.botBattleTopicsIntro, style: textTheme.bodyMedium),
      const SizedBox(height: 8),
      KeepWordsText(
        AppStrings.botBattleDailyLeft(data.dailyLeft, data.dailyLimit),
        style: textTheme.bodyMedium,
      ),
      // 횟수를 다 썼어도 **카드를 숨기지 않는다** — 무엇을 할 수 있는 기능인지는 보여 주고
      // "오늘은 끝"만 말한다. 탭은 막는다(서버도 `BOT_DAILY_LIMIT`으로 거부한다).
      if (!data.hasLeft) ...[
        const SizedBox(height: 12),
        const AppPanel.tone(
          tone: AppTone.neutral,
          icon: AppIcons.clock,
          child: KeepWordsText(AppStrings.botBattleDailyNone),
        ),
      ],
      const SizedBox(height: 24),
      if (data.topics.isEmpty)
        // 운영자가 주제를 전부 내린 경우. 사용자가 할 수 있는 일이 없으므로 사실만 적는다.
        const StatusMessage.empty(
          icon: AppIcons.document,
          message: AppStrings.botBattleTopicsEmpty,
        )
      else
        for (var i = 0; i < data.topics.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          _BotTopicCard(
            topic: data.topics[i],
            onTap: data.hasLeft ? () => _pick(context, ref, data.topics[i]) : null,
          ),
        ],
    ];
  }
}

/// 주제 카드 한 장. 제목 + 기간 칩 + 최소 기준 전문.
///
/// 유형 배지를 두지 않는다 — 봇전은 전부 속도전이라 구분에 쓸모가 없다.
/// 기준은 2~3줄이라 접지 않고 그대로 보여 준다(무엇을 찍어야 하는지가 고르는 근거다).
class _BotTopicCard extends StatelessWidget {
  const _BotTopicCard({required this.topic, this.onTap});

  final BotBattleTopic topic;

  /// null이면 오늘 횟수를 다 쓴 것이다(카드는 그대로 보이고 눌리지 않는다).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return AppPanel.raised(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          KeepWordsText(
            topic.title,
            style: textTheme.titleMedium,
            wrap: KeepWordsWrap.balanced,
          ),
          const SizedBox(height: 8),
          AppTag(
            label: battleDurationLabel(topic.durationMinutes),
            style: neutralTagStyle,
            leading: const Icon(AppIcons.clock, size: 16),
          ),
          const SizedBox(height: 12),
          CriteriaChecklistBox(items: topic.minCriteria),
        ],
      ),
    );
  }
}

/// 시작 확인 시트. 시작에 성공하면 새 대결 id를 돌려준다(아니면 null).
///
/// 상세로 가는 것·목록 무효화는 시트가 닫힌 뒤 호출자가 한다 — 시트 context는 그때 이미 없다.
Future<String?> showBotBattleStartSheet(BuildContext context, BotBattleTopic topic) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _BotBattleStartSheet(topic: topic),
  );
}

class _BotBattleStartSheet extends ConsumerStatefulWidget {
  const _BotBattleStartSheet({required this.topic});

  final BotBattleTopic topic;

  @override
  ConsumerState<_BotBattleStartSheet> createState() => _BotBattleStartSheetState();
}

class _BotBattleStartSheetState extends ConsumerState<_BotBattleStartSheet> {
  bool _busy = false;

  Future<void> _start() async {
    setState(() => _busy = true);
    try {
      final battleId = await ref.read(battleRepositoryProvider).startBotBattle(widget.topic.id);
      if (!mounted) return;
      Navigator.of(context).pop(battleId);
    } catch (error) {
      debugPrint('startBotBattle failed: $error');
      // 주제가 내려갔거나 횟수를 다 썼으면 목록이 낡은 것이다. 닫고 다시 읽게 한다.
      ref.invalidate(botBattleTopicsProvider);
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: KeepWordsText(botBattleStartErrorMessage(error))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final topic = widget.topic;

    return SafeArea(
      child: SingleChildScrollView(
        // 시트 가장자리 20(redesign design 4.1). 위쪽은 테마의 손잡이가 이미 띄운다.
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            KeepWordsText(AppStrings.botBattleStartConfirmTitle, style: textTheme.titleMedium),
            const SizedBox(height: 12),
            KeepWordsText(topic.title, style: textTheme.bodyLarge),
            const SizedBox(height: 8),
            AppTag(
              label: battleDurationLabel(topic.durationMinutes),
              style: neutralTagStyle,
              leading: const Icon(AppIcons.clock, size: 16),
            ),
            const SizedBox(height: 24),
            // 시작 전에 기준 전문을 보여 준다(사람 대결과 같은 규칙).
            CriteriaListBlock(
              title: AppStrings.battleCriteriaMinTitle,
              hint: AppStrings.battleCriteriaMinHint,
              items: topic.minCriteria,
            ),
            const SizedBox(height: 24),
            // 상대가 봇이라는 것·승부 방식·점수가 작은 이유·하루 3회를 **시작 전에** 말한다.
            // 봇의 목표 시각은 적지 않는다(비율도 숫자도).
            AppPanel.tone(
              tone: AppTone.info,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  KeepWordsText(AppStrings.botBattleStartNoticeBot),
                  SizedBox(height: 8),
                  KeepWordsText(AppStrings.botBattleStartNoticeScore),
                ],
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _start,
              child: _busy
                  ? const AppLoader.small()
                  : const KeepWordsText(AppStrings.botBattleStart),
            ),
          ],
        ),
      ),
    );
  }
}
