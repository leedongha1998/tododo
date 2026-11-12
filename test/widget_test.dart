import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthState, User;

import 'package:todododo/core/strings.dart';
import 'package:todododo/core/theme/app_icons.dart';
import 'package:todododo/core/theme/app_palette.dart';
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
import 'package:todododo/features/battle/data/open_recruit_page.dart';
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
import 'package:todododo/features/todo/data/todo_widget_payload.dart';
import 'package:todododo/features/todo/domain/todo_providers.dart';
import 'package:todododo/features/todo/presentation/todo_list_screen.dart';
import 'package:todododo/main.dart';
import 'package:todododo/core/widgets/app_button_styles.dart';
import 'package:todododo/core/widgets/keep_words_text.dart';

import 'core/push/push_fakes.dart';
import 'helpers/line_breaks.dart';
import 'features/todo/due_alarm_fakes.dart';
import 'features/todo/todo_widget_fakes.dart';
import 'helpers/text_finders.dart';

/// 프로필이 보여 주는 점수·전적은 서버 `player_stats` 값이다. 화면이 목록을 세지 않는지
/// 보려고 기록 목록과 일부러 다른 숫자를 쓴다.
const _testStats = PlayerStats(score: 3, wins: 1, losses: 1, draws: 0);

class _FakeBattleRepository implements BattleRepository {
  _FakeBattleRepository({this.recruits = const []});

  /// 서버가 내주는 모집 묶음. 피드 provider가 이 값을 그대로 받아 그린다
  /// (목록을 provider override로 끼워 넣지 않고 repository 한 곳에서만 가짜로 만든다).
  final List<OpenRecruit> recruits;

  @override
  Future<String> createBattle({required String checkId, required int durationMinutes}) async =>
      'new-battle';

  @override
  Future<int> updateBattleCriteria({required String battleId, required String checkId}) async => 1;

  @override
  Future<MyLimits> fetchMyLimits() async => const MyLimits(
        consented: true,
        criteriaCallsLeft: 10,
      );

  @override
  Future<OpenRecruitPage> fetchOpenRecruits({
    int limit = openRecruitPageSize,
    RecruitCursor? cursor,
    String? query,
    String? type,
    String? durationBand,
  }) async => OpenRecruitPage(items: recruits, nextCursor: null, hasMore: false);

  @override
  Future<Battle?> fetchOpenRecruitBattle(String battleId) async => null;

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
  Future<String> submitJudgment({
    required String battleId,
    required bool passed,
    String? superiorId,
  }) async =>
      'judging';

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

    expect(findTextContaining('Supabase 설정이 필요합니다'), findsOneWidget);
  });

  testWidgets('로그인 화면에 구글 로그인 버튼이 보인다', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: LoginScreen()),
      ),
    );

    expect(findText(AppStrings.googleSignIn), findsOneWidget);
  });

  testWidgets('로그인 화면에는 반복 움직임이 없다(깜빡이는 커서 없음 — 화면이 멈춘다)', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(theme: AppTheme.light, home: const LoginScreen()),
      ),
    );
    // 반복 애니메이션이 있으면 pumpAndSettle이 시간 초과로 실패한다.
    await tester.pumpAndSettle();
    expect(findText(AppStrings.appName), findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse);
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

    expect(findTextContaining('아직 할 일이 없어요'), findsOneWidget);
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

    expect(findText('설거지하기'), findsOneWidget);
    expect(findText('빨래하기'), findsOneWidget);

    final doneText = tester.widget<KeepWordsText>(findText('빨래하기'));
    expect(doneText.style?.decoration, TextDecoration.lineThrough);
  });

  // todo-due-date 원칙 5의 회귀 방지: 기한을 쓰지 않는 사용자의 줄에는 글자가 한 자도 늘지 않고,
  // 완료한 할 일에는 기한이 있어도 빨간 "지남"이 붙지 않는다(spec).
  testWidgets('기한이 있는 미완료 할 일만 남은 시간을 보여 준다', (WidgetTester tester) async {
    final now = DateTime.now();
    final todos = [
      Todo(
        id: '1',
        title: '보고서 쓰기',
        isDone: false,
        createdAt: DateTime(2026, 11, 8),
        // 30초를 더해 두는 이유: 화면이 그려지는 순간의 DateTime.now()는 이 now보다 조금
        // 뒤이고, 각 단위는 내림이라 그 차이가 분을 깎을 수 있다(`1시간 41분`이 된다).
        dueAt: now.add(const Duration(hours: 1, minutes: 42, seconds: 30)).toUtc(),
      ),
      Todo(
        id: '2',
        title: '빨래하기',
        isDone: true,
        createdAt: DateTime(2026, 11, 8),
        dueAt: now.subtract(const Duration(days: 3)).toUtc(),
      ),
      Todo(
        id: '3',
        title: '설거지하기',
        isDone: false,
        createdAt: DateTime(2026, 11, 8),
      ),
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

    // 기한이 남은 줄: 두 단위 병기 + 보조 색.
    final remaining = tester.widget<KeepWordsText>(findText('1시간 42분 남음'));
    expect(remaining.style?.color, AppPalette.inkMuted);

    // 완료한 할 일은 기한을 넘겼어도 아무 문구가 없다(빨간 경고가 붙지 않는다).
    expect(findText('3일 지남'), findsNothing);
    expect(findTextContaining('지남'), findsNothing);

    // 기한이 없는 줄에는 둘째 줄 자체가 없다 — 그 줄의 글자는 제목 하나뿐이다
    // (줄이 ListTile이 아니라 네 칸 Row가 되어(todo-reorder design 4.2) subtitle이라는
    //  자리가 없어졌으므로, "글자 줄이 하나다"로 같은 것을 본다).
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('3')),
        matching: find.byType(KeepWordsText),
      ),
      findsOneWidget,
    );
  });

  testWidgets('기한을 넘긴 미완료 할 일은 경고색으로 지난 시간을 말한다', (WidgetTester tester) async {
    final todos = [
      Todo(
        id: '1',
        title: '보고서 쓰기',
        isDone: false,
        createdAt: DateTime(2026, 11, 8),
        dueAt: DateTime.now().subtract(const Duration(hours: 12, minutes: 34)).toUtc(),
      ),
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

    final overdue = tester.widget<KeepWordsText>(findText('12시간 34분 지남'));
    expect(overdue.style?.color, AppPalette.danger);
  });

  // 앱 전체 어절 줄바꿈(redesign 후속 결정 1). 사용자가 쓴 긴 할 일도 "우/유", "버리/기"처럼 끊기지 않는다.
  for (final scale in [1.0, 1.5]) {
    testWidgets('긴 할 일 내용은 360dp·배율 $scale에서 어절 경계에서만 줄을 바꾼다', (WidgetTester tester) async {
      const title = '퇴근길에 장 보기 — 우유, 달걀, 두부, 대파, 사과 한 봉지와 내일 아침에 먹을 식빵까지 잊지 말기';
      tester.view.physicalSize = const Size(720, 1600);
      tester.view.devicePixelRatio = 2;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            todosProvider.overrideWith(
              (ref) async => [Todo(id: '1', title: title, isDone: false, createdAt: DateTime(2026, 11, 8))],
            ),
            myBattlesProvider.overrideWith((ref) async => const []),
          ],
          child: MaterialApp(theme: AppTheme.light, home: const TodoListScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // 원문으로 찾는다(그리는 글자에만 WORD JOINER가 들어간다).
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(of: findText(title), matching: find.byType(RichText)),
      );
      expect(lineStarts(paragraph), isNotEmpty);
      expect(breaksOnlyAtSpaces(paragraph), isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  // redesign 후속 2 W3: 1.5배에서 체크박스·삭제 버튼 주변 여백 때문에 할 일 글자 칸이 152dp뿐이라 한 줄에 몇 글자 안 들어갔다.
  // 버튼 터치 영역(48)은 지키고 여백만 줄여 칸을 넓힌다.
  testWidgets('할 일 행은 360dp·1.5배에서 글자 칸이 넓고(줄 수 감소), 체크박스·삭제 버튼 터치 영역은 48dp 이상이다', (
    WidgetTester tester,
  ) async {
    const title = '퇴근길에 장 보기 — 우유, 달걀, 두부, 대파, 사과 한 봉지와 내일 아침에 먹을 식빵까지 잊지 말기';
    tester.view.physicalSize = const Size(720, 1600);
    tester.view.devicePixelRatio = 2;
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          todosProvider.overrideWith(
            (ref) async => [Todo(id: '1', title: title, isDone: false, createdAt: DateTime(2026, 11, 8))],
          ),
          myBattlesProvider.overrideWith((ref) async => const []),
        ],
        child: MaterialApp(theme: AppTheme.light, home: const TodoListScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final titleRect = tester.getRect(findText(title));
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: findText(title), matching: find.byType(RichText)),
    );
    // **칸으로 잰다.** find.byType(Checkbox)의 사각형은 Transform.scale 때문에 "그려지는
    // 상자"(약 64dp)라 칸보다 넓다 — 히트 영역을 정하는 것은 칸이다(todo-reorder design 4.2,
    // 참고 5번).
    final checkCell = tester.getRect(find.byKey(todoCheckCellKey));
    final delete = tester.getRect(find.byTooltip(AppStrings.delete));
    expect(checkCell.width, greaterThanOrEqualTo(48));
    expect(checkCell.height, greaterThanOrEqualTo(48));
    expect(delete.width, greaterThanOrEqualTo(48));
    expect(delete.height, greaterThanOrEqualTo(48));
    // 글자 칸은 칸들과 겹치지 않는다 — **글자 앞을 눌러도 체크되지 않는다**가 여기서 보장된다.
    expect(titleRect.left, greaterThanOrEqualTo(checkCell.right));
    expect(titleRect.right, lessThanOrEqualTo(delete.left));
    // 여백을 줄이기 전(W2 시점)에는 글자 칸 150dp, 이 글이 11줄이었다(테스트 글꼴 — 글자마다 정사각형).
    // **실측 222dp**다(카드 폭 320 = 360 − 20 − 20, 거기서 칸 48*2와 AppPanel 테두리 1*2를 뺀 값).
    // 2026-11-10에 전용 손잡이(48dp 칸)가 없어지고 그 자리를 만들려고 8dp까지 줄였던 좌우 여백이
    // 20dp로 돌아오면서 198 → 222dp가 됐다. spec의 요구는 "198dp를 깎지 않는다"이고 지금은 24dp
    // 여유가 있지만, **하한은 실측에 붙여** 1dp라도 깎이면 울게 한다.
    expect(titleRect.width, greaterThanOrEqualTo(222));
    expect(lineStarts(paragraph).length + 1, lessThanOrEqualTo(8));
    expect(tester.takeException(), isNull);
  });

  // redesign 후속 결정 4: 1.5배에서 FAB가 마지막 할 일의 삭제 버튼을 가렸다. 끝까지 내리면 완전히 드러나야 한다.
  testWidgets('할 일 목록을 끝까지 내리면 마지막 줄(삭제 버튼 포함)이 FAB에 가리지 않는다(360dp·1.5배)', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(720, 1600);
    tester.view.devicePixelRatio = 2;
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final todos = [
      for (var i = 0; i < 8; i++)
        Todo(id: '$i', title: '할 일 $i번 — 우유와 달걀 사 오기', isDone: i > 5, createdAt: DateTime(2026, 11, 8)),
    ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          todosProvider.overrideWith((ref) async => todos),
          myBattlesProvider.overrideWith((ref) async => const []),
        ],
        child: MaterialApp(theme: AppTheme.light, home: const TodoListScreen()),
      ),
    );
    await tester.pumpAndSettle();
    // 꾹 누르지 않고 바로 미는 세로 이동이므로 재배치가 아니라 스크롤이다 — 끌기는 500ms를
    // 넘겨 쥐어야 시작한다(2026-11-10 오너 확정. 그 전에는 "손잡이 밖에서 시작했으니"가 이유였다).
    await tester.drag(
      find.byType(ReorderableListView),
      const Offset(0, -5000),
    );
    await tester.pumpAndSettle();

    final fab = tester.getRect(find.byType(FloatingActionButton));
    final lastDelete = tester.getRect(find.byTooltip(AppStrings.delete).last);
    final lastTitle = tester.getRect(findText(todos.last.title));
    expect(lastDelete.overlaps(fab), isFalse);
    expect(lastTitle.bottom, lessThanOrEqualTo(fab.top));
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

    expect(findText('아침 운동하기'), findsOneWidget);
    expect(findText('설거지하기'), findsNothing);

    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: const MaterialApp(home: TodoListScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // 두 목록이 한 화면을 나눠 쓰던 구조를 없앴다. 할 일 화면에 대결이 섞이면 안 된다.
    expect(findText('설거지하기'), findsOneWidget);
    expect(findText('아침 운동하기'), findsNothing);
  });

  testWidgets('로그인하면 탭 네 개짜리 탭바가 있는 화면으로 들어간다', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          todosProvider.overrideWith((ref) async => []),
          myBattlesProvider.overrideWith((ref) async => []),
          myRecruitsProvider.overrideWith((ref) async => []),
          // 찾기 탭의 모집 피드와 한도는 repository를 통해 읽는다(목록 provider override는 없다).
          battleRepositoryProvider.overrideWithValue(_FakeBattleRepository()),
          // 프로필 동의 섹션이 서버를 보지 않게 "동의 안 함"으로 고정한다(동의 흐름은 ai_consent_test.dart).
          myAiConsentProvider.overrideWith((ref) async => null),
          myProfileProvider.overrideWith((ref) async => const Profile(id: 'me', displayName: '나')),
          myPlayerStatsProvider.overrideWith((ref) async => _testStats),
          battleRecordsProvider.overrideWith((ref) async => []),
        ...pushOverrides(),
        // 본 화면이 뜨면 홈 화면 위젯 캐시를 발행한다. 가짜로 바꾸지 않으면 플러그인이 없어
        // 조용히 실패하고(서비스가 로그로 삼킨다) 출력만 더러워진다.
        ...todoWidgetOverrides(),
        ...dueAlarmOverrides(),
        ],
        child: const MaterialApp(home: MainShell()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationDestination), findsNWidgets(4));
    expect(findText(AppStrings.battleFind), findsWidgets);
    expect(findText(AppStrings.todoTitle), findsWidgets);
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
    expect(findText(AppStrings.addTodo), findsOneWidget);
    expect(findText(AppStrings.battleCreate), findsNothing);
  });

  testWidgets('대결 찾기 화면의 만들기 버튼은 아이콘 전용이고 이름은 tooltip이 말한다',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          battleRepositoryProvider.overrideWithValue(_FakeBattleRepository()),
        ],
        child: const MaterialApp(home: BattleRecruitsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // 글자 라벨까지 둔 버튼이 카드 오른쪽 절반을 덮어 아이콘 전용(56x56)으로 바꿨다.
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(findWidgetWithText(FloatingActionButton, AppStrings.battleCreate), findsNothing);
    expect(
      find.byTooltip(AppStrings.battleCreate),
      findsOneWidget,
      reason: '라벨을 떼는 대신 tooltip으로 이름을 남긴다(스크린리더·롱프레스)',
    );
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
          battleRepositoryProvider.overrideWithValue(
            _FakeBattleRepository(
              recruits: [
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
          ),
        ],
        child: const MaterialApp(home: BattleRecruitsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(findText('아침 운동하기'), findsOneWidget);
    expect(findText(battleDurationLabel(1440)), findsOneWidget);
    expect(findText('운동화를 신고 밖에 있다'), findsOneWidget);
    // 목록에서 읽어야 하는 것은 무슨 대결인지다. 생성자가 누구이고 전적이 어떤지는
    // 참가를 결정할 때 보면 되므로 상세 시트에서만 보여 준다.
    expect(findText('친구'), findsNothing);
    expect(findText(AppStrings.playerScoreLabel(6)), findsNothing);
    expect(findText(AppStrings.playerRecordLabel(2, 1, 0)), findsNothing);
    // 참가는 카드를 눌러 연 시트에서 한다(기준을 보고 참가하도록).
    expect(findText(AppStrings.battleRecruitJoinWithCriteria), findsNothing);
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
        // 두 유형 모두 active에서만 낼 수 있다. judging은 상호 판정 창(두 유형 공통)이라
        // 제출 자리가 없고 안내만 보인다.
        expect(
          findText(AppStrings.battleEvidenceTakePhoto),
          status == 'active' ? findsOneWidget : findsNothing,
          reason: reason,
        );
        if (status == 'judging') {
          // 양쪽 다 제출 전인 채로 열린 창이라 판정할 증거가 없다. 판정 입력도 나오지 않는다.
          expect(findText(AppStrings.battleJudgmentNothing), findsOneWidget, reason: reason);
          expect(findText(AppStrings.battleJudgmentSend), findsNothing, reason: reason);
        }
        expect(findText(AppStrings.battleForfeit), findsOneWidget, reason: reason);
        expect(find.byType(TextField), findsNothing, reason: reason);
        expect(findText('승인'), findsNothing, reason: reason);
        expect(findText('이의제기'), findsNothing, reason: reason);
        expect(findTextContaining('갤러리'), findsNothing, reason: reason);
        // 진행 중에는 결과 배너가 없다.
        expect(findText(AppStrings.battleYouWon), findsNothing, reason: reason);

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
    expect(findText('아침 운동하기'), findsOneWidget);
    expect(findText(AppStrings.battleStatusFinished), findsOneWidget);
    expect(findText(AppStrings.battleYouWon), findsOneWidget);
    // 끝난 대결에는 제출 자리도 포기 버튼도 없다.
    expect(findText(AppStrings.battleEvidenceTakePhoto), findsNothing);
    expect(findText(AppStrings.battleForfeit), findsNothing);
  });

  testWidgets('상대가 포기해 끝난 대결은 승리 배너에 기권 사유를 보여준다', (WidgetTester tester) async {
    await tester.pumpWidget(
      _detailScreen(
        _detail(id: 'bf', type: 'speed', status: 'finished', winnerId: 'me', forfeitedBy: 'friend'),
      ),
    );
    await tester.pumpAndSettle();

    expect(findText(AppStrings.battleYouWon), findsOneWidget);
    expect(findText(AppStrings.battleWonByForfeit), findsOneWidget);
  });

  testWidgets('무효로 끝난 대결은 무효 칩과 무효 배너를 보여준다', (WidgetTester tester) async {
    await tester.pumpWidget(_detailScreen(_detail(id: 'bv', type: 'quality', status: 'voided')));
    await tester.pumpAndSettle();

    expect(findText(AppStrings.battleStatusVoided), findsOneWidget);
    expect(findText(AppStrings.battleVoidedMessage), findsOneWidget);
    expect(findText(AppStrings.battleYouWon), findsNothing);
    expect(findText(AppStrings.battleYouLost), findsNothing);
    expect(findText(AppStrings.battleDrawMessage), findsNothing);
  });

  testWidgets('포기 확인 문구는 속도전·품질전이 같고, 취소하면 포기하지 않는다', (WidgetTester tester) async {
    for (final type in ['speed', 'quality']) {
      await tester.pumpWidget(_detailScreen(_detail(id: 'ff-$type', type: type, status: 'active')));
      await tester.pumpAndSettle();

      await tester.ensureVisible(findText(AppStrings.battleForfeit));
      await tester.tap(findText(AppStrings.battleForfeit));
      await tester.pumpAndSettle();

      expect(findText(AppStrings.battleForfeitConfirmTitle), findsOneWidget, reason: type);
      expect(findText(AppStrings.battleForfeitConfirm), findsOneWidget, reason: type);

      await tester.tap(findText(AppStrings.cancel));
      await tester.pumpAndSettle();
      expect(findText(AppStrings.battleForfeitConfirmTitle), findsNothing, reason: type);

      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('대결 포기는 위험 텍스트 버튼이다(두께 없는 투명 면 + danger 라벨)', (WidgetTester tester) async {
    await tester.pumpWidget(_detailScreen(_detail(id: 'ff-style', type: 'speed', status: 'active')));
    await tester.pumpAndSettle();

    final forfeit = find.ancestor(
      of: findText(AppStrings.battleForfeit),
      matching: find.byWidgetPredicate((widget) => widget is TextButton),
    );
    expect(forfeit, findsOneWidget);
    expect(tester.widget<TextButton>(forfeit).style, same(AppButtonStyles.dangerText));
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
        ...pushOverrides(),
        ],
        child: const MaterialApp(home: ProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(findText('나'), findsOneWidget);
    // 점수와 승/패/무는 서버 player_stats 값을 그대로 보여 준다(화면이 목록을 세지 않는다).
    expect(findText(AppStrings.playerScoreLabel(3)), findsOneWidget);
    expect(findText(AppStrings.playerRecordLabel(1, 1, 0)), findsOneWidget);
    // 무효는 점수·전적에 들어가지 않으므로 목록과 숫자가 어긋나는 이유를 알린다.
    expect(findText(AppStrings.profileVoidedExcluded), findsOneWidget);

    // 2026-11-12(오너 안 B): 지난 대결은 이 탭에 펼쳐지지 않는다. 메뉴를 눌러 들어가야 보인다 —
    // 기록이 쌓일수록 점수 아래 모든 것이 화면 밖으로 밀리던 것을 멈추려는 것이다.
    expect(findText('아침 운동하기'), findsNothing);
    // 계정 창이 더는 목록 아래로 밀리지 않아 스크롤 없이 한 화면에 있다.
    expect(findText(AppStrings.accountSection), findsOneWidget);
    expect(findText(AppStrings.logout), findsOneWidget);
    expect(findText(AppStrings.accountDelete), findsOneWidget);

    await tester.tap(findText(AppStrings.profileHistorySection));
    await tester.pumpAndSettle();

    expect(findText('아침 운동하기'), findsOneWidget);
    expect(findText('방 청소하기'), findsOneWidget);
    expect(findText('책상 정리하기'), findsOneWidget);
    expect(findText(AppStrings.battleRecordWin), findsOneWidget);
    expect(findText(AppStrings.battleRecordLose), findsOneWidget);
    expect(findText(AppStrings.battleRecordVoided), findsOneWidget);
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
        ...pushOverrides(),
        ],
        child: const MaterialApp(home: ProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // 프로필 → 지난 대결 → 그 대결. 메뉴 한 단계가 2026-11-12에 생겼다(오너 안 B).
    await tester.tap(findText(AppStrings.profileHistorySection));
    await tester.pumpAndSettle();

    await tester.tap(findText('아침 운동하기'));
    await tester.pumpAndSettle();

    // 끝난 대결은 내 대결 목록에서 빠지므로 이 경로가 지난 결과를 보는 유일한 길이다.
    expect(findText(AppStrings.battleYouWon), findsOneWidget);
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
        ...pushOverrides(),
        ],
        child: const MaterialApp(home: ProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // 동의 섹션에 점수 창까지 생겨 계정 창이 첫 화면 아래로 밀린다. 목록은 보이는 곳만 그리므로
    // 내려서 찾고, 화면 가장자리에 걸친 채로 누르면 "off-screen"으로 실패하므로 ensureVisible까지 한다.
    Future<void> tapDeleteAccount() async {
      final button = findText(AppStrings.accountDelete);
      await tester.scrollUntilVisible(button, 200);
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
    }

    // 취소하면 삭제되지 않는다.
    await tapDeleteAccount();
    expect(findText(AppStrings.accountDeleteConfirmTitle), findsOneWidget);
    await tester.tap(findText(AppStrings.cancel));
    await tester.pumpAndSettle();
    expect(authRepository.deleteAccountCount, 0);

    // 확인해야 실제로 삭제된다.
    await tapDeleteAccount();
    await tester.tap(findText(AppStrings.accountDeleteConfirm));
    // 삭제 중에는 진행 표시가 계속 돌기 때문에 pumpAndSettle을 쓸 수 없다.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500)); // 스낵바 등장
    expect(authRepository.deleteAccountCount, 1);
    expect(findText(AppStrings.accountDeleteDone), findsOneWidget);
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
    expect(findText(AppStrings.vsIntroVersus), findsOneWidget);
    expect(store.seen, contains(VsIntroSeenStore.keyFor('me', 'bv')));

    // 누르면 즉시 닫히고 이미 그려진 상세 화면이 보인다.
    await tester.tap(find.byType(VsIntro));
    await tester.pump();
    expect(find.byType(VsIntro), findsNothing);
    // 인트로가 닫히면 진행 중인 속도전의 제출 자리가 보인다.
    expect(findText(AppStrings.battleEvidenceTakePhoto), findsOneWidget);

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

    await tester.tap(findText('open'));
    await tester.pump();

    expect(findText(AppStrings.vsIntroVersus), findsOneWidget);
    expect(findText('홍길동'), findsOneWidget);
    expect(findText('탈퇴한 사용자'), findsOneWidget);
    expect(findText('홍'), findsOneWidget);
    expect(findText('탈'), findsOneWidget);

    await tester.tap(find.byType(VsIntro));
    await tester.pump();
    expect(find.byType(VsIntro), findsNothing);
  });

  testWidgets('이름이 60자이고 글자 크기가 상한(1.5)이어도 VS 인트로가 넘치지 않고 1.5초 뒤 스스로 닫힌다',
      (WidgetTester tester) async {
    final longName = '가' * 60;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.5)),
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

    await tester.tap(findText('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    expect(tester.takeException(), isNull);
    expect(findText(longName), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump();
    expect(find.byType(VsIntro), findsNothing);
  });

  // 탭 라벨은 redesign에서 Pretendard labelSmall 12dp다(design 3.2). 배율 상한(1.5 — design 3.3)과
  // 좁은 화면(360dp)이 겹쳐도 탭바가 무너지지 않는지 보는 스모크 테스트다.
  //
  // **라벨이 칸을 넘는지는 이 테스트로 검증할 수 없다.** NavigationBar는 자체 레이아웃 델리게이트를
  // 써서 (1) 라벨이 넘쳐도 RenderFlex 예외를 내지 않고 (2) 라벨 상자 폭을 칸 폭 이하로 clamp하며
  // (3) 바 높이는 테마의 height: 72가 고정한다. 그래서 "라벨 폭 <= 칸 폭"은 어떤 배율에서도 참이다 —
  // 배율만 3.0으로 올린 복사본도 그대로 통과하는 것을 확인했다. 넘침은 예외가 아니라 2줄
  // 줄바꿈으로 나타나므로 육안 확인 대상이다.
  testWidgets('글자 크기 상한(1.5배)·360dp 폭에서도 탭바가 예외 없이 그려진다(스모크)', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          todosProvider.overrideWith((ref) async => []),
          myBattlesProvider.overrideWith((ref) async => []),
          myRecruitsProvider.overrideWith((ref) async => []),
          battleRepositoryProvider.overrideWithValue(_FakeBattleRepository()),
          myAiConsentProvider.overrideWith((ref) async => null),
          myProfileProvider.overrideWith(
            (ref) async => const Profile(id: 'me', displayName: '나'),
          ),
          myPlayerStatsProvider.overrideWith((ref) async => _testStats),
          battleRecordsProvider.overrideWith((ref) async => []),
        ...pushOverrides(),
        ...todoWidgetOverrides(),
        ...dueAlarmOverrides(),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: const MainShell(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);

    // 네 라벨이 모두 그려진다(라벨이 사라지거나 다른 것으로 바뀌면 깨진다).
    for (final label in [
      AppStrings.battleMyBattles,
      AppStrings.battleFind,
      AppStrings.todoTitle,
      AppStrings.profileTitle,
    ]) {
      expect(
        find.descendant(of: find.byType(NavigationBar), matching: findText(label)),
        findsOneWidget,
        reason: label,
      );
    }
    // 탭바가 세로로 자라 화면을 밀지 않는다(테마가 정한 72).
    expect(tester.getSize(find.byType(NavigationBar)).height, 72);

    // 선택된 탭(내 대결)만 채운 아이콘, 나머지는 윤곽 아이콘이다(찾기는 윤곽 변형이 없다).
    Finder barIcon(IconData icon) => find.descendant(
          of: find.byType(NavigationBar),
          matching: find.byIcon(icon),
        );
    expect(barIcon(AppIcons.battle), findsOneWidget);
    expect(barIcon(AppIcons.battleOutlined), findsNothing);
    expect(barIcon(AppIcons.todoOutlined), findsOneWidget);
    expect(barIcon(AppIcons.todo), findsNothing);
    expect(barIcon(AppIcons.profileOutlined), findsOneWidget);
    expect(barIcon(AppIcons.search), findsOneWidget);
  });

  testWidgets('로그인하면 할 일 목록이 홈 화면 위젯 캐시로 발행된다', (
    WidgetTester tester,
  ) async {
    final host = FakeTodoWidgetHost();

    await _pumpMainShellForWidgetCache(
      tester,
      host: host,
      todos: [
        Todo(
          id: 'a',
          title: '설거지하기',
          isDone: false,
          createdAt: DateTime(2026, 11, 4, 8),
        ),
        Todo(
          id: 'b',
          title: '빨래하기',
          isDone: true,
          createdAt: DateTime(2026, 11, 4, 9),
        ),
      ],
    );

    // 위젯이 보여 주는 것은 "남은 것"이다. 완료한 할 일이 캐시에 실리면 안 된다.
    expect(host.saved.last.items.map((item) => item.title), ['설거지하기']);
    // 캐시만 쓰고 끝나면 홈 화면은 그대로다. 다시 그리라는 브로드캐스트까지 가야 한다.
    expect(host.updateCount, greaterThan(0));
  });

  testWidgets('본 화면이 뜨는 순간 위젯 캐시가 먼저 불러오는 중으로 덮인다', (
    WidgetTester tester,
  ) async {
    final host = FakeTodoWidgetHost();

    await _pumpMainShellForWidgetCache(tester, host: host);

    // 로그아웃 캐시(이전 사용자의 할 일)가 로그인한 사용자에게 잠깐 보이지 않게 하는 장치다.
    expect(host.saved.first.centerText, AppStrings.widgetLoading);
    expect(host.saved.last.centerText, AppStrings.widgetEmpty);
  });

  testWidgets('할 일을 불러오지 못하면 위젯 캐시가 그 사실을 말한다', (
    WidgetTester tester,
  ) async {
    final host = FakeTodoWidgetHost();

    await _pumpMainShellForWidgetCache(
      tester,
      host: host,
      todosError: Exception('network down'),
    );

    // 받아온 목록이 없으니 안내 한 줄뿐이다. 서버 오류 메시지·코드는 위젯에 넣지 않는다.
    expect(host.saved.last.centerText, AppStrings.widgetFetchFailed);
  });

  testWidgets('앱을 다시 켰는데 못 불러오면 위젯은 지난 목록을 그대로 둔다', (
    WidgetTester tester,
  ) async {
    // 기기 캐시에 지난 목록이 남아 있는 상태(= 앱을 껐다 켠 뒤)를 만든다.
    final host = FakeTodoWidgetHost(
      stored: TodoWidgetPayload.fromTodos([
        Todo(
          id: 'a',
          title: '설거지하기',
          isDone: false,
          createdAt: DateTime(2026, 11, 4, 8),
        ),
      ], now: DateTime(2026, 11, 4, 9, 14)),
    );

    await _pumpMainShellForWidgetCache(
      tester,
      host: host,
      todosError: Exception('offline'),
    );

    // "불러오는 중"으로 캐시를 비우지 않고, 지난 목록 + 낡았다는 한 줄로 끝난다(spec P1 2행).
    expect(
      host.saved.map((payload) => payload.centerText),
      isNot(contains(AppStrings.widgetLoading)),
    );
    expect(host.saved.last.items.single.title, '설거지하기');
    expect(host.saved.last.note, '지금은 못 불러왔어요 · 오전 9:14 기준');
  });

  testWidgets('본 화면이 뜨면 미래 기한의 알림이 이 기기에 예약된다', (
    WidgetTester tester,
  ) async {
    final alarms = FakeDueAlarmHost();
    final dueAt = DateTime.now().add(const Duration(days: 2));

    await _pumpMainShellForWidgetCache(
      tester,
      host: FakeTodoWidgetHost(),
      dueAlarmHost: alarms,
      todos: [
        Todo(
          id: 'a',
          title: '설거지하기',
          isDone: false,
          createdAt: DateTime(2026, 11, 4, 8),
          dueAt: dueAt,
        ),
        // 기한이 없는 할 일과 완료한 할 일에는 알림이 가지 않는다.
        Todo(
          id: 'b',
          title: '빨래하기',
          isDone: false,
          createdAt: DateTime(2026, 11, 4, 9),
        ),
        Todo(
          id: 'c',
          title: '장보기',
          isDone: true,
          createdAt: DateTime(2026, 11, 4, 10),
          dueAt: dueAt,
        ),
      ],
    );

    // 목록이 바뀌는 모든 경로가 셸의 ref.listen을 지나므로 보정도 여기서 일어난다(design 8.6).
    expect(alarms.initializeCount, 1);
    expect(alarms.scheduled.map((alarm) => alarm.body), [
      '설거지하기',
      '설거지하기',
    ]);
    expect(alarms.scheduled.map((alarm) => alarm.title), [
      AppStrings.todoDueAlarmBeforeTitle,
      AppStrings.todoDueAlarmAtTitle,
    ]);
  });

  testWidgets('할 일을 불러오지 못하면 걸려 있는 예약을 건드리지 않는다', (
    WidgetTester tester,
  ) async {
    final alarms = FakeDueAlarmHost();

    await _pumpMainShellForWidgetCache(
      tester,
      host: FakeTodoWidgetHost(),
      dueAlarmHost: alarms,
      todosError: Exception('network down'),
    );

    // 네트워크가 없을 때 예약을 지우면 "서버가 안 되면 알림이 사라진다"가 된다.
    expect(alarms.pendingCount, 0);
    expect(alarms.cancelled, isEmpty);
    expect(alarms.cancelAllCount, 0);
  });

  testWidgets('이미 받아 둔 목록이 있어도(재로그인) 예약이 맞춰진다', (
    WidgetTester tester,
  ) async {
    final alarms = FakeDueAlarmHost();
    final dueAt = DateTime.now().add(const Duration(days: 2));

    await _pumpMainShellForWidgetCache(
      tester,
      host: FakeTodoWidgetHost(),
      dueAlarmHost: alarms,
      // 로그아웃 뒤에도 todosProvider는 살아 있다(autoDispose가 아니다). 그 상태에서 셸이 다시
      // 뜨면 ref.listen이 한 번도 울리지 않아, 보정이 셸 시작에 한 번 더 없으면 재로그인한
      // 사용자는 할 일을 건드릴 때까지 알림이 하나도 없다.
      preloadTodos: true,
      todos: [
        Todo(
          id: 'a',
          title: '설거지하기',
          isDone: false,
          createdAt: DateTime(2026, 11, 4, 8),
          dueAt: dueAt,
        ),
      ],
    );

    expect(alarms.scheduled.map((alarm) => alarm.body), [
      '설거지하기',
      '설거지하기',
    ]);
  });
}

/// 홈 화면 위젯 캐시 발행을 보려고 본 화면을 띄운다. 네 탭이 모두 서버를 보지 않게 고정한다.
Future<void> _pumpMainShellForWidgetCache(
  WidgetTester tester, {
  required FakeTodoWidgetHost host,
  FakeDueAlarmHost? dueAlarmHost,
  List<Todo> todos = const [],
  Object? todosError,
  bool preloadTodos = false,
}) async {
  final container = ProviderContainer(
    overrides: [
      todosProvider.overrideWith((ref) async {
        final error = todosError;
        if (error != null) throw error;
        return todos;
      }),
      myBattlesProvider.overrideWith((ref) async => []),
      myRecruitsProvider.overrideWith((ref) async => []),
      battleRepositoryProvider.overrideWithValue(_FakeBattleRepository()),
      myAiConsentProvider.overrideWith((ref) async => null),
      myProfileProvider.overrideWith(
        (ref) async => const Profile(id: 'me', displayName: '나'),
      ),
      myPlayerStatsProvider.overrideWith((ref) async => _testStats),
      battleRecordsProvider.overrideWith((ref) async => []),
      ...pushOverrides(),
      ...todoWidgetOverrides(host: host),
      ...dueAlarmOverrides(host: dueAlarmHost),
    ],
    // Riverpod의 자동 재시도 타이머가 테스트 종료 뒤까지 남지 않게 끈다.
    retry: (retryCount, error) => null,
  );
  addTearDown(container.dispose);
  // 셸이 뜨기 **전에** 목록을 이미 받아 둔 상태(= 같은 프로세스에서 재로그인). 그러면 아래
  // ref.listen은 한 번도 울리지 않는다 — 이미 data인 FutureProvider에 listen을 새로 붙이면
  // 콜백이 불리지 않기 때문이다.
  if (preloadTodos) await container.read(todosProvider.future);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: MainShell()),
    ),
  );
  await tester.pumpAndSettle();
}
