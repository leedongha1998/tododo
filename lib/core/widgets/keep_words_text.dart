import 'package:flutter/material.dart';

/// WORD JOINER(U+2060). 줄바꿈을 막고 폭은 0이다. 번들한 Pretendard 세 굵기 모두 이 글자를 갖고 있어
/// 대체 글꼴로 넘어가지 않는다(줄 높이가 흔들리지 않는다).
const wordJoiner = '⁠';

/// [text]의 어절(공백으로 나뉜 덩어리) 안 글자 사이마다 [wordJoiner]를 끼운다.
///
/// Flutter(ICU)는 한글을 음절마다 끊을 수 있다고 보아 "상대가 더 잘 / 했어요"처럼 단어 중간에서 줄을 바꾼다.
/// 어절 안을 묶어 두면 공백에서만 줄이 바뀐다. 한 어절이 한 줄보다 길면 그때는 엔진이 어절 안에서 자른다
/// (넘쳐 잘리지 않는다 — keep_words_text_test가 고정).
///
/// 양쪽이 모두 ASCII인 글자 사이에는 끼우지 않는다. 영문·숫자는 ICU가 원래 단어 안에서 끊지 않고,
/// 끼우면 커닝이 끊기고 URL·이메일의 `/`·`.` 뒤 줄바꿈 자리가 사라진다.
/// 공백·줄바꿈 문자는 그대로 둔다. 글자는 [String.runes] 단위로 다뤄 서로게이트 쌍을 가르지 않는다.
String keepWords(String text) {
  final buffer = StringBuffer();
  int? previous;
  for (final rune in text.runes) {
    final char = String.fromCharCode(rune);
    final isSpace = char.trim().isEmpty;
    if (!isSpace && previous != null && !(previous < 0x80 && rune < 0x80)) {
      buffer.write(wordJoiner);
    }
    buffer.write(char);
    previous = isSpace ? null : rune;
  }
  return buffer.toString();
}

/// [text]의 어절 중 가장 넓은 것의 폭(논리 픽셀). [KeepWordsText]는 어절 안에서 줄을 바꾸지 않으므로
/// 칸 폭이 이 값보다 좁으면 그 어절이 엔진에 의해 잘린다 — 호출부가 배치를 바꿀지 판단하는 데 쓴다.
double widestWordWidth(String text, {TextStyle? style, TextScaler textScaler = TextScaler.noScaling}) {
  var widest = 0.0;
  for (final word in text.split(RegExp(r'\s+'))) {
    if (word.isEmpty) continue;
    final painter = TextPainter(
      text: TextSpan(text: word, style: style),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
    )..layout();
    if (painter.width > widest) widest = painter.width;
    painter.dispose();
  }
  return widest;
}

/// 어절 단위로만 줄을 바꾸는 [Text]. 앱의 표시용 글자는 전부 이것을 쓴다(redesign 후속 결정 1).
///
/// - [Text]의 하위 클래스이고 [data]는 **원문 그대로**다 — `find.text(원문)`, `tester.widget<Text>`,
///   `widget is Text` 같은 기존 검사가 그대로 맞는다. 문자열 상수(`strings.dart`)도 손대지 않는다.
/// - 그릴 때([build] 동안)만 [data]가 [keepWords]를 거친 글자를 돌려주어, [Text.build]가 만드는 [RichText]에
///   WORD JOINER가 들어간다. 위젯 트리에 [Text]가 하나 더 생기지 않는다(같은 글자를 두 번 찾지 않는다).
/// - 글자가 바뀐 경우에만 화면 낭독기에 원문을 읽히도록 `semanticsLabel`을 원문으로 채운다
///   (호출부가 준 `semanticsLabel`이 있으면 그것을 쓴다).
/// - 편집 가능한 글자(TextField 입력값)·복사 대상(SelectableText)에는 쓰지 않는다 — 끼운 글자가 복사·입력값에 섞인다.
class KeepWordsText extends Text {
  const KeepWordsText(
    super.data, {
    super.key,
    super.style,
    super.strutStyle,
    super.textAlign,
    super.textDirection,
    super.locale,
    super.softWrap,
    super.overflow,
    super.textScaler,
    super.maxLines,
    super.semanticsLabel,
    super.semanticsIdentifier,
    super.textWidthBasis,
    super.textHeightBehavior,
    super.selectionColor,
  });

  /// 지금 [build] 중인 위젯과 그 위젯이 그릴 글자. build는 동기라 중첩되지 않지만, 혹시 몰라 이전 값을 되돌린다.
  static KeepWordsText? _building;
  static String _rendered = '';

  /// 원문(낭독·테스트 기준). [data]와 같다(build 밖에서).
  String get text => super.data!;

  @override
  String? get data => identical(_building, this) ? _rendered : super.data;

  @override
  String? get semanticsLabel {
    final given = super.semanticsLabel;
    if (given != null || !identical(_building, this)) return given;
    final original = super.data!;
    return _rendered == original ? null : original;
  }

  @override
  Widget build(BuildContext context) {
    final previous = _building;
    final previousRendered = _rendered;
    _building = this;
    _rendered = keepWords(super.data!);
    try {
      return super.build(context);
    } finally {
      _building = previous;
      _rendered = previousRendered;
    }
  }
}
