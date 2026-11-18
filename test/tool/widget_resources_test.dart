import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todododo/core/strings.dart';
import 'package:todododo/core/theme/app_palette.dart';

/// `res/values/widget_resources.xml`은 **생성물**이다(`tool/generate_widget_resources.dart`).
///
/// 생성기를 돌리지 않고 `AppStrings`·`AppPalette`만 고치면 위젯 선택기의 이름·설명과 캐시가 없을
/// 때의 한 줄, 그리고 위젯의 색이 **조용히 어긋난다**(네이티브는 테스트하지 않으므로 아무도
/// 알려 주지 않는다). 그 어긋남을 여기서 잡는다 — 이 테스트가 깨지면 고쳐야 할 것은 XML이 아니라
/// `flutter test tool/generate_widget_resources.dart`를 한 번 돌리는 일이다.
void main() {
  test('위젯 리소스 생성물이 지금의 문구·색과 일치한다', () {
    final file = File('android/app/src/main/res/values/widget_resources.xml');
    expect(file.existsSync(), isTrue, reason: '${file.path}가 없다');
    final xml = file.readAsStringSync();

    // 캐시로 전달할 수 없어 네이티브가 직접 갖는 문자열 셋(design 2.4).
    const strings = <String, String>{
      'todo_widget_name': AppStrings.widgetName,
      'todo_widget_description': AppStrings.widgetDescription,
      'todo_widget_no_cache': AppStrings.widgetNoCache,
    };
    strings.forEach((name, value) {
      expect(
        xml,
        contains('<string name="$name">${_xml(value)}</string>'),
        reason: '$name이 AppStrings와 다르다 — 생성기를 다시 돌릴 것',
      );
    });

    // 위젯은 앱과 같은 팔레트를 쓴다. Kotlin이 직접 쓰는 두 색(ink_muted·danger)이 특히 중요하다 —
    // note와 기한 줄의 "지남"이 그 색으로 갈린다.
    const colors = <String, Color>{
      'widget_background': AppPalette.background,
      'widget_surface': AppPalette.surface,
      'widget_sunken': AppPalette.sunken,
      'widget_line': AppPalette.line,
      'widget_outline': AppPalette.outline,
      'widget_ink': AppPalette.ink,
      'widget_ink_muted': AppPalette.inkMuted,
      'widget_danger': AppPalette.danger,
    };
    colors.forEach((name, color) {
      expect(
        xml,
        contains('<color name="$name">${_hex(color)}</color>'),
        reason: '$name이 AppPalette와 다르다 — 생성기를 다시 돌릴 것',
      );
    });
  });
}

// 아래 둘은 생성기의 같은 함수와 **같은 규칙**이어야 한다(그래서 일부러 베껴 둔다 — 한쪽이
// 바뀌면 이 테스트가 깨져 둘을 함께 보게 된다).
String _hex(Color color) =>
    '#${color.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';

String _xml(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');
