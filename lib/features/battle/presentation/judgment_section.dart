import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/strings.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/app_loader.dart';
import '../../../core/widgets/app_panel.dart';
import '../../../core/widgets/evidence_photo_frame.dart';
import '../../../core/widgets/keep_words_text.dart';
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: KeepWordsText(message)));
  }

  /// 되돌릴 수 없는 판정이라 반드시 한 번 확인받는다(서버도 한 번만 받는다).
  Future<void> _confirmAndSend() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const KeepWordsText(AppStrings.battleJudgmentConfirmTitle),
        content: const KeepWordsText(AppStrings.battleJudgmentConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const KeepWordsText(AppStrings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const KeepWordsText(AppStrings.battleJudgmentSend),
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
      JudgmentStage.nothingToJudge => const AppPanel.tone(
          tone: AppTone.info,
          icon: AppIcons.hourglass,
          title: AppStrings.battleJudgmentNothingTitle,
          child: KeepWordsText(AppStrings.battleJudgmentNothing),
        ),
      JudgmentStage.windowClosed => const AppPanel.tone(
          tone: AppTone.neutral,
          icon: AppIcons.clock,
          title: AppStrings.battleJudgmentWindowClosedTitle,
          child: KeepWordsText(AppStrings.battleJudgmentWindowClosed),
        ),
      JudgmentStage.waitingOpponent => const AppPanel.tone(
          tone: AppTone.success,
          title: AppStrings.battleJudgmentSentTitle,
          child: KeepWordsText(AppStrings.battleJudgmentWaitingOpponent),
        ),
      // 3단계(AI 재판정 배선)가 오기 전에는 이 상태가 서버에서 끝나지 않는다.
      JudgmentStage.waitingAi => const AppPanel.tone(
          tone: AppTone.info,
          icon: AppIcons.hourglass,
          title: AppStrings.battleJudgmentAiTitle,
          child: KeepWordsText(AppStrings.battleJudgmentAi),
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
        AppPanel.flat(
          title: AppStrings.battleEvidenceOpponentTitle,
          child: _photo(detail, path, urlAsync),
        ),
        const SizedBox(height: 24),
        CriteriaListBlock(
          title: AppStrings.battleCriteriaMinTitle,
          items: detail.battle.minCriteria,
          hint: AppStrings.battleCriteriaMinHint,
        ),
        if (detail.needsSuperiorityPick && detail.superiorityCriteria.isNotEmpty) ...[
          const SizedBox(height: 24),
          CriteriaListBlock(
            title: AppStrings.battleCriteriaSuperiorityTitle,
            items: detail.superiorityCriteria,
            hint: AppStrings.battleCriteriaSuperiorityHint,
          ),
        ],
        const SizedBox(height: 24),
        AppPanel.flat(
          title: AppStrings.battleJudgmentSectionTitle,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              KeepWordsText(AppStrings.battleJudgmentIntro, style: textTheme.bodyMedium),
              const SizedBox(height: 16),
              // 질문이 문장 속에 묻히지 않게 묶음 제목과 같은 titleSmall(design 5.5 기준 화면 2).
              KeepWordsText(AppStrings.battleJudgmentMinQuestion, style: textTheme.titleSmall),
              const SizedBox(height: 8),
              _ChoicePair<bool>(
                choices: const [
                  (true, AppStrings.battleJudgmentPassed),
                  (false, AppStrings.battleJudgmentFailed),
                ],
                selected: _passed,
                onSelected: _sending ? null : (value) => setState(() => _passed = value),
              ),
              const SizedBox(height: 8),
              KeepWordsText(AppStrings.battleJudgmentRejectHint, style: textTheme.bodyMedium),
              if (detail.needsSuperiorityPick) ...[
                const SizedBox(height: 16),
                KeepWordsText(AppStrings.battleJudgmentSuperiorityQuestion, style: textTheme.titleSmall),
                const SizedBox(height: 8),
                _ChoicePair<String>(
                  // 서버에는 상대적 값이 아니라 고른 사람의 user id가 그대로 간다(뒤집기 실수 방지).
                  choices: [
                    (detail.me.userId, AppStrings.battleJudgmentSuperiorMe),
                    (detail.opponent.userId, AppStrings.battleJudgmentSuperiorOpponent),
                  ],
                  selected: _superiorId,
                  onSelected: _sending ? null : (value) => setState(() => _superiorId = value),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: canSend ? _confirmAndSend : null,
                child: _sending
                    ? const AppLoader.small()
                    : const KeepWordsText(AppStrings.battleJudgmentSend),
              ),
              const SizedBox(height: 12),
              // 놓치면 손해 보는 문장이라 메타 크기가 아니라 bodyMedium + 안내 아이콘(design 5.5 기준 화면 2).
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 아이콘 20을 첫 줄 높이(15 × 글자 배율 × 1.6) 가운데에 맞춘다 — 큰 배율에서도 첫 줄 옆에 온다.
                  SizedBox(
                    height: MediaQuery.textScalerOf(context).scale(textTheme.bodyMedium!.fontSize!) *
                        textTheme.bodyMedium!.height!,
                    child: const Center(
                      child: Icon(AppIcons.info, size: 20, color: AppPalette.inkMuted),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: KeepWordsText(
                      photoFailed
                          ? AppStrings.battleJudgmentPhotoUnavailable
                          : AppStrings.battleJudgmentOnce,
                      style: textTheme.bodyMedium,
                    ),
                  ),
                ],
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

/// 판정 선택지 칸에서 라벨 말고 차지하는 폭(좌우 여백 + 체크 아이콘 18 + 간격 + 테두리). Material
/// `SegmentedButton`이 체크 아이콘이 붙은 칸에 쓰는 값(글자 배율에 따라 약 37–45)보다 넉넉히 잡는다.
const double _choiceChrome = 48;

/// 상호 판정의 정해진 선택지 두 칸(세그먼트). 두 판정 질문이 같이 쓴다.
///
/// - 선택을 색에만 기대지 않게 체크 아이콘을 켠다(redesign design 5.1·5.5 기준 화면 2).
/// - 아무것도 고르지 않은 상태로 시작한다(기본값을 두면 실수로 보낼 수 있다).
/// - 라벨은 어절 단위로만 줄을 바꾼다([KeepWordsText]) — "상대가 더 잘 / 했어요"처럼 끊기지 않게.
///   그래도 칸 하나에 가장 긴 어절이 안 들어가면(360dp·1.5배에서 체크가 붙은 "통과했어요") 두 칸을
///   위아래로 쌓는다. 그러면 칸이 줄 폭을 다 쓰므로 어절 안에서 잘리지 않는다.
class _ChoicePair<T extends Object> extends StatelessWidget {
  const _ChoicePair({required this.choices, required this.selected, required this.onSelected});

  /// (서버로 보낼 값, 원문 라벨).
  final List<(T, String)> choices;
  final T? selected;

  /// null이면 고를 수 없다(보내는 중).
  final ValueChanged<T>? onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelStyle =
        theme.segmentedButtonTheme.style?.textStyle?.resolve(const {WidgetState.selected}) ??
            theme.textTheme.labelLarge;
    final scaler = MediaQuery.textScalerOf(context);
    final widestWord = [
      for (final (_, label) in choices) widestWordWidth(label, style: labelStyle, textScaler: scaler),
    ].reduce(math.max);
    return LayoutBuilder(
      builder: (context, constraints) {
        final cellRoom = constraints.maxWidth / choices.length - _choiceChrome;
        final onSelected = this.onSelected;
        final selected = this.selected;
        return SegmentedButton<T>(
          direction: widestWord <= cellRoom ? Axis.horizontal : Axis.vertical,
          showSelectedIcon: true,
          emptySelectionAllowed: true,
          segments: [
            for (final (value, label) in choices)
              ButtonSegment(value: value, label: KeepWordsText(label)),
          ],
          selected: selected == null ? <T>{} : {selected},
          onSelectionChanged: onSelected == null
              ? null
              : (selection) {
                  if (selection.isEmpty) return;
                  onSelected(selection.first);
                },
        );
      },
    );
  }
}
