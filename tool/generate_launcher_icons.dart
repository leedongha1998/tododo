// 런처 아이콘 생성기.
//
// 실행: flutter test tool/generate_launcher_icons.dart
//
// flutter_test 바인딩 위에서 Flutter의 렌더러(Skia)로 직접 그려 PNG로 떨군다.
// 아이콘 하나 만들자고 flutter_launcher_icons + 원본 PNG를 들이는 대신, 그림 자체를
// 코드로 두고 필요할 때 다시 뽑는다. 색/모양을 바꾸려면 아래 상수와 _drawMark만 고치면 된다.
//
// 만들어지는 것:
//   android/app/src/main/res/mipmap-*/ic_launcher.png             (API 25 이하용 정사각 아이콘)
//   android/app/src/main/res/mipmap-*/ic_launcher_foreground.png  (API 26+ 적응형 아이콘 전경)
//   store/icon-512.png                                            (Play 스토어 등록용)
//
// 적응형 아이콘의 배경은 PNG가 아니라 res/drawable/ic_launcher_background.xml(그라디언트)이다.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 앱 테마 시드(Colors.deepOrange)와 같은 계열. 밝은 쪽 → 어두운 쪽 대각선 그라디언트.
const _gradientStart = Color(0xFFFF7A3D);
const _gradientEnd = Color(0xFFE04A16);

/// 적응형 아이콘은 108dp 중 가운데 72dp만 항상 보인다(나머지는 기기 모양에 따라 잘림).
const _adaptiveSafeRatio = 72 / 108;

/// dpi별 배율. mdpi 기준 48dp(런처) / 108dp(적응형 전경).
const _densities = <String, double>{
  'mdpi': 1,
  'hdpi': 1.5,
  'xhdpi': 2,
  'xxhdpi': 3,
  'xxxhdpi': 4,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('런처 아이콘과 스토어 아이콘을 생성한다', () async {
    for (final entry in _densities.entries) {
      final dir = Directory('android/app/src/main/res/mipmap-${entry.key}');
      dir.createSync(recursive: true);

      final launcherSize = (48 * entry.value).round();
      await _writePng(
        File('${dir.path}/ic_launcher.png'),
        await _renderIcon(launcherSize, background: _Background.rounded, contentRatio: 0.62),
      );

      // 적응형 전경은 배경 없이 마크만. 안전 영역 안에 들어가도록 더 작게 그린다.
      final foregroundSize = (108 * entry.value).round();
      await _writePng(
        File('${dir.path}/ic_launcher_foreground.png'),
        await _renderIcon(
          foregroundSize,
          background: _Background.none,
          contentRatio: 0.62 * _adaptiveSafeRatio,
        ),
      );
    }

    // 스토어 아이콘은 Play가 알아서 모서리를 깎으므로 꽉 찬 정사각으로 만든다.
    Directory('store').createSync(recursive: true);
    await _writePng(
      File('store/icon-512.png'),
      await _renderIcon(512, background: _Background.square, contentRatio: 0.62),
    );
  });
}

enum _Background { none, rounded, square }

Future<Uint8List> _renderIcon(
  int size, {
  required _Background background,
  required double contentRatio,
}) async {
  final side = size.toDouble();
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, side, side));

  if (background != _Background.none) {
    final rect = Rect.fromLTWH(0, 0, side, side);
    final paint = Paint()
      ..shader = ui.Gradient.linear(
        Offset.zero,
        Offset(side, side),
        const [_gradientStart, _gradientEnd],
      );
    if (background == _Background.rounded) {
      canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(side * 0.22)), paint);
    } else {
      canvas.drawRect(rect, paint);
    }
  }

  final content = side * contentRatio;
  canvas.save();
  canvas.translate((side - content) / 2, (side - content) / 2);
  canvas.scale(content);
  _drawMark(canvas);
  canvas.restore();

  final picture = recorder.endRecording();
  final image = await picture.toImage(size, size);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  picture.dispose();
  image.dispose();
  return data!.buffer.asUint8List();
}

/// 0~1 좌표계에 마크를 그린다. 앞선 체크 하나와 뒤따르는 흐린 체크 하나 —
/// "같은 할 일을 두 사람이 겨룬다"는 앱의 성격을 한 글자로 줄인 모양이다.
void _drawMark(Canvas canvas) {
  final check = Path()
    ..moveTo(0.16, 0.54)
    ..lineTo(0.40, 0.78)
    ..lineTo(0.86, 0.24);

  final trailing = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.15
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..color = Colors.white.withValues(alpha: 0.42);

  final leading = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.17
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..color = Colors.white;

  canvas.save();
  canvas.translate(-0.14, 0.13);
  canvas.scale(0.82);
  canvas.drawPath(check, trailing);
  canvas.restore();

  canvas.drawPath(check, leading);
}

Future<void> _writePng(File file, Uint8List bytes) async {
  await file.writeAsBytes(bytes);
  debugPrint('wrote ${file.path} (${bytes.length} bytes)');
}
