import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todododo/core/strings.dart';
import 'package:todododo/core/theme/app_icons.dart';
import 'package:todododo/core/theme/app_palette.dart';
import 'package:todododo/core/theme/depth_border.dart';
import 'package:todododo/core/widgets/app_tag.dart';
import 'package:todododo/features/battle/domain/battle_outcome.dart';
import 'package:todododo/features/battle/presentation/battle_chips.dart';
import '../../../helpers/text_finders.dart';

/// 상태 칩·결과 라벨의 모양 매핑(redesign design.md 5.3). 서버 값 → 모양만 고른다(승패 계산 없음).
/// 의미 구분 규칙(무 ≠ 미결, 무에 위험색 없음, 무효가 가장 약함)은 retro-theme에서 그대로 이어받는다.
void main() {
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

  group('battleStatusTagStyle', () {
    test('8종 상태가 설계 표대로 매핑된다', () {
      expect(
        battleStatusTagStyle('pending'),
        const AppTagStyle(
          fill: AppPalette.surface,
          textColor: AppPalette.ink,
          borderColor: AppPalette.outline,
          dashed: true,
        ),
      );
      expect(
        battleStatusTagStyle('active'),
        const AppTagStyle(
          fill: AppPalette.primary,
          textColor: AppPalette.surface,
        ),
      );
      expect(
        battleStatusTagStyle('judging'),
        const AppTagStyle(
          fill: AppPalette.judgingPale,
          textColor: AppPalette.ink,
          borderColor: AppPalette.judging,
        ),
      );
      expect(
        battleStatusTagStyle('finished'),
        const AppTagStyle(
          fill: AppPalette.success,
          textColor: AppPalette.surface,
        ),
      );
      expect(
        battleStatusTagStyle('draw'),
        const AppTagStyle(
          fill: AppPalette.surface,
          textColor: AppPalette.ink,
          borderColor: AppPalette.outline,
        ),
      );
      expect(
        battleStatusTagStyle('disputed'),
        const AppTagStyle(
          fill: AppPalette.warningPale,
          textColor: AppPalette.ink,
          borderColor: AppPalette.warning,
          icon: AppIcons.warning,
        ),
      );
      expect(
        battleStatusTagStyle('cancelled'),
        const AppTagStyle(
          fill: AppPalette.sunken,
          textColor: AppPalette.inkMuted,
        ),
      );
      expect(
        battleStatusTagStyle('voided'),
        const AppTagStyle(
          fill: Colors.transparent,
          textColor: AppPalette.inkMuted,
          borderColor: AppPalette.inkMuted,
          dashed: true,
        ),
      );
    });

    test('무승부(시간 종료)와 미결(이의제기 종료)은 모양이 다르다', () {
      final draw = battleStatusTagStyle('draw');
      final disputed = battleStatusTagStyle('disputed');
      expect(draw, isNot(disputed));
      expect(draw.fill, isNot(disputed.fill));
      expect(draw.borderColor, isNot(disputed.borderColor));
    });

    test('미결에는 경고 아이콘이 있고 무승부에는 아이콘이 없다', () {
      expect(battleStatusTagStyle('disputed').icon, AppIcons.warning);
      expect(battleStatusTagStyle('draw').icon, isNull);
    });

    test('무승부에는 위험색·경고색을 쓰지 않는다', () {
      final draw = battleStatusTagStyle('draw');
      const alarmColors = [
        AppPalette.danger,
        AppPalette.dangerPale,
        AppPalette.warning,
        AppPalette.warningPale,
      ];
      expect(alarmColors, isNot(contains(draw.fill)));
      expect(alarmColors, isNot(contains(draw.borderColor)));
      expect(alarmColors, isNot(contains(draw.textColor)));
    });

    test('8종 상태의 모양이 서로 모두 다르다', () {
      expect(
        statuses.map(battleStatusTagStyle).toSet(),
        hasLength(statuses.length),
      );
    });

    test('모집 중과 무승부는 점선 여부로 갈린다', () {
      final pending = battleStatusTagStyle('pending');
      final draw = battleStatusTagStyle('draw');
      expect(pending.dashed, isTrue);
      expect(draw.dashed, isFalse);
      expect(pending.copyWithDashed(false), draw);
    });

    test('무효는 면 투명·점선·흐린 글자다', () {
      final voided = battleStatusTagStyle('voided');
      expect(voided.fill, Colors.transparent);
      expect(voided.dashed, isTrue);
      expect(voided.borderColor, AppPalette.inkMuted);
      expect(voided.textColor, AppPalette.inkMuted);
    });

    test('알 수 없는 상태는 중립(무승부와 같은) 모양이다', () {
      expect(
        battleStatusTagStyle('something_new'),
        battleStatusTagStyle('draw'),
      );
    });

    test('어떤 상태 칩도 떠 있지 않다(두께는 승 라벨에만)', () {
      for (final status in statuses) {
        expect(battleStatusTagStyle(status).raised, isFalse, reason: status);
      }
    });
  });

  // 결과 라벨은 상태가 아니라 서버가 적은 outcome에서 나온다.
  // 종료·미결은 결과가 아니라 상태라서 이 매핑에 없다.
  group('resultTagStyle', () {
    test('승은 앰버 면에 유일하게 두께가 있다', () {
      final win = resultTagStyle(BattleResult.win);
      expect(win.fill, AppPalette.amber);
      expect(win.textColor, AppPalette.ink);
      expect(win.raised, isTrue);

      for (final result in [
        BattleResult.loss,
        BattleResult.draw,
        BattleResult.voided,
      ]) {
        expect(resultTagStyle(result).raised, isFalse, reason: result.name);
      }
    });

    test('패·무가 설계 표대로 매핑된다', () {
      expect(
        resultTagStyle(BattleResult.loss),
        const AppTagStyle(
          fill: AppPalette.inkMuted,
          textColor: AppPalette.surface,
        ),
      );
      expect(resultTagStyle(BattleResult.draw), battleStatusTagStyle('draw'));
    });

    test('네 결과의 모양이 서로 모두 다르다', () {
      expect(
        BattleResult.values.map(resultTagStyle).toSet(),
        hasLength(BattleResult.values.length),
      );
    });

    test('무효 결과 라벨은 무효 칩과 같은 모양이고, 무효 상태 칩은 무효 글자로 보인다', () {
      expect(resultTagStyle(BattleResult.voided), voidedResultTagStyle);
      expect(
        resultTagStyle(BattleResult.voided),
        battleStatusTagStyle('voided'),
      );
      expect(
        resultTagStyle(BattleResult.voided),
        isNot(resultTagStyle(BattleResult.draw)),
      );
      expect(battleStatusLabel('voided'), AppStrings.battleStatusVoided);
    });
  });

  group('AppTag', () {
    testWidgets('미결 칩은 글자 앞에 16dp 경고 아이콘을 테두리색으로 그린다', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(child: BattleStatusChip(status: 'disputed')),
          ),
        ),
      );
      final icon = tester.widget<Icon>(find.byIcon(AppIcons.warning));
      expect(icon.size, 16);
      expect(icon.color, AppPalette.warning);
      expect(findText(AppStrings.battleStatusDisputed), findsOneWidget);
    });

    testWidgets('무승부 칩에는 아이콘이 없다', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(child: BattleStatusChip(status: 'draw')),
          ),
        ),
      );
      expect(find.byType(Icon), findsNothing);
    });

    testWidgets('승 라벨만 2dp ink 두께가 있는 DepthBorder로 그려진다', (tester) async {
      DepthBorder shapeOf(BattleResult result) {
        final container = tester.widget<Container>(
          find
              .descendant(
                of: find.byType(AppTag),
                matching: find.byType(Container),
              )
              .first,
        );
        return (container.decoration! as ShapeDecoration).shape as DepthBorder;
      }

      for (final result in BattleResult.values) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(child: ResultLabel.small(result: result)),
            ),
          ),
        );
        final shape = shapeOf(result);
        expect(shape.radius, 8, reason: result.name);
        if (result == BattleResult.win) {
          expect(shape.depth, 2);
          expect(shape.depthColor, AppPalette.ink);
        } else {
          expect(shape.depth, 0, reason: result.name);
        }
      }
    });
  });

  group('BattleTypeBadge', () {
    test('유형 강조색은 한 곳에서만 정한다(배지 색 칸과 모집 카드 색 띠가 같이 쓴다)', () {
      expect(battleTypeAccent('speed'), AppPalette.amber);
      expect(battleTypeAccent('quality'), AppPalette.mint);
    });

    testWidgets('배지는 테두리 없이 색 칸·16dp 아이콘·글자로만 구분된다', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(child: BattleTypeBadge(type: 'speed')),
          ),
        ),
      );

      // 카드 안 테두리 사각형을 줄인 변경이다(recruit-list-scan.md S3) — redesign에서도 유지.
      final box = tester.widget<Container>(
        find.descendant(
          of: find.byType(BattleTypeBadge),
          matching: find.byType(Container).first,
        ),
      );
      final shape = (box.decoration! as ShapeDecoration).shape as DepthBorder;
      expect(shape.side.style, BorderStyle.none);
      expect(shape.radius, 8);

      // 색을 구분하지 못해도 읽을 수 있어야 하므로 글자와 아이콘은 그대로다.
      expect(findText(AppStrings.battleTypeSpeed), findsOneWidget);
      expect(find.byIcon(AppIcons.speed), findsOneWidget);
      expect(tester.widget<Icon>(find.byIcon(AppIcons.speed)).size, 16);
      expect(tester.getSize(find.byIcon(AppIcons.speed)), const Size(16, 16));
    });

    testWidgets('품질전 배지는 인장 리본 아이콘이다', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(child: BattleTypeBadge(type: 'quality')),
          ),
        ),
      );
      expect(find.byIcon(AppIcons.quality), findsOneWidget);
      expect(findText(AppStrings.battleTypeQuality), findsOneWidget);
    });
  });
}

extension on AppTagStyle {
  AppTagStyle copyWithDashed(bool dashed) => AppTagStyle(
    fill: fill,
    textColor: textColor,
    borderColor: borderColor,
    dashed: dashed,
    raised: raised,
    icon: icon,
  );
}
