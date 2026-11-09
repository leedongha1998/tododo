import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart'
    show LicenseEntryWithLineBreaks, LicenseRegistry, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/strings.dart';
import 'core/supabase/supabase_env.dart';
import 'core/supabase/supabase_init.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/keep_words_text.dart';
import 'features/auth/presentation/auth_gate.dart';

/// 시스템 글꼴 크기를 따르되 이 배율에서 멈춘다(redesign design 3.3). 1.5배에서 탭 라벨(labelSmall 12)은
/// 18dp가 되고, 360dp 폭 4칸(칸당 90dp)에 가장 긴 "대결 찾기"가 약 72dp로 들어간다 — 육안 확인 대상.
const maxTextScale = 1.5;

/// 번들한 Pretendard 글꼴의 OFL 1.1 원문(npm 패키지 dist/LICENSE.txt 그대로).
const pretendardLicenseAsset = 'assets/fonts/pretendard/LICENSE.txt';

/// Material Icons 글꼴의 CC BY 4.0 원문(Flutter SDK `bin/cache/artifacts/material_fonts/MaterialIcons_LICENSE.txt` 그대로).
const materialIconsLicenseAsset = 'assets/licenses/material_icons/LICENSE.txt';

/// 앱이 번들하는 글꼴의 고지를 앱 안 오픈소스 라이선스 화면(`showLicensePage`)에 올린다. pub 패키지 라이선스와 함께 보인다.
/// - Pretendard: OFL 글꼴은 고지해야 한다.
/// - Material Icons: Flutter 도구가 만드는 NOTICES는 pub 패키지 LICENSE와 엔진(sky_engine) LICENSE로만 만들어지고
///   거기에 Material Icons 항목이 없다. 아이콘 글꼴은 CC BY 4.0이라 저작자 표시가 필요하다(redesign 후속 결정 3).
void registerFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(
      const ['Pretendard'],
      await rootBundle.loadString(pretendardLicenseAsset),
    );
    yield LicenseEntryWithLineBreaks(
      const ['Material Icons'],
      await rootBundle.loadString(materialIconsLicenseAsset),
    );
  });
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerFontLicenses();
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
      // 기기 언어와 무관하게 한국어 하나로 **고정**한다(다국어 구조를 만드는 것이 아니다 —
      // todo-due-date design 5.2, 오너 확정). 달력·시간 선택과 Material 기본 대화상자 문구가
      // 영어로 뜨는 것을 막는 데만 쓴다.
      locale: const Locale('ko'),
      supportedLocales: const [Locale('ko')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate, // 달력·시간 선택·대화상자 기본 문구
        GlobalWidgetsLocalizations.delegate, // 글 방향(LTR)
        // Cupertino 위젯을 쓰지 않지만 이 delegate는 **빼면 안 된다.** WidgetsApp의 디버그 검사가
        // supportedLocales를 Cupertino까지 포함한 고정 목록으로 확인해서, 없으면 디버그 빌드와
        // 위젯 테스트에서 "locale ko is not supported by all of its localization delegates"로
        // 예외가 난다(2026-11-09 실제로 겪음 — design 5.2의 "넣지 않는다"를 고친 자리다).
        GlobalCupertinoLocalizations.delegate,
      ],
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
          child: KeepWordsText(AppStrings.supabaseNotConfigured, textAlign: TextAlign.center),
        ),
      ),
    );
  }
}
