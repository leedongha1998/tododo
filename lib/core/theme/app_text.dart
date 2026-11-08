import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'app_palette.dart';

/// 글자 역할표(`docs/specs/redesign/design.md` 3.2). 모든 글자는 Pretendard 한 벌(400/700/800)이다.
///
/// - 모든 슬롯에 `fontFamily`를 직접 적는다 — 비워 두면 Material Typography가 머지하며 'Roboto'가 붙는다.
/// - 모든 슬롯에 행간을 직접 적는다 — 비워 두면 englishLike 기하(1.33~1.50)가 머지돼 WCAG SC 1.4.12(본문 1.5em)에
///   미달한다.
/// - 자간은 0 고정(음수 자간 없음), 굵기는 400 이상만.
/// - 같은 역할의 글자는 이 표 밖의 크기를 쓰지 않는다. 화면에서 `copyWith(fontSize: …)`로 새 크기를 만들지 않는다.
class AppText {
  AppText._();

  /// pubspec.yaml의 글꼴 패밀리 이름(OFL 예약 이름 — 바꾸지 않는다).
  static const family = 'Pretendard';

  static const _tabularFigures = [ui.FontFeature.tabularFigures()];

  static TextStyle _slot(double size, FontWeight weight, double height) {
    return TextStyle(
      fontFamily: family,
      fontSize: size,
      fontWeight: weight,
      height: height,
      letterSpacing: 0,
      color: AppPalette.ink,
    );
  }

  /// ThemeData에 넣는 역할표. Material 위젯의 기본 슬롯이 이 표를 따른다.
  static TextTheme textTheme() {
    return TextTheme(
      // 예비(현재 쓰는 곳 없음).
      displayLarge: _slot(40, FontWeight.w800, 1.25),
      // 로그인 앱 이름.
      displayMedium: _slot(34, FontWeight.w800, 1.25),
      displaySmall: _slot(28, FontWeight.w800, 1.3),
      headlineLarge: _slot(26, FontWeight.w700, 1.35),
      headlineMedium: _slot(24, FontWeight.w700, 1.35),
      // 대화상자 제목.
      headlineSmall: _slot(22, FontWeight.w700, 1.4),
      // 앱바 제목.
      titleLarge: _slot(20, FontWeight.w700, 1.4),
      // 결과 배너 헤드라인, VS 명판 이름, 큰 결과 라벨.
      titleMedium: _slot(18, FontWeight.w700, 1.45),
      // 묶음 제목, 안내 블록 제목, 판정 질문.
      titleSmall: _slot(16, FontWeight.w700, 1.5),
      // 할 일 내용, 목록 주 텍스트, 입력 글자.
      bodyLarge: _slot(16, FontWeight.w400, 1.6),
      // 문장: 안내·경고·오류·대화상자 본문·동의 문구·판정 기준·마감 줄.
      bodyMedium: _slot(15, FontWeight.w400, 1.6),
      // 메타데이터만. 놓치면 손해 보는 문장은 여기에 두지 않는다.
      bodySmall: _slot(13, FontWeight.w400, 1.55),
      // 버튼·세그먼트 라벨.
      labelLarge: _slot(16, FontWeight.w700, 1.4),
      // 칩·배지·카운터, VS "상대"/"나".
      labelMedium: _slot(14, FontWeight.w700, 1.4),
      // 하단 탭 라벨(선택 700 / 비선택은 테마가 400으로 내린다).
      labelSmall: _slot(12, FontWeight.w700, 1.35),
    );
  }

  // ── 숫자 슬롯(TextTheme 밖). 고정폭 숫자라 바뀌는 숫자의 폭이 흔들리지 않는다. ──

  /// 프로필 점수.
  static const numberLarge = TextStyle(
    fontFamily: family,
    fontSize: 32,
    fontWeight: FontWeight.w800,
    height: 1.2,
    letterSpacing: 0,
    color: AppPalette.ink,
    fontFeatures: _tabularFigures,
  );

  /// 결과 배너 점수 변화.
  static const numberMedium = TextStyle(
    fontFamily: family,
    fontSize: 20,
    fontWeight: FontWeight.w800,
    height: 1.3,
    letterSpacing: 0,
    color: AppPalette.ink,
    fontFeatures: _tabularFigures,
  );

  /// 상대 카드 점수·전적, 프로필 전적, 기준 번호, 제출 시각.
  static const numberSmall = TextStyle(
    fontFamily: family,
    fontSize: 16,
    fontWeight: FontWeight.w700,
    height: 1.4,
    letterSpacing: 0,
    color: AppPalette.ink,
    fontFeatures: _tabularFigures,
  );

  /// 문장 슬롯에 고정폭 숫자만 켜는 조각(마감·남은 시간 줄). `bodyMedium.merge(AppText.tabular)`.
  static const tabular = TextStyle(fontFeatures: _tabularFigures);
}
