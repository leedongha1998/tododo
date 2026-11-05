import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/battle/domain/battle_providers.dart';
import 'notification_payload.dart';
import 'push_messaging.dart';
import 'push_providers.dart';
import 'push_repository.dart';

/// 푸시 알림 배선의 시작·중지와 권한 요청 시점.
///
/// 이 클래스의 모든 실패는 `debugPrint`로만 남고 밖으로 나가지 않는다. 알림은 어떤 기능의
/// 관문도 아니므로(spec) 토큰 등록이 안 되거나 Firebase 초기화가 실패해도 화면은 그대로 돌아야
/// 한다. 사용자가 그 시점에 할 수 있는 일도 없다 — VS 인트로 실패와 같은 성격의 예외다.
class PushService {
  PushService(this._ref, this._messaging, this._repository);

  /// 로그아웃 때 토큰 정리가 기다리는 상한. 로그아웃 버튼에는 진행 표시가 없어서 네트워크가
  /// 느리면 "눌러도 아무 일이 없다"로 보인다. 넘기면 정리를 포기하고 로그아웃을 진행한다 —
  /// 남은 토큰 행은 다음 발송에서 죽은 토큰으로 판별돼 서버가 지운다(design `record_notification_result`).
  static const _cleanupTimeout = Duration(seconds: 5);

  final Ref _ref;
  final PushMessaging _messaging;
  final PushRepository _repository;

  StreamSubscription<String>? _tokenRefreshes;
  StreamSubscription<Map<String, dynamic>>? _foregroundMessages;
  StreamSubscription<Map<String, dynamic>>? _openedMessages;

  /// 로그인한 뒤(세션이 있는 화면이 뜰 때) 한 번. **권한을 묻지 않는다** —
  /// 묻는 자리는 첫 대결 생성·참가 직후다([ensureNotificationPermissionAfterFirstBattle]).
  Future<void> start() async {
    // 메시지 구독은 권한과 상관없이 먼저 건다. 권한이 없으면 알림 자체가 오지 않아 스트림이
    // 조용할 뿐이고, 사용자가 기기 설정에서 나중에 켰을 때 이 실행에서 바로 받을 수 있다.
    try {
      _listenForMessages();
      // 종료 상태에서 알림을 탭해 시작된 경우. 그 실행에서 한 번만 값이 있다.
      final initial = await _messaging.initialMessage();
      if (initial != null) _handleOpenedMessage(initial);
    } catch (error) {
      debugPrint('push message listen failed: $error');
    }

    try {
      if (await _messaging.permissionStatus() != NotificationPermission.granted) return;
      await _registerCurrentToken();
      _listenForTokenRefresh();
    } catch (error) {
      debugPrint('push start failed: $error');
    }
  }

  /// 화면이 사라질 때. 토큰 행은 그대로 둔다(기기는 여전히 이 계정의 것이다).
  void stop() {
    _tokenRefreshes?.cancel();
    _tokenRefreshes = null;
    _foregroundMessages?.cancel();
    _foregroundMessages = null;
    _openedMessages?.cancel();
    _openedMessages = null;
  }

  /// 첫 대결을 만들거나 참가한 직후. 아직 묻지 않았을 때만 시스템 다이얼로그를 띄운다 —
  /// "이미 물어봤다"는 기록을 앱이 따로 두지 않고 OS 상태를 그 기록으로 쓴다(design 흐름 4).
  /// 거부하면 아무것도 하지 않는다.
  Future<void> ensureNotificationPermissionAfterFirstBattle() async {
    try {
      if (await _messaging.permissionStatus() != NotificationPermission.notDetermined) return;
      if (await _messaging.requestPermission() != NotificationPermission.granted) return;
      await _registerCurrentToken();
      _listenForTokenRefresh();
    } catch (error) {
      debugPrint('notification permission request failed: $error');
    }
  }

  /// 로그아웃 **직전**. 토큰 행 삭제(세션이 살아 있어야 한다)와 토큰 폐기를 따로 감싸
  /// 앞이 실패해도 뒤가 실행되고, 어느 쪽도 로그아웃을 막지 않는다.
  Future<void> forgetCurrentToken() async {
    stop();
    try {
      final token = await _messaging.token().timeout(_cleanupTimeout);
      if (token != null) await _repository.unregister(token).timeout(_cleanupTimeout);
    } catch (error) {
      debugPrint('unregister_push_token failed: $error');
    }
    try {
      // 이 설치에 새 토큰이 발급되게 한다 — 같은 기기를 다른 계정이 써도 토큰이 겹치지 않는다.
      await _messaging.deleteToken().timeout(_cleanupTimeout);
    } catch (error) {
      debugPrint('deleteToken failed: $error');
    }
  }

  Future<void> _registerCurrentToken() async {
    final token = await _messaging.token();
    if (token == null) {
      debugPrint('push token is null — skipping register_push_token');
      return;
    }
    await _repository.register(token);
  }

  void _listenForMessages() {
    // 이미 구독 중이면 다시 걸지 않는다.
    _foregroundMessages ??= _messaging.foregroundMessages.listen(
      _handleForegroundMessage,
      onError: (Object error) => debugPrint('onMessage failed: $error'),
    );
    _openedMessages ??= _messaging.openedMessages.listen(
      _handleOpenedMessage,
      onError: (Object error) => debugPrint('onMessageOpenedApp failed: $error'),
    );
  }

  /// 앱을 보고 있는 동안 도착한 메시지. **알림을 직접 그리지 않는다** — 로컬 알림 패키지를
  /// 넣지 않기로 했으므로(design 흐름 7), 화면이 보고 있는 값만 다시 읽게 해 지금 상태를 비춘다.
  /// 앱 안 확인 경로(목록 상태 줄·상세)가 이미 spec이 정한 자리라 이것으로 충분하다.
  void _handleForegroundMessage(Map<String, dynamic> data) {
    try {
      _ref.invalidate(myBattlesProvider);
      final battleId = battleIdOf(data);
      if (battleId != null) _ref.invalidate(battleDetailProvider(battleId));
    } catch (error) {
      debugPrint('포그라운드 알림 반영 실패: $error');
    }
  }

  /// 알림을 탭했다(백그라운드에서 돌아왔거나 종료 상태에서 시작됐다).
  /// 여기서 화면을 열지 않고 한 칸에 적어 두기만 한다 — 열 수 있는 화면(MainShell)이 떠 있는
  /// 시점과 알림이 도착하는 시점이 다르기 때문이다.
  void _handleOpenedMessage(Map<String, dynamic> data) {
    final battleId = battleIdOf(data);
    if (battleId == null) {
      // 뜻을 모르는 알림이다. 아무 데나 보내지 않고 조용히 넘어간다.
      debugPrint('알림 payload에 쓸 수 있는 battle_id가 없다');
      return;
    }
    try {
      _ref.read(pendingBattleOpenProvider.notifier).request(battleId);
    } catch (error) {
      debugPrint('알림 탭 기록 실패: $error');
    }
  }

  void _listenForTokenRefresh() {
    // 이미 구독 중이면 다시 걸지 않는다(시작 경로가 둘이다 — 로그인 직후, 권한 허용 직후).
    _tokenRefreshes ??= _messaging.tokenRefreshes.listen(
      (token) async {
        try {
          await _repository.register(token);
        } catch (error) {
          debugPrint('register_push_token on refresh failed: $error');
        }
      },
      onError: (Object error) => debugPrint('onTokenRefresh failed: $error'),
    );
  }
}
