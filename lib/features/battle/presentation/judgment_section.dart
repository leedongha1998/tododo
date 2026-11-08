import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/strings.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_loader.dart';
import '../../../core/widgets/app_panel.dart';
import '../../../core/widgets/evidence_photo_frame.dart';
import '../../../core/widgets/initial_badge.dart';
import '../../../core/widgets/keep_words_text.dart';
import '../domain/battle_detail.dart';
import '../domain/battle_providers.dart';
import '../domain/judgment_rules.dart';
import 'criteria_views.dart';
import 'judgment_choice.dart';

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

    final quality = detail.needsSuperiorityPick;
    final answered = _passed != null && (!quality || _superiorId != null);
    final canSend = answered && photoReady && !_sending;
    final onPassed = _sending ? null : (bool value) => setState(() => _passed = value);
    final onSuperior = _sending ? null : (String value) => setState(() => _superiorId = value);

    // 질문 하나 = 경계가 있는 단계 카드 하나. 기준은 그 질문 카드 안에 있다(design-judging-buttons 1A).
    // 품질전은 두 질문을 한 번에 묻는다 — 순서를 강제하지 않는다(어느 카드부터 골라도 된다).
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppPanel.flat(
          title: AppStrings.battleEvidenceOpponentTitle,
          child: _photo(detail, path, urlAsync),
        ),
        const SizedBox(height: 24),
        Semantics(
          header: true,
          child: KeepWordsText(
            AppStrings.battleJudgmentSectionTitle,
            style: textTheme.titleSmall!.copyWith(color: AppPalette.ink),
          ),
        ),
        const SizedBox(height: 12),
        JudgmentStepCard(
          // 속도전은 질문이 하나라 번호를 그리지 않는다(1/1은 소음).
          step: quality ? 1 : null,
          tag: AppStrings.battleCriteriaMinTitle,
          question: AppStrings.battleJudgmentMinQuestion,
          answer: switch (_passed) {
            true => AppStrings.battleJudgmentPassed,
            false => AppStrings.battleJudgmentFailed,
            null => null,
          },
          criteria: CriteriaChecklistBox(
            items: detail.battle.minCriteria,
            hint: AppStrings.battleCriteriaMinHint,
          ),
          choices: JudgmentChoicePair<bool>(
            choices: const [
              JudgmentChoiceOption(
                value: true,
                label: AppStrings.battleJudgmentPassed,
                icon: AppIcons.pass,
                iconColor: AppPalette.success,
              ),
              JudgmentChoiceOption(
                value: false,
                label: AppStrings.battleJudgmentFailed,
                icon: AppIcons.fail,
                iconColor: AppPalette.danger,
              ),
            ],
            selected: _passed,
            onSelected: onPassed,
          ),
          // 불복을 고르면 같은 자리에서 안내 블록으로 강조한다(문구는 같다).
          footer: _passed == false
              ? const JudgmentNote.emphasized(
                  key: ValueKey('judgment-reject-hint-emphasized'),
                  icon: AppIcons.aiReview,
                  text: AppStrings.battleJudgmentRejectHint,
                )
              : const JudgmentNote(
                  key: ValueKey('judgment-reject-hint'),
                  icon: AppIcons.aiReview,
                  text: AppStrings.battleJudgmentRejectHint,
                  textColor: AppPalette.inkMuted,
                ),
        ),
        if (quality) ...[
          const SizedBox(height: 12),
          JudgmentStepCard(
            step: 2,
            tag: AppStrings.battleCriteriaSuperiorityTitle,
            question: AppStrings.battleJudgmentSuperiorityQuestion,
            answer: _superiorId == null
                ? null
                : _superiorId == detail.me.userId
                    ? AppStrings.battleJudgmentSuperiorMe
                    : AppStrings.battleJudgmentSuperiorOpponent,
            // 옛 데이터는 우열 기준이 비어 있을 수 있다 — 상자만 뺀다.
            criteria: detail.superiorityCriteria.isEmpty
                ? null
                : CriteriaChecklistBox(
                    items: detail.superiorityCriteria,
                    hint: AppStrings.battleCriteriaSuperiorityHint,
                  ),
            choices: JudgmentChoicePair<String>(
              // 서버에는 상대적 값이 아니라 고른 사람의 user id가 그대로 간다(뒤집기 실수 방지).
              choices: [
                // 비교하려면 두 사진을 나란히 봐야 한다 — 칸마다 그 사람의 사진 썸네일(오너 결정 8). 판정 창이 열린
                // 뒤라 서버가 이미 양쪽 제출을 내준다(detail.submissions). 서명 URL도 같은 provider를 쓴다.
                JudgmentChoiceOption(
                  value: detail.me.userId,
                  label: AppStrings.battleJudgmentSuperiorMe,
                  badge: InitialBadge(name: detail.myName, fill: AppPalette.primary),
                  thumbnail: _ChoiceThumbnail(path: detail.mySubmission?.objectPath),
                ),
                JudgmentChoiceOption(
                  value: detail.opponent.userId,
                  label: AppStrings.battleJudgmentSuperiorOpponent,
                  badge: InitialBadge(name: detail.opponentName, fill: AppPalette.secondary),
                  thumbnail: _ChoiceThumbnail(path: detail.opponentSubmission?.objectPath),
                ),
              ],
              selected: _superiorId,
              onSelected: onSuperior,
            ),
          ),
        ],
        const SizedBox(height: 24),
        // 경고는 누르기 전에 읽혀야 한다 — 보내기 버튼 바로 위. 사진을 못 받았으면 그 자리를 위험 블록이 대신한다.
        if (photoFailed)
          const AppPanel.tone(
            tone: AppTone.danger,
            child: KeepWordsText(AppStrings.battleJudgmentPhotoUnavailable),
          )
        else
          const JudgmentNote(
            key: ValueKey('judgment-once-note'),
            icon: AppIcons.lock,
            text: AppStrings.battleJudgmentOnce,
          ),
        const SizedBox(height: 8),
        // 이 화면에서 두께가 있는 것은 이 버튼 하나다.
        FilledButton(
          onPressed: canSend ? _confirmAndSend : null,
          child: _sending
              ? const AppLoader.small()
              : const KeepWordsText(AppStrings.battleJudgmentSend),
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

/// 우열 선택 타일 위쪽의 사진 썸네일(높이 96). 비공개 버킷이라 서명 URL을 받는다 — 상대 사진은 위 큰 사진과
/// 같은 provider 값을 그대로 쓴다. 실패해도 고르는 것은 막지 않는다(판정 가능 여부는 위 큰 사진이 정한다).
class _ChoiceThumbnail extends ConsumerWidget {
  const _ChoiceThumbnail({required this.path});

  final String? path;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = this.path;
    if (path == null) return const EvidencePhotoFrame.small(failed: true);
    return ref.watch(evidencePhotoUrlProvider(path)).when(
          data: (url) => EvidencePhotoFrame.small(image: NetworkImage(url)),
          loading: () => const EvidencePhotoFrame.small(),
          error: (error, stackTrace) {
            debugPrint('evidencePhotoUrlProvider error: $error');
            return const EvidencePhotoFrame.small(failed: true);
          },
        );
  }
}

/// 판정 단계 카드(design-judging-buttons 1A.1). 질문 하나 = 카드 하나.
///
/// 머리: [step]이 있으면 단계 배지 28(미답 = primary 면 + 흰 숫자, 답함 = success 면 + 흰 체크) + 12 +
/// [꼬리표 labelMedium primaryDeep / 4 / 질문 titleSmall ink]. 그 아래 기준 상자 → 16 → 선택 타일 → 12 → [footer].
/// 카드 자체는 누를 수 없다. 낭독: 머리는 header, 배지는 읽지 않고(꼬리표·질문이 대신 읽힌다) 고른 답을 값으로 붙인다.
class JudgmentStepCard extends StatelessWidget {
  const JudgmentStepCard({
    super.key,
    required this.step,
    required this.tag,
    required this.question,
    required this.answer,
    required this.criteria,
    required this.choices,
    this.footer,
  });

  /// 단계 번호. null이면 배지를 그리지 않는다(속도전 — 질문이 하나뿐).
  final int? step;
  final String tag;
  final String question;

  /// 고른 답의 원문 라벨. 아직 안 골랐으면 null.
  final String? answer;
  final Widget? criteria;
  final Widget choices;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final step = this.step;
    final criteria = this.criteria;
    final footer = this.footer;

    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        KeepWordsText(tag, style: textTheme.labelMedium!.copyWith(color: AppPalette.primaryDeep)),
        const SizedBox(height: 4),
        KeepWordsText(question, style: textTheme.titleSmall!.copyWith(color: AppPalette.ink)),
      ],
    );

    return AppPanel.flat(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MergeSemantics(
            child: Semantics(
              header: true,
              value: answer,
              child: step == null
                  ? heading
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        JudgmentStepBadge(step: step, answered: answer != null),
                        const SizedBox(width: 12),
                        Expanded(child: heading),
                      ],
                    ),
            ),
          ),
          if (criteria != null) ...[
            const SizedBox(height: 12),
            criteria,
          ],
          const SizedBox(height: 16),
          choices,
          if (footer != null) ...[
            const SizedBox(height: 12),
            footer,
          ],
        ],
      ),
    );
  }
}

/// 단계 배지: 지름 28. 미답 = primary 면 + 흰 숫자(numberSmall 16/700, 5.41) / 답함 = success 면 + 흰 체크 20(5.33).
/// 숫자 → 체크로 모양이 바뀌므로 색에만 기대지 않는다.
class JudgmentStepBadge extends StatelessWidget {
  const JudgmentStepBadge({super.key, required this.step, required this.answered});

  final int step;
  final bool answered;

  static const size = 28.0;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        key: ValueKey('judgment-step-badge-$step'),
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: ShapeDecoration(
          color: answered ? AppPalette.success : AppPalette.primary,
          shape: const CircleBorder(),
        ),
        child: answered
            ? const Icon(AppIcons.check, size: 20, color: AppPalette.surface)
            // 원 안에 고정 크기로 둔다 — 큰 글자 배율에서 숫자가 원 밖으로 나가지 않게.
            : FittedBox(
                fit: BoxFit.scaleDown,
                child: KeepWordsText(
                  '$step',
                  style: AppText.numberSmall.copyWith(color: AppPalette.surface),
                ),
              ),
      ),
    );
  }
}

/// 아이콘 20 + 8 + bodyMedium 한 줄 안내(불복 힌트·한 번만 경고). 아이콘은 첫 줄 높이 가운데에 둔다.
/// [JudgmentNote.emphasized]는 같은 문장을 primaryPale 블록(모서리 12·안쪽 12, 아이콘 primary, 글자 ink)으로 강조한다.
class JudgmentNote extends StatelessWidget {
  const JudgmentNote({
    super.key,
    required this.icon,
    required this.text,
    this.textColor = AppPalette.ink,
  }) : emphasized = false;

  const JudgmentNote.emphasized({super.key, required this.icon, required this.text})
      : textColor = AppPalette.ink,
        emphasized = true;

  final IconData icon;
  final String text;
  final Color textColor;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final body = Theme.of(context).textTheme.bodyMedium!;
    final firstLine = MediaQuery.textScalerOf(context).scale(body.fontSize!) * body.height!;
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: firstLine,
          child: Center(
            child: Icon(
              icon,
              size: 20,
              color: emphasized ? AppPalette.primary : AppPalette.inkMuted,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: KeepWordsText(text, style: body.copyWith(color: textColor))),
      ],
    );
    if (!emphasized) return row;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const ShapeDecoration(
        color: AppPalette.primaryPale,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
      ),
      child: row,
    );
  }
}
