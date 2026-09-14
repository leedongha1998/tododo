import 'package:flutter/painting.dart';

/// 레트로 테마의 제한 팔레트. 앱 안의 모든 색은 여기서만 고른다
/// (`docs/specs/retro-theme/design.md` 1.1). 런처 아이콘 생성 도구도 이 파일을 import해
/// 아이콘과 화면 색의 출처를 하나로 둔다.
class RetroPalette {
  RetroPalette._();

  /// 화면 배경, 시작 창 배경.
  static const paper = Color(0xFFF3EAD3);

  /// 프레임·카드·대화상자·시트·입력 필드 면, 어두운 면 위 글자.
  static const surface = Color(0xFFFFF8E7);

  /// 눌린 면, 중립 칩, 비활성 버튼 면, 사진 여백.
  static const sunken = Color(0xFFE3D6B8);

  /// 장식용 구분선. 조작 요소의 테두리에는 쓰지 않는다.
  static const line = Color(0xFFC9BA98);

  /// 본문 글자, 테두리, 바닥 두께, 토스트 면.
  static const ink = Color(0xFF231F3A);

  /// 보조 글자, 약한 테두리, 패 라벨 면.
  static const inkMuted = Color(0xFF57506B);

  /// 비활성 글자·테두리.
  static const inkDisabled = Color(0xFF756E84);

  /// 주 강조(주 버튼, 선택 탭, 진행 중, 런처 아이콘 배경).
  static const primary = Color(0xFF2F48B8);

  /// 안내 블록 면.
  static const primaryPale = Color(0xFFC5CDF0);

  /// 속도전 표지 칸, 승 라벨, 런처 아이콘 체크.
  static const amber = Color(0xFFF2B233);

  /// 품질전 표지 칸.
  static const mint = Color(0xFF6CC5B0);

  /// 판정 중.
  static const lavender = Color(0xFFB7A4E6);

  /// 종료, 합격.
  static const success = Color(0xFF27714A);

  /// 위험 동작, 오류 테두리.
  static const danger = Color(0xFFB8323A);

  /// 미결, 차단·오류 블록 면.
  static const dangerPale = Color(0xFFF4C7C0);
}

/// WCAG 2.x 대비비. 팔레트 조합이 읽을 수 있는지 테스트로 고정하는 데 쓴다.
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}
