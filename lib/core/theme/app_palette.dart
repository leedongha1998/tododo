import 'package:flutter/painting.dart';

/// redesign 팔레트(`docs/specs/redesign/design.md` 2장, 시안 A). 앱 안의 모든 색은 여기서만 고른다.
///
/// 중립·의미색은 시안과 무관한 공통 토큰이고, 브랜드 묶음(`primary`·`primaryDeep`·`primaryPale`·
/// `secondary`·`judging`·`judgingPale`)만 시안별로 다르다. 시안을 바꿀 일이 생기면 이 묶음의 값만 바꾼다
/// (토큰 이름은 색 이름이 아니라 역할 이름이다). 대비 조합은 `test/core/theme/app_palette_test.dart`가 고정한다.
class AppPalette {
  AppPalette._();

  // ── 공통 토큰 ──

  /// 화면 배경, 앱바 면, 시작 창, 위젯 바탕.
  static const background = Color(0xFFEEF1F6);

  /// 카드·대화상자·시트·입력 필드·탭바 면, 색 면 위 흰 글자.
  static const surface = Color(0xFFFFFFFF);

  /// 가라앉은 면(완료한 할 일, 인용, 모집 조작판), 비활성 버튼 면, 취소 칩, 사진 틀 여백.
  static const sunken = Color(0xFFE2E7EF);

  /// 장식 구분선, 카드 1dp 선. 조작 요소 경계에는 쓰지 않는다(비활성 컨트롤만 예외).
  static const line = Color(0xFFD3D9E3);

  /// 떠 있는 카드의 아래 두께(장식).
  static const edge = Color(0xFFB8C0CF);

  /// 조작 요소 경계: 입력 필드, 체크박스, 보조 버튼, 세그먼트, 칩 테두리.
  static const outline = Color(0xFF6B7289);

  /// 본문 글자, 아이콘, 버튼 아래 두께, 토스트 면.
  static const ink = Color(0xFF1B2033);

  /// 보조 글자, 비선택 탭, 완료한 할 일 글자, 패 라벨 면.
  static const inkMuted = Color(0xFF4A5168);

  /// 비활성 글자·아이콘.
  static const inkDisabled = Color(0xFF767D93);

  /// 종료 칩 면, 합격 아이콘.
  static const success = Color(0xFF1D7A4C);

  /// 성공 블록 면.
  static const successPale = Color(0xFFDDF3E6);

  /// 위험 버튼 면, 위험 텍스트 버튼 글자, 오류 테두리·글자.
  static const danger = Color(0xFFCC2F3F);

  /// 차단·오류 블록 면. 이 면 위 글자는 ink로만(danger 글자는 4.27로 미달).
  static const dangerPale = Color(0xFFFDE3E4);

  /// 미결 칩 테두리·아이콘(경고).
  static const warning = Color(0xFFA65A00);

  /// 미결 칩 면.
  static const warningPale = Color(0xFFFFF1D6);

  /// 속도전 색 칸, 승 라벨 면, 토스트 동작 글자. 흰 면 위에서는 장식으로만 쓴다(1.83).
  static const amber = Color(0xFFFFB020);

  /// 품질전 색 칸. 흰 면 위에서는 장식으로만 쓴다.
  static const mint = Color(0xFF4CC9B0);

  // ── 브랜드 묶음 (시안 A — 밝은 파랑 + 앰버) ──

  /// 주 버튼, 진행 중 칩, 선택 상태, 런처 배경, "나".
  static const primary = Color(0xFF3355FF);

  /// 글자로 쓰는 브랜드색(텍스트 버튼, 기준 번호, 선택 탭 아이콘).
  static const primaryDeep = Color(0xFF2238C8);

  /// 안내 블록 면, 선택 탭 표시기. 이 면 위 primary 글자는 4.47로 미달 — 글자는 ink·primaryDeep.
  static const primaryPale = Color(0xFFE3E9FF);

  /// 보조 강조("상대"). 시안 A에서는 [amber]와 같은 값이다.
  static const secondary = amber;

  /// 판정 중 칩 테두리.
  static const judging = Color(0xFF6247D6);

  /// 판정 중 칩 면.
  static const judgingPale = Color(0xFFECE6FF);

  /// 면색 → 그 위 글자색(design 5.2 InitialBadge). 브랜드 면에는 흰 글자, 그 밖의 면에는 ink.
  /// 시안마다 반대가 될 수 있어(시안 B는 주황 면 위 ink) 화면이 아니라 팔레트가 정한다.
  static Color onFill(Color fill) => fill == primary ? surface : ink;
}

/// WCAG 2.x 대비비. 팔레트 조합이 읽을 수 있는지 테스트로 고정하는 데 쓴다.
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}
