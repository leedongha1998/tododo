import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todododo/core/theme/app_palette.dart';
import 'package:todododo/core/theme/depth_border.dart';

void main() {
  const rect = Rect.fromLTWH(0, 0, 100, 52);
  const side = BorderSide(color: AppPalette.outline, width: 1);
  const raised = DepthBorder(side: side, radius: 12, depth: 2);
  const pressed = DepthBorder(side: side, radius: 12, depth: 2, pressed: true);

  bool within(Rect outer, Rect inner) =>
      outer.inflate(0.01).contains(inner.topLeft) &&
      outer.inflate(0.01).contains(inner.bottomRight);

  test('두께는 바깥 상자 안쪽에 있다 — 눌려도 바깥 경로가 같은 상자 안이다', () {
    expect(within(rect, raised.getOuterPath(rect).getBounds()), isTrue);
    expect(within(rect, pressed.getOuterPath(rect).getBounds()), isTrue);
    // 안 눌림은 상자를 꽉 채우고, 눌림은 위 두께만큼 비운다(면이 내려왔다).
    expect(raised.getOuterPath(rect).getBounds().top, closeTo(0, 0.01));
    expect(pressed.getOuterPath(rect).getBounds().top, closeTo(2, 0.01));
    expect(pressed.getOuterPath(rect).getBounds().bottom, closeTo(52, 0.01));
  });

  test('안 눌림은 바닥에 두께가, 눌림은 위에 같은 만큼 여백이 붙는다', () {
    expect(raised.dimensions, const EdgeInsets.fromLTRB(1, 1, 1, 3));
    expect(pressed.dimensions, const EdgeInsets.fromLTRB(1, 3, 1, 1));
    // 테두리 없고 두께 없으면 여백도 없다.
    expect(const DepthBorder().dimensions, EdgeInsets.zero);
  });

  test('모서리가 둥글다 — 모서리 점은 경로 밖, 가운데는 안', () {
    final path = raised.getOuterPath(rect);
    expect(path.contains(const Offset(0.5, 0.5)), isFalse);
    expect(path.contains(const Offset(99.5, 0.5)), isFalse);
    expect(path.contains(const Offset(0.5, 51.5)), isFalse);
    expect(path.contains(const Offset(99.5, 51.5)), isFalse);
    expect(path.contains(const Offset(50, 26)), isTrue);
    expect(path.contains(const Offset(50, 0.5)), isTrue);
  });

  test('바텀시트(topOnly)는 위 두 모서리만 둥글다', () {
    const sheet = DepthBorder(radius: 24, topOnly: true);
    final path = sheet.getOuterPath(rect);
    expect(path.contains(const Offset(0.5, 0.5)), isFalse);
    expect(path.contains(const Offset(0.5, 51.5)), isTrue);
    expect(path.contains(const Offset(99.5, 51.5)), isTrue);
  });

  group('보간(눌림 움직임)', () {
    test('눌리는 쪽으로 가는 보간은 즉시 눌림이다', () {
      expect(ShapeBorder.lerp(raised, pressed, 0.1), pressed);
      expect(ShapeBorder.lerp(raised, pressed, 0.01), pressed);
    });

    test('되돌아오는 보간은 면 위치와 두께를 연속으로 옮긴다', () {
      final mid = ShapeBorder.lerp(pressed, raised, 0.5)! as DepthBorder;
      expect(mid.press, closeTo(0.5, 1e-9));
      expect(mid.pressed, isFalse);
      // 두께 2의 절반씩: 위 1, 아래 1(+ 테두리 1).
      final insets = mid.dimensions as EdgeInsets;
      expect(insets.top, closeTo(2, 1e-9));
      expect(insets.bottom, closeTo(2, 1e-9));
    });

    test('보간 끝점은 양쪽 모양 그대로다', () {
      expect(ShapeBorder.lerp(pressed, raised, 0), pressed);
      expect(ShapeBorder.lerp(pressed, raised, 1), raised);
    });
  });

  test('버튼이 side만 바꿔도 두께·눌림·모서리는 유지된다', () {
    final copied = pressed.copyWith(
      side: const BorderSide(color: AppPalette.primary, width: 2),
    );
    expect(copied.side.color, AppPalette.primary);
    expect(copied.depth, 2);
    expect(copied.pressed, isTrue);
    expect(copied.radius, 12);
  });

  test('scale은 테두리·모서리·두께를 함께 키운다', () {
    final scaled = raised.scale(2) as DepthBorder;
    expect(scaled.side.width, 2);
    expect(scaled.radius, 24);
    expect(scaled.depth, 4);
    expect(scaled.pressed, isFalse);
  });

  test('같은 인자면 같다(테마 상태별 모양 비교에 쓴다)', () {
    expect(const DepthBorder(depth: 3, pressed: true), const DepthBorder(depth: 3, pressed: true));
    expect(const DepthBorder(depth: 3), isNot(const DepthBorder(depth: 3, pressed: true)));
  });

  test('실선·점선·바텀시트·눌림 모두 예외 없이 그려진다', () {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    for (final border in [
      raised,
      pressed,
      const DepthBorder(side: side, dashed: true),
      const DepthBorder(side: side, radius: 24, topOnly: true),
      const DepthBorder(depth: 3),
    ]) {
      border.paint(canvas, rect);
    }
    recorder.endRecording().dispose();
  });
}
