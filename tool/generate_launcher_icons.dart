// 런처 아이콘 생성기.
//
// 실행: flutter test tool/generate_launcher_icons.dart
//
// flutter_test 바인딩 위에서 Flutter의 렌더러로 직접 그려 PNG로 떨군다. 그림은
// lib/core/theme/app_mark.dart의 16×16 비트맵, 색은 lib/core/theme/retro_palette.dart에서
// 가져온다 — 로그인 화면 마크·앱 화면 색과 출처가 한 곳이다. 모양이나 색을 바꾸려면 그 두
// 파일을 고치고 이 명령을 다시 돌린다.
//
// 번짐 없이 도트가 서도록 셀 크기를 밀도마다 정수 픽셀로 맞추고, 안티에일리어싱을 끈다.
//
// 만들어지는 것:
//   android/app/src/main/res/mipmap-*/ic_launcher.png             (API 25 이하용 정사각 아이콘)
//   android/app/src/main/res/mipmap-*/ic_launcher_foreground.png  (API 26+ 적응형 아이콘 전경)
//   android/app/src/main/res/mipmap-*/ic_launcher_monochrome.png  (안드로이드 13+ 테마 아이콘, 그림자 없음)
//   android/app/src/main/res/values/colors.xml                    (적응형 배경색, 시작 창 배경색)
//   store/icon-512.png                                            (Play 스토어 등록용)

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todododo/core/theme/app_mark.dart';
import 'package:todododo/core/theme/retro_palette.dart';

/// 밀도별 셀 크기(px). 적응형(108dp 캔버스 중 가운데 48dp)과 정사각(48dp 캔버스).
const _densities = <String, ({double scale, int foregroundCell, int launcherCell})>{
  'mdpi': (scale: 1, foregroundCell: 3, launcherCell: 1),
  'hdpi': (scale: 1.5, foregroundCell: 4, launcherCell: 2),
  'xhdpi': (scale: 2, foregroundCell: 6, launcherCell: 2),
  'xxhdpi': (scale: 3, foregroundCell: 9, launcherCell: 3),
  'xxxhdpi': (scale: 4, foregroundCell: 12, launcherCell: 4),
};

/// 스토어 512px 아이콘의 셀 크기. 그림 320px(62.5%).
const _storeCell = 20;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('런처 아이콘과 스토어 아이콘을 생성한다', () async {
    for (final MapEntry(key: name, value: d) in _densities.entries) {
      final dir = Directory('android/app/src/main/res/mipmap-$name');
      dir.createSync(recursive: true);

      final foregroundSize = (108 * d.scale).round();
      await _writePng(
        File('${dir.path}/ic_launcher_foreground.png'),
        await _render(foregroundSize, cell: d.foregroundCell, rows: AppMark.rows),
      );
      // 테마 아이콘은 알파만 쓰인다. 그림자까지 넣으면 칸과 체크가 한 덩어리로 뭉개진다.
      await _writePng(
        File('${dir.path}/ic_launcher_monochrome.png'),
        await _render(foregroundSize, cell: d.foregroundCell, rows: AppMark.monochromeRows),
      );

      final launcherSize = (48 * d.scale).round();
      await _writePng(
        File('${dir.path}/ic_launcher.png'),
        await _render(
          launcherSize,
          cell: d.launcherCell,
          rows: AppMark.rows,
          background: _Background.stepped,
        ),
      );
    }

    // 스토어 아이콘은 Play가 모서리를 깎으므로 꽉 찬 정사각으로 만든다.
    Directory('store').createSync(recursive: true);
    await _writePng(
      File('store/icon-512.png'),
      await _render(512, cell: _storeCell, rows: AppMark.rows, background: _Background.square),
    );

    final colors = File('android/app/src/main/res/values/colors.xml');
    await colors.writeAsString(
      '<?xml version="1.0" encoding="utf-8"?>\n'
      '<!-- tool/generate_launcher_icons.dart가 생성한다. 직접 고치지 말 것 —\n'
      '     색은 lib/core/theme/retro_palette.dart에서 온다. -->\n'
      '<resources>\n'
      '    <!-- 적응형 아이콘 배경 = 앱 주 강조색 -->\n'
      '    <color name="ic_launcher_background">${_hex(RetroPalette.primary)}</color>\n'
      '    <!-- 시작 창 배경 = 앱 화면 배경. 다크 모드 기기에서도 같다. -->\n'
      '    <color name="launch_background">${_hex(RetroPalette.paper)}</color>\n'
      '</resources>\n',
    );
    debugPrint('wrote ${colors.path}');
  });
}

enum _Background { none, stepped, square }

String _hex(Color color) =>
    '#${color.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';

Future<Uint8List> _render(
  int size, {
  required int cell,
  required List<String> rows,
  _Background background = _Background.none,
}) async {
  final side = size.toDouble();
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, side, side));

  if (background != _Background.none) {
    final paint = Paint()
      ..color = RetroPalette.primary
      ..isAntiAlias = false;
    if (background == _Background.square) {
      canvas.drawRect(Rect.fromLTWH(0, 0, side, side), paint);
    } else {
      // 둥근 모서리 대신 계단 모서리: 네 모서리에서 셀 한 칸을 비운다.
      final notch = cell.toDouble();
      canvas.drawRect(Rect.fromLTWH(notch, 0, side - notch * 2, side), paint);
      canvas.drawRect(Rect.fromLTWH(0, notch, side, side - notch * 2), paint);
    }
  }

  final drawing = AppMark.size * cell;
  final origin = ((size - drawing) / 2).floorToDouble();
  final paint = Paint()..isAntiAlias = false;
  for (var y = 0; y < rows.length; y++) {
    for (var x = 0; x < rows[y].length; x++) {
      final color = AppMark.colorOf(rows[y][x]);
      if (color == null) continue;
      paint.color = color;
      canvas.drawRect(
        Rect.fromLTWH(origin + x * cell, origin + y * cell, cell.toDouble(), cell.toDouble()),
        paint,
      );
    }
  }

  final picture = recorder.endRecording();
  final image = await picture.toImage(size, size);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  picture.dispose();
  image.dispose();
  return data!.buffer.asUint8List();
}

Future<void> _writePng(File file, Uint8List bytes) async {
  await file.writeAsBytes(bytes);
  debugPrint('wrote ${file.path} (${bytes.length} bytes)');
}
