import 'package:flutter/material.dart';

import '../theme/retro_palette.dart';

/// 테마 기본값 위에 얹는 버튼 스타일.
///
/// 버튼 진행 중 규칙(새 위젯 없음): 진행 중이면 `onPressed: null` + 라벨 자리에 `PixelLoader.small`.
/// 비활성 모양이 적용되어 누를 수 없음이 보이고 버튼 크기는 유지된다.
class RetroButtonStyles {
  RetroButtonStyles._();

  /// 위험 동작(포기, 계정 삭제, 동의 철회). FilledButton·OutlinedButton 겸용.
  /// 면만 danger로 바꾸고 테두리·바닥 두께·눌림은 테마를 그대로 따른다.
  static final danger = ButtonStyle(
    backgroundColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.disabled) ? RetroPalette.sunken : RetroPalette.danger,
    ),
    foregroundColor: WidgetStateProperty.resolveWith(
      (states) =>
          states.contains(WidgetState.disabled) ? RetroPalette.inkDisabled : RetroPalette.surface,
    ),
    iconColor: WidgetStateProperty.resolveWith(
      (states) =>
          states.contains(WidgetState.disabled) ? RetroPalette.inkDisabled : RetroPalette.surface,
    ),
  );
}
