import 'package:flutter/material.dart';

import '../theme/pixel_border.dart';
import '../theme/retro_palette.dart';
import '../theme/retro_text.dart';

/// 태그 한 개의 모양. 상태 칩·결과 라벨이 서버 값을 이 모양으로 바꾸는 매핑의 결과다
/// (승패를 계산하지 않고 모양만 고른다).
@immutable
class PixelTagStyle {
  const PixelTagStyle({
    required this.fill,
    required this.textColor,
    this.borderColor,
    this.dashed = false,
    this.raised = false,
  });

  final Color fill;
  final Color textColor;

  /// null이면 테두리 없음.
  final Color? borderColor;
  final bool dashed;

  /// 바닥 두께. 가장 강한 결과(승)에만 쓴다.
  final bool raised;

  @override
  bool operator ==(Object other) {
    return other is PixelTagStyle &&
        other.fill == fill &&
        other.textColor == textColor &&
        other.borderColor == borderColor &&
        other.dashed == dashed &&
        other.raised == raised;
  }

  @override
  int get hashCode => Object.hash(fill, textColor, borderColor, dashed, raised);
}

enum PixelTagSize { small, large }

/// 짧은 글자 한 덩어리의 기본 조각. 계단 모서리 2dp, 좌우 8.
/// small: 최소 높이 24·글자 12 / large: 최소 높이 40·글자 24.
/// 높이를 고정하지 않고 최소값만 두어 글자 크기 1.3배에서도 잘리지 않는다.
class PixelTag extends StatelessWidget {
  const PixelTag({
    super.key,
    required this.label,
    required this.style,
    this.size = PixelTagSize.small,
    this.leading,
  });

  final String label;
  final PixelTagStyle style;
  final PixelTagSize size;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final isLarge = size == PixelTagSize.large;
    final border = style.borderColor;

    return Container(
      constraints: BoxConstraints(minHeight: isLarge ? 40 : 24),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: ShapeDecoration(
        color: style.fill,
        shape: PixelBorder(
          side: border == null ? BorderSide.none : BorderSide(color: border, width: 2),
          dashed: style.dashed,
          depth: style.raised ? 2 : 0,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 4)],
          Text(
            label,
            style: RetroText.pixel(isLarge ? RetroText.grid * 2 : RetroText.grid, color: style.textColor),
          ),
        ],
      ),
    );
  }
}

/// 중립 태그(기간 칸 등).
const neutralPixelTagStyle = PixelTagStyle(
  fill: RetroPalette.sunken,
  textColor: RetroPalette.ink,
  borderColor: RetroPalette.ink,
);
