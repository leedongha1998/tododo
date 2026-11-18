import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:todododo/core/strings.dart';
import 'package:todododo/features/auth/data/auth_repository.dart';
import 'package:todododo/features/auth/domain/auth_providers.dart';
import 'package:todododo/features/battle/domain/battle_providers.dart';
import 'package:todododo/features/todo/data/todo.dart';
import 'package:todododo/features/todo/data/todo_widget_notice_store.dart';
import 'package:todododo/features/todo/domain/todo_providers.dart';
import 'package:todododo/features/todo/presentation/todo_list_screen.dart';

import '../../core/push/push_fakes.dart';
import '../../helpers/text_finders.dart';
import '../notification/notification_fakes.dart';
import 'due_alarm_fakes.dart';

/// 홈 화면 노출 안내(home-widget design 7.1). 가리기 설정을 만들지 않는 대신 **한 번** 말하는
/// 자리이고, 드러나는 것이 "제목과 기한" 둘이라는 사실까지 말해야 한다(spec 수용 기준).
void main() {
  testWidgets('처음 열면 홈 화면에 무엇이 보이는지 한 번 알린다', (
    WidgetTester tester,
  ) async {
    final store = _MemoryNoticeStore();

    await tester.pumpWidget(_app(store));
    await tester.pumpAndSettle();

    expect(findText(AppStrings.widgetNotice), findsOneWidget);
    // 위젯에 드러나는 것이 제목 하나에서 제목과 기한 둘로 늘었다.
    expect(AppStrings.widgetNotice, contains('제목과 기한'));
  });

  testWidgets('닫으면 사라지고 다시 열어도 뜨지 않는다', (WidgetTester tester) async {
    final store = _MemoryNoticeStore();

    await tester.pumpWidget(_app(store));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(AppStrings.widgetNoticeDismiss));
    await tester.pumpAndSettle();

    expect(findText(AppStrings.widgetNotice), findsNothing);
    expect(store.seen, contains(TodoWidgetNoticeStore.keyFor('me')));

    // 같은 기기·같은 계정에서 다시 열었을 때(= 화면을 새로 띄웠을 때) 또 뜨지 않는다.
    await tester.pumpWidget(_app(store));
    await tester.pumpAndSettle();
    expect(findText(AppStrings.widgetNotice), findsNothing);
  });

  testWidgets('기록을 읽지 못하면 안내를 띄우지 않는다', (WidgetTester tester) async {
    // 안내는 관문이 아니다 — 읽기 실패에 토스트를 띄우거나 화면을 막지 않고 로그만 남긴다.
    await tester.pumpWidget(_app(_BrokenNoticeStore()));
    await tester.pumpAndSettle();

    expect(findText(AppStrings.widgetNotice), findsNothing);
    expect(findText('설거지하기'), findsOneWidget);
  });
}

Widget _app(TodoWidgetNoticeStore store) {
  return ProviderScope(
    overrides: [
      ...notificationOverrides,
      authRepositoryProvider.overrideWithValue(_SignedInAuthRepository()),
      todosProvider.overrideWith(
        (ref) async => [
          Todo(
            id: 'a',
            title: '설거지하기',
            isDone: false,
            createdAt: DateTime(2026, 11, 18, 8),
          ),
        ],
      ),
      myBattlesProvider.overrideWith((ref) async => const []),
      todoWidgetNoticeStoreProvider.overrideWithValue(store),
      ...pushOverrides(),
      ...dueAlarmOverrides(),
    ],
    child: const MaterialApp(home: TodoListScreen()),
  );
}

/// 기기 기록 대신 쓰는 가짜(선례: `_MemorySeenStore`). 계정별 키를 그대로 쓴다.
class _MemoryNoticeStore extends TodoWidgetNoticeStore {
  final seen = <String>{};

  @override
  Future<bool> hasSeen(String userId) async =>
      seen.contains(TodoWidgetNoticeStore.keyFor(userId));

  @override
  Future<void> markSeen(String userId) async =>
      seen.add(TodoWidgetNoticeStore.keyFor(userId));
}

class _BrokenNoticeStore extends TodoWidgetNoticeStore {
  @override
  Future<bool> hasSeen(String userId) async => throw StateError('no prefs');
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
    createdAt: '2026-11-18T00:00:00Z',
  );

  @override
  Future<void> signInWithGoogle() async {}

  @override
  Future<void> signOut() async {}

  @override
  Future<void> deleteAccount() async {}
}
