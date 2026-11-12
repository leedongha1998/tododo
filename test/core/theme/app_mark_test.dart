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

    testWidgets('색 마크에는 뒤 체크(surface)·앞 체크(amber)·두께(ink)가 모두 있다', (tester) async {
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

    testWidgets('두 체크가 한가운데에서 교차하고 끝과 꺾임은 모두 남는다', (tester) async {
      const pxPerDp = 4.0;
      for (final monochrome in [false, true]) {
        final (:bytes, :side) = await renderAdaptive(tester, monochrome: monochrome);
        bool paintedAt(Offset u) {
          final p = gridToPx(u, pxPerDp);
          return alphaAt(bytes, side, p.dx.floor(), p.dy.floor()) > 0;
        }

        // 앞 체크는 교차점에서 끊기지 않는다 — 위로 지나가는 쪽이다.
        expect(paintedAt(AppMark.crossPoint), isTrue, reason: 'cross, mono=$monochrome');
        // 두 체크의 네 끝과 두 꺾임이 모두 남아 있다 — 지우는 띠가 교차점 밖을 갉아 먹지 않는다.
        for (final points in [AppMark.frontPoints, AppMark.backPoints]) {
          for (final point in points) {
            expect(paintedAt(point), isTrue, reason: '$point, mono=$monochrome');
          }
        }
      }
    });

    // 단색(테마 아이콘·알림)은 색이 하나라 두 획이 만나는 자리를 색으로 구분할 수 없다.
    // 간격을 내지 않으면 교차가 사라지고 그냥 X 한 덩어리가 된다.
    testWidgets('단색에서만 교차 자리에 간격이 있다(색 마크는 ink 두께가 그 경계를 맡는다)',
        (tester) async {
      const pxPerDp = 4.0;
      // 뒤 체크의 긴 획을 따라 교차점에서 멀어지는 방향(왼쪽 위). 아래쪽으로 재면 앞 체크의
      // ink 두께가 걸려 "간격"과 "두께"를 구분할 수 없다.
      final backArm = AppMark.backPoints[2] - AppMark.backPoints[1];
      final away = backArm / backArm.distance;
      // 앞 체크 몸통 바깥, 지운 폭 안.
      final probe = AppMark.crossPoint + away * (AppMark.checkStroke / 2 + AppMark.cutGap / 2);

      for (final monochrome in [false, true]) {
        final (:bytes, :side) = await renderAdaptive(tester, monochrome: monochrome);
        final p = gridToPx(probe, pxPerDp);
        final painted = alphaAt(bytes, side, p.dx.floor(), p.dy.floor()) > 0;
        expect(painted, !monochrome, reason: 'mono=$monochrome');
      }
    });
  });
}
