import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/strings.dart';
import '../domain/auth_providers.dart';
import 'login_screen.dart';

/// 로그인 상태에 따라 화면을 분기한다. todo/battle/profile 화면이 붙기 전까지는
/// 로그인 성공 시 임시 placeholder를 보여준다.
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);

    return authState.when(
      data: (state) {
        return state.session == null ? const LoginScreen() : const _SignedInPlaceholder();
      },
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, stackTrace) {
        debugPrint('authStateProvider error: $error');
        return const LoginScreen();
      },
    );
  }
}

class _SignedInPlaceholder extends StatelessWidget {
  const _SignedInPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.appName)),
      body: const Center(child: Text(AppStrings.appName)),
    );
  }
}
