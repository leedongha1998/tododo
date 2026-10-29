import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todododo/core/theme/app_theme.dart';
import 'package:todododo/core/theme/retro_text.dart';

/// 글꼴 역할 분담(readability.md 방안 1·2).
/// 픽셀 글꼴은 24dp 이상과 숫자 칸에만 남고, 12dp이던 짧은 라벨과 모든 문장은 본문 글꼴이다.
void main() {
  final text = RetroText.textTheme();

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

  const allSlots = [
    'displayLarge',
    'displayMedium',
    'displaySmall',
    'headlineLarge',
    'headlineMedium',
    'headlineSmall',
    'titleLarge',
    'titleMedium',
    'titleSmall',
    'labelLarge',
    'labelMedium',
    'labelSmall',
    'bodyLarge',
    'bodyMedium',
    'bodySmall',
  ];

  group('본문 슬롯', () {
    // WCAG SC 1.4.12는 본문 행간 1.5em 이상을 요구한다. 행간을 비워 두면
    // ThemeData.localize가 englishLike 기하(1.33~1.50)를 머지해 미달한다.
    test('세 슬롯 모두 행간이 1.5em 이상이다', () {
      for (final name in ['bodyLarge', 'bodyMedium', 'bodySmall']) {
        expect(slot(name).height, isNotNull, reason: name);
        expect(slot(name).height, greaterThanOrEqualTo(1.5), reason: name);
      }
    });

    test('크기는 16 / 14 / 13이고 자간을 비워 두지 않는다', () {
      expect(slot('bodyLarge').fontSize, 16);
      expect(slot('bodyMedium').fontSize, 14);
      // "놓치면 손해 보는 문장"이 들어가는 자리라 12에서 13으로 올렸다.
      expect(slot('bodySmall').fontSize, 13);
      for (final name in ['bodyLarge', 'bodyMedium', 'bodySmall']) {
        expect(slot(name).letterSpacing, 0, reason: name);
      }
    });

    test('기기 기본 글꼴이다(픽셀 글꼴을 지정하지 않는다)', () {
      for (final name in ['bodyLarge', 'bodyMedium', 'bodySmall']) {
        expect(slot(name).fontFamily, isNull, reason: name);
      }
    });
  });

  group('짧은 라벨 슬롯', () {
    // 버튼·탭·세그먼트·칩·배지·카운터·작은 소제목이 이 네 슬롯을 타고 온다.
    const labelSlots = ['titleSmall', 'labelLarge', 'labelMedium', 'labelSmall'];

    test('네 슬롯이 본문 글꼴 14dp 굵게로 통일돼 있다', () {
      for (final name in labelSlots) {
        expect(slot(name).fontFamily, isNull, reason: name);
        expect(slot(name).fontSize, 14, reason: name);
        expect(slot(name).fontWeight, FontWeight.w700, reason: name);
        expect(slot(name).height, RetroText.labelHeight, reason: name);
      }
    });
  });

  group('픽셀로 남는 것', () {
    test('픽셀 글꼴 슬롯은 모두 24dp 이상이다', () {
      final pixelSlots = allSlots
          .where((name) => slot(name).fontFamily == RetroText.pixelFamily)
          .toList();
      expect(pixelSlots, isNotEmpty);
      for (final name in pixelSlots) {
        expect(slot(name).fontSize, greaterThanOrEqualTo(RetroText.grid * 2), reason: name);
      }
    });

    test('제목 8슬롯이 픽셀 글꼴이다(도트 인상은 여기서 나온다)', () {
      for (final name in [
        'displayLarge',
        'displayMedium',
        'displaySmall',
        'headlineLarge',
        'headlineMedium',
        'headlineSmall',
        'titleLarge',
        'titleMedium',
      ]) {
        expect(slot(name).fontFamily, RetroText.pixelFamily, reason: name);
      }
    });

    test('픽셀 크기는 격자 12의 정수배만 쓴다', () {
      for (final name in allSlots) {
        if (slot(name).fontFamily != RetroText.pixelFamily) continue;
        expect(slot(name).fontSize! % RetroText.grid, 0, reason: name);
      }
    });

    test('숫자 칸(numeric)과 pixel()은 그대로 픽셀 글꼴이다', () {
      expect(RetroText.numeric.fontFamily, RetroText.pixelFamily);
      expect(RetroText.numeric.height, RetroText.pixelHeight);
      expect(RetroText.pixel(RetroText.grid).fontFamily, RetroText.pixelFamily);
    });
  });

  testWidgets('MaterialApp이 기하를 머지해도 본문 행간 1.5em이 유지된다', (tester) async {
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
    expect(runtime.bodySmall!.fontSize, 13);
    // 라벨도 테마를 타고 온 뒤 픽셀 글꼴로 되돌아가지 않는다.
    // (Material Typography가 머지되며 기본 글꼴 이름 'Roboto'가 붙는다 — 기기에서는 시스템 글꼴이다.)
    expect(runtime.labelLarge!.fontFamily, isNot(RetroText.pixelFamily));
    expect(runtime.bodyMedium!.fontFamily, isNot(RetroText.pixelFamily));
    expect(runtime.titleLarge!.fontFamily, RetroText.pixelFamily);
  });
}
