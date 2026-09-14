import 'package:flutter/widgets.dart';

import '../strings.dart';
import '../theme/retro_palette.dart';

enum PixelLoaderSize { small, medium }

/// 사각형 3개가 150ms마다 하나씩 켜지는 로딩 표시. Material 원형 스피너를 대신한다.
/// 애니메이션 줄이기가 켜져 있으면 셋 다 켜진 채 멈춘다.
class PixelLoader extends StatefulWidget {
  const PixelLoader.small({super.key}) : size = PixelLoaderSize.small;

  const PixelLoader.medium({super.key}) : size = PixelLoaderSize.medium;

  final PixelLoaderSize size;

  /// 한 칸이 켜져 있는 시간.
  static const step = Duration(milliseconds: 150);

  @override
  State<PixelLoader> createState() => _PixelLoaderState();
}

class _PixelLoaderState extends State<PixelLoader> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: PixelLoader.step * 3,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isSmall = widget.size == PixelLoaderSize.small;
    final square = isSmall ? 6.0 : 8.0;
    final gap = isSmall ? 3.0 : 4.0;
    final height = isSmall ? 12.0 : 16.0;
    final still = MediaQuery.disableAnimationsOf(context);

    return Semantics(
      label: AppStrings.loading,
      child: SizedBox(
        height: height,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final active = (_controller.value * 3).floor().clamp(0, 2);
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < 3; i++) ...[
                  if (i > 0) SizedBox(width: gap),
                  SizedBox(
                    width: square,
                    height: square,
                    child: ColoredBox(
                      color: still || i == active ? RetroPalette.ink : RetroPalette.line,
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
