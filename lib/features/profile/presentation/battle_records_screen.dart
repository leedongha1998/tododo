import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/strings.dart';
import '../../../core/widgets/app_loader.dart';
import '../../../core/widgets/app_panel.dart';
import '../../../core/widgets/keep_words_text.dart';
import '../../battle/presentation/battle_chips.dart';
import '../../battle/presentation/battle_detail_screen.dart';
import '../domain/battle_record.dart';
import '../domain/profile_providers.dart';

/// 지난 대결 목록. 2026-11-12에 프로필 탭에서 **떼어 내 메뉴 뒤로 보냈다**(오너 안 B) —
/// 프로필을 열 때마다 가장 먼저 보이던 것이 전적 목록이라 점수·계정·동의가 그 아래로 밀렸다.
///
/// 끝난 대결은 내 대결 탭에서 빠지므로 지난 증거와 결과를 다시 볼 경로는 여기뿐이다.
class BattleRecordsScreen extends ConsumerWidget {
  const BattleRecordsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recordsAsync = ref.watch(battleRecordsProvider);

    return Scaffold(
      appBar: AppBar(title: const KeepWordsText(AppStrings.profileHistorySection)),
      body: recordsAsync.when(
        data: (records) {
          if (records.isEmpty) {
            return const Padding(
              // 화면 가장자리 20(redesign design 4.1).
              padding: EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: KeepWordsText(AppStrings.profileRecordEmpty),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            itemCount: records.length,
            // 목록 항목 사이 12(redesign design 4.1).
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) => BattleRecordTile(record: records[index]),
          );
        },
        loading: () => const Center(child: AppLoader.medium()),
        error: (error, stackTrace) {
          debugPrint('battleRecordsProvider error: $error');
          return const Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: KeepWordsText(AppStrings.profileLoadRecordFailed),
          );
        },
      ),
    );
  }
}

/// 한 대결을 떠 있는 카드 한 장으로 그려 항목끼리의 경계가 보이게 한다.
class BattleRecordTile extends StatelessWidget {
  const BattleRecordTile({super.key, required this.record});

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
                  // 글꼴은 본문이지만 역할은 카드 제목이라 줄 길이를 고르게 한다(redesign 후속 2 W2).
                  wrap: KeepWordsWrap.balanced,
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
