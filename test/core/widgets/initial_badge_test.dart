import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todododo/core/theme/app_palette.dart';
import 'package:todododo/core/theme/app_text.dart';
import 'package:todododo/core/theme/depth_border.dart';
import 'package:todododo/core/widgets/initial_badge.dart';

void main() {
  group('displayInitial', () {
    test('한글 이름은 첫 글자', () {
      expect(displayInitial('홍길동'), '홍');
    });

    test('앞 공백을 지우고 라틴 소문자는 대문자로', () {
      expect(displayInitial('  alice'), 'A');
    });

    test('비었거나 공백뿐이면 물음표', () {
      expect(displayInitial(''), '?');
      expect(displayInitial('   '), '?');
    });

    test('탈퇴한 사용자 묘비도 특별 취급 없이 첫 글자', () {
      expect(displayInitial('탈퇴한 사용자'), '탈');
    });

    test('한 글자 이름은 그대로', () {
      expect(displayInitial('가'), '가');
    });

    test('이모지로 시작하면 이모지 한 글자 단위로 자른다', () {
      // 피부색 조합 이모지, 가족(ZWJ) 이모지
      expect(displayInitial('\u{1F44D}\u{1F3FD}최고'), '\u{1F44D}\u{1F3FD}');
      expect(
        displayInitial('\u{1F468}‍\u{1F469}‍\u{1F467} 가족'),
        '\u{1F468}‍\u{1F469}‍\u{1F467}',
      );
    });

    test('결합 문자는 앞 글자와 함께 한 글자로 본다', () {
      // e + U+0301(결합 악센트) → 두 코드 포인트가 한 글자 단위로 남는다.
      expect(displayInitial('éclair'), 'É');
      // 미리 합성된 é
      expect(displayInitial('éclair'), 'É');
    });

    test('대문자로 바꾸면 글자 수가 늘어나는 글자는 그대로 둔다', () {
      expect(displayInitial('ßeta'), 'ß');
    });
  });

  group('InitialBadge', () {
    Future<void> pump(WidgetTester tester, Widget badge) {
      return tester.pumpWidget(
        MaterialApp(home: Scaffold(body: Center(child: badge))),
      );
    }

    Text textOf(WidgetTester tester) => tester.widget<Text>(find.text('홍'));

    DepthBorder shapeOf(WidgetTester tester) {
      final box = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(InitialBadge),
              matching: find.byType(Container),
            )
            .first,
      );
      return (box.decoration! as ShapeDecoration).shape as DepthBorder;
    }

    testWidgets('나(primary) 면이면 흰 글자', (tester) async {
      await pump(
        tester,
        const InitialBadge(name: '홍길동', fill: AppPalette.primary),
      );
      expect(textOf(tester).style!.color, AppPalette.surface);
    });

    testWidgets('상대(secondary) 면이면 ink 글자', (tester) async {
      await pump(
        tester,
        const InitialBadge(name: '홍길동', fill: AppPalette.secondary),
      );
      expect(textOf(tester).style!.color, AppPalette.ink);
    });

    testWidgets('카드는 40, 모서리 12, 두께 없음, Pretendard 800 20', (tester) async {
      await pump(
        tester,
        const InitialBadge(name: '홍길동', fill: AppPalette.secondary),
      );
      expect(tester.getSize(find.byType(InitialBadge)), const Size(40, 40));
      expect(shapeOf(tester).radius, 12);
      expect(shapeOf(tester).depth, 0);
      final style = textOf(tester).style!;
      expect(style.fontFamily, AppText.family);
      expect(style.fontWeight, FontWeight.w800);
      expect(style.fontSize, 20);
    });

    testWidgets('인트로는 72, 모서리 16, 3dp ink 두께, 글자 32', (tester) async {
      await pump(
        tester,
        const InitialBadge(
          name: '홍길동',
          fill: AppPalette.primary,
          size: InitialBadgeSize.intro,
        ),
      );
      expect(tester.getSize(find.byType(InitialBadge)), const Size(72, 72));
      expect(shapeOf(tester).radius, 16);
      expect(shapeOf(tester).depth, 3);
      expect(shapeOf(tester).depthColor, AppPalette.ink);
      expect(textOf(tester).style!.fontSize, 32);
    });
  });
}
