import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'pixel_border.dart';
import 'retro_palette.dart';
import 'retro_text.dart';

/// 앱 전체의 시각 규칙 — 도트·픽셀 레트로 라이트 테마 하나(`docs/specs/retro-theme/design.md` 1·3.1장).
///
/// 개별 화면이 모양을 지정하지 않아도 Material 위젯에 저절로 입혀지도록 규칙을 전부 여기에 둔다.
/// 색은 `ColorScheme.fromSeed`로 만들지 않고 팔레트에서 슬롯마다 명시한다 — 화면이 `scheme.xxx`를
/// 써도 팔레트 밖의 색이 나오지 않게 하기 위해서다. 런처 아이콘 배경도 같은 `RetroPalette.primary`다.
class AppTheme {
  AppTheme._();

  static const _border2 = BorderSide(color: RetroPalette.ink, width: 2);
  static const _disabledBorder = BorderSide(color: RetroPalette.inkDisabled, width: 2);

  static const _raised = PixelBorder(depth: 2);
  static const _pressed = PixelBorder(depth: 2, pressed: true);
  static const _flat = PixelBorder();

  static final _pressOverlay = RetroPalette.ink.withValues(alpha: 0.12);
  static final _barrier = RetroPalette.ink.withValues(alpha: 0.55);

  static const colorScheme = ColorScheme(
    brightness: Brightness.light,
    primary: RetroPalette.primary,
    onPrimary: RetroPalette.surface,
    primaryContainer: RetroPalette.primaryPale,
    onPrimaryContainer: RetroPalette.ink,
    secondary: RetroPalette.amber,
    onSecondary: RetroPalette.ink,
    secondaryContainer: RetroPalette.amber,
    onSecondaryContainer: RetroPalette.ink,
    tertiary: RetroPalette.mint,
    onTertiary: RetroPalette.ink,
    tertiaryContainer: RetroPalette.lavender,
    onTertiaryContainer: RetroPalette.ink,
    error: RetroPalette.danger,
    onError: RetroPalette.surface,
    errorContainer: RetroPalette.dangerPale,
    onErrorContainer: RetroPalette.ink,
    surface: RetroPalette.surface,
    onSurface: RetroPalette.ink,
    onSurfaceVariant: RetroPalette.inkMuted,
    surfaceBright: RetroPalette.surface,
    surfaceContainerLowest: RetroPalette.surface,
    surfaceContainerLow: RetroPalette.surface,
    surfaceContainer: RetroPalette.paper,
    surfaceContainerHigh: RetroPalette.sunken,
    surfaceContainerHighest: RetroPalette.sunken,
    surfaceDim: RetroPalette.sunken,
    outline: RetroPalette.ink,
    outlineVariant: RetroPalette.line,
    shadow: RetroPalette.ink,
    scrim: RetroPalette.ink,
    inverseSurface: RetroPalette.ink,
    onInverseSurface: RetroPalette.surface,
    inversePrimary: RetroPalette.primaryPale,
    surfaceTint: Colors.transparent,
  );

  static ThemeData get light {
    final text = RetroText.textTheme();

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: colorScheme,
      textTheme: text,
      scaffoldBackgroundColor: RetroPalette.paper,
      canvasColor: RetroPalette.paper,
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      appBarTheme: AppBarTheme(
        backgroundColor: RetroPalette.paper,
        foregroundColor: RetroPalette.ink,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        shape: const Border(bottom: BorderSide(color: RetroPalette.ink, width: 4)),
        iconTheme: const IconThemeData(color: RetroPalette.ink, size: 24),
        actionsIconTheme: const IconThemeData(color: RetroPalette.ink, size: 24),
        titleTextStyle: text.titleLarge,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
      ),
      navigationBarTheme: NavigationBarThemeData(
        // 아이콘만으로는 탭 이름을 짐작해야 한다. 라벨은 항상 보인다.
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        backgroundColor: RetroPalette.surface,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        height: 72,
        indicatorColor: RetroPalette.primary,
        indicatorShape: _flat,
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 24,
            color: states.contains(WidgetState.selected)
                ? RetroPalette.surface
                : RetroPalette.inkMuted,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? text.labelMedium!.copyWith(fontWeight: FontWeight.w700)
              : text.labelMedium!,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: _blockButton(text, background: RetroPalette.primary, foreground: RetroPalette.surface),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: _blockButton(text, background: RetroPalette.surface, foreground: RetroPalette.ink),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: _blockButton(text, background: RetroPalette.surface, foreground: RetroPalette.ink),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.pressed)
                ? RetroPalette.sunken
                : Colors.transparent,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? RetroPalette.inkDisabled
                : RetroPalette.ink,
          ),
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(0),
          shadowColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: const WidgetStatePropertyAll(PixelBorder(side: BorderSide.none)),
          minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
          padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 12)),
          textStyle: WidgetStatePropertyAll(text.labelLarge),
          iconSize: const WidgetStatePropertyAll(24),
          splashFactory: NoSplash.splashFactory,
          enableFeedback: false,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? RetroPalette.inkDisabled
                : RetroPalette.ink,
          ),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.pressed)
                ? RetroPalette.sunken
                : Colors.transparent,
          ),
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.pressed)
                ? _flat
                : const PixelBorder(side: BorderSide.none),
          ),
          minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
          iconSize: const WidgetStatePropertyAll(24),
          splashFactory: NoSplash.splashFactory,
          enableFeedback: false,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: RetroPalette.primary,
        foregroundColor: RetroPalette.surface,
        splashColor: Colors.transparent,
        focusColor: Colors.transparent,
        hoverColor: Colors.transparent,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        disabledElevation: 0,
        shape: _raised,
        iconSize: 24,
        sizeConstraints: const BoxConstraints.tightFor(width: 56, height: 56),
        extendedSizeConstraints: const BoxConstraints(minHeight: 56, minWidth: 56),
        extendedTextStyle: text.labelLarge,
        enableFeedback: false,
      ),
      cardTheme: const CardThemeData(
        color: RetroPalette.surface,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: _raised,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: RetroPalette.surface,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        shape: const PixelBorder(innerColor: RetroPalette.surface),
        titleTextStyle: text.headlineSmall,
        contentTextStyle: text.bodyMedium,
        barrierColor: _barrier,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: RetroPalette.surface,
        modalBackgroundColor: RetroPalette.surface,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        modalElevation: 0,
        shape: const PixelBorder(
          side: BorderSide(color: RetroPalette.ink, width: 4),
          topOnly: true,
        ),
        showDragHandle: true,
        dragHandleColor: RetroPalette.ink,
        dragHandleSize: const Size(32, 4),
        modalBarrierColor: _barrier,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: RetroPalette.ink,
        contentTextStyle: text.bodyMedium!.copyWith(color: RetroPalette.surface),
        actionTextColor: RetroPalette.amber,
        elevation: 0,
        shape: _flat,
        insetPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: RetroPalette.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        hintStyle: text.bodyLarge!.copyWith(color: RetroPalette.inkMuted),
        counterStyle: text.labelMedium,
        border: const OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: _border2),
        enabledBorder:
            const OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: _border2),
        disabledBorder:
            const OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: _disabledBorder),
        focusedBorder: const _DoubleOutlineInputBorder(
          borderSide: BorderSide(color: RetroPalette.primary, width: 2),
        ),
        errorBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: RetroPalette.danger, width: 2),
        ),
        focusedErrorBorder: const _DoubleOutlineInputBorder(
          borderSide: BorderSide(color: RetroPalette.danger, width: 2),
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: RetroPalette.ink,
        selectionColor: RetroPalette.amber.withValues(alpha: 0.5),
        selectionHandleColor: RetroPalette.ink,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) return RetroPalette.sunken;
            return states.contains(WidgetState.selected)
                ? RetroPalette.primary
                : RetroPalette.surface;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) return RetroPalette.inkDisabled;
            return states.contains(WidgetState.selected)
                ? RetroPalette.surface
                : RetroPalette.ink;
          }),
          iconColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) return RetroPalette.inkDisabled;
            return states.contains(WidgetState.selected)
                ? RetroPalette.surface
                : RetroPalette.ink;
          }),
          overlayColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.pressed) ? _pressOverlay : Colors.transparent,
          ),
          side: const WidgetStatePropertyAll(_border2),
          shape: const WidgetStatePropertyAll(_flat),
          textStyle: WidgetStatePropertyAll(text.labelLarge),
          minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
          splashFactory: NoSplash.splashFactory,
          enableFeedback: false,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: const RoundedRectangleBorder(),
        side: WidgetStateBorderSide.resolveWith(
          (states) => states.contains(WidgetState.disabled) ? _disabledBorder : _border2,
        ),
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? RetroPalette.ink : Colors.transparent,
        ),
        checkColor: const WidgetStatePropertyAll(RetroPalette.surface),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        splashRadius: 0,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: RetroPalette.ink,
        textColor: RetroPalette.ink,
        titleTextStyle: text.bodyLarge,
        subtitleTextStyle: text.bodyMedium!.copyWith(color: RetroPalette.inkMuted),
        enableFeedback: false,
      ),
      dividerTheme: const DividerThemeData(color: RetroPalette.line, thickness: 2, space: 2),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: RetroPalette.ink,
        linearTrackColor: RetroPalette.sunken,
        circularTrackColor: RetroPalette.sunken,
        refreshBackgroundColor: RetroPalette.surface,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: const BoxDecoration(color: RetroPalette.ink),
        textStyle: text.bodySmall!.copyWith(color: RetroPalette.surface),
      ),
      expansionTileTheme: const ExpansionTileThemeData(
        shape: Border(),
        collapsedShape: Border(),
      ),
    );
  }

  /// 주·보조 버튼 공통 모양. 2dp ink 테두리 + 바닥 두께, 눌리면 두께가 위·왼쪽으로 가고 ink 12%가 겹친다.
  /// 비활성은 sunken 면 + inkDisabled 글자·테두리, 바닥 두께 없음.
  static ButtonStyle _blockButton(
    TextTheme text, {
    required Color background,
    required Color foreground,
  }) {
    return ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled) ? RetroPalette.sunken : background,
      ),
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled) ? RetroPalette.inkDisabled : foreground,
      ),
      iconColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled) ? RetroPalette.inkDisabled : foreground,
      ),
      overlayColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.pressed) ? _pressOverlay : Colors.transparent,
      ),
      side: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return _disabledBorder;
        // 포커스는 테두리를 주 강조색으로 바꿔 드러낸다.
        if (states.contains(WidgetState.focused)) {
          return const BorderSide(color: RetroPalette.primary, width: 2);
        }
        return _border2;
      }),
      shape: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return _flat;
        if (states.contains(WidgetState.pressed)) return _pressed;
        return _raised;
      }),
      elevation: const WidgetStatePropertyAll(0),
      shadowColor: const WidgetStatePropertyAll(Colors.transparent),
      minimumSize: const WidgetStatePropertyAll(Size(64, 48)),
      padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 16)),
      textStyle: WidgetStatePropertyAll(text.labelLarge),
      iconSize: const WidgetStatePropertyAll(24),
      splashFactory: NoSplash.splashFactory,
      enableFeedback: false,
    );
  }
}

/// 포커스된 입력 필드: 바깥 2dp 강조색 + 안쪽 2dp ink(합 4dp). 직각.
class _DoubleOutlineInputBorder extends OutlineInputBorder {
  const _DoubleOutlineInputBorder({required super.borderSide})
      : super(borderRadius: BorderRadius.zero);

  @override
  _DoubleOutlineInputBorder copyWith({
    BorderSide? borderSide,
    BorderRadius? borderRadius,
    double? gapPadding,
  }) {
    return _DoubleOutlineInputBorder(borderSide: borderSide ?? this.borderSide);
  }

  // 기본 보간은 부모 타입으로 되돌아가 안쪽 선을 잃는다. 한 번에 바꾼다.
  @override
  ShapeBorder? lerpFrom(ShapeBorder? a, double t) => t < 0.5 ? a : this;

  @override
  ShapeBorder? lerpTo(ShapeBorder? b, double t) => t < 0.5 ? this : b;

  @override
  void paint(
    Canvas canvas,
    Rect rect, {
    double? gapStart,
    double gapExtent = 0.0,
    double gapPercentage = 0.0,
    TextDirection? textDirection,
  }) {
    super.paint(
      canvas,
      rect,
      gapStart: gapStart,
      gapExtent: gapExtent,
      gapPercentage: gapPercentage,
      textDirection: textDirection,
    );
    final width = borderSide.width;
    canvas.drawRect(
      rect.deflate(width * 1.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..color = RetroPalette.ink,
    );
  }
}
