import 'package:flutter/material.dart';

import '../theme/app_icons.dart';
import '../theme/app_palette.dart';
import 'app_loader.dart';
import 'keep_words_text.dart';

enum _StatusKind { loading, empty, error }

/// 로딩·빈·오류 상태를 한 모양으로(redesign design.md 5.2).
/// 아이콘 40(빈 상태 inkMuted, 오류 danger — 또는 로더) + 문장(`bodyMedium`, 가운데) + 보조 문장
/// (`bodySmall` inkMuted) + 동작 버튼 하나. 요소 사이 간격 12.
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
        icon = AppIcons.warning;

  final String? message;
  final String? detail;
  final IconData? icon;
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
          const AppLoader.medium()
        else if (icon != null)
          Icon(
            icon,
            size: 40,
            color: _kind == _StatusKind.error
                ? AppPalette.danger
                : AppPalette.inkMuted,
          ),
        if (message != null) ...[
          const SizedBox(height: 12),
          KeepWordsText(message, textAlign: TextAlign.center, style: textTheme.bodyMedium),
        ],
        if (detail != null) ...[
          const SizedBox(height: 12),
          KeepWordsText(
            detail,
            textAlign: TextAlign.center,
            style: textTheme.bodySmall!.copyWith(color: AppPalette.inkMuted),
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
