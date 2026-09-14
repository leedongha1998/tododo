import 'package:flutter/material.dart';

import 'retro_palette.dart';

/// 글꼴 규칙(design.md 1.2).
///
/// 픽셀 글꼴(갈무리11)은 제목·버튼·탭·배지·칩·숫자에만 쓰고, 긴 문장은 기기 기본 글꼴로 둔다.
/// 픽셀 크기는 갈무리11 설계 격자 12px(공식 README)의 정수배만 쓴다 — 1.5배 같은 크기는
/// 획 굵기가 글자마다 들쭉날쭉해진다.
class RetroText {
  RetroText._();

  static const pixelFamily = 'Galmuri11';

  /// 갈무리11 설계 격자.
  static const double grid = 12;

  /// 12dp 글자에 16dp 줄.
  static const double pixelHeight = 1.34;

  /// 숫자가 독립된 칸(점수, 남은 시간, n/5 카운터, 전적 수)에 놓일 때. 크기는 24/36으로 copyWith.
  static const numeric = TextStyle(
    fontFamily: pixelFamily,
    fontSize: grid,
    fontWeight: FontWeight.w400,
    height: pixelHeight,
    letterSpacing: 0,
    color: RetroPalette.ink,
  );

  static TextStyle pixel(double size, {bool bold = false, Color color = RetroPalette.ink}) {
    return TextStyle(
      fontFamily: pixelFamily,
      fontSize: size,
      fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
      height: pixelHeight,
      letterSpacing: 0,
      color: color,
    );
  }

  /// ThemeData에 넣는 역할 분담. Material 위젯의 기본 슬롯이 이 표를 따르므로
  /// 앱바·버튼·탭은 자동으로 픽셀, 목록 본문·토스트·대화상자 본문은 자동으로 기기 글꼴이 된다.
  static TextTheme textTheme() {
    return TextTheme(
      displayLarge: pixel(grid * 6, bold: true),
      displayMedium: pixel(grid * 4, bold: true),
      displaySmall: pixel(grid * 3, bold: true),
      headlineLarge: pixel(grid * 2, bold: true),
      headlineMedium: pixel(grid * 2, bold: true),
      headlineSmall: pixel(grid * 2, bold: true),
      titleLarge: pixel(grid * 2, bold: true),
      titleMedium: pixel(grid * 2, bold: true),
      titleSmall: pixel(grid, bold: true),
      labelLarge: pixel(grid, bold: true),
      labelMedium: pixel(grid),
      labelSmall: pixel(grid),
      // 본문은 fontFamily를 지정하지 않는다 → 기기 기본 한글 글꼴.
      bodyLarge: const TextStyle(fontSize: 16, color: RetroPalette.ink),
      bodyMedium: const TextStyle(fontSize: 14, color: RetroPalette.ink),
      bodySmall: const TextStyle(fontSize: 12, color: RetroPalette.ink),
    );
  }
}
