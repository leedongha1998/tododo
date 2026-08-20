import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/strings.dart';
import '../data/battle_participant.dart';
import '../domain/battle_detail.dart';
import '../domain/battle_providers.dart';

class BattleDetailScreen extends ConsumerWidget {
  const BattleDetailScreen({super.key, required this.battleId});

  final String battleId;

  Future<void> _completeSpeedTask(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(battleRepositoryProvider).completeSpeedTask(battleId);
      ref.invalidate(battleDetailProvider(battleId));
      ref.invalidate(myBattlesProvider);
      if (context.mounted) _showSnackBar(context, AppStrings.battleCompleted);
    } catch (e) {
      debugPrint('completeSpeedTask failed: $e');
      if (context.mounted) _showSnackBar(context, AppStrings.battleCompleteFailed);
    }
  }

  Future<void> _submitEvidence(BuildContext context, WidgetRef ref, String content) async {
    try {
      await ref.read(battleRepositoryProvider).submitQualityEvidence(battleId, content);
      ref.invalidate(battleDetailProvider(battleId));
      ref.invalidate(myBattlesProvider);
      if (context.mounted) _showSnackBar(context, AppStrings.battleEvidenceSubmitted);
    } catch (e) {
      debugPrint('submitQualityEvidence failed: $e');
      if (context.mounted) _showSnackBar(context, AppStrings.battleEvidenceSubmitFailed);
    }
  }

  Future<void> _decide(BuildContext context, WidgetRef ref, String targetUserId, String decision) async {
    try {
      await ref.read(battleRepositoryProvider).decideQualityEvidence(battleId, targetUserId, decision);
      ref.invalidate(battleDetailProvider(battleId));
      ref.invalidate(myBattlesProvider);
      if (context.mounted) _showSnackBar(context, AppStrings.battleCompleted);
    } catch (e) {
      debugPrint('decideQualityEvidence failed: $e');
      if (context.mounted) _showSnackBar(context, AppStrings.battleDecisionFailed);
    }
  }

  void _showSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(battleDetailProvider(battleId));

    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.battleMyBattles)),
      body: detailAsync.when(
        data: (detail) => RefreshIndicator(
          onRefresh: () => ref.refresh(battleDetailProvider(battleId).future),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(detail.battle.title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              if (detail.battle.type == 'speed')
                _SpeedSection(detail: detail, onComplete: () => _completeSpeedTask(context, ref))
              else
                _QualitySection(
                  detail: detail,
                  onSubmitEvidence: (content) => _submitEvidence(context, ref, content),
                  onDecide: (decision) => _decide(context, ref, detail.opponent.userId, decision),
                ),
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

class _SpeedSection extends StatelessWidget {
  const _SpeedSection({required this.detail, required this.onComplete});

  final BattleDetail detail;
  final VoidCallback onComplete;

  @override
  Widget build(BuildContext context) {
    final battle = detail.battle;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ParticipantTile(
          name: '${detail.myName} (${AppStrings.battleMe})',
          statusText: detail.me.completedAt != null
              ? AppStrings.battleSpeedDone
              : AppStrings.battleSpeedWaiting,
          done: detail.me.completedAt != null,
        ),
        _ParticipantTile(
          name: detail.opponentName,
          statusText: detail.opponent.completedAt != null
              ? AppStrings.battleSpeedDone
              : AppStrings.battleSpeedWaiting,
          done: detail.opponent.completedAt != null,
        ),
        const SizedBox(height: 24),
        if (battle.status == 'active' && detail.me.completedAt == null)
          FilledButton(onPressed: onComplete, child: const Text(AppStrings.battleComplete))
        else if (battle.status == 'active')
          Text(AppStrings.battleSpeedWaitingOpponent)
        else if (battle.status == 'finished')
          Text(
            battle.winnerId == detail.me.userId ? AppStrings.battleYouWon : AppStrings.battleYouLost,
            style: Theme.of(context).textTheme.titleMedium,
          ),
      ],
    );
  }
}

class _QualitySection extends StatefulWidget {
  const _QualitySection({
    required this.detail,
    required this.onSubmitEvidence,
    required this.onDecide,
  });

  final BattleDetail detail;
  final ValueChanged<String> onSubmitEvidence;
  final ValueChanged<String> onDecide;

  @override
  State<_QualitySection> createState() => _QualitySectionState();
}

class _QualitySectionState extends State<_QualitySection> {
  final _evidenceController = TextEditingController();

  @override
  void dispose() {
    _evidenceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final detail = widget.detail;
    final battle = detail.battle;
    final BattleParticipant me = detail.me;
    final BattleParticipant opponent = detail.opponent;

    final canSubmitEvidence =
        (battle.status == 'active' || battle.status == 'judging') && me.evidenceSubmittedAt == null;
    final canReviewOpponent = opponent.evidenceSubmittedAt != null && opponent.decision == null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (battle.status == 'disputed')
          Text(AppStrings.battleDisputedMessage, style: Theme.of(context).textTheme.titleMedium),
        if (battle.status == 'finished')
          Text(AppStrings.battleQualityFinished, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 16),
        Text('${AppStrings.battleMe} (${detail.myName})', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        if (canSubmitEvidence) ...[
          TextField(
            controller: _evidenceController,
            decoration: const InputDecoration(hintText: AppStrings.battleEvidenceHint),
            maxLines: 3,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _evidenceController.text.trim().isEmpty
                ? null
                : () => widget.onSubmitEvidence(_evidenceController.text.trim()),
            child: const Text(AppStrings.battleEvidenceSubmit),
          ),
        ] else if (me.evidenceSubmittedAt != null) ...[
          Text(me.evidenceContent ?? ''),
          const SizedBox(height: 4),
          Text(
            me.decision == 'approve'
                ? AppStrings.battleDecisionApproved
                : AppStrings.battleDecisionWaiting,
          ),
        ],
        const SizedBox(height: 24),
        Text(
          '${AppStrings.battleOpponent} (${detail.opponentName})',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        if (opponent.evidenceSubmittedAt == null)
          Text(AppStrings.battleEvidenceWaitingOpponentSubmit)
        else ...[
          Text(AppStrings.battleEvidenceReview),
          const SizedBox(height: 4),
          Text(opponent.evidenceContent ?? ''),
          const SizedBox(height: 8),
          if (canReviewOpponent)
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
            Text(opponent.decision == 'approve' ? AppStrings.battleApprove : AppStrings.battleDispute),
        ],
      ],
    );
  }
}

class _ParticipantTile extends StatelessWidget {
  const _ParticipantTile({required this.name, required this.statusText, required this.done});

  final String name;
  final String statusText;
  final bool done;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(done ? Icons.check_circle : Icons.hourglass_empty),
      title: Text(name),
      trailing: Text(statusText),
    );
  }
}
