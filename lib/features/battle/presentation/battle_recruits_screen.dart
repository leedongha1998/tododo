import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/navigation/app_tab.dart';
import '../../../core/strings.dart';
import '../../../core/theme/pixel_icons.dart';
import '../../../core/widgets/pixel_frame.dart';
import '../../../core/widgets/pixel_icon.dart';
import '../../../core/widgets/pixel_loader.dart';
import '../../../core/widgets/pixel_tag.dart';
import '../../auth/domain/auth_providers.dart';
import '../../profile/domain/profile_providers.dart';
import '../data/open_recruit.dart';
import '../domain/battle_providers.dart';
import 'ai_consent_screen.dart';
import 'battle_chips.dart';
import 'create_battle_screen.dart';
import 'edit_recruit_criteria_screen.dart';
import 'player_card_view.dart';
import 'recruit_detail_sheet.dart';
import 'vs_intro.dart';

class BattleRecruitsScreen extends ConsumerWidget {
  const BattleRecruitsScreen({super.key});

  // 대결을 만들기 전에도 동의를 받는다. 제목과 기준이 AI로 넘어가기 때문이다(3단계 기준 생성).
  Future<void> _openCreate(BuildContext context, WidgetRef ref) async {
    if (!await ensureAiConsent(context, ref)) return;
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CreateBattleScreen()),
    );
  }

  /// 카드 → 모집 상세 시트. 참가는 시트가 하고, 성공하면 여기서 뒷정리를 이어 간다.
  /// 순서: 시트 닫힘 → 목록 갱신 → VS 인트로 → 성공 토스트 → 내 대결 탭.
  Future<void> _openRecruit(BuildContext context, WidgetRef ref, OpenRecruit recruit) async {
    final joined = await showRecruitSheet(context, recruit);
    if (joined == null || !context.mounted) return;

    ref.invalidate(openRecruitsProvider);
    ref.invalidate(myBattlesProvider);
    ref.invalidate(myLimitsProvider);

    // 인트로가 끝난 뒤에 토스트를 띄워 인트로가 토스트를 가리지 않는다.
    // 서버가 방금 active로 바꿨으므로 status는 active로 판단한다.
    final userId = ref.read(authRepositoryProvider).currentUser?.id;
    if (userId != null) {
      final myName = await _myNameForIntro(ref);
      if (!context.mounted) return;
      await maybeShowVsIntro(
        context,
        store: ref.read(vsIntroSeenStoreProvider),
        userId: userId,
        battleId: joined.battle.id,
        status: 'active',
        myName: myName,
        opponentName: joined.creator.displayName,
      );
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text(AppStrings.battleJoined)));
    ref.read(selectedTabProvider.notifier).select(AppTab.myBattles);
  }

  // 내 표시 이름을 못 읽어도 인트로는 "나"로 띄운다. 장식이라 실패를 알리지 않는다.
  Future<String> _myNameForIntro(WidgetRef ref) async {
    try {
      final profile = await ref.read(myProfileProvider.future);
      return profile.displayName;
    } catch (e) {
      debugPrint('myProfileProvider for vs intro failed: $e');
      return AppStrings.battleMe;
    }
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref, String battleId) async {
    try {
      await ref.read(battleRepositoryProvider).cancelBattle(battleId);
      ref.invalidate(myRecruitsProvider);
      ref.invalidate(myLimitsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text(AppStrings.battleRecruitCancelled)));
      }
    } catch (e) {
      debugPrint('cancelBattle failed: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text(AppStrings.battleRecruitCancelFailed)));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final openRecruits = ref.watch(openRecruitsProvider);
    final myRecruits = ref.watch(myRecruitsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.battleFind)),
      // 등록한 모집이 바로 아래 목록에 뜨므로 만들기 버튼도 이 화면에 있는 게 맞다.
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openCreate(context, ref),
        icon: const PixelIcon(PixelIcons.battle),
        label: const Text(AppStrings.battleCreate),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(AppStrings.battleOpenRecruits, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          openRecruits.when(
            data: (recruits) => recruits.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(AppStrings.battleRecruitsEmpty),
                  )
                : Column(
                    children: [
                      for (final recruit in recruits) ...[
                        _OpenRecruitCard(
                          recruit: recruit,
                          onTap: () => _openRecruit(context, ref, recruit),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ],
                  ),
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: PixelLoader.medium()),
            ),
            error: (error, stackTrace) {
              debugPrint('openRecruitsProvider error: $error');
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(AppStrings.battleLoadRecruitsFailed),
              );
            },
          ),
          const SizedBox(height: 24),
          Text(AppStrings.battleMyRecruits, style: Theme.of(context).textTheme.titleMedium),
          myRecruits.when(
            data: (battles) => battles.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(AppStrings.battleRecruitsEmpty),
                  )
                : Column(
                    children: battles
                        .map(
                          (battle) => ListTile(
                            title: Text(battle.title),
                            subtitle: Align(
                              alignment: Alignment.centerLeft,
                              child: BattleTypeBadge(type: battle.type),
                            ),
                            // 매칭 전까지는 기준을 고칠 수 있다. 매칭된 뒤에는 서버가 거부한다.
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                OutlinedButton(
                                  onPressed: () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => EditRecruitCriteriaScreen(battle: battle),
                                    ),
                                  ),
                                  child: const Text(AppStrings.battleCriteriaEditRecruit),
                                ),
                                TextButton(
                                  onPressed: () => _cancel(context, ref, battle.id),
                                  child: const Text(AppStrings.battleRecruitCancel),
                                ),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                  ),
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: PixelLoader.medium()),
            ),
            error: (error, stackTrace) {
              debugPrint('myRecruitsProvider error: $error');
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(AppStrings.battleLoadRecruitsFailed),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// 열린 모집 카드. 무엇을 걸고 누구와 붙는지까지만 보여 주고, 기준 전체는 시트에서 본다.
class _OpenRecruitCard extends StatelessWidget {
  const _OpenRecruitCard({required this.recruit, required this.onTap});

  final OpenRecruit recruit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final battle = recruit.battle;
    final preview = battle.minCriteria.isEmpty ? null : battle.minCriteria.first;

    return PixelFrame.raised(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 대결 제목은 사용자가 입력한 문장이라 본문 글꼴로 둔다.
          Text(battle.title, style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(
            children: [
              BattleTypeBadge(type: battle.type),
              const SizedBox(width: 8),
              PixelTag(
                label: battleDurationLabel(battle.durationHours),
                style: battleStatusTagStyle('draw'),
              ),
            ],
          ),
          if (preview != null) ...[
            const SizedBox(height: 8),
            Text(
              preview,
              style: textTheme.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 12),
          PlayerCardView(card: recruit.creator, label: AppStrings.battleRecruitCreatorLabel),
        ],
      ),
    );
  }
}
