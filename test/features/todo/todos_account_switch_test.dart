import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:todododo/features/auth/data/auth_repository.dart';
import 'package:todododo/features/auth/domain/auth_providers.dart';
import 'package:todododo/features/todo/data/todo.dart';
import 'package:todododo/features/todo/data/todo_repository.dart';
import 'package:todododo/features/todo/domain/todo_providers.dart';

/// 같은 기기에서 계정을 바꿔 로그인해도 **이전 계정의 할 일이 한 순간도 보이지 않는다**
/// (kakao-login spec P0-5, design 흐름 4·8.3). 구글로 가입한 사람이 카카오 버튼을 눌러 보는 흔한
/// 경로에서 "남의 데이터가 보이는 듯한" 첫인상을 만들지 않으려는 회귀 테스트다.
///
/// 앱에서 "구독"은 `MainShell`·`TodoListScreen`이고, 로그아웃하면 `AuthGate`가 그 둘을 걷어 낸다.
/// 여기서는 그 일을 `container.listen`을 열고 닫는 것으로 흉내 낸다.
void main() {
  test('로그아웃 뒤 다른 계정으로 로그인하면 이전 계정의 목록 없이 로딩부터 시작한다', () async {
    final auth = _SwitchableAuthRepository('user-a');
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        todoRepositoryProvider.overrideWithValue(
          _FakeTodoRepository({
            'user-a': [_todo('a1', 'A의 할 일')],
            'user-b': [_todo('b1', 'B의 할 일')],
          }),
        ),
      ],
      retry: (retryCount, error) => null,
    );
    addTearDown(container.dispose);

    // ① 계정 A로 로그인해 목록을 본다.
    final shellA = container.listen(todosProvider, (_, _) {});
    await container.read(todosProvider.future);
    expect(container.read(todosProvider).value!.single.title, 'A의 할 일');

    // ② 로그아웃: 셸이 사라져 구독이 빠지고, 한 틱 뒤 버려질 기회를 준다.
    shellA.close();
    await container.pump();
    await Future<void>.delayed(Duration.zero);

    // ③ 같은 프로세스에서 계정 B로 로그인한다.
    auth.userId = 'user-b';

    // ④ 셸이 다시 뜬다. 첫 상태부터 끝까지 A의 목록이 한 번도 관측되면 안 된다.
    final seen = <AsyncValue<List<Todo>>>[];
    final shellB = container.listen(
      todosProvider,
      (_, next) => seen.add(next),
      fireImmediately: true,
    );
    addTearDown(shellB.close);
    await container.read(todosProvider.future);

    expect(seen.first.isLoading, isTrue);
    expect(seen.first.value, isNull, reason: '이전 계정의 값을 들고 시작하면 화면이 그 목록을 그린다');
    final titles = [
      for (final state in seen) ...?state.value?.map((todo) => todo.title),
    ];
    expect(titles, isNot(contains('A의 할 일')));
    expect(container.read(todosProvider).value!.single.title, 'B의 할 일');
  });

  test('로그인한 동안 구독이 붙어 있으면 목록을 다시 받지 않는다', () async {
    final auth = _SwitchableAuthRepository('user-a');
    final repository = _FakeTodoRepository({
      'user-a': [_todo('a1', 'A의 할 일')],
    });
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        todoRepositoryProvider.overrideWithValue(repository),
      ],
      retry: (retryCount, error) => null,
    );
    addTearDown(container.dispose);

    // `MainShell`이 늘 붙어 있는 구독. 탭 화면(`TodoListScreen`)이 붙었다 떨어져도 버려지지 않는다.
    final shell = container.listen(todosProvider, (_, _) {});
    addTearDown(shell.close);
    final tab = container.listen(todosProvider, (_, _) {});
    await container.read(todosProvider.future);
    tab.close();
    await container.pump();
    await Future<void>.delayed(Duration.zero);
    await container.read(todosProvider.future);

    expect(repository.fetchCount, 1);
  });
}

/// 현재 사용자를 바꿀 수 있는 가짜. 계정 전환은 이 값 하나로 흉내 낸다.
class _SwitchableAuthRepository implements AuthRepository {
  _SwitchableAuthRepository(this.userId);

  String userId;

  @override
  User? get currentUser => User(
    id: userId,
    appMetadata: const {},
    userMetadata: const {},
    aud: 'authenticated',
    createdAt: '2026-11-25T00:00:00Z',
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 사용자 id별 목록을 주는 가짜.
class _FakeTodoRepository implements TodoRepository {
  _FakeTodoRepository(this.byUser);

  final Map<String, List<Todo>> byUser;
  int fetchCount = 0;

  @override
  Future<List<Todo>> fetchTodos(String userId) async {
    fetchCount++;
    return byUser[userId] ?? const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Todo _todo(String id, String title) {
  return Todo(
    id: id,
    title: title,
    isDone: false,
    createdAt: DateTime(2026, 11, 25, 9),
  );
}
