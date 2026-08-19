import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:todododo/core/strings.dart';
import 'package:todododo/features/auth/presentation/login_screen.dart';
import 'package:todododo/features/battle/data/battle.dart';
import 'package:todododo/features/battle/data/battle_repository.dart';
import 'package:todododo/features/battle/data/profile.dart';
import 'package:todododo/features/battle/domain/battle_invite.dart';
import 'package:todododo/features/battle/domain/battle_providers.dart';
import 'package:todododo/features/battle/presentation/battle_invites_screen.dart';
import 'package:todododo/features/battle/presentation/create_battle_screen.dart';
import 'package:todododo/features/todo/data/todo.dart';
import 'package:todododo/features/todo/domain/todo_providers.dart';
import 'package:todododo/features/todo/presentation/todo_list_screen.dart';
import 'package:todododo/main.dart';

class _FakeBattleRepository implements BattleRepository {
  @override
  Future<List<Profile>> searchProfiles(String query) async {
    return const [Profile(id: 'u1', displayName: '테스트유저')];
  }

  @override
  Future<void> createBattle({
    required String opponentId,
    required String type,
    required String title,
  }) async {}

  @override
  Future<List<Battle>> fetchReceivedInvites() async => const [];

  @override
  Future<List<Battle>> fetchSentInvites() async => const [];

  @override
  Future<Map<String, String>> fetchDisplayNames(Iterable<String> ids) async => {};

  @override
  Future<void> acceptBattle(String battleId) async {}
}

void main() {
  testWidgets('Supabase 미설정 시 설정 안내를 보여준다', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: TododuduApp()));

    expect(find.textContaining('Supabase 설정이 필요합니다'), findsOneWidget);
  });

  testWidgets('로그인 화면에 구글 로그인 버튼이 보인다', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: LoginScreen()),
      ),
    );

    expect(find.text(AppStrings.googleSignIn), findsOneWidget);
  });

  testWidgets('할 일이 없으면 빈 상태 문구를 보여준다', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [todosProvider.overrideWith((ref) async => const <Todo>[])],
        child: const MaterialApp(home: TodoListScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('아직 할 일이 없어요'), findsOneWidget);
  });

  testWidgets('할 일 목록이 보이고 완료 표시가 취소선으로 나타난다', (WidgetTester tester) async {
    final todos = [
      Todo(id: '1', title: '설거지하기', isDone: false, createdAt: DateTime(2026, 8, 19)),
      Todo(id: '2', title: '빨래하기', isDone: true, createdAt: DateTime(2026, 8, 19)),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [todosProvider.overrideWith((ref) async => todos)],
        child: const MaterialApp(home: TodoListScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('설거지하기'), findsOneWidget);
    expect(find.text('빨래하기'), findsOneWidget);

    final doneText = tester.widget<Text>(find.text('빨래하기'));
    expect(doneText.style?.decoration, TextDecoration.lineThrough);
  });

  testWidgets('상대를 검색해서 선택하면 대결 유형/제목 입력이 나타난다', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [battleRepositoryProvider.overrideWithValue(_FakeBattleRepository())],
        child: const MaterialApp(home: CreateBattleScreen()),
      ),
    );

    expect(find.text(AppStrings.battleTypeSpeed), findsNothing);

    await tester.enterText(find.byType(TextField), '테스트');
    await tester.pumpAndSettle();

    expect(find.text('테스트유저'), findsOneWidget);

    await tester.tap(find.text('테스트유저'));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.battleTypeSpeed), findsOneWidget);
    expect(find.text(AppStrings.battleTypeQuality), findsOneWidget);

    final submitButton = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(submitButton.onPressed, isNull);
  });

  testWidgets('받은 초대가 보이고 수락 버튼이 있다', (WidgetTester tester) async {
    final battle = Battle(
      id: 'b1',
      type: 'speed',
      status: 'pending',
      title: '아침 운동하기',
      creatorId: 'creator1',
      opponentId: 'me',
      createdAt: DateTime(2026, 8, 20),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          receivedInvitesProvider.overrideWith(
            (ref) async => [BattleInvite(battle: battle, otherPartyName: '친구')],
          ),
          sentInvitesProvider.overrideWith((ref) async => const []),
        ],
        child: const MaterialApp(home: BattleInvitesScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('아침 운동하기'), findsOneWidget);
    expect(find.textContaining('친구'), findsOneWidget);
    expect(find.text(AppStrings.battleAccept), findsOneWidget);
  });
}
