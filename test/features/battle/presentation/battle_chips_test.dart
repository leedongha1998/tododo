import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todododo/core/strings.dart';
import 'package:todododo/core/theme/pixel_border.dart';
import 'package:todododo/core/theme/pixel_icons.dart';
import 'package:todododo/core/theme/retro_palette.dart';
import 'package:todododo/core/widgets/pixel_icon.dart';
import 'package:todododo/core/widgets/pixel_tag.dart';
import 'package:todododo/features/battle/domain/battle_outcome.dart';
import 'package:todododo/features/battle/presentation/battle_chips.dart';

void main() {
  group('battleStatusTagStyle', () {
    test('8종 상태가 설계 표대로 매핑된다', () {
      expect(
        battleStatusTagStyle('pending'),
        const PixelTagStyle(
          fill: RetroPalette.surface,
          textColor: RetroPalette.ink,
          borderColor: RetroPalette.ink,
          dashed: true,
        ),
      );
      expect(
        battleStatusTagStyle('active'),
        const PixelTagStyle(
          fill: RetroPalette.primary,
          textColor: RetroPalette.surface,
          borderColor: RetroPalette.ink,
        ),
      );
      expect(
        battleStatusTagStyle('judging'),
        const PixelTagStyle(
          fill: RetroPalette.lavender,
          textColor: RetroPalette.ink,
          borderColor: RetroPalette.ink,
        ),
      );
      expect(
        battleStatusTagStyle('finished'),
        const PixelTagStyle(
          fill: RetroPalette.success,
          textColor: RetroPalette.surface,
          borderColor: RetroPalette.ink,
        ),
      );
      expect(
        battleStatusTagStyle('draw'),
        const PixelTagStyle(
          fill: RetroPalette.sunken,
          textColor: RetroPalette.ink,
          borderColor: RetroPalette.ink,
        ),
      );
      expect(
        battleStatusTagStyle('disputed'),
        const PixelTagStyle(
          fill: RetroPalette.dangerPale,
          textColor: RetroPalette.ink,
          borderColor: RetroPalette.danger,
        ),
      );
      expect(
        battleStatusTagStyle('cancelled'),
        const PixelTagStyle(fill: RetroPalette.sunken, textColor: RetroPalette.inkMuted),
      );
      expect(
        battleStatusTagStyle('voided'),
        const PixelTagStyle(
          fill: Colors.transparent,
          textColor: RetroPalette.inkMuted,
          borderColor: RetroPalette.inkMuted,
          dashed: true,
        ),
      );
    });

    test('무승부(시간 종료)와 미결(이의제기 종료)은 모양이 다르다', () {
      expect(battleStatusTagStyle('draw'), isNot(battleStatusTagStyle('disputed')));
    });

    test('무승부에는 위험색을 쓰지 않는다', () {
      final draw = battleStatusTagStyle('draw');
      const dangerColors = [RetroPalette.danger, RetroPalette.dangerPale];
      expect(dangerColors, isNot(contains(draw.fill)));
      expect(dangerColors, isNot(contains(draw.borderColor)));
      expect(dangerColors, isNot(contains(draw.textColor)));
    });

    test('8종 상태의 모양이 서로 모두 다르다', () {
      const statuses = [
        'pending',
        'active',
        'judging',
        'finished',
        'draw',
        'disputed',
        'cancelled',
        'voided',
      ];
      expect(statuses.map(battleStatusTagStyle).toSet(), hasLength(statuses.length));
    });

    test('알 수 없는 상태는 중립(무승부와 같은) 모양이다', () {
      expect(battleStatusTagStyle('something_new'), battleStatusTagStyle('draw'));
    });
  });

  // 결과 라벨은 상태가 아니라 서버가 적은 outcome에서 나온다.
  // 종료·미결은 결과가 아니라 상태라서 이 매핑에 없다.
  group('resultTagStyle', () {
    test('승은 앰버 면에 유일하게 바닥 두께가 있다', () {
      final win = resultTagStyle(BattleResult.win);
      expect(win.fill, RetroPalette.amber);
      expect(win.textColor, RetroPalette.ink);
      expect(win.raised, isTrue);

      for (final result in [BattleResult.loss, BattleResult.draw, BattleResult.voided]) {
        expect(resultTagStyle(result).raised, isFalse, reason: result.name);
      }
    });

    test('패·무가 설계 표대로 매핑된다', () {
      expect(
        resultTagStyle(BattleResult.loss),
        const PixelTagStyle(
          fill: RetroPalette.inkMuted,
          textColor: RetroPalette.surface,
          borderColor: RetroPalette.ink,
        ),
      );
      expect(
        resultTagStyle(BattleResult.draw),
        const PixelTagStyle(
          fill: RetroPalette.sunken,
          textColor: RetroPalette.ink,
          borderColor: RetroPalette.ink,
        ),
      );
    });

    test('네 결과의 모양이 서로 모두 다르다', () {
      expect(BattleResult.values.map(resultTagStyle).toSet(), hasLength(BattleResult.values.length));
    });

    test('무효 결과 라벨은 무효 모양으로, 무효 상태 칩은 무효 글자로 보인다', () {
      expect(resultTagStyle(BattleResult.voided), voidedResultTagStyle);
      expect(resultTagStyle(BattleResult.voided), isNot(resultTagStyle(BattleResult.draw)));
      expect(battleStatusLabel('voided'), AppStrings.battleStatusVoided);
    });

    test('무효는 면 없음·점선·흐린 글자로 가장 약하다', () {
      expect(voidedResultTagStyle.fill, Colors.transparent);
      expect(voidedResultTagStyle.dashed, isTrue);
      expect(voidedResultTagStyle.borderColor, RetroPalette.inkMuted);
      expect(voidedResultTagStyle.textColor, RetroPalette.inkMuted);
    });
  });

  group('BattleTypeBadge', () {
    test('유형 강조색은 한 곳에서만 정한다(배지 색 칸과 모집 카드 색 띠가 같이 쓴다)', () {
      expect(battleTypeAccent('speed'), RetroPalette.amber);
      expect(battleTypeAccent('quality'), RetroPalette.mint);
    });

    testWidgets('배지는 테두리 없이 색 칸·아이콘·글자로만 구분된다', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Center(child: BattleTypeBadge(type: 'speed'))),
        ),
      );

      // 카드 안 2dp ink 사각형을 셋에서 둘로 줄인 변경이다(recruit-list-scan.md S3).
      // 테두리를 얇게(1dp) 하지 않고 없앤다 — 2dp 격자와 계단 한 칸 규칙이 그대로 남는다.
      final box = tester.widget<Container>(
        find.descendant(
          of: find.byType(BattleTypeBadge),
          matching: find.byType(Container).first,
        ),
      );
      final shape = (box.decoration! as ShapeDecoration).shape as PixelBorder;
      expect(shape.side.style, BorderStyle.none);

      // 색을 구분하지 못해도 읽을 수 있어야 하므로 글자와 아이콘은 그대로다.
      expect(find.text(AppStrings.battleTypeSpeed), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is PixelIcon && widget.icon == PixelIcons.speed,
        ),
        findsOneWidget,
      );
    });
  });
}
