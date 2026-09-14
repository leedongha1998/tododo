import 'package:flutter/material.dart';

import '../../../core/strings.dart';
import '../../../core/theme/pixel_border.dart';
import '../../../core/theme/pixel_icons.dart';
import '../../../core/theme/retro_palette.dart';
import '../../../core/widgets/pixel_icon.dart';
import '../../../core/widgets/pixel_tag.dart';

/// 대결 카드, 대결 상세, 전적 목록이 유형·상태·결과를 같은 모양으로 보여주기 위한 공용 조각.
/// 여러 곳이 각자 다르게 그리면 같은 상태가 화면마다 달라 보인다.
///
/// 아래 매핑 함수는 서버가 정한 값을 **모양으로만** 바꾼다. 승패를 계산하지 않는다.

String battleTypeLabel(String type) {
  return type == 'speed' ? AppStrings.battleTypeSpeed : AppStrings.battleTypeQuality;
}

String battleStatusLabel(String status) {
  switch (status) {
    case 'active':
      return AppStrings.battleStatusActive;
    case 'judging':
      return AppStrings.battleStatusJudging;
    case 'finished':
      return AppStrings.battleStatusFinished;
    case 'disputed':
      return AppStrings.battleStatusDisputed;
    case 'draw':
      return AppStrings.battleStatusDraw;
    default:
      return status;
  }
}

/// 상태 칩 모양(design.md 3.2 "상태 칩 8종").
PixelTagStyle battleStatusTagStyle(String status) {
  return switch (status) {
    // 빈 자리 = 점선.
    'pending' => const PixelTagStyle(
        fill: RetroPalette.surface,
        textColor: RetroPalette.ink,
        borderColor: RetroPalette.ink,
        dashed: true,
      ),
    'active' => const PixelTagStyle(
        fill: RetroPalette.primary,
        textColor: RetroPalette.surface,
        borderColor: RetroPalette.ink,
      ),
    'judging' => const PixelTagStyle(
        fill: RetroPalette.lavender,
        textColor: RetroPalette.ink,
        borderColor: RetroPalette.ink,
      ),
    'finished' => const PixelTagStyle(
        fill: RetroPalette.success,
        textColor: RetroPalette.surface,
        borderColor: RetroPalette.ink,
      ),
    // 이의제기로 끝난 미결. 무승부와 면·테두리가 모두 달라야 한다.
    'disputed' => const PixelTagStyle(
        fill: RetroPalette.dangerPale,
        textColor: RetroPalette.ink,
        borderColor: RetroPalette.danger,
      ),
    'cancelled' => const PixelTagStyle(
        fill: RetroPalette.sunken,
        textColor: RetroPalette.inkMuted,
      ),
    // 전적에 들어가지 않는 약한 끝(ai-judge가 상태와 문자열을 추가한다).
    'voided' => const PixelTagStyle(
        fill: Colors.transparent,
        textColor: RetroPalette.inkMuted,
        borderColor: RetroPalette.inkMuted,
        dashed: true,
      ),
    // 무승부는 시간이 다 된 것이지 잘못된 일이 아니다. 위험색을 쓰지 않는다.
    // 알 수 없는 상태도 같은 중립 모양.
    _ => _neutralStyle,
  };
}

const _neutralStyle = PixelTagStyle(
  fill: RetroPalette.sunken,
  textColor: RetroPalette.ink,
  borderColor: RetroPalette.ink,
);

/// 무효 결과 라벨. "무효" 문자열은 ai-judge가 추가하므로 모양만 먼저 둔다.
/// 면 없음·점선·흐린 글자로 다른 결과보다 약하게 보인다.
const voidedResultTagStyle = PixelTagStyle(
  fill: Colors.transparent,
  textColor: RetroPalette.inkMuted,
  borderColor: RetroPalette.inkMuted,
  dashed: true,
);

/// 결과 라벨 모양(design.md 3.2 "결과 라벨"). 현재 `BattleRecord.resultLabel`이 문자열이라
/// `AppStrings` 값을 키로 받는다.
PixelTagStyle resultTagStyle(String label) {
  return switch (label) {
    // 가장 강한 결과. 유일하게 떠 있다.
    AppStrings.battleRecordWin => const PixelTagStyle(
        fill: RetroPalette.amber,
        textColor: RetroPalette.ink,
        borderColor: RetroPalette.ink,
        raised: true,
      ),
    AppStrings.battleRecordLose => const PixelTagStyle(
        fill: RetroPalette.inkMuted,
        textColor: RetroPalette.surface,
        borderColor: RetroPalette.ink,
      ),
    AppStrings.battleStatusFinished => const PixelTagStyle(
        fill: RetroPalette.success,
        textColor: RetroPalette.surface,
        borderColor: RetroPalette.ink,
      ),
    AppStrings.battleStatusDisputed => const PixelTagStyle(
        fill: RetroPalette.dangerPale,
        textColor: RetroPalette.ink,
        borderColor: RetroPalette.danger,
      ),
    _ => _neutralStyle,
  };
}

/// 유형 배지. 왼쪽 색 칸(속도전 앰버 / 품질전 민트) + 픽셀 아이콘(번개 / 인장) + 글자.
/// 색을 구분하지 못해도 아이콘과 글자로 구분된다.
class BattleTypeBadge extends StatelessWidget {
  const BattleTypeBadge({super.key, required this.type});

  final String type;

  @override
  Widget build(BuildContext context) {
    final isSpeed = type == 'speed';

    return Container(
      constraints: const BoxConstraints(minHeight: 24),
      decoration: const ShapeDecoration(color: RetroPalette.surface, shape: PixelBorder()),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 20,
            height: 20,
            color: isSpeed ? RetroPalette.amber : RetroPalette.mint,
            alignment: Alignment.center,
            child: PixelIcon(
              isSpeed ? PixelIcons.speed : PixelIcons.quality,
              size: 12,
              color: RetroPalette.ink,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            battleTypeLabel(type),
            style: Theme.of(context).textTheme.labelSmall!.copyWith(color: RetroPalette.ink),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}

/// 진행중/판정중/종료/미결/무승부를 면·테두리·글자색으로도 구분한다.
class BattleStatusChip extends StatelessWidget {
  const BattleStatusChip({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    return PixelTag(label: battleStatusLabel(status), style: battleStatusTagStyle(status));
  }
}

/// 결과 라벨(승/패/무/종료/미결). small은 전적 목록 오른쪽, large는 결과 배너.
class ResultLabel extends StatelessWidget {
  const ResultLabel.small({super.key, required this.label}) : size = PixelTagSize.small;

  const ResultLabel.large({super.key, required this.label}) : size = PixelTagSize.large;

  final String label;
  final PixelTagSize size;

  @override
  Widget build(BuildContext context) {
    return PixelTag(label: label, style: resultTagStyle(label), size: size);
  }
}
