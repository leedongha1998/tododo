import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/open_recruit.dart';
import '../data/open_recruit_page.dart';
import 'battle_providers.dart';
import 'recruit_query.dart';

/// 지금까지 받은 모집 묶음들. 화면은 이 상태를 **표시만** 한다.
@immutable
class RecruitFeed {
  const RecruitFeed({
    required this.query,
    required this.items,
    this.cursor,
    this.hasMore = false,
    this.loadingMore = false,
    this.moreFailed = false,
    this.moreErrorCount = 0,
  });

  /// 이 목록(과 커서)을 받을 때 적용됐던 조건. 지금 적용된 조건과 다르면 이 목록은 곧 버려질
  /// **옛 조건의 것**이므로 그 커서로 다음 묶음을 이어 붙이면 안 된다(`loadMore`의 가드).
  final RecruitQuery query;

  /// 받은 순서(서버의 최신순) 그대로. 클라이언트가 다시 걸러내거나 정렬하지 않는다.
  final List<OpenRecruit> items;

  /// 마지막으로 받은 행의 커서. 다음 묶음은 여기서부터다.
  final RecruitCursor? cursor;
  final bool hasMore;
  final bool loadingMore;

  /// 가장 최근의 이어 불러오기가 실패한 상태인지. 목록 꼬리에 `다시 시도`를 띄우고,
  /// 스크롤이 끝에 닿을 때마다 자동으로 다시 부르는 것을 막는다(실패를 무한히 되풀이하지 않는다).
  final bool moreFailed;

  /// 이어 불러오기가 실패한 횟수. 화면이 이 값의 증가를 보고 토스트를 한 번 띄운다
  /// (notifier에서 직접 스낵바를 띄울 수 없어 신호를 상태에 둔다).
  final int moreErrorCount;

  RecruitFeed copyWith({
    List<OpenRecruit>? items,
    RecruitCursor? cursor,
    bool? hasMore,
    bool? loadingMore,
    bool? moreFailed,
    int? moreErrorCount,
  }) {
    return RecruitFeed(
      // 조건은 `build()`만 정한다. 묶음을 이어 붙이며 바뀌지 않는다.
      query: query,
      items: items ?? this.items,
      cursor: cursor ?? this.cursor,
      hasMore: hasMore ?? this.hasMore,
      loadingMore: loadingMore ?? this.loadingMore,
      moreFailed: moreFailed ?? this.moreFailed,
      moreErrorCount: moreErrorCount ?? this.moreErrorCount,
    );
  }
}

/// 적용된 검색·필터 조건. 입력 중인 글자는 화면 State가 들고 있고 여기엔 들어오지 않는다.
class RecruitFilter extends Notifier<RecruitQuery> {
  @override
  RecruitQuery build() => const RecruitQuery();

  /// 같은 조건이면 아무것도 하지 않는다. 한글 IME는 자모를 조합하는 동안에도 입력 이벤트를
  /// 쏘므로(한 글자에 두세 번) 이 비교가 피드 재조회를 한 번으로 줄인다.
  void setQuery(String text) {
    final trimmed = text.trim();
    if (trimmed == state.query) return;
    state = state.copyWith(query: trimmed);
  }

  void setType(RecruitTypeFilter type) {
    if (type == state.type) return;
    state = state.copyWith(type: type);
  }

  void setBand(RecruitDurationBand band) {
    if (band == state.band) return;
    state = state.copyWith(band: band);
  }

  /// 검색어와 두 축을 한 번에 되돌린다.
  void reset() {
    if (!state.hasAnyCondition) return;
    state = const RecruitQuery();
  }
}

final recruitFilterProvider =
    NotifierProvider.autoDispose<RecruitFilter, RecruitQuery>(
      RecruitFilter.new,
    );

/// 남이 올린 모집 피드. 조건이 바뀌면 `build()`가 다시 돌아 **첫 묶음부터** 시작한다.
class OpenRecruitFeed extends AsyncNotifier<RecruitFeed> {
  /// 무효화·조건 변경으로 `build()`가 다시 돌 때마다 올라간다.
  /// `AsyncNotifier`는 무효화돼도 같은 인스턴스에서 `build()`만 다시 돌므로, 그 사이에 날아간
  /// 옛 `loadMore()` 응답이 새 목록을 덮지 않게 이 번호로 막는다.
  int _generation = 0;

  @override
  Future<RecruitFeed> build() async {
    final query = ref.watch(recruitFilterProvider);
    _generation++;
    final page = await _fetch(query, null);
    return RecruitFeed(
      query: query,
      items: page.items,
      cursor: page.nextCursor,
      hasMore: page.hasMore,
    );
  }

  /// 다음 묶음을 뒤에 붙인다. 이미 받는 중이거나 더 받을 것이 없으면 아무것도 하지 않는다.
  Future<void> loadMore() async {
    // 첫 묶음을 다시 받는 중(조건 변경·당겨서 새로고침)이면 끼어들지 않는다.
    // 그 사이에도 riverpod이 이전 목록을 그대로 보여 주므로 꼬리가 다시 빌드되며 여기까지 온다.
    if (state.isLoading) return;

    final current = state.value;
    if (current == null || current.loadingMore || !current.hasMore) return;

    final query = ref.read(recruitFilterProvider);
    // 지금 들고 있는 목록이 옛 조건의 것이면 그 커서로 이어 붙이면 안 된다 —
    // 새 조건의 첫 묶음 뒤에 옛 커서 다음 묶음이 붙어 **목록 중간이 통째로 빠진다.**
    if (current.query != query) return;

    final cursor = current.cursor;
    if (cursor == null) return;

    final generation = _generation;
    state = AsyncData(
      current.copyWith(loadingMore: true, moreFailed: false),
    );

    try {
      final page = await _fetch(query, cursor);
      final latest = state.value;
      if (latest == null || _isStale(generation, query, latest)) return;
      // 커서 페이징이라 중복은 구조적으로 생기지 않지만, 위 가드의 두 번째 겹으로 id를 본다.
      final seen = latest.items.map((item) => item.battle.id).toSet();
      final merged = [
        ...latest.items,
        ...page.items.where((item) => seen.add(item.battle.id)),
      ];
      state = AsyncData(
        latest.copyWith(
          items: merged,
          cursor: page.nextCursor ?? latest.cursor,
          hasMore: page.hasMore,
          loadingMore: false,
          moreFailed: false,
        ),
      );
    } catch (error) {
      // 이어 불러오기 실패에 AsyncError를 쓰지 않는다. error 갈래로 떨어지면 이미 본 목록이
      // 통째로 사라지는데, 그것이 가장 나쁜 결과다. 목록·커서를 그대로 두고 신호만 올린다.
      debugPrint('list_open_recruits (load more) failed: $error');
      final latest = state.value;
      if (latest == null || _isStale(generation, query, latest)) return;
      state = AsyncData(
        latest.copyWith(
          loadingMore: false,
          moreFailed: true,
          moreErrorCount: latest.moreErrorCount + 1,
        ),
      );
    }
  }

  /// 받는 사이에 이 응답이 쓸모를 잃었는지. 세 가지를 본다.
  ///   - `build()`가 다시 돌았다(무효화·당겨서 새로고침): 세대 번호가 다르다
  ///   - 지금 상태가 다른 조건으로 만들어졌다: 상태의 조건이 다르다
  ///   - 응답을 기다리는 사이에 조건이 바뀌었다(아직 새 묶음이 안 왔을 수도 있다)
  bool _isStale(int generation, RecruitQuery query, RecruitFeed latest) {
    return generation != _generation ||
        latest.query != query ||
        query != ref.read(recruitFilterProvider);
  }

  Future<OpenRecruitPage> _fetch(RecruitQuery query, RecruitCursor? cursor) {
    return ref.read(battleRepositoryProvider).fetchOpenRecruits(
      limit: openRecruitPageSize,
      cursor: cursor,
      query: query.serverQuery,
      type: query.type.serverValue,
      durationBand: query.band.serverValue,
    );
  }
}

final openRecruitFeedProvider =
    AsyncNotifierProvider.autoDispose<OpenRecruitFeed, RecruitFeed>(
      OpenRecruitFeed.new,
    );
