import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthState;

import '../../../core/strings.dart';
import '../../../core/theme/app_mark.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/depth_border.dart';
import '../../../core/widgets/keep_words_text.dart';
import '../domain/auth_providers.dart';
import '../domain/sign_in_failure.dart';

/// 로그인(redesign design 9.4, kakao-login design 1.1). 마크 + 앱 이름 + 구글·카카오 버튼 + 계정 안내 한 줄.
/// 반복 움직임이 없다(옛 ▶ 깜빡이는 커서는 오너 결정 4로 없앴다).
class LoginScreen extends ConsumerWidget {
  const LoginScreen({super.key});

  /// 브라우저를 띄우는 단계의 실패. 구글·카카오가 같은 토스트를 쓴다.
  Future<void> _signIn(
    BuildContext context,
    String label,
    Future<void> Function() signIn,
  ) async {
    try {
      await signIn();
    } catch (e) {
      debugPrint('$label failed: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: KeepWordsText(AppStrings.signInFailed)),
        );
      }
    }
  }

  /// 브라우저에서 돌아온 **뒤의** 실패(kakao-login design 흐름 2, 오너 확정 1번 — 구글·카카오 공통).
  ///
  /// 위 `_signIn`의 토스트는 브라우저를 띄우지 못했을 때만 뜬다. 돌아온 딥링크의 오류(코드 교환 실패·
  /// 네트워크 등)는 `authStateProvider`에 오류로 들어오고, 예전에는 `AuthGate`가 `debugPrint`만 남겨
  /// 사용자는 아무 말 없이 로그인 화면에 남았다. 취소·동의 거부는 사용자가 한 일이라 알리지 않는다.
  ///
  /// 이 화면은 `AuthGate`의 data(세션 없음)·error 두 갈래에서 같은 자리·같은 타입이라 같은 element로
  /// 남으므로, 여기서 듣는 리스너가 오류 전이를 받는다.
  void _onAuthStateChanged(BuildContext context, AsyncValue<AuthState> next) {
    if (next.isLoading) return;
    final error = next.error;
    if (error == null) return;
    if (isOAuthCancellation(error)) {
      debugPrint('signIn cancelled by user: $error');
      return;
    }
    debugPrint('signIn callback failed: $error');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: KeepWordsText(AppStrings.signInFailed)),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final title = Theme.of(context).textTheme.displayMedium!;
    ref.listen(authStateProvider, (previous, next) => _onAuthStateChanged(context, next));

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
                  onPressed: () => _signIn(
                    context,
                    'signInWithGoogle',
                    ref.read(authRepositoryProvider).signInWithGoogle,
                  ),
                  child: const KeepWordsText(AppStrings.googleSignIn),
                ),
                const SizedBox(height: 12),
                // 심볼(공식 PNG)은 오너가 카카오 디자인 가이드에서 받아 넣은 뒤 붙인다(plan 2차분) —
                // 손으로 그린 근사 심볼은 쓰지 않는다(design 1.1).
                FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(240, 56),
                    backgroundColor: AppPalette.kakaoContainer,
                    foregroundColor: AppPalette.kakaoLabel,
                  ),
                  onPressed: () => _signIn(
                    context,
                    'signInWithKakao',
                    ref.read(authRepositoryProvider).signInWithKakao,
                  ),
                  child: const KeepWordsText(AppStrings.kakaoSignIn),
                ),
                const SizedBox(height: 16),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 280),
                  child: KeepWordsText(
                    AppStrings.signInAccountsNotLinked,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
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
