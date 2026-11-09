// 기한 알림 배선(todo-due-date 9단계). 계획이 맞는지는 due_alarm_plan_test.dart가 보고,
// 여기서는 **그 계획을 플랫폼으로 옮기는 태도**를 본다 — 실패를 삼키는지, 같은 상태를 다시
// 쓰지 않는지, 권한을 한 번만 묻는지, 로그아웃이 전부 버리는지.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todododo/core/navigation/app_tab.dart';
import 'package:todododo/core/push/push_messaging.dart';
import 'package:todododo/core/strings.dart';
import 'package:todododo/features/todo/data/todo.dart';
import 'package:todododo/features/todo/domain/todo_providers.dart';

import '../due_alarm_fakes.dart';
import '../../../core/push/push_fakes.dart';

final _now = DateTime.utc(2026, 11, 10, 9, 0);

Todo _todo(String id, {bool isDone = false, DateTime? dueAt}) => Todo(
  id: id,
  title: '설거지하기',
  isDone: isDone,
  createdAt: DateTime.utc(2026, 11, 1),
  dueAt: dueAt,
);

/// `DueAlarmService`는 provider에서 Ref를 받으므로 컨테이너를 거쳐 만든다(선례: PushService).
ProviderContainer _containerFor(
  FakeDueAlarmHost host,
  FakePushMessaging messaging,
) {
  final container = ProviderContainer(
    overrides: [
      ...dueAlarmOverrides(host: host),
      ...pushOverrides(messaging: messaging),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('sync', () {
    test('미래 기한을 예약하고 제목·본문·시각을 그대로 넘긴다', () async {
      final host = FakeDueAlarmHost();
      final container = _containerFor(host, FakePushMessaging());
      final dueAt = _now.add(const Duration(days: 1));

      await container.read(dueAlarmServiceProvider).sync([
        _todo('a', dueAt: dueAt),
      ], now: _now);

      expect(host.scheduled, hasLength(2));
      expect(host.scheduled.first.at, dueAt.subtract(const Duration(hours: 1)));
      expect(host.scheduled.last.at, dueAt);
      expect(host.scheduled.map((alarm) => alarm.body), everyElement('설거지하기'));
      expect(host.initializeCount, 1);
    });

    test('같은 상태로 다시 부르면 플랫폼을 건드리지 않는다', () async {
      final host = FakeDueAlarmHost();
      final service = _containerFor(
        host,
        FakePushMessaging(),
      ).read(dueAlarmServiceProvider);
      final todos = [_todo('a', dueAt: _now.add(const Duration(days: 1)))];

      await service.sync(todos, now: _now);
      await service.sync(todos, now: _now);

      // 탭을 오갈 때마다 목록이 다시 와도 내용이 같으면 조회조차 하지 않는다.
      expect(host.scheduled, hasLength(2));
      expect(host.pendingCount, 1);
    });

    test('완료하면 그 할 일의 예약이 취소된다', () async {
      final host = FakeDueAlarmHost();
      final service = _containerFor(
        host,
        FakePushMessaging(),
      ).read(dueAlarmServiceProvider);
      final dueAt = _now.add(const Duration(days: 1));

      await service.sync([_todo('a', dueAt: dueAt)], now: _now);
      await service.sync([_todo('a', isDone: true, dueAt: dueAt)], now: _now);

      expect(host.cancelled, hasLength(2));
      expect(host.scheduled, isEmpty);
    });

    test('기한을 바꾸면 옛 예약을 버리고 새 시각으로 다시 건다', () async {
      final host = FakeDueAlarmHost();
      final service = _containerFor(
        host,
        FakePushMessaging(),
      ).read(dueAlarmServiceProvider);
      final changed = _now.add(const Duration(days: 2));

      await service.sync([
        _todo('a', dueAt: _now.add(const Duration(days: 1))),
      ], now: _now);
      await service.sync([_todo('a', dueAt: changed)], now: _now);

      expect(host.scheduled, hasLength(2));
      expect(host.scheduled.last.at, changed);
    });

    test('예약이 실패해도 예외가 밖으로 나가지 않는다', () async {
      final host = FakeDueAlarmHost(scheduleError: Exception('no plugin'));
      final service = _containerFor(
        host,
        FakePushMessaging(),
      ).read(dueAlarmServiceProvider);

      // 알림은 관문이 아니다 — 이 실패로 할 일 저장·수정·완료가 막히면 안 된다.
      await expectLater(
        service.sync([
          _todo('a', dueAt: _now.add(const Duration(days: 1))),
        ], now: _now),
        completes,
      );
    });

    test('초기화가 실패하면 다음 목록에서 다시 시도한다', () async {
      final host = FakeDueAlarmHost(initializeError: Exception('no plugin'));
      final service = _containerFor(
        host,
        FakePushMessaging(),
      ).read(dueAlarmServiceProvider);
      final todos = [_todo('a', dueAt: _now.add(const Duration(days: 1)))];

      await service.sync(todos, now: _now);
      await service.sync(todos, now: _now);

      // 실패한 집합을 "맞춰 둔 것"으로 기억하지 않는다.
      expect(host.initializeCount, 2);
    });

    test('조회가 실패하면 아무것도 예약하지 않고 넘어간다', () async {
      final host = FakeDueAlarmHost(pendingError: Exception('prefs broken'));
      final service = _containerFor(
        host,
        FakePushMessaging(),
      ).read(dueAlarmServiceProvider);

      await service.sync([
        _todo('a', dueAt: _now.add(const Duration(days: 1))),
      ], now: _now);

      expect(host.scheduled, isEmpty);
    });

    test('시작과 첫 보정이 겹쳐도 초기화는 한 번만 한다', () async {
      final host = FakeDueAlarmHost();
      final service = _containerFor(
        host,
        FakePushMessaging(),
      ).read(dueAlarmServiceProvider);

      // 셸이 뜨는 순간 start()와 첫 sync()가 거의 동시에 들어온다. 두 번 초기화하면 채널
      // 생성과 탭 콜백 등록이 두 번 돈다.
      await Future.wait([
        service.start(),
        service.sync([_todo('a', dueAt: _now.add(const Duration(days: 1)))], now: _now),
      ]);

      expect(host.initializeCount, 1);
    });

    test('겹친 두 보정이 완료한 할 일의 예약을 남기지 않는다', () async {
      // 플랫폼 호출을 느리게 만들어 "조회 → 취소 → 예약" 중간에 다음 보정이 끼어들게 한다.
      // 직렬화가 없으면 두 번째가 첫 번째의 중간 상태를 읽고, 완료한 할 일의 예약이 남는다.
      final host = FakeDueAlarmHost(delay: const Duration(milliseconds: 5));
      final service = _containerFor(
        host,
        FakePushMessaging(),
      ).read(dueAlarmServiceProvider);
      final dueAt = _now.add(const Duration(days: 1));

      final first = service.sync([_todo('a', dueAt: dueAt)], now: _now);
      final second = service.sync([
        _todo('a', isDone: true, dueAt: dueAt),
      ], now: _now);
      await Future.wait([first, second]);

      expect(host.scheduled, isEmpty);

      // 더 나쁜 증상까지 막는다 — 경합으로 생긴 오상태에 서명이 기록되면 같은 목록이 다시
      // 와도 조회조차 건너뛰어 일시적 경합이 영구히 굳는다.
      await service.sync([_todo('a', isDone: true, dueAt: dueAt)], now: _now);
      expect(host.scheduled, isEmpty);
    });

    test('겹친 보정 뒤에도 마지막 목록의 예약만 남는다', () async {
      final host = FakeDueAlarmHost(delay: const Duration(milliseconds: 5));
      final service = _containerFor(
        host,
        FakePushMessaging(),
      ).read(dueAlarmServiceProvider);
      final first = _now.add(const Duration(days: 1));
      final changed = _now.add(const Duration(days: 3));

      await Future.wait([
        service.sync([_todo('a', dueAt: first)], now: _now),
        service.sync([_todo('a', dueAt: changed)], now: _now),
      ]);

      expect(host.scheduled.map((alarm) => alarm.at), [
        changed.subtract(const Duration(hours: 1)),
        changed,
      ]);
    });

    test('채널 이름을 domain이 넘긴다 - data가 AppStrings를 읽지 않는다', () async {
      final host = FakeDueAlarmHost();
      final service = _containerFor(
        host,
        FakePushMessaging(),
      ).read(dueAlarmServiceProvider);

      await service.sync([
        _todo('a', dueAt: _now.add(const Duration(days: 1))),
      ], now: _now);

      expect(
        host.channelNames,
        everyElement(AppStrings.todoDueAlarmChannel),
      );
      expect(host.channelNames, hasLength(3)); // 초기화 1 + 예약 2
    });

    test('취소를 전부 돌린 뒤에 예약한다 - 해시 충돌의 안전장치다', () async {
      final host = FakeDueAlarmHost();
      final service = _containerFor(
        host,
        FakePushMessaging(),
      ).read(dueAlarmServiceProvider);

      // 기한을 바꾸면 id는 그대로인데 payload가 달라져 "취소 2건 + 예약 2건"이 나온다.
      await service.sync([
        _todo('a', dueAt: _now.add(const Duration(days: 1))),
      ], now: _now);
      host.calls.clear();
      await service.sync([
        _todo('a', dueAt: _now.add(const Duration(days: 2))),
      ], now: _now);

      // 순서가 뒤집히면 아직 남아 있는 남의 자리를 새 예약이 덮어써 그 알림이 조용히 사라진다.
      final firstSchedule = host.calls.indexWhere((c) => c.startsWith('schedule:'));
      final lastCancel = host.calls.lastIndexWhere((c) => c.startsWith('cancel:'));
      expect(firstSchedule, greaterThan(lastCancel));
      expect(host.calls.where((c) => c.startsWith('cancel:')), hasLength(2));
    });
  });

  group('cancelAll', () {
    test('걸려 있는 예약을 전부 버리고, 그 뒤 목록이 오면 처음부터 다시 맞춘다', () async {
      final host = FakeDueAlarmHost();
      final service = _containerFor(
        host,
        FakePushMessaging(),
      ).read(dueAlarmServiceProvider);
      final todos = [_todo('a', dueAt: _now.add(const Duration(days: 1)))];
      await service.sync(todos, now: _now);

      await service.cancelAll();

      expect(host.cancelAllCount, 1);
      expect(host.scheduled, isEmpty);

      // 같은 목록이 다시 와도 "직전과 같다"로 건너뛰지 않는다(그러면 예약이 비어 남는다).
      await service.sync(todos, now: _now);
      expect(host.scheduled, hasLength(2));
    });

    test('취소가 실패해도 예외가 밖으로 나가지 않는다 - 로그아웃을 막지 않는다', () async {
      final host = FakeDueAlarmHost(cancelError: Exception('no plugin'));
      final service = _containerFor(
        host,
        FakePushMessaging(),
      ).read(dueAlarmServiceProvider);

      await expectLater(service.cancelAll(), completes);
    });

    test('로그아웃 직전에 쏜 보정이 전체 취소 뒤에 예약을 되살리지 않는다', () async {
      final host = FakeDueAlarmHost(delay: const Duration(milliseconds: 5));
      final service = _containerFor(
        host,
        FakePushMessaging(),
      ).read(dueAlarmServiceProvider);

      // 셸이 unawaited로 쏜 보정이 아직 예약 중일 때 로그아웃이 cancelAll()을 기다린다.
      final pendingSync = service.sync([
        _todo('a', dueAt: _now.add(const Duration(days: 1))),
      ], now: _now);
      await service.cancelAll();

      // cancelAll이 먼저 끝났다고 보고했으면 그 뒤에 예약이 살아 있어서는 안 된다
      // ("로그아웃한 뒤 이전 사용자의 기한 알림이 오지 않는다" — spec).
      expect(host.scheduled, isEmpty);

      await pendingSync;
      expect(host.scheduled, isEmpty);
    });
  });

  group('권한', () {
    test('아직 묻지 않았으면 기한을 정할 때 한 번 묻는다', () async {
      final messaging = FakePushMessaging(
        permission: NotificationPermission.notDetermined,
      );
      final service = _containerFor(
        FakeDueAlarmHost(),
        messaging,
      ).read(dueAlarmServiceProvider);

      await service.ensurePermissionWhenSettingDue();

      expect(messaging.requestCount, 1);
    });

    test('거부한 사용자에게 다시 묻지 않는다', () async {
      final messaging = FakePushMessaging(
        permission: NotificationPermission.denied,
      );
      final service = _containerFor(
        FakeDueAlarmHost(),
        messaging,
      ).read(dueAlarmServiceProvider);

      await service.ensurePermissionWhenSettingDue();
      await service.ensurePermissionWhenSettingDue();

      // "이미 물어봤다"는 기록을 앱이 따로 두지 않는다 — denied가 그 기록이다(spec).
      expect(messaging.requestCount, 0);
    });

    test('이미 허용한 사용자에게도 묻지 않는다', () async {
      final messaging = FakePushMessaging();
      final service = _containerFor(
        FakeDueAlarmHost(),
        messaging,
      ).read(dueAlarmServiceProvider);

      await service.ensurePermissionWhenSettingDue();

      expect(messaging.requestCount, 0);
    });

    test('거부해도 예약 호출을 권한으로 가르지 않는다', () async {
      final host = FakeDueAlarmHost();
      final service = _containerFor(
        host,
        FakePushMessaging(permission: NotificationPermission.denied),
      ).read(dueAlarmServiceProvider);

      await service.sync([
        _todo('a', dueAt: _now.add(const Duration(days: 1))),
      ], now: _now);

      // 권한으로 가르면 나중에 기기 설정에서 켠 사용자의 예약이 비어 있게 된다.
      // OS가 조용히 버리게 두고, 보정이 다음 실행에 다시 건다(design 8.9).
      expect(host.scheduled, hasLength(2));
    });
  });

  group('알림 탭', () {
    test('종료 상태에서 탭해 시작되면 할 일 탭으로 옮긴다', () async {
      final host = FakeDueAlarmHost(launchedByNotificationValue: true);
      final container = _containerFor(host, FakePushMessaging());

      await container.read(dueAlarmServiceProvider).start();

      expect(container.read(selectedTabProvider), AppTab.todo);
    });

    test('탭하지 않고 시작하면 탭을 옮기지 않는다', () async {
      final container = _containerFor(FakeDueAlarmHost(), FakePushMessaging());

      await container.read(dueAlarmServiceProvider).start();

      expect(container.read(selectedTabProvider), AppTab.myBattles);
    });

    test('앱이 떠 있는 동안 탭하면 할 일 탭으로 옮긴다', () async {
      final host = FakeDueAlarmHost();
      final container = _containerFor(host, FakePushMessaging());
      await container.read(dueAlarmServiceProvider).start();

      // 플러그인이 탭 콜백을 부른 상황. payload는 해석하지 않는다(어느 할 일인지로 분기하지
      // 않으므로 뜻을 모르는 알림이어도 그냥 할 일 화면을 연다).
      host.onTap!();

      expect(container.read(selectedTabProvider), AppTab.todo);
    });
  });
}
