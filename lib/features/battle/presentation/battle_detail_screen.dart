import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/strings.dart';
import '../../../core/theme/pixel_icons.dart';
import '../../../core/theme/retro_palette.dart';
import '../../../core/widgets/evidence_photo_frame.dart';
import '../../../core/widgets/pixel_frame.dart';
import '../../../core/widgets/pixel_icon.dart';
import '../../../core/widgets/pixel_loader.dart';
import '../domain/battle_detail.dart';
import '../domain/battle_providers.dart';
import 'battle_chips.dart';
import 'vs_intro.dart';

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
              // 화면에 보이지 않는 판단 전용 조각. 배치는 바뀌지 않는다.
              _VsIntroOnFirstEntry(detail: detail),
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
              leading: const PixelIcon(PixelIcons.camera),
              title: const Text(AppStrings.battleEvidencePhotoFromCamera),
              onTap: () => Navigator.of(context).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const PixelIcon(PixelIcons.gallery),
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
        // 고른 사진도 제출될 원본 그대로 틀 안에 보여 준다(자르지 않음).
        EvidencePhotoFrame.thumbnail(image: MemoryImage(_photoBytes!)),
        const SizedBox(height: 8),
      ],
      OutlinedButton.icon(
        onPressed: _submitting ? null : _pickPhoto,
        icon: const PixelIcon(PixelIcons.camera),
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
            ? const PixelLoader.small()
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
          return EvidencePhotoFrame.thumbnail(failed: true, onRetry: _retry);
        }
        if (!snapshot.hasData) {
          return const EvidencePhotoFrame.thumbnail();
        }
        // 사진 로딩·디코딩 실패도 같은 틀 안에서 처리한다(원본 가공 없음, 잘림 없음).
        return EvidencePhotoFrame.thumbnail(
          image: NetworkImage(snapshot.data!),
          onRetry: _retry,
        );
      },
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
    final textTheme = Theme.of(context).textTheme;

    final String headline;
    final String? reason;
    final PixelIconData icon;
    // null이면 떠 있는 프레임(승리 — 가장 강한 결과). 나머지는 성격별 안내 블록.
    final PixelTone? tone;

    if (detail.isQualityFinished) {
      headline = AppStrings.battleQualityFinished;
      reason = null;
      icon = PixelIcons.check;
      tone = PixelTone.success;
    } else if (detail.didIWinSpeedBattle) {
      headline = AppStrings.battleYouWon;
      reason = switch (detail) {
        _ when detail.didOpponentForfeit => AppStrings.battleWonByForfeit,
        _ when detail.wasOpponentEvidenceDisputed => AppStrings.battleWonByOpponentDisputed,
        _ => AppStrings.battleWonBySpeed,
      };
      icon = PixelIcons.trophy;
      tone = null;
    } else if (detail.didILoseSpeedBattle) {
      headline = AppStrings.battleYouLost;
      reason = switch (detail) {
        _ when detail.didIForfeit => AppStrings.battleLostByForfeit,
        _ when detail.wasMyEvidenceDisputed => AppStrings.battleLostByDisputed,
        _ => AppStrings.battleLostBySpeed,
      };
      // 얼굴 아이콘 금지 규칙 때문에 표정 대신 아래로 꺾인 화살표.
      icon = PixelIcons.lose;
      tone = PixelTone.neutral;
    } else if (detail.isDraw) {
      headline = AppStrings.battleDrawMessage;
      reason = null;
      icon = PixelIcons.hourglass;
      // 무승부는 잘못된 일이 아니다. 위험색이 아니라 중립.
      tone = PixelTone.neutral;
    } else if (detail.isSpeedDisputed) {
      headline = AppStrings.battleSpeedDisputedMessage;
      reason = null;
      icon = PixelIcons.warning;
      tone = PixelTone.danger;
    } else if (detail.isDisputed) {
      // 품질전은 기권해도 승자를 두지 않는다. 다만 왜 미결인지는 말해준다.
      headline = detail.battle.forfeitedBy != null
          ? AppStrings.battleQualityForfeited
          : AppStrings.battleDisputedMessage;
      reason = null;
      icon = PixelIcons.warning;
      tone = PixelTone.danger;
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
String _formatSubmittedAt(DateTime time) {
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

  return '${AppStrings.battleDeadlineLabel} ${_formatSubmittedAt(deadline)}'
      ' · ${AppStrings.battleDeadlineLeft(_formatGap(left))}';
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
