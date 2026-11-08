import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/strings.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_button_styles.dart';
import '../../../core/widgets/app_loader.dart';
import '../../../core/widgets/app_panel.dart';
import '../../../core/widgets/keep_words_text.dart';
import '../../auth/domain/auth_providers.dart';
import '../../battle/domain/battle_outcome.dart';
import '../../battle/presentation/battle_chips.dart';
import '../../battle/presentation/battle_detail_screen.dart';
import '../data/player_stats.dart';
import '../domain/battle_record.dart';
import '../domain/profile_providers.dart';
import 'ai_consent_section.dart';
import 'notification_section.dart';

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
      appBar: AppBar(title: const KeepWordsText(AppStrings.profileTitle)),
      body: ListView(
        // 화면 가장자리 20(redesign design 4.1).
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          profileAsync.when(
            data: (profile) =>
                KeepWordsText(profile.displayName, style: Theme.of(context).textTheme.titleLarge),
            loading: () => const Center(child: AppLoader.medium()),
            error: (error, stackTrace) {
              debugPrint('myProfileProvider error: $error');
              return KeepWordsText(AppStrings.profileLoadFailed);
            },
          ),
          const SizedBox(height: 24),
          // 점수와 승/패/무는 서버 player_stats가 정답이다. 목록을 세어 만들지 않는다
          // (무효·취소는 서버가 애초에 세지 않고, 완료한 패배도 전적에서는 그냥 패다).
          _StatsFrame(statsAsync: statsAsync, hasVoidedRecord: hasVoidedRecord),
          const SizedBox(height: 24),
          KeepWordsText(
            AppStrings.profileHistorySection,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          recordsAsync.when(
            data: (records) {
              if (records.isEmpty) return const KeepWordsText(AppStrings.profileRecordEmpty);
              // 지난 대결은 한 장씩 떠 있는 카드로 나눈다.
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final record in records) ...[
                    _BattleRecordTile(record: record),
                    // 목록 항목 사이 12(redesign design 4.1).
                    const SizedBox(height: 12),
                  ],
                ],
              );
            },
            loading: () => const Center(child: AppLoader.medium()),
            error: (error, stackTrace) {
              debugPrint('battleRecordsProvider error: $error');
              return KeepWordsText(AppStrings.profileLoadRecordFailed);
            },
          ),
          const SizedBox(height: 24),
          // 알림이 꺼져 있을 때만 보인다. 켜져 있으면 자리를 차지하지 않는다.
          const NotificationSection(),
          // 대결 참여의 전제 조건이라 계정 섹션 위에 둔다.
          const AiConsentSection(),
          const SizedBox(height: 24),
          // 탭바가 생기면서 앱바 아이콘이 사라졌다. 계정 관련 동작은 전부 이 창 하나에 모은다.
          AppPanel.flat(
            title: AppStrings.accountSection,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OutlinedButton.icon(
                  onPressed: () => ref.read(authRepositoryProvider).signOut(),
                  icon: const Icon(AppIcons.logout),
                  label: const KeepWordsText(AppStrings.logout),
                ),
                const SizedBox(height: 8),
                // 번들한 글꼴(OFL)의 고지를 사용자가 찾을 수 있는 자리.
                TextButton.icon(
                  style: TextButton.styleFrom(alignment: Alignment.centerLeft),
                  onPressed: () => showLicensePage(
                    context: context,
                    applicationName: AppStrings.appName,
                  ),
                  icon: const Icon(AppIcons.document),
                  label: const KeepWordsText(AppStrings.openSourceLicenses),
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
        title: const KeepWordsText(AppStrings.accountDeleteConfirmTitle),
        content: const KeepWordsText(AppStrings.accountDeleteConfirmMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const KeepWordsText(AppStrings.cancel),
          ),
          FilledButton(
            style: AppButtonStyles.danger,
            onPressed: () => Navigator.of(context).pop(true),
            child: const KeepWordsText(AppStrings.accountDeleteConfirm),
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
      messenger.showSnackBar(const SnackBar(content: KeepWordsText(AppStrings.accountDeleteDone)));
    } catch (error) {
      debugPrint('deleteAccount error: $error');
      if (mounted) setState(() => _isDeleting = false);
      messenger.showSnackBar(const SnackBar(content: KeepWordsText(AppStrings.accountDeleteFailed)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      style: AppButtonStyles.danger,
      // 진행 중에는 누를 수 없는 모양 + 라벨 자리 로더(버튼 크기 유지).
      onPressed: _isDeleting ? null : _confirmAndDelete,
      icon: const Icon(AppIcons.accountDelete),
      label: _isDeleting ? const AppLoader.small() : const KeepWordsText(AppStrings.accountDelete),
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

    return AppPanel.flat(
      title: AppStrings.profileRecordSection,
      child: statsAsync.when(
        data: (stats) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 큰 배율(32 × 1.5)에서 한 줄을 넘으면 전적이 다음 줄로 내려간다(design 9.2-9). Wrap은 글자 기준선을
            // 맞추지 못해 아래 끝을 맞춘다(숫자 슬롯 둘 다 아래 여백이 작아 기준선과 거의 같다).
            Wrap(
              spacing: 12,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.end,
              children: [
                // 점수가 이 묶음의 주인공이라 유일하게 큰 숫자다.
                KeepWordsText(AppStrings.playerScoreLabel(stats.score), style: AppText.numberLarge),
                KeepWordsText(
                  AppStrings.playerRecordLabel(stats.wins, stats.losses, stats.draws),
                  style: AppText.numberSmall,
                ),
              ],
            ),
            if (hasVoidedRecord) ...[
              const SizedBox(height: 8),
              KeepWordsText(AppStrings.profileVoidedExcluded, style: textTheme.bodySmall),
            ],
          ],
        ),
        loading: () => const Center(child: AppLoader.small()),
        error: (error, stackTrace) {
          debugPrint('myPlayerStatsProvider error: $error');
          return const KeepWordsText(AppStrings.profileLoadStatsFailed);
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

    return AppPanel.raised(
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
                KeepWordsText(
                  record.battle.title,
                  style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    BattleTypeBadge(type: record.battle.type),
                    const SizedBox(width: 8),
                    Flexible(
                      child: KeepWordsText(
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
