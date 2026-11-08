import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:todododo/core/theme/app_text.dart';
import 'package:todododo/core/widgets/keep_words_text.dart';

import '../../helpers/line_breaks.dart';
import '../../helpers/text_finders.dart';

void main() {
  group('keepWords', () {
    test('어절 안 글자 사이에만 WORD JOINER를 끼운다', () {
      expect(keepWords('상대가 더 잘했어요'), '상\u2060대\u2060가 더 잘\u2060했\u2060어\u2060요');
      expect(keepWords('통과했어요'), '통\u2060과\u2060했\u2060어\u2060요');
    });

    test('공백은 그대로 두고, 한 글자 어절·빈 문자열도 다룬다', () {
      expect(keepWords('a  b'), 'a  b');
      expect(keepWords(''), '');
      expect(keepWords('더'), '더');
    });

    test('WORD JOINER를 지우면 원문으로 돌아온다', () {
      const original = '통과하지 못했어요';
      expect(keepWords(original).replaceAll(wordJoiner, ''), original);
    });

    test('서로게이트 쌍(이모지)을 가르지 않는다', () {
      final joined = keepWords('a😀b');
      expect(joined.replaceAll(wordJoiner, ''), 'a😀b');
      expect(joined.runes.where((r) => r == 0x1F600), hasLength(1));
    });
  });

  test('양쪽이 모두 ASCII인 글자 사이에는 끼우지 않는다(영문·숫자 커닝, URL 줄바꿈 보존)', () {
    expect(keepWords('Google LLC'), 'Google LLC');
    expect(keepWords('https://example.com/a'), 'https://example.com/a');
    expect(keepWords('AI가 3km'), 'AI\u2060가 3km');
    expect(keepWords('10분'), '10\u2060분');
  });

  testWidgets('KeepWordsText는 Text가 아니다 — 원문은 text에, 그리는 글자에만 WORD JOINER가 들어간다', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      const Directionality(textDirection: TextDirection.ltr, child: KeepWordsText('상대가 더 잘했어요')),
    );
    // Text를 상속하지 않고(redesign 후속 2 W1) 안에 Text도 만들지 않는다 — 원문은 공용 finder로 찾는다.
    expect(find.byType(Text), findsNothing);
    expect(findText('상대가 더 잘했어요'), findsOneWidget);
    expect(findText(keepWords('상대가 더 잘했어요')), findsNothing);
    expect(tester.widget<KeepWordsText>(findText('상대가 더 잘했어요')).text, '상대가 더 잘했어요');
    final rich = tester.widget<RichText>(find.byType(RichText));
    expect(rich.text.toPlainText(), keepWords('상대가 더 잘했어요'));
    // 화면 낭독기에는 원문.
    expect(find.bySemanticsLabel('상대가 더 잘했어요'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('Text.build처럼 DefaultTextStyle을 합성하고 글자 배율·굵은 글씨 설정을 따른다', (tester) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(1.5), boldText: true),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: DefaultTextStyle(
            style: TextStyle(fontSize: 10, color: Color(0xFF112233)),
            textAlign: TextAlign.center,
            maxLines: 2,
            child: KeepWordsText('가나', style: TextStyle(height: 1.5)),
          ),
        ),
      ),
    );
    final rich = tester.widget<RichText>(find.byType(RichText));
    expect(rich.text.style!.fontSize, 10);
    expect(rich.text.style!.color, const Color(0xFF112233));
    expect(rich.text.style!.height, 1.5);
    expect(rich.text.style!.fontWeight, FontWeight.bold);
    expect(rich.textScaler, const TextScaler.linear(1.5));
    expect(rich.textAlign, TextAlign.center);
    expect(rich.maxLines, 2);
  });

  testWidgets('글자가 바뀌지 않으면(ASCII뿐) semanticsLabel을 덧씌우지 않고, 호출부가 준 값은 그대로 쓴다', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Column(
          children: [
            KeepWordsText('13/60'),
            KeepWordsText('러닝 3km', semanticsLabel: '달리기'),
          ],
        ),
      ),
    );
    expect(find.byWidgetPredicate((w) => w is Semantics && w.properties.label == '13/60'), findsNothing);
    expect(
      find.byWidgetPredicate((w) => w is Semantics && w.properties.label == '달리기'),
      findsOneWidget,
    );
  });

  testWidgets('한 어절이 칸보다 길면 그 어절 안에서 끊긴다 — 넘쳐서 잘리지 않는다', (tester) async {
    // 테스트 글꼴은 글자마다 10 × 10. 폭 40에 열 글자짜리 한 어절.
    const word = '가나다라마바사아자차';
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(width: 40, child: KeepWordsText(word, style: TextStyle(fontSize: 10))),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    final paragraph = tester.renderObject<RenderParagraph>(find.byType(RichText));
    expect(lineStarts(paragraph), isNotEmpty);
    expect(paragraph.size.width, lessThanOrEqualTo(40));
    expect(paragraph.didExceedMaxLines, isFalse);
    // 글자는 하나도 빠지지 않고 세로로 이어진다.
    expect(paragraph.size.height, greaterThanOrEqualTo(30));
  });

  test('widestWordWidth는 가장 넓은 어절의 폭을 글자 배율까지 반영해 잰다', () {
    // 테스트 글꼴은 글자마다 정사각형이다(크기 10 → 10 × 10).
    const style = TextStyle(fontSize: 10);
    expect(widestWordWidth('상대가 더 잘했어요', style: style), 40);
    expect(widestWordWidth('상대가 더 잘했어요', style: style, textScaler: const TextScaler.linear(1.5)), 60);
    expect(widestWordWidth('', style: style), 0);
  });

  testWidgets('좁은 칸에서 어절 경계에서만 줄을 바꾼다(그냥 Text는 단어 중간에서 끊는다)', (tester) async {
    const label = '상대가 더 잘했어요';
    // 테스트 글꼴은 글자마다 정사각형(10 × 10)이다. 폭 80이면 한 줄에 여덟 칸 — "상대가 더 잘했"까지 들어가
    // 그냥 Text는 "잘했 / 어요"로 끊고, 어절을 묶으면 "상대가 더 / 잘했어요"가 된다.
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 80,
            child: Column(
              children: [
                Text(label, key: Key('plain'), style: TextStyle(fontSize: 10)),
                // 줄 모양 옵션은 끄고 어절 경계만 본다(pretty면 "상대가 / 더 잘했어요"가 된다 — 아래 고아 방지 테스트).
                KeepWordsText(label, key: Key('kept'), style: TextStyle(fontSize: 10), wrap: KeepWordsWrap.none),
              ],
            ),
          ),
        ),
      ),
    );
    RenderParagraph paragraphOf(String key) => tester.renderObject<RenderParagraph>(
          find.descendant(of: find.byKey(Key(key)), matching: find.byType(RichText)),
        );

    final plain = paragraphOf('plain');
    final kept = paragraphOf('kept');
    // 비교 기준: 그냥 Text는 어절 중간에서 끊긴다(이 테스트가 실제로 줄바꿈을 보고 있다는 증거).
    expect(lineStarts(plain), [8]);
    expect(breaksOnlyAtSpaces(plain), isFalse);
    expect(lineStarts(kept), isNotEmpty);
    expect(lineStarts(kept), [keepWords('상대가 더 ').length]);
    expect(breaksOnlyAtSpaces(kept), isTrue);
  });

  group('줄 모양(redesign 후속 2 W2)', () {
    setUp(debugClearKeepWordsPlanCache);

    // 테스트 글꼴은 글자마다 10 × 10이다(공백 포함). 행간을 1.4로 주면 기본값이 balanced, 1.6이면 pretty.
    const title = TextStyle(fontSize: 10, height: 1.4);
    const body = TextStyle(fontSize: 10, height: 1.6);

    Future<void> pumpAt(WidgetTester tester, double width, Widget child, {TextScaler? scaler}) => tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(textScaler: scaler ?? TextScaler.noScaling),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Align(alignment: Alignment.topLeft, child: SizedBox(width: width, child: child)),
            ),
          ),
        );

    RenderParagraph paragraphOf(WidgetTester tester, Finder of) =>
        tester.renderObject<RenderParagraph>(find.descendant(of: of, matching: find.byType(RichText)));

    test('기본값은 design 3.2 역할표의 행간으로 정한다 — 본문 슬롯은 pretty, 제목·라벨·숫자 슬롯은 balanced', () {
      final theme = AppText.textTheme();
      for (final style in [theme.bodyLarge, theme.bodyMedium, theme.bodySmall]) {
        expect(wrapForStyle(style), KeepWordsWrap.pretty);
      }
      for (final style in [
        theme.displayLarge, theme.displayMedium, theme.displaySmall, //
        theme.headlineLarge, theme.headlineMedium, theme.headlineSmall,
        theme.titleLarge, theme.titleMedium, theme.titleSmall,
        theme.labelLarge, theme.labelMedium, theme.labelSmall,
        AppText.numberLarge, AppText.numberMedium, AppText.numberSmall,
      ]) {
        expect(wrapForStyle(style), KeepWordsWrap.balanced, reason: '$style');
      }
      expect(wrapForStyle(null), KeepWordsWrap.pretty);
      expect(wrapForStyle(const TextStyle(fontSize: 10)), KeepWordsWrap.pretty);
    });

    testWidgets('balanced: 줄 수는 그대로, 줄 길이가 고르게 — 위젯 폭과 왼쪽 정렬은 그대로', (tester) async {
      const label = '냉장고 안 유통기한 지난 음식 전부 버리기';
      await pumpAt(
        tester,
        200,
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            KeepWordsText(label, key: Key('none'), style: title, wrap: KeepWordsWrap.none),
            KeepWordsText(label, key: Key('balanced'), style: title),
          ],
        ),
      );
      final none = paragraphOf(tester, find.byKey(const Key('none')));
      final balanced = paragraphOf(tester, find.byKey(const Key('balanced')));
      // 비교 기준: 엔진 기본은 "냉장고 안 유통기한 지난 음식 전부 / 버리기"(한 어절만 넘어간다).
      expect(lineWidths(none), [190, 30]);
      expect(lineWidths(balanced), hasLength(2));
      expect(spread(lineWidths(balanced)), lessThan(spread(lineWidths(none))));
      expect(spread(lineWidths(balanced)), lessThanOrEqualTo(30));
      expect(breaksOnlyAtSpaces(balanced), isTrue);
      // 글자는 좁게 그려도 위젯은 칸 폭 전체를 차지하고, 왼쪽 정렬이라 글자는 왼쪽 끝에 붙는다.
      expect(tester.getSize(find.byKey(const Key('balanced'))).width, 200);
      expect(balanced.size.width, lessThan(200));
      expect(tester.getTopLeft(find.byType(RichText).last).dx, 0);
    });

    testWidgets('balanced: 가운데 정렬은 칸 가운데를 지킨다', (tester) async {
      const label = '냉장고 안 유통기한 지난 음식 전부 버리기';
      await pumpAt(tester, 200, const KeepWordsText(label, style: title, textAlign: TextAlign.center));
      final paragraph = tester.renderObject<RenderParagraph>(find.byType(RichText));
      expect(paragraph.size.width, lessThan(200));
      expect(tester.getSize(find.byType(KeepWordsText)).width, 200);
      expect(tester.getCenter(find.byType(RichText)).dx, closeTo(100, 0.01));
    });

    testWidgets('balanced: 한 줄이거나 다섯 줄 이상이면 손대지 않는다', (tester) async {
      await pumpAt(
        tester,
        200,
        const Column(
          children: [
            KeepWordsText('짧은 제목', key: Key('one'), style: title),
            KeepWordsText('가나 다라 마바 사아 자차 카타 파하 가나 다라 마바', key: Key('five'), style: title),
          ],
        ),
      );
      await pumpAt(
        tester,
        40,
        const Column(
          children: [
            KeepWordsText('짧은 제목', key: Key('one'), style: title),
            KeepWordsText('가나 다라 마바 사아 자차 카타 파하 가나 다라 마바', key: Key('five'), style: title),
          ],
        ),
      );
      final five = paragraphOf(tester, find.byKey(const Key('five')));
      expect(lineStarts(five).length + 1, greaterThan(balancedMaxLines));
      expect(five.size.width, 40);
    });

    testWidgets('pretty: 마지막 줄에 한 어절만 남지 않는다(끄면 남는다)', (tester) async {
      const todo = '냉장고 정리할 때 유통기한 잊지 말기';
      await pumpAt(
        tester,
        90,
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            KeepWordsText(todo, key: Key('none'), style: body, wrap: KeepWordsWrap.none),
            KeepWordsText(todo, key: Key('pretty'), style: body),
          ],
        ),
      );
      final none = paragraphOf(tester, find.byKey(const Key('none')));
      final pretty = paragraphOf(tester, find.byKey(const Key('pretty')));
      // 비교 기준: 엔진 기본은 "냉장고 정리할 때 / 유통기한 잊지 / 말기".
      expect(lastLineWords(none), ['말기']);
      expect(lastLineWords(pretty), ['잊지', '말기']);
      expect(lineStarts(pretty).length, lineStarts(none).length);
      expect(breaksOnlyAtSpaces(pretty), isTrue);
      // 낭독·찾기는 원문 그대로.
      expect(findText(todo), findsNWidgets(2));
    });

    testWidgets('pretty: 문단마다 따로, 1.5배에서도', (tester) async {
      const text = '가나다 라마 바사\n아자차 카타 파하';
      // 1.5배면 글자가 15 × 15. 폭 120이면 한 줄에 8칸 — "가나다 라마"(6) + " 바사"(9) 넘침 → 문단마다 "바사"·"파하"가 혼자 남는다.
      await pumpAt(tester, 120, const KeepWordsText(text, style: body), scaler: const TextScaler.linear(1.5));
      final paragraph = tester.renderObject<RenderParagraph>(find.byType(RichText));
      final shown = paragraph.text.toPlainText().replaceAll(wordJoiner, '');
      final starts = lineStarts(paragraph);
      final plain = paragraph.text.toPlainText();
      final lines = [
        for (var i = 0; i <= starts.length; i++)
          plain.substring(i == 0 ? 0 : starts[i - 1], i == starts.length ? plain.length : starts[i]),
      ].map((line) => line.replaceAll(wordJoiner, '').trim()).toList();
      expect(shown, text);
      expect(lines, ['가나다', '라마 바사', '아자차', '카타 파하']);
    });

    testWidgets('pretty: 붙인 두 어절이 칸보다 넓으면 붙이지 않는다', (tester) async {
      // 폭 50(다섯 칸). "가나 다라마바"는 일곱 칸이라 붙이면 그 덩어리가 칸을 넘는다 → 그대로 "가나 / 다라마바".
      await pumpAt(tester, 50, const KeepWordsText('가나 다라마바', style: body));
      final paragraph = tester.renderObject<RenderParagraph>(find.byType(RichText));
      expect(paragraph.text.toPlainText(), keepWords('가나 다라마바'));
      expect(lastLineWords(paragraph), ['다라마바']);
      expect(breaksOnlyAtSpaces(paragraph), isTrue);
    });

    test('joinLastWords는 마지막 공백 뒤에만 WORD JOINER를 넣고, fits가 거짓이면 그대로 둔다', () {
      expect(joinLastWords('가 나 다', (_) => true), '가 나 ⁠다');
      expect(joinLastWords('가 나 다', (pair) => pair == '나 다'), '가 나 ⁠다');
      expect(joinLastWords('가 나 다', (_) => false), '가 나 다');
      expect(joinLastWords('하나', (_) => true), '하나');
      expect(joinLastWords('', (_) => true), '');
      expect(joinLastWords('가  나 ', (_) => true), '가  ⁠나 ');
      expect(joinLastWords('가 나\n다 라', (_) => true), '가 ⁠나\n다 ⁠라');
    });

    for (final wrap in KeepWordsWrap.values) {
      testWidgets('한 어절이 칸보다 길어도 넘치지 않는다 — $wrap', (tester) async {
        const word = '가나다라마바사아자차';
        await pumpAt(tester, 40, const KeepWordsText('$word 끝', style: title).copyWithWrap(wrap));
        expect(tester.takeException(), isNull);
        final paragraph = tester.renderObject<RenderParagraph>(find.byType(RichText));
        expect(paragraph.size.width, lessThanOrEqualTo(40));
        expect(tester.getSize(find.byType(KeepWordsText)).width, lessThanOrEqualTo(40));
        expect(paragraph.didExceedMaxLines, isFalse);
      });
    }

    testWidgets('IntrinsicWidth·대화상자 안에서도 고유 크기를 답한다', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: IntrinsicWidth(
              child: Column(
                children: [
                  KeepWordsText('가나다 라마', style: title),
                  KeepWordsText('가나 다라마바사', style: body),
                ],
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      // 가장 긴 글자("가나 다라마바사", 여덟 칸)의 폭이 고유 폭이 된다.
      expect(tester.getSize(find.byType(IntrinsicWidth)).width, 80);
      expect(tester.getSize(find.byType(KeepWordsText).first).height, 14);
    });

    testWidgets('기준선 정렬(Row baseline)에서도 글자 기준선을 낸다', (tester) async {
      await pumpAt(
        tester,
        200,
        const Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            KeepWordsText('1', style: TextStyle(fontSize: 20, height: 1.4)),
            Expanded(child: KeepWordsText('가나 다라마 바사아 자차카타파하 가나다', style: title)),
          ],
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });
}

extension on KeepWordsText {
  KeepWordsText copyWithWrap(KeepWordsWrap wrap) => KeepWordsText(text, style: style, wrap: wrap);
}
