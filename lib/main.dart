import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/strings.dart';
import 'core/supabase/supabase_env.dart';
import 'core/supabase/supabase_init.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/presentation/auth_gate.dart';

/// 시스템 글꼴 크기를 따르되 이 배율에서 멈춘다. 1.5부터는 360dp 폭에서 탭 이름이 칸을 넘는다.
const maxTextScale = 1.3;

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
      // 다크 모드 없음. 기기가 다크 모드여도 같은 라이트 테마로 보인다.
      themeMode: ThemeMode.light,
      builder: (context, child) => MediaQuery.withClampedTextScaling(
        maxScaleFactor: maxTextScale,
        child: child!,
      ),
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
