import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthState, User;

import 'package:todododo/features/auth/data/auth_repository.dart';
import 'package:todododo/features/auth/domain/auth_providers.dart';
import 'package:todododo/features/battle/domain/battle_providers.dart';
import 'package:todododo/features/todo/data/todo.dart';
import 'package:todododo/features/todo/data/todo_repository.dart';
import 'package:todododo/features/todo/domain/todo_providers.dart';
import 'package:todododo/features/todo/presentation/todo_list_screen.dart';

import '../../core/push/push_fakes.dart';
import '../../helpers/text_finders.dart';
import 'due_alarm_fakes.dart';

/// 남은 시간 문구가 **아무것도 저장하지 않아도 스스로 줄어드는지**(2026-11-12 버그).
///
/// 증상은 이랬다: 기한을 넣어 두고 앱에 들어가면 문구가 첫 build 때의 값에 멈춰 있고, 할 일을
/// 수정해 저장해야(= `todosProvider`가 다시 불려야) 맞는 값이 됐다. 이 화면은 `MainShell`의
/// IndexedStack에 계속 살아 있어 탭을 오가거나 앱을 다시 열어도 스스로 다시 그리지 않는다.
///
/// 문구 규칙과 "다음에 글자가 바뀌는 때"는 `domain/due_date_rules_test.dart`가 지킨다. 여기서
/// 보는 것은 **화면이 그 약속대로 깨어나는지**다.
///
/// 시간을 두 군데서 함께 돌린다 — `todoNowProvider`(화면이 읽는 "지금")와 `tester.pump`의 가짜
/// 시계(타이머가 깨는 시각)다. 기한을 **분 경계에 딱 맞추지 않는** 이유가 있다: 경계에 앉으면
/// 다음 간격이 1밀리초가 되어(그게 맞다 — 글자가 곧 바뀐다) 시계를 세운 채 pumpAndSettle하면
/// 1밀리초마다 다시 그리며 맴돈다. 실제 앱에서는 시계가 흐르므로 일어나지 않는 일이다.
void main() {
  testWidgets('저장하지 않아도 분이 넘어가면 남은 시간이 줄어든다', (tester) async {
    final clock = _FakeClock(DateTime(2026, 11, 12, 12, 0, 20));
    final repository = _FakeTodoRepository([
      _todo(dueAt: DateTime(2026, 11, 12, 14, 30, 32)),
    ]);

    await tester.pumpWidget(_app(repository, clock));
    await tester.pumpAndSettle();

    expect(findText('2시간 30분 남음'), findsOneWidget);
    expect(repository.fetchCount, 1);

    // 분이 넘어가는 순간(12초 뒤)을 지나게 둔다.
    clock.advance(const Duration(seconds: 13));
    await tester.pump(const Duration(seconds: 13));

    expect(findText('2시간 29분 남음'), findsOneWidget);
    // **다시 조회하지 않는다.** 바뀐 것은 글자뿐이라 서버에 묻는 일이 아니다.
    expect(repository.fetchCount, 1);
  });

  testWidgets('1분 미만 남으면 초가 1초마다 바뀐다', (tester) async {
    final clock = _FakeClock(DateTime(2026, 11, 12, 12, 0, 0, 300));
    final repository = _FakeTodoRepository([
      _todo(dueAt: DateTime(2026, 11, 12, 12, 0, 40)),
    ]);

    await tester.pumpWidget(_app(repository, clock));
    await tester.pumpAndSettle();

    expect(findText('39초 남음'), findsOneWidget);

    clock.advance(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(findText('38초 남음'), findsOneWidget);

    clock.advance(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(findText('37초 남음'), findsOneWidget);
  });

  testWidgets('기한이 지나는 순간도 스스로 넘어간다', (tester) async {
    final clock = _FakeClock(DateTime(2026, 11, 12, 11, 59, 58));
    final repository = _FakeTodoRepository([
      _todo(dueAt: DateTime(2026, 11, 12, 12, 0, 0)),
    ]);

    await tester.pumpWidget(_app(repository, clock));
    await tester.pumpAndSettle();

    expect(findText('2초 남음'), findsOneWidget);

    // 기한을 넘기면 `방금 지남`, 1분이 더 지나면 `1분 지남`이다(8구간 표 5·6행).
    clock.advance(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 3));
    expect(findText('방금 지남'), findsOneWidget);

    clock.advance(const Duration(minutes: 1));
    await tester.pump(const Duration(minutes: 1));
    expect(findText('1분 지남'), findsOneWidget);
  });

  testWidgets('앱에 다시 들어오면 그 자리에서 맞는 값이 된다', (tester) async {
    final clock = _FakeClock(DateTime(2026, 11, 12, 12, 0, 20));
    final repository = _FakeTodoRepository([
      _todo(dueAt: DateTime(2026, 11, 12, 14, 30, 32)),
    ]);

    await tester.pumpWidget(_app(repository, clock));
    await tester.pumpAndSettle();
    expect(findText('2시간 30분 남음'), findsOneWidget);

    // 뒤로 보낸다 — 여기서 타이머를 거둔다.
    await _lifecycle(tester, [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]);

    // 세 시간 뒤에 돌아온다. 그동안 provider는 다시 불리지 않았다.
    clock.advance(const Duration(hours: 3));
    await _lifecycle(tester, [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]);
    await tester.pumpAndSettle();

    expect(findText('29분 지남'), findsOneWidget);
    expect(repository.fetchCount, 1);
  });

  testWidgets('완료한 줄은 문구가 없고 타이머도 걸지 않는다', (tester) async {
    final clock = _FakeClock(DateTime(2026, 11, 12, 12, 0, 20));
    final repository = _FakeTodoRepository([
      _todo(dueAt: DateTime(2026, 11, 12, 14, 30, 32), isDone: true),
    ]);

    // 걸어 둔 타이머를 dispose가 거두지 않으면 테스트가 끝날 때 "A Timer is still pending"으로
    // 깨진다 — 그 점도 이 파일이 함께 지킨다.
    await tester.pumpWidget(_app(repository, clock));
    await tester.pumpAndSettle();

    expect(findTextContaining('남음'), findsNothing);

    clock.advance(const Duration(hours: 3));
    await tester.pump(const Duration(hours: 3));

    expect(findTextContaining('지남'), findsNothing);
  });
}

/// 생애 주기 상태를 순서대로 보낸다. **한 칸씩** 보내야 한다 — `AppLifecycleListener`가
/// 건너뛴 전이를 단정으로 막는다(안드로이드의 실제 순서도 resumed→inactive→hidden→paused다).
Future<void> _lifecycle(WidgetTester tester, List<AppLifecycleState> states) async {
  for (final state in states) {
    tester.binding.handleAppLifecycleStateChanged(state);
    await tester.pump();
  }
}

/// 손으로 돌리는 시계. `tester.pump`의 가짜 시계와 **함께** 움직여야 한다 — 전자는 화면이 읽는
/// "지금"이고 후자는 타이머가 깨는 시각이다.
class _FakeClock {
  _FakeClock(this._now);

  DateTime _now;

  DateTime now() => _now;

  void advance(Duration by) => _now = _now.add(by);
}

Todo _todo({required DateTime dueAt, bool isDone = false}) => Todo(
  id: '1',
  title: '장보기',
  isDone: isDone,
  createdAt: DateTime(2026, 11, 10, 8),
  // 서버는 UTC로 준다(Todo.dueAt 문서). 화면이 toLocal()해서 쓰므로 여기서 거꾸로 돌려 둔다.
  dueAt: dueAt.toUtc(),
);

Widget _app(TodoRepository repository, _FakeClock clock) {
  return ProviderScope(
    overrides: [
      todoRepositoryProvider.overrideWithValue(repository),
      authRepositoryProvider.overrideWithValue(_SignedInAuthRepository()),
      todoNowProvider.overrideWithValue(clock.now),
      todosProvider.overrideWith((ref) {
        return ref.watch(todoRepositoryProvider).fetchTodos('me');
      }),
      myBattlesProvider.overrideWith((ref) async => const []),
      ...pushOverrides(),
      ...dueAlarmOverrides(),
    ],
    child: const MaterialApp(home: TodoListScreen()),
  );
}

/// 조회 횟수만 세는 가짜. 이 파일이 보는 것은 **다시 그리기**이고, 다시 그리는 동안 서버에
/// 묻지 않는다는 것이 이 방식을 고른 이유다.
class _FakeTodoRepository implements TodoRepository {
  _FakeTodoRepository(this._stored);

  final List<Todo> _stored;
  int fetchCount = 0;

  @override
  Future<List<Todo>> fetchTodos(String userId) async {
    fetchCount++;
    return List.of(_stored);
  }

  @override
  Future<void> moveTodo(String todoId, {required String? afterId}) async {}

  @override
  Future<void> addTodo(String userId, String title, {DateTime? dueAt}) async {}

  @override
  Future<void> setDone(String id, bool isDone) async {}

  @override
  Future<void> updateTodo(
    String id, {
    required String title,
    required DateTime? dueAt,
  }) async {}

  @override
  Future<void> deleteTodo(String id) async {}
}

class _SignedInAuthRepository implements AuthRepository {
  @override
  Stream<AuthState> get authStateChanges => const Stream.empty();

  @override
  User? get currentUser => const User(
    id: 'me',
    appMetadata: {},
    userMetadata: {},
    aud: 'authenticated',
    createdAt: '2026-11-10T00:00:00Z',
  );

  @override
  Future<void> signInWithGoogle() async {}

  @override
  Future<void> signOut() async {}

  @override
  Future<void> deleteAccount() async {}
}
