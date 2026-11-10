import 'package:flutter/material.dart';

/// 앱 안 아이콘(`docs/specs/redesign/design.md` 5.4). Flutter에 내장된 Material Icons의 Rounded 변형만 쓴다
/// (`uses-material-design: true`로 이미 번들, Apache 2.0 — 새 패키지 없음).
///
/// - 반드시 `Icons.*` 상수를 그대로 대입한다. `IconData(...)`를 동적으로 만들면 릴리스 빌드의 아이콘 트리 셰이킹이
///   깨진다.
/// - 한 벌 규칙: 한 색(현재 `IconTheme` 색), 크기 16/20/24/40. 탭바만 선택=채움·비선택=윤곽 변형을 쓴다.
/// - 얼굴·캐릭터·새 형태, 불꽃·하트·보석 아이콘은 쓰지 않는다(IP 가드, `app_icons_test`).
/// - 쓰는 곳이 생길 때만 추가한다(미래 대비 금지).
class AppIcons {
  AppIcons._();

  /// 내 대결 탭, 대결 만들기 FAB(권투 글러브 — design 결정 2).
  static const battle = Icons.sports_mma_rounded;

  /// 내 대결 탭 비선택.
  static const battleOutlined = Icons.sports_mma_outlined;

  /// 대결 찾기 탭, 검색 필드. 윤곽 변형이 없어 탭 선택·비선택 모두 이 아이콘이다.
  static const search = Icons.search_rounded;

  /// 할 일 탭.
  static const todo = Icons.check_box_rounded;

  /// 할 일 탭 비선택, 빈 할 일.
  static const todoOutlined = Icons.check_box_outlined;

  /// 프로필 탭.
  static const profile = Icons.person_rounded;

  /// 프로필 탭 비선택.
  static const profileOutlined = Icons.person_outline_rounded;

  /// FAB, 기준 항목 추가.
  static const add = Icons.add_rounded;

  /// 앱바 뒤로.
  static const back = Icons.arrow_back_rounded;

  /// 로그아웃.
  static const logout = Icons.logout_rounded;

  /// 계정 삭제.
  static const accountDelete = Icons.person_remove_rounded;

  /// 할 일 삭제.
  static const delete = Icons.delete_outline_rounded;

  /// 세그먼트 선택 표시.
  static const check = Icons.check_rounded;

  /// 속도전 배지.
  static const speed = Icons.bolt_rounded;

  /// 품질전 배지(인장 리본).
  static const quality = Icons.workspace_premium_rounded;

  /// 포기.
  static const flag = Icons.flag_rounded;

  /// 촬영·다시 찍기.
  static const camera = Icons.photo_camera_rounded;

  /// 사진 불러오기 실패.
  static const brokenImage = Icons.broken_image_rounded;

  /// 승리 배너.
  static const trophy = Icons.emoji_events_rounded;

  /// 패배 배너(얼굴 대신 아래로 꺾인 화살표).
  static const lose = Icons.trending_down_rounded;

  /// 무 배너, 판정 대기 블록.
  static const hourglass = Icons.hourglass_bottom_rounded;

  /// 미결, 오류, 위험 블록, 무효 배너.
  static const warning = Icons.warning_amber_rounded;

  /// 성공 블록 기본 아이콘, 판정 선택지 "통과했어요".
  static const pass = Icons.check_circle_rounded;

  /// 판정 선택지 "통과하지 못했어요"(design-judging-buttons 1A.2).
  static const fail = Icons.cancel_rounded;

  /// AI가 다시 봄(불복 힌트, AI 재판정). 로봇 얼굴 대신 돋보기.
  static const aiReview = Icons.manage_search_rounded;

  /// 판정은 한 번만.
  static const lock = Icons.lock_rounded;

  /// 판정 진행 줄 "판정할 사진 없음"(design-judging-buttons 1C의 "—" 배지).
  static const dash = Icons.remove_rounded;

  /// 안내 블록.
  static const info = Icons.info_outline_rounded;

  /// 다시 시도·다시 찍기.
  static const retry = Icons.refresh_rounded;

  /// 기준 항목 삭제.
  static const remove = Icons.remove_circle_outline_rounded;

  /// 남은 시간·제출 시각·판정 기한 경과.
  static const clock = Icons.schedule_rounded;

  /// 동의 문구, 오픈소스 라이선스.
  static const document = Icons.description_outlined;

  /// 시트 닫기, 검색어 지우기, 모집 취소.
  static const close = Icons.close_rounded;

  /// 모집 기준 수정(design-judging-buttons 2.7).
  static const edit = Icons.edit_rounded;
}
