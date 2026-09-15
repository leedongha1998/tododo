import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todododo/core/strings.dart';
import 'package:todododo/core/theme/retro_palette.dart';
import 'package:todododo/core/widgets/pixel_tag.dart';
import 'package:todododo/features/battle/presentation/battle_chips.dart';

void main() {
  group('battleStatusTagStyle', () {
    test('8종 상태가 설계 표대로 매핑된다', () {
      expect(
        battleStatusTagStyle('pending'),
        const PixelTagStyle(
          fill: RetroPalette.surface,
          textColor: RetroPalette.ink,
          borderColor: RetroPalette.ink,
          dashed: true,
        ),
      );
      expect(
        battleStatusTagStyle('active'),
        const PixelTagStyle(
          fill: RetroPalette.primary,
          textColor: RetroPalette.surface,
          borderColor: RetroPalette.ink,
        ),
      );
      expect(
        battleStatusTagStyle('judging'),
        const PixelTagStyle(
          fill: RetroPalette.lavender,
          textColor: RetroPalette.ink,
          borderColor: RetroPalette.ink,
        ),
      );
      expect(
        battleStatusTagStyle('finished'),
        const PixelTagStyle(
          fill: RetroPalette.success,
          textColor: RetroPalette.surface,
          borderColor: RetroPalette.ink,
        ),
      );
      expect(
        battleStatusTagStyle('draw'),
        const PixelTagStyle(
          fill: RetroPalette.sunken,
          textColor: RetroPalette.ink,
          borderColor: RetroPalette.ink,
        ),
      );
      expect(
        battleStatusTagStyle('disputed'),
        const PixelTagStyle(
          fill: RetroPalette.dangerPale,
          textColor: RetroPalette.ink,
          borderColor: RetroPalette.danger,
        ),
      );
      expect(
        battleStatusTagStyle('cancelled'),
        const PixelTagStyle(fill: RetroPalette.sunken, textColor: RetroPalette.inkMuted),
      );
      expect(
        battleStatusTagStyle('voided'),
        const PixelTagStyle(
          fill: Colors.transparent,
          textColor: RetroPalette.inkMuted,
          borderColor: RetroPalette.inkMuted,
          dashed: true,
        ),
      );
    });

    test('무승부(시간 종료)와 미결(이의제기 종료)은 모양이 다르다', () {
      expect(battleStatusTagStyle('draw'), isNot(battleStatusTagStyle('disputed')));
    });

    test('무승부에는 위험색을 쓰지 않는다', () {
      final draw = battleStatusTagStyle('draw');
      const dangerColors = [RetroPalette.danger, RetroPalette.dangerPale];
      expect(dangerColors, isNot(contains(draw.fill)));
      expect(dangerColors, isNot(contains(draw.borderColor)));
      expect(dangerColors, isNot(contains(draw.textColor)));
    });

    test('8종 상태의 모양이 서로 모두 다르다', () {
      const statuses = [
        'pending',
        'active',
        'judging',
        'finished',
        'draw',
        'disputed',
        'cancelled',
        'voided',
      ];
      expect(statuses.map(battleStatusTagStyle).toSet(), hasLength(statuses.length));
    });

    test('알 수 없는 상태는 중립(무승부와 같은) 모양이다', () {
      expect(battleStatusTagStyle('something_new'), battleStatusTagStyle('draw'));
    });
  });

  group('resultTagStyle', () {
    test('승은 앰버 면에 유일하게 바닥 두께가 있다', () {
      final win = resultTagStyle(AppStrings.battleRecordWin);
      expect(win.fill, RetroPalette.amber);
      expect(win.textColor, RetroPalette.ink);
      expect(win.raised, isTrue);

      for (final label in [
        AppStrings.battleRecordLose,
        AppStrings.battleRecordDraw,
        AppStrings.battleStatusFinished,
        AppStrings.battleStatusDisputed,
      ]) {
        expect(resultTagStyle(label).raised, isFalse, reason: label);
      }
      expect(voidedResultTagStyle.raised, isFalse);
    });

    test('패·무·종료·미결이 설계 표대로 매핑된다', () {
      expect(
        resultTagStyle(AppStrings.battleRecordLose),
        const PixelTagStyle(
          fill: RetroPalette.inkMuted,
          textColor: RetroPalette.surface,
          borderColor: RetroPalette.ink,
        ),
      );
      expect(
        resultTagStyle(AppStrings.battleRecordDraw),
        const PixelTagStyle(
          fill: RetroPalette.sunken,
          textColor: RetroPalette.ink,
          borderColor: RetroPalette.ink,
        ),
      );
      expect(
        resultTagStyle(AppStrings.battleStatusFinished),
        const PixelTagStyle(
          fill: RetroPalette.success,
          textColor: RetroPalette.surface,
          borderColor: RetroPalette.ink,
        ),
      );
      expect(
        resultTagStyle(AppStrings.battleStatusDisputed),
        const PixelTagStyle(
          fill: RetroPalette.dangerPale,
          textColor: RetroPalette.ink,
          borderColor: RetroPalette.danger,
        ),
      );
    });

    test('무효 결과 라벨은 무효 모양으로, 무효 상태 칩은 무효 글자로 보인다', () {
      expect(resultTagStyle(AppStrings.battleRecordVoided), voidedResultTagStyle);
      expect(resultTagStyle(AppStrings.battleRecordVoided),
          isNot(resultTagStyle(AppStrings.battleRecordDraw)));
      expect(battleStatusLabel('voided'), AppStrings.battleStatusVoided);
    });

    test('무효는 면 없음·점선·흐린 글자로 가장 약하다', () {
      expect(voidedResultTagStyle.fill, Colors.transparent);
      expect(voidedResultTagStyle.dashed, isTrue);
      expect(voidedResultTagStyle.borderColor, RetroPalette.inkMuted);
      expect(voidedResultTagStyle.textColor, RetroPalette.inkMuted);
    });
  });
}
