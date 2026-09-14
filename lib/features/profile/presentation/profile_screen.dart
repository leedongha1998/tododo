import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/strings.dart';
import '../../../core/theme/pixel_icons.dart';
import '../../../core/widgets/pixel_frame.dart';
import '../../../core/widgets/pixel_icon.dart';
import '../../../core/widgets/pixel_loader.dart';
import '../../../core/widgets/retro_button_styles.dart';
import '../../auth/domain/auth_providers.dart';
import '../../battle/presentation/battle_chips.dart';
import '../../battle/presentation/battle_detail_screen.dart';
import '../domain/battle_record.dart';
import '../domain/profile_providers.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

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
            loading: () => const Center(child: PixelLoader.medium()),
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
              // 마감까지 아무도 끝내지 못한 대결. 승도 패도 아니라 따로 센다.
              final speedDraws = records
                  .where((r) => r.battle.type == 'speed' && r.battle.status == 'draw')
                  .length;
              final qualityDraws = records
                  .where((r) => r.battle.type == 'quality' && r.battle.status == 'draw')
                  .length;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${AppStrings.battleTypeSpeed} $speedWins${AppStrings.battleRecordWin}'
                    ' $speedLosses${AppStrings.battleRecordLose}'
                    ' $speedDraws${AppStrings.battleRecordDraw}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${AppStrings.battleTypeQuality} $qualityFinished${AppStrings.battleStatusFinished}'
                    ' $qualityDisputed${AppStrings.battleStatusDisputed}'
                    ' $qualityDraws${AppStrings.battleRecordDraw}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  ...records.map((record) => _BattleRecordTile(record: record)),
                ],
              );
            },
            loading: () => const Center(child: PixelLoader.medium()),
            error: (error, stackTrace) {
              debugPrint('battleRecordsProvider error: $error');
              return Text(AppStrings.profileLoadRecordFailed);
            },
          ),
          const SizedBox(height: 32),
          // 탭바가 생기면서 앱바 아이콘이 사라졌다. 계정 관련 동작은 전부 이 창 하나에 모은다.
          PixelFrame.flat(
            title: AppStrings.accountSection,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OutlinedButton.icon(
                  onPressed: () => ref.read(authRepositoryProvider).signOut(),
                  icon: const PixelIcon(PixelIcons.logout),
                  label: const Text(AppStrings.logout),
                ),
                const SizedBox(height: 8),
                // 번들한 갈무리 글꼴(OFL)의 고지를 사용자가 찾을 수 있는 자리.
                TextButton.icon(
                  style: TextButton.styleFrom(alignment: Alignment.centerLeft),
                  onPressed: () => showLicensePage(
                    context: context,
                    applicationName: AppStrings.appName,
                  ),
                  icon: const PixelIcon(PixelIcons.document),
                  label: const Text(AppStrings.openSourceLicenses),
                ),
                const SizedBox(height: 8),
                const Divider(),
                const SizedBox(height: 8),
                // 위험 동작은 구분선 뒤 맨 아래에 따로 둔다.
                const _DeleteAccountButton(),
              ],
            ),
          ),
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
            style: RetroButtonStyles.danger,
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
    return FilledButton.icon(
      style: RetroButtonStyles.danger,
      // 진행 중에는 누를 수 없는 모양 + 라벨 자리 로더(버튼 크기 유지).
      onPressed: _isDeleting ? null : _confirmAndDelete,
      icon: const PixelIcon(PixelIcons.accountDelete),
      label: _isDeleting ? const PixelLoader.small() : const Text(AppStrings.accountDelete),
    );
  }
}

/// 끝난 대결은 내 대결 탭에서 빠지므로, 지난 증거와 결과를 다시 볼 경로는 여기뿐이다.
class _BattleRecordTile extends StatelessWidget {
  const _BattleRecordTile({required this.record});

  final BattleRecord record;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(record.battle.title),
      subtitle: Row(
        children: [
          BattleTypeBadge(type: record.battle.type),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              '${AppStrings.battleVersus} ${record.otherPartyName}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      trailing: ResultLabel.small(label: record.resultLabel),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => BattleDetailScreen(battleId: record.battle.id)),
      ),
    );
  }
}
