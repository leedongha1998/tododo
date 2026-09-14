import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'retro_palette.dart';

/// 레트로 모양 규칙(design.md 1.4)을 한 곳에서 그린다.
///
/// - 둥근 모서리 대신 계단 모서리: 네 모서리에서 테두리 두께만 한 정사각형 한 칸을 비운다.
/// - 흐린 그림자 대신 바닥 두께: 떠 있는 요소는 아래·오른쪽 테두리를 [depth]만큼 더 두껍게.
///   눌리면 두께가 위·왼쪽으로 옮겨 가 안으로 꺼진 모양이 된다.
/// - 두께는 바깥 크기 안쪽에 그리므로 레이아웃 크기가 변하지 않는다.
///
/// `getOuterPath`가 계단 다각형이라 Material의 클리핑·겹침 색도 계단 모서리를 따른다.
class PixelBorder extends OutlinedBorder {
  const PixelBorder({
    super.side = const BorderSide(color: RetroPalette.ink, width: 2),
    this.depth = 0,
    this.pressed = false,
    this.dashed = false,
    this.innerColor,
    this.topOnly = false,
  });

  /// 바닥 두께(0 또는 2dp).
  final double depth;

  /// 눌림 변형. 바닥 두께가 위·왼쪽으로 간다.
  final bool pressed;

  /// 2dp 켜짐·2dp 꺼짐 점선.
  final bool dashed;

  /// 안쪽 이중선 색. 대화상자·명판의 "창" 테두리(바깥 ink + 안쪽 surface)에 쓴다.
  final Color? innerColor;

  /// 위쪽 선과 위 두 모서리 계단만 그린다(바텀시트).
  final bool topOnly;

  double get _width => side.style == BorderStyle.none ? 0 : side.width;

  double get _innerWidth => innerColor == null ? 0 : _width;

  EdgeInsets _ringInsets(double base) {
    if (topOnly) return EdgeInsets.only(top: base);
    return pressed
        ? EdgeInsets.fromLTRB(base + depth, base + depth, base, base)
        : EdgeInsets.fromLTRB(base, base, base + depth, base + depth);
  }

  @override
  EdgeInsetsGeometry get dimensions => _ringInsets(_width + _innerWidth);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) {
    return Path()..addRect(_ringInsets(_width + _innerWidth).deflateRect(rect));
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    final notch = math.min(_width, rect.shortestSide / 2);
    if (notch <= 0) return Path()..addRect(rect);

    final l = rect.left;
    final t = rect.top;
    final r = rect.right;
    final b = rect.bottom;

    if (topOnly) {
      return Path()
        ..moveTo(l, t + notch)
        ..lineTo(l + notch, t + notch)
        ..lineTo(l + notch, t)
        ..lineTo(r - notch, t)
        ..lineTo(r - notch, t + notch)
        ..lineTo(r, t + notch)
        ..lineTo(r, b)
        ..lineTo(l, b)
        ..close();
    }

    return Path()
      ..moveTo(l + notch, t)
      ..lineTo(r - notch, t)
      ..lineTo(r - notch, t + notch)
      ..lineTo(r, t + notch)
      ..lineTo(r, b - notch)
      ..lineTo(r - notch, b - notch)
      ..lineTo(r - notch, b)
      ..lineTo(l + notch, b)
      ..lineTo(l + notch, b - notch)
      ..lineTo(l, b - notch)
      ..lineTo(l, t + notch)
      ..lineTo(l + notch, t + notch)
      ..close();
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (_width <= 0) return;

    final ringInner = _ringInsets(_width).deflateRect(rect);
    final ring = Path.combine(
      PathOperation.difference,
      getOuterPath(rect),
      Path()..addRect(ringInner),
    );
    final paint = Paint()
      ..color = side.color
      ..isAntiAlias = false;

    if (dashed) {
      _paintDashed(canvas, rect, ringInner, ring, paint);
    } else {
      canvas.drawPath(ring, paint);
    }

    final inner = innerColor;
    if (inner != null && !topOnly) {
      final innerRing = Path.combine(
        PathOperation.difference,
        Path()..addRect(ringInner),
        Path()..addRect(ringInner.deflate(_innerWidth)),
      );
      canvas.drawPath(
        innerRing,
        Paint()
          ..color = inner
          ..isAntiAlias = false,
      );
    }
  }

  /// 두께 한 칸 켜짐·한 칸 꺼짐. 위아래 변은 세로 칸, 좌우 변은 가로 칸으로 끊는다.
  void _paintDashed(Canvas canvas, Rect rect, Rect ringInner, Path ring, Paint paint) {
    final cell = _width;

    canvas.save();
    canvas.clipPath(ring);
    canvas.clipRect(Rect.fromLTRB(rect.left, rect.top, rect.right, ringInner.top));
    for (var x = rect.left; x < rect.right; x += cell * 2) {
      canvas.drawRect(Rect.fromLTWH(x, rect.top, cell, rect.height), paint);
    }
    canvas.restore();

    canvas.save();
    canvas.clipPath(ring);
    canvas.clipRect(Rect.fromLTRB(rect.left, ringInner.bottom, rect.right, rect.bottom));
    for (var x = rect.left; x < rect.right; x += cell * 2) {
      canvas.drawRect(Rect.fromLTWH(x, rect.top, cell, rect.height), paint);
    }
    canvas.restore();

    canvas.save();
    canvas.clipPath(ring);
    canvas.clipRect(Rect.fromLTRB(rect.left, ringInner.top, rect.right, ringInner.bottom));
    for (var y = ringInner.top; y < ringInner.bottom; y += cell * 2) {
      canvas.drawRect(Rect.fromLTWH(rect.left, y, rect.width, cell), paint);
    }
    canvas.restore();
  }

  @override
  PixelBorder copyWith({
    BorderSide? side,
    double? depth,
    bool? pressed,
    bool? dashed,
    Color? innerColor,
    bool? topOnly,
  }) {
    return PixelBorder(
      side: side ?? this.side,
      depth: depth ?? this.depth,
      pressed: pressed ?? this.pressed,
      dashed: dashed ?? this.dashed,
      innerColor: innerColor ?? this.innerColor,
      topOnly: topOnly ?? this.topOnly,
    );
  }

  @override
  ShapeBorder scale(double t) {
    return copyWith(side: side.scale(t), depth: depth * t);
  }

  // 모양 전환도 연속 보간 대신 한 번에 바뀐다(계단식 움직임 규칙).
  @override
  ShapeBorder? lerpFrom(ShapeBorder? a, double t) {
    if (a is PixelBorder) return t < 0.5 ? a : this;
    return super.lerpFrom(a, t);
  }

  @override
  ShapeBorder? lerpTo(ShapeBorder? b, double t) {
    if (b is PixelBorder) return t < 0.5 ? this : b;
    return super.lerpTo(b, t);
  }

  @override
  bool operator ==(Object other) {
    return other is PixelBorder &&
        other.side == side &&
        other.depth == depth &&
        other.pressed == pressed &&
        other.dashed == dashed &&
        other.innerColor == innerColor &&
        other.topOnly == topOnly;
  }

  @override
  int get hashCode => Object.hash(side, depth, pressed, dashed, innerColor, topOnly);
}
