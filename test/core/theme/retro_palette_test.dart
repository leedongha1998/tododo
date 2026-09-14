import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todododo/core/theme/retro_palette.dart';

/// design.md 1.1 대비비 표. 글자/배경, 설계에 적은 값, 지켜야 할 기준.
const _body = 4.5;
const _disabledTarget = 3.0;

final _table = <(String, Color, Color, double, double)>[
  ('ink / paper', RetroPalette.ink, RetroPalette.paper, 13.2, _body),
  ('ink / surface', RetroPalette.ink, RetroPalette.surface, 14.9, _body),
  ('inkMuted / paper', RetroPalette.inkMuted, RetroPalette.paper, 6.3, _body),
  ('inkMuted / surface', RetroPalette.inkMuted, RetroPalette.surface, 7.2, _body),
  ('inkMuted / sunken', RetroPalette.inkMuted, RetroPalette.sunken, 5.3, _body),
  ('ink / sunken', RetroPalette.ink, RetroPalette.sunken, 11.0, _body),
  ('surface / primary', RetroPalette.surface, RetroPalette.primary, 7.2, _body),
  ('primary / surface', RetroPalette.primary, RetroPalette.surface, 7.2, _body),
  ('primary / primaryPale', RetroPalette.primary, RetroPalette.primaryPale, 4.9, _body),
  ('ink / primaryPale', RetroPalette.ink, RetroPalette.primaryPale, 10.1, _body),
  ('ink / amber', RetroPalette.ink, RetroPalette.amber, 8.4, _body),
  ('ink / mint', RetroPalette.ink, RetroPalette.mint, 7.7, _body),
  ('ink / lavender', RetroPalette.ink, RetroPalette.lavender, 7.1, _body),
  ('surface / success', RetroPalette.surface, RetroPalette.success, 5.6, _body),
  ('success / paper', RetroPalette.success, RetroPalette.paper, 4.9, _body),
  ('surface / danger', RetroPalette.surface, RetroPalette.danger, 5.6, _body),
  ('danger / paper', RetroPalette.danger, RetroPalette.paper, 4.9, _body),
  ('danger / surface', RetroPalette.danger, RetroPalette.surface, 5.6, _body),
  ('ink / dangerPale', RetroPalette.ink, RetroPalette.dangerPale, 10.4, _body),
  ('surface / inkMuted', RetroPalette.surface, RetroPalette.inkMuted, 7.2, _body),
  ('surface / ink', RetroPalette.surface, RetroPalette.ink, 14.9, _body),
  ('amber / ink', RetroPalette.amber, RetroPalette.ink, 8.4, _body),
  ('inkDisabled / surface', RetroPalette.inkDisabled, RetroPalette.surface, 4.6, _disabledTarget),
  ('inkDisabled / sunken', RetroPalette.inkDisabled, RetroPalette.sunken, 3.4, _disabledTarget),
];

void main() {
  test('대비비 공식은 흑/백에서 21:1이다', () {
    expect(
      contrastRatio(const Color(0xFF000000), const Color(0xFFFFFFFF)),
      closeTo(21.0, 0.001),
    );
  });

  for (final (name, foreground, background, designed, minimum) in _table) {
    test('$name 대비비가 설계값($designed)과 같고 기준 $minimum 이상이다', () {
      final ratio = contrastRatio(foreground, background);
      expect(ratio, closeTo(designed, 0.05));
      expect(ratio, greaterThanOrEqualTo(minimum));
    });
  }

  test('조작 요소 경계로 쓰는 ink·danger는 paper 위에서 3:1 이상이다', () {
    expect(contrastRatio(RetroPalette.ink, RetroPalette.paper), greaterThanOrEqualTo(3));
    expect(contrastRatio(RetroPalette.danger, RetroPalette.paper), greaterThanOrEqualTo(3));
  });
}
