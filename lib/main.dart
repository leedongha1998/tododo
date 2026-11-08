import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart'
    show LicenseEntryWithLineBreaks, LicenseRegistry, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/strings.dart';
import 'core/supabase/supabase_env.dart';
import 'core/supabase/supabase_init.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/presentation/auth_gate.dart';

/// 시스템 글꼴 크기를 따르되 이 배율에서 멈춘다(redesign design 3.3). 1.5배에서 탭 라벨(labelSmall 12)은
/// 18dp가 되고, 360dp 폭 4칸(칸당 90dp)에 가장 긴 "대결 찾기"가 약 72dp로 들어간다 — 육안 확인 대상.
const maxTextScale = 1.5;

/// 번들한 Pretendard 글꼴의 OFL 1.1 원문(npm 패키지 dist/LICENSE.txt 그대로).
const pretendardLicenseAsset = 'assets/fonts/pretendard/LICENSE.txt';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // OFL 글꼴(Pretendard)은 앱 안 오픈소스 라이선스 화면에 고지해야 한다. pub 패키지 라이선스와 함께 보인다.
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(
      const ['Pretendard'],
      await rootBundle.loadString(pretendardLicenseAsset),
    );
  });
  if (SupabaseEnv.isConfigured) {
    await initSupabase();
    // 알림은 어떤 기능의 관문도 아니다. Firebase 초기화가 실패하면(설정 파일 누락 등) 로그만
    // 남기고 앱은 그대로 뜬다 — 토큰 등록도 알림 수신도 조용히 없는 상태가 된다.
    // 옵션을 코드로 넘기지 않는다: android/app/google-services.json을 네이티브 플러그인이 읽는다.
    try {
      await Firebase.initializeApp();
    } catch (error) {
      debugPrint('Firebase.initializeApp failed: $error');
    }
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
      builder: (context, child) {
        final clamped = MediaQuery.withClampedTextScaling(
          maxScaleFactor: maxTextScale,
          child: child!,
        );
        // 애니메이션 줄이기: 버튼이 되돌아오는 움직임도 즉시. 테마는 MediaQuery를 못 보므로 여기서 고른다.
        if (!MediaQuery.disableAnimationsOf(context)) return clamped;
        return Theme(data: AppTheme.build(reduceMotion: true), child: clamped);
      },
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
