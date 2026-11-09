import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthState, User;

import 'package:todododo/core/strings.dart';
import 'package:todododo/core/theme/app_icons.dart';
import 'package:todododo/features/auth/data/auth_repository.dart';
import 'package:todododo/features/auth/domain/auth_providers.dart';
import 'package:todododo/features/battle/domain/battle_providers.dart';
import 'package:todododo/features/todo/data/todo.dart';
import 'package:todododo/features/todo/data/todo_repository.dart';
import 'package:todododo/features/todo/domain/todo_providers.dart';
import 'package:todododo/features/todo/presentation/todo_list_screen.dart';

import '../../helpers/text_finders.dart';

/// 추가·수정 대화상자가 **기한을 쓰지 않는 사용자의 타수를 늘리지 않는지**와
/// **기한만 바꿔도 저장되는지**를 고정한다(todo-due-date spec 수용 기준).
///
/// 대화상자가 `AlertDialog(content: TextField)`에서 `SingleChildScrollView > Column`으로
/// 바뀌었으므로, `autofocus`/`onSubmitted`(= 제목 적고 엔터) 경로가 깨지면 여기서 울어야 한다.
void main() {
  testWidgets('제목만 적고 엔터를 누르면 기한 없는 할 일이 추가된다', (tester) async {
    final repository = _FakeTodoRepository();

    await tester.pumpWidget(_app(repository, const <Todo>[]));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(AppIcons.add));
    await tester.pumpAndSettle();

    // 입력 칸이 autofocus라 바로 글자가 들어가고, 엔터 한 번으로 저장까지 간다.
    await tester.enterText(find.byType(TextField), '설거지하기');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(repository.added, hasLength(1));
    expect(repository.added.single.title, '설거지하기');
    expect(repository.added.single.dueAt, isNull);
    expect(repository.updated, isEmpty);
    // 대화상자가 닫혔다(날짜를 고르라고 막는 단계가 끼어들지 않는다).
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('기한을 정하지 않고 저장 버튼을 눌러도 기한 없는 할 일이 추가된다', (tester) async {
    final repository = _FakeTodoRepository();

    await tester.pumpWidget(_app(repository, const <Todo>[]));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(AppIcons.add));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '빨래하기');
    await tester.tap(findWidgetWithText(FilledButton, AppStrings.save));
    await tester.pumpAndSettle();

    expect(repository.added.single.dueAt, isNull);
  });

  testWidgets('제목을 그대로 두고 기한만 넣어도 저장된다', (tester) async {
    final repository = _FakeTodoRepository();
    final todos = [
      Todo(
        id: 't1',
        title: '보고서 쓰기',
        isDone: false,
        createdAt: DateTime(2026, 11, 8),
      ),
    ];

    await tester.pumpWidget(_app(repository, todos));
    await tester.pumpAndSettle();

    await tester.tap(findText('보고서 쓰기'));
    await tester.pumpAndSettle();

    // 기한 추가 → 달력 확인 → 시간 확인. 둘 다 초기값을 그대로 받으므로
    // "날짜만 고르면 그 날 23:59"가 그대로 들어온다(spec).
    await tester.tap(findText(AppStrings.todoDueAdd));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'OK'));
    await tester.pumpAndSettle();

    await tester.tap(findWidgetWithText(FilledButton, AppStrings.save));
    await tester.pumpAndSettle();

    // 제목이 그대로여도 기한이 바뀌었으므로 저장이 **한 번** 일어난다.
    expect(repository.updated, hasLength(1));
    expect(repository.updated.single.id, 't1');
    expect(repository.updated.single.title, '보고서 쓰기');
    final saved = repository.updated.single.dueAt!.toLocal();
    expect(saved.hour, 23);
    expect(saved.minute, 59);
  });

  testWidgets('제목도 기한도 그대로면 저장하지 않는다', (tester) async {
    final repository = _FakeTodoRepository();
    final todos = [
      Todo(
        id: 't1',
        title: '보고서 쓰기',
        isDone: false,
        createdAt: DateTime(2026, 11, 8),
        dueAt: DateTime(2026, 11, 12, 18).toUtc(),
      ),
    ];

    await tester.pumpWidget(_app(repository, todos));
    await tester.pumpAndSettle();

    await tester.tap(findText('보고서 쓰기'));
    await tester.pumpAndSettle();
    await tester.tap(findWidgetWithText(FilledButton, AppStrings.save));
    await tester.pumpAndSettle();

    expect(repository.updated, isEmpty);
  });

  testWidgets('기한 지우기를 누르고 저장하면 기한이 null로 저장된다', (tester) async {
    final repository = _FakeTodoRepository();
    final todos = [
      Todo(
        id: 't1',
        title: '보고서 쓰기',
        isDone: false,
        createdAt: DateTime(2026, 11, 8),
        dueAt: DateTime(2026, 11, 12, 18).toUtc(),
      ),
    ];

    await tester.pumpWidget(_app(repository, todos));
    await tester.pumpAndSettle();

    await tester.tap(findText('보고서 쓰기'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(AppStrings.todoDueClear));
    await tester.pumpAndSettle();
    await tester.tap(findWidgetWithText(FilledButton, AppStrings.save));
    await tester.pumpAndSettle();

    expect(repository.updated, hasLength(1));
    expect(repository.updated.single.dueAt, isNull);
  });
}

Widget _app(TodoRepository repository, List<Todo> todos) {
  return ProviderScope(
    overrides: [
      todoRepositoryProvider.overrideWithValue(repository),
      authRepositoryProvider.overrideWithValue(_SignedInAuthRepository()),
      todosProvider.overrideWith((ref) async => todos),
      myBattlesProvider.overrideWith((ref) async => const []),
    ],
    child: const MaterialApp(home: TodoListScreen()),
  );
}

/// 쓰기 호출을 받아 적는 가짜. 실제 플러그인·네트워크에 닿지 않는다
/// (가짜를 `implements`로 만들고 override로 끼우는 선례: `todo_widget_fakes.dart`).
class _FakeTodoRepository implements TodoRepository {
  final added = <_Added>[];
  final updated = <_Updated>[];

  @override
  Future<List<Todo>> fetchTodos(String userId) async => const [];

  @override
  Future<void> addTodo(String userId, String title, {DateTime? dueAt}) async {
    added.add(_Added(title: title, dueAt: dueAt));
  }

  @override
  Future<void> updateTodo(
    String id, {
    required String title,
    required DateTime? dueAt,
  }) async {
    updated.add(_Updated(id: id, title: title, dueAt: dueAt));
  }

  @override
  Future<void> setDone(String id, bool isDone) async {}

  @override
  Future<void> deleteTodo(String id) async {}
}

class _Added {
  const _Added({required this.title, required this.dueAt});

  final String title;
  final DateTime? dueAt;
}

class _Updated {
  const _Updated({required this.id, required this.title, required this.dueAt});

  final String id;
  final String title;
  final DateTime? dueAt;
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
    createdAt: '2026-11-09T00:00:00Z',
  );

  @override
  Future<void> signInWithGoogle() async {}

  @override
  Future<void> signOut() async {}

  @override
  Future<void> deleteAccount() async {}
}
