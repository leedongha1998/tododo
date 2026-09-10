import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/strings.dart';
import '../domain/battle_detail.dart';
import '../domain/battle_providers.dart';
import 'battle_chips.dart';

class BattleDetailScreen extends ConsumerWidget {
  const BattleDetailScreen({super.key, required this.battleId});

  final String battleId;

  // 사진이면 먼저 Storage에 올리고, 받은 경로를 증거 내용으로 넘긴다.
  // 성공 여부를 돌려줘서 화면이 로컬 상태(고른 사진 등)를 정리할 수 있게 한다.
  Future<bool> _submitEvidence(
    BuildContext context,
    WidgetRef ref, {
    Uint8List? photoBytes,
    String? text,
  }) async {
    try {
      final repo = ref.read(battleRepositoryProvider);
      final String evidenceType;
      final String content;
      if (photoBytes != null) {
        content = await repo.uploadEvidencePhoto(battleId, photoBytes);
        evidenceType = 'photo';
      } else {
        content = text!.trim();
        evidenceType = 'text';
      }
      await repo.submitEvidence(battleId, evidenceType, content);
      ref.invalidate(battleDetailProvider(battleId));
      ref.invalidate(myBattlesProvider);
      if (context.mounted) _showSnackBar(context, AppStrings.battleEvidenceSubmitted);
      return true;
    } catch (e) {
      debugPrint('submitEvidence failed: $e');
      if (context.mounted) _showSnackBar(context, AppStrings.battleEvidenceSubmitFailed);
      return false;
    }
  }

  Future<void> _decide(
    BuildContext context,
    WidgetRef ref,
    BattleDetail detail,
    String decision,
  ) async {
    if (decision == 'dispute') {
      final confirmed = await _confirmDispute(context, detail);
      if (!confirmed || !context.mounted) return;
    }
    try {
      await ref.read(battleRepositoryProvider).decideEvidence(
            battleId,
            detail.opponent.userId,
            decision,
          );
      ref.invalidate(battleDetailProvider(battleId));
      ref.invalidate(myBattlesProvider);
      if (context.mounted) _showSnackBar(context, AppStrings.battleDecisionDone);
    } catch (e) {
      debugPrint('decideEvidence failed: $e');
      if (context.mounted) _showSnackBar(context, AppStrings.battleDecisionFailed);
    }
  }

  // 포기는 곧 패배(품질전은 미결)라 되돌릴 수 없다. 반드시 한 번 확인받는다.
  Future<void> _forfeit(BuildContext context, WidgetRef ref, BattleDetail detail) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(AppStrings.battleForfeitConfirmTitle),
        content: Text(
          detail.battle.type == 'speed'
              ? AppStrings.battleForfeitConfirmSpeed
              : AppStrings.battleForfeitConfirmQuality,
        ),
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

  // 이의제기는 되돌릴 수 없고 유형에 따라 결과가 다르므로 한 번 확인받는다.
  Future<bool> _confirmDispute(BuildContext context, BattleDetail detail) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(AppStrings.battleDisputeConfirmTitle),
        content: Text(
          detail.battle.type == 'speed'
              ? AppStrings.battleDisputeConfirmSpeed
              : AppStrings.battleDisputeConfirmQuality,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(AppStrings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(AppStrings.battleDispute),
          ),
        ],
      ),
    );
    return confirmed ?? false;
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
              _BattleHeader(detail: detail),
              const SizedBox(height: 16),
              _ResultBanner(detail: detail),
              _EvidenceSection(
                battleId: battleId,
                detail: detail,
                onSubmit: ({photoBytes, text}) =>
                    _submitEvidence(context, ref, photoBytes: photoBytes, text: text),
                onDecide: (decision) => _decide(context, ref, detail, decision),
              ),
              if (detail.canForfeit) ...[
                const Divider(height: 32),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => _forfeit(context, ref, detail),
                    style: TextButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                    ),
                    icon: const Icon(Icons.flag_outlined),
                    label: const Text(AppStrings.battleForfeit),
                  ),
                ),
              ],
            ],
          ),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) {
          debugPrint('battleDetailProvider error: $error');
          return Center(child: Text(AppStrings.battleLoadDetailFailed));
        },
      ),
    );
  }
}

typedef _SubmitEvidence = Future<bool> Function({Uint8List? photoBytes, String? text});

/// 속도전/품질전 공용 증거 영역.
///
/// 두 유형은 "양쪽이 각자 증거를 제출하고 서로의 증거를 승인/이의제기한다"는 절차를 공유하므로
/// 화면도 하나로 쓴다. 유형에 따라 갈리는 건 필수 증거 종류와 결과 문구뿐이다.
class _EvidenceSection extends StatefulWidget {
  const _EvidenceSection({
    required this.battleId,
    required this.detail,
    required this.onSubmit,
    required this.onDecide,
  });

  final String battleId;
  final BattleDetail detail;
  final _SubmitEvidence onSubmit;
  final ValueChanged<String> onDecide;

  @override
  State<_EvidenceSection> createState() => _EvidenceSectionState();
}

class _EvidenceSectionState extends State<_EvidenceSection> {
  final _textController = TextEditingController();
  Uint8List? _photoBytes;
  bool _resubmitting = false;
  bool _submitting = false;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  bool get _showForm =>
      widget.detail.canSubmitEvidence || (_resubmitting && widget.detail.canResubmitEvidence);

  bool get _canSubmitNow {
    if (_submitting) return false;
    if (_photoBytes != null) return true;
    // 품질전은 사진 없이는 제출할 수 없다. 속도전만 텍스트 증거를 허용한다.
    if (widget.detail.requiresPhotoEvidence) return false;
    return _textController.text.trim().isNotEmpty;
  }

  Future<void> _pickPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text(AppStrings.battleEvidencePhotoFromCamera),
              onTap: () => Navigator.of(context).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text(AppStrings.battleEvidencePhotoFromGallery),
              onTap: () => Navigator.of(context).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1600,
        imageQuality: 80,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      setState(() => _photoBytes = bytes);
    } catch (e) {
      debugPrint('pickImage failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.battleEvidencePhotoPickFailed)),
      );
    }
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    final succeeded = await widget.onSubmit(
      photoBytes: _photoBytes,
      text: _textController.text,
    );
    if (!mounted) return;
    setState(() {
      _submitting = false;
      if (succeeded) {
        _photoBytes = null;
        _resubmitting = false;
        _textController.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final detail = widget.detail;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${AppStrings.battleMe} (${detail.myName})', style: textTheme.titleSmall),
        const SizedBox(height: 8),
        if (_showForm) ..._buildForm(context, detail) else ..._buildMyEvidence(context, detail),
        const Divider(height: 32),
        Text('${AppStrings.battleOpponent} (${detail.opponentName})', style: textTheme.titleSmall),
        const SizedBox(height: 8),
        ..._buildOpponentEvidence(context, detail),
      ],
    );
  }

  List<Widget> _buildForm(BuildContext context, BattleDetail detail) {
    return [
      if (detail.battle.type == 'speed') ...[
        Text(AppStrings.battleSpeedEvidenceNotice, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
      ],
      if (detail.requiresPhotoEvidence) ...[
        Text(AppStrings.battleEvidencePhotoRequired, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
      ],
      if (_photoBytes != null) ...[
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.memory(_photoBytes!, height: 160, fit: BoxFit.cover),
        ),
        const SizedBox(height: 8),
      ],
      OutlinedButton.icon(
        onPressed: _submitting ? null : _pickPhoto,
        icon: const Icon(Icons.photo_camera_outlined),
        label: Text(
          _photoBytes == null
              ? AppStrings.battleEvidencePhotoAdd
              : AppStrings.battleEvidencePhotoChange,
        ),
      ),
      if (!detail.requiresPhotoEvidence) ...[
        const SizedBox(height: 8),
        TextField(
          controller: _textController,
          decoration: const InputDecoration(hintText: AppStrings.battleEvidenceHint),
          maxLines: 3,
          enabled: !_submitting,
          onChanged: (_) => setState(() {}),
        ),
      ],
      const SizedBox(height: 8),
      FilledButton(
        onPressed: _canSubmitNow ? _submit : null,
        child: _submitting
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text(AppStrings.battleEvidenceSubmit),
      ),
    ];
  }

  List<Widget> _buildMyEvidence(BuildContext context, BattleDetail detail) {
    if (!detail.hasSubmittedEvidence) return const [];

    final String statusText;
    if (detail.wasMyEvidenceApproved) {
      statusText = AppStrings.battleDecisionApproved;
    } else if (detail.wasMyEvidenceDisputed) {
      statusText = AppStrings.battleMyEvidenceDisputed;
    } else {
      statusText = AppStrings.battleDecisionWaiting;
    }

    return [
      _EvidenceContent(
        evidenceType: detail.me.evidenceType,
        evidenceContent: detail.me.evidenceContent,
      ),
      if (detail.me.evidenceSubmittedAt != null) ...[
        const SizedBox(height: 4),
        _SubmittedAt(time: detail.me.evidenceSubmittedAt!),
      ],
      const SizedBox(height: 8),
      Text(statusText),
      if (detail.isAwaitingBothDecisions) ...[
        const SizedBox(height: 4),
        Text(AppStrings.battleAwaitingBothDecisions),
      ],
      if (detail.canResubmitEvidence) ...[
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => setState(() => _resubmitting = true),
          child: const Text(AppStrings.battleEvidenceResubmit),
        ),
      ],
    ];
  }

  List<Widget> _buildOpponentEvidence(BuildContext context, BattleDetail detail) {
    final opponent = detail.opponent;
    if (opponent.evidenceSubmittedAt == null) {
      return [Text(AppStrings.battleEvidenceWaitingOpponentSubmit)];
    }

    return [
      Text(AppStrings.battleEvidenceReview),
      const SizedBox(height: 8),
      _EvidenceContent(
        evidenceType: opponent.evidenceType,
        evidenceContent: opponent.evidenceContent,
      ),
      if (opponent.evidenceSubmittedAt != null) ...[
        const SizedBox(height: 4),
        _SubmittedAt(time: opponent.evidenceSubmittedAt!),
      ],
      const SizedBox(height: 8),
      if (detail.canReviewOpponentEvidence)
        Row(
          children: [
            FilledButton(
              onPressed: () => widget.onDecide('approve'),
              child: const Text(AppStrings.battleApprove),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: () => widget.onDecide('dispute'),
              child: const Text(AppStrings.battleDispute),
            ),
          ],
        )
      else if (opponent.decision != null)
        Text(
          opponent.decision == 'approve' ? AppStrings.battleApprove : AppStrings.battleDispute,
        ),
    ];
  }
}

/// 증거 한 건을 그린다. 사진이면 서명 URL을 받아 띄우고, 텍스트면 본문을 그대로 보여준다.
class _EvidenceContent extends StatelessWidget {
  const _EvidenceContent({required this.evidenceType, required this.evidenceContent});

  final String? evidenceType;
  final String? evidenceContent;

  @override
  Widget build(BuildContext context) {
    final content = evidenceContent;
    if (content == null || content.isEmpty) return const SizedBox.shrink();
    if (evidenceType == 'photo') return _EvidencePhoto(path: content);
    return Text(content);
  }
}

/// 비공개 버킷의 사진은 매번 서명 URL을 새로 받아 띄운다.
/// 발급이나 로딩에 실패해도 화면 전체를 깨뜨리지 않고 이 자리만 재시도 버튼으로 바꾼다.
class _EvidencePhoto extends ConsumerStatefulWidget {
  const _EvidencePhoto({required this.path});

  final String path;

  @override
  ConsumerState<_EvidencePhoto> createState() => _EvidencePhotoState();
}

class _EvidencePhotoState extends ConsumerState<_EvidencePhoto> {
  late Future<String> _urlFuture;

  @override
  void initState() {
    super.initState();
    _urlFuture = _loadUrl();
  }

  Future<String> _loadUrl() {
    return ref.read(battleRepositoryProvider).createEvidencePhotoUrl(widget.path);
  }

  void _retry() => setState(() => _urlFuture = _loadUrl());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _urlFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          debugPrint('createEvidencePhotoUrl failed: ${snapshot.error}');
          return _failed();
        }
        if (!snapshot.hasData) {
          return const SizedBox(height: 160, child: Center(child: CircularProgressIndicator()));
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            snapshot.data!,
            height: 160,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              debugPrint('evidence image load failed: $error');
              return _failed();
            },
          ),
        );
      },
    );
  }

  Widget _failed() {
    return Row(
      children: [
        const Icon(Icons.broken_image_outlined),
        const SizedBox(width: 8),
        Text(AppStrings.battleEvidencePhotoLoadFailed),
        const SizedBox(width: 8),
        TextButton(onPressed: _retry, child: const Text(AppStrings.retry)),
      ],
    );
  }
}

/// 유형과 현재 상태, 그리고 속도전이면 누가 얼마나 앞섰는지를 한 줄로 보여준다.
class _BattleHeader extends StatelessWidget {
  const _BattleHeader({required this.detail});

  final BattleDetail detail;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final lead = _speedLeadText(detail);

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
        if (lead != null) ...[
          const SizedBox(height: 8),
          Text(lead, style: textTheme.bodyMedium),
        ],
      ],
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
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final String headline;
    final String? reason;
    final IconData icon;
    final Color background;
    final Color foreground;

    if (detail.isQualityFinished) {
      headline = AppStrings.battleQualityFinished;
      reason = null;
      icon = Icons.check_circle_outline;
      background = scheme.secondaryContainer;
      foreground = scheme.onSecondaryContainer;
    } else if (detail.didIWinSpeedBattle) {
      headline = AppStrings.battleYouWon;
      reason = switch (detail) {
        _ when detail.didOpponentForfeit => AppStrings.battleWonByForfeit,
        _ when detail.wasOpponentEvidenceDisputed => AppStrings.battleWonByOpponentDisputed,
        _ => AppStrings.battleWonBySpeed,
      };
      icon = Icons.emoji_events_outlined;
      background = scheme.primaryContainer;
      foreground = scheme.onPrimaryContainer;
    } else if (detail.didILoseSpeedBattle) {
      headline = AppStrings.battleYouLost;
      reason = switch (detail) {
        _ when detail.didIForfeit => AppStrings.battleLostByForfeit,
        _ when detail.wasMyEvidenceDisputed => AppStrings.battleLostByDisputed,
        _ => AppStrings.battleLostBySpeed,
      };
      icon = Icons.sentiment_dissatisfied_outlined;
      background = scheme.surfaceContainerHighest;
      foreground = scheme.onSurfaceVariant;
    } else if (detail.isSpeedDisputed) {
      headline = AppStrings.battleSpeedDisputedMessage;
      reason = null;
      icon = Icons.report_problem_outlined;
      background = scheme.errorContainer;
      foreground = scheme.onErrorContainer;
    } else if (detail.isDisputed) {
      // 품질전은 기권해도 승자를 두지 않는다. 다만 왜 미결인지는 말해준다.
      headline = detail.battle.forfeitedBy != null
          ? AppStrings.battleQualityForfeited
          : AppStrings.battleDisputedMessage;
      reason = null;
      icon = Icons.report_problem_outlined;
      background = scheme.errorContainer;
      foreground = scheme.onErrorContainer;
    } else {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: foreground),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  headline,
                  style: textTheme.titleMedium
                      ?.copyWith(color: foreground, fontWeight: FontWeight.bold),
                ),
                if (reason != null) ...[
                  const SizedBox(height: 4),
                  Text(reason, style: textTheme.bodyMedium?.copyWith(color: foreground)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 증거를 언제 냈는지. 속도전에서는 이 값이 곧 승부 기준이라 반드시 보여야 한다.
class _SubmittedAt extends StatelessWidget {
  const _SubmittedAt({required this.time});

  final DateTime time;

  @override
  Widget build(BuildContext context) {
    return Text(
      '${AppStrings.battleEvidenceSubmittedLabel} ${_formatSubmittedAt(time)}',
      style: Theme.of(context).textTheme.bodySmall,
    );
  }
}

// 서버가 준 UTC 시각을 기기 시간대로 바꿔 보여준다. 연도는 대결 주기상 군더더기라 뺀다.
String _formatSubmittedAt(DateTime time) {
  final local = time.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.month}월 ${local.day}일 $hour:$minute';
}

// 속도전에서 양쪽이 다 냈을 때만 격차를 말한다. 재제출로 순서가 뒤집혀도 이 줄이 바로 알려준다.
String? _speedLeadText(BattleDetail detail) {
  if (detail.battle.type != 'speed') return null;

  final mine = detail.me.evidenceSubmittedAt;
  final theirs = detail.opponent.evidenceSubmittedAt;
  if (mine == null || theirs == null) return null;

  final gap = mine.difference(theirs);
  if (gap.inSeconds == 0) return null;

  final label = _formatGap(gap.abs());
  return gap.isNegative
      ? AppStrings.battleSpeedLeadMine(label)
      : AppStrings.battleSpeedLeadOpponent(label);
}

String _formatGap(Duration gap) {
  if (gap.inDays > 0) return '${gap.inDays}일';
  if (gap.inHours > 0) return '${gap.inHours}시간';
  if (gap.inMinutes > 0) return '${gap.inMinutes}분';
  return '${gap.inSeconds}초';
}
