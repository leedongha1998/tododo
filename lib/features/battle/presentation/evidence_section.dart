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
import '../data/submission_result.dart';
import '../domain/battle_detail.dart';
import '../domain/battle_providers.dart';
import '../domain/submission_rules.dart';

/// 내 증거 영역: 촬영 → 미리보기 → 제출 → (속도전) 판정 결과 → 이력.
///
/// 속도전은 제출마다 바로 판정이 돌아오고 최대 5회까지 다시 낼 수 있다.
/// 품질전은 한 번만 낼 수 있고(확인 다이얼로그), 두 사진이 모두 올라오면 대결 단위로 판정된다.
///
/// 활성화 판단은 전부 [BattleDetail]의 getter가 하고, 같은 검사를 서버가 다시 한다.
/// 이 위젯은 승패를 계산하지 않는다 — 판정 결과와 상태는 서버가 준 값을 그대로 보여 준다.
class MyEvidenceSection extends ConsumerStatefulWidget {
  const MyEvidenceSection({super.key, required this.detail});

  final BattleDetail detail;

  @override
  ConsumerState<MyEvidenceSection> createState() => _MyEvidenceSectionState();
}

enum _Stage { idle, uploading, judging }

class _MyEvidenceSectionState extends ConsumerState<MyEvidenceSection> {
  EvidenceShot? _shot;
  _Stage _stage = _Stage.idle;

  /// 방금 돌아온 판정. 불합격 사유와 AI 실패 안내를 곧바로 보여 주는 데만 쓴다.
  SubmissionResult? _lastResult;

  bool get _busy => _stage != _Stage.idle;

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _capture() async {
    try {
      final shot = await ref.read(evidenceCameraProvider).capture();
      if (shot == null || !mounted) return;
      setState(() {
        _shot = shot;
        _lastResult = null;
      });
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
      if (mounted) setState(() => _stage = _Stage.judging);

      final result = await repository.submitEvidence(
        battleId: battleId,
        objectPath: path,
        capturedAt: shot.capturedAt,
      );

      // 결과는 서버에 남는다. 화면은 다시 읽어 상태·횟수·이력을 서버 값으로 맞춘다.
      ref.invalidate(battleDetailProvider(battleId));
      ref.invalidate(myBattlesProvider);

      if (!mounted) return;
      setState(() {
        _stage = _Stage.idle;
        _shot = null;
        _lastResult = result;
      });
    } catch (error) {
      debugPrint('submitEvidence failed: $error');
      if (!mounted) return;
      setState(() => _stage = _Stage.idle);
      // 거부(촬영 시각·마감·잠금·횟수)는 코드별 문구로 알린다. 횟수는 줄지 않는다.
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
        children: [
          ..._buildBody(context, detail),
          if (detail.mySubmissions.isNotEmpty) ...[
            const SizedBox(height: 16),
            _SubmissionHistory(
              submissions: detail.mySubmissions,
              title: AppStrings.battleEvidenceHistoryTitle,
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildBody(BuildContext context, BattleDetail detail) {
    if (_busy) {
      return [
        StatusMessage.loading(
          message: _stage == _Stage.uploading
              ? AppStrings.battleEvidenceUploading
              : detail.isSpeed
                  ? AppStrings.battleEvidenceJudging
                  : AppStrings.battleEvidenceQualityJudging,
        ),
      ];
    }

    if (!detail.isSpeed) return _qualityBody(context, detail);

    // 서버가 판정 중인 내 제출을 들고 있는 경우(앱을 껐다 켠 뒤 등).
    if (detail.isMyJudgingInProgress) {
      return const [StatusMessage.loading(message: AppStrings.battleEvidenceJudging)];
    }

    if (detail.didIPass) {
      return [_passedBlock(context, detail)];
    }

    if (detail.didIUseAllAttempts) {
      return const [
        PixelFrame.tone(
          tone: PixelTone.neutral,
          icon: PixelIcons.lock,
          child: Text(AppStrings.battleEvidenceExhausted),
        ),
      ];
    }

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

    // 마감이 지났는데 아직 정산 전이면 낼 수 없다(서버도 거부한다).
    if (!detail.canSubmitEvidence) {
      return [
        ..._lastVerdictBlock(context),
        if (detail.isPastDeadline(DateTime.now()))
          const PixelFrame.tone(
            tone: PixelTone.neutral,
            icon: PixelIcons.clock,
            child: Text(AppStrings.battleDeadlinePassed),
          ),
      ];
    }

    return [
      ..._lastVerdictBlock(context),
      FilledButton.icon(
        onPressed: _capture,
        icon: const PixelIcon(PixelIcons.camera),
        label: const Text(AppStrings.battleEvidenceTakePhoto),
      ),
      const SizedBox(height: 8),
      Text(
        AppStrings.battleEvidenceAttemptsLeft(detail.myAttemptsLeft),
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ];
  }

  /// 품질전: 한 번 내면 상대를 기다리고, 두 사진이 모두 올라오면 서버가 판정한다.
  /// 판정 결과(승패·사유)는 종결 뒤 결과 배너가 서버 값으로 보여 준다 — 여기서는 판단하지 않는다.
  List<Widget> _qualityBody(BuildContext context, BattleDetail detail) {
    if (detail.isQualityJudging) {
      return const [
        PixelFrame.tone(
          tone: PixelTone.info,
          title: AppStrings.battleEvidenceQualityJudgingTitle,
          child: Text(AppStrings.battleEvidenceQualityJudging),
        ),
      ];
    }

    if (detail.hasMyQualitySubmission) {
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

  /// 방금 받은 불합격·AI 실패 안내. 합격은 아래 통과 블록이 대신한다.
  List<Widget> _lastVerdictBlock(BuildContext context) {
    final result = _lastResult;
    if (result == null || result.isPassed) return const [];

    if (result.isError) {
      return const [
        PixelFrame.tone(
          tone: PixelTone.neutral,
          icon: PixelIcons.warning,
          title: AppStrings.battleEvidenceErrorTitle,
          child: Text(AppStrings.battleEvidenceErrorDetail),
        ),
        SizedBox(height: 12),
      ];
    }

    return [
      PixelFrame.tone(
        tone: PixelTone.danger,
        icon: PixelIcons.fail,
        title: AppStrings.battleEvidenceFailedTitle,
        child: Text(result.reason ?? ''),
      ),
      const SizedBox(height: 12),
    ];
  }

  Widget _passedBlock(BuildContext context, BattleDetail detail) {
    final passed = detail.mySubmissions.where((submission) => submission.isPassed).firstOrNull;
    final passedAt = detail.me.passedAt ?? passed?.submittedAt;

    return PixelFrame.tone(
      tone: PixelTone.success,
      icon: PixelIcons.pass,
      title: AppStrings.battleEvidencePassedTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (passedAt != null)
            Text(
              AppStrings.battleEvidencePassedAt(formatEvidenceTime(passedAt)),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          if (passed?.reason != null) ...[
            const SizedBox(height: 4),
            Text(passed!.reason!, style: Theme.of(context).textTheme.bodyMedium),
          ],
          const SizedBox(height: 8),
          Text(
            AppStrings.battleEvidencePassedLocked,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// 상대 영역. 진행 중에는 사진도 사유도 보여 주지 않는다 — 서버가 내주지 않기 때문에
/// 보여 줄 수도 없다. 제출했다는 사실과, 속도전이면 합격/불합격 결과만 보인다(결정 65).
class OpponentEvidenceSummary extends StatelessWidget {
  const OpponentEvidenceSummary({super.key, required this.detail});

  final BattleDetail detail;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final submittedAt = detail.opponent.firstSubmittedAt;
    final verdict = detail.opponentLastVerdict;

    return PixelFrame.flat(
      title: AppStrings.battleEvidenceOpponentTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            submittedAt == null
                ? AppStrings.battleEvidenceOpponentWaiting
                : AppStrings.battleEvidenceOpponentSubmitted(formatEvidenceTime(submittedAt)),
            style: textTheme.bodyMedium,
          ),
          if (detail.isSpeed && verdict != null) ...[
            const SizedBox(height: 4),
            Text(
              AppStrings.battleEvidenceOpponentVerdict(
                submissionStatusLabel(verdict),
                detail.opponent.attemptsUsed,
              ),
              style: textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

/// 종결 뒤 공개되는 양쪽 증거(사진 + 합격/불합격 + 사유).
///
/// 진행 중에는 서버(RLS)가 상대 제출 행을 아예 내주지 않으므로 이 위젯이 그릴 것도 없다.
/// 종결 뒤에 열리는 것도 서버가 정하고, 화면은 받은 행을 그대로 보여 준다.
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
          child: _historyOrEmpty(detail.mySubmissions),
        ),
        const SizedBox(height: 16),
        PixelFrame.flat(
          title: AppStrings.battleEvidenceOpponentTitle,
          child: _historyOrEmpty(detail.opponentSubmissions),
        ),
      ],
    );
  }

  // 한 번도 내지 않은 채 끝난 대결(마감 무승부, 포기 등)도 있다.
  Widget _historyOrEmpty(List<BattleSubmission> submissions) {
    if (submissions.isEmpty) return const Text(AppStrings.battleEvidenceNoSubmission);
    return _SubmissionHistory(submissions: submissions);
  }
}

/// 내 시도 이력(시각, 합격/불합격/실패, 사유, 사진).
class _SubmissionHistory extends StatelessWidget {
  const _SubmissionHistory({required this.submissions, this.title});

  final List<BattleSubmission> submissions;

  /// 창 제목이 이미 누구 것인지 말하는 자리(종결 뒤 공개)에서는 null이다.
  final String? title;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    // 최근 시도가 위에 오게 뒤집는다.
    final ordered = submissions.reversed.toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null) Text(title!, style: textTheme.titleSmall),
        for (final submission in ordered) ...[
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(formatEvidenceTime(submission.submittedAt), style: RetroText.numeric),
              const SizedBox(width: 8),
              PixelTag(
                label: submissionStatusLabel(submission.status),
                style: _verdictTagStyle(submission.status),
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

/// 합격 = 성공 면, 불합격 = 위험 테두리, 그 밖(판정 중·실패) = 약한 점선.
PixelTagStyle _verdictTagStyle(String status) {
  return switch (status) {
    'passed' => const PixelTagStyle(
        fill: RetroPalette.success,
        textColor: RetroPalette.surface,
        borderColor: RetroPalette.ink,
      ),
    'failed' => const PixelTagStyle(
        fill: RetroPalette.dangerPale,
        textColor: RetroPalette.ink,
        borderColor: RetroPalette.danger,
      ),
    _ => const PixelTagStyle(
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
