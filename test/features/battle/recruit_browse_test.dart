import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:todododo/core/navigation/app_tab.dart';
import 'package:todododo/core/strings.dart';
import 'package:todododo/features/battle/data/battle.dart';
import 'package:todododo/features/battle/data/battle_repository.dart';
import 'package:todododo/features/battle/data/criteria_check_result.dart';
import 'package:todododo/features/battle/data/open_recruit.dart';
import 'package:todododo/features/battle/data/open_recruit_page.dart';
import 'package:todododo/features/battle/data/player_card.dart';
import 'package:todododo/features/battle/domain/battle_providers.dart';
import 'package:todododo/features/battle/domain/open_recruit_feed.dart';
import 'package:todododo/features/battle/domain/recruit_query.dart';
import 'package:todododo/features/battle/presentation/battle_recruits_screen.dart';

OpenRecruit _recruit(int index, {String type = 'speed', int minutes = 30}) =>
    OpenRecruit(
      battle: Battle(
        id: 'b$index',
        type: type,
        status: 'pending',
        title: '모집 $index',
        creatorId: 'creator$index',
        createdAt: DateTime(2026, 10, 28).subtract(Duration(minutes: index)),
        durationMinutes: minutes,
        minCriteria: const ['싱크대가 비어 있다'],
      ),
      creator: PlayerCard(userId: 'creator$index', displayName: '도윤$index'),
    );

/// 서버를 흉내 낸 가짜 repository. 조건 적용과 묶음 끊기를 이 안에서 한다.
class _BrowseRepository implements BattleRepository {
  _BrowseRepository({
    this.all = const [],
    this.hasPending = false,
    this.failFirstPage = false,
  });

  final List<OpenRecruit> all;
  final bool hasPending;
  final bool failFirstPage;

  final calls = <Map<String, Object?>>[];

  /// 채워 두면 그 묶음 요청이 이 Completer를 기다린다(꼬리 로딩을 보려고).
  Completer<void>? gate;
  Object? failNext;

  @override
  Future<MyLimits> fetchMyLimits() async => MyLimits(
    consented: true,
    hasPending: hasPending,
    dailyBattleUsed: false,
    criteriaCallsLeft: 10,
  );

  @override
  Future<OpenRecruitPage> fetchOpenRecruits({
    int limit = openRecruitPageSize,
    RecruitCursor? cursor,
    String? query,
    String? type,
    String? durationBand,
  }) async {
    calls.add({
      'cursor': cursor?.id,
      'query': query,
      'type': type,
      'band': durationBand,
    });
    if (failFirstPage && cursor == null) throw Exception('first page down');
    final error = failNext;
    if (error != null) {
      failNext = null;
      throw error;
    }
    final gate = this.gate;
    if (gate != null) {
      this.gate = null;
      await gate.future;
    }

    var items = all;
    if (query != null) {
      items = items.where((item) => item.battle.title.contains(query)).toList();
    }
    if (type != null) {
      items = items.where((item) => item.battle.type == type).toList();
    }
    if (durationBand != null) {
      items = items
          .where(
            (item) => switch (durationBand) {
              'quick' => item.battle.durationMinutes <= 60,
              'day' =>
                item.battle.durationMinutes > 60 &&
                    item.battle.durationMinutes <= 1440,
              _ => item.battle.durationMinutes > 1440,
            },
          )
          .toList();
    }
    var start = 0;
    if (cursor != null) {
      start = items.indexWhere((item) => item.battle.id == cursor.id) + 1;
    }
    final slice = items.skip(start).take(limit).toList();
    return OpenRecruitPage(
      items: slice,
      nextCursor: slice.isEmpty
          ? null
          : RecruitCursor(
              createdAt: slice.last.battle.createdAt.toIso8601String(),
              id: slice.last.battle.id,
            ),
      hasMore: slice.length == limit,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Future<ProviderContainer> _pumpFind(
  WidgetTester tester,
  _BrowseRepository repository,
) async {
  final container = ProviderContainer(
    overrides: [battleRepositoryProvider.overrideWithValue(repository)],
    // Riverpod는 실패한 provider를 스스로 다시 부른다(기본 재시도). 테스트에서는 그 타이머가
    // 남아 "Timer is still pending"으로 터지므로, 실패 화면만 보려고 끈다.
    retry: (retryCount, error) => null,
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: BattleRecruitsScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Finder _segment<T>(String label) => find.descendant(
  of: find.byType(SegmentedButton<T>),
  matching: find.text(label),
);

void main() {
  testWidgets('글자마다 부르지 않고 입력이 멈춘 뒤 한 번만 서버를 부른다', (tester) async {
    final repository = _BrowseRepository(
      all: [for (var i = 0; i < 3; i++) _recruit(i)],
    );
    await _pumpFind(tester, repository);
    expect(repository.calls.length, 1);

    // 한 글자씩 치는 동안에는 타이머가 다시 걸릴 뿐 요청이 나가지 않는다.
    // (입력창 글자와 카드 제목이 같으면 찾기가 모호해지므로 제목의 일부만 친다.)
    await tester.enterText(find.byType(TextField), '집');
    await tester.enterText(find.byType(TextField), '집 ');
    await tester.enterText(find.byType(TextField), '집 1');
    expect(repository.calls.length, 1);

    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(repository.calls.length, 2);
    expect(repository.calls.last['query'], '집 1');
    expect(find.text('모집 1'), findsOneWidget);
    expect(find.text('모집 2'), findsNothing);
  });

  testWidgets('X 버튼을 누르면 검색어가 지워지고 전체 목록으로 돌아온다', (tester) async {
    final repository = _BrowseRepository(
      all: [for (var i = 0; i < 3; i++) _recruit(i)],
    );
    final container = await _pumpFind(tester, repository);

    await tester.enterText(find.byType(TextField), '집 1');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(container.read(recruitFilterProvider).query, '집 1');

    // 입력이 있을 때만 생기는 지우기 버튼.
    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();

    expect(container.read(recruitFilterProvider).query, '');
    expect(repository.calls.last['query'], isNull);
    expect(find.text('모집 2'), findsOneWidget);
  });

  testWidgets('유형·기간대 필터는 서버에 그 키로 요청하고 지금 걸린 조건이 계속 보인다', (tester) async {
    final repository = _BrowseRepository(
      all: [
        _recruit(0, type: 'speed', minutes: 30),
        _recruit(1, type: 'quality', minutes: 4320),
      ],
    );
    final container = await _pumpFind(tester, repository);

    await tester.tap(_segment<RecruitTypeFilter>(AppStrings.battleTypeQuality));
    await tester.pumpAndSettle();
    expect(repository.calls.last['type'], 'quality');
    expect(container.read(recruitFilterProvider).type, RecruitTypeFilter.quality);

    await tester.tap(_segment<RecruitDurationBand>('며칠'));
    await tester.pumpAndSettle();
    expect(repository.calls.last['band'], 'multi');
    expect(repository.calls.last['type'], 'quality');

    // 조작 영역은 스크롤되지 않으므로 무엇이 걸려 있는지 목록을 보는 동안 계속 보인다.
    expect(_segment<RecruitTypeFilter>(AppStrings.battleTypeQuality), findsOneWidget);
    expect(_segment<RecruitDurationBand>('며칠'), findsOneWidget);
    expect(find.text('모집 1'), findsOneWidget);
    expect(find.text('모집 0'), findsNothing);
  });

  testWidgets('조건 지우기는 검색어와 두 축을 한 번에 되돌린다', (tester) async {
    final repository = _BrowseRepository(
      all: [for (var i = 0; i < 3; i++) _recruit(i)],
    );
    final container = await _pumpFind(tester, repository);

    // 조건이 없으면 이 버튼은 아예 없다.
    expect(find.text(AppStrings.battleFilterClear), findsNothing);

    await tester.enterText(find.byType(TextField), '집 1');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.tap(_segment<RecruitTypeFilter>(AppStrings.battleTypeSpeed));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, AppStrings.battleFilterClear));
    await tester.pumpAndSettle();

    expect(container.read(recruitFilterProvider).hasAnyCondition, isFalse);
    expect(find.text(AppStrings.battleFilterClear), findsNothing);
    expect(repository.calls.last['query'], isNull);
    expect(repository.calls.last['type'], isNull);
    expect(find.text('모집 2'), findsOneWidget);
  });

  testWidgets('모집이 하나도 없으면 내가 먼저 걸어 보라고 권한다', (tester) async {
    await _pumpFind(tester, _BrowseRepository());

    expect(find.text(AppStrings.battleRecruitsEmptyNone), findsOneWidget);
    expect(find.text(AppStrings.battleRecruitsEmptyNoneHint), findsOneWidget);
    expect(
      find.widgetWithText(FilledButton, AppStrings.battleCreate),
      findsOneWidget,
    );
  });

  testWidgets('조건 때문에 비었으면 조건을 지우라고 권하고 대결 만들기를 권하지 않는다', (tester) async {
    final repository = _BrowseRepository(all: [_recruit(0)]);
    await _pumpFind(tester, repository);

    await tester.enterText(find.byType(TextField), '없는 제목');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.battleRecruitsEmptyFiltered), findsOneWidget);
    expect(find.text(AppStrings.battleRecruitsEmptyFilteredHint), findsOneWidget);
    expect(
      find.widgetWithText(FilledButton, AppStrings.battleFilterClear),
      findsOneWidget,
    );
    // 사용자의 의도는 찾는 것이었다. 여기서 만들기를 권하지 않는다(FAB는 그대로 있다).
    expect(
      find.widgetWithText(FilledButton, AppStrings.battleCreate),
      findsNothing,
    );

    // 그 버튼으로 조건이 풀리고 목록이 돌아온다.
    await tester.tap(
      find.widgetWithText(FilledButton, AppStrings.battleFilterClear),
    );
    await tester.pumpAndSettle();
    expect(find.text('모집 0'), findsOneWidget);
  });

  testWidgets('첫 묶음을 못 불러오면 비었다고 하지 않고 다시 시도를 준다', (tester) async {
    await _pumpFind(tester, _BrowseRepository(failFirstPage: true));

    // 본문 안내와 토스트 양쪽에서 말한다.
    expect(find.text(AppStrings.battleLoadRecruitsFailed), findsWidgets);
    expect(find.text(AppStrings.battleRecruitsEmptyNone), findsNothing);
    expect(find.widgetWithText(TextButton, AppStrings.retry), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  // riverpod은 실패해도 직전 목록을 들고 있다. 그대로 그리면 "새 검색어 + 옛 결과"가 한 화면에
  // 보이고 사용자는 그걸 검색 결과로 읽는다. 실패는 토스트와 본문 양쪽에서 말해야 한다.
  testWidgets('조건을 바꾸다 실패하면 옛 결과를 결과처럼 보여 주지 않고 실패를 알린다', (tester) async {
    final repository = _BrowseRepository(
      all: [for (var i = 0; i < 3; i++) _recruit(i)],
    );
    await _pumpFind(tester, repository);
    expect(find.text('모집 0'), findsOneWidget);

    repository.failNext = Exception('network down');
    await tester.tap(_segment<RecruitTypeFilter>(AppStrings.battleTypeSpeed));
    await tester.pumpAndSettle();

    // 옛 목록이 결과인 척 남아 있지 않다.
    expect(find.text('모집 0'), findsNothing);
    expect(find.text(AppStrings.battleLoadRecruitsFailed), findsWidgets);
    expect(find.widgetWithText(TextButton, AppStrings.retry), findsOneWidget);
    // 빈 상태로 둘러대지도 않는다.
    expect(find.text(AppStrings.battleRecruitsEmptyFiltered), findsNothing);

    // 다시 시도하면 그 조건으로 목록이 돌아온다.
    await tester.tap(find.widgetWithText(TextButton, AppStrings.retry));
    await tester.pumpAndSettle();
    expect(repository.calls.last['type'], 'speed');
    expect(find.text('모집 0'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('당겨서 새로고침이 실패하면 그 사실을 알린다', (tester) async {
    final repository = _BrowseRepository(
      all: [for (var i = 0; i < 3; i++) _recruit(i)],
    );
    final container = await _pumpFind(tester, repository);

    repository.failNext = Exception('network down');
    final refreshed = container.refresh(openRecruitFeedProvider.future);
    await expectLater(refreshed, throwsA(isA<Exception>()));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.battleLoadRecruitsFailed), findsWidgets);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  // 실패 → 새로고침 → 다시 실패에서 두 번째 토스트가 묵살되면 사용자는 아무 신호도 받지 못한다.
  testWidgets('이어 불러오기가 두 번 실패하면 두 번 알린다', (tester) async {
    final repository = _BrowseRepository(
      all: [for (var i = 0; i < 45; i++) _recruit(i)],
    );
    final container = await _pumpFind(tester, repository);
    final notifier = container.read(openRecruitFeedProvider.notifier);

    repository.failNext = Exception('network down');
    await notifier.loadMore();
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.battleRecruitsLoadMoreFailed), findsWidgets);

    // 새로고침으로 실패 횟수가 0으로 돌아간 뒤 같은 실패를 다시 겪는다.
    final refreshed = container.refresh(openRecruitFeedProvider.future);
    await refreshed;
    await tester.pumpAndSettle();
    expect(container.read(openRecruitFeedProvider).value!.moreErrorCount, 0);
    ScaffoldMessenger.of(
      tester.element(find.byType(ListView)),
    ).removeCurrentSnackBar();
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.battleRecruitsLoadMoreFailed), findsNothing);

    repository.failNext = Exception('network down again');
    await container.read(openRecruitFeedProvider.notifier).loadMore();
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.battleRecruitsLoadMoreFailed), findsWidgets);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('이어 불러오는 중이면 목록 끝에 로더가 보인다', (tester) async {
    final repository = _BrowseRepository(
      all: [for (var i = 0; i < 45; i++) _recruit(i)],
    );
    final container = await _pumpFind(tester, repository);

    final gate = Completer<void>();
    repository.gate = gate;
    container.read(openRecruitFeedProvider.notifier).loadMore();
    await tester.pump();

    expect(container.read(openRecruitFeedProvider).value!.loadingMore, isTrue);

    gate.complete();
    await tester.pumpAndSettle();
    expect(container.read(openRecruitFeedProvider).value!.items.length, 40);
  });

  testWidgets('이어 불러오기가 실패하면 목록이 남고 꼬리에서 다시 시도할 수 있다', (tester) async {
    final repository = _BrowseRepository(
      all: [for (var i = 0; i < 45; i++) _recruit(i)],
    );
    final container = await _pumpFind(tester, repository);

    repository.failNext = Exception('network down');
    await container.read(openRecruitFeedProvider.notifier).loadMore();
    await tester.pumpAndSettle();

    // 이미 본 목록은 그대로다.
    expect(container.read(openRecruitFeedProvider).value!.items.length, 20);
    expect(find.text('모집 0'), findsOneWidget);
    // 실패를 토스트와 꼬리 양쪽에서 말한다.
    expect(find.text(AppStrings.battleRecruitsLoadMoreFailed), findsWidgets);

    // 꼬리의 다시 시도는 목록 맨 아래에 있어 아직 그려지지도 않았다.
    final retry = find.widgetWithText(TextButton, AppStrings.retry);
    await tester.scrollUntilVisible(
      retry,
      400,
      // 검색 입력(EditableText)도 Scrollable이라 목록 쪽을 집어 준다.
      scrollable: find.descendant(
        of: find.byType(ListView),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(retry);
    await tester.pumpAndSettle();

    expect(container.read(openRecruitFeedProvider).value!.items.length, 40);
    expect(container.read(openRecruitFeedProvider).value!.moreFailed, isFalse);
  });

  testWidgets('목록 끝까지 내리면 다음 묶음이 이어지고 더 없으면 멈춘다', (tester) async {
    final repository = _BrowseRepository(
      all: [for (var i = 0; i < 25; i++) _recruit(i)],
    );
    final container = await _pumpFind(tester, repository);
    expect(container.read(openRecruitFeedProvider).value!.items.length, 20);

    for (var i = 0; i < 12; i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pump();
      await tester.pumpAndSettle();
    }

    final feed = container.read(openRecruitFeedProvider).value!;
    expect(feed.items.length, 25);
    expect(feed.hasMore, isFalse);
    // 끝에 닿아도 같은 요청을 반복하지 않는다(첫 묶음 + 두 번째 묶음 두 번뿐이다).
    expect(repository.calls.length, 2);
  });

  testWidgets('이미 모집 중이면 목록 맨 앞에서 이유와 내 모집이 어디 있는지 알린다', (tester) async {
    final repository = _BrowseRepository(
      all: [_recruit(0)],
      hasPending: true,
    );
    final container = await _pumpFind(tester, repository);

    expect(find.text(AppStrings.battleMyRecruitBlocked), findsOneWidget);
    await tester.tap(find.text(AppStrings.battleMyRecruitGo));
    await tester.pumpAndSettle();

    expect(container.read(selectedTabProvider), AppTab.myBattles);
  });

  testWidgets('이미 모집 중이면 만들기 버튼이 사유를 알리고 생성 화면으로 보내지 않는다', (tester) async {
    final repository = _BrowseRepository(hasPending: true);
    await _pumpFind(tester, repository);

    await tester.tap(find.widgetWithText(FloatingActionButton, AppStrings.battleCreate));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.battleMyRecruitBlocked), findsWidgets);
    // 생성 화면으로 넘어가지 않았다(찾기 탭 앱바가 그대로다).
    expect(find.text(AppStrings.battleFind), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });
}
