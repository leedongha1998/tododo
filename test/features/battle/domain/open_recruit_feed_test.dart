import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:todododo/features/battle/data/battle.dart';
import 'package:todododo/features/battle/data/battle_repository.dart';
import 'package:todododo/features/battle/data/open_recruit.dart';
import 'package:todododo/features/battle/data/open_recruit_page.dart';
import 'package:todododo/features/battle/data/player_card.dart';
import 'package:todododo/features/battle/domain/battle_providers.dart';
import 'package:todododo/features/battle/domain/open_recruit_feed.dart';
import 'package:todododo/features/battle/domain/recruit_query.dart';

OpenRecruit _recruit(int index, {String type = 'speed'}) => OpenRecruit(
  battle: Battle(
    id: 'b$index',
    type: type,
    status: 'pending',
    title: index.isEven ? '설거지하기 $index' : '방 청소하기 $index',
    creatorId: 'creator$index',
    // 최신순이므로 index가 작을수록 최신이다.
    createdAt: DateTime(2026, 10, 28).subtract(Duration(minutes: index)),
    durationMinutes: 30,
    minCriteria: const ['싱크대가 비어 있다'],
  ),
  creator: PlayerCard(userId: 'creator$index', displayName: '도윤$index'),
);

/// 서버를 흉내 낸 가짜 repository. **걸러내기와 묶음 끊기를 이 안에서** 한다 —
/// 클라이언트가 받은 묶음을 다시 걸러내지 않는지 보려면 서버 쪽이 조건을 적용해야 한다.
class _FeedRepository implements BattleRepository {
  _FeedRepository(this.all);

  final List<OpenRecruit> all;
  final calls = <Map<String, Object?>>[];

  /// 다음 호출만 실패시킨다.
  Object? failNext;

  /// 다음 묶음이 이미 본 행 하나를 겹쳐 돌려준다(중복 방어를 보려고).
  bool overlapNextPage = false;

  @override
  Future<OpenRecruitPage> fetchOpenRecruits({
    int limit = openRecruitPageSize,
    RecruitCursor? cursor,
    String? query,
    String? type,
    String? durationBand,
  }) async {
    calls.add({
      'limit': limit,
      'cursor': cursor?.id,
      'query': query,
      'type': type,
      'band': durationBand,
    });
    final error = failNext;
    if (error != null) {
      failNext = null;
      throw error;
    }

    var items = all;
    if (query != null) {
      items = items
          .where((item) => item.battle.title.contains(query))
          .toList();
    }
    if (type != null) {
      items = items.where((item) => item.battle.type == type).toList();
    }
    var start = 0;
    if (cursor != null) {
      start =
          items.indexWhere((item) => item.battle.id == cursor.id) +
          (overlapNextPage ? 0 : 1);
      overlapNextPage = false;
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

ProviderContainer _containerWith(_FeedRepository repository) {
  final container = ProviderContainer(
    overrides: [battleRepositoryProvider.overrideWithValue(repository)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('첫 묶음은 20건이고 더 있을 수 있다고 본다', () async {
    final repository = _FeedRepository([
      for (var i = 0; i < 45; i++) _recruit(i),
    ]);
    final container = _containerWith(repository);

    final feed = await container.read(openRecruitFeedProvider.future);

    expect(feed.items.length, openRecruitPageSize);
    expect(feed.items.first.battle.id, 'b0');
    expect(feed.hasMore, isTrue);
    expect(repository.calls.single['cursor'], isNull);
  });

  test('이어 불러오면 뒤에 붙고, 끝에 닿으면 같은 요청을 반복하지 않는다', () async {
    final repository = _FeedRepository([
      for (var i = 0; i < 45; i++) _recruit(i),
    ]);
    final container = _containerWith(repository);
    await container.read(openRecruitFeedProvider.future);
    final notifier = container.read(openRecruitFeedProvider.notifier);

    await notifier.loadMore();
    expect(container.read(openRecruitFeedProvider).value!.items.length, 40);
    // 두 번째 묶음은 첫 묶음의 마지막 행 커서에서 이어진다.
    expect(repository.calls.last['cursor'], 'b19');

    await notifier.loadMore();
    final feed = container.read(openRecruitFeedProvider).value!;
    expect(feed.items.length, 45);
    expect(feed.hasMore, isFalse);

    // 더 받을 것이 없으면 부르지 않는다.
    final callsBefore = repository.calls.length;
    await notifier.loadMore();
    expect(repository.calls.length, callsBefore);
  });

  test('받은 묶음에 이미 본 행이 섞여 와도 같은 모집이 두 번 들어가지 않는다', () async {
    final repository = _FeedRepository([
      for (var i = 0; i < 45; i++) _recruit(i),
    ]);
    final container = _containerWith(repository);
    await container.read(openRecruitFeedProvider.future);

    repository.overlapNextPage = true;
    await container.read(openRecruitFeedProvider.notifier).loadMore();

    final ids = container
        .read(openRecruitFeedProvider)
        .value!
        .items
        .map((item) => item.battle.id)
        .toList();
    expect(ids.length, ids.toSet().length);
  });

  test('이어 불러오기가 실패해도 이미 본 목록이 사라지지 않고 다시 시도할 수 있다', () async {
    final repository = _FeedRepository([
      for (var i = 0; i < 45; i++) _recruit(i),
    ]);
    final container = _containerWith(repository);
    await container.read(openRecruitFeedProvider.future);
    final notifier = container.read(openRecruitFeedProvider.notifier);

    repository.failNext = Exception('network down');
    await notifier.loadMore();

    final failed = container.read(openRecruitFeedProvider);
    // AsyncError로 떨어지면 이미 본 목록이 통째로 사라진다. 그게 가장 나쁜 결과다.
    expect(failed.hasError, isFalse);
    expect(failed.value!.items.length, openRecruitPageSize);
    expect(failed.value!.moreFailed, isTrue);
    expect(failed.value!.moreErrorCount, 1);
    expect(failed.value!.hasMore, isTrue);

    // 같은 커서로 다시 부른다.
    await notifier.loadMore();
    final retried = container.read(openRecruitFeedProvider).value!;
    expect(retried.items.length, 40);
    expect(retried.moreFailed, isFalse);
  });

  test('조건이 바뀌면 커서를 버리고 첫 묶음부터 다시 시작한다', () async {
    final repository = _FeedRepository([
      for (var i = 0; i < 45; i++) _recruit(i),
    ]);
    final container = _containerWith(repository);
    await container.read(openRecruitFeedProvider.future);
    await container.read(openRecruitFeedProvider.notifier).loadMore();
    expect(container.read(openRecruitFeedProvider).value!.items.length, 40);

    container.read(recruitFilterProvider.notifier).setQuery('방 청소');
    final filtered = await container.read(openRecruitFeedProvider.future);

    // 걸러내는 일은 서버가 한다. 커서 없이 첫 묶음부터 받는다.
    expect(repository.calls.last['query'], '방 청소');
    expect(repository.calls.last['cursor'], isNull);
    expect(filtered.items.every((item) => item.battle.title.contains('방 청소')), isTrue);
  });

  // 조작 영역은 목록 끝까지 내린 상태에서도 바로 누를 수 있다. 그래서 "첫 묶음을 다시 받는 중에
  // 꼬리가 또 빌드돼 loadMore가 걸리는" 순서가 실제로 일어난다. 그때 옛 커서로 받은 묶음이
  // 새 첫 묶음 뒤에 붙으면 목록 중간이 통째로 빠진다.
  test('조건이 바뀌는 사이에 걸린 이어 불러오기가 새 목록을 오염시키지 않는다', () async {
    final repository = _FeedRepository([
      for (var i = 0; i < 60; i++) _recruit(i),
    ]);
    final container = _containerWith(repository);
    // autoDispose라 듣는 쪽이 없으면 상태가 버려진다. 조건 변경 뒤의 상태를 보려면 먼저 듣는다.
    container.listen(openRecruitFeedProvider, (previous, next) {});
    await container.read(openRecruitFeedProvider.future);
    final notifier = container.read(openRecruitFeedProvider.notifier);
    await notifier.loadMore();
    expect(container.read(openRecruitFeedProvider).value!.items.length, 40);

    // 기간대만 바꾼다(가짜 서버는 기간대를 걸러내지 않으므로 집합은 그대로다 —
    // 오염이 일어났다면 건수로 바로 드러난다).
    container.read(recruitFilterProvider.notifier).setBand(RecruitDurationBand.quick);
    final intruder = notifier.loadMore();
    final rebuilt = await container.read(openRecruitFeedProvider.future);
    await intruder;

    final feed = container.read(openRecruitFeedProvider).value!;
    expect(feed.items.length, openRecruitPageSize);
    expect(
      feed.items.map((item) => item.battle.id),
      rebuilt.items.map((item) => item.battle.id),
    );
    // 커서도 새 묶음의 마지막 행에 머문다(b59로 뛰면 b20~b39가 영영 안 나온다).
    expect(feed.cursor!.id, 'b19');
    expect(feed.query.band, RecruitDurationBand.quick);
    // 옛 커서로는 아예 부르지 않는다.
    expect(repository.calls.where((call) => call['cursor'] == 'b39'), isEmpty);
  });

  test('검색어를 지우면 전체 목록으로 돌아온다', () async {
    final repository = _FeedRepository([
      for (var i = 0; i < 5; i++) _recruit(i),
    ]);
    final container = _containerWith(repository);
    container.read(recruitFilterProvider.notifier).setQuery('방 청소');
    await container.read(openRecruitFeedProvider.future);

    container.read(recruitFilterProvider.notifier).setQuery('');
    final all = await container.read(openRecruitFeedProvider.future);

    expect(repository.calls.last['query'], isNull);
    expect(all.items.length, 5);
  });

  test('유형·기간대 조건이 서버 인자로 그대로 간다', () async {
    final repository = _FeedRepository([
      for (var i = 0; i < 5; i++) _recruit(i, type: i.isEven ? 'speed' : 'quality'),
    ]);
    final container = _containerWith(repository);
    container.read(recruitFilterProvider.notifier).setType(RecruitTypeFilter.quality);
    container.read(recruitFilterProvider.notifier).setBand(RecruitDurationBand.quick);

    final feed = await container.read(openRecruitFeedProvider.future);

    expect(repository.calls.last['type'], 'quality');
    expect(repository.calls.last['band'], 'quick');
    expect(feed.items.every((item) => item.battle.type == 'quality'), isTrue);
  });

  test('같은 조건을 다시 적용하면 다시 읽지 않는다', () async {
    final repository = _FeedRepository([_recruit(0)]);
    final container = _containerWith(repository);
    await container.read(openRecruitFeedProvider.future);
    final notifier = container.read(recruitFilterProvider.notifier);

    // 한글 IME는 자모 조합 중에도 같은 글자를 여러 번 쏜다.
    notifier.setQuery('설거지');
    await container.read(openRecruitFeedProvider.future);
    final callsAfterFirst = repository.calls.length;
    notifier.setQuery('설거지');
    notifier.setQuery('  설거지  ');
    notifier.setType(RecruitTypeFilter.all);
    await container.read(openRecruitFeedProvider.future);

    expect(repository.calls.length, callsAfterFirst);
  });
}
