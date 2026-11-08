import 'package:flutter/material.dart';

import '../theme/app_palette.dart';

/// 테마 기본값 위에 얹는 버튼 스타일(design 4.2).
///
/// 버튼 진행 중 규칙(새 위젯 없음): 진행 중이면 `onPressed: null` + 라벨 자리에 `AppLoader.small`.
/// 비활성 모양(납작한 sunken 면)이 적용되어 누를 수 없음이 보이고 버튼 크기는 유지된다.
class AppButtonStyles {
  AppButtonStyles._();

  /// 위험 동작(계정 삭제, 동의 철회). FilledButton용.
  /// 면만 danger(라벨·아이콘 흰색)로 바꾸고 모양·3dp ink 두께·눌림은 테마를 그대로 따른다.
  /// 비활성은 sunken 면 + inkDisabled 라벨.
  static final danger = ButtonStyle(
    backgroundColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.disabled)
          ? AppPalette.sunken
          : AppPalette.danger,
    ),
    foregroundColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.disabled)
          ? AppPalette.inkDisabled
          : AppPalette.surface,
    ),
    iconColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.disabled)
          ? AppPalette.inkDisabled
          : AppPalette.surface,
    ),
  );
}
