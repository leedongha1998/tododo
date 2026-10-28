import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:todododo/core/strings.dart';
import 'package:todododo/features/battle/data/battle.dart';
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
      child: const MaterialApp(home: MyBattlesScreen()),
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
}
