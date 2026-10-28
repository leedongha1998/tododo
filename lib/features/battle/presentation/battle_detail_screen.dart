import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/strings.dart';
import '../../../core/theme/pixel_icons.dart';
import '../../../core/theme/retro_palette.dart';
import '../../../core/theme/retro_text.dart';
import '../../../core/widgets/pixel_frame.dart';
import '../../../core/widgets/pixel_icon.dart';
import '../../../core/widgets/pixel_loader.dart';
import '../data/player_card.dart';
import '../domain/battle_detail.dart';
import '../domain/battle_outcome.dart';
import '../domain/battle_providers.dart';
import 'battle_chips.dart';
import 'evidence_section.dart';
import 'judgment_section.dart';
import 'player_card_view.dart';
import 'vs_intro.dart';

class BattleDetailScreen extends ConsumerWidget {
  const BattleDetailScreen({super.key, required this.battleId});

  final String battleId;

  // 포기는 곧 패배라 되돌릴 수 없다. 반드시 한 번 확인받는다.
  Future<void> _forfeit(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(AppStrings.battleForfeitConfirmTitle),
        content: const Text(AppStrings.battleForfeitConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(AppStrings.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(AppStrings.battleForfeit),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await ref.read(battleRepositoryProvider).forfeitBattle(battleId);
      ref.invalidate(battleDetailProvider(battleId));
      ref.invalidate(myBattlesProvider);
      if (context.mounted) _showSnackBar(context, AppStrings.battleForfeitDone);
    } catch (e) {
      debugPrint('forfeitBattle failed: $e');
      if (context.mounted) _showSnackBar(context, AppStrings.battleForfeitFailed);
    }
  }

  void _showSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(battleDetailProvider(battleId));

    return Scaffold(
      // 어느 대결을 보고 있는지가 제목이어야 한다. 목록으로 돌아가지 않아도 구분된다.
      appBar: AppBar(
        title: Text(detailAsync.value?.battle.title ?? AppStrings.battleMyBattles),
      ),
      body: detailAsync.when(
        data: (detail) => RefreshIndicator(
          onRefresh: () => ref.refresh(battleDetailProvider(battleId).future),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // 화면에 보이지 않는 판단 전용 조각. 배치는 바뀌지 않는다.
              _VsIntroOnFirstEntry(detail: detail),
              _BattleHeader(detail: detail),
              const SizedBox(height: 16),
              _ResultBanner(detail: detail),
              // 상호 판정 창. 내 차례면 판정 섹션이 상대 사진을 크게 보여 주므로 양쪽 증거
              // 블록을 겹쳐 그리지 않는다. 판정을 보낸 뒤에는 두 사진을 함께 보여 준다.
              if (detail.isJudging) ...[
                JudgmentSection(detail: detail),
                if (!detail.isMyJudgmentTurn && detail.submissions.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  RevealedEvidenceSection(detail: detail),
                ],
              ] else if (detail.isOngoing) ...[
                MyEvidenceSection(detail: detail),
                const SizedBox(height: 16),
                OpponentEvidenceSummary(detail: detail),
              ]
              // 종결 뒤에는 서버가 상대 제출까지 내준다. 그때만 양쪽 이력을 함께 보여 준다.
              else if (detail.areSubmissionsRevealed && detail.submissions.isNotEmpty)
                RevealedEvidenceSection(detail: detail),
              if (detail.canForfeit) ...[
                const Divider(height: 32),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => _forfeit(context, ref),
                    style: TextButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                    ),
                    icon: const PixelIcon(PixelIcons.flag),
                    label: const Text(AppStrings.battleForfeit),
                  ),
                ),
              ],
            ],
          ),
        ),
        loading: () => const Center(child: PixelLoader.medium()),
        error: (error, stackTrace) {
          debugPrint('battleDetailProvider error: $error');
          return Center(child: Text(AppStrings.battleLoadDetailFailed));
        },
      ),
    );
  }
}

/// 유형, 현재 상태, 진행 중이면 마감까지 남은 시간.
class _BattleHeader extends StatelessWidget {
  const _BattleHeader({required this.detail});

  final BattleDetail detail;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    // 제출 창과 판정 창은 다른 시계다. 한 줄로 합치면 "1분 대결이 하루 걸린다"로 읽힌다.
    final submitDeadline = _submitDeadlineText(detail);
    final judgeDeadline = _judgeDeadlineText(detail);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            BattleTypeBadge(type: detail.battle.type),
            const SizedBox(width: 8),
            BattleStatusChip(status: detail.battle.status),
          ],
        ),
        if (submitDeadline != null) ...[
          const SizedBox(height: 8),
          Text(submitDeadline, style: textTheme.bodySmall),
        ],
        if (judgeDeadline != null) ...[
          const SizedBox(height: 4),
          Text(judgeDeadline, style: textTheme.bodySmall),
        ],
        const SizedBox(height: 12),
        _OpponentCard(detail: detail),
      ],
    );
  }
}

/// 누구와 겨루고 있는지. 전적은 서버가 대결 상대에게만 내준다.
class _OpponentCard extends ConsumerWidget {
  const _OpponentCard({required this.detail});

  final BattleDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cardAsync = ref.watch(playerCardProvider(detail.opponent.userId));

    return PixelFrame.raised(
      child: cardAsync.when(
        data: (card) => PlayerCardView(card: card, label: AppStrings.battleOpponent),
        // 전적을 못 읽어도 상대가 누구인지는 보여 준다.
        loading: () => const Center(child: PixelLoader.small()),
        error: (error, stackTrace) {
          debugPrint('playerCardProvider error: $error');
          return PlayerCardView(
            card: PlayerCard(
              userId: detail.opponent.userId,
              displayName: detail.opponentName,
            ),
            label: AppStrings.battleOpponent,
          );
        },
      ),
    );
  }
}

/// 끝난 대결의 결과. 본문에 섞인 한 줄이 아니라 눈에 띄는 블록으로 보여준다.
/// 진행 중이면 아무것도 그리지 않는다.
class _ResultBanner extends StatelessWidget {
  const _ResultBanner({required this.detail});

  final BattleDetail detail;

  @override
  Widget build(BuildContext context) {
    // 결과는 서버가 정한 status·outcome에서 나온다. 진행 중이면 아직 결과가 없다.
    final result = detail.result;
    if (result == null) return const SizedBox.shrink();

    final textTheme = Theme.of(context).textTheme;

    final String headline;
    final PixelIconData icon;
    // null이면 떠 있는 프레임(승리 — 가장 강한 결과). 나머지는 성격별 안내 블록.
    final PixelTone? tone;

    switch (result) {
      case BattleResult.win:
        headline = AppStrings.battleYouWon;
        icon = PixelIcons.trophy;
        tone = null;
      case BattleResult.loss:
        headline = AppStrings.battleYouLost;
        // 얼굴 아이콘 금지 규칙 때문에 표정 대신 아래로 꺾인 화살표.
        icon = PixelIcons.lose;
        tone = PixelTone.neutral;
      case BattleResult.draw:
        headline = AppStrings.battleDrawMessage;
        icon = PixelIcons.hourglass;
        // 무승부는 잘못된 일이 아니다. 위험색이 아니라 중립.
        tone = PixelTone.neutral;
      case BattleResult.voided:
        headline = AppStrings.battleVoidedMessage;
        icon = PixelIcons.warning;
        // 사용자 잘못이 아니고 점수에도 반영되지 않는 약한 끝. 위험색을 쓰지 않는다.
        tone = PixelTone.neutral;
    }

    final subtitle = _subtitleOf(detail);
    // 서버가 기록한 품질전 판정 사유. 링크·서식 해석 없는 일반 텍스트다.
    // 속도전 제출별 사유는 아래 제출 이력에 있다.
    final reason = detail.verdictReason;
    final scoreDelta = detail.myScoreDelta;

    // 헤드라인은 문장이라 픽셀 글꼴이 아니라 본문 글꼴이다(결정 A).
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          headline,
          style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(subtitle, style: textTheme.bodyMedium),
        ],
        if (reason != null) ...[
          const SizedBox(height: 8),
          Text(AppStrings.battleVerdictReasonLabel, style: textTheme.bodySmall),
          const SizedBox(height: 2),
          Text(reason, style: textTheme.bodyMedium),
        ],
        // 점수는 서버가 하한(0)까지 적용해 반영한 값이다. 앱이 다시 계산하지 않는다.
        if (scoreDelta != null) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Text(AppStrings.battleScoreChangeLabel, style: textTheme.bodySmall),
              const SizedBox(width: 8),
              Text(AppStrings.battleScoreDelta(scoreDelta), style: RetroText.numeric),
            ],
          ),
          // 0점인 사람은 더 깎이지 않는다. 표가 말하는 -3과 달라 보이므로 이유를 적는다.
          if (scoreDelta == 0) ...[
            const SizedBox(height: 2),
            Text(AppStrings.battleScoreFloorNote, style: textTheme.bodySmall),
          ],
        ],
      ],
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: SizedBox(
        width: double.infinity,
        child: tone == null
            ? PixelFrame.raised(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PixelIcon(icon, color: RetroPalette.ink),
                    const SizedBox(width: 12),
                    Expanded(child: content),
                  ],
                ),
              )
            : PixelFrame.tone(
                tone: tone,
                icon: icon,
                padding: const EdgeInsets.all(16),
                child: content,
              ),
      ),
    );
  }
}

/// 결과 아래에 붙는 한 줄 설명. 전부 서버가 기록한 값(포기자, outcome, 상대 제출 여부)에서 고른다.
/// 승패를 다시 정하지 않는다.
String? _subtitleOf(BattleDetail detail) {
  if (detail.didIForfeit) return AppStrings.battleLostByForfeit;
  if (detail.didOpponentForfeit) return AppStrings.battleWonByForfeit;
  // 속도전에서 졌지만 기준은 통과한 경우. 감점이 -3이 아니라 -1인 이유를 말해 준다.
  if (detail.didICompleteButLose) return AppStrings.battleCompletedLoss;
  // 품질전에서 상대가 끝내 내지 않아 AI 판정 없이 이긴 경우.
  if (detail.didIWinByOpponentNoShow) return AppStrings.battleWonByOpponentNoShow;
  return null;
}

/// 매칭된 대결에 이번 진입에서 처음 데이터가 도착했을 때 한 번만 VS 인트로를 판단한다.
/// 모집을 올린 사람의 모든 진입 경로(내 대결 카드 등)를 이 한 곳이 덮는다. 참가자는 참가 직후
/// 이미 기록했으므로 여기서 다시 뜨지 않는다. 새로고침으로 다시 그려져도 상태가 남아 재판단하지 않는다.
class _VsIntroOnFirstEntry extends ConsumerStatefulWidget {
  const _VsIntroOnFirstEntry({required this.detail});

  final BattleDetail detail;

  @override
  ConsumerState<_VsIntroOnFirstEntry> createState() => _VsIntroOnFirstEntryState();
}

class _VsIntroOnFirstEntryState extends ConsumerState<_VsIntroOnFirstEntry> {
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    // 상세 화면이 먼저 그려진 뒤 띄워, 인트로가 닫히면 곧바로 상세가 보인다.
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  void _check() {
    if (_checked || !mounted) return;
    _checked = true;
    final detail = widget.detail;
    maybeShowVsIntro(
      context,
      store: ref.read(vsIntroSeenStoreProvider),
      userId: detail.me.userId,
      battleId: detail.battle.id,
      status: detail.battle.status,
      myName: detail.myName,
      opponentName: detail.opponentName,
    );
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

// 서버가 준 UTC 시각을 기기 시간대로 바꿔 보여준다. 연도는 대결 주기상 군더더기라 뺀다.
String _formatDateTime(DateTime time) {
  final local = time.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.month}월 ${local.day}일 $hour:$minute';
}

// 사진을 낼 수 있는 시간(제출 창). 진행 중인 대결에만 말한다 — 끝난 대결에서는 결과가 이미 답이다.
// 판정 창에서도 보여 준다: 제출은 끝났고 지금은 판정 중이라는 것이 두 줄로 읽혀야 한다.
String? _submitDeadlineText(BattleDetail detail) {
  final deadline = detail.battle.deadlineAt;
  if (deadline == null || !detail.isOngoing) return null;

  final left = deadline.difference(DateTime.now());
  if (left.isNegative) {
    return '${AppStrings.battleSubmitDeadlineLabel} · ${AppStrings.battleDeadlineClosed}';
  }

  return '${AppStrings.battleSubmitDeadlineLabel} ${_formatDateTime(deadline)}'
      ' · ${AppStrings.battleDeadlineLeft(_formatRemaining(left))}';
}

// 서로 판정할 수 있는 시간(판정 창). 서버가 창을 열 때 기록한 judge_deadline_at을 그대로 보여 준다.
String? _judgeDeadlineText(BattleDetail detail) {
  final deadline = detail.judgeDeadlineAt;
  if (deadline == null || !detail.isOngoing) return null;

  final left = deadline.difference(DateTime.now());
  if (left.isNegative) {
    return '${AppStrings.battleJudgeDeadlineLabel} · ${AppStrings.battleJudgeDeadlineClosed}';
  }

  return '${AppStrings.battleJudgeDeadlineLabel} ${_formatDateTime(deadline)}'
      ' · ${AppStrings.battleDeadlineLeft(_formatRemaining(left))}';
}

String _formatRemaining(Duration gap) {
  if (gap.inDays > 0) return '${gap.inDays}일';
  if (gap.inHours > 0) return '${gap.inHours}시간';
  if (gap.inMinutes > 0) return '${gap.inMinutes}분';
  return '${gap.inSeconds}초';
}
