import 'package:flutter/foundation.dart';
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

/// 어절 단위로만 줄을 바꾸는 글자. 앱의 표시용 글자는 전부 이것을 쓴다(redesign 후속 결정 1).
///
/// - [Text]를 상속하지 않는다. 원문은 [text]에 그대로 두고, 그릴 때 [keepWords]를 거친 글자로 [RichText]를 직접 만든다
///   (redesign 후속 2 W1 — `Text.build` 중 `data`를 바꿔치기하던 옛 방식은 Flutter 내부 구현에 기댔다).
///   스타일 합성은 [Text.build]와 같은 공개 API로 한다: [DefaultTextStyle] 합성, 굵은 글씨 설정, 글자 배율, 기본 행 높이 동작.
///   웹 전용 글자 간격 덮어쓰기(`MediaQuery.*Override`)는 Android 앱이라 따르지 않는다.
/// - 테스트는 원문으로 찾는다 — `test/helpers/text_finders.dart`의 `findText`가 [Text]·[EditableText]·[KeepWordsText]를 함께 본다.
/// - 낭독기에는 원문(호출부가 준 [semanticsLabel]이 있으면 그것)을 읽힌다. 그리는 글자가 원문과 같고 [semanticsLabel]도 없으면
///   [RichText]의 낭독을 그대로 쓴다.
/// - 편집 가능한 글자(TextField 입력값)·복사 대상(SelectableText)에는 쓰지 않는다 — 끼운 글자가 복사·입력값에 섞인다.
class KeepWordsText extends StatelessWidget {
  const KeepWordsText(
    this.text, {
    super.key,
    this.style,
    this.strutStyle,
    this.textAlign,
    this.textDirection,
    this.locale,
    this.softWrap,
    this.overflow,
    this.textScaler,
    this.maxLines,
    this.semanticsLabel,
    this.semanticsIdentifier,
    this.textWidthBasis,
    this.textHeightBehavior,
    this.selectionColor,
  });

  /// 원문(낭독·테스트 기준).
  final String text;
  final TextStyle? style;
  final StrutStyle? strutStyle;
  final TextAlign? textAlign;
  final TextDirection? textDirection;
  final Locale? locale;
  final bool? softWrap;
  final TextOverflow? overflow;
  final TextScaler? textScaler;
  final int? maxLines;
  final String? semanticsLabel;
  final String? semanticsIdentifier;
  final TextWidthBasis? textWidthBasis;
  final TextHeightBehavior? textHeightBehavior;

  /// 선택 영역(SelectionArea) 안에서만 쓰인다. 앱에 선택 영역이 없어 지금은 받아 두기만 한다.
  final Color? selectionColor;

  @override
  Widget build(BuildContext context) {
    final defaultTextStyle = DefaultTextStyle.of(context);
    var effectiveStyle = style;
    if (style == null || style!.inherit) {
      effectiveStyle = defaultTextStyle.style.merge(style);
    }
    if (MediaQuery.boldTextOf(context)) {
      effectiveStyle = effectiveStyle!.merge(const TextStyle(fontWeight: FontWeight.bold));
    }
    final rendered = keepWords(text);
    Widget result = RichText(
      textAlign: textAlign ?? defaultTextStyle.textAlign ?? TextAlign.start,
      textDirection: textDirection,
      locale: locale,
      softWrap: softWrap ?? defaultTextStyle.softWrap,
      overflow: overflow ?? effectiveStyle?.overflow ?? defaultTextStyle.overflow,
      textScaler: textScaler ?? MediaQuery.textScalerOf(context),
      maxLines: maxLines ?? defaultTextStyle.maxLines,
      strutStyle: strutStyle,
      textWidthBasis: textWidthBasis ?? defaultTextStyle.textWidthBasis,
      textHeightBehavior:
          textHeightBehavior ?? defaultTextStyle.textHeightBehavior ?? DefaultTextHeightBehavior.maybeOf(context),
      text: TextSpan(style: effectiveStyle, text: rendered, locale: locale),
    );
    final label = semanticsLabel ?? (rendered == text ? null : text);
    if (label != null || semanticsIdentifier != null) {
      result = Semantics(
        textDirection: textDirection,
        label: label,
        identifier: semanticsIdentifier,
        child: ExcludeSemantics(excluding: label != null, child: result),
      );
    }
    return result;
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(StringProperty('text', text, showName: false));
    style?.debugFillProperties(properties);
  }
}
