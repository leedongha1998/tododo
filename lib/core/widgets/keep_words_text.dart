import 'package:flutter/foundation.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

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

/// 여러 줄이 될 때 줄을 어떻게 나눌지(redesign 후속 2 W2). 어느 쪽이든 줄은 어절 경계에서만 바뀐다([keepWords]).
enum KeepWordsWrap {
  /// 줄 수를 유지하는 가장 좁은 폭으로 그려 줄 길이를 고르게 한다(CSS `text-wrap: balance`). 4줄 이하에만 적용한다.
  /// 제목·라벨·버튼·칩처럼 짧은 글자용. 위젯이 차지하는 폭과 정렬은 그대로다.
  balanced,

  /// 문단의 마지막 줄에 한 어절만 남지 않게 마지막 두 어절을 붙인다(고아 방지). 붙인 두 어절이 칸보다 넓으면 붙이지 않는다.
  /// 설명·안내·동의 문구·할 일 내용 같은 본문용.
  pretty,

  /// 엔진의 기본 줄 나눔(어절 경계만 지킨다).
  none,
}

/// design 3.2 역할표에서 본문 슬롯(bodyLarge·bodyMedium·bodySmall)의 행간은 1.55~1.6, 제목·라벨·숫자 슬롯은 1.2~1.5다.
/// [KeepWordsText.wrap]을 생략하면 합성된 스타일의 행간으로 역할을 가린다.
const double bodyLineHeightThreshold = 1.55;

/// 행간 < [bodyLineHeightThreshold] → [KeepWordsWrap.balanced](제목·라벨), 그 밖(행간이 없는 경우 포함) → [KeepWordsWrap.pretty].
/// 행간이 없으면 본문 쪽으로 둔다 — pretty는 줄 폭을 줄이지 않아 더 보수적이다.
KeepWordsWrap wrapForStyle(TextStyle? style) {
  final height = style?.height;
  return height != null && height < bodyLineHeightThreshold ? KeepWordsWrap.balanced : KeepWordsWrap.pretty;
}

/// 어절 단위로만 줄을 바꾸는 글자. 앱의 표시용 글자는 전부 이것을 쓴다(redesign 후속 결정 1).
///
/// - [Text]를 상속하지 않는다. 원문은 [text]에 그대로 두고, 그릴 때 [keepWords]를 거친 글자로 [RichText]를 직접 만든다
///   (redesign 후속 2 W1 — `Text.build` 중 `data`를 바꿔치기하던 옛 방식은 Flutter 내부 구현에 기댔다).
///   스타일 합성은 [Text.build]와 같은 공개 API로 한다: [DefaultTextStyle] 합성, 굵은 글씨 설정, 글자 배율, 기본 행 높이 동작.
///   웹 전용 글자 간격 덮어쓰기(`MediaQuery.*Override`)는 Android 앱이라 따르지 않는다.
/// - 줄 모양은 [wrap](생략하면 [wrapForStyle])으로 정한다. 칸 폭을 알아야 하므로 [RichText]는 레이아웃 단계에서 만든다
///   (계획값이 같으면 다시 만들지 않는다). 고유 크기 질의(IntrinsicWidth·대화상자)에는 [TextPainter]로 직접 답한다.
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
    this.wrap,
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

  /// 줄 모양. null이면 합성된 스타일로 정한다([wrapForStyle]).
  final KeepWordsWrap? wrap;

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
    Widget result = _KeepWordsLayout(
      _WrapConfig(
        mode: wrap ?? wrapForStyle(effectiveStyle),
        text: rendered,
        style: effectiveStyle,
        textAlign: textAlign ?? defaultTextStyle.textAlign ?? TextAlign.start,
        textDirection: textDirection ?? Directionality.of(context),
        locale: locale ?? Localizations.maybeLocaleOf(context),
        softWrap: softWrap ?? defaultTextStyle.softWrap,
        overflow: overflow ?? effectiveStyle?.overflow ?? defaultTextStyle.overflow,
        textScaler: textScaler ?? MediaQuery.textScalerOf(context),
        maxLines: maxLines ?? defaultTextStyle.maxLines,
        strutStyle: strutStyle,
        textWidthBasis: textWidthBasis ?? defaultTextStyle.textWidthBasis,
        textHeightBehavior:
            textHeightBehavior ?? defaultTextStyle.textHeightBehavior ?? DefaultTextHeightBehavior.maybeOf(context),
      ),
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
    properties.add(EnumProperty<KeepWordsWrap>('wrap', wrap, defaultValue: null));
    style?.debugFillProperties(properties);
  }
}

/// [RichText]에 넘길 값 전부(합성이 끝난 값). 계획 캐시의 키로도 쓴다.
@immutable
class _WrapConfig {
  const _WrapConfig({
    required this.mode,
    required this.text,
    required this.style,
    required this.textAlign,
    required this.textDirection,
    required this.locale,
    required this.softWrap,
    required this.overflow,
    required this.textScaler,
    required this.maxLines,
    required this.strutStyle,
    required this.textWidthBasis,
    required this.textHeightBehavior,
  });

  final KeepWordsWrap mode;

  /// [keepWords]를 거친 글자.
  final String text;
  final TextStyle? style;
  final TextAlign textAlign;
  final TextDirection textDirection;
  final Locale? locale;
  final bool softWrap;
  final TextOverflow overflow;
  final TextScaler textScaler;
  final int? maxLines;
  final StrutStyle? strutStyle;
  final TextWidthBasis textWidthBasis;
  final TextHeightBehavior? textHeightBehavior;

  TextSpan span(String text) => TextSpan(style: style, text: text, locale: locale);

  /// [RenderParagraph]와 같은 설정의 [TextPainter]. 호출부가 dispose한다.
  TextPainter painter(String text, {int? maxLines}) => TextPainter(
        text: span(text),
        textAlign: textAlign,
        textDirection: textDirection,
        locale: locale,
        maxLines: maxLines ?? this.maxLines,
        ellipsis: overflow == TextOverflow.ellipsis ? '…' : null,
        textScaler: textScaler,
        strutStyle: strutStyle,
        textWidthBasis: textWidthBasis,
        textHeightBehavior: textHeightBehavior,
      );

  Widget build(_WrapPlan plan) => RichText(
        textAlign: textAlign,
        textDirection: textDirection,
        locale: locale,
        softWrap: softWrap,
        overflow: overflow,
        textScaler: textScaler,
        maxLines: maxLines,
        strutStyle: strutStyle,
        textWidthBasis: textWidthBasis,
        textHeightBehavior: textHeightBehavior,
        text: span(plan.text),
      );

  @override
  bool operator ==(Object other) =>
      other is _WrapConfig &&
      other.mode == mode &&
      other.text == text &&
      other.style == style &&
      other.textAlign == textAlign &&
      other.textDirection == textDirection &&
      other.locale == locale &&
      other.softWrap == softWrap &&
      other.overflow == overflow &&
      other.textScaler == textScaler &&
      other.maxLines == maxLines &&
      other.strutStyle == strutStyle &&
      other.textWidthBasis == textWidthBasis &&
      other.textHeightBehavior == textHeightBehavior;

  @override
  int get hashCode => Object.hash(mode, text, style, textAlign, textDirection, locale, softWrap, overflow, textScaler,
      maxLines, strutStyle, textWidthBasis, textHeightBehavior);
}

/// 칸 폭 하나에 대한 결정: 그릴 글자(pretty는 마지막 두 어절을 붙인 글자)와 글자를 그릴 폭(balanced, null이면 칸 폭 그대로).
@immutable
class _WrapPlan {
  const _WrapPlan(this.text, [this.width]);

  final String text;
  final double? width;

  @override
  bool operator ==(Object other) => other is _WrapPlan && other.text == text && other.width == width;

  @override
  int get hashCode => Object.hash(text, width);
}

/// 계획값 캐시(설정 + 칸 폭). 목록을 스크롤하며 위젯이 다시 만들어져도 이분 탐색을 되풀이하지 않는다.
final _planCache = <(_WrapConfig, double), _WrapPlan>{}; // 넣은 순서를 지킨다(LRU).
const _planCacheSize = 512;

/// balanced를 적용하는 최대 줄 수.
const balancedMaxLines = 4;

_WrapPlan _planFor(_WrapConfig config, double maxWidth) {
  final base = _WrapPlan(config.text);
  if (config.mode == KeepWordsWrap.none || !maxWidth.isFinite || !config.softWrap) return base;
  final key = (config, maxWidth);
  final cached = _planCache.remove(key);
  if (cached != null) {
    _planCache[key] = cached; // 최근 사용으로 옮긴다.
    return cached;
  }
  final plan = _computePlan(config, maxWidth, base);
  _planCache[key] = plan;
  if (_planCache.length > _planCacheSize) _planCache.remove(_planCache.keys.first);
  return plan;
}

/// 테스트용 — 캐시를 비운다.
@visibleForTesting
void debugClearKeepWordsPlanCache() => _planCache.clear();

_WrapPlan _computePlan(_WrapConfig config, double maxWidth, _WrapPlan base) {
  final painter = config.painter(config.text);
  try {
    painter.layout(maxWidth: maxWidth);
    final lines = painter.computeLineMetrics().length;
    if (lines < 2 || painter.didExceedMaxLines) return base;
    switch (config.mode) {
      case KeepWordsWrap.none:
        return base;
      case KeepWordsWrap.pretty:
        final joined = joinLastWords(config.text, (pair) {
          final measure = config.painter(pair, maxLines: null)..layout();
          final width = measure.width;
          measure.dispose();
          return width <= maxWidth;
        });
        if (joined == config.text) return base;
        // 붙인 두 어절이 칸 안에 들어가면 줄 수는 늘지 않는다 — 그래도 확인하고, 어긋나면 붙이지 않는다.
        final check = config.painter(joined)..layout(maxWidth: maxWidth);
        final ok = !check.didExceedMaxLines && check.computeLineMetrics().length <= lines;
        check.dispose();
        return ok ? _WrapPlan(joined) : base;
      case KeepWordsWrap.balanced:
        if (lines > balancedMaxLines || config.textAlign == TextAlign.justify) return base;
        var lo = painter.minIntrinsicWidth;
        var hi = maxWidth;
        // 줄 수가 그대로인 가장 좁은 폭. 0.5dp까지 좁히면 충분하다(최대 약 10번).
        while (hi - lo > 0.5) {
          final mid = (lo + hi) / 2;
          painter.layout(maxWidth: mid);
          if (!painter.didExceedMaxLines && painter.computeLineMetrics().length == lines) {
            hi = mid;
          } else {
            lo = mid;
          }
        }
        return hi >= maxWidth - 0.5 ? base : _WrapPlan(config.text, hi);
    }
  } finally {
    painter.dispose();
  }
}

/// 문단(`\n`으로 나뉜 덩어리)마다 마지막 공백 뒤에 [wordJoiner]를 넣어 마지막 두 어절이 한 줄에 같이 있게 한다.
/// [fits]가 그 두 어절(사이 공백 포함)을 받아 거짓을 돌려주면 그 문단은 그대로 둔다. 어절이 하나뿐인 문단도 그대로다.
/// 공백은 U+0020만 본다(줄바꿈 금지 공백 등은 이미 붙어 있다).
String joinLastWords(String text, bool Function(String pair) fits) {
  final paragraphs = text.split('\n');
  for (var i = 0; i < paragraphs.length; i++) {
    final paragraph = paragraphs[i];
    final end = paragraph.trimRight().length;
    if (end == 0) continue;
    final lastSpace = paragraph.lastIndexOf(' ', end - 1);
    if (lastSpace < 0) continue;
    // 마지막 공백 덩어리의 앞 끝과, 그 앞 어절의 시작.
    var spaceStart = lastSpace;
    while (spaceStart > 0 && paragraph[spaceStart - 1] == ' ') {
      spaceStart--;
    }
    if (spaceStart == 0 || paragraph.substring(0, spaceStart).trim().isEmpty) continue;
    final previousSpace = paragraph.lastIndexOf(' ', spaceStart - 1);
    final pair = paragraph.substring(previousSpace + 1, end);
    if (!fits(pair)) continue;
    paragraphs[i] = '${paragraph.substring(0, lastSpace + 1)}$wordJoiner${paragraph.substring(lastSpace + 1)}';
  }
  return paragraphs.join('\n');
}

/// 칸 폭을 받은 뒤 [_WrapPlan]을 정하고, 그 계획으로 [RichText]를 만든다.
class _KeepWordsLayout extends AbstractLayoutBuilder<_WrapPlan> {
  const _KeepWordsLayout(this.config);

  final _WrapConfig config;

  @override
  Widget Function(BuildContext context, _WrapPlan plan) get builder => _build;

  Widget _build(BuildContext context, _WrapPlan plan) => config.build(plan);

  @override
  bool updateShouldRebuild(_KeepWordsLayout oldWidget) => oldWidget.config != config;

  @override
  _RenderKeepWords createRenderObject(BuildContext context) => _RenderKeepWords(config);

  @override
  void updateRenderObject(BuildContext context, _RenderKeepWords renderObject) {
    renderObject.config = config;
  }
}

class _RenderKeepWords extends RenderBox
    with
        RenderObjectWithChildMixin<RenderBox>,
        RenderObjectWithLayoutCallbackMixin,
        RenderAbstractLayoutBuilderMixin<_WrapPlan, RenderBox> {
  _RenderKeepWords(this._config);

  _WrapConfig _config;
  _WrapConfig get config => _config;
  set config(_WrapConfig value) {
    if (value == _config) return;
    _config = value;
    _intrinsicWidths = null;
    markNeedsLayout();
  }

  @override
  _WrapPlan get layoutInfo => _planFor(_config, constraints.maxWidth);

  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! BoxParentData) child.parentData = BoxParentData();
  }

  /// 계획에 따라 글자에 줄 제약.
  BoxConstraints _childConstraints(BoxConstraints constraints, _WrapPlan plan) {
    final width = plan.width;
    if (width == null) return constraints;
    return constraints.copyWith(minWidth: math.min(constraints.minWidth, width), maxWidth: width);
  }

  /// 글자 크기([RenderParagraph]와 같은 계산) → 위젯 크기. balanced로 좁혔어도 칸 폭 기준(`textWidthBasis.parent`)이면
  /// 원래처럼 칸 폭 전체를 차지한다 — 주변 정렬이 흔들리지 않게.
  Size _ownSize(BoxConstraints constraints, _WrapPlan plan, Size childSize) {
    final width = plan.width != null && _config.textWidthBasis == TextWidthBasis.parent
        ? constraints.maxWidth
        : childSize.width;
    return constraints.constrain(Size(width, childSize.height));
  }

  double _childDx(Size size, Size childSize) {
    final free = size.width - childSize.width;
    if (free <= 0) return 0;
    final rtl = _config.textDirection == TextDirection.rtl;
    return switch (_config.textAlign) {
      TextAlign.center => free / 2,
      TextAlign.right => free,
      TextAlign.left || TextAlign.justify => 0,
      TextAlign.start => rtl ? free : 0,
      TextAlign.end => rtl ? 0 : free,
    };
  }

  @override
  void performLayout() {
    final constraints = this.constraints;
    runLayoutCallback();
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    final plan = _planFor(_config, constraints.maxWidth);
    child.layout(_childConstraints(constraints, plan), parentUsesSize: true);
    size = _ownSize(constraints, plan, child.size);
    (child.parentData! as BoxParentData).offset = Offset(_childDx(size, child.size), 0);
  }

  /// 실제로 배치하지 않고 [TextPainter]로 같은 계산을 한다(고유 크기·dry layout).
  (Size, double?) _measure(BoxConstraints constraints, {TextBaseline? baseline}) {
    final plan = _planFor(_config, constraints.maxWidth);
    final childConstraints = _childConstraints(constraints, plan);
    final painter = _config.painter(plan.text);
    final widthMatters = _config.softWrap || _config.overflow == TextOverflow.ellipsis;
    painter.layout(
      minWidth: childConstraints.minWidth,
      maxWidth: widthMatters ? childConstraints.maxWidth : double.infinity,
    );
    final childSize = childConstraints.constrain(painter.size);
    final distance = baseline == null ? null : painter.computeDistanceToActualBaseline(baseline);
    painter.dispose();
    return (_ownSize(constraints, plan, childSize), distance);
  }

  /// (최소, 최대) 고유 폭. 설정이 바뀔 때만 다시 잰다.
  (double, double)? _intrinsicWidths;

  double _intrinsicWidth({required bool min}) {
    var widths = _intrinsicWidths;
    if (widths == null) {
      final painter = _config.painter(_config.text)..layout();
      widths = _intrinsicWidths = (painter.minIntrinsicWidth, painter.maxIntrinsicWidth);
      painter.dispose();
    }
    return min ? widths.$1 : widths.$2;
  }

  @override
  double computeMinIntrinsicWidth(double height) => _intrinsicWidth(min: true);

  @override
  double computeMaxIntrinsicWidth(double height) => _intrinsicWidth(min: false);

  @override
  double computeMinIntrinsicHeight(double width) => _measure(BoxConstraints(maxWidth: width)).$1.height;

  @override
  double computeMaxIntrinsicHeight(double width) => computeMinIntrinsicHeight(width);

  @override
  Size computeDryLayout(BoxConstraints constraints) => _measure(constraints).$1;

  @override
  double? computeDryBaseline(BoxConstraints constraints, TextBaseline baseline) =>
      _measure(constraints, baseline: baseline).$2;

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) {
    final child = this.child;
    if (child == null) return null;
    final distance = child.getDistanceToActualBaseline(baseline);
    return distance == null ? null : distance + (child.parentData! as BoxParentData).offset.dy;
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final child = this.child;
    if (child == null) return false;
    final offset = (child.parentData! as BoxParentData).offset;
    return result.addWithPaintOffset(
      offset: offset,
      position: position,
      hitTest: (result, transformed) => child.hitTest(result, position: transformed),
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child != null) context.paintChild(child, offset + (child.parentData! as BoxParentData).offset);
  }
}
