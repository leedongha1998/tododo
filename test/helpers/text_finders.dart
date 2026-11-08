import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:todododo/core/widgets/keep_words_text.dart';

/// 글자 위젯이 보여 주는 **원문**. [KeepWordsText]는 [Text]가 아니라서(redesign 후속 2 W1) `find.text`가 찾지 못한다 —
/// 그래서 테스트는 이 파일의 finder를 쓴다. [Text]·[EditableText]는 `find.text`와 같은 기준으로 본다.
String? _shownText(Widget widget) => switch (widget) {
      KeepWordsText() => widget.text,
      Text() => widget.data ?? widget.textSpan?.toPlainText(),
      EditableText() => widget.controller.text,
      _ => null,
    };

/// `find.text`와 같되 [KeepWordsText]도 원문으로 찾는다.
Finder findText(String text, {bool skipOffstage = true}) => find.byWidgetPredicate(
      (widget) => _shownText(widget) == text,
      description: 'text "$text"',
      skipOffstage: skipOffstage,
    );

/// `find.textContaining`과 같되 [KeepWordsText]도 원문으로 찾는다.
Finder findTextContaining(Pattern pattern, {bool skipOffstage = true}) => find.byWidgetPredicate(
      (widget) => _shownText(widget)?.contains(pattern) ?? false,
      description: 'text containing $pattern',
      skipOffstage: skipOffstage,
    );

/// `find.widgetWithText`와 같되 [KeepWordsText]도 원문으로 찾는다.
Finder findWidgetWithText(Type widgetType, String text, {bool skipOffstage = true}) => find.ancestor(
      of: findText(text, skipOffstage: skipOffstage),
      matching: find.byType(widgetType, skipOffstage: skipOffstage),
    );
