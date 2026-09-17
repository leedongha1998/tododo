import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/strings.dart';
import '../../../core/theme/pixel_icons.dart';
import '../../../core/theme/retro_text.dart';
import '../../../core/widgets/pixel_frame.dart';
import '../../../core/widgets/pixel_icon.dart';
import '../../../core/widgets/pixel_loader.dart';
import '../../../core/widgets/retro_button_styles.dart';
import '../../auth/domain/auth_providers.dart';
import '../../battle/domain/battle_outcome.dart';
import '../../battle/presentation/battle_chips.dart';
import '../../battle/presentation/battle_detail_screen.dart';
import '../data/player_stats.dart';
import '../domain/battle_record.dart';
import '../domain/profile_providers.dart';
import 'ai_consent_section.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(myProfileProvider);
    final statsAsync = ref.watch(myPlayerStatsProvider);
    final recordsAsync = ref.watch(battleRecordsProvider);
    // 무효는 점수에도 승/패/무에도 들어가지 않는다. 목록에 무효가 있을 때만 그 이유를 적는다.
    final hasVoidedRecord =
        recordsAsync.value?.any((record) => record.result == BattleResult.voided) ?? false;

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
          // 점수와 승/패/무는 서버 player_stats가 정답이다. 목록을 세어 만들지 않는다
          // (무효·취소는 서버가 애초에 세지 않고, 완료한 패배도 전적에서는 그냥 패다).
          _StatsFrame(statsAsync: statsAsync, hasVoidedRecord: hasVoidedRecord),
          const SizedBox(height: 24),
          Text(
            AppStrings.profileHistorySection,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          recordsAsync.when(
            data: (records) {
              if (records.isEmpty) return const Text(AppStrings.profileRecordEmpty);
              // 지난 대결은 한 장씩 떠 있는 카드로 나눈다.
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final record in records) ...[
                    _BattleRecordTile(record: record),
                    const SizedBox(height: 8),
                  ],
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
          // 대결 참여의 전제 조건이라 계정 섹션 위에 둔다.
          const AiConsentSection(),
          const SizedBox(height: 16),
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

/// 점수와 승/패/무 한 줄. 서버가 정한 값을 그대로 보여 주고 순위는 만들지 않는다.
/// 유형(속도전/품질전)을 나누지 않는다 — spec은 합산 전적만 요구한다.
class _StatsFrame extends StatelessWidget {
  const _StatsFrame({required this.statsAsync, required this.hasVoidedRecord});

  final AsyncValue<PlayerStats> statsAsync;
  final bool hasVoidedRecord;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return PixelFrame.flat(
      title: AppStrings.profileRecordSection,
      child: statsAsync.when(
        data: (stats) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                // 점수가 이 창의 주인공이라 유일하게 큰 픽셀 숫자다.
                Text(
                  AppStrings.playerScoreLabel(stats.score),
                  style: RetroText.pixel(20, bold: true),
                ),
                const SizedBox(width: 12),
                Text(
                  AppStrings.playerRecordLabel(stats.wins, stats.losses, stats.draws),
                  style: RetroText.numeric,
                ),
              ],
            ),
            if (hasVoidedRecord) ...[
              const SizedBox(height: 8),
              Text(AppStrings.profileVoidedExcluded, style: textTheme.bodySmall),
            ],
          ],
        ),
        loading: () => const Center(child: PixelLoader.small()),
        error: (error, stackTrace) {
          debugPrint('myPlayerStatsProvider error: $error');
          return const Text(AppStrings.profileLoadStatsFailed);
        },
      ),
    );
  }
}

/// 끝난 대결은 내 대결 탭에서 빠지므로, 지난 증거와 결과를 다시 볼 경로는 여기뿐이다.
/// 한 대결을 떠 있는 카드 한 장으로 그려 항목끼리의 경계가 보이게 한다.
class _BattleRecordTile extends StatelessWidget {
  const _BattleRecordTile({required this.record});

  final BattleRecord record;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final mutedColor = Theme.of(context).colorScheme.onSurfaceVariant;

    return PixelFrame.raised(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => BattleDetailScreen(battleId: record.battle.id)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 대결 제목은 사용자가 입력한 문장이라 본문 글꼴로 둔다.
                Text(
                  record.battle.title,
                  style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    BattleTypeBadge(type: record.battle.type),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        '${AppStrings.battleVersus} ${record.otherPartyName}',
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodyMedium?.copyWith(color: mutedColor),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ResultLabel.small(result: record.result),
        ],
      ),
    );
  }
}
