import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:todododo/features/auth/domain/auth_providers.dart';
import 'package:todododo/features/auth/domain/login_method.dart';

/// 프로필의 로그인 수단 한 줄(kakao-login design 흐름 3·8.3). 모르면 null — 줄을 그리지 않는다.
void main() {
  group('loginMethodFrom', () {
    test('provider가 google·kakao면 그 수단', () {
      expect(loginMethodFrom({'provider': 'google'}), LoginMethod.google);
      expect(loginMethodFrom({'provider': 'kakao'}), LoginMethod.kakao);
    });

    test('provider가 다른 값이거나 없으면 null', () {
      expect(loginMethodFrom({'provider': 'email'}), isNull);
      expect(loginMethodFrom({}), isNull);
      expect(loginMethodFrom(null), isNull);
      // provider가 이상하면 providers로 넘어가지 않는다.
      expect(loginMethodFrom({'provider': 'email', 'providers': ['kakao']}), isNull);
    });

    test('provider가 없으면 providers가 정확히 하나일 때만', () {
      expect(loginMethodFrom({'providers': ['kakao']}), LoginMethod.kakao);
      expect(loginMethodFrom({'providers': ['google']}), LoginMethod.google);
      expect(loginMethodFrom({'providers': ['google', 'kakao']}), isNull);
      expect(loginMethodFrom({'providers': <String>[]}), isNull);
      expect(loginMethodFrom({'providers': 'kakao'}), isNull);
    });
  });

  group('myLoginMethodProvider', () {
    ProviderContainer containerWith(Stream<AuthState> auth) {
      final container = ProviderContainer(
        overrides: [authStateProvider.overrideWith((ref) => auth)],
        retry: (retryCount, error) => null,
      );
      addTearDown(container.dispose);
      return container;
    }

    test('세션의 app_metadata에서 읽는다', () async {
      final auth = StreamController<AuthState>();
      addTearDown(auth.close);
      final container = containerWith(auth.stream);
      final sub = container.listen(myLoginMethodProvider, (_, _) {});
      addTearDown(sub.close);

      expect(container.read(myLoginMethodProvider), isNull, reason: '세션을 받기 전');

      auth.add(AuthState(AuthChangeEvent.signedIn, _sessionWith({'provider': 'kakao'})));
      await Future<void>.delayed(Duration.zero);
      expect(container.read(myLoginMethodProvider), LoginMethod.kakao);

      auth.add(AuthState(AuthChangeEvent.signedOut, null));
      await Future<void>.delayed(Duration.zero);
      expect(container.read(myLoginMethodProvider), isNull);
    });

    test('인증 스트림이 실패해도 던지지 않고 null', () async {
      final container = containerWith(Stream.error(StateError('no supabase')));
      final sub = container.listen(myLoginMethodProvider, (_, _) {});
      addTearDown(sub.close);
      await Future<void>.delayed(Duration.zero);

      expect(container.read(myLoginMethodProvider), isNull);
    });
  });
}

Session _sessionWith(Map<String, dynamic> appMetadata) {
  return Session(
    accessToken: 'test-access-token',
    tokenType: 'bearer',
    user: User(
      id: 'me',
      appMetadata: appMetadata,
      userMetadata: const {},
      aud: 'authenticated',
      createdAt: '2026-11-25T00:00:00Z',
    ),
  );
}
