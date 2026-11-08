import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todododo/core/theme/app_palette.dart';

/// redesign design.md 2.2(공통)·2.3(시안 A) 대비비 표. 이름, 앞(글자·요소) 색, 뒤(배경) 색,
/// 설계에 적은 값, 지켜야 할 기준. 설계값은 ±0.05로 고정한다.
const _body = 4.5;
const _disabledTarget = 3.0;
const _nonText = 3.0;

typedef _Pair = (String, Color, Color, double, double);

/// 2.2 공통 글자/배경 쌍(일반 4.5, 비활성 3). `danger / dangerPale`은 글자 불가라 아래 장식 표로 뺐다.
final _textPairs = <_Pair>[
  ('ink / surface', AppPalette.ink, AppPalette.surface, 16.14, _body),
  ('ink / background', AppPalette.ink, AppPalette.background, 14.26, _body),
  ('ink / sunken', AppPalette.ink, AppPalette.sunken, 13.00, _body),
  ('inkMuted / surface', AppPalette.inkMuted, AppPalette.surface, 7.87, _body),
  ('inkMuted / background', AppPalette.inkMuted, AppPalette.background, 6.95, _body),
  ('inkMuted / sunken', AppPalette.inkMuted, AppPalette.sunken, 6.34, _body),
  ('surface / ink', AppPalette.surface, AppPalette.ink, 16.14, _body),
  ('amber / ink', AppPalette.amber, AppPalette.ink, 8.83, _body),
  ('surface / inkMuted', AppPalette.surface, AppPalette.inkMuted, 7.87, _body),
  ('ink / amber', AppPalette.ink, AppPalette.amber, 8.83, _body),
  ('ink / mint', AppPalette.ink, AppPalette.mint, 7.91, _body),
  ('surface / success', AppPalette.surface, AppPalette.success, 5.33, _body),
  ('success / surface', AppPalette.success, AppPalette.surface, 5.33, _body),
  ('success / background', AppPalette.success, AppPalette.background, 4.71, _body),
  ('success / successPale', AppPalette.success, AppPalette.successPale, 4.58, _body),
  ('ink / successPale', AppPalette.ink, AppPalette.successPale, 13.86, _body),
  ('surface / danger', AppPalette.surface, AppPalette.danger, 5.19, _body),
  ('danger / surface', AppPalette.danger, AppPalette.surface, 5.19, _body),
  ('danger / background', AppPalette.danger, AppPalette.background, 4.58, _body),
  ('ink / dangerPale', AppPalette.ink, AppPalette.dangerPale, 13.29, _body),
  ('warning / surface', AppPalette.warning, AppPalette.surface, 5.14, _body),
  ('warning / background', AppPalette.warning, AppPalette.background, 4.54, _body),
  ('warning / warningPale', AppPalette.warning, AppPalette.warningPale, 4.60, _body),
  ('ink / warningPale', AppPalette.ink, AppPalette.warningPale, 14.45, _body),
  ('ink / judgingPale', AppPalette.ink, AppPalette.judgingPale, 13.32, _body),
  ('inkDisabled / surface', AppPalette.inkDisabled, AppPalette.surface, 4.10, _disabledTarget),
  ('inkDisabled / sunken', AppPalette.inkDisabled, AppPalette.sunken, 3.30, _disabledTarget),
  ('inkDisabled / background', AppPalette.inkDisabled, AppPalette.background, 3.62, _disabledTarget),
];

/// 2.2 공통 비텍스트 쌍(SC 1.4.11, 3:1).
final _nonTextPairs = <_Pair>[
  ('outline / surface', AppPalette.outline, AppPalette.surface, 4.78, _nonText),
  ('outline / background', AppPalette.outline, AppPalette.background, 4.22, _nonText),
  ('outline / sunken', AppPalette.outline, AppPalette.sunken, 3.85, _nonText),
  ('ink / background (버튼 두께)', AppPalette.ink, AppPalette.background, 14.26, _nonText),
  ('danger / surface (오류 입력)', AppPalette.danger, AppPalette.surface, 5.19, _nonText),
  ('danger / background (오류 입력)', AppPalette.danger, AppPalette.background, 4.58, _nonText),
  ('success / surface (합격 아이콘)', AppPalette.success, AppPalette.surface, 5.33, _nonText),
  ('warning / warningPale (미결 테두리)', AppPalette.warning, AppPalette.warningPale, 4.60, _nonText),
  ('judging / judgingPale (판정 중 테두리)', AppPalette.judging, AppPalette.judgingPale, 5.11, _nonText),
  ('inkMuted / surface (비선택 탭 아이콘)', AppPalette.inkMuted, AppPalette.surface, 7.87, _nonText),
  ('danger / dangerPale (블록 아이콘)', AppPalette.danger, AppPalette.dangerPale, 4.27, _nonText),
];

/// 2.3 시안 A 표. 글자 쌍은 4.5, 경계·포커스·작은 조작 요소는 3.
final _brandPairs = <_Pair>[
  ('surface / primary (주 버튼 라벨)', AppPalette.surface, AppPalette.primary, 5.41, _body),
  ('primary / surface (링크형 글자)', AppPalette.primary, AppPalette.surface, 5.41, _body),
  ('primary / background', AppPalette.primary, AppPalette.background, 4.78, _body),
  ('primaryDeep / surface', AppPalette.primaryDeep, AppPalette.surface, 8.51, _body),
  ('primaryDeep / background', AppPalette.primaryDeep, AppPalette.background, 7.52, _body),
  ('primaryDeep / sunken', AppPalette.primaryDeep, AppPalette.sunken, 6.85, _body),
  ('ink / primaryPale (안내 블록 본문)', AppPalette.ink, AppPalette.primaryPale, 13.35, _body),
  ('primaryDeep / primaryPale (선택 탭)', AppPalette.primaryDeep, AppPalette.primaryPale, 7.04, _body),
  ('primary / primaryPale (아이콘만)', AppPalette.primary, AppPalette.primaryPale, 4.47, _nonText),
  ('주 버튼 면 / background', AppPalette.primary, AppPalette.background, 4.78, _nonText),
  ('주 버튼 면 / surface', AppPalette.primary, AppPalette.surface, 5.41, _nonText),
  ('체크박스 선택 면 primary / sunken', AppPalette.primary, AppPalette.sunken, 4.35, _nonText),
];

/// design-judging-buttons 2.5 — 토널·위험 토널·위험 텍스트 버튼(2A).
final _buttonPairs = <_Pair>[
  ('primaryDeep / primaryTonal (토널 라벨)', AppPalette.primaryDeep, AppPalette.primaryTonal, 6.55, _body),
  ('primaryDeep / primaryTonalPressed (토널 누름)', AppPalette.primaryDeep, AppPalette.primaryTonalPressed, 5.50, _body),
  ('ink / primaryTonal', AppPalette.ink, AppPalette.primaryTonal, 12.42, _body),
  ('primary 포커스 링 / primaryTonal', AppPalette.primary, AppPalette.primaryTonal, 4.16, _nonText),
  ('dangerDeep / dangerPale (위험 토널 라벨, 위험 텍스트 누름)', AppPalette.dangerDeep, AppPalette.dangerPale, 6.17, _body),
  ('dangerDeep / dangerTonalPressed (위험 토널 누름)', AppPalette.dangerDeep, AppPalette.dangerTonalPressed, 5.23, _body),
  ('dangerDeep / surface', AppPalette.dangerDeep, AppPalette.surface, 7.49, _body),
  ('danger / surface (위험 텍스트)', AppPalette.danger, AppPalette.surface, 5.19, _body),
  ('danger / background (위험 텍스트)', AppPalette.danger, AppPalette.background, 4.58, _body),
  ('inkDisabled / sunken (모든 비활성)', AppPalette.inkDisabled, AppPalette.sunken, 3.30, _disabledTarget),
];

/// 기준에 기대지 않는 쌍 — 설계값만 고정한다.
final _decorativePairs = <(String, Color, Color, double)>[
  // 글자에 쓰지 않는다: 차단·오류 블록 글자는 ink로만(블록 아이콘은 위 비텍스트 표에서 3:1 통과).
  ('danger / dangerPale', AppPalette.danger, AppPalette.dangerPale, 4.27),
  // 글자에 쓰지 않는다: 안내 블록의 primary는 아이콘(3:1)만.
  ('primary / primaryPale', AppPalette.primary, AppPalette.primaryPale, 4.47),
  // 장식: 속도전 칸·승 라벨 면. 뜻은 칸 안 ink 아이콘(8.83)과 글자가 전달한다.
  ('amber / surface', AppPalette.amber, AppPalette.surface, 1.83),
  // 장식: 품질전 칸. 같은 이유.
  ('mint / surface', AppPalette.mint, AppPalette.surface, 2.05),
  // 장식: 카드 선·카드 두께. 층 구분은 면 대비 + 두께가 함께 낸다.
  ('line / background', AppPalette.line, AppPalette.background, 1.25),
  ('edge / background', AppPalette.edge, AppPalette.background, 1.62),
  // 장식: 토널 버튼 경계. 토널·텍스트 버튼은 라벨(6.55)이 버튼을 식별한다(SC 1.4.11 대상 아님).
  ('primaryTonal / surface', AppPalette.primaryTonal, AppPalette.surface, 1.30),
  ('primaryTonal / background', AppPalette.primaryTonal, AppPalette.background, 1.15),
  // 쓰지 않는 조합: primaryPale 면 위에는 토널을 두지 않는다(면이 사라진다).
  ('primaryTonal / primaryPale', AppPalette.primaryTonal, AppPalette.primaryPale, 1.07),
  // 장식: 런처 마크의 체크/배경. 체크에 ink 두께를 둘러 윤곽을 세운다.
  ('amber / primary', AppPalette.amber, AppPalette.primary, 2.96),
];

void main() {
  test('대비비 공식은 흑/백에서 21:1이다', () {
    expect(
      contrastRatio(const Color(0xFF000000), const Color(0xFFFFFFFF)),
      closeTo(21.0, 0.001),
    );
  });

  for (final (category, table) in [
    ('글자', _textPairs),
    ('비텍스트', _nonTextPairs),
    ('시안 A', _brandPairs),
    ('버튼 2A', _buttonPairs),
  ]) {
    for (final (name, foreground, background, designed, minimum) in table) {
      test('[$category] $name 대비비가 설계값($designed)과 같고 기준 $minimum 이상이다', () {
        final ratio = contrastRatio(foreground, background);
        expect(ratio, closeTo(designed, 0.05));
        expect(ratio, greaterThanOrEqualTo(minimum));
      });
    }
  }

  for (final (name, foreground, background, designed) in _decorativePairs) {
    test('[장식] $name 대비비가 설계값($designed)과 같다', () {
      expect(contrastRatio(foreground, background), closeTo(designed, 0.05));
    });
  }

  test('보조 강조(secondary)는 amber와 같은 값이다(시안 A)', () {
    expect(AppPalette.secondary, AppPalette.amber);
  });

  group('onFill', () {
    test('브랜드 면에는 흰 글자, 그 밖의 면에는 ink', () {
      expect(AppPalette.onFill(AppPalette.primary), AppPalette.surface);
      expect(AppPalette.onFill(AppPalette.secondary), AppPalette.ink);
      expect(AppPalette.onFill(AppPalette.amber), AppPalette.ink);
      expect(AppPalette.onFill(AppPalette.surface), AppPalette.ink);
    });

    test('고른 글자색은 그 면 위에서 4.5:1 이상이다', () {
      for (final fill in [
        AppPalette.primary,
        AppPalette.secondary,
        AppPalette.amber,
        AppPalette.surface,
      ]) {
        expect(
          contrastRatio(AppPalette.onFill(fill), fill),
          greaterThanOrEqualTo(_body),
          reason: '$fill',
        );
      }
    });
  });

  group('IP 가드(design 4.3)', () {
    // 레퍼런스(Duolingo)의 브랜드 초록. 우리는 브랜드에 초록을 쓰지 않고, 의미색의 초록은 이 색과 눈으로 갈린다.
    const reference = Color(0xFF58CC02);
    double hueOf(Color color) => HSLColor.fromColor(color).hue;

    double hueDistance(double a, double b) {
      final d = (a - b).abs() % 360;
      return d > 180 ? 360 - d : d;
    }

    test('브랜드색(primary·primaryDeep)은 초록 범위(75°~165°) 밖이다', () {
      for (final color in [AppPalette.primary, AppPalette.primaryDeep]) {
        final hue = hueOf(color);
        expect(hue < 75 || hue > 165, isTrue, reason: '$color hue=$hue');
      }
    });

    test('의미색 success·mint는 #58CC02와 색상이 30° 이상 떨어져 있다', () {
      for (final color in [AppPalette.success, AppPalette.mint]) {
        expect(
          hueDistance(hueOf(color), hueOf(reference)),
          greaterThanOrEqualTo(30),
          reason: '$color',
        );
      }
    });
  });
}
