import 'dart:async';

// ProviderScope의 overrides 타입(`Override`)은 flutter_riverpod.dart가 아니라 misc.dart에 있다.
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:todododo/core/push/push_messaging.dart';
import 'package:todododo/core/push/push_providers.dart';
import 'package:todododo/core/push/push_repository.dart';

/// `FirebaseMessaging` 대신 쓰는 가짜. 권한 상태·토큰을 메모리에 들고 있고 호출 횟수를 센다.
///
/// 테스트에서 실제 Firebase를 건드리면 초기화되지 않아 던진다. `PushService`는 그 예외를
/// 로그로 삼키므로 테스트는 통과하지만 출력이 더러워지고 실제 동작은 하나도 검증되지 않는다.
class FakePushMessaging extends PushMessaging {
  FakePushMessaging({
    this.permission = NotificationPermission.granted,
    this.currentToken = 'fcm-token-1',
    this.grantOnRequest = true,
  });

  NotificationPermission permission;
  String? currentToken;

  /// 권한 다이얼로그에서 사용자가 허용을 누르는지.
  bool grantOnRequest;

  int requestCount = 0;
  int deleteTokenCount = 0;

  final _refreshes = StreamController<String>.broadcast();

  /// FCM이 토큰을 바꾼 상황을 만든다.
  void emitRefreshedToken(String token) => _refreshes.add(token);

  @override
  Future<NotificationPermission> permissionStatus() async => permission;

  @override
  Future<NotificationPermission> requestPermission() async {
    requestCount++;
    permission =
        grantOnRequest ? NotificationPermission.granted : NotificationPermission.denied;
    return permission;
  }

  @override
  Future<String?> token() async => currentToken;

  @override
  Stream<String> get tokenRefreshes => _refreshes.stream;

  @override
  Future<void> deleteToken() async {
    deleteTokenCount++;
    currentToken = null;
  }
}

/// 토큰 등록·해제 RPC 대신 호출을 기록한다.
class FakePushRepository implements PushRepository {
  FakePushRepository({this.registerError, this.unregisterError});

  final Object? registerError;
  final Object? unregisterError;

  final registered = <String>[];
  final unregistered = <String>[];

  @override
  Future<void> register(String token) async {
    registered.add(token);
    final error = registerError;
    if (error != null) throw error;
  }

  @override
  Future<void> unregister(String token) async {
    unregistered.add(token);
    final error = unregisterError;
    if (error != null) throw error;
  }
}

/// 푸시 배선이 Firebase·Supabase에 닿지 않게 하는 override 묶음.
/// 화면 테스트가 알림을 검증하지 않을 때도 넣는다 — 기본값은 "권한 있음"이라 아무 일도 하지 않는다.
List<Override> pushOverrides({FakePushMessaging? messaging, FakePushRepository? repository}) {
  return [
    pushMessagingProvider.overrideWithValue(messaging ?? FakePushMessaging()),
    pushRepositoryProvider.overrideWithValue(repository ?? FakePushRepository()),
  ];
}
