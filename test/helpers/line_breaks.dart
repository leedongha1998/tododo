import 'package:flutter/rendering.dart';

/// [paragraph]가 줄을 바꾼 자리(다음 줄 첫 글자의 위치)를 모두 돌려준다.
/// 글자마다 캐럿의 세로 위치를 보고, 앞 글자보다 아래로 내려간 글자를 줄 첫 글자로 친다.
List<int> lineStarts(RenderParagraph paragraph) {
  final text = paragraph.text.toPlainText();
  final starts = <int>[];
  double? previousTop;
  for (var i = 0; i < text.length; i++) {
    final top = paragraph.getOffsetForCaret(TextPosition(offset: i), Rect.zero).dy;
    if (previousTop != null && top > previousTop) starts.add(i);
    previousTop = top;
  }
  return starts;
}

/// 모든 줄바꿈이 공백 바로 뒤(어절 경계)에서 일어나는가.
bool breaksOnlyAtSpaces(RenderParagraph paragraph) {
  final text = paragraph.text.toPlainText();
  return lineStarts(paragraph).every((start) => start > 0 && text[start - 1] == ' ');
}

/// 줄마다 그려진 글자의 폭(줄 끝 공백 제외, 정수로 반올림). 줄은 [lineStarts]로 나눈다.
List<double> lineWidths(RenderParagraph paragraph) {
  final text = paragraph.text.toPlainText();
  final starts = [0, ...lineStarts(paragraph), text.length];
  final widths = <double>[];
  for (var i = 0; i + 1 < starts.length; i++) {
    var end = starts[i + 1];
    while (end > starts[i] && text[end - 1].trim().isEmpty) {
      end--;
    }
    final boxes = paragraph.getBoxesForSelection(TextSelection(baseOffset: starts[i], extentOffset: end));
    if (boxes.isEmpty) {
      widths.add(0);
      continue;
    }
    final left = boxes.map((box) => box.left).reduce((a, b) => a < b ? a : b);
    final right = boxes.map((box) => box.right).reduce((a, b) => a > b ? a : b);
    widths.add((right - left).roundToDouble());
  }
  return widths;
}

/// 가장 긴 줄과 가장 짧은 줄의 폭 차이.
double spread(List<double> widths) =>
    widths.reduce((a, b) => a > b ? a : b) - widths.reduce((a, b) => a < b ? a : b);

/// 마지막 줄의 어절들(WORD JOINER 제거).
List<String> lastLineWords(RenderParagraph paragraph) {
  final text = paragraph.text.toPlainText();
  final starts = lineStarts(paragraph);
  final last = text.substring(starts.isEmpty ? 0 : starts.last).replaceAll('\u2060', '').trim();
  return last.split(RegExp(r'\s+'));
}
