import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/strings.dart';
import '../../../core/theme/app_mark.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/depth_border.dart';
import '../../../core/widgets/keep_words_text.dart';
import '../domain/auth_providers.dart';

/// 로그인(redesign design 9.4). 구성(마크 + 앱 이름 + 구글 로그인)과 동작은 그대로다.
/// 반복 움직임이 없다(옛 ▶ 깜빡이는 커서는 오너 결정 4로 없앴다).
class LoginScreen extends ConsumerWidget {
  const LoginScreen({super.key});

  Future<void> _signIn(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(authRepositoryProvider).signInWithGoogle();
    } catch (e) {
      debugPrint('signInWithGoogle failed: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: KeepWordsText(AppStrings.signInFailed)),
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
                  child: KeepWordsText(AppStrings.appName, style: title),
                ),
                const SizedBox(height: 40),
                FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size(240, 56)),
                  onPressed: () => _signIn(context, ref),
                  child: const KeepWordsText(AppStrings.googleSignIn),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 런처 아이콘과 같은 마크(design 7.1)를 112dp 브랜드 둥근 사각(모서리 28) + 4dp ink 두께 위에 그린다.
/// 아이콘을 누르고 앱이 열렸을 때 색과 모양이 이어진다.
class _AppMark extends StatelessWidget {
  const _AppMark();

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: 112,
        height: 112,
        decoration: const ShapeDecoration(
          color: AppPalette.primary,
          shape: DepthBorder(radius: 28, depth: 4, depthColor: AppPalette.ink),
        ),
        // 두께를 뺀 면(112 × 108) 가운데 마크 상자 72dp.
        child: const Center(
          child: SizedBox.square(dimension: 72, child: CustomPaint(painter: _AppMarkPainter())),
        ),
      ),
    );
  }
}

class _AppMarkPainter extends CustomPainter {
  const _AppMarkPainter();

  @override
  void paint(Canvas canvas, Size size) => AppMark.paint(canvas, Offset.zero & size);

  @override
  bool shouldRepaint(_AppMarkPainter oldDelegate) => false;
}
