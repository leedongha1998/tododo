import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/keep_words_text.dart';

/// 선택 타일 한 칸에 들어갈 것(design-judging-buttons 1A.2).
///
/// 머리는 셋 중 하나다: 아이콘 40([icon] + [iconColor]) / 이니셜 배지 40([badge]) /
/// 사진 썸네일 높이 96([thumbnail], 그 왼쪽 위에 [badge]가 겹친다).
class JudgmentChoiceOption<T extends Object> {
  const JudgmentChoiceOption({
    required this.value,
    required this.label,
    this.icon,
    this.iconColor,
    this.badge,
    this.thumbnail,
  });

  /// 서버로 보낼 값. 화면은 이 값을 해석하지 않는다.
  final T value;

  /// `strings.dart` 원문. 낭독 라벨도 이것이다.
  final String label;
  final IconData? icon;
  final Color? iconColor;
  final Widget? badge;
  final Widget? thumbnail;
}

/// 상호 판정의 정해진 선택지 두 칸. 두 판정 질문이 같이 쓴다.
///
/// - 아무것도 고르지 않은 상태로 시작한다(기본값을 두면 실수로 보낼 수 있다).
/// - 두 칸은 가로 1:1, 사이 8, 높이를 같게 맞춘다(긴 라벨 쪽).
/// - 칸 안쪽 폭에 가장 긴 **어절**이 안 들어가면 위아래로 쌓는다 — 라벨이 어절 안에서 끊기지 않게.
class JudgmentChoicePair<T extends Object> extends StatelessWidget {
  const JudgmentChoicePair({
    super.key,
    required this.choices,
    required this.selected,
    required this.onSelected,
  });

  final List<JudgmentChoiceOption<T>> choices;
  final T? selected;

  /// null이면 고를 수 없다(보내는 중).
  final ValueChanged<T>? onSelected;

  /// 두 칸 사이.
  static const gap = 8.0;

  /// 라벨 말고 한 칸이 가로로 차지하는 폭: 좌우 안쪽 12 × 2 + 선택 테두리 2 × 2.
  static const cellChrome = 12.0 * 2 + 2.0 * 2;

  @override
  Widget build(BuildContext context) {
    final labelStyle = Theme.of(context).textTheme.labelLarge;
    final scaler = MediaQuery.textScalerOf(context);
    final widestWord = [
      for (final choice in choices)
        widestWordWidth(choice.label, style: labelStyle, textScaler: scaler),
    ].reduce(math.max);

    return LayoutBuilder(
      builder: (context, constraints) {
        final cellRoom =
            (constraints.maxWidth - gap * (choices.length - 1)) / choices.length - cellChrome;
        final tiles = [
          for (final choice in choices)
            JudgmentChoiceTile(
              option: choice,
              selected: choice.value == selected,
              onTap: onSelected == null ? null : () => onSelected!(choice.value),
            ),
        ];

        if (widestWord > cellRoom) {
          return Column(
            key: const ValueKey('judgment-choice-stacked'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < tiles.length; i++) ...[
                if (i > 0) const SizedBox(height: gap),
                tiles[i],
              ],
            ],
          );
        }
        return IntrinsicHeight(
          key: const ValueKey('judgment-choice-row'),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < tiles.length; i++) ...[
                if (i > 0) const SizedBox(width: gap),
                Expanded(child: tiles[i]),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// 선택 타일 한 칸(design-judging-buttons 1A.2).
///
/// | 상태 | 면 | 테두리 | 그 밖 |
/// |---|---|---|---|
/// | 미선택 | surface | 1.5dp outline | 라벨 ink |
/// | 누르는 동안 | sunken(즉시, 뗄 때 120ms) | 그대로 | 두께 없음 |
/// | 선택 | primaryPale | 2dp primary | 오른쪽 위 체크 배지 24 |
/// | 보내는 중의 미선택 칸 | sunken | 1.5dp line | 아이콘·라벨 inkDisabled(이니셜·사진은 그대로) |
///
/// 고르지 않은 쪽을 흐리게 하지 않는다 — 흐리면 비활성으로 읽혀 바꿀 수 없다고 오해한다.
/// 선택을 색에만 기대지 않는다: 테두리 굵기 1.5 → 2 + 체크 배지.
class JudgmentChoiceTile extends StatefulWidget {
  const JudgmentChoiceTile({
    super.key,
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final JudgmentChoiceOption<Object> option;
  final bool selected;

  /// null이면 누를 수 없다(보내는 중).
  final VoidCallback? onTap;

  static const minHeight = 104.0;
  static const radius = 16.0;
  static const padding = EdgeInsets.fromLTRB(12, 16, 12, 14);
  static const leadingSize = 40.0;
  static const thumbnailHeight = 96.0;
  static const checkBadgeSize = 24.0;
  static const checkBadgeInset = 6.0;
  static const releaseDuration = Duration(milliseconds: 120);

  @override
  State<JudgmentChoiceTile> createState() => _JudgmentChoiceTileState();
}

class _JudgmentChoiceTileState extends State<JudgmentChoiceTile> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  void didUpdateWidget(JudgmentChoiceTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.onTap == null) _pressed = false;
  }

  @override
  Widget build(BuildContext context) {
    final option = widget.option;
    final selected = widget.selected;
    final enabled = widget.onTap != null;
    final dimmed = !enabled && !selected;

    final Color face;
    final BorderSide side;
    if (_pressed) {
      face = AppPalette.sunken;
    } else if (selected) {
      face = AppPalette.primaryPale;
    } else if (dimmed) {
      face = AppPalette.sunken;
    } else {
      face = AppPalette.surface;
    }
    if (selected) {
      side = const BorderSide(color: AppPalette.primary, width: 2);
    } else if (dimmed) {
      side = const BorderSide(color: AppPalette.line, width: 1.5);
    } else {
      side = const BorderSide(color: AppPalette.outline, width: 1.5);
    }
    final contentColor = dimmed ? AppPalette.inkDisabled : AppPalette.ink;

    // 누를 때는 즉시, 뗄 때만 되돌아온다(애니메이션 줄이기면 즉시).
    final duration = _pressed || MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : JudgmentChoiceTile.releaseDuration;

    final tile = AnimatedContainer(
      duration: duration,
      curve: Curves.easeOutCubic,
      constraints: const BoxConstraints(minHeight: JudgmentChoiceTile.minHeight),
      decoration: ShapeDecoration(
        color: face,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(Radius.circular(JudgmentChoiceTile.radius)),
          side: side,
        ),
      ),
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          Padding(
            padding: JudgmentChoiceTile.padding,
            child: Align(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _leading(option, dimmed),
                  const SizedBox(height: 8),
                  KeepWordsText(
                    option.label,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelLarge!.copyWith(color: contentColor),
                  ),
                ],
              ),
            ),
          ),
          if (selected)
            const Positioned(
              top: JudgmentChoiceTile.checkBadgeInset,
              right: JudgmentChoiceTile.checkBadgeInset,
              child: _CheckBadge(),
            ),
        ],
      ),
    );

    return Semantics(
      container: true,
      button: true,
      inMutuallyExclusiveGroup: true,
      selected: selected,
      enabled: enabled,
      label: option.label,
      onTap: widget.onTap,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => _setPressed(true) : null,
        onTapUp: enabled ? (_) => _setPressed(false) : null,
        onTapCancel: enabled ? () => _setPressed(false) : null,
        onTap: widget.onTap,
        child: tile,
      ),
    );
  }

  Widget _leading(JudgmentChoiceOption<Object> option, bool dimmed) {
    final thumbnail = option.thumbnail;
    final badge = option.badge;
    if (thumbnail != null) {
      return SizedBox(
        height: JudgmentChoiceTile.thumbnailHeight,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            thumbnail,
            if (badge != null) Positioned(top: 4, left: 4, child: badge),
          ],
        ),
      );
    }
    if (badge != null) return badge;
    final icon = option.icon;
    if (icon == null) return const SizedBox.shrink();
    return Icon(
      icon,
      size: JudgmentChoiceTile.leadingSize,
      color: dimmed ? AppPalette.inkDisabled : option.iconColor,
    );
  }
}

/// 선택 칸 오른쪽 위 체크 배지: 지름 24 primary 원 + 흰 체크 16.
class _CheckBadge extends StatelessWidget {
  const _CheckBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('judgment-choice-check'),
      width: JudgmentChoiceTile.checkBadgeSize,
      height: JudgmentChoiceTile.checkBadgeSize,
      decoration: const ShapeDecoration(color: AppPalette.primary, shape: CircleBorder()),
      alignment: Alignment.center,
      child: const Icon(AppIcons.check, size: 16, color: AppPalette.surface),
    );
  }
}
