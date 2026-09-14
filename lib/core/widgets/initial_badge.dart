import 'package:flutter/material.dart';

import '../theme/pixel_border.dart';
import '../theme/retro_palette.dart';
import '../theme/retro_text.dart';

/// 표시 이름의 이니셜 한 글자.
///
/// 앞뒤 공백을 지우고 첫 글자 단위(grapheme) 하나를 쓴다 — 이모지·결합 문자가 반쪽으로 잘리지 않는다.
/// 라틴 소문자는 대문자로. 비었으면 `?`. 서버가 준 묘비 표시명("탈퇴한 사용자")도 특별 취급하지 않는다
/// (문자열 비교로 분기하면 서버 문구가 바뀔 때 깨진다).
String displayInitial(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return '?';
  final first = trimmed.characters.first;
  // 한글·이모지는 대문자가 없어 그대로다. 'ß' → 'SS'처럼 글자 수가 바뀌는 경우만 원래 글자를 쓴다.
  final upper = first.toUpperCase();
  return upper.characters.length == 1 ? upper : first;
}

enum InitialBadgeSize { card, intro }

/// 이니셜을 담는 정사각 칸. 카드용 40(글자 24) / VS 인트로용 72(글자 36).
/// 면색은 호출자가 나(primary) / 상대(amber) 중 고르고, 글자는 면에 맞는 색이 된다.
/// 캐릭터·사진 없이 글자만 둔다.
class InitialBadge extends StatelessWidget {
  const InitialBadge({
    super.key,
    required this.name,
    required this.fill,
    this.size = InitialBadgeSize.card,
    this.dimension,
  });

  final String name;
  final Color fill;
  final InitialBadgeSize size;

  /// 작은 화면에서 칸을 줄일 때만 지정한다(VS 인트로).
  final double? dimension;

  @override
  Widget build(BuildContext context) {
    final isIntro = size == InitialBadgeSize.intro;
    final side = dimension ?? (isIntro ? 72.0 : 40.0);
    final fontSize = side >= 72 ? RetroText.grid * 3 : RetroText.grid * 2;
    final textColor = fill == RetroPalette.primary ? RetroPalette.surface : RetroPalette.ink;

    return ExcludeSemantics(
      child: Container(
        width: side,
        height: side,
        decoration: ShapeDecoration(color: fill, shape: const PixelBorder(depth: 2)),
        alignment: Alignment.center,
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              displayInitial(name),
              style: RetroText.pixel(fontSize, bold: true, color: textColor),
            ),
          ),
        ),
      ),
    );
  }
}
