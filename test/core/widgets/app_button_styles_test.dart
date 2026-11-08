import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:todododo/core/theme/app_palette.dart';
import 'package:todododo/core/widgets/app_button_styles.dart';

void main() {
  group('AppButtonStyles.dangerOutlined(위험 윤곽 — 동의 철회)', () {
    final style = AppButtonStyles.dangerOutlined;

    test('평소: danger 글자·아이콘·1.5dp danger 테두리, 면은 보조 버튼 테마(흰 면)를 따른다', () {
      const states = <WidgetState>{};
      expect(style.foregroundColor!.resolve(states), AppPalette.danger);
      expect(style.iconColor!.resolve(states), AppPalette.danger);
      expect(style.side!.resolve(states), const BorderSide(color: AppPalette.danger, width: 1.5));
      // 면을 정하지 않는다 — 빨간 채움(AppButtonStyles.danger)과 갈리는 지점.
      expect(style.backgroundColor, isNull);
    });

    test('비활성: inkDisabled 글자, 테두리 없음(보조 버튼 비활성 모양과 같다)', () {
      const states = {WidgetState.disabled};
      expect(style.foregroundColor!.resolve(states), AppPalette.inkDisabled);
      expect(style.iconColor!.resolve(states), AppPalette.inkDisabled);
      expect(style.side!.resolve(states), BorderSide.none);
    });

    test('포커스: primary 2dp 링(보조 버튼과 같다)', () {
      expect(
        style.side!.resolve({WidgetState.focused}),
        const BorderSide(color: AppPalette.primary, width: 2),
      );
    });
  });
}
