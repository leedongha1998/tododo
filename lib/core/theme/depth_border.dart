import 'dart:math' as math;

import 'package:flutter/painting.dart';

import 'app_palette.dart';

/// redesign 모양 규칙(`docs/specs/redesign/design.md` 4.1·4.2·5.2)을 한 곳에서 그린다.
///
/// - 둥근 모서리([radius]).
/// - 흐린 그림자 대신 **아래 두께**: 떠 있는 요소는 바닥에 [depth]만큼 [depthColor] 띠가 보인다.
/// - **눌림**: 면이 [depth]만큼 내려와 띠를 덮는다. 두께는 바깥 상자 **안쪽**에 그리므로 눌려도 바깥 크기가
///   그대로다 — 레이아웃이 흔들리지 않는다. [dimensions]가 면의 위치를 따라가므로
///   `Container(decoration: ShapeDecoration(...))` 안의 내용도 함께 내려간다.
/// - 테두리([side])는 면 둘레에 안쪽으로 그린다. [dashed]면 둥근 사각 경로를 따라 일정 간격으로 끊는다.
/// - [topOnly]: 바텀시트용. 위 두 모서리만 둥글고 테두리도 위쪽만 그린다(두께 없음).
///
/// 보간은 비대칭이다: **눌리는 쪽으로 가는 보간은 즉시**(t > 0이면 눌림 상태), 되돌아오는 보간만 두께·면 위치를
/// 연속으로 옮긴다. design 4.2의 "누를 때 0ms, 뗄 때 120ms"를 Material의 모양 애니메이션 안에서 낸다.
class DepthBorder extends OutlinedBorder {
  const DepthBorder({
    super.side = BorderSide.none,
    this.radius = 12,
    this.depth = 0,
    this.depthColor = AppPalette.ink,
    bool pressed = false,
    this.dashed = false,
    this.topOnly = false,
  }) : press = pressed ? 1.0 : 0.0;

  const DepthBorder._raw({
    required super.side,
    required this.radius,
    required this.depth,
    required this.depthColor,
    required this.press,
    required this.dashed,
    required this.topOnly,
  });

  /// 모서리 반지름. 상자가 작으면 짧은 변의 절반에서 멈춘다.
  final double radius;

  /// 아래 두께(0이면 납작).
  final double depth;

  /// 아래 두께 색. 누르는 버튼은 ink, 떠 있는 카드는 edge.
  final Color depthColor;

  /// 눌린 정도. 0 = 안 눌림, 1 = 눌림. 그 사이 값은 되돌아오는 보간 중에만 나온다.
  final double press;

  /// 테두리를 점선으로.
  final bool dashed;

  /// 위 두 모서리만 둥글고 위 테두리만 그린다(바텀시트).
  final bool topOnly;

  /// 눌림 상태.
  bool get pressed => press >= 1;

  double get _width => side.style == BorderStyle.none ? 0 : side.width;

  /// 면이 위에서 내려온 거리.
  double get _faceOffset => topOnly ? 0 : depth * press;

  /// 바닥에 보이는 두께.
  double get _band => topOnly ? 0 : depth * (1 - press);

  @override
  EdgeInsetsGeometry get dimensions {
    if (topOnly) return EdgeInsets.only(top: _width);
    return EdgeInsets.fromLTRB(_width, _width + _faceOffset, _width, _width + _band);
  }

  /// 면 + 바닥 두께가 차지하는 자리(눌리면 위가 비어 있다).
  Rect _outerRect(Rect rect) =>
      Rect.fromLTRB(rect.left, rect.top + _faceOffset, rect.right, rect.bottom);

  /// 면이 차지하는 자리.
  Rect _faceRect(Rect rect) {
    final top = rect.top + _faceOffset;
    return Rect.fromLTRB(rect.left, top, rect.right, math.max(top, rect.bottom - _band));
  }

  RRect _rounded(Rect rect, {double inset = 0}) {
    final r = math.max(0.0, math.min(radius, rect.shortestSide / 2) - inset);
    final corner = Radius.circular(r);
    if (topOnly) {
      return RRect.fromRectAndCorners(rect, topLeft: corner, topRight: corner);
    }
    return RRect.fromRectAndRadius(rect, corner);
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    return Path()..addRRect(_rounded(_outerRect(rect)));
  }

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) {
    final inner = dimensions.resolve(textDirection).deflateRect(rect);
    return Path()..addRRect(_rounded(inner, inset: _width));
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    // 바닥 두께: 바깥 경로에서 면을 뺀 아래 초승달 모양.
    if (_band > 0) {
      final band = Path.combine(
        PathOperation.difference,
        getOuterPath(rect),
        Path()..addRRect(_rounded(_faceRect(rect))),
      );
      canvas.drawPath(band, Paint()..color = depthColor);
    }

    if (_width <= 0) return;

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _width
      ..color = side.color;
    final outline = topOnly ? _topEdgePath(rect) : _faceOutlinePath(rect);

    if (dashed) {
      _paintDashed(canvas, outline, stroke);
    } else {
      canvas.drawPath(outline, stroke);
    }
  }

  /// 면 둘레(선 굵기 절반만큼 안쪽 — 선이 바깥 상자를 넘지 않게).
  Path _faceOutlinePath(Rect rect) {
    final face = _faceRect(rect).deflate(_width / 2);
    return Path()..addRRect(_rounded(face));
  }

  /// 바텀시트의 위 테두리: 왼쪽 위 모서리 → 위 변 → 오른쪽 위 모서리.
  Path _topEdgePath(Rect rect) {
    final r = rect.deflate(_width / 2);
    final corner = math.max(0.0, math.min(radius, r.shortestSide / 2));
    return Path()
      ..moveTo(r.left, r.top + corner)
      ..arcToPoint(Offset(r.left + corner, r.top), radius: Radius.circular(corner))
      ..lineTo(r.right - corner, r.top)
      ..arcToPoint(Offset(r.right, r.top + corner), radius: Radius.circular(corner));
  }

  void _paintDashed(Canvas canvas, Path path, Paint paint) {
    final dash = _width * 3;
    final gap = _width * 2;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = math.min(distance + dash, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance += dash + gap;
      }
    }
  }

  @override
  DepthBorder copyWith({
    BorderSide? side,
    double? radius,
    double? depth,
    Color? depthColor,
    bool? pressed,
    bool? dashed,
    bool? topOnly,
  }) {
    return DepthBorder._raw(
      side: side ?? this.side,
      radius: radius ?? this.radius,
      depth: depth ?? this.depth,
      depthColor: depthColor ?? this.depthColor,
      press: pressed == null ? press : (pressed ? 1.0 : 0.0),
      dashed: dashed ?? this.dashed,
      topOnly: topOnly ?? this.topOnly,
    );
  }

  @override
  ShapeBorder scale(double t) {
    return DepthBorder._raw(
      side: side.scale(t),
      radius: radius * t,
      depth: depth * t,
      depthColor: depthColor,
      press: press,
      dashed: dashed,
      topOnly: topOnly,
    );
  }

  static double _lerpDouble(double a, double b, double t) => a + (b - a) * t;

  /// [a] → [b] 보간. 더 눌린 쪽으로 가면 즉시 [b], 아니면(되돌아옴·활성/비활성 전환) 연속 보간.
  static DepthBorder _lerp(DepthBorder a, DepthBorder b, double t) {
    if (t <= 0) return a;
    if (t >= 1) return b;
    if (b.press > a.press) return b;
    return DepthBorder._raw(
      side: BorderSide.lerp(a.side, b.side, t),
      radius: _lerpDouble(a.radius, b.radius, t),
      depth: _lerpDouble(a.depth, b.depth, t),
      depthColor: Color.lerp(a.depthColor, b.depthColor, t) ?? b.depthColor,
      press: _lerpDouble(a.press, b.press, t),
      dashed: t < 0.5 ? a.dashed : b.dashed,
      topOnly: t < 0.5 ? a.topOnly : b.topOnly,
    );
  }

  @override
  ShapeBorder? lerpFrom(ShapeBorder? a, double t) {
    if (a is DepthBorder) return _lerp(a, this, t);
    return super.lerpFrom(a, t);
  }

  @override
  ShapeBorder? lerpTo(ShapeBorder? b, double t) {
    if (b is DepthBorder) return _lerp(this, b, t);
    return super.lerpTo(b, t);
  }

  @override
  bool operator ==(Object other) {
    return other is DepthBorder &&
        other.side == side &&
        other.radius == radius &&
        other.depth == depth &&
        other.depthColor == depthColor &&
        other.press == press &&
        other.dashed == dashed &&
        other.topOnly == topOnly;
  }

  @override
  int get hashCode => Object.hash(side, radius, depth, depthColor, press, dashed, topOnly);

  @override
  String toString() =>
      'DepthBorder(side: $side, radius: $radius, depth: $depth, press: $press, '
      'dashed: $dashed, topOnly: $topOnly)';
}
