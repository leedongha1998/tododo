import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:todododo/core/navigation/main_shell.dart';
import 'package:todododo/core/strings.dart';
import 'package:todododo/features/auth/data/auth_repository.dart';
import 'package:todododo/features/auth/domain/auth_providers.dart';
import 'package:todododo/features/auth/presentation/auth_gate.dart';
import 'package:todododo/features/auth/presentation/login_screen.dart';
import 'package:todododo/features/battle/data/battle_repository.dart';
import 'package:todododo/features/battle/data/criteria_check_result.dart';
import 'package:todododo/features/battle/data/open_recruit_page.dart';
import 'package:todododo/features/battle/data/profile.dart';
import 'package:todododo/features/battle/domain/ai_consent_providers.dart';
import 'package:todododo/features/battle/domain/battle_providers.dart';
import 'package:todododo/features/profile/data/player_stats.dart';
import 'package:todododo/features/profile/domain/profile_providers.dart';
import 'package:todododo/features/todo/domain/todo_providers.dart';

import '../../helpers/text_finders.dart';
import '../../core/push/push_fakes.dart';
import '../notification/notification_fakes.dart';
import '../todo/due_alarm_fakes.dart';
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

  testWidgets('구글 버튼 아래에 카카오 버튼과 계정 안내 한 줄이 있고, 누르면 각자의 로그인을 부른다',
      (WidgetTester tester) async {
    final repo = _RecordingAuthRepository();
    final auth = StreamController<AuthState>();
    addTearDown(auth.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authStateProvider.overrideWith((ref) => auth.stream),
          authRepositoryProvider.overrideWithValue(repo),
        ],
        child: const MaterialApp(home: LoginScreen()),
      ),
    );
    await tester.pump();

    final google = findText(AppStrings.googleSignIn);
    final kakao = findText(AppStrings.kakaoSignIn);
    expect(google, findsOneWidget);
    expect(kakao, findsOneWidget);
    expect(findText(AppStrings.signInAccountsNotLinked), findsOneWidget);
    // 구글이 위, 카카오가 아래(design 1.1 — 기존 가입자의 손이 기억하는 자리를 지킨다).
    expect(tester.getCenter(google).dy, lessThan(tester.getCenter(kakao).dy));

    await tester.tap(kakao);
    await tester.pump();
    expect(repo.kakaoCalls, 1);
    expect(repo.googleCalls, 0);

    await tester.tap(google);
    await tester.pump();
    expect(repo.googleCalls, 1);
    expect(find.byType(SnackBar), findsNothing);
  });

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

  // 재시도 끄기와 `AuthGate`의 `skipError`를 고정한다(plan "구현 중 바꾼 것"). 로그인한 사용자의 토큰 갱신이
  // 네트워크로 실패해도(gotrue가 스트림에 오류를 흘린다) 본 화면에서 쫓겨나지 않고, 그 뒤 진짜 로그아웃은
  // 그대로 로그인 화면으로 간다. 본 화면은 `widget_test.dart`의 `_pumpMainShellForWidgetCache`와 같은
  // 방식으로 서버를 보지 않게 고정한다.
  testWidgets('로그인한 동안 인증 스트림 오류가 와도 본 화면을 지키고, 로그아웃하면 로그인 화면으로 간다', (
    WidgetTester tester,
  ) async {
    final auth = StreamController<AuthState>();
    addTearDown(auth.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...notificationOverrides,
          ...pushOverrides(),
          ...todoWidgetOverrides(host: FakeTodoWidgetHost()),
          ...dueAlarmOverrides(),
          authStateProvider.overrideWith((ref) => auth.stream),
          todosProvider.overrideWith((ref) async => []),
          myBattlesProvider.overrideWith((ref) async => []),
          myRecruitsProvider.overrideWith((ref) async => []),
          battleRepositoryProvider.overrideWithValue(_QuietBattleRepository()),
          myAiConsentProvider.overrideWith((ref) async => null),
          myProfileProvider.overrideWith(
            (ref) async => const Profile(id: 'me', displayName: '나'),
          ),
          myPlayerStatsProvider.overrideWith((ref) async => PlayerStats.empty),
          battleRecordsProvider.overrideWith((ref) async => []),
        ],
        child: const MaterialApp(home: AuthGate()),
      ),
    );

    auth.add(AuthState(AuthChangeEvent.signedIn, _session()));
    await tester.pumpAndSettle();
    expect(find.byType(MainShell), findsOneWidget);

    // 토큰 갱신 실패 같은 스트림 오류. 재시도 로딩으로 바뀌지도, 로그인 화면으로 쫓겨나지도 않는다.
    auth.addError(const AuthException('x'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(MainShell), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);

    // 오류 뒤에도 스트림 구독은 이어진다 — 진짜 로그아웃은 그대로 로그인 화면이다.
    auth.add(AuthState(AuthChangeEvent.signedOut, null));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(MainShell), findsNothing);
  });

  testWidgets('로그아웃 이벤트는 실패가 아니다', (WidgetTester tester) async {
    final auth = await pumpLogin(tester);

    auth.add(AuthState(AuthChangeEvent.signedOut, null));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(SnackBar), findsNothing);
  });
}

Session _session() {
  return Session(
    accessToken: 'test-access-token',
    tokenType: 'bearer',
    user: const User(
      id: 'me',
      appMetadata: {'provider': 'google'},
      userMetadata: {},
      aud: 'authenticated',
      createdAt: '2026-11-25T00:00:00Z',
    ),
  );
}

/// 본 화면의 모집 탭이 서버를 보지 않게 하는 가짜(`notification_tap_test.dart`의 것과 같은 범위).
class _QuietBattleRepository implements BattleRepository {
  @override
  Future<OpenRecruitPage> fetchOpenRecruits({
    int limit = openRecruitPageSize,
    RecruitCursor? cursor,
    String? query,
    String? type,
    String? durationBand,
  }) async =>
      const OpenRecruitPage(items: [], nextCursor: null, hasMore: false);

  @override
  Future<MyLimits> fetchMyLimits() async =>
      const MyLimits(consented: true, criteriaCallsLeft: 10);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// 로그인 버튼이 어느 메서드를 부르는지만 센다. 나머지 메서드는 이 테스트에서 불리지 않는다.
class _RecordingAuthRepository implements AuthRepository {
  int googleCalls = 0;
  int kakaoCalls = 0;

  @override
  Future<void> signInWithGoogle() async {
    googleCalls++;
  }

  @override
  Future<void> signInWithKakao() async {
    kakaoCalls++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
