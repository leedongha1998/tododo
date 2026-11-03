import 'package:firebase_messaging/firebase_messaging.dart';

/// 알림 권한 상태. OS가 주는 값을 앱이 판단에 쓰는 세 가지로 줄인다.
///
/// 안드로이드 12 이하에는 알림 권한 개념이 없어 항상 [granted]로 나온다.
/// "이미 물어봤다"는 기록을 앱이 따로 두지 않는다 — [denied]가 그 기록이다(design 흐름 4).
enum NotificationPermission { notDetermined, granted, denied }

/// `FirebaseMessaging`을 감싼 얇은 계층. 위젯 테스트에서 가짜로 바꿀 수 있게
/// provider(`pushMessagingProvider`)로 노출한다 — 선례: `EvidenceCamera`, `VsIntroSeenStore`.
///
/// 여기서는 예외를 삼키지 않는다. 호출자(`PushService`)가 로그를 남기고 삼킨다.
class PushMessaging {
  const PushMessaging();

  FirebaseMessaging get _messaging => FirebaseMessaging.instance;

  /// 지금 권한 상태. 다이얼로그를 띄우지 않는다.
  Future<NotificationPermission> permissionStatus() async {
    final settings = await _messaging.getNotificationSettings();
    return _toPermission(settings.authorizationStatus);
  }

  /// 시스템 권한 다이얼로그를 띄운다. 이미 결정된 상태면 OS가 다시 묻지 않는다.
  Future<NotificationPermission> requestPermission() async {
    final settings = await _messaging.requestPermission();
    return _toPermission(settings.authorizationStatus);
  }

  /// 이 설치의 FCM 등록 토큰. 권한이 없으면 null일 수 있다.
  ///
  /// firebase_messaging 17은 `getToken`/`onTokenRefresh`/`deleteToken`을 deprecated로 두고
  /// `register()`+`onRegistered`를 권한다. 그쪽은 **등록 토큰이 아니라 FID**를 스트림으로만
  /// 내주고 "지금 값"을 읽는 길이 없어, 설계가 정한 서버 계약(FCM v1 `message.token`에 기기
  /// 등록 토큰)과 앱 실행 시 즉시 등록하는 흐름이 둘 다 달라진다. 서버 경로(4단계)를 만들기도
  /// 전에 검증되지 않은 전송 대상으로 갈아탈 이유가 없으므로 지금은 등록 토큰을 쓴다.
  /// 전환은 TODO_BACKLOG.md에 남겼다.
  // ignore: deprecated_member_use
  Future<String?> token() => _messaging.getToken();

  /// FCM이 토큰을 바꿀 때 새 토큰을 내보낸다(앱 재설치·데이터 삭제·서버 회전).
  // ignore: deprecated_member_use
  Stream<String> get tokenRefreshes => _messaging.onTokenRefresh;

  /// 이 설치의 토큰을 버린다. 로그아웃 때 불러 다음 로그인에 새 토큰이 발급되게 한다.
  // ignore: deprecated_member_use
  Future<void> deleteToken() => _messaging.deleteToken();

  static NotificationPermission _toPermission(AuthorizationStatus status) {
    return switch (status) {
      AuthorizationStatus.authorized || AuthorizationStatus.provisional =>
        NotificationPermission.granted,
      // 안드로이드 13+의 `denied`는 "OS가 한 번 더 물을 수 있다"는 뜻이지만, 우리는 한 번만
      // 묻기로 했으므로(`notDetermined`일 때만) 두 상태를 구분할 이유가 없다 — 어느 쪽이든
      // 이 앱에서 다시 묻지 않고, 켜는 길은 기기 설정뿐이다.
      AuthorizationStatus.denied || AuthorizationStatus.deniedPermanently =>
        NotificationPermission.denied,
      AuthorizationStatus.notDetermined => NotificationPermission.notDetermined,
    };
  }
}
