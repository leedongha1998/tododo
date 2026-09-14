import 'package:flutter/material.dart';

import '../theme/pixel_icons.dart';
import '../theme/retro_palette.dart';
import 'pixel_icon.dart';
import 'pixel_loader.dart';

enum _StatusKind { loading, empty, error }

/// 로딩·빈·오류 상태를 한 모양으로(design.md 3.2).
/// 아이콘 36(또는 로더) + 문장(본문 글꼴, 가운데) + 보조 문장 + 동작 버튼 하나.
/// [fill]이면 화면 가운데, 아니면 영역 안에서 세로 여백 12.
class StatusMessage extends StatelessWidget {
  const StatusMessage.loading({
    super.key,
    this.message,
    this.detail,
    this.fill = false,
  })  : _kind = _StatusKind.loading,
        icon = null,
        action = null;

  const StatusMessage.empty({
    super.key,
    required String this.message,
    this.icon,
    this.detail,
    this.action,
    this.fill = false,
  }) : _kind = _StatusKind.empty;

  const StatusMessage.error({
    super.key,
    required String this.message,
    this.detail,
    this.action,
    this.fill = false,
  })  : _kind = _StatusKind.error,
        icon = PixelIcons.warning;

  final String? message;
  final String? detail;
  final PixelIconData? icon;
  final Widget? action;
  final bool fill;
  final _StatusKind _kind;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final message = this.message;
    final detail = this.detail;
    final icon = this.icon;

    final body = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_kind == _StatusKind.loading)
          const PixelLoader.medium()
        else if (icon != null)
          PixelIcon(icon, size: 36, color: RetroPalette.ink),
        if (message != null) ...[
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center, style: textTheme.bodyMedium),
        ],
        if (detail != null) ...[
          const SizedBox(height: 4),
          Text(
            detail,
            textAlign: TextAlign.center,
            style: textTheme.bodySmall!.copyWith(color: RetroPalette.inkMuted),
          ),
        ],
        if (action != null) ...[
          const SizedBox(height: 12),
          action!,
        ],
      ],
    );

    if (fill) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: body,
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(child: body),
    );
  }
}
