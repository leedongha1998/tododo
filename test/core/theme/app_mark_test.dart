import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:todododo/core/theme/app_mark.dart';

void main() {
  test('16×16이고 허용된 색 인덱스만 쓴다', () {
    expect(AppMark.rows, hasLength(AppMark.size));
    for (final row in AppMark.rows) {
      expect(row, hasLength(AppMark.size), reason: '"$row"');
      expect(RegExp(r'^[.sak]+$').hasMatch(row), isTrue, reason: '"$row"');
    }
  });

  test('네 모서리 2×2가 비어 있다', () {
    for (final (cx, cy) in [(0, 0), (14, 0), (0, 14), (14, 14)]) {
      for (var dy = 0; dy < 2; dy++) {
        for (var dx = 0; dx < 2; dx++) {
          expect(AppMark.rows[cy + dy][cx + dx], '.', reason: '(${cx + dx}, ${cy + dy})');
        }
      }
    }
  });

  test('켜진 셀의 네 꼭짓점이 모두 적응형 안전 원(반지름 33dp) 안에 있다', () {
    // 108dp 캔버스 가운데 48dp에 16셀 → 셀 3dp, 중심은 (8, 8)셀.
    const cellDp = 3.0;
    for (var y = 0; y < AppMark.size; y++) {
      for (var x = 0; x < AppMark.size; x++) {
        if (AppMark.rows[y][x] == '.') continue;
        for (final cornerX in [x, x + 1]) {
          for (final cornerY in [y, y + 1]) {
            final distance = sqrt(pow(cornerX - 8, 2) + pow(cornerY - 8, 2)) * cellDp;
            expect(distance, lessThanOrEqualTo(33), reason: '($x, $y)');
          }
        }
      }
    }
  });

  test('칸·체크·그림자 세 요소가 모두 있고, 단색 아이콘에는 그림자가 없다', () {
    final all = AppMark.rows.join();
    expect(all.contains('s'), isTrue);
    expect(all.contains('a'), isTrue);
    expect(all.contains('k'), isTrue);

    final mono = AppMark.monochromeRows.join();
    expect(mono.contains('k'), isFalse);
    expect(mono.contains('s'), isTrue);
    expect(mono.contains('a'), isTrue);
  });
}
