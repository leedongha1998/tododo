import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/strings.dart';
import '../../../core/theme/pixel_icons.dart';
import '../../../core/theme/retro_palette.dart';
import '../../../core/theme/retro_text.dart';
import '../../../core/widgets/evidence_photo_frame.dart';
import '../../../core/widgets/pixel_frame.dart';
import '../../../core/widgets/pixel_icon.dart';
import '../../../core/widgets/pixel_tag.dart';
import '../../../core/widgets/status_message.dart';
import '../data/battle_submission.dart';
import '../data/evidence_camera.dart';
import '../domain/battle_detail.dart';
import '../domain/battle_providers.dart';
import '../domain/submission_rules.dart';

/// 내 증거 영역(제출 창): 촬영 → 미리보기 → 제출 → 제출 완료.
///
/// 제출 즉시 판정은 없다. 판정은 사진 제출이 끝난 뒤 판정 창에서 참가자끼리 한다.
/// 품질전은 한 번만 낼 수 있어 제출 전에 확인받는다.
///
/// 활성화 판단은 전부 [BattleDetail]의 getter가 하고, 같은 검사를 서버가 다시 한다.
/// 이 위젯은 승패를 계산하지 않는다.
class MyEvidenceSection extends ConsumerStatefulWidget {
  const MyEvidenceSection({super.key, required this.detail});

  final BattleDetail detail;

  @override
  ConsumerState<MyEvidenceSection> createState() => _MyEvidenceSectionState();
}

class _MyEvidenceSectionState extends ConsumerState<MyEvidenceSection> {
  EvidenceShot? _shot;
  bool _uploading = false;

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _capture() async {
    try {
      final shot = await ref.read(evidenceCameraProvider).capture();
      if (shot == null || !mounted) return;
      setState(() => _shot = shot);
    } catch (error) {
      debugPrint('evidence capture failed: $error');
      if (mounted) _showSnackBar(AppStrings.battleEvidenceCaptureFailed);
    }
  }

  Future<void> _submit() async {
    final shot = _shot;
    if (shot == null) return;

    final battleId = widget.detail.battle.id;
    final repository = ref.read(battleRepositoryProvider);

    setState(() => _uploading = true);
    try {
      final path = await repository.uploadEvidencePhoto(battleId: battleId, bytes: shot.bytes);
      await repository.submitEvidence(
        battleId: battleId,
        objectPath: path,
        capturedAt: shot.capturedAt,
      );

      // 접수 사실은 서버에 남는다. 화면은 다시 읽어 상태(판정 창 열림 포함)를 서버 값으로 맞춘다.
      ref.invalidate(battleDetailProvider(battleId));
      ref.invalidate(myBattlesProvider);

      if (!mounted) return;
      setState(() {
        _uploading = false;
        _shot = null;
      });
    } catch (error) {
      debugPrint('submitEvidence failed: $error');
      if (!mounted) return;
      setState(() => _uploading = false);
      // 거부(촬영 시각·마감·잠금)는 코드별 문구로 알린다. 거부된 사진은 제출로 치지 않는다.
      _showSnackBar(submissionErrorMessage(error));
      ref.invalidate(battleDetailProvider(battleId));
    }
  }

  /// 품질전은 재제출이 없다. 실수로 한 번 누르면 그 사진으로 끝나므로 반드시 확인받는다.
  Future<void> _confirmAndSubmitQuality() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(AppStrings.battleEvidenceQualityConfirmTitle),
        content: const Text(AppStrings.battleEvidenceQualityConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(AppStrings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(AppStrings.battleEvidenceSubmit),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _submit();
  }

  @override
  Widget build(BuildContext context) {
    return PixelFrame.flat(
      title: AppStrings.battleEvidenceSectionTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _buildBody(context, widget.detail),
      ),
    );
  }

  List<Widget> _buildBody(BuildContext context, BattleDetail detail) {
    if (_uploading) {
      return const [StatusMessage.loading(message: AppStrings.battleEvidenceUploading)];
    }

    final mine = detail.mySubmission;
    if (detail.hasMySubmission) {
      return [_submittedBlock(context, detail, mine)];
    }

    final shot = _shot;
    if (shot != null) {
      return [
        EvidencePhotoFrame.large(image: MemoryImage(shot.bytes)),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: detail.isSpeed ? _submit : _confirmAndSubmitQuality,
          child: Text(
            detail.isSpeed
                ? AppStrings.battleEvidenceSubmit
                : AppStrings.battleEvidenceQualitySubmit,
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _capture,
          icon: const PixelIcon(PixelIcons.retry),
          label: const Text(AppStrings.battleEvidenceRetake),
        ),
      ];
    }

    // 마감이 지났는데 아직 정산 전이면 낼 수 없다(서버도 거부한다).
    if (!detail.canSubmitEvidence) {
      return const [
        PixelFrame.tone(
          tone: PixelTone.neutral,
          icon: PixelIcons.clock,
          child: Text(AppStrings.battleDeadlinePassed),
        ),
      ];
    }

    return [
      FilledButton.icon(
        onPressed: _capture,
        icon: const PixelIcon(PixelIcons.camera),
        label: const Text(AppStrings.battleEvidenceTakePhoto),
      ),
      const SizedBox(height: 8),
      Text(
        detail.isSpeed ? AppStrings.battleEvidenceSpeedHint : AppStrings.battleEvidenceQualityOnce,
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ];
  }

  /// 낸 뒤: 내 사진과 제출 시각, 그리고 판정이 언제 시작되는지.
  Widget _submittedBlock(BuildContext context, BattleDetail detail, BattleSubmission? mine) {
    final textTheme = Theme.of(context).textTheme;

    return PixelFrame.tone(
      tone: PixelTone.success,
      icon: PixelIcons.pass,
      title: AppStrings.battleEvidenceSubmittedTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (mine != null)
            Text(
              AppStrings.battleEvidenceSubmittedAt(formatEvidenceTime(mine.submittedAt)),
              style: textTheme.bodyMedium,
            ),
          const SizedBox(height: 4),
          Text(
            detail.hasOpponentSubmitted
                ? AppStrings.battleEvidenceWaitingDeadline
                : AppStrings.battleEvidenceWaitingOpponent,
            style: textTheme.bodySmall,
          ),
          if (mine?.objectPath != null) ...[
            const SizedBox(height: 8),
            _SubmissionThumbnail(path: mine!.objectPath!),
          ],
        ],
      ),
    );
  }
}

/// 상대 영역(제출 창). 사진도 시각도 보여 주지 않는다 — 서버가 내주지 않기 때문에 보여 줄 수도 없다.
/// 제출했다는 사실만 보인다.
class OpponentEvidenceSummary extends StatelessWidget {
  const OpponentEvidenceSummary({super.key, required this.detail});

  final BattleDetail detail;

  @override
  Widget build(BuildContext context) {
    return PixelFrame.flat(
      title: AppStrings.battleEvidenceOpponentTitle,
      child: Text(
        detail.hasOpponentSubmitted
            ? AppStrings.battleEvidenceOpponentSubmitted
            : AppStrings.battleEvidenceOpponentWaiting,
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }
}

/// 판정 창. 판정 화면은 4단계에서 붙는다. 그 전까지는 판정 기한이 지나면 자동 승인으로 끝난다는
/// 안내만 한다.
class JudgingWindowNotice extends StatelessWidget {
  const JudgingWindowNotice({super.key, required this.detail});

  final BattleDetail detail;

  @override
  Widget build(BuildContext context) {
    return PixelFrame.tone(
      tone: PixelTone.info,
      title: AppStrings.battleJudgingTitle,
      child: Text(
        detail.hasSomethingToJudge
            ? AppStrings.battleJudgingPreparing
            : AppStrings.battleJudgingNothingToJudge,
      ),
    );
  }
}

/// 판정 창이 열리거나 대결이 끝난 뒤 공개되는 양쪽 증거(사진 + 제출 시각 + 최소 기준 결론 + AI 사유).
///
/// 판정 창 전에는 서버(RLS)가 상대 제출 행을 아예 내주지 않는다. 열리는 시점도 서버가 정하고,
/// 화면은 받은 행을 그대로 보여 준다.
class RevealedEvidenceSection extends StatelessWidget {
  const RevealedEvidenceSection({super.key, required this.detail});

  final BattleDetail detail;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PixelFrame.flat(
          title: AppStrings.battleEvidenceSectionTitle,
          child: _submissionOrEmpty(detail.mySubmission),
        ),
        const SizedBox(height: 16),
        PixelFrame.flat(
          title: AppStrings.battleEvidenceOpponentTitle,
          child: _submissionOrEmpty(detail.opponentSubmission),
        ),
      ],
    );
  }

  // 한 번도 내지 않은 채 끝난 대결(제출 0건 무승부, 포기 등)도 있다.
  Widget _submissionOrEmpty(BattleSubmission? submission) {
    if (submission == null) return const Text(AppStrings.battleEvidenceNoSubmission);
    return _SubmissionEntry(submission: submission);
  }
}

/// 제출 한 건(시각, 최소 기준 결론, AI 사유, 사진).
class _SubmissionEntry extends StatelessWidget {
  const _SubmissionEntry({required this.submission});

  final BattleSubmission submission;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(formatEvidenceTime(submission.submittedAt), style: RetroText.numeric),
            const SizedBox(width: 8),
            PixelTag(
              label: submissionVerdictLabel(submission.meetsCriteria),
              style: _verdictTagStyle(submission.meetsCriteria),
            ),
          ],
        ),
        if (submission.reason != null) ...[
          const SizedBox(height: 4),
          Text(submission.reason!, style: textTheme.bodyMedium),
        ],
        if (submission.objectPath != null) ...[
          const SizedBox(height: 4),
          _SubmissionThumbnail(path: submission.objectPath!),
        ],
      ],
    );
  }
}

/// 비공개 버킷이라 볼 때마다 짧은 수명의 서명 URL을 받는다.
class _SubmissionThumbnail extends ConsumerWidget {
  const _SubmissionThumbnail({required this.path});

  final String path;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final urlAsync = ref.watch(evidencePhotoUrlProvider(path));

    return urlAsync.when(
      data: (url) => EvidencePhotoFrame.thumbnail(image: NetworkImage(url)),
      loading: () => const EvidencePhotoFrame.thumbnail(),
      error: (error, stackTrace) {
        debugPrint('evidencePhotoUrlProvider error: $error');
        return EvidencePhotoFrame.thumbnail(
          failed: true,
          onRetry: () => ref.invalidate(evidencePhotoUrlProvider(path)),
        );
      },
    );
  }
}

/// 통과 = 성공 면, 미달 = 위험 테두리, 판정 전 = 약한 점선.
PixelTagStyle _verdictTagStyle(bool? meetsCriteria) {
  return switch (meetsCriteria) {
    true => const PixelTagStyle(
        fill: RetroPalette.success,
        textColor: RetroPalette.surface,
        borderColor: RetroPalette.ink,
      ),
    false => const PixelTagStyle(
        fill: RetroPalette.dangerPale,
        textColor: RetroPalette.ink,
        borderColor: RetroPalette.danger,
      ),
    null => const PixelTagStyle(
        fill: Colors.transparent,
        textColor: RetroPalette.inkMuted,
        borderColor: RetroPalette.inkMuted,
        dashed: true,
      ),
  };
}

/// 서버가 준 UTC 시각을 기기 시간대의 hh:mm으로. 대결 주기상 날짜는 군더더기다.
String formatEvidenceTime(DateTime time) {
  final local = time.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}
