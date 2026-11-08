import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:todododo/core/theme/app_palette.dart';
import 'package:todododo/core/theme/app_theme.dart';
import 'package:todododo/core/theme/depth_border.dart';
import 'package:todododo/core/widgets/app_button_styles.dart';

/// design-judging-buttons 2A: 위험 토널·위험 텍스트·작은 크기.
void main() {
  const rest = <WidgetState>{};
  const pressed = {WidgetState.pressed};
  const disabled = {WidgetState.disabled};

  group('AppButtonStyles.dangerTonal(위험 토널 — 동의 철회)', () {
    final style = AppButtonStyles.dangerTonal;

    test('평소: dangerPale 면 + dangerDeep 라벨·아이콘', () {
      expect(style.backgroundColor!.resolve(rest), AppPalette.dangerPale);
      expect(style.foregroundColor!.resolve(rest), AppPalette.dangerDeep);
      expect(style.iconColor!.resolve(rest), AppPalette.dangerDeep);
    });

    test('누름: dangerTonalPressed 면, 라벨은 그대로 dangerDeep', () {
      expect(style.backgroundColor!.resolve(pressed), AppPalette.dangerTonalPressed);
      expect(style.foregroundColor!.resolve(pressed), AppPalette.dangerDeep);
    });

    test('비활성: sunken 면 + inkDisabled', () {
      expect(style.backgroundColor!.resolve(disabled), AppPalette.sunken);
      expect(style.foregroundColor!.resolve(disabled), AppPalette.inkDisabled);
      expect(style.iconColor!.resolve(disabled), AppPalette.inkDisabled);
    });

    test('테두리·모양은 정하지 않는다 — 보조(토널) 테마의 "테두리·두께 없음"을 따른다', () {
      expect(style.side, isNull);
      expect(style.shape, isNull);
      final merged = style.merge(AppTheme.light.outlinedButtonTheme.style);
      expect(merged.side!.resolve(rest), BorderSide.none);
      expect((merged.shape!.resolve(rest)! as DepthBorder).depth, 0);
    });
  });

  group('AppButtonStyles.dangerText(위험 텍스트 — 포기·모집 취소)', () {
    final style = AppButtonStyles.dangerText;

    test('평소: 투명 면 + danger 라벨·아이콘', () {
      expect(style.backgroundColor!.resolve(rest), Colors.transparent);
      expect(style.foregroundColor!.resolve(rest), AppPalette.danger);
      expect(style.iconColor!.resolve(rest), AppPalette.danger);
    });

    test('누름: dangerPale 면 + dangerDeep 라벨(danger 글자는 dangerPale 위 4.27로 미달)', () {
      expect(style.backgroundColor!.resolve(pressed), AppPalette.dangerPale);
      expect(style.foregroundColor!.resolve(pressed), AppPalette.dangerDeep);
      expect(
        contrastRatio(style.foregroundColor!.resolve(pressed)!, AppPalette.dangerPale),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('비활성: inkDisabled, 면 투명', () {
      expect(style.foregroundColor!.resolve(disabled), AppPalette.inkDisabled);
      expect(style.backgroundColor!.resolve(disabled), Colors.transparent);
    });
  });

  group('AppButtonStyles.compact(작은 크기)', () {
    const style = AppButtonStyles.compact;

    test('면 최소 높이 40, 알약(모서리 20, 두께 없음), 아이콘 20, 터치 영역은 48로 채운다', () {
      expect(style.minimumSize!.resolve(rest)!.height, 40);
      final shape = style.shape!.resolve(rest)! as DepthBorder;
      expect(shape.radius, 20);
      expect(shape.depth, 0);
      expect(style.iconSize!.resolve(rest), 20);
      expect(style.tapTargetSize, MaterialTapTargetSize.padded);
    });

    test('색은 정하지 않는다 — 등급 스타일 위에 얹는다', () {
      expect(style.backgroundColor, isNull);
      expect(style.foregroundColor, isNull);
      final merged = AppButtonStyles.dangerText.merge(style);
      expect(merged.foregroundColor!.resolve(rest), AppPalette.danger);
      expect(merged.minimumSize!.resolve(rest)!.height, 40);
    });

    testWidgets('실제로 그리면 면 40·터치 48', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Center(
            child: OutlinedButton(
              style: AppButtonStyles.compact,
              onPressed: () {},
              child: const Text('기준 수정'),
            ),
          ),
        ),
      ));
      final outer = tester.getSize(find.byType(OutlinedButton));
      expect(outer.height, 48);
      final face = tester.getSize(
        find.descendant(of: find.byType(OutlinedButton), matching: find.byType(Material)),
      );
      expect(face.height, 40);
    });
  });
}
