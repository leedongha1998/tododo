import 'package:flutter/painting.dart';

import 'app_palette.dart';

/// 앱 마크 — 런처·스토어·알림·테마 아이콘과 로그인 화면이 같은 그림을 쓴다(redesign design 7.1).
///
/// 둥근 체크 칸(할 일)을 굵은 앰버 체크가 오른쪽 위로 뚫고 나가고("먼저 해치운다"), 아래로 ink 두께가
/// 붙는다(버튼 두께와 같은 언어). 캐릭터·얼굴·원형 볼 같은 특정 게임 도형은 없다.
/// 적응형 아이콘(108dp)에서 가운데 44dp 상자에 그리면 모든 픽셀이 안전 원(반지름 33dp) 안에 든다 — 테스트로 고정.
class AppMark {
  AppMark._();

  // ── 벡터 마크(redesign design 7.1) ──────────────────────────────────────────────────────────
  //
  // 24×24 단위(u) 격자 위의 그림. 로그인·런처·스토어·알림·테마 아이콘이 [paint] 하나를 함께 쓴다.
  // - 칸: 둥근 사각 [boxRect], 모서리 [boxRadius], 선 굵기 [boxStroke] — surface(흰색).
  // - 체크: 꺾은선 [checkPoints], 굵기 [checkStroke], 둥근 끝·꺾임 — amber.
  // - 뚫린 자리: 체크가 칸 선을 지나는 곳(오른쪽 위)에서 칸 선을 체크 둘레 [cutGap]만큼 지운다 — 체크가
  //   칸을 "뚫고" 오른쪽 위로 나간다.
  // - 두께: 칸·체크를 아래로 [shadowOffset] 옮긴 같은 모양을 ink로 먼저 깐다(버튼 두께와 같은 언어).
  //   뚫린 자리는 체크 몸통(체크 + 그 두께) 둘레로 내서 체크 두께가 간격을 메우지 않게 한다.
  // - 단색(테마 아이콘·알림): 두께 없이 칸 + 체크만, 뚫린 간격은 남긴다(한 덩어리로 뭉개지지 않게).
  // 얼굴·캐릭터·특정 게임 도형 없음(체크와 네모뿐).

  /// 격자 한 변(u).
  static const grid = 24.0;

  static const boxRect = Rect.fromLTRB(2, 6, 18, 22);
  static const boxRadius = 3.5;
  static const boxStroke = 2.5;

  static const checkPoints = [Offset(5.5, 13.5), Offset(10, 18), Offset(21.5, 4)];
  static const checkStroke = 4.0;

  /// 체크 둘레에서 칸 선을 지우는 폭(체크 굵기 바깥으로).
  static const cutGap = 1.5;

  /// 아래 두께(ink) 오프셋.
  static const shadowOffset = 1.5;

  /// 뚫린 자리를 내는 구간 — 체크의 긴 획 가운데부터 끝까지. 긴 획 전체로 지우면 아래 꺾임(10, 18)의 둥근
  /// 끝이 칸 아랫선까지 갉아 먹는다. 칸 선과 만나는 곳(오른쪽 위)만 지운다.
  static final cutFrom = Offset.lerp(checkPoints[1], checkPoints[2], 0.5)!;

  /// [box](격자 24u가 들어갈 정사각형)에 마크를 그린다. 배경은 그리지 않는다(호출자 몫).
  ///
  /// [monochrome]이면 두께 없이 칸 + 체크를 [monoColor](기본 surface) 한 색으로 그린다.
  static void paint(Canvas canvas, Rect box, {bool monochrome = false, Color? monoColor}) {
    final unit = box.shortestSide / grid;
    final mono = monoColor ?? AppPalette.surface;
    // 체크 몸통(체크 + 그 아래 두께)이 차지하는 세로 오프셋들. 뚫린 자리는 몸통 전체 둘레로 낸다 —
    // 체크 면만 둘레로 지우면 체크 두께가 간격을 메워 칸과 붙어 보인다.
    final checkOffsets = monochrome ? const [0.0] : const [0.0, shadowOffset];

    canvas.save();
    canvas.translate(box.left, box.top);
    canvas.scale(unit);

    // 칸(+ 칸 두께)은 자기 층에 그리고 뚫린 자리를 그 층에서만 지운다(배경은 지워지지 않는다).
    canvas.saveLayer(null, Paint());
    final boxShape = RRect.fromRectAndRadius(boxRect, const Radius.circular(boxRadius));
    final boxPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = boxStroke;
    if (!monochrome) {
      canvas.drawRRect(boxShape.shift(const Offset(0, shadowOffset)), boxPaint..color = AppPalette.ink);
    }
    canvas.drawRRect(boxShape, boxPaint..color = monochrome ? mono : AppPalette.surface);
    final cutPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = checkStroke + cutGap * 2
      ..strokeCap = StrokeCap.round
      ..blendMode = BlendMode.clear;
    for (final dy in checkOffsets) {
      canvas.drawLine(cutFrom.translate(0, dy), checkPoints[2].translate(0, dy), cutPaint);
    }
    canvas.restore();

    final checkPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = checkStroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    if (!monochrome) {
      canvas.drawPath(_checkPath.shift(const Offset(0, shadowOffset)), checkPaint..color = AppPalette.ink);
    }
    canvas.drawPath(_checkPath, checkPaint..color = monochrome ? mono : AppPalette.amber);
    canvas.restore();
  }

  static Path get _checkPath => Path()
    ..moveTo(checkPoints[0].dx, checkPoints[0].dy)
    ..lineTo(checkPoints[1].dx, checkPoints[1].dy)
    ..lineTo(checkPoints[2].dx, checkPoints[2].dy);
}
