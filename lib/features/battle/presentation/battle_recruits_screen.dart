import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/navigation/app_tab.dart';
import '../../../core/push/push_providers.dart';
import '../../../core/strings.dart';
import '../../../core/theme/pixel_icons.dart';
import '../../../core/theme/retro_palette.dart';
import '../../../core/widgets/pixel_frame.dart';
import '../../../core/widgets/pixel_icon.dart';
import '../../../core/widgets/pixel_tag.dart';
import '../../../core/widgets/status_message.dart';
import '../../auth/domain/auth_providers.dart';
import '../../profile/domain/profile_providers.dart';
import '../data/open_recruit.dart';
import '../domain/battle_providers.dart';
import '../domain/open_recruit_feed.dart';
import '../domain/recruit_query.dart';
import 'ai_consent_screen.dart';
import 'battle_chips.dart';
import 'create_battle_screen.dart';
import 'recruit_detail_sheet.dart';
import 'vs_intro.dart';

/// 검색어 입력이 멈춘 뒤 조건을 적용하기까지 기다리는 시간.
/// 글자마다 서버를 부르지 않기 위한 것이고, 키보드 검색 버튼·`X`는 기다리지 않고 즉시 적용한다.
const _searchDebounce = Duration(milliseconds: 300);

/// 끝에서 몇 번째 카드가 그려질 때 다음 묶음을 예약할지. 카드 높이가 제목·기준 길이에 따라
/// 달라 픽셀 기준 임계값이 불안정하므로 스크롤 리스너 대신 항목 위치로 판단한다.
const _loadMoreLookahead = 3;

/// `대결 찾기` 탭. **남이 올린 모집만** 있는 하나의 목록이다.
/// 검색·유형·기간대·정렬·묶음 끊기는 전부 서버가 하고, 이 화면은 조건을 만들어 보내고 받은 묶음을 그린다.
/// 내가 등록한 모집은 `내 대결` 탭의 구역으로 옮겼다.
class BattleRecruitsScreen extends ConsumerStatefulWidget {
  const BattleRecruitsScreen({super.key});

  @override
  ConsumerState<BattleRecruitsScreen> createState() =>
      _BattleRecruitsScreenState();
}

class _BattleRecruitsScreenState extends ConsumerState<BattleRecruitsScreen> {
  // 입력 중인 글자는 provider에 넣지 않는다. 글자마다 피드가 다시 돌면 안 된다.
  final _searchController = TextEditingController();
  Timer? _debounce;

  /// 목록을 아래로 내리는 동안 만들기 버튼을 치운다(카드를 가리지 않게). 멈추거나 위로 올리면 돌아온다.
  bool _hideFab = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _showSnackBar(String message, {SnackBarAction? action}) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message), action: action));
  }

  void _goToMyBattles() =>
      ref.read(selectedTabProvider.notifier).select(AppTab.myBattles);

  void _onSearchChanged(String text) {
    // suffix의 `X` 버튼이 입력 유무에 따라 생겼다 사라지므로 글자마다 다시 그린다(조회는 하지 않는다).
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(_searchDebounce, () {
      ref.read(recruitFilterProvider.notifier).setQuery(text);
    });
  }

  void _applySearchNow(String text) {
    _debounce?.cancel();
    ref.read(recruitFilterProvider.notifier).setQuery(text);
    FocusScope.of(context).unfocus();
  }

  void _clearSearch() {
    _debounce?.cancel();
    _searchController.clear();
    setState(() {});
    ref.read(recruitFilterProvider.notifier).setQuery('');
  }

  void _clearConditions() {
    _debounce?.cancel();
    _searchController.clear();
    setState(() {});
    ref.read(recruitFilterProvider.notifier).reset();
  }

  // 대결을 만들기 전에도 동의를 받는다. 제목과 기준이 AI로 넘어가기 때문이다(3단계 기준 생성).
  Future<void> _openCreate(BuildContext context) async {
    // 찾기 탭에는 더 이상 내 모집이 보이지 않으므로, 막힌 이유와 그것이 어디 있는지를 이 자리에서 말한다.
    if (ref.read(myLimitsProvider).value?.hasPending ?? false) {
      _showSnackBar(
        AppStrings.battleMyRecruitBlocked,
        action: SnackBarAction(
          label: AppStrings.battleMyRecruitGo,
          onPressed: _goToMyBattles,
        ),
      );
      return;
    }
    if (!await ensureAiConsent(context, ref)) return;
    if (!context.mounted) return;
    final created = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const CreateBattleScreen()));
    // 모집을 올린 것도 "첫 대결이 생겼다"에 든다 — 누군가 참가하면 알릴 일이 생긴다.
    if (created == true) await _askNotificationPermission();
  }

  /// 카드 → 모집 상세 시트. 참가는 시트가 하고, 성공하면 여기서 뒷정리를 이어 간다.
  /// 순서: 시트 닫힘 → 목록 갱신 → VS 인트로 → 성공 토스트 → 내 대결 탭.
  Future<void> _openRecruit(BuildContext context, OpenRecruit recruit) async {
    final joined = await showRecruitSheet(context, recruit);
    if (joined == null || !context.mounted) return;

    // 참가한 모집은 사라졌어야 한다. 곧 내 대결 탭으로 가므로 첫 묶음으로 되감겨도 잃는 것이 없다.
    ref.invalidate(openRecruitFeedProvider);
    ref.invalidate(myBattlesProvider);
    ref.invalidate(myLimitsProvider);

    // 인트로가 끝난 뒤에 토스트를 띄워 인트로가 토스트를 가리지 않는다.
    // 서버가 방금 active로 바꿨으므로 status는 active로 판단한다.
    final userId = ref.read(authRepositoryProvider).currentUser?.id;
    if (userId != null) {
      final myName = await _myNameForIntro();
      if (!context.mounted) return;
      await maybeShowVsIntro(
        context,
        store: ref.read(vsIntroSeenStoreProvider),
        userId: userId,
        battleId: joined.battle.id,
        status: 'active',
        myName: myName,
        opponentName: joined.creator.displayName,
      );
    }
    if (!context.mounted) return;
    _showSnackBar(AppStrings.battleJoined);
    _goToMyBattles();
    await _askNotificationPermission();
  }

  /// 알림 권한을 묻는 두 자리(첫 참가·첫 모집 등록)가 공유한다. 아직 묻지 않았을 때만 뜬다.
  /// 연출·토스트·탭 이동을 모두 마친 **뒤**에 불러 시스템 다이얼로그가 그것들을 가리지 않게 한다.
  /// 묻지 못해도 알리지 않는다 — 알림은 관문이 아니다.
  Future<void> _askNotificationPermission() async {
    try {
      await ref.read(pushServiceProvider).ensureNotificationPermissionAfterFirstBattle();
    } catch (error) {
      debugPrint('notification permission request skipped: $error');
    }
  }

  // 내 표시 이름을 못 읽어도 인트로는 "나"로 띄운다. 장식이라 실패를 알리지 않는다.
  Future<String> _myNameForIntro() async {
    try {
      final profile = await ref.read(myProfileProvider.future);
      return profile.displayName;
    } catch (e) {
      debugPrint('myProfileProvider for vs intro failed: $e');
      return AppStrings.battleMe;
    }
  }

  @override
  Widget build(BuildContext context) {
    final feedAsync = ref.watch(openRecruitFeedProvider);
    final filter = ref.watch(recruitFilterProvider);
    // 한도는 서버가 내준 같은 응답(`get_my_limits`)에서 둘 다 읽는다 — 추가 조회가 없다.
    // 차단은 서버가 하고 여기서는 "지금 참가할 수 있는 몸인가"를 미리 알려 줄 뿐이다.
    final limits = ref.watch(myLimitsProvider).value;
    final hasPending = limits?.hasPending ?? false;
    final dailyBattleUsed = limits?.dailyBattleUsed ?? false;

    // 실패는 삼키지 않는다. 두 가지를 구분해 한 번씩만 말한다.
    //   - 목록을 다시 읽다 실패(첫 묶음·조건 변경·당겨서 새로고침): riverpod이 이전 목록을 들고 있어
    //     값만 보면 성공처럼 보인다. hasError가 켜지는 순간을 잡는다.
    //   - 이어 불러오기 실패: 목록을 지우지 않고 신호(moreErrorCount)만 올라온다.
    // 직전 값과 비교하므로 "실패 → 새로고침 → 다시 실패"에서도 두 번 말한다.
    ref.listen(openRecruitFeedProvider, (previous, next) {
      if (next.hasError && previous?.hasError != true) {
        debugPrint('openRecruitFeedProvider failed: ${next.error}');
        _showSnackBar(AppStrings.battleLoadRecruitsFailed);
        return;
      }
      final before = previous?.value?.moreErrorCount ?? 0;
      final after = next.value?.moreErrorCount ?? 0;
      if (after > before) _showSnackBar(AppStrings.battleRecruitsLoadMoreFailed);
    });

    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.battleFind)),
      // 마음에 드는 모집이 없을 때의 다음 행동이 "내가 만든다"이고, 그 판단은 목록을 보는 자리에서 나온다.
      // 라벨을 뗀 아이콘 전용(56x56)이다 — 글자까지 둔 버튼이 카드 오른쪽 절반을 덮었다.
      // 이름은 tooltip과 빈 상태의 글자 버튼이 말한다.
      // Scaffold 기본값은 FAB이 생기고 사라질 때 200ms 동안 돌면서 커지는 연출을 넣는다.
      // design.md 1.4 "움직임"이 연속 곡선을 금지하므로 즉시 교체로 바꾼다.
      floatingActionButtonAnimator: FloatingActionButtonAnimator.noAnimation,
      floatingActionButton: _hideFab
          ? null
          : FloatingActionButton(
              onPressed: () => _openCreate(context),
              tooltip: AppStrings.battleCreate,
              child: const PixelIcon(PixelIcons.battle),
            ),
      body: Column(
        children: [
          _buildControls(context, filter),
          // 고정 조작 영역과 목록을 가르는 "용기 경계". 카드 테두리(2dp)와 역할을 가르려고
          // 창·앱바와 같은 4dp를 쓴다(design.md 1.4: 2dp = 요소, 4dp = 창).
          const SizedBox(
            height: 4,
            width: double.infinity,
            child: ColoredBox(color: RetroPalette.ink),
          ),
          Expanded(
            // 목록을 내리는 동안 만들기 버튼을 감춘다. 애니메이션 없이 즉시 교체한다
            // (design.md 1.4 "움직임"이 연속 곡선을 금지한다).
            child: NotificationListener<ScrollNotification>(
              onNotification: _onScrollNotification,
              child: _buildFeed(
                context,
                feedAsync,
                filter,
                hasPending: hasPending,
                dailyBattleUsed: dailyBattleUsed,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 아래로 내리는 동안에만 FAB을 감춘다. 멈춤(idle)·위로 올림(forward)은 즉시 되돌린다 —
  /// 당겨서 새로고침도 forward 신호를 보내므로 그때도 버튼이 돌아온다.
  /// `ScrollController` 리스너는 오프셋이 변할 때만 불려 "멈췄다"를 놓치므로 알림을 본다.
  /// 알림은 그대로 흘려보낸다(false) — 바깥 `RefreshIndicator`가 같은 알림을 쓴다.
  bool _onScrollNotification(ScrollNotification notification) {
    if (notification is UserScrollNotification) {
      final hide = notification.direction == ScrollDirection.reverse;
      if (hide != _hideFab) setState(() => _hideFab = hide);
    }
    return false;
  }

  /// 고정 조작 영역. 스크롤되지 않으므로 지금 어떤 조건이 걸려 있는지가 목록을 보는 동안 계속 보인다.
  ///
  /// 면은 `sunken`이다 — 화면이 "가라앉은 조작판(sunken) → 종이 목록(paper) → 떠 있는 카드(surface)"
  /// 세 겹으로 갈려, 목록이 이 아래로 잘려 들어가는 모습이 고장이 아니라 스크롤로 읽힌다.
  /// 목록 배경을 `sunken`으로 바꾸는 쪽은 쓸 수 없다(기간 칩의 면색이라 칩이 묻힌다).
  Widget _buildControls(BuildContext context, RecruitQuery filter) {
    final notifier = ref.read(recruitFilterProvider.notifier);

    return ColoredBox(
      color: RetroPalette.sunken,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: AppStrings.battleSearchHint,
                prefixIcon: const Padding(
                  padding: EdgeInsets.all(12),
                  child: PixelIcon(PixelIcons.search, size: 24),
                ),
                prefixIconConstraints: const BoxConstraints(),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: _clearSearch,
                        icon: const PixelIcon(PixelIcons.close, size: 24),
                      ),
              ),
              onChanged: _onSearchChanged,
              onSubmitted: _applySearchNow,
            ),
            const SizedBox(height: 8),
            // 테마가 selectedIcon(체크)을 주므로 끄지 않으면 라벨 폭을 먹어 글자가 잘린다.
            SegmentedButton<RecruitTypeFilter>(
              showSelectedIcon: false,
              segments: [
                for (final type in RecruitTypeFilter.values)
                  ButtonSegment(value: type, label: Text(type.label)),
              ],
              selected: {filter.type},
              onSelectionChanged: (selection) =>
                  notifier.setType(selection.first),
            ),
            const SizedBox(height: 8),
            // 기간대 구간의 분 경계는 서버만 안다. 여기서 보내는 것은 키와 라벨뿐이다.
            SegmentedButton<RecruitDurationBand>(
              showSelectedIcon: false,
              segments: [
                for (final band in RecruitDurationBand.values)
                  ButtonSegment(value: band, label: Text(band.label)),
              ],
              selected: {filter.band},
              onSelectionChanged: (selection) =>
                  notifier.setBand(selection.first),
            ),
            // 조건이 걸려 있을 때만 보인다. 검색어와 두 축을 한 번에 되돌린다.
            if (filter.hasAnyCondition)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _clearConditions,
                  icon: const PixelIcon(PixelIcons.close, size: 12),
                  label: const Text(AppStrings.battleFilterClear),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeed(
    BuildContext context,
    AsyncValue<RecruitFeed> feedAsync,
    RecruitQuery filter, {
    required bool hasPending,
    required bool dailyBattleUsed,
  }) {
    final feed = feedAsync.value;
    final items = feed?.items ?? const <OpenRecruit>[];

    final Widget? body;
    // 이전 목록이 남아 있어도 실패를 숨기지 않는다. riverpod은 실패해도 직전 값을 들고 있어서
    // 그대로 그리면 **새 검색어와 옛 결과가 한 화면에** 보이고 사용자는 그걸 검색 결과로 읽는다.
    // (이어 불러오기 실패는 AsyncError가 아니라 목록을 지키므로 이 갈래로 오지 않는다.)
    if (feedAsync.hasError) {
      body = StatusMessage.error(
        message: AppStrings.battleLoadRecruitsFailed,
        action: TextButton(
          onPressed: () => ref.invalidate(openRecruitFeedProvider),
          child: const Text(AppStrings.retry),
        ),
      );
    } else if (feed == null) {
      // 첫 진입(이전 값 없음)에서만 전체 로더가 보인다. 조건을 바꾸는 동안에는 이전 목록을 둔다.
      body = const StatusMessage.loading();
    } else {
      body = switch (recruitEmptyKind(
        hasItems: items.isNotEmpty,
        hasAnyCondition: filter.hasAnyCondition,
      )) {
        RecruitEmptyKind.none => null,
        // 올라온 모집이 없다 → 내가 먼저 걸어 보라고 권한다. 단 이미 모집 중이면 막힌 버튼을 권하지 않는다.
        RecruitEmptyKind.noRecruits => StatusMessage.empty(
          icon: PixelIcons.battle,
          message: AppStrings.battleRecruitsEmptyNone,
          detail: AppStrings.battleRecruitsEmptyNoneHint,
          action: hasPending
              ? TextButton(
                  onPressed: _goToMyBattles,
                  child: const Text(AppStrings.battleMyRecruitGo),
                )
              : FilledButton(
                  onPressed: () => _openCreate(context),
                  child: const Text(AppStrings.battleCreate),
                ),
        ),
        // 조건 때문에 비었다 → 조건을 되돌리는 것이 먼저다. 여기서 대결 만들기를 권하지 않는다.
        RecruitEmptyKind.noMatches => StatusMessage.empty(
          icon: PixelIcons.search,
          message: AppStrings.battleRecruitsEmptyFiltered,
          detail: AppStrings.battleRecruitsEmptyFilteredHint,
          action: FilledButton(
            onPressed: _clearConditions,
            child: const Text(AppStrings.battleFilterClear),
          ),
        ),
      };
    }

    // 오늘 한도를 다 썼어도 배너를 띄운다. "참가 실패" 토스트로 처음 알게 되지 않도록
    // 목록을 훑기 전에 말해 준다. 카드 탭·시트 열기는 막지 않는다 — 기준 구경은 한도와 무관하다.
    final hasBanner = hasPending || dailyBattleUsed;
    final headCount = hasBanner ? 1 : 0;
    // 카드가 없을 때는 안내 문구 한 칸이 본문을 대신한다.
    final bodyCount = body != null ? 1 : items.length;
    // 목록이 아니라 안내 한 칸을 그리고 있으면 꼬리(이어 불러오기 상태)는 뜻이 없다.
    final tail = body == null ? _buildTail(feed) : null;
    final tailCount = tail != null ? 1 : 0;

    return RefreshIndicator(
      // 새로고침하면 목록은 처음 묶음부터 다시 시작한다. 배너·FAB 분기가 보는 한도도 함께 읽는다.
      onRefresh: () async {
        ref.invalidate(myLimitsProvider);
        final refreshed = ref.refresh(openRecruitFeedProvider.future);
        try {
          await refreshed;
        } catch (error) {
          // 여기서 다시 던지면 당겨서 새로고침 제스처가 그대로 터진다. 사용자에게 알리는 일은
          // 위 ref.listen(토스트)과 본문의 실패 안내가 맡는다 — 삼키지 않는다.
          debugPrint('openRecruitFeedProvider refresh failed: $error');
        }
      },
      child: ListView.builder(
        // 목록이 비었을 때야말로 새로고침이 필요하므로 짧아도 항상 당겨지게 한다.
        physics: const AlwaysScrollableScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        // 아래 여백은 만들기 버튼(FAB)이 마지막 카드를 가리지 않게 하려는 것이다.
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        itemCount: headCount + bodyCount + tailCount,
        itemBuilder: (context, index) {
          if (hasBanner && index == 0) {
            return _buildLimitBanner(
              hasPending: hasPending,
              dailyBattleUsed: dailyBattleUsed,
            );
          }
          final slot = index - headCount;
          if (slot < bodyCount) {
            if (body != null) return body;
            _maybeLoadMore(feed!, slot, items.length);
            return Padding(
              // 카드 사이는 카드 **안쪽** 간격(8/12dp)보다 넓어야 카드가 한 덩어리로 묶이지 않는다.
              // 카드 면(surface)과 목록 배경(paper)의 대비가 1.13:1이라 여백이 테두리와 함께
              // 둘뿐인 구분 수단이다. 이 목록 카드 한 곳의 값이다(전역 기본값은 8dp 그대로).
              padding: const EdgeInsets.only(bottom: 16),
              child: _OpenRecruitCard(
                recruit: items[slot],
                onTap: () => _openRecruit(context, items[slot]),
              ),
            );
          }
          return tail!;
        },
      ),
    );
  }

  /// 목록 맨 앞의 한도 안내. 두 가지를 말한다.
  ///   - 오늘 대결을 이미 했다 → 참가 자체가 내일까지 막힌다. 갈 곳이 없으므로 버튼을 달지 않는다.
  ///   - 이미 모집 중이다 → 새로 올릴 수 없다는 뜻이고, 내 모집이 어디 있는지 알려 준다.
  ///
  /// 둘이 동시에 참일 수 있다(오늘 매칭을 끝낸 뒤 또 모집을 올려 둔 경우). 그때는 배너를 두 장으로
  /// 나누지 않고 한 장 안에 두 줄로 적는다 — 참가를 막는 한도를 먼저 둔다(이 화면에서 하려는 일이다).
  Widget _buildLimitBanner({
    required bool hasPending,
    required bool dailyBattleUsed,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: PixelFrame.tone(
        tone: PixelTone.info,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (dailyBattleUsed) const Text(AppStrings.battleDailyLimitBanner),
            if (hasPending) ...[
              if (dailyBattleUsed) const SizedBox(height: 8),
              const Text(AppStrings.battleMyRecruitBlocked),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _goToMyBattles,
                  child: const Text(AppStrings.battleMyRecruitGo),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 목록 끝. 받는 중이면 로더, 실패했으면 다시 시도, 더 없으면 아무것도 두지 않는다
  /// (끝을 알리는 요란한 장치는 만들지 않는다).
  Widget? _buildTail(RecruitFeed? feed) {
    if (feed == null) return null;
    if (feed.loadingMore) return const StatusMessage.loading();
    if (feed.moreFailed) {
      return StatusMessage.error(
        message: AppStrings.battleRecruitsLoadMoreFailed,
        action: TextButton(
          onPressed: () =>
              ref.read(openRecruitFeedProvider.notifier).loadMore(),
          child: const Text(AppStrings.retry),
        ),
      );
    }
    return null;
  }

  /// 목록 끝이 가까워지면 다음 묶음을 **예약**한다. 빌드 중에 상태를 바꾸면 Flutter가 터지므로
  /// 동기로 부르지 않는다. 실패한 뒤에는 자동으로 다시 부르지 않고 꼬리의 `다시 시도`를 기다린다.
  void _maybeLoadMore(RecruitFeed feed, int index, int itemCount) {
    if (!feed.hasMore || feed.loadingMore || feed.moreFailed) return;
    if (index < itemCount - _loadMoreLookahead) return;
    Future.microtask(() {
      if (!mounted) return;
      ref.read(openRecruitFeedProvider.notifier).loadMore();
    });
  }
}

/// 열린 모집 카드. 무슨 대결인지(제목·유형·기간·기준 미리보기)까지만 보여 준다.
/// 생성자가 누구이고 전적이 어떤지는 목록에서 빼고 상세 시트에서만 본다 — 목록에서는
/// 대결 내용을 읽는 것이 중요하고, 사람과 전적은 참가를 결정할 때 보면 된다.
class _OpenRecruitCard extends StatelessWidget {
  const _OpenRecruitCard({required this.recruit, required this.onTap});

  final OpenRecruit recruit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final battle = recruit.battle;
    final preview = battle.minCriteria.isEmpty
        ? null
        : battle.minCriteria.first;

    return PixelFrame.raised(
      onTap: onTap,
      // 프레임 기본 12dp 패딩을 안쪽(오른쪽 칸)으로 옮겨 색 띠가 카드 높이를 그대로 채운다.
      padding: EdgeInsets.zero,
      // `stretch`는 높이가 먼저 정해져 있어야 쓸 수 있다. 이 카드는 ListView 항목이라 세로 제약이
      // 무한이므로 IntrinsicHeight로 높이를 확정한 뒤 띠를 늘린다.
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 세로로 훑을 때 눈이 멈출 앵커. 유형 색(속도전 앰버 / 품질전 민트)을 그대로 쓴다.
            // **보조 신호다** — 같은 뜻을 아래 유형 배지의 아이콘과 글자가 그대로 말하므로
            // 색만으로 전달되는 정보는 하나도 늘지 않는다(색각 이상 대응 유지).
            SizedBox(
              width: 8,
              child: ColoredBox(color: battleTypeAccent(battle.type)),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 대결 제목은 사용자가 입력한 문장이라 본문 글꼴로 둔다.
                    // 2줄 상한이 없으면 최대 4줄까지 늘어나 다음 카드의 시작 위치를 예측할 수 없다.
                    // 제목 전문은 상세 시트가 보여 준다.
                    Text(
                      battle.title,
                      style: textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        BattleTypeBadge(type: battle.type),
                        const SizedBox(width: 8),
                        // 카드 안에서 유일하게 테두리를 가진 조각이다(유형 배지는 테두리를 벗었다).
                        // "내가 낼 수 있는 시간인가"가 두 번째 판단 축이라 그 무게를 여기 둔다.
                        // 기간은 상태가 아니므로 중립 태그 모양을 쓴다(무승부 칩 모양을 끌어다
                        // 쓰면 앞으로 무승부 칩을 손댈 때 기간이 따라 변한다).
                        PixelTag(
                          label: battleDurationLabel(battle.durationMinutes),
                          style: neutralPixelTagStyle,
                          leading: const PixelIcon(PixelIcons.clock, size: 12),
                        ),
                      ],
                    ),
                    // 목록에서 중요한 것은 무슨 대결인지다. 기준 미리보기를 두 줄까지 보여 준다.
                    // 기준 첫 문장은 모집끼리 거의 같아(AI가 만든 문장) 제목과 같은 색이면
                    // 카드 네 장이 같은 실루엣으로 보인다 → 보조 글자색으로 낮춘다.
                    if (preview != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        preview,
                        style: textTheme.bodySmall?.copyWith(
                          color: RetroPalette.inkMuted,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
