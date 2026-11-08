import 'package:flutter/material.dart';

import '../theme/app_palette.dart';

/// 테마 기본값 위에 얹는 버튼 스타일(design 4.2).
///
/// 버튼 진행 중 규칙(새 위젯 없음): 진행 중이면 `onPressed: null` + 라벨 자리에 `AppLoader.small`.
/// 비활성 모양(납작한 sunken 면)이 적용되어 누를 수 없음이 보이고 버튼 크기는 유지된다.
class AppButtonStyles {
  AppButtonStyles._();

  /// 위험 동작(계정 삭제, 대화상자 안의 되돌릴 수 없는 확인). FilledButton용.
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

  /// 위험 윤곽: 되돌릴 수는 있지만 결과가 큰 동작(동의 철회 — 다시 동의하면 돌아온다). OutlinedButton용.
  /// 빨간 채움(계정 삭제)보다 한 단계 낮다: 흰 면 + danger 글자·아이콘·1.5dp danger 테두리. 3dp ink 두께·눌림·비활성
  /// (납작한 sunken 면, 테두리 없음)·포커스 링은 보조 버튼 테마를 그대로 따른다(redesign 후속 결정 5).
  static final dangerOutlined = ButtonStyle(
    foregroundColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.disabled)
          ? AppPalette.inkDisabled
          : AppPalette.danger,
    ),
    iconColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.disabled)
          ? AppPalette.inkDisabled
          : AppPalette.danger,
    ),
    side: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) return BorderSide.none;
      if (states.contains(WidgetState.focused)) {
        return const BorderSide(color: AppPalette.primary, width: 2);
      }
      return const BorderSide(color: AppPalette.danger, width: 1.5);
    }),
  );
}
