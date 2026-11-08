import 'package:flutter/material.dart';

/// WORD JOINER(U+2060). 줄바꿈을 막고 폭은 0이다.
const wordJoiner = '\u2060';

/// [text]의 어절(공백으로 나뉜 덩어리) 안 글자 사이마다 [wordJoiner]를 끼운다.
///
/// Flutter(ICU)는 한글을 음절마다 끊을 수 있다고 보아 "상대가 더 잘 / 했어요"처럼 단어 중간에서 줄을 바꾼다.
/// 어절 안을 묶어 두면 공백에서만 줄이 바뀐다. 한 어절이 한 줄보다 길면 그때는 엔진이 어절 안에서 자른다.
/// 공백·줄바꿈 문자는 그대로 둔다. 글자는 [String.runes] 단위로 다뤄 서로게이트 쌍을 가르지 않는다.
String keepWords(String text) {
  final buffer = StringBuffer();
  var previousWasWordChar = false;
  for (final rune in text.runes) {
    final char = String.fromCharCode(rune);
    final isSpace = char.trim().isEmpty;
    if (!isSpace && previousWasWordChar) buffer.write(wordJoiner);
    buffer.write(char);
    previousWasWordChar = !isSpace;
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

/// 어절 단위로만 줄을 바꾸는 [Text]. 좁은 칸의 짧은 라벨(판정 세그먼트 등)에 쓴다.
///
/// 문자열 상수(`strings.dart`)는 그대로 두고 그릴 때만 [keepWords]로 바꾼다. 화면 낭독기에는
/// 원문을 읽히도록 `semanticsLabel`에 [text]를 그대로 넘긴다.
class KeepWordsText extends StatelessWidget {
  const KeepWordsText(this.text, {super.key, this.style, this.textAlign});

  /// 원문(낭독·테스트 기준).
  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    return Text(keepWords(text), style: style, textAlign: textAlign, semanticsLabel: text);
  }
}
