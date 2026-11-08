import 'package:flutter/material.dart';

import '../../../core/strings.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/initial_badge.dart';
import '../../../core/widgets/keep_words_text.dart';
import '../data/player_card.dart';

/// 상대·모집 생성자의 전적 한 줄(이니셜 + 이름 + 점수 + 승/패/무).
/// 모집 목록 카드, 모집 상세 시트, 대결 상세 헤더가 같은 모양을 쓴다.
class PlayerCardView extends StatelessWidget {
  const PlayerCardView({super.key, required this.card, this.label});

  final PlayerCard card;

  /// "만든 사람" / "상대" 같은 자리 이름(선택).
  final String? label;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // 상대는 앰버, 나는 primary(VS 인트로와 같은 규칙).
        InitialBadge(name: card.displayName, fill: AppPalette.secondary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (label != null)
                KeepWordsText(label!, style: textTheme.bodySmall),
              // 이름이 이 카드의 주인공이다. 아래 점수·전적(numberSmall 16/700)보다 위에 서도록
              // titleMedium(18/700)으로 둔다 — bodyLarge(16/400)면 숫자 줄보다 가늘고 작아 위계가 뒤집힌다
              // (redesign 후속 결정 6).
              KeepWordsText(
                card.displayName,
                style: textTheme.titleMedium,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              if (card.hasStats)
                // 숫자 슬롯(16/700, 고정폭). 큰 배율에서 한 줄을 넘으면 전적이 다음 줄로 내려간다.
                Wrap(
                  spacing: 12,
                  children: [
                    KeepWordsText(AppStrings.playerScoreLabel(card.score!), style: AppText.numberSmall),
                    KeepWordsText(
                      AppStrings.playerRecordLabel(card.wins!, card.losses!, card.draws!),
                      style: AppText.numberSmall,
                    ),
                  ],
                )
              else
                // 탈퇴한 사용자는 점수 행이 없다.
                KeepWordsText(AppStrings.playerStatsUnknown, style: textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}
