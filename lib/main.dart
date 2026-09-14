import 'package:flutter/foundation.dart' show LicenseEntryWithLineBreaks, LicenseRegistry;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/strings.dart';
import 'core/supabase/supabase_env.dart';
import 'core/supabase/supabase_init.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/presentation/auth_gate.dart';

/// 시스템 글꼴 크기를 따르되 이 배율에서 멈춘다. 1.5부터는 360dp 폭에서 탭 이름이 칸을 넘는다.
const maxTextScale = 1.3;

/// 번들한 갈무리 글꼴의 OFL 1.1 원문(배포 zip의 파일 이름 그대로).
const galmuriLicenseAsset = 'assets/fonts/galmuri/LICENSE.txt';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // OFL 폰트는 앱 안 오픈소스 라이선스 화면에 고지해야 한다. pub 패키지 라이선스와 함께 보인다.
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(
      const ['Galmuri'],
      await rootBundle.loadString(galmuriLicenseAsset),
    );
  });
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
