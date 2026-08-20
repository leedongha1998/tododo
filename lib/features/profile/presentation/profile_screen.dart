import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/strings.dart';
import '../domain/battle_record.dart';
import '../domain/profile_providers.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  String _typeLabel(String type) {
    return type == 'speed' ? AppStrings.battleTypeSpeed : AppStrings.battleTypeQuality;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(myProfileProvider);
    final recordsAsync = ref.watch(battleRecordsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.profileTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          profileAsync.when(
            data: (profile) =>
                Text(profile.displayName, style: Theme.of(context).textTheme.titleLarge),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stackTrace) {
              debugPrint('myProfileProvider error: $error');
              return Text(AppStrings.profileLoadFailed);
            },
          ),
          const SizedBox(height: 24),
          recordsAsync.when(
            data: (records) {
              if (records.isEmpty) {
                return Text(AppStrings.profileRecordEmpty);
              }

              final speedWins =
                  records.where((r) => r.battle.type == 'speed' && r.resultLabel == AppStrings.battleRecordWin).length;
              final speedLosses =
                  records.where((r) => r.battle.type == 'speed' && r.resultLabel == AppStrings.battleRecordLose).length;
              final qualityFinished = records
                  .where((r) => r.battle.type == 'quality' && r.battle.status == 'finished')
                  .length;
              final qualityDisputed = records
                  .where((r) => r.battle.type == 'quality' && r.battle.status == 'disputed')
                  .length;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${AppStrings.battleTypeSpeed} $speedWins${AppStrings.battleRecordWin} $speedLosses${AppStrings.battleRecordLose}'
                    ' · ${AppStrings.battleTypeQuality} $qualityFinished${AppStrings.battleStatusFinished} $qualityDisputed${AppStrings.battleStatusDisputed}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  ...records.map((record) => _BattleRecordTile(record: record, typeLabel: _typeLabel)),
                ],
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stackTrace) {
              debugPrint('battleRecordsProvider error: $error');
              return Text(AppStrings.profileLoadRecordFailed);
            },
          ),
        ],
      ),
    );
  }
}

class _BattleRecordTile extends StatelessWidget {
  const _BattleRecordTile({required this.record, required this.typeLabel});

  final BattleRecord record;
  final String Function(String) typeLabel;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(record.battle.title),
      subtitle: Text('${record.otherPartyName} · ${typeLabel(record.battle.type)}'),
      trailing: Text(record.resultLabel, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}
