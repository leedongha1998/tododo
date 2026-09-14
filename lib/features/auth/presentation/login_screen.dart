import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/strings.dart';
import '../../../core/theme/app_mark.dart';
import '../../../core/theme/pixel_border.dart';
import '../../../core/theme/pixel_icons.dart';
import '../../../core/theme/retro_palette.dart';
import '../../../core/widgets/pixel_icon.dart';
import '../domain/auth_providers.dart';

/// 게임 타이틀 화면처럼 보이는 로그인. 구성(앱 이름 + 구글 로그인)과 동작은 그대로다.
class LoginScreen extends ConsumerWidget {
  const LoginScreen({super.key});

  Future<void> _signIn(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(authRepositoryProvider).signInWithGoogle();
    } catch (e) {
      debugPrint('signInWithGoogle failed: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(AppStrings.signInFailed)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final title = Theme.of(context).textTheme.displayMedium!;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _AppMark(),
                const SizedBox(height: 24),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    AppStrings.appName,
                    style: title.copyWith(
                      // 흐림 없는 단단한 그림자 — 레트로 바닥 두께와 같은 표현.
                      shadows: const [Shadow(color: RetroPalette.amber, offset: Offset(4, 4))],
                    ),
                  ),
                ),
                const SizedBox(height: 40),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const _BlinkingCursor(),
                    const SizedBox(width: 8),
                    FilledButton(
                      style: FilledButton.styleFrom(minimumSize: const Size(200, 56)),
                      onPressed: () => _signIn(context, ref),
                      child: const Text(AppStrings.googleSignIn),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 런처 아이콘과 같은 16×16 마크를 셀 6dp(= 96dp)로, 주 강조색 계단 사각 위에 그린다.
/// 아이콘을 누르고 앱이 열렸을 때 색과 모양이 이어진다.
class _AppMark extends StatelessWidget {
  const _AppMark();

  static const _cell = 6.0;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: _cell * AppMark.size,
        height: _cell * AppMark.size,
        decoration: const ShapeDecoration(
          color: RetroPalette.primary,
          shape: PixelBorder(side: BorderSide(color: RetroPalette.primary, width: _cell)),
        ),
        child: const CustomPaint(painter: _AppMarkPainter()),
      ),
    );
  }
}

class _AppMarkPainter extends CustomPainter {
  const _AppMarkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / AppMark.size;
    final paint = Paint()..isAntiAlias = false;
    for (var y = 0; y < AppMark.size; y++) {
      for (var x = 0; x < AppMark.size; x++) {
        final color = AppMark.colorOf(AppMark.rows[y][x]);
        if (color == null) continue;
        paint.color = color;
        canvas.drawRect(Rect.fromLTWH(x * cell, y * cell, cell, cell), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_AppMarkPainter oldDelegate) => false;
}

/// 타이틀 화면의 ▶ 커서. 500ms 켜짐/꺼짐, 애니메이션 줄이기면 켜진 채 멈춘다.
class _BlinkingCursor extends StatefulWidget {
  const _BlinkingCursor();

  @override
  State<_BlinkingCursor> createState() => _BlinkingCursorState();
}

class _BlinkingCursorState extends State<_BlinkingCursor> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
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
    final still = MediaQuery.disableAnimationsOf(context);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => Opacity(
        opacity: still || _controller.value < 0.5 ? 1 : 0,
        child: child,
      ),
      child: const PixelIcon(PixelIcons.cursor, size: 24, color: RetroPalette.ink),
    );
  }
}
