import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/strings.dart';
import '../../auth/domain/auth_providers.dart';
import '../../battle/presentation/battle_detail_screen.dart';
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
          const SizedBox(height: 32),
          const Divider(),
          // 탭바가 생기면서 앱바 아이콘이 사라졌다. 계정 관련 동작은 전부 여기로 모은다.
          Text(AppStrings.accountSection, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => ref.read(authRepositoryProvider).signOut(),
              icon: const Icon(Icons.logout),
              label: const Text(AppStrings.logout),
            ),
          ),
          const _DeleteAccountButton(),
        ],
      ),
    );
  }
}

/// 탈퇴 버튼. Google 계정으로 로그인하는 앱은 앱 안에 계정 삭제 경로가 있어야 한다(Play 정책).
class _DeleteAccountButton extends ConsumerStatefulWidget {
  const _DeleteAccountButton();

  @override
  ConsumerState<_DeleteAccountButton> createState() => _DeleteAccountButtonState();
}

class _DeleteAccountButtonState extends ConsumerState<_DeleteAccountButton> {
  bool _isDeleting = false;

  Future<void> _confirmAndDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(AppStrings.accountDeleteConfirmTitle),
        content: const Text(AppStrings.accountDeleteConfirmMessage),
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
            child: const Text(AppStrings.accountDeleteConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    // 삭제 성공 시 이 위젯이 사라지므로 messenger/navigator를 미리 잡아둔다.
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    setState(() => _isDeleting = true);
    try {
      await ref.read(authRepositoryProvider).deleteAccount();
      // AuthGate가 로그인 화면으로 바뀌므로 그 위에 쌓여 있던 화면을 걷어낸다.
      navigator.popUntil((route) => route.isFirst);
      messenger.showSnackBar(const SnackBar(content: Text(AppStrings.accountDeleteDone)));
    } catch (error) {
      debugPrint('deleteAccount error: $error');
      if (mounted) setState(() => _isDeleting = false);
      messenger.showSnackBar(const SnackBar(content: Text(AppStrings.accountDeleteFailed)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: _isDeleting ? null : _confirmAndDelete,
        style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
        icon: _isDeleting
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.person_remove_outlined),
        label: const Text(AppStrings.accountDelete),
      ),
    );
  }
}

/// 끝난 대결은 홈 목록에서 빠지므로, 지난 증거와 결과를 다시 볼 경로는 여기뿐이다.
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
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => BattleDetailScreen(battleId: record.battle.id)),
      ),
    );
  }
}
