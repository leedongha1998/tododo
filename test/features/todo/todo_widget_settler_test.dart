import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:todododo/core/strings.dart';
import 'package:todododo/features/auth/data/auth_repository.dart';
import 'package:todododo/features/auth/domain/auth_providers.dart';
import 'package:todododo/features/todo/data/todo.dart';
import 'package:todododo/features/todo/data/todo_repository.dart';
import 'package:todododo/features/todo/data/todo_widget_payload.dart';
import 'package:todododo/features/todo/domain/todo_providers.dart';
import 'package:todododo/features/todo/domain/todo_widget_tap_settler.dart';

import 'todo_widget_fakes.dart';

/// 앱 쪽 **정산기**(design 9장의 신규 파일). 백그라운드가 맡긴 묶음과 앱 열림 계기 ④가 같은
/// 규칙을 지나는지를 여기서 고정한다 — isolate·네트워크는 테스트하지 않고(design 11.2) 그
/// 안에서 **판단하는 부분**만 본다.
void main() {
  final now = DateTime(2026, 11, 20, 9, 14);

  ({ProviderContainer container, FakeTodoWidgetHost host, _FakeTodoRepository repository})
  setUp({
    List<Todo>? todos,
    bool signedIn = true,
    String? failingId,
    TodoWidgetPayload? stored,
    String? storedMarks,
  }) {
    final host = FakeTodoWidgetHost(stored: stored, storedMarks: storedMarks);
    final repository = _FakeTodoRepository(failingId: failingId);
    final container = ProviderContainer(
      overrides: [
        ...todoWidgetOverrides(host: host),
        todoRepositoryProvider.overrideWithValue(repository),
        authRepositoryProvider.overrideWithValue(
          _FakeAuthRepository(signedIn: signedIn),
        ),
        todosProvider.overrideWith((ref) async => todos ?? const []),
      ],
      retry: (retryCount, error) => null,
    );
    addTearDown(container.dispose);
    return (container: container, host: host, repository: repository);
  }

  final todos = [
    _todo('1', '장보기'),
    _todo('2', '운동하기'),
    _todo('3', '책 반납'),
  ];

  test('세 줄 중 하나가 실패하면 발행이 한 번이고 실패 줄이 앞에 온다', () async {
    final fixture = setUp(todos: todos, failingId: '2');
    // 목록이 이미 손에 있는 상태(= 앱이 떠 있고 할 일 탭을 지났다). 앱에서는 `MainShell`이 늘
    // 구독하고 있으므로 여기서도 구독을 쥔다 — todosProvider는 autoDispose라 구독자가 없으면 버려진다.
    final shell = fixture.container.listen(todosProvider, (_, _) {});
    addTearDown(shell.close);
    await fixture.container.read(todosProvider.future);

    final outcome = await fixture.container
        .read(todoWidgetTapSettlerProvider)
        .settle(
          const [
            TodoWidgetCheckTarget(id: '1', done: true),
            TodoWidgetCheckTarget(id: '2', done: true),
            TodoWidgetCheckTarget(id: '3', done: true),
          ],
          claimedGen: 7,
        );

    // 세 줄을 **병렬로** 쓴다(줄마다 자기 try라 한 줄의 실패가 나머지를 막지 않는다).
    expect(fixture.repository.wrote, hasLength(3));
    // **발행은 한 번이다**(spec Q: 묶음마다 결말 하나).
    expect(fixture.host.saved, hasLength(1));
    final published = fixture.host.saved.single;
    expect(published.items.map((item) => item.done), [true, false, true]);
    // 되돌아간 줄이 보이는 자리를 **먼저** 받는다(spec S).
    expect(published.items.firstWhere((item) => item.id == '2').rank, 0);
    expect(published.note, AppStrings.widgetCheckFailed);
    expect(published.noteTone, TodoWidgetNoteTone.danger);
    expect(published.settledGen, 7);
    // 줄마다 성공·실패가 갈렸어도 **결말을 발행했다**는 답이다 — 백그라운드가 그 위에 실패 한
    // 줄을 덮어쓰지 않는다.
    expect(outcome, TodoWidgetSettleOutcome.settled);
  });

  test('로그인 화면이면 쓰지 않고 로그아웃으로 답한다', () async {
    final fixture = setUp(todos: todos, signedIn: false);

    final outcome = await fixture.container
        .read(todoWidgetTapSettlerProvider)
        .settle(
          const [TodoWidgetCheckTarget(id: '1', done: true)],
          claimedGen: 1,
        );

    expect(outcome, TodoWidgetSettleOutcome.loggedOut);
    expect(fixture.repository.wrote, isEmpty);
    expect(fixture.host.saved, isEmpty);
  });

  test('목록을 아직 못 받아왔으면 캐시로 같은 결말을 만든다', () async {
    final stored = TodoWidgetPayload.fromTodos(todos, now: now);
    final fixture = setUp(todos: todos, stored: stored);
    final service = fixture.container.read(todoWidgetServiceProvider);
    await service.primeFromCache(now: now);

    // `todosProvider`를 읽지 않은 상태 = 앱이 막 떠서 목록이 손에 없다.
    final outcome = await fixture.container
        .read(todoWidgetTapSettlerProvider)
        .settle(
          const [TodoWidgetCheckTarget(id: '1', done: true)],
          claimedGen: 3,
        );

    expect(outcome, TodoWidgetSettleOutcome.settled);
    // 세대를 올리지 않으면 쓰기가 끝난 줄의 낙관 그림이 되돌림 시각까지 남는다.
    expect(service.settledGen, 3);
    expect(fixture.host.saved.last.items.first.done, isTrue);
    expect(fixture.host.saved.last.settledGen, 3);
  });

  // 떠나는 계기 ④(앱이 열린다 — design 6.3). **떠날 시각이 지난 묶음만** 집는다.
  group('settleLapsed', () {
    TodoWidgetPayload cacheOf() => TodoWidgetPayload.fromTodos(todos, now: now);

    test('떠날 시각이 지난 자국을 그 자리에서 마무리한다', () async {
      final fixture = setUp(
        todos: todos,
        stored: cacheOf(),
        storedMarks: marksJson(
          gen: 2,
          batchAtMs: now.millisecondsSinceEpoch,
          lastAtMs: now.millisecondsSinceEpoch,
          marks: [
            mark(gen: 1, id: '1', done: true, at: now),
            mark(gen: 2, id: '3', done: true, at: now),
          ],
        ),
      );

      await fixture.container
          .read(todoWidgetTapSettlerProvider)
          .settleLapsed(now: now.add(const Duration(seconds: 3)));

      expect(fixture.repository.wrote.map((write) => write.id), ['1', '3']);
      expect(fixture.host.saved, hasLength(1));
      expect(fixture.host.saved.single.settledGen, 2);
    });

    test('아직 모으는 중인 묶음은 건드리지 않는다', () async {
      final fixture = setUp(
        todos: todos,
        stored: cacheOf(),
        storedMarks: marksJson(
          gen: 1,
          batchAtMs: now.millisecondsSinceEpoch,
          lastAtMs: now.millisecondsSinceEpoch,
          marks: [mark(gen: 1, id: '1', done: true, at: now)],
        ),
      );

      // 떠날 시각(= 마지막 탭 + 1초) 전에 앱이 열렸다 → 일꾼의 것이다(두 일꾼을 만들지 않는다).
      await fixture.container
          .read(todoWidgetTapSettlerProvider)
          .settleLapsed(now: now.add(const Duration(milliseconds: 500)));

      expect(fixture.repository.wrote, isEmpty);
      expect(fixture.host.saved, isEmpty);
    });

    test('이미 정산된 세대면 아무것도 하지 않는다', () async {
      final fixture = setUp(
        todos: todos,
        stored: TodoWidgetPayload.fromTodos(todos, now: now, settledGen: 2),
        storedMarks: marksJson(
          gen: 2,
          batchAtMs: now.millisecondsSinceEpoch,
          lastAtMs: now.millisecondsSinceEpoch,
          marks: [mark(gen: 2, id: '1', done: true, at: now)],
        ),
      );
      await fixture.container
          .read(todoWidgetServiceProvider)
          .primeFromCache(now: now);

      await fixture.container
          .read(todoWidgetTapSettlerProvider)
          .settleLapsed(now: now.add(const Duration(seconds: 3)));

      expect(fixture.repository.wrote, isEmpty);
    });

    test('상쇄만 있었던 묶음은 쓰지도 발행하지도 않는다', () async {
      final fixture = setUp(
        todos: todos,
        stored: cacheOf(),
        storedMarks: marksJson(
          gen: 2,
          batchAtMs: now.millisecondsSinceEpoch,
          lastAtMs: now.millisecondsSinceEpoch,
          marks: [
            mark(gen: 1, id: '1', done: true, at: now),
            mark(gen: 2, id: '1', done: false, at: now),
          ],
        ),
      );

      await fixture.container
          .read(todoWidgetTapSettlerProvider)
          .settleLapsed(now: now.add(const Duration(seconds: 3)));

      // spec P: 보낼 것이 없고, 그 줄에 실패 한 줄도 띄우지 않는다.
      expect(fixture.repository.wrote, isEmpty);
      expect(fixture.host.saved, isEmpty);
      // 그래도 세대는 올라간다(그 자국이 다시 효력을 갖지 않게).
      expect(fixture.container.read(todoWidgetServiceProvider).settledGen, 2);
    });

    test('자국이 없으면 조용히 끝난다', () async {
      final fixture = setUp(todos: todos, stored: cacheOf());

      await fixture.container
          .read(todoWidgetTapSettlerProvider)
          .settleLapsed(now: now);

      expect(fixture.repository.wrote, isEmpty);
      expect(fixture.host.saved, isEmpty);
    });
  });
}

/// 쓰기 호출을 받아 적는 가짜. [failingId]로 **한 줄만 실패하는** 상황을 만든다(실기기에서
/// 만들기 어려운 경우라 spec S가 유닛 테스트로 덮으라고 못 박았다).
class _FakeTodoRepository implements TodoRepository {
  _FakeTodoRepository({this.failingId});

  final String? failingId;
  final wrote = <({String id, bool done})>[];

  @override
  Future<void> setDone(String id, bool isDone) async {
    wrote.add((id: id, done: isDone));
    if (id == failingId) throw StateError('network down');
  }

  @override
  Future<List<Todo>> fetchTodos(String userId) async => const [];

  @override
  Future<void> addTodo(String userId, String title, {DateTime? dueAt}) async {}

  @override
  Future<void> updateTodo(
    String id, {
    required String title,
    required DateTime? dueAt,
  }) async {}

  @override
  Future<void> deleteTodo(String id) async {}

  @override
  Future<void> moveTodo(String todoId, {required String? afterId}) async {}
}

class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository({required this.signedIn});

  final bool signedIn;

  @override
  Stream<AuthState> get authStateChanges => const Stream.empty();

  @override
  User? get currentUser => signedIn
      ? const User(
          id: 'me',
          appMetadata: {},
          userMetadata: {},
          aud: 'authenticated',
          createdAt: '2026-11-20T00:00:00Z',
        )
      : null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Todo _todo(String id, String title, {bool isDone = false}) {
  return Todo(
    id: id,
    title: title,
    isDone: isDone,
    createdAt: DateTime(2026, 11, 20, 8),
  );
}
