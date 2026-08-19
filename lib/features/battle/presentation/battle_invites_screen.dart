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
                            trailing: FilledButton(
                              onPressed: () => _accept(context, ref, invite.battle.id),
                              child: const Text(AppStrings.battleAccept),
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
                            trailing: const Text(AppStrings.battleWaitingAcceptance),
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
