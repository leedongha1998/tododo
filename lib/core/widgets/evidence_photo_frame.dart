import 'package:flutter/material.dart';

import '../strings.dart';
import '../theme/app_icons.dart';
import '../theme/app_palette.dart';
import '../theme/depth_border.dart';
import 'app_loader.dart';

/// 증거 사진 틀(redesign design.md 5.2, retro-theme 결정 C 승계).
///
/// 바깥 둥근 사각(모서리 12) `sunken` 면 → 안쪽 6dp 여백 → 사진. 사진이 판정 근거라 **원본을 가공하지
/// 않는다**: `BoxFit.contain`(자르지 않음), `filterQuality`는 기본값, 색 필터·축소 디코딩 없음.
/// **사진에 clip을 걸지 않는다** — 여백 6이면 모서리 반지름 12의 곡선 안쪽에 사진 모서리가 들어가므로
/// 둥근 모서리가 사진 픽셀을 깎지 않는다.
///
/// [image]가 null이면 로딩, [failed]면 실패 상태. 사진 디코딩 실패도 같은 실패 상태로 바뀐다.
class EvidencePhotoFrame extends StatelessWidget {
  /// 기존 자리 크기(가로 꽉 참, 높이 160).
  const EvidencePhotoFrame.thumbnail({
    super.key,
    this.image,
    this.failed = false,
    this.onRetry,
  }) : large = false;

  /// 가로 꽉 참, 높이는 사진 비율.
  const EvidencePhotoFrame.large({
    super.key,
    this.image,
    this.failed = false,
    this.onRetry,
  }) : large = true;

  final ImageProvider? image;
  final bool failed;
  final VoidCallback? onRetry;
  final bool large;

  static const thumbnailHeight = 160.0;

  @override
  Widget build(BuildContext context) {
    final image = this.image;
    final Widget content;
    if (failed) {
      content = _failure(context);
    } else if (image == null) {
      content = const Center(child: AppLoader.medium());
    } else {
      content = Image(
        image: image,
        fit: BoxFit.contain,
        width: double.infinity,
        height: large ? null : double.infinity,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return const SizedBox(
            height: thumbnailHeight,
            child: Center(child: AppLoader.medium()),
          );
        },
        errorBuilder: (context, error, stackTrace) {
          debugPrint('evidence image load failed: $error');
          return _failure(context);
        },
      );
    }

    final framed = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(6),
      decoration: const ShapeDecoration(
        color: AppPalette.sunken,
        shape: DepthBorder(radius: 12),
      ),
      child: content,
    );

    if (large && !failed && image != null) return framed;
    return SizedBox(height: thumbnailHeight, width: double.infinity, child: framed);
  }

  Widget _failure(BuildContext context) {
    final onRetry = this.onRetry;
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(AppIcons.brokenImage, size: 40, color: AppPalette.ink),
            const SizedBox(height: 4),
            // 글자가 길거나 커져도 가로로 넘치지 않게 줄바꿈한다.
            Text(
              AppStrings.battleEvidencePhotoLoadFailed,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (onRetry != null)
              TextButton(onPressed: onRetry, child: const Text(AppStrings.retry)),
          ],
        ),
      ),
    );
  }
}
