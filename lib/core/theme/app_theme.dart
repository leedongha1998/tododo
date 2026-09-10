import 'package:flutter/material.dart';

/// 앱 전체의 시각 규칙.
///
/// 색은 런처 아이콘의 주황 그라디언트와 같은 계열을 시드로 쓴다
/// (`tool/generate_launcher_icons.dart`의 `_gradientEnd`). 아이콘과 앱 화면이
/// 다른 색을 쓰면 설치 직후부터 남의 앱처럼 보인다.
class AppTheme {
  AppTheme._();

  static const seed = Color(0xFFE04A16);

  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(seedColor: seed);
    final base = ThemeData(useMaterial3: true, colorScheme: scheme);

    return base.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 2,
        titleTextStyle: base.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.bold,
          color: scheme.onSurface,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        // 아이콘만으로는 탭 이름을 짐작해야 한다. 라벨은 항상 보인다.
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primaryContainer,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? scheme.onPrimaryContainer
                : scheme.onSurfaceVariant,
          ),
        ),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLow,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      snackBarTheme: base.snackBarTheme.copyWith(behavior: SnackBarBehavior.floating),
    );
  }
}
