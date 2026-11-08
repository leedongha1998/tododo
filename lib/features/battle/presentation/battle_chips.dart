import 'package:flutter/material.dart';

import '../../../core/strings.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/depth_border.dart';
import '../../../core/widgets/app_tag.dart';
import '../../../core/widgets/keep_words_text.dart';
import '../domain/battle_outcome.dart';

/// 대결 카드, 대결 상세, 전적 목록이 유형·상태·결과를 같은 모양으로 보여주기 위한 공용 조각.
/// 여러 곳이 각자 다르게 그리면 같은 상태가 화면마다 달라 보인다.
///
/// 아래 매핑 함수는 서버가 정한 값을 **모양으로만** 바꾼다. 승패를 계산하지 않는다.

String battleTypeLabel(String type) {
  return type == 'speed' ? AppStrings.battleTypeSpeed : AppStrings.battleTypeQuality;
}

/// 기간(분) → 라벨. 서버는 1~10080분 사이 아무 값이나 받으므로 고정 라벨로 덮을 수 없다.
/// 떨어지는 가장 큰 단위로 말한다(1440 → "1일", 60 → "1시간", 90 → "90분").
String battleDurationLabel(int minutes) {
  if (minutes % 1440 == 0) return AppStrings.battleDurationDays(minutes ~/ 1440);
  if (minutes % 60 == 0) return AppStrings.battleDurationHours(minutes ~/ 60);
  return AppStrings.battleDurationMinutes(minutes);
}

/// 유형 한 줄 설명. 두 유형을 고르는 이유를 한 문장으로 말한다.
String battleTypeTagline(String type) {
  return type == 'speed' ? AppStrings.battleTypeSpeedTagline : AppStrings.battleTypeQualityTagline;
}

String battleStatusLabel(String status) {
  switch (status) {
    // 상대가 아직 없는 모집. 내 대결 탭의 모집 구역이 이 라벨을 쓴다.
    case 'pending':
      return AppStrings.battleStatusPending;
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
    case 'voided':
      return AppStrings.battleStatusVoided;
    default:
      return status;
  }
}

/// 상태 칩 모양(redesign design.md 5.3 "상태 칩 8종").
AppTagStyle battleStatusTagStyle(String status) {
  return switch (status) {
    // 빈 자리 = 점선(무승부의 실선과 점선 여부로 갈린다).
    'pending' => const AppTagStyle(
        fill: AppPalette.surface,
        textColor: AppPalette.ink,
        borderColor: AppPalette.outline,
        dashed: true,
      ),
    'active' => const AppTagStyle(
        fill: AppPalette.primary,
        textColor: AppPalette.surface,
      ),
    'judging' => const AppTagStyle(
        fill: AppPalette.judgingPale,
        textColor: AppPalette.ink,
        borderColor: AppPalette.judging,
      ),
    'finished' => const AppTagStyle(
        fill: AppPalette.success,
        textColor: AppPalette.surface,
      ),
    // 이의제기로 끝난 미결. 무승부와 면·테두리·아이콘이 모두 달라야 한다(경고색 계열 + 경고 아이콘).
    'disputed' => const AppTagStyle(
        fill: AppPalette.warningPale,
        textColor: AppPalette.ink,
        borderColor: AppPalette.warning,
        icon: AppIcons.warning,
      ),
    'cancelled' => const AppTagStyle(
        fill: AppPalette.sunken,
        textColor: AppPalette.inkMuted,
      ),
    // 전적에 들어가지 않는 약한 끝.
    'voided' => voidedResultTagStyle,
    // 무승부는 시간이 다 된 것이지 잘못된 일이 아니다. 위험색·경고색을 쓰지 않는다.
    // 알 수 없는 상태도 같은 중립 모양.
    _ => _neutralStyle,
  };
}

const _neutralStyle = neutralTagStyle;

/// 무효 모양(상태 칩·결과 라벨 공용). 면 없음·점선·흐린 글자로 다른 결과보다 약하게 보인다.
const voidedResultTagStyle = AppTagStyle(
  fill: Colors.transparent,
  textColor: AppPalette.inkMuted,
  borderColor: AppPalette.inkMuted,
  dashed: true,
);

/// 결과 라벨 모양(redesign design.md 5.3 "결과"). 서버가 정한 결과 키로 고른다.
///
/// 종료·미결은 결과가 아니라 상태다(`battleStatusTagStyle`). 기록 목록과 결과 배너에 올라오는
/// 결과는 승·패·무·무효 넷뿐이라 그 넷만 매핑한다.
AppTagStyle resultTagStyle(BattleResult result) {
  return switch (result) {
    // 가장 강한 결과. 유일하게 떠 있다(2dp ink 두께).
    BattleResult.win => const AppTagStyle(
        fill: AppPalette.amber,
        textColor: AppPalette.ink,
        raised: true,
      ),
    BattleResult.loss => const AppTagStyle(
        fill: AppPalette.inkMuted,
        textColor: AppPalette.surface,
      ),
    // 무승부는 잘못된 일이 아니다. 위험색을 쓰지 않는다.
    BattleResult.draw => _neutralStyle,
    BattleResult.voided => voidedResultTagStyle,
  };
}

/// 유형을 뜻하는 강조색(속도전 앰버 / 품질전 민트). 배지의 색 칸과 모집 카드 왼쪽 색 띠가
/// **같은 규칙**을 써야 하므로 매핑은 여기 한 곳에만 둔다.
Color battleTypeAccent(String type) {
  return type == 'speed' ? AppPalette.amber : AppPalette.mint;
}

/// 유형 배지. 왼쪽 24×24 색 칸(속도전 앰버 / 품질전 민트) 안 16dp 아이콘(번개 / 인장 리본) + 글자.
/// 색을 구분하지 못해도 아이콘과 글자로 구분된다.
///
/// 테두리가 없다(recruit-list-scan.md S3, 2026-11-02 오너 승인 — redesign에서도 유지). 유형은 위계 3위이고
/// 테두리를 벗어도 색 칸·아이콘·글자로 식별된다. **전 화면 공용**이다 — 화면별 변형(flat 플래그 등)은
/// 만들지 않는다(이 파일 머리말의 존재 이유).
class BattleTypeBadge extends StatelessWidget {
  const BattleTypeBadge({super.key, required this.type});

  final String type;

  @override
  Widget build(BuildContext context) {
    final isSpeed = type == 'speed';

    return Container(
      constraints: const BoxConstraints(minHeight: 24),
      // 면색은 남긴다(surface가 아닌 면 위에 놓여도 칩 모양을 잃지 않는다).
      decoration: const ShapeDecoration(
        color: AppPalette.surface,
        shape: DepthBorder(radius: 8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: ShapeDecoration(
              color: battleTypeAccent(type),
              shape: const DepthBorder(radius: 6),
            ),
            alignment: Alignment.center,
            child: Icon(
              isSpeed ? AppIcons.speed : AppIcons.quality,
              size: 16,
              color: AppPalette.ink,
            ),
          ),
          const SizedBox(width: 6),
          KeepWordsText(
            battleTypeLabel(type),
            style: Theme.of(context).textTheme.labelMedium!.copyWith(color: AppPalette.ink),
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
    return AppTag(label: battleStatusLabel(status), style: battleStatusTagStyle(status));
  }
}

/// 결과 라벨(승/패/무/무효). small은 전적 목록 오른쪽, large는 결과 배너.
class ResultLabel extends StatelessWidget {
  const ResultLabel.small({super.key, required this.result}) : size = AppTagSize.small;

  const ResultLabel.large({super.key, required this.result}) : size = AppTagSize.large;

  final BattleResult result;
  final AppTagSize size;

  @override
  Widget build(BuildContext context) {
    return AppTag(
      label: battleResultLabel(result),
      style: resultTagStyle(result),
      size: size,
    );
  }
}
