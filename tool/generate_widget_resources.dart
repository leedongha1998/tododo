// 홈 화면 투두 위젯의 안드로이드 리소스 생성기.
//
// 실행: flutter test tool/generate_widget_resources.dart
//
// 위젯에 보이는 문구는 거의 전부 기기 캐시(JSON)에 실려 가므로 네이티브가 가질 필요가 없다.
// 캐시로 전달할 수 없는 것만 여기서 XML 리소스로 떨군다 — 위젯 선택기에 뜨는 이름·설명(위젯을
// 올리기 전이라 캐시가 쓰이지 않는다)과 캐시가 아예 없을 때의 한 줄, 그리고 색이다.
// 문구의 출처는 lib/core/strings.dart, 색의 출처는 lib/core/theme/retro_palette.dart 하나다.
// 손으로 두 곳에 적으면 어긋나므로 이 명령으로 생성한다(선례: tool/generate_launcher_icons.dart).
//
// 만들어지는 것:
//   android/app/src/main/res/values/widget_resources.xml
//
// res/values/colors.xml은 런처 아이콘 생성기의 소유다. 그 파일을 덮지 않도록 일부러 다른 파일에 쓴다.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todododo/core/strings.dart';
import 'package:todododo/core/theme/retro_palette.dart';

void main() {
  test('홈 화면 위젯 리소스를 생성한다', () async {
    final file = File('android/app/src/main/res/values/widget_resources.xml');
    file.parent.createSync(recursive: true);

    final buffer = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="utf-8"?>')
      ..writeln('<!-- tool/generate_widget_resources.dart가 생성한다. 직접 고치지 말 것 —')
      ..writeln('     문구는 lib/core/strings.dart, 색은 lib/core/theme/retro_palette.dart에서 온다. -->')
      ..writeln('<resources>')
      ..writeln('    <!-- 위젯 선택기에 뜨는 이름과 설명. 위젯을 올리기 전에는 캐시가 쓰이지 않는다. -->')
      ..writeln('    <string name="todo_widget_name">${_xml(AppStrings.widgetName)}</string>')
      ..writeln('    <string name="todo_widget_description">${_xml(AppStrings.widgetDescription)}</string>')
      ..writeln('    <!-- 캐시가 아직 없거나 판 번호를 모를 때의 마지막 한 줄. 빈 사각형을 보여 주지 않는다. -->')
      ..writeln('    <string name="todo_widget_no_cache">${_xml(AppStrings.widgetNoCache)}</string>');

    const colors = <String, Color>{
      'widget_paper': RetroPalette.paper,
      'widget_surface': RetroPalette.surface,
      'widget_sunken': RetroPalette.sunken,
      'widget_line': RetroPalette.line,
      'widget_ink': RetroPalette.ink,
      'widget_ink_muted': RetroPalette.inkMuted,
      'widget_danger': RetroPalette.danger,
    };
    buffer.writeln('    <!-- 앱 화면과 같은 레트로 색. 위젯은 다크 모드에서도 같은 색을 쓴다. -->');
    for (final MapEntry(key: name, value: color) in colors.entries) {
      buffer.writeln('    <color name="$name">${_hex(color)}</color>');
    }
    buffer.writeln('</resources>');

    await file.writeAsString(buffer.toString());
    debugPrint('wrote ${file.path}');
  });
}

// 런처 아이콘 생성기와 같은 방식으로 적는다(android의 #AARRGGBB).
String _hex(Color color) =>
    '#${color.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';

String _xml(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');
