import 'package:flutter/painting.dart';

import 'retro_palette.dart';

/// 앱 마크 — 런처·스토어 아이콘과 로그인 화면이 같은 그림을 쓴다(design.md 6장).
///
/// 계단 모서리 체크 칸(할 일)을 굵은 앰버 체크가 뚫고 나가고("먼저 해치운다"), 오른쪽·아래로
/// 1셀 단단한 그림자(레트로 바닥 두께)가 붙는다. 캐릭터·얼굴·원형 볼 같은 특정 게임 도형은 없다.
///
/// 16×16 색 인덱스 비트맵: `.` 투명, `s` surface, `a` amber, `k` ink.
/// 적응형 아이콘이 원형으로 깎여도 잘리지 않도록 네 모서리 2×2는 비우고, 켜진 셀은 전부
/// 중심에서 33dp(108dp 캔버스의 안전 원) 안에 둔다 — 테스트로 고정.
class AppMark {
  AppMark._();

  static const size = 16;

  static const rows = [
    '................',
    '................',
    '..sssssssss..aa.',
    '.s.kkkkkkkksaakk',
    '.sk........aakk.',
    '.sk.......aakk..',
    '.skaa....aask...',
    '.sk.aa..aaksk...',
    '.sk..aaaakksk...',
    '.sk...aakk.sk...',
    '.sk....kk..sk...',
    '.sk........sk...',
    '..sssssssss.k...',
    '...kkkkkkkkk....',
    '................',
    '................',
  ];

  /// 안드로이드 13 테마 아이콘용. 알파만 쓰이므로 그림자를 빼야 칸과 체크가 뭉개지지 않는다.
  static List<String> get monochromeRows => [for (final row in rows) row.replaceAll('k', '.')];

  static Color? colorOf(String cell) {
    return switch (cell) {
      's' => RetroPalette.surface,
      'a' => RetroPalette.amber,
      'k' => RetroPalette.ink,
      _ => null,
    };
  }
}
