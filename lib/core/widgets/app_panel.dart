import 'package:flutter/material.dart';

import '../theme/app_icons.dart';
import '../theme/app_palette.dart';
import '../theme/depth_border.dart';

enum _PanelVariant { raised, flat, inset, tone }

/// 안내 블록의 성격.
enum AppTone { info, success, danger, neutral }

/// "무언가를 감싸는" 영역(`docs/specs/redesign/design.md` 5.2).
///
/// - raised: surface + 1dp line + 2dp edge 아래 두께 — 카드, 상대 카드, 모집 카드, 승리 배너
/// - flat: surface + 1dp line — 섹션 묶음, 기준 목록 블록
/// - inset: sunken 면, 테두리 없음 — 인용된 텍스트, 완료한 할 일처럼 가라앉은 것
/// - tone: 문장이 들어가는 안내 블록(info / success / danger / neutral). 연한 면, 테두리 없음, 왼쪽 아이콘
///
/// 모서리는 16(tone은 12). [title]이 있으면 묶음 안 첫 줄에 `titleSmall` ink 제목을 둔다(옛 창 제목 띠 없음).
/// [onTap]이 있으면 누르는 동안 면이 두께만큼 내려온다 — 누를 때 즉시, 뗄 때 120ms `easeOutCubic`
/// (애니메이션 줄이기면 즉시). 물결은 그리지 않는다.
class AppPanel extends StatefulWidget {
  const AppPanel.raised({
    super.key,
    required this.child,
    this.title,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
  }) : _variant = _PanelVariant.raised,
       tone = null,
       icon = null;

  const AppPanel.flat({
    super.key,
    required this.child,
    this.title,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
  }) : _variant = _PanelVariant.flat,
       tone = null,
       icon = null;

  const AppPanel.inset({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
  }) : _variant = _PanelVariant.inset,
       title = null,
       tone = null,
       icon = null;

  /// [icon]을 주지 않으면 성격별 기본 아이콘(info → info, success → pass, danger → warning,
  /// neutral → 없음)을 쓴다.
  const AppPanel.tone({
    super.key,
    required AppTone this.tone,
    required this.child,
    this.title,
    this.icon,
    this.padding = const EdgeInsets.all(16),
  }) : _variant = _PanelVariant.tone,
       onTap = null;

  final Widget child;
  final String? title;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final AppTone? tone;
  final IconData? icon;
  final _PanelVariant _variant;

  /// 손을 뗀 뒤 되돌아오는 길이(design 4.2).
  static const releaseDuration = Duration(milliseconds: 120);

  static const _radius = 16.0;
  static const _toneRadius = 12.0;
  static const _hairline = BorderSide(color: AppPalette.line);

  @override
  State<AppPanel> createState() => _AppPanelState();
}

class _AppPanelState extends State<AppPanel> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final (Color fill, DepthBorder shape) = switch (widget._variant) {
      _PanelVariant.raised => (
        AppPalette.surface,
        DepthBorder(
          side: AppPanel._hairline,
          radius: AppPanel._radius,
          depth: 2,
          depthColor: AppPalette.edge,
          pressed: _pressed,
        ),
      ),
      _PanelVariant.flat => (
        AppPalette.surface,
        const DepthBorder(side: AppPanel._hairline, radius: AppPanel._radius),
      ),
      _PanelVariant.inset => (
        AppPalette.sunken,
        const DepthBorder(radius: AppPanel._radius),
      ),
      _PanelVariant.tone => (
        switch (widget.tone!) {
          AppTone.info => AppPalette.primaryPale,
          AppTone.success => AppPalette.successPale,
          AppTone.danger => AppPalette.dangerPale,
          AppTone.neutral => AppPalette.sunken,
        },
        const DepthBorder(radius: AppPanel._toneRadius),
      ),
    };

    final title = widget.title;
    final isTone = widget._variant == _PanelVariant.tone;
    final content = isTone ? _toneContent(context) : widget.child;

    Widget panel = AnimatedContainer(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : AppPanel.releaseDuration,
      curve: Curves.easeOutCubic,
      decoration: ShapeDecoration(color: fill, shape: shape),
      // 면을 장식으로 칠하므로 안에 든 ListTile·InkWell이 겹침 색을 그릴 Material을 따로 둔다.
      child: Material(
        type: MaterialType.transparency,
        child: Padding(
          padding: widget.padding,
          child: title != null && !isTone
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall!
                          .copyWith(color: AppPalette.ink),
                    ),
                    const SizedBox(height: 12),
                    content,
                  ],
                )
              : content,
        ),
      ),
    );

    final onTap = widget.onTap;
    if (onTap != null) {
      panel = Semantics(
        button: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => _setPressed(true),
          onTapUp: (_) => _setPressed(false),
          onTapCancel: () => _setPressed(false),
          onTap: onTap,
          child: panel,
        ),
      );
    }
    return panel;
  }

  Widget _toneContent(BuildContext context) {
    final icon =
        widget.icon ??
        switch (widget.tone!) {
          AppTone.info => AppIcons.info,
          AppTone.success => AppIcons.pass,
          AppTone.danger => AppIcons.warning,
          AppTone.neutral => null,
        };
    final iconColor = switch (widget.tone!) {
      AppTone.info => AppPalette.primary,
      AppTone.success => AppPalette.success,
      AppTone.danger => AppPalette.danger,
      AppTone.neutral => AppPalette.inkMuted,
    };
    final title = widget.title;
    final textTheme = Theme.of(context).textTheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 24, color: iconColor),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: DefaultTextStyle.merge(
            style: textTheme.bodyMedium!.copyWith(color: AppPalette.ink),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (title != null) ...[
                  Text(
                    title,
                    style: textTheme.titleSmall!.copyWith(
                      color: AppPalette.ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                widget.child,
              ],
            ),
          ),
        ),
      ],
    );
  }
}
