import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todododo/core/theme/app_icons.dart';
import 'package:todododo/core/theme/app_palette.dart';
import 'package:todododo/core/theme/app_theme.dart';
import 'package:todododo/core/theme/depth_border.dart';
import 'package:todododo/core/widgets/app_panel.dart';
import 'package:todododo/core/widgets/keep_words_text.dart';
import '../../helpers/text_finders.dart';

/// AppPanel(design 5.2): 변형별 모양, 제목 띠 없음, 누름, 애니메이션 줄이기.
void main() {
  Future<void> pump(
    WidgetTester tester,
    Widget panel, {
    bool disableAnimations = false,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(disableAnimations: disableAnimations),
            child: Scaffold(body: Center(child: panel)),
          ),
        ),
      ),
    );
  }

  ShapeDecoration decorationOf(WidgetTester tester) {
    final container = tester.widget<AnimatedContainer>(
      find.byType(AnimatedContainer),
    );
    return container.decoration! as ShapeDecoration;
  }

  DepthBorder shapeOf(WidgetTester tester) =>
      decorationOf(tester).shape as DepthBorder;

  testWidgets('raised는 흰 면 + 1dp line + 2dp edge 두께, 모서리 16', (tester) async {
    await pump(tester, const AppPanel.raised(child: Text('본문')));
    final shape = shapeOf(tester);
    expect(decorationOf(tester).color, AppPalette.surface);
    expect(shape.depth, 2);
    expect(shape.depthColor, AppPalette.edge);
    expect(shape.side.color, AppPalette.line);
    expect(shape.side.width, 1);
    expect(shape.radius, 16);
    expect(shape.pressed, isFalse);
  });

  testWidgets('flat은 흰 면 + 1dp line, 두께 없음', (tester) async {
    await pump(tester, const AppPanel.flat(child: Text('본문')));
    final shape = shapeOf(tester);
    expect(decorationOf(tester).color, AppPalette.surface);
    expect(shape.depth, 0);
    expect(shape.side.color, AppPalette.line);
  });

  testWidgets('inset은 sunken 면, 테두리 없음', (tester) async {
    await pump(tester, const AppPanel.inset(child: Text('본문')));
    expect(decorationOf(tester).color, AppPalette.sunken);
    expect(shapeOf(tester).side, BorderSide.none);
    expect(shapeOf(tester).depth, 0);
  });

  testWidgets('tone은 성격별 연한 면, 테두리 없음, 모서리 12, 기본 아이콘', (tester) async {
    const cases = {
      AppTone.info: (AppPalette.primaryPale, AppIcons.info, AppPalette.primary),
      AppTone.success: (
        AppPalette.successPale,
        AppIcons.pass,
        AppPalette.success,
      ),
      AppTone.danger: (
        AppPalette.dangerPale,
        AppIcons.warning,
        AppPalette.danger,
      ),
    };
    for (final MapEntry(key: tone, value: (fill, icon, color))
        in cases.entries) {
      await pump(tester, AppPanel.tone(tone: tone, child: const Text('안내')));
      expect(decorationOf(tester).color, fill, reason: '$tone');
      expect(shapeOf(tester).side, BorderSide.none, reason: '$tone');
      expect(shapeOf(tester).radius, 12, reason: '$tone');
      final drawn = tester.widget<Icon>(find.byType(Icon));
      expect(drawn.icon, icon, reason: '$tone');
      expect(drawn.color, color, reason: '$tone');
      expect(drawn.size, 24, reason: '$tone');
    }

    await pump(
      tester,
      const AppPanel.tone(tone: AppTone.neutral, child: Text('안내')),
    );
    expect(decorationOf(tester).color, AppPalette.sunken);
    expect(find.byType(Icon), findsNothing, reason: 'neutral은 기본 아이콘이 없다');

    await pump(
      tester,
      const AppPanel.tone(
        tone: AppTone.neutral,
        icon: AppIcons.clock,
        child: Text('안내'),
      ),
    );
    expect(tester.widget<Icon>(find.byType(Icon)).color, AppPalette.inkMuted);
  });

  testWidgets('제목은 ink 띠 없이 묶음 안 첫 줄 titleSmall 글자로만 그린다', (tester) async {
    await pump(tester, const AppPanel.flat(title: '최소 기준', child: Text('본문')));
    final title = tester.widget<KeepWordsText>(findText('최소 기준'));
    final theme = AppTheme.light.textTheme.titleSmall!;
    expect(title.style!.fontSize, theme.fontSize);
    expect(title.style!.fontWeight, theme.fontWeight);
    expect(title.style!.color, AppPalette.ink);
    final bands = tester
        .widgetList<ColoredBox>(
          find.ancestor(
            of: findText('최소 기준'),
            matching: find.byType(ColoredBox),
          ),
        )
        .where((box) => box.color == AppPalette.ink);
    expect(bands, isEmpty);
  });

  testWidgets('onTap이 있으면 버튼으로 읽히고 누르는 동안 눌림이 된다', (tester) async {
    var taps = 0;
    await pump(
      tester,
      AppPanel.raised(onTap: () => taps++, child: const Text('카드')),
    );

    expect(tester.getSemantics(findText('카드')), isSemantics(isButton: true));

    final gesture = await tester.startGesture(
      tester.getCenter(findText('카드')),
    );
    await tester.pump();
    expect(shapeOf(tester).pressed, isTrue);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(shapeOf(tester).pressed, isFalse);
    expect(taps, 1);
  });

  testWidgets('onTap이 없으면 버튼으로 읽히지 않는다', (tester) async {
    await pump(tester, const AppPanel.raised(child: Text('카드')));
    expect(
      find.ancestor(
        of: findText('카드'),
        matching: find.byType(GestureDetector),
      ),
      findsNothing,
    );
  });

  testWidgets('되돌아옴은 120ms, 애니메이션 줄이기면 즉시', (tester) async {
    await pump(tester, AppPanel.raised(onTap: () {}, child: const Text('카드')));
    expect(
      tester.widget<AnimatedContainer>(find.byType(AnimatedContainer)).duration,
      AppPanel.releaseDuration,
    );

    await pump(
      tester,
      AppPanel.raised(onTap: () {}, child: const Text('카드')),
      disableAnimations: true,
    );
    expect(
      tester.widget<AnimatedContainer>(find.byType(AnimatedContainer)).duration,
      Duration.zero,
    );
  });
}
