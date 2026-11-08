import 'package:flutter/material.dart';

import '../theme/app_palette.dart';
import '../theme/depth_border.dart';

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

  /// 위험 토널: 되돌릴 수는 있지만 결과가 큰 동작(동의 철회 — 다시 동의하면 돌아온다). OutlinedButton용.
  /// 빨간 채움(계정 삭제)보다 한 단계 낮다: dangerPale 면 + dangerDeep 라벨·아이콘(6.17), 테두리·두께 없음.
  /// 누름 = dangerTonalPressed 면(5.23). 비활성(sunken + inkDisabled)·포커스 링·크기는 보조(토널) 테마를 따른다
  /// (design-judging-buttons 2A — 옛 이름 `dangerOutlined`는 모양을 오해하게 해서 바꿨다).
  static final dangerTonal = ButtonStyle(
    backgroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) return AppPalette.sunken;
      if (states.contains(WidgetState.pressed)) return AppPalette.dangerTonalPressed;
      return AppPalette.dangerPale;
    }),
    foregroundColor: _dangerDeepOrDisabled,
    iconColor: _dangerDeepOrDisabled,
  );

  /// 위험 텍스트: 낮은 위험(대결 포기 — 확인 대화상자가 따로 있다, 모집 취소). TextButton용.
  /// 투명 면 + danger 라벨(surface 5.19 · background 4.58). 누르는 동안 dangerPale 면 + dangerDeep 라벨
  /// (danger 글자는 dangerPale 위 4.27로 미달이라 그 순간 라벨색을 바꾼다). 크기·포커스 링은 텍스트 버튼 테마.
  static final dangerText = ButtonStyle(
    backgroundColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.pressed) && !states.contains(WidgetState.disabled)
          ? AppPalette.dangerPale
          : Colors.transparent,
    ),
    foregroundColor: _dangerTextColor,
    iconColor: _dangerTextColor,
  );

  /// 작은 크기(카드 안 작은 행동 — 모집 카드). 등급 스타일 위에 `merge`로 얹는다:
  /// `AppButtonStyles.dangerText.merge(AppButtonStyles.compact)`, 토널은 `style: AppButtonStyles.compact`.
  /// 면 높이 40·알약(모서리 20)·아이콘 20. 좌우 여백은 등급(테마)대로 — 토널 16, 텍스트 12.
  /// 터치 영역은 `MaterialTapTargetSize.padded`가 바깥을 48로 채운다. 1.5배에서는 면이 늘어난다(40은 최소값).
  static const compact = ButtonStyle(
    minimumSize: WidgetStatePropertyAll(Size(48, 40)),
    shape: WidgetStatePropertyAll(DepthBorder(radius: 20)),
    iconSize: WidgetStatePropertyAll(20),
    tapTargetSize: MaterialTapTargetSize.padded,
  );

  static final _dangerDeepOrDisabled = WidgetStateProperty.resolveWith(
    (states) =>
        states.contains(WidgetState.disabled) ? AppPalette.inkDisabled : AppPalette.dangerDeep,
  );

  static final _dangerTextColor = WidgetStateProperty.resolveWith((states) {
    if (states.contains(WidgetState.disabled)) return AppPalette.inkDisabled;
    if (states.contains(WidgetState.pressed)) return AppPalette.dangerDeep;
    return AppPalette.danger;
  });
}
