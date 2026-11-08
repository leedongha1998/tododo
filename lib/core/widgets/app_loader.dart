import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../strings.dart';
import '../theme/app_palette.dart';

enum AppLoaderSize { small, medium }

/// 둥근 점 3개가 부드러운 투명도 물결로 깜빡이는 로딩 표시(design 5.2). Material 원형 스피너를 대신한다.
/// small: 점 6dp·간격 4 / medium: 점 8dp·간격 6. 색은 `inkMuted` ↔ `line`, 900ms 주기.
/// 애니메이션 줄이기가 켜져 있으면 셋 다 `inkMuted`로 켜진 채 멈춘다(티커도 멈춘다).
class AppLoader extends StatefulWidget {
  const AppLoader.small({super.key}) : size = AppLoaderSize.small;

  const AppLoader.medium({super.key}) : size = AppLoaderSize.medium;

  final AppLoaderSize size;

  /// 물결 한 바퀴.
  static const period = Duration(milliseconds: 900);

  @override
  State<AppLoader> createState() => _AppLoaderState();
}

class _AppLoaderState extends State<AppLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppLoader.period,
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

  /// 점 [index]의 진하기(0 = line, 1 = inkMuted). 점마다 1/3 주기씩 늦게 오는 코사인 물결.
  static double _intensity(double t, int index) {
    final phase = (t - index / 3) * 2 * math.pi;
    return (1 + math.cos(phase)) / 2;
  }

  @override
  Widget build(BuildContext context) {
    final isSmall = widget.size == AppLoaderSize.small;
    final dot = isSmall ? 6.0 : 8.0;
    final gap = isSmall ? 4.0 : 6.0;
    final height = isSmall ? 12.0 : 16.0;
    final still = MediaQuery.disableAnimationsOf(context);

    return Semantics(
      label: AppStrings.loading,
      child: SizedBox(
        height: height,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < 3; i++) ...[
                  if (i > 0) SizedBox(width: gap),
                  Container(
                    width: dot,
                    height: dot,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: still
                          ? AppPalette.inkMuted
                          : Color.lerp(
                              AppPalette.line,
                              AppPalette.inkMuted,
                              _intensity(_controller.value, i),
                            ),
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
