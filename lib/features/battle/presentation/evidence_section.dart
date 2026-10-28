import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/strings.dart';
import '../../../core/theme/pixel_icons.dart';
import '../../../core/theme/retro_text.dart';
import '../../../core/widgets/evidence_photo_frame.dart';
import '../../../core/widgets/pixel_frame.dart';
import '../../../core/widgets/pixel_icon.dart';
import '../../../core/widgets/status_message.dart';
import '../data/battle_submission.dart';
import '../data/evidence_camera.dart';
import '../domain/battle_detail.dart';
import '../domain/battle_providers.dart';
import '../domain/submission_rules.dart';

/// 내 증거 영역: 촬영 → 미리보기 → 제출(또는 교체).
///
/// 제출 즉시 판정하지 않는다 — 판정은 마감(또는 양쪽 제출) 뒤 상호 판정 창에서 일어나고,
/// 그 화면은 4단계에서 만든다. 여기서는 "낼 수 있는가"만 다룬다.
///
/// 속도전은 상대가 아직 내지 않은 동안에만 사진을 바꿀 수 있고, 바꾸면 제출 시각이 다시
/// 기록된다. 품질전은 한 번만 낼 수 있다(확인 다이얼로그).
///
/// 활성화 판단은 전부 [BattleDetail]의 getter가 하고, 같은 검사를 서버가 다시 한다.
/// 이 위젯은 승패를 계산하지 않는다 — 서버가 준 값을 그대로 보여 준다.
class MyEvidenceSection extends ConsumerStatefulWidget {
  const MyEvidenceSection({super.key, required this.detail});

  final BattleDetail detail;

  @override
  ConsumerState<MyEvidenceSection> createState() => _MyEvidenceSectionState();
}

enum _Stage { idle, uploading, submitting }

class _MyEvidenceSectionState extends ConsumerState<MyEvidenceSection> {
  EvidenceShot? _shot;

  _Stage _stage = _Stage.idle;

  bool get _busy => _stage != _Stage.idle;

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

    setState(() => _stage = _Stage.uploading);
    try {
      final path = await repository.uploadEvidencePhoto(battleId: battleId, bytes: shot.bytes);
      if (mounted) setState(() => _stage = _Stage.submitting);

      await repository.submitEvidence(
        battleId: battleId,
        objectPath: path,
        capturedAt: shot.capturedAt,
      );

      // 결과는 서버에 남는다. 화면은 다시 읽어 상태·제출 여부를 서버 값으로 맞춘다.
      ref.invalidate(battleDetailProvider(battleId));
      ref.invalidate(myBattlesProvider);

      if (!mounted) return;
      setState(() {
        _stage = _Stage.idle;
        _shot = null;
      });
    } catch (error) {
      debugPrint('submitEvidence failed: $error');
      if (!mounted) return;
      setState(() => _stage = _Stage.idle);
      // 거부(촬영 시각·마감·잠금)는 코드별 문구로 알린다.
      _showSnackBar(submissionErrorMessage(error));
      ref.invalidate(battleDetailProvider(battleId));
    }
  }

  /// 품질전은 재제출이 없다(결정 14). 실수로 한 번 누르면 그 사진으로 끝나므로 반드시 확인받는다.
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
    final detail = widget.detail;

    return PixelFrame.flat(
      title: AppStrings.battleEvidenceSectionTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _buildBody(context, detail),
      ),
    );
  }

  List<Widget> _buildBody(BuildContext context, BattleDetail detail) {
    if (_busy) {
      return [
        StatusMessage.loading(
          message: _stage == _Stage.uploading
              ? AppStrings.battleEvidenceUploading
              : AppStrings.battleEvidenceSubmitting,
        ),
      ];
    }

    // 상호 판정 창. 판정 화면 자체는 4단계 몫이다.
    if (detail.isJudging) {
      return const [_JudgingPlaceholder()];
    }

    return detail.isSpeed ? _speedBody(context, detail) : _qualityBody(context, detail);
  }

  List<Widget> _speedBody(BuildContext context, BattleDetail detail) {
    final shot = _shot;
    if (shot != null) {
      return [
        EvidencePhotoFrame.large(image: MemoryImage(shot.bytes)),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _submit,
          child: const Text(AppStrings.battleEvidenceSubmit),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _capture,
          icon: const PixelIcon(PixelIcons.retry),
          label: const Text(AppStrings.battleEvidenceRetake),
        ),
      ];
    }

    if (detail.isReplacingEvidence) {
      return [
        const PixelFrame.tone(
          tone: PixelTone.neutral,
          icon: PixelIcons.camera,
          child: Text(AppStrings.battleEvidenceSubmittedWaitingOpponent),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _capture,
          icon: const PixelIcon(PixelIcons.retry),
          label: const Text(AppStrings.battleEvidenceReplace),
        ),
        const SizedBox(height: 4),
        Text(
          AppStrings.battleEvidenceReplaceHint,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ];
    }

    // 마감이 지났는데 아직 정산 전이면 낼 수 없다(서버도 거부한다).
    if (!detail.canSubmitEvidence) {
      return [
        if (detail.isPastDeadline(DateTime.now()))
          const PixelFrame.tone(
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
    ];
  }

  /// 품질전: 한 번 내면 상대를 기다리고, 두 사진이 모두 올라오면 판정 창이 열린다.
  /// 판정 결과(승패·사유)는 종결 뒤 결과 배너가 서버 값으로 보여 준다 — 여기서는 판단하지 않는다.
  List<Widget> _qualityBody(BuildContext context, BattleDetail detail) {
    if (detail.me.hasSubmitted) {
      return const [
        PixelFrame.tone(
          tone: PixelTone.success,
          title: AppStrings.battleEvidenceQualitySubmittedTitle,
          child: Text(AppStrings.battleEvidenceQualityWaiting),
        ),
      ];
    }

    final shot = _shot;
    if (shot != null) {
      return [
        EvidencePhotoFrame.large(image: MemoryImage(shot.bytes)),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _confirmAndSubmitQuality,
          child: const Text(AppStrings.battleEvidenceQualitySubmit),
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
        AppStrings.battleEvidenceQualityOnce,
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ];
  }
}

/// 상호 판정 창 안내. 속도전·품질전 공통이고, 실제 판정 버튼은 4단계에서 붙는다.
class _JudgingPlaceholder extends StatelessWidget {
  const _JudgingPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const PixelFrame.tone(
      tone: PixelTone.info,
      icon: PixelIcons.hourglass,
      title: AppStrings.battleJudgingPlaceholderTitle,
      child: Text(AppStrings.battleJudgingPlaceholder),
    );
  }
}

/// 상대 영역. 마감 전(판정 창이 열리기 전)에는 "제출했다"는 사실 하나만 보여 준다 —
/// 사진·시각·통과 여부는 서버가 내주지 않기 때문에 보여 줄 수도 없다(결정 D2).
class OpponentEvidenceSummary extends StatelessWidget {
  const OpponentEvidenceSummary({super.key, required this.detail});

  final BattleDetail detail;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return PixelFrame.flat(
      title: AppStrings.battleEvidenceOpponentTitle,
      child: Text(
        detail.hasOpponentSubmitted
            ? AppStrings.battleEvidenceOpponentSubmitted
            : AppStrings.battleEvidenceOpponentWaiting,
        style: textTheme.bodyMedium,
      ),
    );
  }
}

/// 판정 창이 열리거나 종결된 뒤 공개되는 양쪽 증거(사진 + 사유, 있으면).
///
/// 그전에는 서버(RLS)가 상대 제출 행을 아예 내주지 않으므로 이 위젯이 그릴 것도 없다.
/// 공개 시점도 서버가 정하고, 화면은 받은 행을 그대로 보여 주기만 한다.
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

  // 한 번도 내지 않은 채 끝난 대결(마감 무승부, 포기 등)도 있다.
  Widget _submissionOrEmpty(BattleSubmission? submission) {
    if (submission == null) return const Text(AppStrings.battleEvidenceNoSubmission);
    return _SubmissionTile(submission: submission);
  }
}

/// 제출 한 건(시각, 사유, 사진).
class _SubmissionTile extends StatelessWidget {
  const _SubmissionTile({required this.submission});

  final BattleSubmission submission;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(formatEvidenceTime(submission.submittedAt), style: RetroText.numeric),
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

/// 서버가 준 UTC 시각을 기기 시간대의 hh:mm으로. 대결 주기상 날짜는 군더더기다.
String formatEvidenceTime(DateTime time) {
  final local = time.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}
