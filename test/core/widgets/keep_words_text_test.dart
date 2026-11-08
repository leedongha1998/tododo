import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:todododo/core/widgets/keep_words_text.dart';

import '../../helpers/line_breaks.dart';

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

  testWidgets('KeepWordsText는 Text이고 data는 원문 — 그리는 글자에만 WORD JOINER가 들어간다', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      const Directionality(textDirection: TextDirection.ltr, child: KeepWordsText('상대가 더 잘했어요')),
    );
    // 원문으로 찾는다(기존 find.text 검사가 그대로 맞는다). 같은 글자의 Text가 둘 생기지 않는다.
    expect(find.text('상대가 더 잘했어요'), findsOneWidget);
    expect(find.text(keepWords('상대가 더 잘했어요')), findsNothing);
    expect(tester.widget<Text>(find.text('상대가 더 잘했어요')).data, '상대가 더 잘했어요');
    final rich = tester.widget<RichText>(find.byType(RichText));
    expect(rich.text.toPlainText(), keepWords('상대가 더 잘했어요'));
    // 화면 낭독기에는 원문.
    expect(find.bySemanticsLabel('상대가 더 잘했어요'), findsOneWidget);
    semantics.dispose();
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
                KeepWordsText(label, key: Key('kept'), style: TextStyle(fontSize: 10)),
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
}
