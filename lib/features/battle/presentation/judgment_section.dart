import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/strings.dart';
import '../../../core/theme/pixel_icons.dart';
import '../../../core/widgets/evidence_photo_frame.dart';
import '../../../core/widgets/pixel_frame.dart';
import '../../../core/widgets/pixel_loader.dart';
import '../domain/battle_detail.dart';
import '../domain/battle_providers.dart';
import '../domain/judgment_rules.dart';
import 'criteria_views.dart';

/// 상호 판정 창(`judging`)의 영역. 두 유형 공통이다.
///
/// 내가 판정할 차례면 상대 사진과 확정된 기준을 보여 주고 정해진 선택지로 답을 받는다.
/// 그 밖의 단계(판정할 것이 없음·판정 보냄·AI 재판정 중·기한 경과)에서는 서버가 기록한 값으로
/// 지금 무슨 일이 일어나고 있는지만 알린다.
///
/// **승패를 계산하지 않는다.** 단계 판단은 [BattleDetail.judgmentStage](순수 함수)가 하고,
/// 결론은 서버(`submit_judgment` → `resolve_battle`)가 낸다. 자유 텍스트 입력은 어디에도 없다.
class JudgmentSection extends ConsumerStatefulWidget {
  const JudgmentSection({super.key, required this.detail});

  final BattleDetail detail;

  @override
  ConsumerState<JudgmentSection> createState() => _JudgmentSectionState();
}

class _JudgmentSectionState extends ConsumerState<JudgmentSection> {
  /// 최소 기준 통과 여부(승인/불복). 아직 고르지 않았으면 null.
  bool? _passed;

  /// 품질전에서 더 잘했다고 고른 사람의 user id. 아직 고르지 않았으면 null.
  String? _superiorId;

  bool _sending = false;

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// 되돌릴 수 없는 판정이라 반드시 한 번 확인받는다(서버도 한 번만 받는다).
  Future<void> _confirmAndSend() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(AppStrings.battleJudgmentConfirmTitle),
        content: const Text(AppStrings.battleJudgmentConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(AppStrings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(AppStrings.battleJudgmentSend),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _send();
  }

  Future<void> _send() async {
    final passed = _passed;
    if (passed == null) return;

    final detail = widget.detail;
    final battleId = detail.battle.id;

    setState(() => _sending = true);
    try {
      await ref.read(battleRepositoryProvider).submitJudgment(
            battleId: battleId,
            passed: passed,
            // 속도전에 우열을 넘기면 서버가 거부한다.
            superiorId: detail.needsSuperiorityPick ? _superiorId : null,
          );

      // 결론은 서버에 남는다. 화면은 다시 읽어 단계·결과를 서버 값으로 맞춘다.
      ref.invalidate(battleDetailProvider(battleId));
      ref.invalidate(myBattlesProvider);

      if (!mounted) return;
      setState(() => _sending = false);
      _showSnackBar(AppStrings.battleJudgmentSent);
    } catch (error) {
      debugPrint('submitJudgment failed: $error');
      if (!mounted) return;
      setState(() => _sending = false);
      // 기한 경과·이미 판정함 같은 거부는 코드별 문구로 알리고, 서버 상태를 다시 읽는다.
      _showSnackBar(judgmentErrorMessage(error));
      ref.invalidate(battleDetailProvider(battleId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = widget.detail;

    return switch (detail.judgmentStage) {
      JudgmentStage.notOpen => const SizedBox.shrink(),
      JudgmentStage.nothingToJudge => const PixelFrame.tone(
          tone: PixelTone.info,
          icon: PixelIcons.hourglass,
          title: AppStrings.battleJudgmentNothingTitle,
          child: Text(AppStrings.battleJudgmentNothing),
        ),
      JudgmentStage.windowClosed => const PixelFrame.tone(
          tone: PixelTone.neutral,
          icon: PixelIcons.clock,
          title: AppStrings.battleJudgmentWindowClosedTitle,
          child: Text(AppStrings.battleJudgmentWindowClosed),
        ),
      JudgmentStage.waitingOpponent => const PixelFrame.tone(
          tone: PixelTone.success,
          title: AppStrings.battleJudgmentSentTitle,
          child: Text(AppStrings.battleJudgmentWaitingOpponent),
        ),
      // 3단계(AI 재판정 배선)가 오기 전에는 이 상태가 서버에서 끝나지 않는다.
      JudgmentStage.waitingAi => const PixelFrame.tone(
          tone: PixelTone.info,
          icon: PixelIcons.hourglass,
          title: AppStrings.battleJudgmentAiTitle,
          child: Text(AppStrings.battleJudgmentAi),
        ),
      JudgmentStage.myTurn => _form(context, detail),
    };
  }

  Widget _form(BuildContext context, BattleDetail detail) {
    final textTheme = Theme.of(context).textTheme;
    final path = detail.opponentSubmission?.objectPath;
    final urlAsync = path == null ? null : ref.watch(evidencePhotoUrlProvider(path));

    // 못 본 사진을 판정하게 하지 않는다. 서명 URL 발급은 서버 정책을 거치므로 여기서 막히면
    // 애초에 볼 권한이 없거나 통신이 안 되는 것이다.
    final photoReady = urlAsync != null && urlAsync.hasValue;
    final photoFailed = path == null || (urlAsync?.hasError ?? false);

    final answered = _passed != null && (!detail.needsSuperiorityPick || _superiorId != null);
    final canSend = answered && photoReady && !_sending;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PixelFrame.flat(
          title: AppStrings.battleEvidenceOpponentTitle,
          child: _photo(detail, path, urlAsync),
        ),
        const SizedBox(height: 16),
        CriteriaListBlock(
          title: AppStrings.battleCriteriaMinTitle,
          items: detail.battle.minCriteria,
          hint: AppStrings.battleCriteriaMinHint,
        ),
        if (detail.needsSuperiorityPick && detail.superiorityCriteria.isNotEmpty) ...[
          const SizedBox(height: 16),
          CriteriaListBlock(
            title: AppStrings.battleCriteriaSuperiorityTitle,
            items: detail.superiorityCriteria,
            hint: AppStrings.battleCriteriaSuperiorityHint,
          ),
        ],
        const SizedBox(height: 16),
        PixelFrame.flat(
          title: AppStrings.battleJudgmentSectionTitle,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(AppStrings.battleJudgmentIntro, style: textTheme.bodyMedium),
              const SizedBox(height: 16),
              Text(AppStrings.battleJudgmentMinQuestion, style: textTheme.bodyLarge),
              const SizedBox(height: 8),
              SegmentedButton<bool>(
                showSelectedIcon: false,
                // 아무것도 고르지 않은 상태로 시작한다(기본값을 두면 실수로 보낼 수 있다).
                emptySelectionAllowed: true,
                segments: const [
                  ButtonSegment(value: true, label: Text(AppStrings.battleJudgmentPassed)),
                  ButtonSegment(value: false, label: Text(AppStrings.battleJudgmentFailed)),
                ],
                selected: _passed == null ? const <bool>{} : {_passed!},
                onSelectionChanged: _sending
                    ? null
                    : (selection) {
                        if (selection.isEmpty) return;
                        setState(() => _passed = selection.first);
                      },
              ),
              const SizedBox(height: 4),
              Text(AppStrings.battleJudgmentRejectHint, style: textTheme.bodySmall),
              if (detail.needsSuperiorityPick) ...[
                const SizedBox(height: 16),
                Text(AppStrings.battleJudgmentSuperiorityQuestion, style: textTheme.bodyLarge),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  showSelectedIcon: false,
                  emptySelectionAllowed: true,
                  // 서버에는 상대적 값이 아니라 고른 사람의 user id가 그대로 간다(뒤집기 실수 방지).
                  segments: [
                    ButtonSegment(
                      value: detail.me.userId,
                      label: const Text(AppStrings.battleJudgmentSuperiorMe),
                    ),
                    ButtonSegment(
                      value: detail.opponent.userId,
                      label: const Text(AppStrings.battleJudgmentSuperiorOpponent),
                    ),
                  ],
                  selected: _superiorId == null ? const <String>{} : {_superiorId!},
                  onSelectionChanged: _sending
                      ? null
                      : (selection) {
                          if (selection.isEmpty) return;
                          setState(() => _superiorId = selection.first);
                        },
                ),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: canSend ? _confirmAndSend : null,
                child: _sending
                    ? const PixelLoader.small()
                    : const Text(AppStrings.battleJudgmentSend),
              ),
              const SizedBox(height: 8),
              Text(
                photoFailed
                    ? AppStrings.battleJudgmentPhotoUnavailable
                    : AppStrings.battleJudgmentOnce,
                style: textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 상대 사진. 비공개 버킷이라 볼 때마다 짧은 수명의 서명 URL을 받는다.
  Widget _photo(BattleDetail detail, String? path, AsyncValue<String>? urlAsync) {
    // 제출자가 탈퇴하면 경로가 null이 된다. 그 대결은 서버가 따로 정리하지만 화면은 버텨야 한다.
    if (path == null || urlAsync == null) {
      return const EvidencePhotoFrame.large(failed: true);
    }

    return urlAsync.when(
      data: (url) => EvidencePhotoFrame.large(image: NetworkImage(url)),
      loading: () => const EvidencePhotoFrame.large(),
      error: (error, stackTrace) {
        debugPrint('evidencePhotoUrlProvider error: $error');
        return EvidencePhotoFrame.large(
          failed: true,
          onRetry: () => ref.invalidate(evidencePhotoUrlProvider(path)),
        );
      },
    );
  }
}
