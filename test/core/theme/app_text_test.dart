import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todododo/core/theme/app_text.dart';
import 'package:todododo/core/theme/app_theme.dart';

/// 글자 역할표(redesign design 3.2). 모든 글자는 Pretendard 한 벌이고, 크기·굵기·행간은 표 그대로다.
void main() {
  final text = AppText.textTheme();

  TextStyle slot(String name) => switch (name) {
    'displayLarge' => text.displayLarge!,
    'displayMedium' => text.displayMedium!,
    'displaySmall' => text.displaySmall!,
    'headlineLarge' => text.headlineLarge!,
    'headlineMedium' => text.headlineMedium!,
    'headlineSmall' => text.headlineSmall!,
    'titleLarge' => text.titleLarge!,
    'titleMedium' => text.titleMedium!,
    'titleSmall' => text.titleSmall!,
    'labelLarge' => text.labelLarge!,
    'labelMedium' => text.labelMedium!,
    'labelSmall' => text.labelSmall!,
    'bodyLarge' => text.bodyLarge!,
    'bodyMedium' => text.bodyMedium!,
    'bodySmall' => text.bodySmall!,
    _ => throw ArgumentError(name),
  };

  /// design 3.2 표: 슬롯, 크기, 굵기, 행간.
  const table = <(String, double, FontWeight, double)>[
    ('displayLarge', 40.0, FontWeight.w800, 1.25),
    ('displayMedium', 34.0, FontWeight.w800, 1.25),
    ('displaySmall', 28.0, FontWeight.w800, 1.3),
    ('headlineLarge', 26.0, FontWeight.w700, 1.35),
    ('headlineMedium', 24.0, FontWeight.w700, 1.35),
    ('headlineSmall', 22.0, FontWeight.w700, 1.4),
    ('titleLarge', 20.0, FontWeight.w700, 1.4),
    ('titleMedium', 18.0, FontWeight.w700, 1.45),
    ('titleSmall', 16.0, FontWeight.w700, 1.5),
    ('bodyLarge', 16.0, FontWeight.w400, 1.6),
    ('bodyMedium', 15.0, FontWeight.w400, 1.6),
    ('bodySmall', 13.0, FontWeight.w400, 1.55),
    ('labelLarge', 16.0, FontWeight.w700, 1.4),
    ('labelMedium', 14.0, FontWeight.w700, 1.4),
    ('labelSmall', 12.0, FontWeight.w700, 1.35),
  ];

  final numbers = <(String, TextStyle, double, FontWeight, double)>[
    ('numberLarge', AppText.numberLarge, 32.0, FontWeight.w800, 1.2),
    ('numberMedium', AppText.numberMedium, 20.0, FontWeight.w800, 1.3),
    ('numberSmall', AppText.numberSmall, 16.0, FontWeight.w700, 1.4),
  ];

  const tnum = ui.FontFeature.tabularFigures();

  test('15슬롯의 크기·굵기·행간이 design 3.2 표와 같다', () {
    for (final (name, size, weight, height) in table) {
      expect(slot(name).fontSize, size, reason: name);
      expect(slot(name).fontWeight, weight, reason: name);
      expect(slot(name).height, height, reason: name);
    }
  });

  test('모든 슬롯·숫자 슬롯이 Pretendard다', () {
    expect(AppText.family, 'Pretendard');
    for (final (name, _, _, _) in table) {
      expect(slot(name).fontFamily, AppText.family, reason: name);
    }
    for (final (name, style, _, _, _) in numbers) {
      expect(style.fontFamily, AppText.family, reason: name);
    }
  });

  test('최소 12, 문장 슬롯 14 이상, 본문 3슬롯 행간 1.5 이상', () {
    for (final (name, _, _, _) in table) {
      expect(slot(name).fontSize, greaterThanOrEqualTo(12), reason: name);
    }
    expect(slot('bodyMedium').fontSize, greaterThanOrEqualTo(14));
    expect(slot('bodyLarge').fontSize, greaterThanOrEqualTo(14));
    // WCAG SC 1.4.12는 본문 행간 1.5em 이상을 요구한다.
    for (final name in ['bodyLarge', 'bodyMedium', 'bodySmall']) {
      expect(slot(name).height, greaterThanOrEqualTo(1.5), reason: name);
    }
  });

  test('자간 0(음수 없음), 굵기는 번들한 400/700/800만', () {
    for (final (name, _, _, _) in table) {
      expect(slot(name).letterSpacing, 0, reason: name);
      // 번들한 굵기(400/700/800)만 쓴다 — 300 이하·500·600 없음.
      expect(
        const [FontWeight.w400, FontWeight.w700, FontWeight.w800],
        contains(slot(name).fontWeight),
        reason: name,
      );
    }
    for (final (name, style, _, _, _) in numbers) {
      expect(style.letterSpacing, 0, reason: name);
    }
  });

  test('숫자 슬롯 3개는 표 그대로이고 고정폭 숫자를 켠다', () {
    for (final (name, style, size, weight, height) in numbers) {
      expect(style.fontSize, size, reason: name);
      expect(style.fontWeight, weight, reason: name);
      expect(style.height, height, reason: name);
      expect(style.fontFeatures, contains(tnum), reason: name);
    }
    expect(AppText.tabular.fontFeatures, contains(tnum));
    // 문장 슬롯에 붙여도 크기·글꼴은 그대로다.
    final merged = slot('bodyMedium').merge(AppText.tabular);
    expect(merged.fontSize, 15);
    expect(merged.fontFamily, AppText.family);
    expect(merged.fontFeatures, contains(tnum));
  });

  testWidgets('MaterialApp이 기하를 머지해도 Pretendard와 본문 행간이 유지된다', (tester) async {
    late TextTheme runtime;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) {
            runtime = Theme.of(context).textTheme;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(runtime.bodyLarge!.height, 1.6);
    expect(runtime.bodyMedium!.height, 1.6);
    expect(runtime.bodySmall!.height, 1.55);
    expect(runtime.bodyMedium!.fontSize, 15);
    // Material Typography가 머지되며 붙는 'Roboto'가 이기지 않는다.
    for (final style in [
      runtime.titleLarge!,
      runtime.headlineSmall!,
      runtime.labelLarge!,
      runtime.labelSmall!,
      runtime.bodyLarge!,
      runtime.bodyMedium!,
      runtime.bodySmall!,
    ]) {
      expect(style.fontFamily, AppText.family);
    }
  });
}
