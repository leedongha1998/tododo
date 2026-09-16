import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/strings.dart';
import '../../../core/theme/pixel_icons.dart';
import '../../../core/theme/retro_palette.dart';
import '../../../core/widgets/pixel_frame.dart';
import '../../../core/widgets/pixel_icon.dart';
import '../../../core/widgets/pixel_loader.dart';
import '../data/player_card.dart';
import '../domain/battle_detail.dart';
import '../domain/battle_providers.dart';
import 'battle_chips.dart';
import 'evidence_section.dart';
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
              if (detail.isOngoing) ...[
                // 품질전은 두 사진을 비교하는 판정 잡이 붙는 6단계까지 제출을 열지 않는다.
                if (detail.isSpeed)
                  MyEvidenceSection(detail: detail)
                else
                  const _SubmissionPreparing(),
                const SizedBox(height: 16),
                OpponentEvidenceSummary(detail: detail),
              ],
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

/// 품질전 제출 자리. 두 사진을 비교하는 AI 판정 잡이 붙기 전까지 이 안내만 둔다
/// (속도전은 [MyEvidenceSection]이 대신한다).
class _SubmissionPreparing extends StatelessWidget {
  const _SubmissionPreparing();

  @override
  Widget build(BuildContext context) {
    return const PixelFrame.tone(
      tone: PixelTone.info,
      title: AppStrings.battleSubmissionPreparingTitle,
      child: Text(AppStrings.battleSubmissionPreparing),
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
    final deadline = _deadlineText(detail);

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
        if (deadline != null) ...[
          const SizedBox(height: 8),
          Text(deadline, style: textTheme.bodySmall),
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
    final textTheme = Theme.of(context).textTheme;

    final String headline;
    final String? reason;
    final PixelIconData icon;
    // null이면 떠 있는 프레임(승리 — 가장 강한 결과). 나머지는 성격별 안내 블록.
    final PixelTone? tone;

    if (detail.didIWin) {
      headline = AppStrings.battleYouWon;
      reason = detail.didOpponentForfeit ? AppStrings.battleWonByForfeit : null;
      icon = PixelIcons.trophy;
      tone = null;
    } else if (detail.didILose) {
      headline = AppStrings.battleYouLost;
      reason = detail.didIForfeit ? AppStrings.battleLostByForfeit : null;
      // 얼굴 아이콘 금지 규칙 때문에 표정 대신 아래로 꺾인 화살표.
      icon = PixelIcons.lose;
      tone = PixelTone.neutral;
    } else if (detail.isDraw) {
      headline = AppStrings.battleDrawMessage;
      reason = null;
      icon = PixelIcons.hourglass;
      // 무승부는 잘못된 일이 아니다. 위험색이 아니라 중립.
      tone = PixelTone.neutral;
    } else if (detail.isVoided) {
      headline = AppStrings.battleVoidedMessage;
      reason = null;
      icon = PixelIcons.warning;
      // 사용자 잘못이 아니고 점수에도 반영되지 않는 약한 끝. 위험색을 쓰지 않는다.
      tone = PixelTone.neutral;
    } else {
      return const SizedBox.shrink();
    }

    // 헤드라인은 문장이라 픽셀 글꼴이 아니라 본문 글꼴이다(결정 A).
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          headline,
          style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        if (reason != null) ...[
          const SizedBox(height: 4),
          Text(reason, style: textTheme.bodyMedium),
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

// 진행 중인 대결에만 마감을 말한다. 끝난 대결에서는 결과가 이미 답이다.
String? _deadlineText(BattleDetail detail) {
  final deadline = detail.battle.deadlineAt;
  if (deadline == null || !detail.isOngoing) return null;

  final left = deadline.difference(DateTime.now());
  if (left.isNegative) return AppStrings.battleDeadlinePassed;

  return '${AppStrings.battleDeadlineLabel} ${_formatDateTime(deadline)}'
      ' · ${AppStrings.battleDeadlineLeft(_formatRemaining(left))}';
}

String _formatRemaining(Duration gap) {
  if (gap.inDays > 0) return '${gap.inDays}일';
  if (gap.inHours > 0) return '${gap.inHours}시간';
  if (gap.inMinutes > 0) return '${gap.inMinutes}분';
  return '${gap.inSeconds}초';
}
