import 'package:flutter/painting.dart';

import 'app_palette.dart';

/// 앱 마크 — 런처·스토어·알림·테마 아이콘과 로그인 화면이 같은 그림을 쓴다(redesign design 7.1).
///
/// **체크 두 개가 맞붙는다**(2026-11-12 오너 — "체크 표시 두 개가 배틀하고 있는 느낌"). 앰버 체크와
/// 흰 체크가 서로를 향해 그어져 한가운데에서 X로 교차한다 — 칼 두 자루를 교차시킨 대결 기호를
/// 체크로 바꾼 것이고, 두 색이 곧 두 사람이다. 앞(앰버)이 지나는 자리에서 뒤(흰)를 끊어 두 획이
/// 한 덩어리로 뭉치지 않고 **겹쳐 지나가는** 것으로 읽힌다.
///
/// 전에는 체크 칸 하나와 체크 하나였다. 투두는 읽혔지만 대결이 어디에도 없었다 — 두 번째 체크가
/// 그 자리를 메운다.
///
/// 캐릭터·얼굴·원형 볼 같은 특정 게임 도형은 없다(IP 가드, design 4.3). 적응형 아이콘(108dp)에서
/// 가운데 44dp 상자에 그리면 모든 픽셀이 안전 원(반지름 33dp) 안에 든다 — 테스트로 고정.
class AppMark {
  AppMark._();

  // ── 벡터 마크(redesign design 7.1) ──────────────────────────────────────────────────────────
  //
  // 24×24 단위(u) 격자 위의 그림. 로그인·런처·스토어·알림·테마 아이콘이 [paint] 하나를 함께 쓴다.
  // - 두 체크: 꺾은선 [frontPoints](앰버)와 그것을 세로축으로 뒤집은 [backPoints](흰색),
  //   굵기 [checkStroke], 둥근 끝·꺾임. 두 긴 획이 [crossPoint]에서 직각으로 만난다.
  // - 끊긴 자리: 앞 체크 몸통 둘레 [cutGap]만큼을 뒤 체크 층에서 지운다 — 앞이 위로 지나간다.
  // - 두께: 두 체크를 아래로 [shadowOffset] 옮긴 같은 모양을 ink로 먼저 깐다(버튼 두께와 같은 언어).
  //   끊긴 자리는 앞 체크 몸통(체크 + 그 두께) 둘레로 내서 두께가 간격을 메우지 않게 한다.
  // - 단색(테마 아이콘·알림): 두께 없이 두 체크만, 끊긴 간격은 남긴다 — 한 색이라 간격이 없으면
  //   교차가 사라지고 그냥 X 한 덩어리가 된다.

  /// 격자 한 변(u).
  static const grid = 24.0;

  /// 앞 체크(앰버). 왼쪽 아래에서 오른쪽 위로 긋는다.
  static const frontPoints = [Offset(2.4, 12.6), Offset(7.4, 17.6), Offset(20.6, 4.4)];

  /// 뒤 체크(흰색). [frontPoints]를 세로축(x = 12)으로 뒤집은 모양이다.
  static const backPoints = [Offset(21.6, 12.6), Offset(16.6, 17.6), Offset(3.4, 4.4)];

  static const checkStroke = 3.4;

  /// 앞 체크 둘레에서 뒤 체크를 지우는 폭(앞 체크 굵기 바깥으로).
  static const cutGap = 1.0;

  /// 아래 두께(ink) 오프셋.
  static const shadowOffset = 1.5;

  /// 두 긴 획이 만나는 점. 두 획이 서로 직각(기울기 +1과 -1)이라 교차는 한 곳뿐이다.
  static const crossPoint = Offset(12, 13);

  /// 끊긴 자리를 내는 구간 — [crossPoint] 양옆으로 앞 체크 반 굵기 + [cutGap]. 짧게 끊어야
  /// 지우는 띠가 뒤 체크의 **짧은 획**(앞 긴 획과 나란하다)까지 갉아 먹지 않는다.
  static final Offset _cutReach = () {
    final arm = frontPoints[2] - frontPoints[1];
    return arm / arm.distance * (checkStroke / 2 + cutGap);
  }();

  static Offset get cutFrom => crossPoint - _cutReach;
  static Offset get cutTo => crossPoint + _cutReach;

  /// [box](격자 24u가 들어갈 정사각형)에 마크를 그린다. 배경은 그리지 않는다(호출자 몫).
  ///
  /// [monochrome]이면 두께 없이 두 체크를 [monoColor](기본 surface) 한 색으로 그린다.
  static void paint(Canvas canvas, Rect box, {bool monochrome = false, Color? monoColor}) {
    final unit = box.shortestSide / grid;
    final mono = monoColor ?? AppPalette.surface;
    // **색 마크는 끊지 않는다.** 앞 체크의 ink 두께가 뒤 체크 위로 지나가며 경계를 만들어 주므로
    // (앞 획의 그림자가 뒤 획에 드리운 것처럼) 파란 간격까지 내면 뒤 체크가 두 동강 난 조각으로
    // 보인다. 단색에서는 색이 하나라 그 경계가 없어 간격이 없으면 그냥 X 한 덩어리가 된다.

    canvas.save();
    canvas.translate(box.left, box.top);
    canvas.scale(unit);

    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = checkStroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // 뒤 체크는 자기 층에 그리고 끊긴 자리를 그 층에서만 지운다(배경은 지워지지 않는다).
    canvas.saveLayer(null, Paint());
    if (!monochrome) {
      canvas.drawPath(
        _path(backPoints).shift(const Offset(0, shadowOffset)),
        strokePaint..color = AppPalette.ink,
      );
    }
    canvas.drawPath(_path(backPoints), strokePaint..color = monochrome ? mono : AppPalette.surface);
    // 끝을 둥글게 두면 지우는 띠가 교차점에서 더 멀리까지 번진다. 자른 끝(butt)이라 간격의
    // 가장자리가 앞 체크와 나란한 직선이 된다.
    if (monochrome) {
      canvas.drawLine(
        cutFrom,
        cutTo,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = checkStroke + cutGap * 2
          ..strokeCap = StrokeCap.butt
          ..blendMode = BlendMode.clear,
      );
    }
    canvas.restore();

    if (!monochrome) {
      canvas.drawPath(
        _path(frontPoints).shift(const Offset(0, shadowOffset)),
        strokePaint..color = AppPalette.ink,
      );
    }
    canvas.drawPath(_path(frontPoints), strokePaint..color = monochrome ? mono : AppPalette.amber);
    canvas.restore();
  }

  static Path _path(List<Offset> points) {
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    return path;
  }
}
