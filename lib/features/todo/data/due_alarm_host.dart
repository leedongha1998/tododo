import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

/// 기한 알림 채널 id. **대결 알림(FCM)과 다른 id여야 한다** — 대결 알림은 매니페스트에 기본
/// 채널을 지정하지 않아 `fcm_fallback_notification_channel`로 가므로 이 id와 겹치지 않는다.
/// 채널이 갈려 있어야 OS 알림 설정에서 `기한 알림`만 끌 수 있고, 그래야 "앱 안에 알림 끄기
/// 설정을 두지 않는다"는 결정이 성립한다(spec, design 8.3).
const dueAlarmChannelId = 'todo_due';

/// 알림의 작은 아이콘. 매니페스트의 FCM 기본 아이콘과 같은 흰 실루엣을 쓴다
/// (`tool/generate_launcher_icons.dart`가 만든다). 런처 아이콘을 쓰면 흰 사각형으로 뭉개진다.
const _smallIcon = 'ic_notification';

/// `flutter_local_notifications` 접점. 위젯 테스트에서 가짜로 바꾸는 지점이다
/// (선례: `TodoWidgetHost`, `PushMessaging`, `EvidenceCamera`).
///
/// **여기서는 예외를 삼키지 않는다.** 호출자(`DueAlarmService`)가 로그를 남기고 삼킨다 —
/// 알림은 관문이 아니므로 예약·취소 실패로 할 일 저장·수정·완료·삭제를 막지 않는다
/// (design 원칙 4).
///
/// **`domain`을 import하지 않는다.** 예약 하나를 뜻하는 `DueAlarm`은 사용자 문구(`AppStrings`)를
/// 읽는 domain 값이라, 호스트가 그것을 받으면 `data`가 domain과 사용자 문구에 전이 의존한다
/// (P0 리뷰 지적 3과 같은 모양이다). 그래서 이 계층은 원시값만 주고받는다 —
/// **사용자에게 보이는 채널 이름도 `AppStrings`에서 직접 읽지 않고 인자로 받는다.**
class DueAlarmHost {
  const DueAlarmHost();

  FlutterLocalNotificationsPlugin get _plugin =>
      FlutterLocalNotificationsPlugin();

  /// 플러그인을 초기화하고 기한 알림 채널을 만든다. 같은 id로 다시 만들어도 OS가 기존 채널을
  /// 그대로 두므로(이름만 갱신) 실행마다 불러도 안전하다.
  ///
  /// [onTap]은 알림을 탭했을 때 불린다 — 앱이 떠 있거나 백그라운드에 있던 경우다. 종료 상태에서
  /// 시작된 경우는 이 콜백이 아니라 [launchedByNotification]으로 집는다.
  ///
  /// 백그라운드 탭 핸들러(`onDidReceiveBackgroundNotificationResponse`)는 **등록하지 않는다** —
  /// 동작 버튼이 없어 탭은 늘 앱을 띄우고, 띄워진 앱이 위 두 경로로 집어 간다(design 8.11).
  Future<void> initialize({
    required String channelName,
    void Function()? onTap,
  }) async {
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings(_smallIcon),
      ),
      onDidReceiveNotificationResponse: onTap == null ? null : (_) => onTap(),
    );
    // 채널 설명은 두지 않는다(API에서 선택 항목이고, spec에 없는 문구를 새로 지어내지 않는다).
    // defaultImportance = 소리는 나지만 화면을 가로채는 헤드업은 쓰지 않는다.
    // 잠금화면 가리기(visibility)도 지정하지 않고 OS 기본에 맡긴다 — 사용자가 직접 넣은
    // 할 일의 제목이므로 노출 여부가 이미 사용자의 선택이다(spec).
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(
          AndroidNotificationChannel(
            dueAlarmChannelId,
            channelName,
            importance: Importance.defaultImportance,
          ),
        );
  }

  /// 지금 OS에 걸려 있는 예약. **보정 설계가 이 조회 하나에 걸려 있다**(design 8.5) —
  /// 돌려주는 payload가 "그 예약이 무엇을 뜻하는지"의 진실이고, id는 자리 번호일 뿐이다.
  ///
  /// 돌려주는 레코드는 구조적 타입이라 domain 값(`PendingDueAlarm`)을 import하지 않는다.
  Future<List<({int id, String? payload})>> pending() async {
    final requests = await _plugin.pendingNotificationRequests();
    return [
      for (final request in requests)
        (id: request.id, payload: request.payload),
    ];
  }

  /// 알림 하나를 예약한다.
  ///
  /// **부정확 예약(`inexactAllowWhileIdle`)을 쓴다**(오너 확정, design 결정 기록 2번).
  /// 정확 알람은 Play 심사에서 알람시계·캘린더 성격의 앱만 정당화되고 Android 14+에서는
  /// 사용자를 OS 설정으로 보내는 안내가 하나 더 생긴다. 대가는 절전(Doze) 상태의 지연이다 —
  /// 기한 알림은 몇 분 늦어도 뜻이 상하지 않는다.
  ///
  /// [body]는 할 일 제목이고 **앱이 자르지 않는다**(spec). 길면 안드로이드가 줄여 보여 주고
  /// 펼치면 전체가 보인다 — 앱이 먼저 자르면 펼쳐도 복구되지 않는다.
  Future<void> schedule({
    required int id,
    required DateTime at,
    required String title,
    required String body,
    required String payload,
    required String channelName,
  }) async {
    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: toScheduleTime(at),
      payload: payload,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          dueAlarmChannelId,
          channelName,
          importance: Importance.defaultImportance,
          // 제목이 길면 접힌 줄에서는 안드로이드가 줄이고, 펼치면 전체가 보인다.
          // 이 스타일이 없으면 펼쳐도 한 줄에서 잘린 채로 남는다.
          styleInformation: BigTextStyleInformation(body),
        ),
      ),
    );
  }

  Future<void> cancel(int id) => _plugin.cancel(id: id);

  /// 이 기기의 예약을 전부 버린다. 로그아웃·탈퇴에서 쓴다 — 걸려 있는 알림이 전부 기한 알림
  /// 하나뿐이라(대결 알림은 FCM이 직접 그려 이 플러그인을 거치지 않는다) 이것으로 충분하다.
  Future<void> cancelAll() => _plugin.cancelAll();

  /// 앱이 **종료된 상태**에서 기한 알림을 탭해 시작됐는지. 그 실행에서 한 번만 참이다.
  /// 어느 할 일인지로 분기하지 않으므로 payload는 읽지 않는다(design 8.11).
  Future<bool> launchedByNotification() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    return details?.didNotificationLaunchApp ?? false;
  }

  /// 예약을 절대 시각으로 넘긴다. `tz.UTC`는 `initializeTimeZones()` 없이 쓸 수 있는 내장
  /// Location이라(테스트로 고정했다) 기기 시간대 이름을 조회하는 패키지가 필요 없다.
  ///
  /// 테스트가 **이 식을 다시 적지 않고 직접 부르도록** 열어 두었다(식이 바뀌면 테스트가 울어야 한다).
  @visibleForTesting
  static tz.TZDateTime toScheduleTime(DateTime at) =>
      tz.TZDateTime.from(at.toUtc(), tz.UTC);
}
