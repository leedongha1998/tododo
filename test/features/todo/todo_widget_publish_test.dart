import 'package:flutter_test/flutter_test.dart';
import 'package:todododo/core/strings.dart';
import 'package:todododo/features/todo/data/todo.dart';
import 'package:todododo/features/todo/data/todo_widget_payload.dart';
import 'package:todododo/features/todo/domain/todo_widget_service.dart';

import 'todo_widget_fakes.dart';

/// 위젯 캐시 발행 계층. 화면(`MainShell`)이 이 서비스를 부르는 경로는 widget_test.dart에서 본다.
void main() {
  final now = DateTime(2026, 11, 4, 9, 14);

  test('발행하면 캐시를 쓰고 위젯을 다시 그린다', () async {
    final host = FakeTodoWidgetHost();
    final service = TodoWidgetService(host);

    await service.publish(TodoWidgetPayload.fromTodos([_todo('1')], now: now));

    expect(host.saved, hasLength(1));
    expect(host.updateCount, 1);
    expect(service.lastPublished?.items.single.id, '1');
  });

  test('같은 상태는 다시 발행하지 않는다', () async {
    final host = FakeTodoWidgetHost();
    final service = TodoWidgetService(host);
    final todos = [_todo('1')];

    await service.publish(TodoWidgetPayload.fromTodos(todos, now: now));
    await service.publish(TodoWidgetPayload.fromTodos(todos, now: now));

    // 탭을 오갈 때마다 목록이 다시 와도 내용이 같으면 브로드캐스트를 보내지 않는다.
    expect(host.saved, hasLength(1));
    expect(host.updateCount, 1);
  });

  test('내용이 바뀌면 다시 발행한다', () async {
    final host = FakeTodoWidgetHost();
    final service = TodoWidgetService(host);

    await service.publish(TodoWidgetPayload.fromTodos([_todo('1')], now: now));
    await service.publish(
      TodoWidgetPayload.fromTodos([_todo('1'), _todo('2')], now: now),
    );

    expect(host.saved, hasLength(2));
    expect(host.updateCount, 2);
  });

  test('캐시 쓰기가 실패해도 앱으로 예외가 나가지 않는다', () async {
    final host = FakeTodoWidgetHost(saveError: StateError('no plugin'));
    final service = TodoWidgetService(host);

    await service.publish(TodoWidgetPayload.loading(now: now));

    // 위젯은 관문이 아니다 — 실패는 로그만 남기고 화면·흐름을 막지 않는다.
    expect(host.updateCount, 0);
    // 실패한 발행은 "직전"으로 기억하지 않는다. 위젯에는 옛 내용이 남아 있으므로 다음에 같은
    // 값이 와도 다시 시도해야 한다.
    expect(service.lastPublished, isNull);
    await service.publish(TodoWidgetPayload.loading(now: now));
    expect(host.saved, hasLength(2));
  });

  test('조회 실패는 직전 발행을 근거로 목록을 유지한다', () async {
    final host = FakeTodoWidgetHost();
    final service = TodoWidgetService(host);
    await service.publish(TodoWidgetPayload.fromTodos([_todo('1')], now: now));

    await service.publish(
      TodoWidgetPayload.fetchFailed(service.lastPublished, now: now),
    );

    final published = host.saved.last;
    expect(published.items.single.id, '1');
    expect(published.note, '지금은 못 불러왔어요 · 오전 9:14 기준');
  });

  test('다시 그리기가 실패하면 직전으로 기억하지 않는다', () async {
    final host = FakeTodoWidgetHost(updateError: StateError('no launcher'));
    final service = TodoWidgetService(host);

    await service.publish(TodoWidgetPayload.fromTodos([_todo('1')], now: now));

    // 캐시는 썼지만 홈 화면은 아직 옛 내용이다. 같은 값이 다시 와도 한 번 더 시도해야 한다.
    expect(service.lastPublished, isNull);
    await service.publish(TodoWidgetPayload.fromTodos([_todo('1')], now: now));
    expect(host.updateCount, 2);
  });

  group('primeFromCache', () {
    test('캐시에 지난 목록이 있으면 불러오는 중으로 덮지 않는다', () async {
      final host = FakeTodoWidgetHost(
        stored: TodoWidgetPayload.fromTodos([_todo('1')], now: now),
      );
      final service = TodoWidgetService(host);

      await service.primeFromCache(now: now.add(const Duration(days: 1)));

      // 앱을 다시 켠 것만으로 홈 화면의 지난 목록이 사라지면 안 된다.
      expect(host.saved, isEmpty);
      expect(host.readCount, 1);
      expect(service.lastPublished?.items.single.id, '1');
    });

    test('되읽은 목록이 조회 실패의 직전 목록이 된다', () async {
      final host = FakeTodoWidgetHost(
        stored: TodoWidgetPayload.fromTodos([_todo('1')], now: now),
      );
      final service = TodoWidgetService(host);
      await service.primeFromCache(now: now);

      // 앱을 다시 켰는데 네트워크가 없는 경우 — 가장 흔한 실패다.
      await service.publish(
        TodoWidgetPayload.fetchFailed(service.lastPublished, now: now),
      );

      expect(host.saved.single.items.single.id, '1');
      expect(host.saved.single.note, '지금은 못 불러왔어요 · 오전 9:14 기준');
    });

    test('캐시에 보여 줄 것이 없으면 불러오는 중을 발행한다', () async {
      final host = FakeTodoWidgetHost(
        stored: TodoWidgetPayload.loggedOut(now: now),
      );
      final service = TodoWidgetService(host);

      await service.primeFromCache(now: now);

      // 이전 사용자의 로그아웃 캐시를 가리는 것이 상태 2의 목적이다.
      expect(host.saved.single.centerText, AppStrings.widgetLoading);
    });

    test('캐시가 아예 없어도, 되읽기가 실패해도 불러오는 중은 발행된다', () async {
      final empty = FakeTodoWidgetHost();
      await TodoWidgetService(empty).primeFromCache(now: now);
      expect(empty.saved.single.centerText, AppStrings.widgetLoading);

      final broken = FakeTodoWidgetHost(readError: StateError('no plugin'));
      await TodoWidgetService(broken).primeFromCache(now: now);
      expect(broken.saved.single.centerText, AppStrings.widgetLoading);
    });
  });

  test('로그아웃 발행은 목록을 비운다', () async {
    final host = FakeTodoWidgetHost();
    final service = TodoWidgetService(host);
    await service.publish(TodoWidgetPayload.fromTodos([_todo('1')], now: now));

    await service.publish(TodoWidgetPayload.loggedOut(now: now));

    expect(host.saved.last.items, isEmpty);
    expect(host.saved.last.centerText, AppStrings.widgetLoggedOut);
  });
}

Todo _todo(String id) {
  return Todo(
    id: id,
    title: '할 일 $id',
    isDone: false,
    createdAt: DateTime(2026, 11, 4, 8),
  );
}
