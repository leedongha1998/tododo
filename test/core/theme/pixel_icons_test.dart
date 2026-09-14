import 'package:flutter_test/flutter_test.dart';
import 'package:todododo/core/theme/pixel_icons.dart';

void main() {
  for (final MapEntry(key: name, value: icon) in PixelIcons.all.entries) {
    group('$name 아이콘', () {
      test('12줄, 각 12자, #과 .만 쓴다', () {
        expect(icon.rows, hasLength(PixelIconData.gridSize));
        for (final row in icon.rows) {
          expect(row, hasLength(PixelIconData.gridSize), reason: '"$row"');
          expect(RegExp(r'^[#.]+$').hasMatch(row), isTrue, reason: '"$row"');
        }
      });

      test('바깥 1셀 여백이 비어 있고 그림이 있다', () {
        expect(icon.rows.first, '.' * 12);
        expect(icon.rows.last, '.' * 12);
        for (final row in icon.rows) {
          expect(row[0], '.');
          expect(row[11], '.');
        }
        expect(icon.rows.join().contains('#'), isTrue);
      });
    });
  }

  test('아이콘 모양이 서로 겹치지 않는다', () {
    final shapes = PixelIcons.all.values.map((icon) => icon.rows.join()).toSet();
    expect(shapes, hasLength(PixelIcons.all.length));
  });
}
