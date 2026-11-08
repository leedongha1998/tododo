import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:todododo/core/strings.dart';
import 'package:todododo/core/theme/app_theme.dart';
import 'package:todododo/features/battle/data/player_card.dart';
import 'package:todododo/features/battle/presentation/player_card_view.dart';

void main() {
  // redesign 후속 결정 6: 이름이 점수·전적 줄보다 가늘고 작아 위계가 뒤집혀 보였다.
  testWidgets('상대 카드는 이름이 점수·전적 줄보다 크고 가늘지 않다', (tester) async {
    const card = PlayerCard(userId: 'u1', displayName: '도윤', score: 12, wins: 4, losses: 2, draws: 1);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(body: PlayerCardView(card: card, label: AppStrings.battleOpponent)),
      ),
    );

    final name = tester.widget<Text>(find.text('도윤')).style!;
    final score = tester.widget<Text>(find.text(AppStrings.playerScoreLabel(12))).style!;
    final record = tester.widget<Text>(find.text(AppStrings.playerRecordLabel(4, 2, 1))).style!;
    final label = tester.widget<Text>(find.text(AppStrings.battleOpponent)).style!;

    for (final numbers in [score, record]) {
      expect(name.fontSize, greaterThan(numbers.fontSize!));
      expect(name.fontWeight!.value, greaterThanOrEqualTo(numbers.fontWeight!.value));
    }
    // 자리 이름("상대")은 메타데이터라 이름보다 작다.
    expect(label.fontSize, lessThan(name.fontSize!));
  });
}
