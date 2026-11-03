import 'package:flutter_test/flutter_test.dart';
import 'package:todododo/core/push/push_messaging.dart';
import 'package:todododo/core/push/push_service.dart';

import 'push_fakes.dart';

void main() {
  group('start', () {
    test('권한이 있으면 토큰을 등록하고 갱신된 토큰도 등록한다', () async {
      final messaging = FakePushMessaging();
      final repository = FakePushRepository();
      final service = PushService(messaging, repository);

      await service.start();

      expect(repository.registered, ['fcm-token-1']);
      // 권한을 묻는 자리는 첫 대결 직후다. 시작은 묻지 않는다.
      expect(messaging.requestCount, 0);

      messaging.emitRefreshedToken('fcm-token-2');
      await Future<void>.delayed(Duration.zero);
      expect(repository.registered, ['fcm-token-1', 'fcm-token-2']);

      service.stop();
      messaging.emitRefreshedToken('fcm-token-3');
      await Future<void>.delayed(Duration.zero);
      expect(repository.registered, ['fcm-token-1', 'fcm-token-2']);
    });

    test('권한이 없으면 토큰을 등록하지 않고 묻지도 않는다', () async {
      final messaging = FakePushMessaging(permission: NotificationPermission.denied);
      final repository = FakePushRepository();

      await PushService(messaging, repository).start();

      expect(repository.registered, isEmpty);
      expect(messaging.requestCount, 0);
    });

    test('토큰 등록이 실패해도 예외가 밖으로 나가지 않는다', () async {
      final messaging = FakePushMessaging();
      final repository = FakePushRepository(registerError: Exception('rpc down'));

      await expectLater(PushService(messaging, repository).start(), completes);
    });

    test('토큰이 없으면 등록을 건너뛴다', () async {
      final messaging = FakePushMessaging(currentToken: null);
      final repository = FakePushRepository();

      await PushService(messaging, repository).start();

      expect(repository.registered, isEmpty);
    });
  });

  group('첫 대결 직후 권한 요청', () {
    test('아직 묻지 않은 상태에서만 묻고, 허용하면 토큰을 등록한다', () async {
      final messaging = FakePushMessaging(permission: NotificationPermission.notDetermined);
      final repository = FakePushRepository();
      final service = PushService(messaging, repository);

      await service.ensureNotificationPermissionAfterFirstBattle();

      expect(messaging.requestCount, 1);
      expect(repository.registered, ['fcm-token-1']);

      // 두 번째 대결에서는 이미 결정된 상태이므로 다시 묻지 않는다.
      await service.ensureNotificationPermissionAfterFirstBattle();
      expect(messaging.requestCount, 1);
    });

    test('거부하면 토큰을 등록하지 않는다(앱은 그대로 돌아간다)', () async {
      final messaging = FakePushMessaging(
        permission: NotificationPermission.notDetermined,
        grantOnRequest: false,
      );
      final repository = FakePushRepository();

      await PushService(messaging, repository)
          .ensureNotificationPermissionAfterFirstBattle();

      expect(messaging.requestCount, 1);
      expect(repository.registered, isEmpty);
    });

    test('이미 거부한 상태면 다시 묻지 않는다 — OS 상태가 "물어봤다"는 기록이다', () async {
      final messaging = FakePushMessaging(permission: NotificationPermission.denied);
      final repository = FakePushRepository();

      await PushService(messaging, repository)
          .ensureNotificationPermissionAfterFirstBattle();

      expect(messaging.requestCount, 0);
      expect(repository.registered, isEmpty);
    });
  });

  group('로그아웃', () {
    test('이 기기의 토큰 행을 지우고 토큰을 폐기한다', () async {
      final messaging = FakePushMessaging();
      final repository = FakePushRepository();

      await PushService(messaging, repository).forgetCurrentToken();

      expect(repository.unregistered, ['fcm-token-1']);
      expect(messaging.deleteTokenCount, 1);
    });

    test('토큰 행 삭제가 실패해도 토큰 폐기는 실행되고 예외가 나가지 않는다', () async {
      final messaging = FakePushMessaging();
      final repository = FakePushRepository(unregisterError: Exception('rpc down'));
      final service = PushService(messaging, repository);

      await expectLater(service.forgetCurrentToken(), completes);
      expect(messaging.deleteTokenCount, 1);
    });
  });
}
