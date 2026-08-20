import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/strings.dart';
import '../domain/battle_providers.dart';

class BattleInvitesScreen extends ConsumerWidget {
  const BattleInvitesScreen({super.key});

  String _typeLabel(String type) {
    return type == 'speed' ? AppStrings.battleTypeSpeed : AppStrings.battleTypeQuality;
  }

  Future<void> _accept(BuildContext context, WidgetRef ref, String battleId) async {
    try {
      await ref.read(battleRepositoryProvider).acceptBattle(battleId);
      ref.invalidate(receivedInvitesProvider);
      ref.invalidate(sentInvitesProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text(AppStrings.battleAccepted)));
      }
    } catch (e) {
      debugPrint('acceptBattle failed: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text(AppStrings.battleAcceptFailed)));
      }
    }
  }

  Future<void> _cancel(
    BuildContext context,
    WidgetRef ref,
    String battleId, {
    required bool isDecline,
  }) async {
    try {
      await ref.read(battleRepositoryProvider).cancelBattle(battleId);
      ref.invalidate(receivedInvitesProvider);
      ref.invalidate(sentInvitesProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(isDecline ? AppStrings.battleDeclined : AppStrings.battleInviteCancelled),
        ));
      }
    } catch (e) {
      debugPrint('cancelBattle failed: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(isDecline ? AppStrings.battleDeclineFailed : AppStrings.battleInviteCancelFailed),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final received = ref.watch(receivedInvitesProvider);
    final sent = ref.watch(sentInvitesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.battleInvites)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(AppStrings.battleReceivedInvites, style: Theme.of(context).textTheme.titleMedium),
          received.when(
            data: (invites) => invites.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(AppStrings.battleInvitesEmpty),
                  )
                : Column(
                    children: invites
                        .map(
                          (invite) => ListTile(
                            title: Text(invite.battle.title),
                            subtitle: Text('${invite.otherPartyName} · ${_typeLabel(invite.battle.type)}'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                TextButton(
                                  onPressed: () =>
                                      _cancel(context, ref, invite.battle.id, isDecline: true),
                                  child: const Text(AppStrings.battleDecline),
                                ),
                                FilledButton(
                                  onPressed: () => _accept(context, ref, invite.battle.id),
                                  child: const Text(AppStrings.battleAccept),
                                ),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                  ),
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, stackTrace) {
              debugPrint('receivedInvitesProvider error: $error');
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(AppStrings.battleLoadInvitesFailed),
              );
            },
          ),
          const SizedBox(height: 24),
          Text(AppStrings.battleSentInvites, style: Theme.of(context).textTheme.titleMedium),
          sent.when(
            data: (invites) => invites.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(AppStrings.battleInvitesEmpty),
                  )
                : Column(
                    children: invites
                        .map(
                          (invite) => ListTile(
                            title: Text(invite.battle.title),
                            subtitle: Text('${invite.otherPartyName} · ${_typeLabel(invite.battle.type)}'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text(AppStrings.battleWaitingAcceptance),
                                TextButton(
                                  onPressed: () =>
                                      _cancel(context, ref, invite.battle.id, isDecline: false),
                                  child: const Text(AppStrings.battleInviteCancel),
                                ),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                  ),
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, stackTrace) {
              debugPrint('sentInvitesProvider error: $error');
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(AppStrings.battleLoadInvitesFailed),
              );
            },
          ),
        ],
      ),
    );
  }
}
