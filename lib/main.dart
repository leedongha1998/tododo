import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/strings.dart';
import 'core/supabase/supabase_env.dart';
import 'core/supabase/supabase_init.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/presentation/auth_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (SupabaseEnv.isConfigured) {
    await initSupabase();
  }
  runApp(const ProviderScope(child: TododuduApp()));
}

class TododuduApp extends StatelessWidget {
  const TododuduApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppStrings.appName,
      theme: AppTheme.light,
      home: SupabaseEnv.isConfigured ? const AuthGate() : const _SupabaseNotConfigured(),
    );
  }
}

class _SupabaseNotConfigured extends StatelessWidget {
  const _SupabaseNotConfigured();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(AppStrings.supabaseNotConfigured, textAlign: TextAlign.center),
        ),
      ),
    );
  }
}
