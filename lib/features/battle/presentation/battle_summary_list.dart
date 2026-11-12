import 'package:flutter/material.dart';

import '../../../core/remaining_time.dart';
import '../../../core/strings.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/app_panel.dart';
import '../../../core/widgets/keep_words_text.dart';
import '../../../core/widgets/time_ticker.dart';
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
    // **카드마다 자기 시계를 갖는다**(2026-11-12, audit M19를 여기서 닫는다). 목록을 통째로
    // 한 타이머에 담지 않는 이유는 카드마다 마감이 다르고, 화면 밖으로 나간 카드는
    // `ListView.builder`가 버리면서 그 타이머까지 함께 거두기 때문이다 — 보이는 카드만 깨어난다.
    //
    // 깨어나는 잦기는 그 카드의 남은 시간이 정한다(`nextDeadlineTick`). 하루 넘게 남은 대결은
    // 한 시간에 한 번이고, 1분 속도전만 1초에 한 번이다.
    return TimeTicker(nextChange: _nextDeadlineChange, builder: _buildCard);
  }

  /// 이 카드가 다음에 다시 그려져야 할 때까지의 간격. 흐르는 시계는 하나다 — `deadlineLineAt`과
  /// 같은 갈래로 고른다(판정 창이면 판정 기한, 그 밖이면 제출 마감).
  Duration? _nextDeadlineChange(DateTime now) {
    final battle = summary.battle;
    final deadline = battle.status == 'judging'
        ? battle.judgeDeadlineAt
        : battle.deadlineAt;
    if (deadline == null) return null;
    return nextDeadlineTick(deadline, now);
  }

  Widget _buildCard(BuildContext context, DateTime now) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final Battle battle = summary.battle;
    // 상태 줄과 남은 시간 줄이 같은 시각을 보게 now를 한 번만 구한다(경계에서 두 줄이 어긋나지 않는다).
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
                  // 글꼴은 본문이지만 역할은 카드 제목이라 줄 길이를 고르게 한다(redesign 후속 2 W2).
                  wrap: KeepWordsWrap.balanced,
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
