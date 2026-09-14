import 'package:flutter/widgets.dart';

import '../theme/pixel_icons.dart';

/// 픽셀 아이콘. `Icon`처럼 색·크기를 `IconTheme`에서 받으므로 탭바 선택 상태나 버튼 글자색이
/// 테마만으로 따라 바뀐다. 크기는 12 / 24 / 36 / 48dp(셀 1·2·3·4dp)만 쓴다.
class PixelIcon extends StatelessWidget {
  const PixelIcon(this.icon, {super.key, this.size, this.color, this.semanticLabel});

  final PixelIconData icon;
  final double? size;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final iconTheme = IconTheme.of(context);
    final side = size ?? iconTheme.size ?? 24;
    var paintColor = color ?? iconTheme.color ?? const Color(0xFF000000);
    final opacity = iconTheme.opacity;
    if (color == null && opacity != null && opacity < 1) {
      paintColor = paintColor.withValues(alpha: paintColor.a * opacity);
    }

    return Semantics(
      label: semanticLabel,
      excludeSemantics: semanticLabel == null,
      child: SizedBox(
        width: side,
        height: side,
        child: CustomPaint(painter: _PixelIconPainter(icon, paintColor)),
      ),
    );
  }
}

class _PixelIconPainter extends CustomPainter {
  _PixelIconPainter(this.icon, this.color);

  final PixelIconData icon;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / PixelIconData.gridSize;
    final paint = Paint()
      ..color = color
      ..isAntiAlias = false;
    for (var y = 0; y < icon.rows.length; y++) {
      final row = icon.rows[y];
      for (var x = 0; x < row.length; x++) {
        if (row.codeUnitAt(x) == 0x23) {
          canvas.drawRect(Rect.fromLTWH(x * cell, y * cell, cell, cell), paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_PixelIconPainter oldDelegate) {
    return oldDelegate.icon != icon || oldDelegate.color != color;
  }
}
