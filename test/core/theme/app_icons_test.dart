import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todododo/core/theme/app_icons.dart';

/// 앱 안 아이콘(redesign design 5.4). 상수가 서로 겹치지 않고, 금지 도형(IP 가드 — design 4.3)을 쓰지 않는다.
void main() {
  const icons = <String, IconData>{
    'battle': AppIcons.battle,
    'battleOutlined': AppIcons.battleOutlined,
    'search': AppIcons.search,
    'todo': AppIcons.todo,
    'todoOutlined': AppIcons.todoOutlined,
    'profile': AppIcons.profile,
    'profileOutlined': AppIcons.profileOutlined,
    'add': AppIcons.add,
    'back': AppIcons.back,
    'logout': AppIcons.logout,
    'accountDelete': AppIcons.accountDelete,
    'delete': AppIcons.delete,
    'check': AppIcons.check,
    'speed': AppIcons.speed,
    'quality': AppIcons.quality,
    'flag': AppIcons.flag,
    'camera': AppIcons.camera,
    'brokenImage': AppIcons.brokenImage,
    'trophy': AppIcons.trophy,
    'lose': AppIcons.lose,
    'hourglass': AppIcons.hourglass,
    'warning': AppIcons.warning,
    'pass': AppIcons.pass,
    'info': AppIcons.info,
    'retry': AppIcons.retry,
    'remove': AppIcons.remove,
    'clock': AppIcons.clock,
    'document': AppIcons.document,
    'close': AppIcons.close,
    'edit': AppIcons.edit,
    'fail': AppIcons.fail,
    'aiReview': AppIcons.aiReview,
    'lock': AppIcons.lock,
    'dash': AppIcons.dash,
    'dragHandle': AppIcons.dragHandle,
  };

  test('35개 상수가 모두 서로 다른 글리프다', () {
    expect(icons.length, 35);
    final codePoints = icons.values.map((icon) => icon.codePoint).toSet();
    expect(codePoints.length, icons.length);
  });

  test('모두 Flutter 내장 Material Icons 글꼴이다(새 패키지 없음)', () {
    for (final entry in icons.entries) {
      expect(entry.value.fontFamily, Icons.add.fontFamily, reason: entry.key);
    }
  });

  test('금지 도형(불꽃·하트·보석·얼굴)을 쓰지 않는다', () {
    const forbidden = [
      Icons.local_fire_department,
      Icons.local_fire_department_rounded,
      Icons.favorite,
      Icons.favorite_rounded,
      Icons.favorite_border_rounded,
      Icons.diamond,
      Icons.face,
      Icons.face_rounded,
      Icons.mood_bad,
      Icons.mood_bad_rounded,
      Icons.sentiment_dissatisfied_rounded,
      Icons.sentiment_very_dissatisfied_rounded,
      // 로봇 얼굴 — AI는 돋보기로 나타낸다(design-judging-buttons "바꾸지 않는 것").
      Icons.smart_toy,
      Icons.smart_toy_rounded,
    ];
    final forbiddenCodePoints = forbidden.map((icon) => icon.codePoint).toSet();
    for (final entry in icons.entries) {
      expect(forbiddenCodePoints, isNot(contains(entry.value.codePoint)), reason: entry.key);
    }
  });
}
