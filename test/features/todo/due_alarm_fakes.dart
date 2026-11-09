// ProviderScope의 overrides 타입(`Override`)은 flutter_riverpod.dart가 아니라 misc.dart에 있다.
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:todododo/features/todo/data/due_alarm_host.dart';
import 'package:todododo/features/todo/domain/todo_providers.dart';

/// 예약 하나를 흉내 내는 기록. 실제 OS에 걸린 알람 대신 메모리에 쌓인다.
class FakeScheduled {
  FakeScheduled({
    required this.id,
    required this.at,
    required this.title,
    required this.body,
    required this.payload,
  });

  final int id;
  final DateTime at;
  final String title;
  final String body;
  final String payload;
}

/// `flutter_local_notifications` 대신 쓰는 가짜. 예약·취소를 메모리에 들고 호출 횟수를 센다.
///
/// 테스트에서 실제 플러그인을 건드리면 MethodChannel이 없어 아무 일도 하지 않거나 던지고,
/// `DueAlarmService`가 그 예외를 로그로 삼킨다 — 통과하지만 아무것도 검증되지 않는다
/// (위젯·푸시 가짜와 같은 이유).
class FakeDueAlarmHost extends DueAlarmHost {
  FakeDueAlarmHost({
    this.initializeError,
    this.pendingError,
    this.scheduleError,
    this.cancelError,
    this.launchedByNotificationValue = false,
    this.delay = Duration.zero,
  });

  final Object? initializeError;
  final Object? pendingError;
  final Object? scheduleError;
  final Object? cancelError;

  /// 플랫폼 호출 하나하나를 느리게 만든다. **겹친 보정**(조회 → 취소 → 예약 사이에 다른 보정이
  /// 끼어드는 상황)을 재현하는 수단이다 — 실제로 안드로이드의 예약 읽기·쓰기는 prefs 파일을
  /// 건드리므로 즉시 끝나지 않는다.
  final Duration delay;

  Future<void> _tick() => delay == Duration.zero
      ? Future<void>.value()
      : Future<void>.delayed(delay);

  /// 종료 상태에서 기한 알림을 탭해 앱이 시작된 상황을 만든다.
  bool launchedByNotificationValue;

  final scheduled = <FakeScheduled>[];
  final cancelled = <int>[];

  /// 채널 이름이 넘어온 기록. 사용자에게 보이는 문구를 `data`가 직접 읽지 않고 domain이
  /// 넘긴다는 계약을 테스트가 볼 수 있게 모아 둔다.
  final channelNames = <String>[];

  /// 플랫폼 호출의 **순서** 기록(`cancel:<id>` / `schedule:<id>`). 보정이 취소를 전부 돌린 뒤에
  /// 예약하는지(해시 충돌 안전장치)를 테스트가 볼 수 있게 남긴다.
  final calls = <String>[];

  int initializeCount = 0;
  int pendingCount = 0;
  int cancelAllCount = 0;

  /// `initialize`에 넘어온 탭 콜백. 앱이 떠 있는 동안 탭한 상황을 만들 때 부른다.
  void Function()? onTap;

  @override
  Future<void> initialize({
    required String channelName,
    void Function()? onTap,
  }) async {
    initializeCount++;
    channelNames.add(channelName);
    this.onTap = onTap;
    final error = initializeError;
    if (error != null) throw error;
  }

  @override
  Future<List<({int id, String? payload})>> pending() async {
    pendingCount++;
    await _tick();
    final error = pendingError;
    if (error != null) throw error;
    return [
      for (final alarm in scheduled) (id: alarm.id, payload: alarm.payload),
    ];
  }

  @override
  Future<void> schedule({
    required int id,
    required DateTime at,
    required String title,
    required String body,
    required String payload,
    required String channelName,
  }) async {
    calls.add('schedule:$id');
    await _tick();
    channelNames.add(channelName);
    final error = scheduleError;
    if (error != null) throw error;
    scheduled.add(
      FakeScheduled(id: id, at: at, title: title, body: body, payload: payload),
    );
  }

  @override
  Future<void> cancel(int id) async {
    cancelled.add(id);
    calls.add('cancel:$id');
    await _tick();
    final error = cancelError;
    if (error != null) throw error;
    scheduled.removeWhere((alarm) => alarm.id == id);
  }

  @override
  Future<void> cancelAll() async {
    cancelAllCount++;
    await _tick();
    final error = cancelError;
    if (error != null) throw error;
    scheduled.clear();
  }

  @override
  Future<bool> launchedByNotification() async => launchedByNotificationValue;
}

/// 기한 알림이 플러그인에 닿지 않게 하는 override. 알림을 검증하지 않는 화면 테스트에도 넣는다.
List<Override> dueAlarmOverrides({FakeDueAlarmHost? host}) {
  return [dueAlarmHostProvider.overrideWithValue(host ?? FakeDueAlarmHost())];
}
