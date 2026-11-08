import 'package:flutter/material.dart';

import '../theme/app_palette.dart';
import '../theme/depth_border.dart';

/// 태그 한 개의 모양. 상태 칩·결과 라벨이 서버 값을 이 모양으로 바꾸는 매핑의 결과다
/// (승패를 계산하지 않고 모양만 고른다).
@immutable
class AppTagStyle {
  const AppTagStyle({
    required this.fill,
    required this.textColor,
    this.borderColor,
    this.dashed = false,
    this.raised = false,
    this.icon,
  });

  final Color fill;
  final Color textColor;

  /// null이면 테두리 없음.
  final Color? borderColor;
  final bool dashed;

  /// 2dp ink 아래 두께. 가장 강한 결과(승)에만 쓴다.
  final bool raised;

  /// 글자 앞 16dp 아이콘(테두리색, 없으면 글자색). 색 말고도 구분돼야 하는 칩(미결)에만 쓴다.
  final IconData? icon;

  @override
  bool operator ==(Object other) {
    return other is AppTagStyle &&
        other.fill == fill &&
        other.textColor == textColor &&
        other.borderColor == borderColor &&
        other.dashed == dashed &&
        other.raised == raised &&
        other.icon == icon;
  }

  @override
  int get hashCode =>
      Object.hash(fill, textColor, borderColor, dashed, raised, icon);
}

enum AppTagSize { small, large }

/// 짧은 글자 한 덩어리의 기본 조각(design 5.2). 모서리 8, 테두리 1.5dp.
/// small: 최소 높이 28·좌우 10·`labelMedium` / large: 최소 높이 40·좌우 14·`titleMedium`.
/// 높이를 고정하지 않고 최소값만 두어 글자 크기 1.5배에서도 잘리지 않는다.
class AppTag extends StatelessWidget {
  const AppTag({
    super.key,
    required this.label,
    required this.style,
    this.size = AppTagSize.small,
    this.leading,
  });

  final String label;
  final AppTagStyle style;
  final AppTagSize size;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final isLarge = size == AppTagSize.large;
    final border = style.borderColor;
    final textTheme = Theme.of(context).textTheme;
    final icon = style.icon;

    return Container(
      constraints: BoxConstraints(minHeight: isLarge ? 40 : 28),
      padding: EdgeInsets.symmetric(horizontal: isLarge ? 14 : 10),
      decoration: ShapeDecoration(
        color: style.fill,
        shape: DepthBorder(
          side: border == null
              ? BorderSide.none
              : BorderSide(color: border, width: 1.5),
          radius: 8,
          dashed: style.dashed,
          depth: style.raised ? 2 : 0,
          depthColor: AppPalette.ink,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 4)],
          if (icon != null) ...[
            Icon(icon, size: 16, color: border ?? style.textColor),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: (isLarge ? textTheme.titleMedium : textTheme.labelMedium)!
                .copyWith(color: style.textColor),
          ),
        ],
      ),
    );
  }
}

/// 중립 태그(기간 칸 등). 무 칩과 같은 모양.
const neutralTagStyle = AppTagStyle(
  fill: AppPalette.surface,
  textColor: AppPalette.ink,
  borderColor: AppPalette.outline,
);
