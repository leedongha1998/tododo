import 'package:flutter/material.dart';

import '../../../core/strings.dart';

/// 대결 카드, 대결 상세, 전적 목록이 유형과 상태를 같은 모양으로 보여주기 위한 공용 조각.
/// 세 곳이 각자 다르게 그리면 같은 상태가 화면마다 달라 보인다.

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
    default:
      return status;
  }
}

/// 유형 배지. 속도전은 번개, 품질전은 인증 표시로 성격을 드러낸다.
class BattleTypeBadge extends StatelessWidget {
  const BattleTypeBadge({super.key, required this.type});

  final String type;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isSpeed = type == 'speed';
    final color = isSpeed ? scheme.primary : scheme.tertiary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(isSpeed ? Icons.bolt : Icons.verified_outlined, size: 14, color: color),
          const SizedBox(width: 2),
          Text(
            battleTypeLabel(type),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

/// 진행중/판정중/종료/미결을 색으로도 구분한다. 문장만으로는 지금 상태가 눈에 안 들어온다.
class BattleStatusChip extends StatelessWidget {
  const BattleStatusChip({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (Color background, Color foreground) = switch (status) {
      'active' => (scheme.primaryContainer, scheme.onPrimaryContainer),
      'judging' => (scheme.tertiaryContainer, scheme.onTertiaryContainer),
      'finished' => (scheme.secondaryContainer, scheme.onSecondaryContainer),
      'disputed' => (scheme.errorContainer, scheme.onErrorContainer),
      _ => (scheme.surfaceContainerHighest, scheme.onSurfaceVariant),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        battleStatusLabel(status),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(color: foreground),
      ),
    );
  }
}
