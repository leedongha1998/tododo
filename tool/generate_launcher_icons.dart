// 런처 아이콘 생성기.
//
// 실행: flutter test tool/generate_launcher_icons.dart
//
// flutter_test 바인딩 위에서 Flutter의 렌더러로 직접 그려 PNG로 떨군다. 그림은
// lib/core/theme/app_mark.dart의 벡터 마크(AppMark.paint), 색은 lib/core/theme/app_palette.dart에서
// 가져온다 — 로그인 화면 마크·앱 화면 색과 출처가 한 곳이다. 모양이나 색을 바꾸려면 그 두
// 파일을 고치고 이 명령을 다시 돌린다.
//
// 벡터라 밀도마다 배율만 바꿔 같은 비율로 그린다(안티에일리어싱 켬).
//
// 만들어지는 것:
//   android/app/src/main/res/mipmap-*/ic_launcher.png             (API 25 이하용 정사각 아이콘)
//   android/app/src/main/res/mipmap-*/ic_launcher_foreground.png  (API 26+ 적응형 아이콘 전경)
//   android/app/src/main/res/mipmap-*/ic_launcher_monochrome.png  (안드로이드 13+ 테마 아이콘, 두께 없음)
//   android/app/src/main/res/drawable-*/ic_notification.png       (알림 작은 아이콘, 흰 실루엣)
//   android/app/src/main/res/values/colors.xml                    (적응형 배경색, 시작 창 배경색)
//   store/icon-512.png                                            (Play 스토어 등록용)

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todododo/core/theme/app_mark.dart';
import 'package:todododo/core/theme/app_palette.dart';

/// 밀도 이름 → dp당 픽셀.
const _densities = <String, double>{
  'mdpi': 1,
  'hdpi': 1.5,
  'xhdpi': 2,
  'xxhdpi': 3,
  'xxxhdpi': 4,
};

// 캔버스와 마크 상자 크기(dp, redesign design 7.2).

/// 적응형 아이콘 캔버스. 가운데 지름 66dp(반지름 33)가 어떤 모양으로 깎여도 남는 안전 원이다.
const _adaptiveCanvas = 108.0;
const _adaptiveBox = 44.0;

/// API 25 이하 정사각 아이콘: 브랜드 둥근 사각 배경(모서리 10dp) 위 상자 34dp.
const _legacyCanvas = 48.0;
const _legacyBox = 34.0;
const _legacyRadius = 10.0;

/// 알림 작은 아이콘: 밀도마다 정확히 24dp, 상자 20dp, 흰 실루엣.
const _notificationCanvas = 24.0;
const _notificationBox = 20.0;

/// 스토어 아이콘: 512px 꽉 찬 브랜드 정사각(모서리는 Play가 깎음), 상자 300px.
const _storeSize = 512;
const _storeBox = 300.0;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('런처 아이콘과 스토어 아이콘을 생성한다', () async {
    for (final MapEntry(key: name, value: scale) in _densities.entries) {
      final dir = Directory('android/app/src/main/res/mipmap-$name');
      dir.createSync(recursive: true);

      final foregroundSize = (_adaptiveCanvas * scale).round();
      await _writePng(
        File('${dir.path}/ic_launcher_foreground.png'),
        await _render(foregroundSize, box: _adaptiveBox * scale),
      );
      // 테마 아이콘은 알파만 쓰인다. 두께까지 넣으면 칸과 체크가 한 덩어리로 뭉개진다.
      await _writePng(
        File('${dir.path}/ic_launcher_monochrome.png'),
        await _render(foregroundSize, box: _adaptiveBox * scale, monochrome: true),
      );

      await _writePng(
        File('${dir.path}/ic_launcher.png'),
        await _render(
          (_legacyCanvas * scale).round(),
          box: _legacyBox * scale,
          background: _Background.rounded,
          radius: _legacyRadius * scale,
        ),
      );

      // 알림 작은 아이콘: 시스템이 알파만 쓰고 색을 제 테마로 칠한다. 두께를 빼야 칸과 체크가
      // 뭉개지지 않으므로 테마 아이콘과 같은 단색 그림을 흰색으로 그린다.
      final notificationDir = Directory('android/app/src/main/res/drawable-$name');
      notificationDir.createSync(recursive: true);
      await _writePng(
        File('${notificationDir.path}/ic_notification.png'),
        await _render(
          (_notificationCanvas * scale).round(),
          box: _notificationBox * scale,
          monochrome: true,
        ),
      );
    }

    // 스토어 아이콘은 Play가 모서리를 깎으므로 꽉 찬 정사각으로 만든다.
    Directory('store').createSync(recursive: true);
    await _writePng(
      File('store/icon-512.png'),
      await _render(_storeSize, box: _storeBox, background: _Background.square),
    );

    final colors = File('android/app/src/main/res/values/colors.xml');
    await colors.writeAsString(
      '<?xml version="1.0" encoding="utf-8"?>\n'
      '<!-- tool/generate_launcher_icons.dart가 생성한다. 직접 고치지 말 것 —\n'
      '     색은 lib/core/theme/app_palette.dart에서 온다. -->\n'
      '<resources>\n'
      '    <!-- 적응형 아이콘 배경 = 브랜드색(primary) -->\n'
      '    <color name="ic_launcher_background">${_hex(AppPalette.primary)}</color>\n'
      '    <!-- 시작 창 배경 = 앱 화면 배경(background). 다크 모드 기기에서도 같다. -->\n'
      '    <color name="launch_background">${_hex(AppPalette.background)}</color>\n'
      '</resources>\n',
    );
    debugPrint('wrote ${colors.path}');
  });
}

enum _Background { none, rounded, square }

String _hex(Color color) =>
    '#${color.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';

/// [size]px 정사각 캔버스 가운데 [box]px 상자에 마크를 그린다.
Future<Uint8List> _render(
  int size, {
  required double box,
  bool monochrome = false,
  _Background background = _Background.none,
  double radius = 0,
}) async {
  final side = size.toDouble();
  final canvasRect = Rect.fromLTWH(0, 0, side, side);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, canvasRect);

  final backgroundPaint = Paint()..color = AppPalette.primary;
  switch (background) {
    case _Background.none:
      break;
    case _Background.square:
      canvas.drawRect(canvasRect, backgroundPaint);
    case _Background.rounded:
      canvas.drawRRect(RRect.fromRectAndRadius(canvasRect, Radius.circular(radius)), backgroundPaint);
  }

  AppMark.paint(
    canvas,
    Rect.fromCenter(center: canvasRect.center, width: box, height: box),
    monochrome: monochrome,
    monoColor: const Color(0xFFFFFFFF),
  );

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
