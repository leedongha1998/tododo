import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todododo/core/theme/app_mark.dart';
import 'package:todododo/core/theme/app_palette.dart';

/// 108dp 적응형 캔버스를 [pxPerDp]배로 그린 RGBA 바이트. 마크 상자 44dp를 가운데 둔다(design 7.1).
Future<({ByteData bytes, int side})> renderAdaptive(
  WidgetTester tester, {
  bool monochrome = false,
  double pxPerDp = 4,
}) async {
  final side = (108 * pxPerDp).round();
  final box = Rect.fromCenter(
    center: Offset(side / 2, side / 2),
    width: 44 * pxPerDp,
    height: 44 * pxPerDp,
  );
  final recorder = ui.PictureRecorder();
  AppMark.paint(Canvas(recorder), box, monochrome: monochrome);
  final picture = recorder.endRecording();
  final bytes = await tester.runAsync(() async {
    final image = await picture.toImage(side, side);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    return data!;
  });
  picture.dispose();
  return (bytes: bytes!, side: side);
}

int alphaAt(ByteData bytes, int side, int x, int y) => bytes.getUint8((y * side + x) * 4 + 3);

/// 격자(u) 좌표 → 108dp 캔버스 픽셀(마크 상자 44dp 가운데).
Offset gridToPx(Offset u, double pxPerDp) {
  final unit = 44 / AppMark.grid * pxPerDp;
  final origin = (108 - 44) / 2 * pxPerDp;
  return Offset(origin + u.dx * unit, origin + u.dy * unit);
}

void main() {
  group('벡터 마크', () {
    testWidgets('108dp 캔버스 가운데 44dp 상자에 그리면 모든 픽셀이 중심에서 33dp(안전 원) 안이다',
        (tester) async {
      for (final monochrome in [false, true]) {
        const pxPerDp = 4.0;
        final (:bytes, :side) = await renderAdaptive(tester, monochrome: monochrome);
        final center = side / 2;
        var painted = 0;
        var farthest = 0.0;
        for (var y = 0; y < side; y++) {
          for (var x = 0; x < side; x++) {
            if (alphaAt(bytes, side, x, y) == 0) continue;
            painted++;
            // 픽셀의 가장 먼 꼭짓점까지.
            final dx = max((x - center).abs(), (x + 1 - center).abs());
            final dy = max((y - center).abs(), (y + 1 - center).abs());
            farthest = max(farthest, sqrt(dx * dx + dy * dy) / pxPerDp);
          }
        }
        expect(painted, greaterThan(0));
        expect(farthest, lessThanOrEqualTo(33), reason: 'monochrome: $monochrome');
      }
    });

    testWidgets('단색 그리기에는 ink 두께가 없다(한 색뿐)', (tester) async {
      final (:bytes, :side) = await renderAdaptive(tester, monochrome: true);
      final colors = <int>{};
      for (var i = 0; i < side * side; i++) {
        final a = bytes.getUint8(i * 4 + 3);
        if (a < 255) continue; // 가장자리 안티에일리어싱은 섞인 색이라 뺀다.
        colors.add(bytes.getUint32(i * 4));
      }
      // surface(흰색) 하나뿐 — ink(두께)·amber(체크 색)가 없다.
      expect(colors, hasLength(1));
      final rgba = colors.single;
      expect(rgba >> 8 & 0xFFFFFF, AppPalette.surface.toARGB32() & 0xFFFFFF);
    });

    testWidgets('색 마크에는 칸(surface)·체크(amber)·두께(ink)가 모두 있다', (tester) async {
      final (:bytes, :side) = await renderAdaptive(tester);
      final colors = <int>{};
      for (var i = 0; i < side * side; i++) {
        if (bytes.getUint8(i * 4 + 3) < 255) continue;
        colors.add(bytes.getUint32(i * 4) >> 8);
      }
      for (final color in [AppPalette.surface, AppPalette.amber, AppPalette.ink]) {
        expect(colors, contains(color.toARGB32() & 0xFFFFFF));
      }
    });

    testWidgets('체크가 칸 오른쪽 선을 뚫는 자리에 간격이 있고, 칸 선의 나머지는 이어져 있다', (tester) async {
      const pxPerDp = 4.0;
      for (final monochrome in [false, true]) {
        final (:bytes, :side) = await renderAdaptive(tester, monochrome: monochrome);
        bool paintedAt(Offset u) {
          final p = gridToPx(u, pxPerDp);
          return alphaAt(bytes, side, p.dx.floor(), p.dy.floor()) > 0;
        }

        // 긴 획(10,18)→(21.5,4)이 칸 오른쪽 선 x = 18과 만나는 높이.
        final a = AppMark.checkPoints[1];
        final b = AppMark.checkPoints[2];
        final crossY = a.dy + (b.dy - a.dy) * (AppMark.boxRect.right - a.dx) / (b.dx - a.dx);
        // 체크 굵기가 오른쪽 선에서 차지하는 세로 반폭.
        final length = (b - a).distance;
        final checkHalf = AppMark.checkStroke / 2 * length / (b.dx - a.dx);
        final cutHalf = (AppMark.checkStroke / 2 + AppMark.cutGap) * length / (b.dx - a.dx);
        // 체크 몸통(색 마크는 체크 + 아래 두께) 바깥, 지운 폭 안: 칸 선이 있어야 할 자리가 비어 있다(간격 > 0).
        final bodyBottom = crossY + checkHalf + (monochrome ? 0 : AppMark.shadowOffset);
        final cutBottom = crossY + cutHalf + (monochrome ? 0 : AppMark.shadowOffset);
        expect(cutBottom - bodyBottom, greaterThan(0));
        final gapY = (bodyBottom + cutBottom) / 2;
        expect(paintedAt(Offset(AppMark.boxRect.right, gapY)), isFalse, reason: 'gap, mono=$monochrome');
        // 지운 폭 밖의 오른쪽 선·왼쪽 선·아랫선은 남아 있다.
        expect(paintedAt(Offset(AppMark.boxRect.right, cutBottom + 1.5)), isTrue);
        expect(paintedAt(Offset(AppMark.boxRect.left, 14)), isTrue);
        expect(paintedAt(Offset(10, AppMark.boxRect.bottom)), isTrue, reason: '아랫선은 꺾임에 갉아 먹히지 않는다');
      }
    });
  });

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
