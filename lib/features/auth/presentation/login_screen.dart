import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/strings.dart';
import '../domain/auth_providers.dart';

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
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(AppStrings.appName, style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: () => _signIn(context, ref),
              child: const Text(AppStrings.googleSignIn),
            ),
          ],
        ),
      ),
    );
  }
}
