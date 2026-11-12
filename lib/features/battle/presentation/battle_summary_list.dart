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

/// 내 대결 탭 카드(모집·진행 중)의 **공통 뼈대 치수**. 두 카드가 같은 포맷이어야 하므로
/// 숫자를 한 곳에만 둔다(2026-11-12 오너 — "둘이 같은 포맷을 써야지").
///
/// 위 칩 줄과 아래 안내 줄이 **같은 높이**라서 제목이 카드의 정확한 가운데에 선다.
/// 40dp는 모집 카드 우상단 아이콘 버튼의 크기이기도 하다 — 그 버튼이 윗줄 높이를 정한다.
const double myBattleCardBlockHeight = 40;

/// 카드 안쪽 여백. 위아래가 같아야 제목 중앙이 유지되고, 윗줄(칩)이 떠 보이지 않도록
/// 세로는 가로보다 좁게 둔다(2026-11-12 오너 — "속도전 있는 행 padding이 너무 크다").
const EdgeInsets myBattleCardPadding = EdgeInsets.fromLTRB(16, 4, 16, 4);

/// 진행 중인 대결 카드들. 자체 스크롤 뷰를 갖지 않는다 — 내 대결 탭이 모집 구역과 함께
/// 하나의 스크롤 뷰에 담기 때문이다(스크롤 뷰 중첩 금지).
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
    //
    // 짜임새는 **모집 카드와 같다**(2026-11-12 오너 — 두 카드의 디자인이 달라 보이면 안 된다):
    // 곁들이는 정보(칩)가 위 → 제목이 가운데 → 지금 무슨 일인지가 아래.
    // 상태 칩이 오른쪽 끝에서 윗줄로 들어온 것도 그래서다.
    return AppPanel.raised(
      padding: myBattleCardPadding,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => BattleDetailScreen(battleId: battle.id)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 윗줄: 왼쪽은 유형 · 상대, **오른쪽 끝은 지금 상태**(2026-11-12 오너 — "판정중 표시는
          // 우측 상단에 둬"). 모집 카드의 윗줄과 같은 자리·같은 크기이고, 그 카드가 오른쪽 끝에
          // 두 동작을 두는 자리를 여기서는 상태 칩이 쓴다. 버튼이 없는 카드라 줄 높이를
          // `ConstrainedBox`로 직접 맞춘다.
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: myBattleCardBlockHeight),
            child: Row(
              children: [
                Expanded(
                  // 배지 라벨(12dp)과 긴 이름이 한 줄에 못 들어갈 수 있다.
                  // 이름을 줄여 보여 주는 대신 다음 줄로 내린다(readability.md 3-1).
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      BattleTypeBadge(type: battle.type, compact: true),
                      KeepWordsText(
                        '${AppStrings.battleVersus} ${summary.otherPartyName}',
                        style: textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                BattleStatusChip(status: battle.status, compact: true),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // 제목은 카드의 가운데다. 크기도 모집 카드와 같은 titleMedium(18/700) —
          // 칩이 곁들이는 정보로 내려간 자리에서 제목이 유일한 주인공이다.
          KeepWordsText(
            battle.title,
            style: textTheme.titleMedium,
            // 줄 수를 막지 않는다 — 제목은 이 카드가 무엇인지를 말하는 유일한 줄이라
            // 큰 글자 배율에서 뒷말이 잘리면 대결을 알아볼 수 없다.
            // 역할이 카드 제목이라 줄 길이를 고르게 한다(redesign 후속 2 W2).
            wrap: KeepWordsWrap.balanced,
          ),
          const SizedBox(height: 8),
          // 아랫줄: 알림이 없으므로 "그 사이 무슨 일이 있었는지"를 이 블록이 알린다.
          // 모집 카드의 "아직 아무도 참가하지 않았어요"와 같은 자리·같은 높이다.
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: myBattleCardBlockHeight),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 내가 손을 써야 하는 줄만 강조색·굵은 글씨로 띄우고, 그냥 소식은 흐리게 둔다.
                  // 둘을 같은 모양으로 그리면 "들어가서 눌러야 하는가"가 다시 가려진다.
                  // 내 차례 줄은 놓치면 손해 보는 문장이라 bodySmall(13, 메타데이터 전용)이 아니라
                  // titleSmall(16/700)로 둔다(redesign 후속 결정 2).
                  if (statusLine != null)
                    KeepWordsText(
                      statusLine,
                      style: notice.needsMyAction
                          ? textTheme.titleSmall?.copyWith(color: AppPalette.primaryDeep)
                          : textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                    ),
                  // 남은 시간. 어느 시계인지(사진 마감/판정 마감)는 문구가 말한다.
                  if (deadlineLine != null) ...[
                    if (statusLine != null) const SizedBox(height: 4),
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
          ),
        ],
      ),
    );
  }
}
