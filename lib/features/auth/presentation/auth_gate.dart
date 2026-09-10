import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/navigation/main_shell.dart';
import '../domain/auth_providers.dart';
import 'login_screen.dart';

/// 로그인 상태에 따라 화면을 분기한다. 로그인하면 탭바가 있는 본 화면으로 들어간다.
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);

    return authState.when(
      data: (state) {
        return state.session == null ? const LoginScreen() : const MainShell();
      },
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, stackTrace) {
        debugPrint('authStateProvider error: $error');
        return const LoginScreen();
      },
    );
  }
}
