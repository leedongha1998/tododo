import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthState, User;

import 'package:todododo/core/strings.dart';
import 'package:todododo/core/theme/app_theme.dart';
import 'package:todododo/features/auth/data/auth_repository.dart';
import 'package:todododo/features/auth/domain/auth_providers.dart';
import 'package:todododo/features/auth/presentation/login_screen.dart';
import 'package:todododo/features/battle/data/battle.dart';
import 'package:todododo/features/battle/data/battle_participant.dart';
import 'package:todododo/features/battle/data/battle_submission.dart';
import 'package:todododo/features/battle/data/submission_result.dart';
import 'package:todododo/features/battle/data/battle_repository.dart';
import 'package:todododo/features/battle/data/criteria_check_result.dart';
import 'package:todododo/features/battle/data/profile.dart';
import 'package:todododo/features/battle/data/vs_intro_seen_store.dart';
import 'package:todododo/features/battle/domain/ai_consent_providers.dart';
import 'package:todododo/features/battle/domain/battle_detail.dart';
import 'package:todododo/features/battle/domain/battle_providers.dart';
import 'package:todododo/features/battle/data/open_recruit.dart';
import 'package:todododo/features/battle/data/player_card.dart';
import 'package:todododo/features/battle/domain/battle_summary.dart';
import 'package:todododo/features/battle/presentation/battle_chips.dart';
import 'package:todododo/features/battle/presentation/battle_detail_screen.dart';
import 'package:todododo/core/navigation/main_shell.dart';
import 'package:todododo/features/battle/presentation/battle_recruits_screen.dart';
import 'package:todododo/features/battle/presentation/my_battles_screen.dart';
import 'package:todododo/features/battle/presentation/vs_intro.dart';
import 'package:todododo/features/profile/data/player_stats.dart';
import 'package:todododo/features/battle/domain/battle_outcome.dart';
import 'package:todododo/features/profile/domain/battle_record.dart';
import 'package:todododo/features/profile/domain/profile_providers.dart';
import 'package:todododo/features/profile/presentation/profile_screen.dart';
import 'package:todododo/features/todo/data/todo.dart';
import 'package:todododo/features/todo/domain/todo_providers.dart';
import 'package:todododo/features/todo/presentation/todo_list_screen.dart';
import 'package:todododo/main.dart';

/// 프로필이 보여 주는 점수·전적은 서버 `player_stats` 값이다. 화면이 목록을 세지 않는지
/// 보려고 기록 목록과 일부러 다른 숫자를 쓴다.
const _testStats = PlayerStats(score: 3, wins: 1, losses: 1, draws: 0);

class _FakeBattleRepository implements BattleRepository {
  @override
  Future<String> createBattle({required String checkId, required int durationMinutes}) async =>
      'new-battle';

  @override
  Future<int> updateBattleCriteria({required String battleId, required String checkId}) async => 1;

  @override
  Future<MyLimits> fetchMyLimits() async => const MyLimits(
        consented: true,
        hasPending: false,
        dailyBattleUsed: false,
        criteriaCallsLeft: 10,
      );

  @override
  Future<List<OpenRecruit>> fetchOpenRecruits() async => const [];

  @override
  Future<PlayerCard> fetchPlayerCard(String userId) async => const PlayerCard(
        userId: 'friend',
        displayName: '친구',
        score: 3,
        wins: 1,
        losses: 0,
        draws: 0,
      );

  @override
  Future<List<Battle>> fetchMyRecruits() async => const [];

  @override
  Future<Map<String, String>> fetchDisplayNames(Iterable<String> ids) async => {};

  @override
  Future<void> joinBattle(String battleId, int criteriaVersion) async {}

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
  Future<List<BattleParticipant>> fetchParticipantsOf(Iterable<String> battleIds) async =>
      const [];

  @override
  Future<String> createEvidencePhotoUrl(String path) async => 'https://example.com/$path';

  @override
  Future<List<BattleSubmission>> fetchSubmissions(String battleId) async => const [];

  @override
  Future<String> uploadEvidencePhoto({
    required String battleId,
    required Uint8List bytes,
  }) async =>
      '$battleId/me/photo.jpg';

  @override
  Future<SubmissionResult> submitEvidence({
    required String battleId,
    required String objectPath,
    required DateTime capturedAt,
  }) async =>
      const SubmissionResult(submissionId: 1);
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

/// 모든 대결의 VS 인트로를 이미 봤다고 답하는 저장소.
class _SeenAllStore extends VsIntroSeenStore {
  const _SeenAllStore();

  @override
  Future<bool> hasSeen(String userId, String battleId) async => true;

  @override
  Future<void> markSeen(String userId, String battleId) async {}
}

/// 기기 저장소 대신 메모리에 "봤음"을 기록한다.
class _MemorySeenStore extends VsIntroSeenStore {
  _MemorySeenStore();

  final seen = <String>{};

  @override
  Future<bool> hasSeen(String userId, String battleId) async =>
      seen.contains(VsIntroSeenStore.keyFor(userId, battleId));

  @override
  Future<void> markSeen(String userId, String battleId) async {
    seen.add(VsIntroSeenStore.keyFor(userId, battleId));
  }
}

BattleDetail _detail({
  required String id,
  required String type,
  required String status,
  String? winnerId,
  String? forfeitedBy,
}) {
  return BattleDetail(
    battle: Battle(
      id: id,
      type: type,
      status: status,
      title: '아침 운동하기',
      creatorId: 'me',
      opponentId: 'friend',
      winnerId: winnerId,
      forfeitedBy: forfeitedBy,
      createdAt: DateTime(2026, 9, 15),
    ),
    me: BattleParticipant(battleId: id, userId: 'me'),
    opponent: BattleParticipant(battleId: id, userId: 'friend'),
    myName: '나',
    opponentName: '친구',
  );
}

Widget _detailScreen(BattleDetail detail) {
  return ProviderScope(
    overrides: [
      battleDetailProvider(detail.battle.id).overrideWith((ref) async => detail),
      battleRepositoryProvider.overrideWithValue(_FakeBattleRepository()),
      // 인트로가 상세 화면 검증에 끼어들지 않게 이미 봤다고 둔다.
      vsIntroSeenStoreProvider.overrideWithValue(const _SeenAllStore()),
    ],
    child: MaterialApp(home: BattleDetailScreen(battleId: detail.battle.id)),
  );
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
          // 프로필 동의 섹션이 서버를 보지 않게 "동의 안 함"으로 고정한다(동의 흐름은 ai_consent_test.dart).
          myAiConsentProvider.overrideWith((ref) async => null),
          myProfileProvider.overrideWith((ref) async => const Profile(id: 'me', displayName: '나')),
          myPlayerStatsProvider.overrideWith((ref) async => _testStats),
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

  // 대결 만들기 화면은 AI 기준 생성·승인 2단계로 바뀌어 create_battle_test.dart에서 따로 본다.

  testWidgets('모집 카드에 제목·기간·기준 미리보기가 보이고 생성자와 전적은 보이지 않는다',
      (WidgetTester tester) async {
    final battle = Battle(
      id: 'b1',
      type: 'speed',
      status: 'pending',
      title: '아침 운동하기',
      creatorId: 'creator1',
      createdAt: DateTime(2026, 8, 20),
      durationMinutes: 1440,
      minCriteria: const ['운동화를 신고 밖에 있다'],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          openRecruitsProvider.overrideWith(
            (ref) async => [
              OpenRecruit(
                battle: battle,
                creator: const PlayerCard(
                  userId: 'creator1',
                  displayName: '친구',
                  score: 6,
                  wins: 2,
                  losses: 1,
                  draws: 0,
                ),
              ),
            ],
          ),
          myRecruitsProvider.overrideWith((ref) async => const []),
        ],
        child: const MaterialApp(home: BattleRecruitsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('아침 운동하기'), findsOneWidget);
    expect(find.text(battleDurationLabel(1440)), findsOneWidget);
    expect(find.text('운동화를 신고 밖에 있다'), findsOneWidget);
    // 목록에서 읽어야 하는 것은 무슨 대결인지다. 생성자가 누구이고 전적이 어떤지는
    // 참가를 결정할 때 보면 되므로 상세 시트에서만 보여 준다.
    expect(find.text('친구'), findsNothing);
    expect(find.text(AppStrings.playerScoreLabel(6)), findsNothing);
    expect(find.text(AppStrings.playerRecordLabel(2, 1, 0)), findsNothing);
    // 참가는 카드를 눌러 연 시트에서 한다(기준을 보고 참가하도록).
    expect(find.text(AppStrings.battleRecruitJoinWithCriteria), findsNothing);
  });

  // spec 수용 기준: "어떤 화면에도 상대 증거를 승인/이의제기하는 수단이 없다",
  // "증거 제출 경로에서 갤러리 사진을 고를 방법이 없다", "텍스트만으로는 제출할 수 없다".
  testWidgets('진행 중인 대결 상세에는 카메라 제출과 포기만 있고 승인·이의제기·텍스트 입력·사진 선택이 없다',
      (WidgetTester tester) async {
    for (final type in ['speed', 'quality']) {
      for (final status in ['active', 'judging']) {
        await tester.pumpWidget(_detailScreen(_detail(id: '$type-$status', type: type, status: status)));
        await tester.pumpAndSettle();

        final reason = '$type/$status';
        // 두 유형 모두 active에서만 낼 수 있다. judging은 품질전에서 두 사진이 다 올라와
        // AI가 판정하는 중인 상태라 제출 자리가 없다.
        expect(
          find.text(AppStrings.battleEvidenceTakePhoto),
          status == 'active' ? findsOneWidget : findsNothing,
          reason: reason,
        );
        if (type == 'quality' && status == 'judging') {
          expect(find.text(AppStrings.battleEvidenceQualityJudging), findsOneWidget, reason: reason);
        }
        expect(find.text(AppStrings.battleForfeit), findsOneWidget, reason: reason);
        expect(find.byType(TextField), findsNothing, reason: reason);
        expect(find.text('승인'), findsNothing, reason: reason);
        expect(find.text('이의제기'), findsNothing, reason: reason);
        expect(find.textContaining('갤러리'), findsNothing, reason: reason);
        // 진행 중에는 결과 배너가 없다.
        expect(find.text(AppStrings.battleYouWon), findsNothing, reason: reason);

        await tester.pumpWidget(const SizedBox());
      }
    }
  });

  testWidgets('끝난 품질전도 승패가 있어 승리 배너와 종료 칩을 보여준다', (WidgetTester tester) async {
    await tester.pumpWidget(
      _detailScreen(_detail(id: 'bq', type: 'quality', status: 'finished', winnerId: 'me')),
    );
    await tester.pumpAndSettle();

    // 제목은 앱바로 올라갔고, 상태는 문장이 아니라 칩으로 드러난다.
    expect(find.text('아침 운동하기'), findsOneWidget);
    expect(find.text(AppStrings.battleStatusFinished), findsOneWidget);
    expect(find.text(AppStrings.battleYouWon), findsOneWidget);
    // 끝난 대결에는 제출 자리도 포기 버튼도 없다.
    expect(find.text(AppStrings.battleEvidenceTakePhoto), findsNothing);
    expect(find.text(AppStrings.battleForfeit), findsNothing);
  });

  testWidgets('상대가 포기해 끝난 대결은 승리 배너에 기권 사유를 보여준다', (WidgetTester tester) async {
    await tester.pumpWidget(
      _detailScreen(
        _detail(id: 'bf', type: 'speed', status: 'finished', winnerId: 'me', forfeitedBy: 'friend'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.battleYouWon), findsOneWidget);
    expect(find.text(AppStrings.battleWonByForfeit), findsOneWidget);
  });

  testWidgets('무효로 끝난 대결은 무효 칩과 무효 배너를 보여준다', (WidgetTester tester) async {
    await tester.pumpWidget(_detailScreen(_detail(id: 'bv', type: 'quality', status: 'voided')));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.battleStatusVoided), findsOneWidget);
    expect(find.text(AppStrings.battleVoidedMessage), findsOneWidget);
    expect(find.text(AppStrings.battleYouWon), findsNothing);
    expect(find.text(AppStrings.battleYouLost), findsNothing);
    expect(find.text(AppStrings.battleDrawMessage), findsNothing);
  });

  testWidgets('포기 확인 문구는 속도전·품질전이 같고, 취소하면 포기하지 않는다', (WidgetTester tester) async {
    for (final type in ['speed', 'quality']) {
      await tester.pumpWidget(_detailScreen(_detail(id: 'ff-$type', type: type, status: 'active')));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text(AppStrings.battleForfeit));
      await tester.tap(find.text(AppStrings.battleForfeit));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.battleForfeitConfirmTitle), findsOneWidget, reason: type);
      expect(find.text(AppStrings.battleForfeitConfirm), findsOneWidget, reason: type);

      await tester.tap(find.text(AppStrings.cancel));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.battleForfeitConfirmTitle), findsNothing, reason: type);

      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('프로필 화면에 이름과 점수·승/패/무 전적이 보인다', (WidgetTester tester) async {
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
    final qualityLoss = Battle(
      id: 'b2',
      type: 'quality',
      status: 'finished',
      title: '방 청소하기',
      creatorId: 'friend',
      opponentId: 'me',
      winnerId: 'friend',
      createdAt: DateTime(2026, 8, 19),
    );
    final qualityVoided = Battle(
      id: 'b3',
      type: 'quality',
      status: 'voided',
      title: '책상 정리하기',
      creatorId: 'friend',
      opponentId: 'me',
      createdAt: DateTime(2026, 8, 20),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // 프로필 동의 섹션이 서버를 보지 않게 "동의 안 함"으로 고정한다(동의 흐름은 ai_consent_test.dart).
          myAiConsentProvider.overrideWith((ref) async => null),
          myProfileProvider.overrideWith((ref) async => const Profile(id: 'me', displayName: '나')),
          myPlayerStatsProvider.overrideWith((ref) async => _testStats),
          battleRecordsProvider.overrideWith(
            (ref) async => [
              BattleRecord(
                battle: speedWin,
                otherPartyName: '친구',
                result: BattleResult.win,
              ),
              BattleRecord(
                battle: qualityLoss,
                otherPartyName: '친구',
                result: BattleResult.loss,
              ),
              BattleRecord(
                battle: qualityVoided,
                otherPartyName: '친구',
                result: BattleResult.voided,
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
    expect(find.text('책상 정리하기'), findsOneWidget);
    expect(find.text(AppStrings.battleRecordWin), findsOneWidget);
    expect(find.text(AppStrings.battleRecordLose), findsOneWidget);
    expect(find.text(AppStrings.battleRecordVoided), findsOneWidget);
    // 점수와 승/패/무는 서버 player_stats 값을 그대로 보여 준다(화면이 목록을 세지 않는다).
    expect(find.text(AppStrings.playerScoreLabel(3)), findsOneWidget);
    expect(find.text(AppStrings.playerRecordLabel(1, 1, 0)), findsOneWidget);
    // 무효는 점수·전적에 들어가지 않으므로 목록과 숫자가 어긋나는 이유를 알린다.
    expect(find.text(AppStrings.profileVoidedExcluded), findsOneWidget);
    // 앱바 아이콘이 사라진 뒤 계정 관련 동작은 전부 이 화면에 모인다.
    // 기록이 세 장이라 계정 창이 첫 화면 아래로 밀린다. 목록은 보이는 곳만 그리므로 내려서 확인한다.
    await tester.scrollUntilVisible(find.text(AppStrings.accountDelete), 200);
    expect(find.text(AppStrings.accountSection), findsOneWidget);
    expect(find.text(AppStrings.logout), findsOneWidget);
    expect(find.text(AppStrings.accountDelete), findsOneWidget);
  });

  testWidgets('전적 항목을 탭하면 지난 대결 상세로 들어간다', (WidgetTester tester) async {
    final detail = _detail(id: 'b1', type: 'speed', status: 'finished', winnerId: 'me');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // 프로필 동의 섹션이 서버를 보지 않게 "동의 안 함"으로 고정한다(동의 흐름은 ai_consent_test.dart).
          myAiConsentProvider.overrideWith((ref) async => null),
          myProfileProvider.overrideWith((ref) async => const Profile(id: 'me', displayName: '나')),
          myPlayerStatsProvider.overrideWith((ref) async => _testStats),
          battleRecordsProvider.overrideWith(
            (ref) async => [
              BattleRecord(
                battle: detail.battle,
                otherPartyName: '친구',
                result: BattleResult.win,
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

    // 끝난 대결은 내 대결 목록에서 빠지므로 이 경로가 지난 결과를 보는 유일한 길이다.
    expect(find.text(AppStrings.battleYouWon), findsOneWidget);
  });

  testWidgets('계정 삭제는 확인 다이얼로그를 거쳐야 실행된다', (WidgetTester tester) async {
    final authRepository = _FakeAuthRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(authRepository),
          // 프로필 동의 섹션이 서버를 보지 않게 "동의 안 함"으로 고정한다(동의 흐름은 ai_consent_test.dart).
          myAiConsentProvider.overrideWith((ref) async => null),
          myProfileProvider.overrideWith((ref) async => const Profile(id: 'me', displayName: '나')),
          myPlayerStatsProvider.overrideWith((ref) async => _testStats),
          battleRecordsProvider.overrideWith((ref) async => <BattleRecord>[]),
        ],
        child: const MaterialApp(home: ProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // 동의 섹션에 점수 창까지 생겨 계정 창이 첫 화면 아래로 밀린다. 목록은 보이는 곳만 그리므로
    // 내려서 찾고, 화면 가장자리에 걸친 채로 누르면 "off-screen"으로 실패하므로 ensureVisible까지 한다.
    Future<void> tapDeleteAccount() async {
      final button = find.text(AppStrings.accountDelete);
      await tester.scrollUntilVisible(button, 200);
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
    }

    // 취소하면 삭제되지 않는다.
    await tapDeleteAccount();
    expect(find.text(AppStrings.accountDeleteConfirmTitle), findsOneWidget);
    await tester.tap(find.text(AppStrings.cancel));
    await tester.pumpAndSettle();
    expect(authRepository.deleteAccountCount, 0);

    // 확인해야 실제로 삭제된다.
    await tapDeleteAccount();
    await tester.tap(find.text(AppStrings.accountDeleteConfirm));
    // 삭제 중에는 진행 표시가 계속 돌기 때문에 pumpAndSettle을 쓸 수 없다.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500)); // 스낵바 등장
    expect(authRepository.deleteAccountCount, 1);
    expect(find.text(AppStrings.accountDeleteDone), findsOneWidget);
    await tester.pump(const Duration(seconds: 5)); // 스낵바 타이머 소진
  });
  testWidgets('매칭된 대결에 처음 들어가면 VS 인트로가 뜨고, 다시 들어가면 뜨지 않는다', (WidgetTester tester) async {
    final store = _MemorySeenStore();
    final detail = _detail(id: 'bv', type: 'speed', status: 'active');
    Widget screen() => ProviderScope(
          overrides: [
            battleDetailProvider('bv').overrideWith((ref) async => detail),
            vsIntroSeenStoreProvider.overrideWithValue(store),
          ],
          child: MaterialApp(theme: AppTheme.light, home: const BattleDetailScreen(battleId: 'bv')),
        );

    await tester.pumpWidget(screen());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));

    expect(find.byType(VsIntro), findsOneWidget);
    // 인트로 route가 뜬 다음 프레임부터 연출 시간이 흐른다.
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.text(AppStrings.vsIntroVersus), findsOneWidget);
    expect(store.seen, contains(VsIntroSeenStore.keyFor('me', 'bv')));

    // 누르면 즉시 닫히고 이미 그려진 상세 화면이 보인다.
    await tester.tap(find.byType(VsIntro));
    await tester.pump();
    expect(find.byType(VsIntro), findsNothing);
    // 인트로가 닫히면 진행 중인 속도전의 제출 자리가 보인다.
    expect(find.text(AppStrings.battleEvidenceTakePhoto), findsOneWidget);

    // 같은 대결에 다시 들어가면 뜨지 않는다.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(screen());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.byType(VsIntro), findsNothing);
  });

  testWidgets('애니메이션 줄이기면 VS 인트로 첫 프레임부터 이름·이니셜·VS가 보이고 누르면 닫힌다',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showVsIntro(context, myName: '홍길동', opponentName: '탈퇴한 사용자'),
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pump();

    expect(find.text(AppStrings.vsIntroVersus), findsOneWidget);
    expect(find.text('홍길동'), findsOneWidget);
    expect(find.text('탈퇴한 사용자'), findsOneWidget);
    expect(find.text('홍'), findsOneWidget);
    expect(find.text('탈'), findsOneWidget);

    await tester.tap(find.byType(VsIntro));
    await tester.pump();
    expect(find.byType(VsIntro), findsNothing);
  });

  testWidgets('이름이 60자이고 글자 크기가 상한(1.3)이어도 VS 인트로가 넘치지 않고 1.5초 뒤 스스로 닫힌다',
      (WidgetTester tester) async {
    final longName = '가' * 60;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.3)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showVsIntro(context, myName: longName, opponentName: '가'),
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    expect(tester.takeException(), isNull);
    expect(find.text(longName), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump();
    expect(find.byType(VsIntro), findsNothing);
  });
}
