import 'package:flutter/material.dart';

import '../theme/pixel_border.dart';
import '../theme/pixel_icons.dart';
import '../theme/retro_palette.dart';
import '../theme/retro_text.dart';
import 'pixel_icon.dart';

enum _FrameVariant { raised, flat, inset, tone }

/// 안내 블록의 성격.
enum PixelTone { info, success, danger, neutral }

/// "무언가를 감싸는" 영역(design.md 3.2).
///
/// - raised: surface + 2dp ink + 바닥 두께 — 카드, 상대 카드, 결과 배너 바탕
/// - flat: surface + 2dp ink — 섹션 묶음, 기준 목록 블록
/// - inset: sunken 면, 테두리 없음 — 인용된 텍스트, 완료한 할 일처럼 가라앉은 것
/// - tone: 문장이 들어가는 강조 블록(info / success / danger / neutral)
///
/// [title]이 있으면 위쪽에 ink 띠 + surface 픽셀 글자로 창 제목 띠를 그린다.
/// [onTap]이 있으면 누르는 동안 눌림 변형(바닥 두께가 위·왼쪽으로)이 된다.
class PixelFrame extends StatefulWidget {
  const PixelFrame.raised({
    super.key,
    required this.child,
    this.title,
    this.onTap,
    this.padding = const EdgeInsets.all(12),
  })  : _variant = _FrameVariant.raised,
        tone = null,
        icon = null;

  const PixelFrame.flat({
    super.key,
    required this.child,
    this.title,
    this.onTap,
    this.padding = const EdgeInsets.all(12),
  })  : _variant = _FrameVariant.flat,
        tone = null,
        icon = null;

  const PixelFrame.inset({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(12),
  })  : _variant = _FrameVariant.inset,
        title = null,
        tone = null,
        icon = null;

  /// [icon]을 주지 않으면 성격별 기본 아이콘(info → info, success → pass, danger → warning,
  /// neutral → 없음)을 쓴다.
  const PixelFrame.tone({
    super.key,
    required PixelTone this.tone,
    required this.child,
    this.title,
    this.icon,
    this.padding = const EdgeInsets.all(12),
  })  : _variant = _FrameVariant.tone,
        onTap = null;

  final Widget child;
  final String? title;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final PixelTone? tone;
  final PixelIconData? icon;
  final _FrameVariant _variant;

  @override
  State<PixelFrame> createState() => _PixelFrameState();
}

class _PixelFrameState extends State<PixelFrame> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final (Color fill, BorderSide side, double depth) = switch (widget._variant) {
      _FrameVariant.raised => (
          RetroPalette.surface,
          const BorderSide(color: RetroPalette.ink, width: 2),
          2.0,
        ),
      _FrameVariant.flat => (
          RetroPalette.surface,
          const BorderSide(color: RetroPalette.ink, width: 2),
          0.0,
        ),
      _FrameVariant.inset => (RetroPalette.sunken, BorderSide.none, 0.0),
      _FrameVariant.tone => switch (widget.tone!) {
          PixelTone.info => (
              RetroPalette.primaryPale,
              const BorderSide(color: RetroPalette.primary, width: 2),
              0.0,
            ),
          PixelTone.success => (
              RetroPalette.surface,
              const BorderSide(color: RetroPalette.success, width: 2),
              0.0,
            ),
          PixelTone.danger => (
              RetroPalette.dangerPale,
              const BorderSide(color: RetroPalette.danger, width: 2),
              0.0,
            ),
          PixelTone.neutral => (
              RetroPalette.sunken,
              const BorderSide(color: RetroPalette.inkMuted, width: 2),
              0.0,
            ),
        },
    };

    final title = widget.title;
    final content = widget._variant == _FrameVariant.tone ? _toneContent(context) : widget.child;

    Widget frame = Container(
      decoration: ShapeDecoration(
        color: fill,
        shape: PixelBorder(side: side, depth: depth, pressed: _pressed),
      ),
      foregroundDecoration: _pressed
          ? BoxDecoration(color: RetroPalette.ink.withValues(alpha: 0.12))
          : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null && widget._variant != _FrameVariant.tone)
            ColoredBox(
              color: RetroPalette.ink,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Text(
                  title,
                  style: RetroText.pixel(RetroText.grid, bold: true, color: RetroPalette.surface),
                ),
              ),
            ),
          // 면을 장식으로 칠하므로 안에 든 ListTile·InkWell이 겹침 색을 그릴 Material을 따로 둔다.
          Material(
            type: MaterialType.transparency,
            child: Padding(padding: widget.padding, child: content),
          ),
        ],
      ),
    );

    final onTap = widget.onTap;
    if (onTap != null) {
      frame = Semantics(
        button: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => _setPressed(true),
          onTapUp: (_) => _setPressed(false),
          onTapCancel: () => _setPressed(false),
          onTap: onTap,
          child: frame,
        ),
      );
    }
    return frame;
  }

  Widget _toneContent(BuildContext context) {
    final icon = widget.icon ??
        switch (widget.tone!) {
          PixelTone.info => PixelIcons.info,
          PixelTone.success => PixelIcons.pass,
          PixelTone.danger => PixelIcons.warning,
          PixelTone.neutral => null,
        };
    final iconColor = switch (widget.tone!) {
      PixelTone.info => RetroPalette.primary,
      PixelTone.success => RetroPalette.success,
      PixelTone.danger => RetroPalette.danger,
      PixelTone.neutral => RetroPalette.ink,
    };
    final title = widget.title;
    final textTheme = Theme.of(context).textTheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (icon != null) ...[
          PixelIcon(icon, size: 24, color: iconColor),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: DefaultTextStyle.merge(
            style: textTheme.bodyMedium!.copyWith(color: RetroPalette.ink),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (title != null) ...[
                  Text(title, style: RetroText.pixel(RetroText.grid, bold: true)),
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
