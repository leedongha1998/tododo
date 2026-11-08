import 'package:flutter/material.dart';

import '../../../core/strings.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/app_panel.dart';
import '../../../core/widgets/keep_words_text.dart';
import '../data/battle.dart';
import '../domain/battle_summary.dart';
import 'battle_chips.dart';
import 'battle_detail_screen.dart';

/// 진행 중인 대결 카드들. 자체 스크롤 뷰를 갖지 않는다 — 내 대결 탭이 모집 구역과 함께
/// 하나의 스크롤 뷰에 담기 때문이다(스크롤 뷰 중첩 금지).
///
/// 제목 · 상대 · 유형 · 상태를 한 줄에 이어 붙이면 무엇이 중요한지 사라진다.
/// 제목을 크게 두고, 상대와 유형은 아래로, 지금 상태는 오른쪽 칩으로 뗀다.
List<Widget> battleSummaryCards(List<BattleSummary> summaries) {
  return [
    for (final summary in summaries) ...[
      BattleSummaryCard(summary: summary),
      // 목록 항목 사이 12(redesign design 4.1).
      const SizedBox(height: 12),
    ],
  ];
}

class BattleSummaryCard extends StatelessWidget {
  const BattleSummaryCard({super.key, required this.summary});

  final BattleSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final Battle battle = summary.battle;
    // 상태 줄과 남은 시간 줄이 같은 시각을 보게 now를 한 번만 구한다(경계에서 두 줄이 어긋나지 않는다).
    // 이 줄은 카드를 다시 그릴 때마다 갱신된다 — 주기적 갱신은 이번 범위가 아니다(audit M19).
    final now = DateTime.now();
    final notice = summary.noticeAt(now);
    final statusLine = notice.line;
    final deadlineLine = summary.deadlineLineAt(now);

    // 떠 있는 카드. 누르는 동안 두께가 꺼진다(물결 없음, design 5.5).
    return AppPanel.raised(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => BattleDetailScreen(battleId: battle.id)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                KeepWordsText(
                  battle.title,
                  // 대결 제목은 목록 본문이라 목록 주 텍스트 슬롯(bodyLarge)을 굵게 쓴다.
                  style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                // 배지 라벨이 14dp가 되면서 긴 이름과 한 줄에 못 들어갈 수 있다.
                // 이름을 줄여 보여 주는 대신 다음 줄로 내린다(readability.md 3-1).
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    BattleTypeBadge(type: battle.type),
                    KeepWordsText(
                      '${AppStrings.battleVersus} ${summary.otherPartyName}',
                      style: textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
                // 알림이 없으므로 "그 사이 무슨 일이 있었는지"를 이 줄이 알린다.
                // 내가 손을 써야 하는 줄만 강조색·굵은 글씨로 띄우고, 그냥 소식은 흐리게 둔다.
                // 둘을 같은 모양으로 그리면 "들어가서 눌러야 하는가"가 다시 가려진다.
                // 내 차례 줄은 놓치면 손해 보는 문장이라 bodySmall(13, 메타데이터 전용)이 아니라
                // titleSmall(16/700)로 둔다(redesign 후속 결정 2).
                if (statusLine != null) ...[
                  const SizedBox(height: 8),
                  KeepWordsText(
                    statusLine,
                    style: notice.needsMyAction
                        ? textTheme.titleSmall?.copyWith(color: AppPalette.primaryDeep)
                        : textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                  ),
                ],
                // 남은 시간. 어느 시계인지(사진 마감/판정 마감)는 문구가 말한다.
                if (deadlineLine != null) ...[
                  const SizedBox(height: 4),
                  KeepWordsText(
                    deadlineLine,
                    style: textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          BattleStatusChip(status: battle.status),
        ],
      ),
    );
  }
}
