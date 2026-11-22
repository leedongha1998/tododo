import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:todododo/core/strings.dart';
import 'package:todododo/core/widgets/app_tag.dart';
import 'package:todododo/features/battle/data/battle.dart';
import 'package:todododo/features/battle/data/battle_participant.dart';
import 'package:todododo/features/battle/data/battle_repository.dart';
import 'package:todododo/features/battle/data/battle_submission.dart';
import 'package:todododo/features/battle/data/bot_battle_topic.dart';
import 'package:todododo/features/battle/data/player_card.dart';
import 'package:todododo/features/battle/data/vs_intro_seen_store.dart';
import 'package:todododo/features/battle/domain/battle_detail.dart';
import 'package:todododo/features/battle/domain/battle_outcome.dart';
import 'package:todododo/features/battle/domain/battle_providers.dart';
import 'package:todododo/features/battle/presentation/battle_detail_screen.dart';
import 'package:todododo/features/battle/presentation/bot_battle_topics_screen.dart';
import 'package:todododo/features/profile/domain/battle_record.dart';
import 'package:todododo/features/profile/presentation/battle_records_screen.dart';

import '../../helpers/text_finders.dart';

/// 연습 대결(봇전) 화면. **승패·점수·상태는 전부 서버 값**이므로 여기서 보는 것은
/// "무엇을 보여 주고 무엇을 묻지 않는가"뿐이다 — 특히 **판정을 묻지 않는 것**이 중요하다
/// (불복이라는 입력이 서버에 들어올 수 없어야 AI 호출 0회가 지켜진다).
class _BotRepository implements BattleRepository {
  _BotRepository({this.topics = const [], this.dailyLeft = 3});

  final List<BotBattleTopic> topics;
  final int dailyLeft;

  final startedTopicIds = <String>[];
  final playerCardCalls = <String>[];
  int settleCalls = 0;

  @override
  Future<BotBattleTopics> listBotBattleTopics() async =>
      BotBattleTopics(dailyLimit: 3, dailyLeft: dailyLeft, topics: topics);

  @override
  Future<String> startBotBattle(String topicId) async {
    startedTopicIds.add(topicId);
    return 'b1';
  }

  @override
  Future<int> settleMyBotBattles() async {
    settleCalls++;
    return 0;
  }

  @override
  Future<PlayerCard> fetchPlayerCard(String userId) async {
    playerCardCalls.add(userId);
    return const PlayerCard(userId: 'bot', displayName: '연습 봇', score: 999, wins: 999);
  }

  @override
  Future<String> createEvidencePhotoUrl(String path) async =>
      throw Exception('서명 URL은 이 테스트의 사정권이 아니다');

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _SeenAllStore implements VsIntroSeenStore {
  const _SeenAllStore();

  @override
  Future<bool> hasSeen(String userId, String battleId) async => true;

  @override
  Future<void> markSeen(String userId, String battleId) async {}
}

const _topic = BotBattleTopic(
  id: 't1',
  title: '설거지하기',
  minCriteria: ['싱크대 안에 씻지 않은 그릇이나 컵이 보이지 않는다', '싱크대 바닥에 음식물 찌꺼기가 남아 있지 않다'],
  durationMinutes: 10,
);

const _topic2 = BotBattleTopic(
  id: 't2',
  title: '쓰레기통 비우기',
  minCriteria: ['쓰레기통 안이 비어 있거나 새 봉투가 끼워져 있다'],
  durationMinutes: 5,
);

Widget _topicsScreen(_BotRepository repository) {
  return ProviderScope(
    overrides: [
      battleRepositoryProvider.overrideWithValue(repository),
      // 시작에 성공하면 그 대결 상세로 갈아 끼운다. 그 화면이 서버를 다시 읽지 않게 둔다.
      battleDetailProvider('b1').overrideWith((ref) async => _botDetail()),
      vsIntroSeenStoreProvider.overrideWithValue(const _SeenAllStore()),
    ],
    child: const MaterialApp(home: BotBattleTopicsScreen()),
  );
}

final _now = DateTime(2026, 11, 21, 12);

BattleSubmission _mySubmission({String? verdictSource}) => BattleSubmission(
      id: 1,
      battleId: 'b1',
      userId: 'me',
      objectPath: 'b1/me/photo.jpg',
      capturedAt: _now.add(const Duration(minutes: 3)),
      submittedAt: _now.add(const Duration(minutes: 3)),
      meetsCriteria: true,
      verdictSource: verdictSource,
    );

/// 봇의 제출 행. **사진도 촬영 시각도 없다**(서버가 null로 둔다).
BattleSubmission _botSubmission() => BattleSubmission(
      id: 2,
      battleId: 'b1',
      userId: 'bot',
      submittedAt: _now.add(const Duration(minutes: 6)),
      meetsCriteria: true,
      verdictSource: 'auto',
    );

BattleDetail _botDetail({
  String status = 'active',
  String? myOutcome,
  int? scoreDelta,
  String? winnerId,
  bool myHasSubmitted = false,
  List<BattleSubmission> submissions = const [],
}) {
  final battle = Battle(
    id: 'b1',
    type: 'speed',
    status: status,
    title: '설거지하기',
    creatorId: 'me',
    opponentId: 'bot',
    winnerId: winnerId,
    createdAt: _now,
    startedAt: _now,
    deadlineAt: _now.add(const Duration(minutes: 10)),
    judgingOpenedAt: status == 'active' ? null : _now.add(const Duration(minutes: 6)),
    judgeDeadlineAt: status == 'judging' ? _now.add(const Duration(hours: 24)) : null,
    durationMinutes: 10,
    minCriteria: const ['싱크대 안에 씻지 않은 그릇이나 컵이 보이지 않는다'],
    isBot: true,
    botTopicId: 't1',
  );
  return BattleDetail(
    battle: battle,
    me: BattleParticipant(
      battleId: 'b1',
      userId: 'me',
      hasSubmitted: myHasSubmitted,
      outcome: myOutcome,
      scoreDeltaApplied: scoreDelta,
    ),
    opponent: const BattleParticipant(battleId: 'b1', userId: 'bot'),
    myName: '나',
    opponentName: '연습 봇',
    submissions: submissions,
  );
}

Widget _detailScreen(BattleDetail detail, _BotRepository repository) {
  return ProviderScope(
    overrides: [
      battleDetailProvider(detail.battle.id).overrideWith((ref) async => detail),
      battleRepositoryProvider.overrideWithValue(repository),
      vsIntroSeenStoreProvider.overrideWithValue(const _SeenAllStore()),
      // 봇 칸에는 사진이 없고, 내 사진의 서명 URL은 이 테스트의 사정권이 아니다.
      evidencePhotoUrlProvider('b1/me/photo.jpg')
          .overrideWith((ref) => Future<String>.error('no storage in tests')),
    ],
    child: MaterialApp(home: BattleDetailScreen(battleId: detail.battle.id)),
  );
}

void main() {
  group('주제 고르기', () {
    testWidgets('주제 카드마다 제목·기간·최소 기준이 보이고 남은 횟수를 말한다', (tester) async {
      final repository = _BotRepository(topics: const [_topic, _topic2], dailyLeft: 2);
      await tester.pumpWidget(_topicsScreen(repository));
      await tester.pumpAndSettle();

      expect(findText(AppStrings.botBattleTopicsIntro), findsOneWidget);
      expect(findText(AppStrings.botBattleDailyLeft(2, 3)), findsOneWidget);
      expect(findText('설거지하기'), findsOneWidget);
      expect(findText('쓰레기통 비우기'), findsOneWidget);
      // 기간은 주제에 붙어 있다(사용자가 고르지 않는다).
      expect(findText('10분'), findsOneWidget);
      expect(findText('5분'), findsOneWidget);
      // 무엇을 찍어야 하는지가 고르는 근거라 기준을 접지 않고 보여 준다.
      expect(findText(_topic.minCriteria.first), findsOneWidget);
      // 횟수가 남아 있으면 "다 썼다" 안내는 없다.
      expect(findText(AppStrings.botBattleDailyNone), findsNothing);
    });

    testWidgets('오늘 횟수를 다 쓰면 카드는 그대로 보이고 시작만 막힌다', (tester) async {
      final repository = _BotRepository(topics: const [_topic], dailyLeft: 0);
      await tester.pumpWidget(_topicsScreen(repository));
      await tester.pumpAndSettle();

      expect(findText(AppStrings.botBattleDailyNone), findsOneWidget);
      // 무엇을 할 수 있는 기능인지는 보여 준다.
      expect(findText('설거지하기'), findsOneWidget);

      await tester.tap(findText('설거지하기'));
      await tester.pumpAndSettle();
      // 확인 시트가 열리지 않는다(서버도 BOT_DAILY_LIMIT으로 거부한다).
      expect(findText(AppStrings.botBattleStartConfirmTitle), findsNothing);
      expect(repository.startedTopicIds, isEmpty);
    });

    testWidgets('운영자가 주제를 전부 내리면 그 사실만 말한다', (tester) async {
      await tester.pumpWidget(_topicsScreen(_BotRepository()));
      await tester.pumpAndSettle();

      expect(findText(AppStrings.botBattleTopicsEmpty), findsOneWidget);
    });

    testWidgets('확인 시트는 상대가 봇이라는 것·점수·하루 3회를 시작 전에 말한다', (tester) async {
      final repository = _BotRepository(topics: const [_topic]);
      await tester.pumpWidget(_topicsScreen(repository));
      await tester.pumpAndSettle();

      await tester.tap(findText('설거지하기'));
      await tester.pumpAndSettle();

      expect(findText(AppStrings.botBattleStartConfirmTitle), findsOneWidget);
      expect(findText(AppStrings.botBattleStartNoticeBot), findsOneWidget);
      expect(findText(AppStrings.botBattleStartNoticeScore), findsOneWidget);
      // 기준은 시작 전에 공개된다(사람 대결과 같은 규칙). 뒤에 깔린 주제 카드에도 같은 글이
      // 있으므로 두 번 잡힌다.
      expect(findText(_topic.minCriteria.last), findsNWidgets(2));
      // 봇의 목표 시각은 비율도 숫자도 적지 않는다.
      expect(findTextContaining('50'), findsNothing);
      expect(findTextContaining('85'), findsNothing);
    });

    testWidgets('시작은 주제 id 하나만 보낸다', (tester) async {
      final repository = _BotRepository(topics: const [_topic]);
      await tester.pumpWidget(_topicsScreen(repository));
      await tester.pumpAndSettle();

      await tester.tap(findText('설거지하기'));
      await tester.pumpAndSettle();
      await tester.tap(findWidgetWithText(FilledButton, AppStrings.botBattleStart));
      await tester.pumpAndSettle();

      expect(repository.startedTopicIds, ['t1']);
    });
  });

  group('봇전 상세', () {
    testWidgets('진행 중에는 연습 배지와 상대 칸 안내가 보이고 전적을 조회하지 않는다', (tester) async {
      final repository = _BotRepository();
      await tester.pumpWidget(_detailScreen(_botDetail(), repository));
      await tester.pumpAndSettle();

      expect(
        find.byWidgetPredicate(
          (widget) => widget is AppTag && widget.label == AppStrings.botBattleBadge,
        ),
        findsOneWidget,
      );
      expect(findText('연습 봇'), findsOneWidget);
      expect(findText(AppStrings.botBattleOpponentLabel), findsOneWidget);
      // 봇 칸은 빈 칸도 가짜 이미지도 아니다 — 사실과 "기간 안 어느 시각에 완료한다"를 적는다.
      expect(findText(AppStrings.botBattleNoEvidence), findsOneWidget);
      expect(findText(AppStrings.botBattleOpponentWaiting), findsOneWidget);
      // 점수·승패 숫자가 한 자도 없다(조회 자체를 하지 않는다).
      expect(repository.playerCardCalls, isEmpty);
      // 묻는 것이 없다.
      expect(findText(AppStrings.battleJudgmentMinQuestion), findsNothing);
      expect(findText(AppStrings.battleJudgmentFailed), findsNothing);
      // 사진 마감은 보이고 판정 마감 줄은 없다(봇전은 판정 창에 머물지 않는다).
      expect(findTextContaining(AppStrings.battleSubmitDeadlineLabel), findsOneWidget);
      expect(findTextContaining(AppStrings.battleJudgeDeadlineLabel), findsNothing);
      // 빠져나가는 유일한 길은 그대로 있다.
      expect(findText(AppStrings.battleForfeit), findsWidgets);
    });

    testWidgets('판정 창이 남는 드문 경우에도 묻지 않고 한 줄만 말한다', (tester) async {
      await tester.pumpWidget(
        _detailScreen(_botDetail(status: 'judging', myHasSubmitted: true), _BotRepository()),
      );
      await tester.pumpAndSettle();

      expect(findText(AppStrings.botBattleNoJudgment), findsOneWidget);
      expect(findText(AppStrings.battleJudgmentMinQuestion), findsNothing);
      expect(findText(AppStrings.battleJudgmentPassed), findsNothing);
      expect(findText(AppStrings.battleJudgmentFailed), findsNothing);
    });

    testWidgets('종결 뒤에는 봇 완료 시각과 자동 인정 설명이 보인다', (tester) async {
      final detail = _botDetail(
        status: 'finished',
        winnerId: 'bot',
        myOutcome: 'completed_loss',
        scoreDelta: -1,
        myHasSubmitted: true,
        submissions: [_mySubmission(verdictSource: 'auto'), _botSubmission()],
      );
      await tester.pumpWidget(_detailScreen(detail, _BotRepository()));
      await tester.pumpAndSettle();

      // 결과·점수는 서버 값 그대로, 부제만 봇전 문구로 갈린다.
      expect(findText(AppStrings.battleYouLost), findsOneWidget);
      expect(findText(AppStrings.botBattleCompletedLoss), findsOneWidget);
      // 사람 대결의 "감점이 줄었다" 설명은 쓰지 않는다(봇전은 -1 하나뿐이다).
      expect(findText(AppStrings.battleCompletedLoss), findsNothing);
      expect(findText(AppStrings.battleScoreDelta(-1)), findsOneWidget);
      // 봇 칸: 사진 자리를 비우지 않고 완료 시각과 사실을 둔다.
      expect(findTextContaining(AppStrings.botBattleDoneAtLabel), findsOneWidget);
      expect(findText(AppStrings.botBattleNoEvidence), findsOneWidget);
      // 내 사진은 "봇이 판정하지 않아 그대로 인정됐다"로 설명한다.
      expect(findText(AppStrings.botBattleAutoApproved), findsOneWidget);
    });

    testWidgets('사진을 내지 않고 마감까지 두면 그 사실을 부제가 말한다', (tester) async {
      final detail = _botDetail(
        status: 'finished',
        winnerId: 'bot',
        myOutcome: 'loss',
        scoreDelta: -1,
        submissions: [_botSubmission()],
      );
      await tester.pumpWidget(_detailScreen(detail, _BotRepository()));
      await tester.pumpAndSettle();

      expect(findText(AppStrings.botBattleLossNoSubmission), findsOneWidget);
      expect(findText(AppStrings.battleEvidenceNoSubmission), findsOneWidget);
    });

    testWidgets('이기면 봇보다 먼저 완료했다고 말한다', (tester) async {
      final detail = _botDetail(
        status: 'finished',
        winnerId: 'me',
        myOutcome: 'win',
        scoreDelta: 1,
        myHasSubmitted: true,
        submissions: [_mySubmission(verdictSource: 'auto'), _botSubmission()],
      );
      await tester.pumpWidget(_detailScreen(detail, _BotRepository()));
      await tester.pumpAndSettle();

      expect(findText(AppStrings.battleYouWon), findsOneWidget);
      expect(findText(AppStrings.botBattleWon), findsOneWidget);
      expect(findText(AppStrings.battleScoreDelta(1)), findsOneWidget);
    });
  });

  testWidgets('기록 카드에 연습 배지가 붙는다', (tester) async {
    final battle = Battle(
      id: 'b1',
      type: 'speed',
      status: 'finished',
      title: '설거지하기',
      creatorId: 'me',
      opponentId: 'bot',
      winnerId: 'me',
      createdAt: _now,
      isBot: true,
      botTopicId: 't1',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BattleRecordTile(
            record: BattleRecord(
              battle: battle,
              otherPartyName: '연습 봇',
              result: BattleResult.win,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byWidgetPredicate(
        (widget) => widget is AppTag && widget.label == AppStrings.botBattleBadge,
      ),
      findsOneWidget,
    );
    expect(findText('vs 연습 봇'), findsOneWidget);
  });
}
