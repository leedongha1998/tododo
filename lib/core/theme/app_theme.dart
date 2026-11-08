import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_icons.dart';
import 'app_palette.dart';
import 'app_text.dart';
import 'depth_border.dart';

/// 앱 전체의 시각 규칙 — redesign 라이트 테마 하나(`docs/specs/redesign/design.md` 4·5.1장).
///
/// 개별 화면이 모양을 지정하지 않아도 Material 위젯에 저절로 입혀지도록 규칙을 전부 여기에 둔다.
/// 색은 `ColorScheme.fromSeed`로 만들지 않고 팔레트에서 슬롯마다 명시한다 — 화면이 `scheme.xxx`를
/// 써도 팔레트 밖의 색이 나오지 않게 하기 위해서다.
///
/// 흐린 그림자(elevation)는 쓰지 않는다. 떠 있음 = 아래 단단한 두께([DepthBorder]), 층 = 면색 차이.
/// 물결(ripple)도 쓰지 않는다 — 눌림은 두께로 보인다.
class AppTheme {
  AppTheme._();

  /// 버튼이 손을 뗀 뒤 되돌아오는 길이(design 4.2). 누를 때는 [DepthBorder] 보간이 즉시 처리한다.
  static const buttonAnimation = Duration(milliseconds: 120);

  /// 떠 있는 버튼(FAB)이 있는 목록의 아래 여백. 끝까지 내리면 마지막 항목이 FAB 위로 완전히 드러난다:
  /// FAB 56 + Scaffold 바깥 여백 16 + 두께 3 + 사이 간격 21 = 96. FAB 크기는 글자 배율과 무관하다
  /// (할 일·대결 찾기 목록이 쓴다 — redesign 후속 결정 4, 1.5배 끝까지 내린 상태를 위젯 테스트로 고정).
  static const fabClearance = 56.0 + 16 + _buttonDepth + 21;

  static const _buttonRadius = 12.0;
  static const _buttonDepth = 3.0;

  static const _raisedButton = DepthBorder(radius: _buttonRadius, depth: _buttonDepth);
  static const _pressedButton =
      DepthBorder(radius: _buttonRadius, depth: _buttonDepth, pressed: true);
  static const _flatButton = DepthBorder(radius: _buttonRadius);

  /// ButtonStyleButton은 모양의 dimensions로 자식을 밀지 않는다. 라벨이 면과 함께 내려가도록 상태별 여백을 준다.
  static const _restPadding = EdgeInsets.fromLTRB(16, 0, 16, _buttonDepth);
  static const _pressedPadding = EdgeInsets.fromLTRB(16, _buttonDepth, 16, 0);
  static const _flatPadding = EdgeInsets.symmetric(horizontal: 16);

  static const _controlRadius = BorderRadius.all(Radius.circular(12));
  static const _controlSide = BorderSide(color: AppPalette.outline, width: 1.5);
  static const _disabledControlSide = BorderSide(color: AppPalette.line, width: 1.5);

  static final _barrier = AppPalette.ink.withValues(alpha: 0.5);

  static const colorScheme = ColorScheme(
    brightness: Brightness.light,
    primary: AppPalette.primary,
    onPrimary: AppPalette.surface,
    primaryContainer: AppPalette.primaryPale,
    onPrimaryContainer: AppPalette.ink,
    secondary: AppPalette.secondary,
    onSecondary: AppPalette.ink,
    secondaryContainer: AppPalette.secondary,
    onSecondaryContainer: AppPalette.ink,
    tertiary: AppPalette.mint,
    onTertiary: AppPalette.ink,
    tertiaryContainer: AppPalette.judgingPale,
    onTertiaryContainer: AppPalette.ink,
    error: AppPalette.danger,
    onError: AppPalette.surface,
    errorContainer: AppPalette.dangerPale,
    onErrorContainer: AppPalette.ink,
    surface: AppPalette.surface,
    onSurface: AppPalette.ink,
    onSurfaceVariant: AppPalette.inkMuted,
    surfaceBright: AppPalette.surface,
    surfaceContainerLowest: AppPalette.surface,
    surfaceContainerLow: AppPalette.surface,
    surfaceContainer: AppPalette.background,
    surfaceContainerHigh: AppPalette.sunken,
    surfaceContainerHighest: AppPalette.sunken,
    surfaceDim: AppPalette.sunken,
    outline: AppPalette.outline,
    outlineVariant: AppPalette.line,
    shadow: AppPalette.ink,
    scrim: AppPalette.ink,
    inverseSurface: AppPalette.ink,
    onInverseSurface: AppPalette.surface,
    inversePrimary: AppPalette.primaryPale,
    surfaceTint: Colors.transparent,
  );

  /// 기본 테마.
  static ThemeData get light => build();

  /// [reduceMotion]이면 버튼이 되돌아오는 움직임도 즉시다(눌림 자체는 상태 표시라 남는다).
  /// 테마는 MediaQuery를 못 보므로 `MaterialApp.builder`가 `MediaQuery.disableAnimationsOf`를 보고 고른다.
  static ThemeData build({bool reduceMotion = false}) {
    final text = AppText.textTheme();
    final buttonDuration = reduceMotion ? Duration.zero : buttonAnimation;

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: colorScheme,
      fontFamily: AppText.family,
      textTheme: text,
      scaffoldBackgroundColor: AppPalette.background,
      canvasColor: AppPalette.background,
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      actionIconTheme: ActionIconThemeData(
        backButtonIconBuilder: (context) => const Icon(AppIcons.back),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppPalette.background,
        foregroundColor: AppPalette.ink,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: AppPalette.ink, size: 24),
        actionsIconTheme: const IconThemeData(color: AppPalette.ink, size: 24),
        titleTextStyle: text.titleLarge,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
      ),
      navigationBarTheme: NavigationBarThemeData(
        // 아이콘만으로는 탭 이름을 짐작해야 한다. 라벨은 항상 보인다.
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        backgroundColor: AppPalette.surface,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        height: 72,
        indicatorColor: AppPalette.primaryPale,
        indicatorShape: const StadiumBorder(),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 24,
            color: states.contains(WidgetState.selected)
                ? AppPalette.primaryDeep
                : AppPalette.inkMuted,
          ),
        ),
        // 선택은 색 + 표시기 + 아이콘 채움 + 굵기 넷으로 구분한다.
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? text.labelSmall!
              : text.labelSmall!.copyWith(
                  fontWeight: FontWeight.w400,
                  color: AppPalette.inkMuted,
                ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: _depthButton(
          text,
          background: AppPalette.primary,
          foreground: AppPalette.surface,
          // 면이 primary라 primary 링은 보이지 않는다. 주 버튼만 ink 링으로 포커스를 드러낸다.
          focusRing: AppPalette.ink,
          animationDuration: buttonDuration,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: _depthButton(
          text,
          background: AppPalette.surface,
          foreground: AppPalette.ink,
          side: _controlSide,
          focusRing: AppPalette.primary,
          animationDuration: buttonDuration,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: _depthButton(
          text,
          background: AppPalette.surface,
          foreground: AppPalette.ink,
          side: _controlSide,
          focusRing: AppPalette.primary,
          animationDuration: buttonDuration,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.pressed)
                ? AppPalette.sunken
                : Colors.transparent,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? AppPalette.inkDisabled
                : AppPalette.primaryDeep,
          ),
          iconColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? AppPalette.inkDisabled
                : AppPalette.primaryDeep,
          ),
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(0),
          shadowColor: const WidgetStatePropertyAll(Colors.transparent),
          side: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.focused)
                ? const BorderSide(color: AppPalette.primary, width: 2)
                : BorderSide.none,
          ),
          shape: const WidgetStatePropertyAll(_flatButton),
          minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
          padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 12)),
          textStyle: WidgetStatePropertyAll(text.labelLarge),
          iconSize: const WidgetStatePropertyAll(24),
          animationDuration: buttonDuration,
          splashFactory: NoSplash.splashFactory,
          enableFeedback: false,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? AppPalette.inkDisabled
                : AppPalette.ink,
          ),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.pressed)
                ? AppPalette.sunken
                : Colors.transparent,
          ),
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          side: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.focused)
                ? const BorderSide(color: AppPalette.primary, width: 2)
                : BorderSide.none,
          ),
          shape: const WidgetStatePropertyAll(_flatButton),
          minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
          iconSize: const WidgetStatePropertyAll(24),
          animationDuration: buttonDuration,
          splashFactory: NoSplash.splashFactory,
          enableFeedback: false,
        ),
      ),
      // FAB 테마의 shape는 상태별 값을 받지 않는다 — 눌림 없이 정적 두께(plan "설계와 다른 점" 2).
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppPalette.primary,
        foregroundColor: AppPalette.surface,
        splashColor: Colors.transparent,
        focusColor: Colors.transparent,
        hoverColor: Colors.transparent,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        disabledElevation: 0,
        shape: const DepthBorder(radius: 16, depth: _buttonDepth),
        iconSize: 24,
        sizeConstraints: const BoxConstraints.tightFor(width: 56, height: 56),
        extendedSizeConstraints: const BoxConstraints(minHeight: 56, minWidth: 56),
        extendedTextStyle: text.labelLarge,
        enableFeedback: false,
      ),
      cardTheme: const CardThemeData(
        color: AppPalette.surface,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: DepthBorder(
          side: BorderSide(color: AppPalette.line, width: 1),
          radius: 16,
          depth: 2,
          depthColor: AppPalette.edge,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppPalette.surface,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(20))),
        titleTextStyle: text.headlineSmall,
        contentTextStyle: text.bodyMedium,
        barrierColor: _barrier,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: AppPalette.surface,
        modalBackgroundColor: AppPalette.surface,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        modalElevation: 0,
        shape: const DepthBorder(radius: 24, topOnly: true),
        showDragHandle: true,
        dragHandleColor: AppPalette.outline,
        dragHandleSize: const Size(32, 4),
        modalBarrierColor: _barrier,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppPalette.ink,
        contentTextStyle: text.bodyMedium!.copyWith(color: AppPalette.surface),
        actionTextColor: AppPalette.amber,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: _controlRadius),
        insetPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppPalette.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: text.bodyLarge!.copyWith(color: AppPalette.inkMuted),
        // 글자 수 카운터("13/60")는 메타데이터다 — 보조 글자색·보통 굵기(redesign 후속 결정 7).
        // 입력 글자(bodyLarge ink)보다 눈에 덜 띄어야 한다.
        counterStyle: text.labelMedium!.copyWith(color: AppPalette.inkMuted, fontWeight: FontWeight.w400),
        border: const OutlineInputBorder(borderRadius: _controlRadius, borderSide: _controlSide),
        enabledBorder:
            const OutlineInputBorder(borderRadius: _controlRadius, borderSide: _controlSide),
        disabledBorder: const OutlineInputBorder(
          borderRadius: _controlRadius,
          borderSide: _disabledControlSide,
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: _controlRadius,
          borderSide: BorderSide(color: AppPalette.primary, width: 2),
        ),
        errorBorder: const OutlineInputBorder(
          borderRadius: _controlRadius,
          borderSide: BorderSide(color: AppPalette.danger, width: 2),
        ),
        focusedErrorBorder: const OutlineInputBorder(
          borderRadius: _controlRadius,
          borderSide: BorderSide(color: AppPalette.danger, width: 2),
        ),
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: AppPalette.ink,
        selectionColor: AppPalette.primaryPale,
        selectionHandleColor: AppPalette.primary,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        selectedIcon: const Icon(AppIcons.check),
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) return AppPalette.sunken;
            return states.contains(WidgetState.selected)
                ? AppPalette.primary
                : AppPalette.surface;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) return AppPalette.inkDisabled;
            return states.contains(WidgetState.selected)
                ? AppPalette.surface
                : AppPalette.ink;
          }),
          iconColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) return AppPalette.inkDisabled;
            return states.contains(WidgetState.selected)
                ? AppPalette.surface
                : AppPalette.ink;
          }),
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          side: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? _disabledControlSide
                : _controlSide,
          ),
          shape: const WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: _controlRadius),
          ),
          textStyle: WidgetStatePropertyAll(text.labelLarge),
          minimumSize: const WidgetStatePropertyAll(Size(48, 52)),
          splashFactory: NoSplash.splashFactory,
          enableFeedback: false,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(6))),
        side: WidgetStateBorderSide.resolveWith(
          (states) => BorderSide(
            color: states.contains(WidgetState.disabled)
                ? AppPalette.line
                : AppPalette.outline,
            width: 2,
          ),
        ),
        fillColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? AppPalette.primary : Colors.transparent,
        ),
        checkColor: const WidgetStatePropertyAll(AppPalette.surface),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        splashRadius: 0,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: AppPalette.ink,
        textColor: AppPalette.ink,
        titleTextStyle: text.bodyLarge,
        subtitleTextStyle: text.bodyMedium!.copyWith(color: AppPalette.inkMuted),
        enableFeedback: false,
      ),
      dividerTheme: const DividerThemeData(color: AppPalette.line, thickness: 1, space: 1),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppPalette.primary,
        linearTrackColor: AppPalette.primaryPale,
        circularTrackColor: AppPalette.primaryPale,
        refreshBackgroundColor: AppPalette.surface,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: const BoxDecoration(
          color: AppPalette.ink,
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
        textStyle: text.bodySmall!.copyWith(color: AppPalette.surface),
      ),
      expansionTileTheme: const ExpansionTileThemeData(
        shape: Border(),
        collapsedShape: Border(),
      ),
    );
  }

  /// 주·보조·위험 버튼 공통 모양(design 4.2). 둥근 사각 12 + 아래 3dp ink 두께, 높이 52(면 49).
  /// 눌림 = 면이 두께만큼 내려와 두께를 덮는다(라벨도 함께 내려간다). 비활성 = sunken 면 + inkDisabled, 납작.
  static ButtonStyle _depthButton(
    TextTheme text, {
    required Color background,
    required Color foreground,
    required Color focusRing,
    required Duration animationDuration,
    BorderSide side = BorderSide.none,
  }) {
    return ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled) ? AppPalette.sunken : background,
      ),
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled) ? AppPalette.inkDisabled : foreground,
      ),
      iconColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled) ? AppPalette.inkDisabled : foreground,
      ),
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      side: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return BorderSide.none;
        if (states.contains(WidgetState.focused)) return BorderSide(color: focusRing, width: 2);
        return side;
      }),
      shape: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return _flatButton;
        if (states.contains(WidgetState.pressed)) return _pressedButton;
        return _raisedButton;
      }),
      padding: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return _flatPadding;
        if (states.contains(WidgetState.pressed)) return _pressedPadding;
        return _restPadding;
      }),
      elevation: const WidgetStatePropertyAll(0),
      shadowColor: const WidgetStatePropertyAll(Colors.transparent),
      minimumSize: const WidgetStatePropertyAll(Size(64, 52)),
      textStyle: WidgetStatePropertyAll(text.labelLarge),
      iconSize: const WidgetStatePropertyAll(24),
      animationDuration: animationDuration,
      splashFactory: NoSplash.splashFactory,
      enableFeedback: false,
    );
  }
}
