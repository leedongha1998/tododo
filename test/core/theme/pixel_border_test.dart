import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todododo/core/theme/pixel_border.dart';
import 'package:todododo/core/theme/retro_palette.dart';

void main() {
  const rect = Rect.fromLTWH(0, 0, 100, 40);

  test('네 모서리에서 테두리 두께만 한 칸을 비운 계단 모서리다', () {
    final path = const PixelBorder().getOuterPath(rect);

    // 모서리 2×2 칸은 비어 있다.
    expect(path.contains(const Offset(0.5, 0.5)), isFalse);
    expect(path.contains(const Offset(99.5, 0.5)), isFalse);
    expect(path.contains(const Offset(0.5, 39.5)), isFalse);
    expect(path.contains(const Offset(99.5, 39.5)), isFalse);
    // 모서리 바로 옆은 채워져 있다.
    expect(path.contains(const Offset(2.5, 0.5)), isTrue);
    expect(path.contains(const Offset(0.5, 2.5)), isTrue);
    expect(path.contains(const Offset(50, 20)), isTrue);
  });

  test('바닥 두께는 아래·오른쪽에, 눌리면 위·왼쪽에 붙는다', () {
    const raised = PixelBorder(depth: 2);
    expect(raised.dimensions, const EdgeInsets.fromLTRB(2, 2, 4, 4));

    const pressed = PixelBorder(depth: 2, pressed: true);
    expect(pressed.dimensions, const EdgeInsets.fromLTRB(4, 4, 2, 2));
  });

  test('안쪽 이중선이 있으면 두께가 두 배다', () {
    const window = PixelBorder(innerColor: RetroPalette.surface);
    expect(window.dimensions, const EdgeInsets.all(4));
  });

  test('버튼이 side만 바꿔도 바닥 두께·눌림 속성은 유지된다', () {
    const border = PixelBorder(depth: 2, pressed: true);
    final copied = border.copyWith(side: const BorderSide(color: RetroPalette.danger, width: 2));

    expect(copied.side.color, RetroPalette.danger);
    expect(copied.depth, 2);
    expect(copied.pressed, isTrue);
  });

  test('테두리가 없으면 직사각형이다', () {
    final path = const PixelBorder(side: BorderSide.none).getOuterPath(rect);
    expect(path.contains(const Offset(0.5, 0.5)), isTrue);
  });
}
