import 'package:flutter/material.dart';

import 'retro_palette.dart';

/// 글꼴 규칙(design.md 1.2 + readability.md 방안 1·2, 2026-10-29 개정).
///
/// 픽셀 글꼴(갈무리11)은 **24dp 이상**(제목·VS 인트로·이니셜)과 독립된 숫자 칸에만 쓴다.
/// 버튼·탭·칩·배지처럼 12dp이던 짧은 라벨과 모든 문장은 기기 기본 글꼴이다 —
/// 갈무리11은 12px 격자라 한 음절이 11x11 dot이고, Flutter는 텍스트 안티에일리어싱을 끌 수 없어
/// 받침이 있는 글자가 작은 크기에서 번진다. 도트 인상은 테두리·모서리·아이콘·팔레트·VS 연출이 낸다.
///
/// 픽셀 크기는 갈무리11 설계 격자 12px(공식 README)의 정수배만 쓴다 — 1.5배 같은 크기는
/// 획 굵기가 글자마다 들쭉날쭉해진다.
class RetroText {
  RetroText._();

  static const pixelFamily = 'Galmuri11';

  /// 갈무리11 설계 격자.
  static const double grid = 12;

  /// 12dp 글자에 16dp 줄.
  static const double pixelHeight = 1.34;

  /// 한글 본문 행간. WCAG SC 1.4.12는 1.5em 이상을 요구하고, 한글 권장은 1.6~1.75다.
  static const double bodyHeight = 1.6;

  /// 짧은 라벨(버튼·탭·칩·배지·창 제목 띠)의 본문 글꼴 기하. 한 줄짜리라 본문보다 행간이 좁다.
  static const double labelHeight = 1.4;

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

  /// 짧은 라벨 슬롯(버튼·탭·칩·배지·작은 소제목). 본문 글꼴 14dp 굵게 — 12dp 픽셀이던 자리다.
  static TextStyle label() {
    return const TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w700,
      height: labelHeight,
      letterSpacing: 0.2,
      color: RetroPalette.ink,
    );
  }

  /// ThemeData에 넣는 역할 분담. Material 위젯의 기본 슬롯이 이 표를 따르므로
  /// 앱바·대화상자 제목은 자동으로 픽셀(24dp 이상), 버튼·탭·칩과 목록 본문·토스트·대화상자 본문은
  /// 자동으로 기기 글꼴이 된다.
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
      // 여기부터는 본문 글꼴이다(fontFamily 미지정 → 기기 기본 한글 글꼴).
      // 12dp 픽셀로 쓰던 네 슬롯 = 버튼·탭·세그먼트·칩·배지·카운터·작은 소제목.
      titleSmall: label(),
      labelLarge: label(),
      labelMedium: label(),
      labelSmall: label(),
      // 문장. 행간을 비워 두면 ThemeData.localize가 englishLike 기하(1.33~1.50)를 머지해
      // WCAG SC 1.4.12(1.5em)에 미달한다. 한글 기준으로 직접 적는다.
      bodyLarge: const TextStyle(
        fontSize: 16,
        height: bodyHeight,
        letterSpacing: 0,
        color: RetroPalette.ink,
      ),
      bodyMedium: const TextStyle(
        fontSize: 14,
        height: bodyHeight,
        letterSpacing: 0,
        color: RetroPalette.ink,
      ),
      // 12dp는 "놓치면 손해 보는 문장"을 담기에 작아 13dp로 올린다.
      bodySmall: const TextStyle(
        fontSize: 13,
        height: 1.55,
        letterSpacing: 0,
        color: RetroPalette.ink,
      ),
    );
  }
}
