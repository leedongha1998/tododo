import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:todododo/core/strings.dart';
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
import 'package:todododo/features/battle/presentation/battle_recruits_screen.dart';
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

  testWidgets('홈 화면 상단에 대결 영역, 하단에 할 일 영역이 함께 보인다', (WidgetTester tester) async {
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

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          todosProvider.overrideWith((ref) async => todos),
          myBattlesProvider.overrideWith(
            (ref) async => [BattleSummary(battle: battle, otherPartyName: '친구')],
          ),
        ],
        child: const MaterialApp(home: TodoListScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.battleMyBattles), findsOneWidget);
    expect(find.text('아침 운동하기'), findsOneWidget);
    expect(find.text('설거지하기'), findsOneWidget);
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
  });
}
