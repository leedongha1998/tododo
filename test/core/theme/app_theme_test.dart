import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todododo/core/theme/app_palette.dart';
import 'package:todododo/core/theme/app_theme.dart';
import 'package:todododo/core/theme/depth_border.dart';

/// redesign 테마(design 4·5.1). 흐린 그림자 없음, 버튼 상태별 모양, 애니메이션 줄이기, 팔레트 밖 색 없음.
void main() {
  final theme = AppTheme.light;
  const pressed = {WidgetState.pressed};
  const disabled = {WidgetState.disabled};
  const rest = <WidgetState>{};

  test('흐린 그림자(elevation)를 쓰지 않고 surfaceTint는 투명이다', () {
    expect(theme.colorScheme.surfaceTint, Colors.transparent);
    expect(theme.appBarTheme.elevation, 0);
    expect(theme.appBarTheme.scrolledUnderElevation, 0);
    expect(theme.navigationBarTheme.elevation, 0);
    expect(theme.cardTheme.elevation, 0);
    expect(theme.dialogTheme.elevation, 0);
    expect(theme.bottomSheetTheme.elevation, 0);
    expect(theme.bottomSheetTheme.modalElevation, 0);
    expect(theme.snackBarTheme.elevation, 0);
    expect(theme.floatingActionButtonTheme.elevation, 0);
    expect(theme.floatingActionButtonTheme.highlightElevation, 0);
    for (final style in [
      theme.filledButtonTheme.style!,
      theme.outlinedButtonTheme.style!,
      theme.elevatedButtonTheme.style!,
      theme.textButtonTheme.style!,
    ]) {
      expect(style.elevation!.resolve(rest), 0);
      expect(style.elevation!.resolve(pressed), 0);
    }
  });

  group('주 버튼(FilledButton)', () {
    final style = theme.filledButtonTheme.style!;

    test('안 눌림은 3dp 두께, 눌림은 면이 내려온 DepthBorder, 비활성은 납작하다', () {
      final restShape = style.shape!.resolve(rest)! as DepthBorder;
      expect(restShape.depth, 3);
      expect(restShape.pressed, isFalse);

      final pressedShape = style.shape!.resolve(pressed)! as DepthBorder;
      expect(pressedShape.pressed, isTrue);
      expect(pressedShape.depth, 3);

      final disabledShape = style.shape!.resolve(disabled)! as DepthBorder;
      expect(disabledShape.depth, 0);
    });

    test('면색은 primary, 비활성은 sunken + inkDisabled', () {
      expect(style.backgroundColor!.resolve(rest), AppPalette.primary);
      expect(style.foregroundColor!.resolve(rest), AppPalette.surface);
      expect(style.backgroundColor!.resolve(disabled), AppPalette.sunken);
      expect(style.foregroundColor!.resolve(disabled), AppPalette.inkDisabled);
    });

    test('라벨이 면과 함께 내려가도록 여백이 상태별로 바뀐다', () {
      final restPadding = style.padding!.resolve(rest)! as EdgeInsets;
      final pressedPadding = style.padding!.resolve(pressed)! as EdgeInsets;
      expect(restPadding.bottom, 3);
      expect(restPadding.top, 0);
      expect(pressedPadding.top, 3);
      expect(pressedPadding.bottom, 0);
    });

    test('최소 높이 52(두께 포함)', () {
      expect(style.minimumSize!.resolve(rest)!.height, 52);
    });
  });

  // design-judging-buttons 2A: 두께는 주 행동만. 보조는 토널 면 + 테두리·두께 없음, 누름 = 면색.
  group('보조 버튼(Outlined·Elevated)은 토널이다', () {
    for (final (name, style) in [
      ('OutlinedButton', theme.outlinedButtonTheme.style!),
      ('ElevatedButton', theme.elevatedButtonTheme.style!),
    ]) {
      test('$name: primaryTonal 면 + primaryDeep 라벨, 누름은 primaryTonalPressed, 비활성은 sunken', () {
        expect(style.backgroundColor!.resolve(rest), AppPalette.primaryTonal);
        expect(style.foregroundColor!.resolve(rest), AppPalette.primaryDeep);
        expect(style.iconColor!.resolve(rest), AppPalette.primaryDeep);
        expect(style.backgroundColor!.resolve(pressed), AppPalette.primaryTonalPressed);
        expect(style.foregroundColor!.resolve(pressed), AppPalette.primaryDeep);
        expect(style.backgroundColor!.resolve(disabled), AppPalette.sunken);
        expect(style.foregroundColor!.resolve(disabled), AppPalette.inkDisabled);
      });

      test('$name: 테두리 없음, 두께 없음(안 눌림·눌림 모두), 포커스는 2dp primary 링', () {
        expect(style.side!.resolve(rest), BorderSide.none);
        expect(style.side!.resolve(pressed), BorderSide.none);
        expect(
          style.side!.resolve({WidgetState.focused}),
          const BorderSide(color: AppPalette.primary, width: 2),
        );
        for (final states in [rest, pressed, disabled]) {
          final shape = style.shape!.resolve(states)! as DepthBorder;
          expect(shape.depth, 0, reason: '$states');
          expect(shape.radius, 12);
        }
        // 두께가 없으니 라벨도 내려가지 않는다.
        expect(style.padding!.resolve(rest), style.padding!.resolve(pressed));
      });

      test('$name: 최소 높이 48(주 버튼 52보다 낮다)', () {
        expect(style.minimumSize!.resolve(rest)!.height, 48);
      });
    }
  });

  test('화면에서 두께를 갖는 버튼 등급은 주(FilledButton)뿐이다', () {
    expect((theme.filledButtonTheme.style!.shape!.resolve(rest)! as DepthBorder).depth, 3);
    expect((theme.outlinedButtonTheme.style!.shape!.resolve(rest)! as DepthBorder).depth, 0);
    expect((theme.textButtonTheme.style!.shape!.resolve(rest)! as DepthBorder).depth, 0);
  });

  test('되돌아옴은 120ms, 애니메이션 줄이기면 0ms', () {
    expect(theme.filledButtonTheme.style!.animationDuration, const Duration(milliseconds: 120));

    final reduced = AppTheme.build(reduceMotion: true);
    for (final style in [
      reduced.filledButtonTheme.style!,
      reduced.outlinedButtonTheme.style!,
      reduced.elevatedButtonTheme.style!,
      reduced.textButtonTheme.style!,
      reduced.iconButtonTheme.style!,
    ]) {
      expect(style.animationDuration, Duration.zero);
    }
    // 눌림 자체는 상태 표시라 남는다.
    final pressedShape = reduced.filledButtonTheme.style!.shape!.resolve(pressed);
    expect((pressedShape! as DepthBorder).pressed, isTrue);
  });

  test('입력 필드 포커스는 이중선이 아닌 2dp primary 단일선, 오류는 2dp danger', () {
    final input = theme.inputDecorationTheme;
    final focused = input.focusedBorder!;
    expect(focused.runtimeType, OutlineInputBorder);
    expect(focused.borderSide, const BorderSide(color: AppPalette.primary, width: 2));
    expect(input.errorBorder!.borderSide, const BorderSide(color: AppPalette.danger, width: 2));
    expect(input.focusedErrorBorder!.runtimeType, OutlineInputBorder);
    expect(
      input.enabledBorder!.borderSide,
      const BorderSide(color: AppPalette.outline, width: 1.5),
    );
  });

  test('Pretendard가 앱 기본 글꼴이다', () {
    expect(theme.textTheme.bodyMedium!.fontFamily, 'Pretendard');
    expect(theme.textTheme.titleLarge!.fontFamily, 'Pretendard');
  });

  test('ColorScheme의 모든 색이 AppPalette 값이다(팔레트 밖 색 없음)', () {
    final palette = <Color>{
      AppPalette.background,
      AppPalette.surface,
      AppPalette.sunken,
      AppPalette.line,
      AppPalette.edge,
      AppPalette.outline,
      AppPalette.ink,
      AppPalette.inkMuted,
      AppPalette.inkDisabled,
      AppPalette.success,
      AppPalette.successPale,
      AppPalette.danger,
      AppPalette.dangerPale,
      AppPalette.warning,
      AppPalette.warningPale,
      AppPalette.amber,
      AppPalette.mint,
      AppPalette.primary,
      AppPalette.primaryDeep,
      AppPalette.primaryPale,
      AppPalette.judging,
      AppPalette.judgingPale,
    };
    final scheme = theme.colorScheme;
    final used = <String, Color>{
      'primary': scheme.primary,
      'onPrimary': scheme.onPrimary,
      'primaryContainer': scheme.primaryContainer,
      'onPrimaryContainer': scheme.onPrimaryContainer,
      'secondary': scheme.secondary,
      'onSecondary': scheme.onSecondary,
      'secondaryContainer': scheme.secondaryContainer,
      'onSecondaryContainer': scheme.onSecondaryContainer,
      'tertiary': scheme.tertiary,
      'onTertiary': scheme.onTertiary,
      'tertiaryContainer': scheme.tertiaryContainer,
      'onTertiaryContainer': scheme.onTertiaryContainer,
      'error': scheme.error,
      'onError': scheme.onError,
      'errorContainer': scheme.errorContainer,
      'onErrorContainer': scheme.onErrorContainer,
      'surface': scheme.surface,
      'onSurface': scheme.onSurface,
      'onSurfaceVariant': scheme.onSurfaceVariant,
      'surfaceBright': scheme.surfaceBright,
      'surfaceDim': scheme.surfaceDim,
      'surfaceContainerLowest': scheme.surfaceContainerLowest,
      'surfaceContainerLow': scheme.surfaceContainerLow,
      'surfaceContainer': scheme.surfaceContainer,
      'surfaceContainerHigh': scheme.surfaceContainerHigh,
      'surfaceContainerHighest': scheme.surfaceContainerHighest,
      'outline': scheme.outline,
      'outlineVariant': scheme.outlineVariant,
      'shadow': scheme.shadow,
      'scrim': scheme.scrim,
      'inverseSurface': scheme.inverseSurface,
      'onInverseSurface': scheme.onInverseSurface,
      'inversePrimary': scheme.inversePrimary,
    };
    for (final entry in used.entries) {
      expect(palette, contains(entry.value), reason: entry.key);
    }
    expect(scheme.tertiaryContainer, AppPalette.judgingPale);
    expect(scheme.outline, AppPalette.outline);
    expect(scheme.outlineVariant, AppPalette.line);
    expect(scheme.surfaceContainer, AppPalette.background);
  });
}
