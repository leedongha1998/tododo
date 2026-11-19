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
    expect(published.note, '못 불러왔어요 · 오전 9:14 기준');
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
      expect(host.saved.single.note, '못 불러왔어요 · 오전 9:14 기준');
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

  // "방금 누른 줄은 반드시 보인다"는 예외의 **수명**이 여기서 결정된다(design 7.2 (1)).
  // 적어 두는 자리(`AuthGate`)와 발행하는 자리(`MainShell`)가 달라서 그 사이를 서비스가 잇는다.
  group('markJustChecked', () {
    final todos = [_todo('1', isDone: true), _todo('2')];

    test('적어 둔 id가 다음 한 번의 발행에만 쓰인다', () async {
      final host = FakeTodoWidgetHost();
      final service = TodoWidgetService(host);

      service.markJustChecked('1', at: now);
      await service.publishTodos(todos, now: now);
      // 첫 발행에서는 그 완료 줄이 rank 0을 받아 어떤 줄 자리 수에서도 보인다.
      expect(host.saved.last.items.first.rank, 0);
      expect(host.saved.last.items.first.id, '1');

      // 목록을 다시 받은 두 번째 발행에는 그 예외가 남아 있지 않다(평소 랭크로 돌아간다).
      await service.publishTodos([...todos, _todo('3')], now: now);
      final later = host.saved.last.items;
      expect(later.firstWhere((item) => item.id == '1').rank, 2);
      expect(later.firstWhere((item) => item.id == '2').rank, 0);
    });

    test('60초가 지난 기억은 쓰이지 않는다', () async {
      final host = FakeTodoWidgetHost();
      final service = TodoWidgetService(host);

      // 쓰기는 성공했는데 목록 재조회가 한참 늦어진 경우다 — 엉뚱한 발행이 예외를 쓰지 않는다.
      service.markJustChecked('1', at: now);
      await service.publishTodos(
        todos,
        now: now.add(const Duration(seconds: 60)),
      );

      expect(host.saved.last.items.firstWhere((i) => i.id == '1').rank, 1);
    });

    test('적어 두지 않았으면 평소 랭크로 발행된다', () async {
      final host = FakeTodoWidgetHost();
      final service = TodoWidgetService(host);

      await service.publishTodos(todos, now: now);

      // 미완료가 먼저 고른다.
      expect(host.saved.last.items.firstWhere((i) => i.id == '2').rank, 0);
      expect(host.saved.last.items.firstWhere((i) => i.id == '1').rank, 1);
    });
  });

  // 2026-11-19(추가 범위 3 K): 위젯에서 누른 체크의 **결말**을 그 자리에서 발행한다. 앱이 이미
  // 든 목록을 쓰므로 왕복이 하나 준다.
  group('publishChecked', () {
    final todos = [_todo('1'), _todo('2')];

    test('그 한 줄만 바꿔 발행하고 방금 누른 줄 예외를 쓴다', () async {
      final host = FakeTodoWidgetHost();
      final service = TodoWidgetService(host);

      await service.publishChecked(
        todos,
        todoId: '1',
        done: true,
        now: now,
      );

      final published = host.saved.last;
      expect(published.items.map((item) => item.id), ['1', '2']);
      expect(published.items.map((item) => item.done), [true, false]);
      // 방금 누른 줄은 어떤 줄 자리 수에서도 보인다.
      expect(published.items.first.rank, 0);
      expect(published.totalCount, 1);
    });

    test('기준 시각을 앞당기지 않는다', () async {
      final host = FakeTodoWidgetHost();
      final service = TodoWidgetService(host);
      await service.publishTodos(todos, now: now);

      await service.publishChecked(
        todos,
        todoId: '1',
        done: true,
        now: now.add(const Duration(hours: 3)),
      );

      // 체크는 목록을 새로 받아온 것이 아니다 — 직전 발행의 나이를 그대로 물려준다.
      expect(host.saved.last.updatedAtMs, host.saved.first.updatedAtMs);
    });

    test('적어 둔 기억을 소비하지 않는다', () async {
      final host = FakeTodoWidgetHost();
      final service = TodoWidgetService(host);

      service.markJustChecked('1', at: now);
      await service.publishChecked(
        todos,
        todoId: '1',
        done: true,
        now: now,
      );
      // 뒤따르는 보정 발행(`invalidate` → MainShell)이 그 기억을 써야 한다. 여기서 소비하면
      // 1~2초 뒤 **방금 누른 줄이 사라진다.**
      await service.publishTodos(todosWithDone(todos, '1', true), now: now);

      expect(host.saved.last.items.first.id, '1');
      expect(host.saved.last.items.first.rank, 0);
    });
  });
}

Todo _todo(String id, {bool isDone = false}) {
  return Todo(
    id: id,
    title: '할 일 $id',
    isDone: isDone,
    createdAt: DateTime(2026, 11, 4, 8),
  );
}
