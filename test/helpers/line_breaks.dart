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
