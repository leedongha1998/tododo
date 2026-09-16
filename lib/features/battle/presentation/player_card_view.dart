import 'package:flutter/material.dart';

import '../../../core/strings.dart';
import '../../../core/theme/retro_palette.dart';
import '../../../core/theme/retro_text.dart';
import '../../../core/widgets/initial_badge.dart';
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
        InitialBadge(name: card.displayName, fill: RetroPalette.amber),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (label != null)
                Text(label!, style: textTheme.bodySmall),
              Text(
                card.displayName,
                style: textTheme.bodyLarge,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              if (card.hasStats)
                Row(
                  children: [
                    // 숫자는 픽셀 글꼴.
                    Text(AppStrings.playerScoreLabel(card.score!), style: RetroText.numeric),
                    const SizedBox(width: 12),
                    Text(
                      AppStrings.playerRecordLabel(card.wins!, card.losses!, card.draws!),
                      style: RetroText.numeric,
                    ),
                  ],
                )
              else
                // 탈퇴한 사용자는 점수 행이 없다.
                Text(AppStrings.playerStatsUnknown, style: textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}
