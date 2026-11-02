import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:todododo/core/strings.dart';
import 'package:todododo/core/theme/app_theme.dart';
import 'package:todododo/core/widgets/pixel_tag.dart';
import 'package:todododo/features/battle/data/battle.dart';
import 'package:todododo/features/battle/data/battle_participant.dart';
import 'package:todododo/features/battle/data/battle_repository.dart';
import 'package:todododo/features/battle/data/criteria_check_result.dart';
import 'package:todododo/features/battle/domain/battle_providers.dart';
import 'package:todododo/features/battle/domain/battle_summary.dart';
import 'package:todododo/features/battle/presentation/battle_chips.dart';
import 'package:todododo/features/battle/presentation/my_battles_screen.dart';

Battle _recruit() => Battle(
  id: 'p1',
  type: 'speed',
  status: 'pending',
  title: '설거지하기',
  creatorId: 'me',
  createdAt: DateTime(2026, 10, 28),
  durationMinutes: 30,
  minCriteria: const ['싱크대가 비어 있다'],
);

BattleSummary _activeSummary() => BattleSummary(
  battle: Battle(
    id: 'a1',
    type: 'quality',
    status: 'active',
    title: '방 청소하기',
    creatorId: 'me',
    opponentId: 'friend',
    createdAt: DateTime(2026, 10, 28),
    startedAt: DateTime(2026, 10, 28),
    deadlineAt: DateTime(2026, 10, 31),
    durationMinutes: 4320,
    minCriteria: const ['바닥이 보인다'],
    superiorityCriteria: const ['먼지가 없다'],
  ),
  otherPartyName: '도윤',
);

class _MyBattlesRepository implements BattleRepository {
  _MyBattlesRepository({List<Battle> recruits = const []})
    : recruits = [...recruits];

  List<Battle> recruits;
  int cancelCount = 0;

  /// 채워 두면 다음 모집 조회만 실패한다.
  Object? failNextRecruits;

  @override
  Future<List<Battle>> fetchMyRecruits() async {
    final error = failNextRecruits;
    if (error != null) {
      failNextRecruits = null;
      throw error;
    }
    return recruits;
  }

  @override
  Future<void> cancelBattle(String battleId) async {
    cancelCount++;
    recruits = recruits.where((battle) => battle.id != battleId).toList();
  }

  @override
  Future<MyLimits> fetchMyLimits() async => MyLimits(
    consented: true,
    hasPending: recruits.isNotEmpty,
    dailyBattleUsed: false,
    criteriaCallsLeft: 10,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Future<ProviderContainer> _pumpMyBattles(
  WidgetTester tester, {
  required _MyBattlesRepository repository,
  List<BattleSummary> summaries = const [],
  // 칩 줄 검증만 실제 테마와 글자 배율을 쓴다(나머지 테스트는 기본 테마 그대로 둔다).
  ThemeData? theme,
  double textScale = 1,
}) async {
  final container = ProviderContainer(
    overrides: [
      battleRepositoryProvider.overrideWithValue(repository),
      // 진행 중 목록은 로그인 세션을 직접 읽으므로 테스트에서는 값으로 고정한다.
      myBattlesProvider.overrideWith((ref) async => summaries),
    ],
    // Riverpod의 자동 재시도 타이머가 테스트 종료 뒤까지 남지 않게 끈다.
    retry: (retryCount, error) => null,
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const MyBattlesScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('내가 등록한 모집이 진행 중 목록과 구분된 구역으로 보인다', (tester) async {
    await _pumpMyBattles(
      tester,
      repository: _MyBattlesRepository(recruits: [_recruit()]),
      summaries: [_activeSummary()],
    );

    // 구역 A: 제목 띠 + 모집 제목 + 모집 중 칩 + 기간 + 기다리는 중 안내 + 두 버튼.
    expect(find.text(AppStrings.battleMyRecruits), findsOneWidget);
    expect(find.text('설거지하기'), findsOneWidget);
    expect(find.text(AppStrings.battleStatusPending), findsOneWidget);
    expect(find.text(battleDurationLabel(30)), findsOneWidget);
    expect(find.text(AppStrings.battleMyRecruitWaiting), findsOneWidget);
    expect(
      find.widgetWithText(OutlinedButton, AppStrings.battleCriteriaEditRecruit),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(TextButton, AppStrings.battleRecruitCancel),
      findsOneWidget,
    );

    // 구역 B: 진행 중 카드는 그대로다(상대·유형·상태 칩).
    expect(find.text('방 청소하기'), findsOneWidget);
    expect(find.text('${AppStrings.battleVersus} 도윤'), findsOneWidget);
    expect(find.text(AppStrings.battleStatusActive), findsOneWidget);
  });

  testWidgets('모집 1건만 있으면 "비었다"가 아니라 진행 중이 아직 없다고만 말한다', (tester) async {
    await _pumpMyBattles(
      tester,
      repository: _MyBattlesRepository(recruits: [_recruit()]),
    );

    expect(find.text(AppStrings.battleMyRecruits), findsOneWidget);
    expect(find.text(AppStrings.battleNoActiveBattlesYet), findsOneWidget);
    // 모집 구역이 이미 "기다리는 중"을 말하므로 찾기 탭으로 보내는 버튼을 두 번 권하지 않는다.
    expect(find.text(AppStrings.battleMyBattlesEmpty), findsNothing);
    expect(
      find.widgetWithText(FilledButton, AppStrings.battleFind),
      findsNothing,
    );
  });

  testWidgets('모집도 진행 중도 없으면 기존 빈 상태 안내가 그대로 보인다', (tester) async {
    await _pumpMyBattles(tester, repository: _MyBattlesRepository());

    expect(find.text(AppStrings.battleMyRecruits), findsNothing);
    expect(find.text(AppStrings.battleMyBattlesEmpty), findsOneWidget);
    expect(find.text(AppStrings.battleFinishedInProfile), findsOneWidget);
    expect(
      find.widgetWithText(FilledButton, AppStrings.battleFind),
      findsOneWidget,
    );
  });

  // riverpod은 실패해도 직전 값을 들고 있다. 그 값을 그대로 그리면 이미 사라졌을 수도 있는
  // 모집에 기준 수정을 시도하게 된다.
  testWidgets('모집을 다시 읽다 실패하면 낡은 모집을 그대로 두지 않고 실패를 알린다', (tester) async {
    final repository = _MyBattlesRepository(recruits: [_recruit()]);
    final container = await _pumpMyBattles(tester, repository: repository);
    expect(find.text('설거지하기'), findsOneWidget);

    repository.failNextRecruits = Exception('network down');
    container.invalidate(myRecruitsProvider);
    await tester.pumpAndSettle();

    expect(find.text('설거지하기'), findsNothing);
    expect(find.text(AppStrings.battleLoadRecruitsFailed), findsOneWidget);
    expect(find.widgetWithText(TextButton, AppStrings.retry), findsOneWidget);

    // 다시 시도하면 구역이 돌아온다.
    await tester.tap(find.widgetWithText(TextButton, AppStrings.retry));
    await tester.pumpAndSettle();
    expect(find.text('설거지하기'), findsOneWidget);
  });

  testWidgets('모집을 취소하면 그 구역이 사라지고 새로 올릴 수 있는 상태로 돌아온다', (tester) async {
    final repository = _MyBattlesRepository(recruits: [_recruit()]);
    await _pumpMyBattles(tester, repository: repository);

    await tester.tap(
      find.widgetWithText(TextButton, AppStrings.battleRecruitCancel),
    );
    await tester.pumpAndSettle();

    expect(repository.cancelCount, 1);
    expect(find.text(AppStrings.battleRecruitCancelled), findsOneWidget);
    expect(find.text(AppStrings.battleMyRecruits), findsNothing);
    expect(find.text('설거지하기'), findsNothing);
    // 모집이 없어졌으므로 빈 상태 안내로 돌아온다.
    expect(find.text(AppStrings.battleMyBattlesEmpty), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  // 칩 라벨이 12dp 픽셀에서 14dp 본문 글꼴로 커졌다(readability.md 방안 2).
  // 좁은 화면·큰 글자에서 한 줄에 다 못 들어가면 칩을 빼지 않고 다음 줄로 내린다(3-1).
  testWidgets('글자 크기 1.3배·360dp 폭에서도 모집 카드 칩 세 개가 다 남고 칸을 넘지 않는다', (tester) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await _pumpMyBattles(
      tester,
      repository: _MyBattlesRepository(recruits: [_recruit()]),
      theme: AppTheme.light,
      textScale: 1.3,
    );

    expect(tester.takeException(), isNull);

    // 유형 배지 + 모집 중 + 기간. 하나라도 빼면 사용자가 정보를 잃는다.
    final badge = find.byType(BattleTypeBadge);
    expect(badge, findsOneWidget);
    expect(find.text(AppStrings.battleStatusPending), findsOneWidget);
    expect(find.text(battleDurationLabel(30)), findsOneWidget);

    // Row로 되돌리면(= 줄바꿈이 사라지면) 이 단정이 깨진다.
    final wrap = find.ancestor(of: badge, matching: find.byType(Wrap));
    expect(wrap, findsOneWidget);

    // 어떤 칩도 화면 밖으로 나가지 않는다(세 개가 한 줄에 다 못 들어가면 아래 줄로 내려간다).
    final screen = tester.getRect(find.byType(MyBattlesScreen));
    expect(screen.width, 360);
    final chips = <Finder>[badge, ...List.generate(2, (i) => find.byType(PixelTag).at(i))];
    for (final chip in chips) {
      final rect = tester.getRect(chip);
      expect(rect.left, greaterThanOrEqualTo(screen.left - 0.5));
      expect(rect.right, lessThanOrEqualTo(screen.right + 0.5));
    }
  });

  // 푸시가 없는 MVP에서 "지금 내가 할 일"을 말하는 자리가 이 카드뿐이다(mobile-ux M1).
  // 카드는 DateTime.now()를 읽으므로 고정 날짜 픽스처가 아니라 지금 시각 기준으로 만든다
  // (유닛 테스트는 statusLineAt(now)로 덮는다).
  testWidgets('판정 창에서 내 차례면 카드가 그 말을 강조하고 판정 기한을 함께 보여 준다', (tester) async {
    await _pumpMyBattles(
      tester,
      repository: _MyBattlesRepository(),
      summaries: [_judgingSummaryNow()],
    );

    expect(find.text(AppStrings.battleListMyJudgeTurn), findsOneWidget);
    expect(
      find.text(
        '${AppStrings.battleJudgeDeadlineLabel} · '
        '${AppStrings.battleDeadlineLeft('2시간')}',
      ),
      findsOneWidget,
    );

    // 할 일이 있는 줄만 굵게 띄운다. 모든 줄을 같은 모양으로 그리면 구분이 사라진다.
    final line = tester.widget<Text>(
      find.text(AppStrings.battleListMyJudgeTurn),
    );
    expect(line.style?.fontWeight, FontWeight.w600);
  });

  testWidgets('제출 창에서 내 사진이 없으면 카드가 그 말을 하고, 상대 소식은 흐리게 둔다', (tester) async {
    await _pumpMyBattles(
      tester,
      repository: _MyBattlesRepository(),
      summaries: [_activeSummaryNow(iSubmitted: false)],
    );

    expect(find.text(AppStrings.battleListNotSubmitted), findsOneWidget);
    expect(
      find.text(
        '${AppStrings.battleSubmitDeadlineLabel} · '
        '${AppStrings.battleDeadlineLeft('5시간')}',
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Text>(find.text(AppStrings.battleListNotSubmitted))
          .style
          ?.fontWeight,
      FontWeight.w600,
    );

  });

  // 내가 이미 냈으면 남은 소식은 "상대가 제출했어요"이고, 그것은 내 할 일이 아니다.
  testWidgets('상대 제출 소식은 내 할 일 줄과 다른 모양으로 둔다', (tester) async {
    await _pumpMyBattles(
      tester,
      repository: _MyBattlesRepository(),
      summaries: [_activeSummaryNow(opponentSubmitted: true)],
    );

    expect(find.text(AppStrings.battleListNotSubmitted), findsNothing);
    final news = tester.widget<Text>(
      find.text(AppStrings.battleListOpponentSubmitted),
    );
    expect(news.style?.fontWeight, isNot(FontWeight.w600));
  });

  // M6 — 로그인 직후 첫 탭이 여기다. 새 계정은 이 앱이 무엇인지 어디서도 듣지 못한 상태로
  // `진행 중인 대결이 없어요.` 한 줄을 본다. 온보딩 화면을 만들지 않고 빈 상태 위 블록 한 장으로 말한다.
  testWidgets('대결도 모집도 없는 첫 화면은 이 앱이 무엇인지 세 줄로 먼저 말한다', (tester) async {
    await _pumpMyBattles(tester, repository: _MyBattlesRepository());

    expect(find.text(AppStrings.battleIntroMatching), findsOneWidget);
    expect(find.text(AppStrings.battleIntroEvidence), findsOneWidget);
    expect(find.text(AppStrings.battleIntroJudging), findsOneWidget);

    // 기존 빈 상태와 CTA는 그대로 남는다. 블록이 그것을 대신하지 않는다.
    expect(find.text(AppStrings.battleMyBattlesEmpty), findsOneWidget);
    expect(
      find.widgetWithText(FilledButton, AppStrings.battleFind),
      findsOneWidget,
    );

    // 빈 상태 "위"다 — 설명을 읽고 나서 다음 행동 버튼에 닿는다.
    expect(
      tester.getTopLeft(find.text(AppStrings.battleIntroMatching)).dy,
      lessThan(tester.getTopLeft(find.text(AppStrings.battleMyBattlesEmpty)).dy),
    );
  });

  // 음성 단언. 이 블록은 빈 상태 전용이다 — 대결이 하나라도 있으면 소개를 다시 읽힐 이유가 없고,
  // 목록 맨 위를 설명으로 밀어내면 "지금 내가 할 일"이 그만큼 내려간다.
  testWidgets('진행 중인 대결이 있으면 소개 블록이 보이지 않는다', (tester) async {
    await _pumpMyBattles(
      tester,
      repository: _MyBattlesRepository(),
      summaries: [_activeSummary()],
    );

    expect(find.text('방 청소하기'), findsOneWidget);
    expect(find.text(AppStrings.battleIntroMatching), findsNothing);
    expect(find.text(AppStrings.battleIntroEvidence), findsNothing);
    expect(find.text(AppStrings.battleIntroJudging), findsNothing);
  });

  // audit.md가 적지 않은 자리(developer 재량). 모집을 이미 올려 본 사람은 만들기 흐름을 한 번 지났고
  // 기준·동의 화면에서 설명을 다 읽은 뒤다. 거기서는 빈 상태 자체가 뜨지 않으므로 블록도 두지 않는다.
  testWidgets('모집 1건만 있는 화면에도 소개 블록을 두지 않는다', (tester) async {
    await _pumpMyBattles(
      tester,
      repository: _MyBattlesRepository(recruits: [_recruit()]),
    );

    expect(find.text(AppStrings.battleNoActiveBattlesYet), findsOneWidget);
    expect(find.text(AppStrings.battleIntroMatching), findsNothing);
    expect(find.text(AppStrings.battleIntroEvidence), findsNothing);
    expect(find.text(AppStrings.battleIntroJudging), findsNothing);
  });
}

/// 판정 창(판정 기한 2시간 남음)에 들어간 내 대결. 상대는 사진을 냈고 나는 아직 판정하지 않았다.
BattleSummary _judgingSummaryNow() {
  final now = DateTime.now();
  return BattleSummary(
    battle: Battle(
      id: 'j1',
      type: 'quality',
      status: 'judging',
      title: '방 청소하기',
      creatorId: 'me',
      opponentId: 'friend',
      createdAt: now.subtract(const Duration(days: 2)),
      startedAt: now.subtract(const Duration(days: 2)),
      deadlineAt: now.subtract(const Duration(hours: 1)),
      judgingOpenedAt: now.subtract(const Duration(hours: 1)),
      judgeDeadlineAt: now.add(const Duration(hours: 2, minutes: 1)),
      durationMinutes: 2880,
      minCriteria: const ['바닥이 보인다'],
      superiorityCriteria: const ['먼지가 없다'],
    ),
    otherPartyName: '도윤',
    me: const BattleParticipant(battleId: 'j1', userId: 'me', hasSubmitted: true),
    opponent: const BattleParticipant(
      battleId: 'j1',
      userId: 'friend',
      hasSubmitted: true,
    ),
  );
}

/// 제출 창(사진 마감 5시간 남음)인 내 대결.
BattleSummary _activeSummaryNow({
  bool iSubmitted = true,
  bool opponentSubmitted = false,
}) {
  final now = DateTime.now();
  return BattleSummary(
    battle: Battle(
      id: 'a2',
      type: 'speed',
      status: 'active',
      title: '아침 운동하기',
      creatorId: 'me',
      opponentId: 'friend',
      createdAt: now.subtract(const Duration(hours: 1)),
      startedAt: now.subtract(const Duration(hours: 1)),
      deadlineAt: now.add(const Duration(hours: 5, minutes: 1)),
      durationMinutes: 360,
      minCriteria: const ['운동복을 입은 사진'],
    ),
    otherPartyName: '도윤',
    me: BattleParticipant(battleId: 'a2', userId: 'me', hasSubmitted: iSubmitted),
    opponent: BattleParticipant(
      battleId: 'a2',
      userId: 'friend',
      hasSubmitted: opponentSubmitted,
    ),
  );
}
