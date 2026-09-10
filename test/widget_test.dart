import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthState, User;

import 'package:todododo/core/strings.dart';
import 'package:todododo/features/auth/data/auth_repository.dart';
import 'package:todododo/features/auth/domain/auth_providers.dart';
import 'package:todododo/features/auth/presentation/login_screen.dart';
import 'package:todododo/features/battle/data/battle.dart';
import 'package:todododo/features/battle/data/battle_participant.dart';
import 'package:todododo/features/battle/data/battle_repository.dart';
import 'package:todododo/features/battle/data/profile.dart';
import 'package:todododo/features/battle/domain/battle_detail.dart';
import 'package:todododo/features/battle/domain/battle_providers.dart';
import 'package:todododo/features/battle/domain/battle_recruit.dart';
import 'package:todododo/features/battle/domain/battle_summary.dart';
import 'package:todododo/features/battle/presentation/battle_detail_screen.dart';
import 'package:todododo/core/navigation/main_shell.dart';
import 'package:todododo/features/battle/presentation/battle_recruits_screen.dart';
import 'package:todododo/features/battle/presentation/my_battles_screen.dart';
import 'package:todododo/features/battle/presentation/create_battle_screen.dart';
import 'package:todododo/features/profile/domain/battle_record.dart';
import 'package:todododo/features/profile/domain/profile_providers.dart';
import 'package:todododo/features/profile/presentation/profile_screen.dart';
import 'package:todododo/features/todo/data/todo.dart';
import 'package:todododo/features/todo/domain/todo_providers.dart';
import 'package:todododo/features/todo/presentation/todo_list_screen.dart';
import 'package:todododo/main.dart';

class _FakeBattleRepository implements BattleRepository {
  @override
  Future<void> createBattle({
    required String type,
    required String title,
  }) async {}

  @override
  Future<List<Battle>> fetchOpenRecruits() async => const [];

  @override
  Future<List<Battle>> fetchMyRecruits() async => const [];

  @override
  Future<Map<String, String>> fetchDisplayNames(Iterable<String> ids) async => {};

  @override
  Future<void> joinBattle(String battleId) async {}

  @override
  Future<void> cancelBattle(String battleId) async {}

  @override
  Future<void> forfeitBattle(String battleId) async {}

  @override
  Future<List<Battle>> fetchMyBattles() async => const [];

  @override
  Future<Battle> fetchBattle(String battleId) => throw UnimplementedError();

  @override
  Future<List<BattleParticipant>> fetchParticipants(String battleId) async => const [];

  @override
  Future<String> uploadEvidencePhoto(String battleId, Uint8List bytes) async => 'path';

  @override
  Future<String> createEvidencePhotoUrl(String path) async => 'https://example.com/$path';

  @override
  Future<void> submitEvidence(String battleId, String evidenceType, String content) async {}

  @override
  Future<void> decideEvidence(String battleId, String targetUserId, String decision) async {}
}

class _FakeAuthRepository implements AuthRepository {
  int deleteAccountCount = 0;

  @override
  Stream<AuthState> get authStateChanges => const Stream.empty();

  @override
  User? get currentUser => null;

  @override
  Future<void> signInWithGoogle() async {}

  @override
  Future<void> signOut() async {}

  @override
  Future<void> deleteAccount() async {
    deleteAccountCount++;
  }
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
        overrides: [
          todosProvider.overrideWith((ref) async => const <Todo>[]),
          myBattlesProvider.overrideWith((ref) async => const []),
        ],
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
        overrides: [
          todosProvider.overrideWith((ref) async => todos),
          myBattlesProvider.overrideWith((ref) async => const []),
        ],
        child: const MaterialApp(home: TodoListScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('설거지하기'), findsOneWidget);
    expect(find.text('빨래하기'), findsOneWidget);

    final doneText = tester.widget<Text>(find.text('빨래하기'));
    expect(doneText.style?.decoration, TextDecoration.lineThrough);
  });

  testWidgets('내 대결 화면에는 진행 중인 대결만, 할 일 화면에는 할 일만 보인다', (WidgetTester tester) async {
    final battle = Battle(
      id: 'b1',
      type: 'speed',
      status: 'active',
      title: '아침 운동하기',
      creatorId: 'me',
      opponentId: 'friend',
      createdAt: DateTime(2026, 8, 20),
    );
    final todos = [
      Todo(id: '1', title: '설거지하기', isDone: false, createdAt: DateTime(2026, 8, 19)),
    ];
    final overrides = [
      todosProvider.overrideWith((ref) async => todos),
      myBattlesProvider.overrideWith(
        (ref) async => [BattleSummary(battle: battle, otherPartyName: '친구')],
      ),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: const MaterialApp(home: MyBattlesScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('아침 운동하기'), findsOneWidget);
    expect(find.text('설거지하기'), findsNothing);

    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: const MaterialApp(home: TodoListScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // 두 목록이 한 화면을 나눠 쓰던 구조를 없앴다. 할 일 화면에 대결이 섞이면 안 된다.
    expect(find.text('설거지하기'), findsOneWidget);
    expect(find.text('아침 운동하기'), findsNothing);
  });

  testWidgets('로그인하면 탭 네 개짜리 탭바가 있는 화면으로 들어간다', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          todosProvider.overrideWith((ref) async => []),
          myBattlesProvider.overrideWith((ref) async => []),
          openRecruitsProvider.overrideWith((ref) async => []),
          myRecruitsProvider.overrideWith((ref) async => []),
          myProfileProvider.overrideWith((ref) async => const Profile(id: 'me', displayName: '나')),
          battleRecordsProvider.overrideWith((ref) async => []),
        ],
        child: const MaterialApp(home: MainShell()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationDestination), findsNWidgets(4));
    expect(find.text(AppStrings.battleFind), findsWidgets);
    expect(find.text(AppStrings.todoTitle), findsWidgets);
  });

  testWidgets('할 일 탭의 추가 버튼은 곧장 입력창을 연다', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [todosProvider.overrideWith((ref) async => [])],
        child: const MaterialApp(home: TodoListScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    // 무엇을 추가할지 고르는 단계는 탭이 대신하므로 사라졌다.
    expect(find.text(AppStrings.addTodo), findsOneWidget);
    expect(find.text(AppStrings.battleCreate), findsNothing);
  });

  testWidgets('대결 찾기 화면에 대결 만들기 버튼이 있다', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          openRecruitsProvider.overrideWith((ref) async => []),
          myRecruitsProvider.overrideWith((ref) async => []),
        ],
        child: const MaterialApp(home: BattleRecruitsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FloatingActionButton, AppStrings.battleCreate), findsOneWidget);
  });

  testWidgets('대결 만들기 화면에 유형/제목 입력이 바로 보이고, 제목을 입력하면 등록 버튼이 활성화된다',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [battleRepositoryProvider.overrideWithValue(_FakeBattleRepository())],
        child: const MaterialApp(home: CreateBattleScreen()),
      ),
    );

    expect(find.text(AppStrings.battleTypeSpeed), findsOneWidget);
    expect(find.text(AppStrings.battleTypeQuality), findsOneWidget);

    final initialButton = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(initialButton.onPressed, isNull);

    await tester.enterText(find.byType(TextField), '아침 운동하기');
    await tester.pumpAndSettle();

    final filledButton = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(filledButton.onPressed, isNotNull);
  });

  testWidgets('모집 중인 대결이 보이고 참가 버튼이 있다', (WidgetTester tester) async {
    final battle = Battle(
      id: 'b1',
      type: 'speed',
      status: 'pending',
      title: '아침 운동하기',
      creatorId: 'creator1',
      createdAt: DateTime(2026, 8, 20),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          openRecruitsProvider.overrideWith(
            (ref) async => [BattleRecruit(battle: battle, creatorName: '친구')],
          ),
          myRecruitsProvider.overrideWith((ref) async => const []),
        ],
        child: const MaterialApp(home: BattleRecruitsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('아침 운동하기'), findsOneWidget);
    expect(find.textContaining('친구'), findsOneWidget);
    expect(find.text(AppStrings.battleJoin), findsOneWidget);
  });

  testWidgets('속도전 진행 화면에서 내가 제출 전이면 증거 제출 폼이 보인다', (WidgetTester tester) async {
    final battle = Battle(
      id: 'b1',
      type: 'speed',
      status: 'active',
      title: '아침 운동하기',
      creatorId: 'me',
      opponentId: 'friend',
      createdAt: DateTime(2026, 8, 20),
    );
    final detail = BattleDetail(
      battle: battle,
      me: const BattleParticipant(battleId: 'b1', userId: 'me'),
      opponent: const BattleParticipant(battleId: 'b1', userId: 'friend'),
      myName: '나',
      opponentName: '친구',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [battleDetailProvider('b1').overrideWith((ref) async => detail)],
        child: const MaterialApp(home: BattleDetailScreen(battleId: 'b1')),
      ),
    );
    await tester.pumpAndSettle();

    // 속도전도 자기 신고가 아니라 증거 제출로 완료를 주장한다.
    expect(find.text(AppStrings.battleEvidenceSubmit), findsOneWidget);
    expect(find.text(AppStrings.battleSpeedEvidenceNotice), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('품질전 제출 폼은 사진이 필수라 텍스트 입력란이 없다', (WidgetTester tester) async {
    final battle = Battle(
      id: 'bq',
      type: 'quality',
      status: 'active',
      title: '방 청소하기',
      creatorId: 'me',
      opponentId: 'friend',
      createdAt: DateTime(2026, 8, 20),
    );
    final detail = BattleDetail(
      battle: battle,
      me: const BattleParticipant(battleId: 'bq', userId: 'me'),
      opponent: const BattleParticipant(battleId: 'bq', userId: 'friend'),
      myName: '나',
      opponentName: '친구',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [battleDetailProvider('bq').overrideWith((ref) async => detail)],
        child: const MaterialApp(home: BattleDetailScreen(battleId: 'bq')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.battleEvidencePhotoRequired), findsOneWidget);
    expect(find.text(AppStrings.battleEvidencePhotoAdd), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('내 증거가 이의제기당하면 완료가 무효라고 알려준다', (WidgetTester tester) async {
    final battle = Battle(
      id: 'bd',
      type: 'speed',
      status: 'judging',
      title: '아침 운동하기',
      creatorId: 'me',
      opponentId: 'friend',
      createdAt: DateTime(2026, 8, 20),
    );
    final detail = BattleDetail(
      battle: battle,
      me: BattleParticipant(
        battleId: 'bd',
        userId: 'me',
        evidenceType: 'text',
        evidenceContent: '내 증거',
        evidenceSubmittedAt: DateTime(2026, 8, 20),
        decision: 'dispute',
      ),
      opponent: const BattleParticipant(battleId: 'bd', userId: 'friend'),
      myName: '나',
      opponentName: '친구',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [battleDetailProvider('bd').overrideWith((ref) async => detail)],
        child: const MaterialApp(home: BattleDetailScreen(battleId: 'bd')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.battleMyEvidenceDisputed), findsOneWidget);
    // 이의제기당해도 재제출로 복구할 수 있다.
    expect(find.text(AppStrings.battleEvidenceResubmit), findsOneWidget);
  });

  testWidgets('진행 화면에서 상대 증거가 있으면 승인/이의제기 버튼이 보인다', (WidgetTester tester) async {
    final battle = Battle(
      id: 'b2',
      type: 'speed',
      status: 'judging',
      title: '방 청소하기',
      creatorId: 'me',
      opponentId: 'friend',
      createdAt: DateTime(2026, 8, 20),
    );
    final detail = BattleDetail(
      battle: battle,
      me: BattleParticipant(
        battleId: 'b2',
        userId: 'me',
        evidenceType: 'text',
        evidenceContent: '내 증거',
        evidenceSubmittedAt: DateTime(2026, 8, 20),
      ),
      opponent: BattleParticipant(
        battleId: 'b2',
        userId: 'friend',
        evidenceType: 'text',
        evidenceContent: '상대 증거',
        evidenceSubmittedAt: DateTime(2026, 8, 20),
      ),
      myName: '나',
      opponentName: '친구',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [battleDetailProvider('b2').overrideWith((ref) async => detail)],
        child: const MaterialApp(home: BattleDetailScreen(battleId: 'b2')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('상대 증거'), findsOneWidget);
    expect(find.text(AppStrings.battleApprove), findsOneWidget);
    expect(find.text(AppStrings.battleDispute), findsOneWidget);
  });

  testWidgets('끝난 속도전은 상태 칩, 결과 배너, 제출 격차를 함께 보여준다', (WidgetTester tester) async {
    final battle = Battle(
      id: 'b3',
      type: 'speed',
      status: 'finished',
      title: '아침 운동하기',
      creatorId: 'me',
      opponentId: 'friend',
      createdAt: DateTime(2026, 8, 20),
      winnerId: 'me',
    );
    final detail = BattleDetail(
      battle: battle,
      me: BattleParticipant(
        battleId: 'b3',
        userId: 'me',
        evidenceType: 'text',
        evidenceContent: '내 증거',
        evidenceSubmittedAt: DateTime(2026, 8, 20, 7, 0),
        decision: 'approve',
      ),
      opponent: BattleParticipant(
        battleId: 'b3',
        userId: 'friend',
        evidenceType: 'text',
        evidenceContent: '상대 증거',
        evidenceSubmittedAt: DateTime(2026, 8, 20, 7, 30),
        decision: 'approve',
      ),
      myName: '나',
      opponentName: '친구',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [battleDetailProvider('b3').overrideWith((ref) async => detail)],
        child: const MaterialApp(home: BattleDetailScreen(battleId: 'b3')),
      ),
    );
    await tester.pumpAndSettle();

    // 제목은 앱바로 올라갔고, 상태는 문장이 아니라 칩으로 드러난다.
    expect(find.text('아침 운동하기'), findsOneWidget);
    expect(find.text(AppStrings.battleStatusFinished), findsOneWidget);
    expect(find.text(AppStrings.battleYouWon), findsOneWidget);
    expect(find.text(AppStrings.battleWonBySpeed), findsOneWidget);
    // 속도전 승부 기준인 제출 시각과 격차가 화면에 드러나야 한다.
    expect(find.text(AppStrings.battleSpeedLeadMine('30분')), findsOneWidget);
    expect(find.textContaining('${AppStrings.battleEvidenceSubmittedLabel} 8월 20일 07:00'),
        findsOneWidget);
  });

  testWidgets('프로필 화면에 이름과 대결 전적이 보인다', (WidgetTester tester) async {
    final speedWin = Battle(
      id: 'b1',
      type: 'speed',
      status: 'finished',
      title: '아침 운동하기',
      creatorId: 'me',
      opponentId: 'friend',
      winnerId: 'me',
      createdAt: DateTime(2026, 8, 18),
    );
    final qualityDisputed = Battle(
      id: 'b2',
      type: 'quality',
      status: 'disputed',
      title: '방 청소하기',
      creatorId: 'friend',
      opponentId: 'me',
      createdAt: DateTime(2026, 8, 19),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myProfileProvider.overrideWith((ref) async => const Profile(id: 'me', displayName: '나')),
          battleRecordsProvider.overrideWith(
            (ref) async => [
              BattleRecord(battle: speedWin, otherPartyName: '친구', resultLabel: AppStrings.battleRecordWin),
              BattleRecord(
                battle: qualityDisputed,
                otherPartyName: '친구',
                resultLabel: AppStrings.battleStatusDisputed,
              ),
            ],
          ),
        ],
        child: const MaterialApp(home: ProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('나'), findsOneWidget);
    expect(find.text('아침 운동하기'), findsOneWidget);
    expect(find.text('방 청소하기'), findsOneWidget);
    expect(find.text(AppStrings.battleRecordWin), findsOneWidget);
    expect(find.text(AppStrings.battleStatusDisputed), findsOneWidget);
    // 앱바 아이콘이 사라진 뒤 계정 관련 동작은 전부 이 화면에 모인다.
    expect(find.text(AppStrings.accountSection), findsOneWidget);
    expect(find.text(AppStrings.logout), findsOneWidget);
    expect(find.text(AppStrings.accountDelete), findsOneWidget);
  });

  testWidgets('전적 항목을 탭하면 지난 대결 상세로 들어간다', (WidgetTester tester) async {
    final battle = Battle(
      id: 'b1',
      type: 'speed',
      status: 'finished',
      title: '아침 운동하기',
      creatorId: 'me',
      opponentId: 'friend',
      winnerId: 'me',
      createdAt: DateTime(2026, 8, 18),
    );
    final detail = BattleDetail(
      battle: battle,
      me: BattleParticipant(
        battleId: 'b1',
        userId: 'me',
        evidenceType: 'text',
        evidenceContent: '내 증거',
        evidenceSubmittedAt: DateTime(2026, 8, 18, 7, 0),
        decision: 'approve',
      ),
      opponent: BattleParticipant(
        battleId: 'b1',
        userId: 'friend',
        evidenceType: 'text',
        evidenceContent: '상대 증거',
        evidenceSubmittedAt: DateTime(2026, 8, 18, 8, 0),
        decision: 'approve',
      ),
      myName: '나',
      opponentName: '친구',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myProfileProvider.overrideWith((ref) async => const Profile(id: 'me', displayName: '나')),
          battleRecordsProvider.overrideWith(
            (ref) async => [
              BattleRecord(
                battle: battle,
                otherPartyName: '친구',
                resultLabel: AppStrings.battleRecordWin,
              ),
            ],
          ),
          battleDetailProvider('b1').overrideWith((ref) async => detail),
        ],
        child: const MaterialApp(home: ProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('아침 운동하기'));
    await tester.pumpAndSettle();

    // 끝난 대결은 내 대결 목록에서 빠지므로 이 경로가 지난 증거를 보는 유일한 길이다.
    expect(find.text(AppStrings.battleYouWon), findsOneWidget);
    expect(find.text('상대 증거'), findsOneWidget);
  });

  testWidgets('계정 삭제는 확인 다이얼로그를 거쳐야 실행된다', (WidgetTester tester) async {
    final authRepository = _FakeAuthRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(authRepository),
          myProfileProvider.overrideWith((ref) async => const Profile(id: 'me', displayName: '나')),
          battleRecordsProvider.overrideWith((ref) async => <BattleRecord>[]),
        ],
        child: const MaterialApp(home: ProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // 취소하면 삭제되지 않는다.
    await tester.tap(find.text(AppStrings.accountDelete));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.accountDeleteConfirmTitle), findsOneWidget);
    await tester.tap(find.text(AppStrings.cancel));
    await tester.pumpAndSettle();
    expect(authRepository.deleteAccountCount, 0);

    // 확인해야 실제로 삭제된다.
    await tester.tap(find.text(AppStrings.accountDelete));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.accountDeleteConfirm));
    // 삭제 중에는 진행 표시가 계속 돌기 때문에 pumpAndSettle을 쓸 수 없다.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500)); // 스낵바 등장
    expect(authRepository.deleteAccountCount, 1);
    expect(find.text(AppStrings.accountDeleteDone), findsOneWidget);
    await tester.pump(const Duration(seconds: 5)); // 스낵바 타이머 소진
  });
}
