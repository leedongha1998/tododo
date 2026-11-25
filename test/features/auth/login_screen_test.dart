import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:todododo/core/strings.dart';
import 'package:todododo/features/auth/domain/auth_providers.dart';
import 'package:todododo/features/auth/presentation/auth_gate.dart';
import 'package:todododo/features/auth/presentation/login_screen.dart';

import '../../helpers/text_finders.dart';
import '../todo/todo_widget_fakes.dart';

/// 브라우저에서 돌아온 뒤의 로그인 실패(kakao-login design 흐름 2, 오너 확정 1번 — 구글·카카오 공통).
/// 취소는 조용히, 그 밖은 `signInFailed` 토스트.
void main() {
  Future<StreamController<AuthState>> pumpLogin(WidgetTester tester) async {
    final auth = StreamController<AuthState>();
    addTearDown(auth.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authStateProvider.overrideWith((ref) => auth.stream)],
        child: const MaterialApp(home: LoginScreen()),
      ),
    );
    await tester.pump();
    return auth;
  }

  testWidgets('카카오·구글 화면에서 취소하고 돌아오면 아무 말도 하지 않는다', (WidgetTester tester) async {
    final auth = await pumpLogin(tester);

    auth.addError(const AuthException('User denied', code: 'access_denied'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(SnackBar), findsNothing);
    expect(findText(AppStrings.googleSignIn), findsOneWidget);
  });

  testWidgets('돌아온 뒤 로그인이 실패하면 토스트로 알린다', (WidgetTester tester) async {
    final auth = await pumpLogin(tester);

    auth.addError(const AuthException('Code verifier could not be found', code: 'flow_state_not_found'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(findText(AppStrings.signInFailed), findsOneWidget);
    await tester.pump(const Duration(seconds: 10)); // 스낵바 타이머 소진
  });

  // `AuthGate`를 거친 경로. 오류가 오면 재시도 로딩으로 화면이 바뀌지 않고(재시도를 끈다) 로그인 화면이
  // 같은 element로 남아 그 리스너가 오류를 받는지 본다.
  group('AuthGate를 거쳐', () {
    Future<StreamController<AuthState>> pumpGate(WidgetTester tester) async {
      final auth = StreamController<AuthState>();
      addTearDown(auth.close);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...todoWidgetOverrides(host: FakeTodoWidgetHost()),
            authStateProvider.overrideWith((ref) => auth.stream),
          ],
          child: const MaterialApp(home: AuthGate()),
        ),
      );
      auth.add(AuthState(AuthChangeEvent.signedOut, null));
      await tester.pump();
      return auth;
    }

    testWidgets('취소하고 돌아오면 로그인 화면에 그대로 남고 아무 말도 없다', (WidgetTester tester) async {
      final auth = await pumpGate(tester);

      auth.addError(const AuthException('User denied', code: 'access_denied'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('돌아온 로그인이 실패하면 로그인 화면에서 토스트로 알린다', (WidgetTester tester) async {
      final auth = await pumpGate(tester);

      auth.addError(const AuthException('Failed host lookup'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(findText(AppStrings.signInFailed), findsOneWidget);
      await tester.pump(const Duration(seconds: 10)); // 스낵바 타이머 소진
    });
  });

  testWidgets('로그아웃 이벤트는 실패가 아니다', (WidgetTester tester) async {
    final auth = await pumpLogin(tester);

    auth.add(AuthState(AuthChangeEvent.signedOut, null));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(SnackBar), findsNothing);
  });
}
