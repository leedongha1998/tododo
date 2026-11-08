import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/battle/domain/battle_providers.dart';
import '../../features/battle/presentation/battle_detail_screen.dart';
import '../../features/battle/presentation/battle_recruits_screen.dart';
import '../../features/battle/presentation/my_battles_screen.dart';
import '../../features/profile/domain/profile_providers.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/todo/data/todo_widget_payload.dart';
import '../../features/todo/domain/todo_providers.dart';
import '../../features/todo/presentation/todo_list_screen.dart';
import '../push/push_providers.dart';
import '../push/push_service.dart';
import '../strings.dart';
import '../theme/app_icons.dart';
import '../theme/app_palette.dart';
import 'app_tab.dart';

/// 로그인 후 앱의 뼈대. 탭 전환만 맡고, 각 탭은 자기 앱바와 FAB를 그대로 갖는다.
///
/// 이 화면은 세션이 있을 때만 떠 있으므로(AuthGate) 푸시 토큰 등록을 시작·중지하는 자리도 여기다.
class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  PushService? _push;

  @override
  void initState() {
    super.initState();
    unawaited(_startPush());
    // 이 화면은 세션이 있을 때만 떠 있으므로 여기가 "로그인 직후"다. 기기 캐시를 먼저 되읽어
    // 지난 목록을 지키고(앱을 다시 켠 뒤 네트워크가 없으면 그 목록이 유일하게 보여 줄 것이다),
    // 보여 줄 것이 없을 때만 "불러오는 중"으로 덮는다. 그 뒤 아래 ref.listen이 실제 목록으로 덮는다.
    unawaited(
      ref
          .read(todoWidgetServiceProvider)
          .primeFromCache(now: DateTime.now()),
    );
  }

  /// 권한이 이미 있으면 토큰을 등록하고 갱신을 따라간다. 권한은 여기서 묻지 않는다.
  /// provider를 만드는 것부터 실패할 수 있어(Firebase 미초기화 등) 전체를 감싼다 — 알림 배선이
  /// 어떤 이유로 안 되더라도 화면은 그대로 떠야 한다.
  Future<void> _startPush() async {
    try {
      final push = ref.read(pushServiceProvider);
      _push = push;
      await push.start();
    } catch (error) {
      debugPrint('pushService start failed: $error');
    }
    // 종료 상태에서 알림을 탭해 시작된 경우, start()가 그 사이에 적어 두었다. 아래 ref.listen은
    // 이미 적힌 값에는 울리지 않으므로 여기서 한 번 집어 간다.
    await _openPendingBattle();
  }

  /// 알림이 가리키는 대결을 연다. 열 수 없으면 조용히 넘어간다 —
  /// 알림을 눌러서 오류 화면을 보는 일은 없어야 한다(spec "알림을 눌렀을 때").
  Future<void> _openPendingBattle() async {
    final battleId = ref.read(pendingBattleOpenProvider.notifier).take();
    if (battleId == null) return;

    // 탭을 먼저 옮긴다. 상세를 닫았을 때 그 대결이 있는 목록으로 돌아오게 하려는 것이다.
    ref.read(selectedTabProvider.notifier).select(AppTab.myBattles);

    // 열 수 있는지 먼저 확인한다. 취소된 대결이나 더 볼 수 없는 대결이면 상세가 오류 화면을
    // 띄우므로, 띄우기 전에 서버에 한 번 물어 본다.
    try {
      await ref.read(battleRepositoryProvider).fetchBattle(battleId);
    } catch (error) {
      debugPrint('알림으로 연 대결을 읽지 못했다($battleId): $error');
      return;
    }
    if (!mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => BattleDetailScreen(battleId: battleId)),
    );
  }

  @override
  void dispose() {
    _push?.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tab = ref.watch(selectedTabProvider);

    // 상대가 증거를 내거나 판정해도 알림이 없다. 탭으로 돌아오는 순간에만 다시 읽어
    // 최신 상태를 보여준다. 대결은 내가 앱을 보지 않는 동안 서버에서 끝나 있을 수 있다.
    ref.listen(selectedTabProvider, (previous, next) {
      if (next == AppTab.myBattles && previous != AppTab.myBattles) {
        ref.invalidate(myBattlesProvider);
        // 자리를 비운 사이 내 모집이 매칭돼 모집 구역에서 진행 중 목록으로 옮겨가 있을 수 있다.
        ref.invalidate(myRecruitsProvider);
      }
      // 대결 만들기의 사전 안내가 "오늘 남은 기준 생성 횟수"에 걸려 있고, 그 값은 다른 기기나
      // 지난 시도로 서버에서 바뀐다(대결 개수 한도는 없어졌다 — daily-limit-removal).
      // 모집 목록(피드)은 일부러 포함하지 않는다 — 스크롤 위치와 검색·필터 조건을 지키고,
      // 새 모집은 당겨서 새로고침으로 받는다.
      if (next == AppTab.find && previous != AppTab.find) {
        ref.invalidate(myLimitsProvider);
      }
      // 점수와 전적도 종결 시점에 서버가 바꾼다. 프로필로 돌아올 때 함께 다시 읽는다.
      if (next == AppTab.profile && previous != AppTab.profile) {
        ref.invalidate(battleRecordsProvider);
        ref.invalidate(myPlayerStatsProvider);
        // 기기 설정에서 알림을 켜고 돌아왔을 수 있다. "꺼져 있어요" 안내가 남아 있지 않게 다시 읽는다.
        ref.invalidate(notificationPermissionProvider);
      }
    });

    // 앱이 떠 있는 동안 알림을 탭하면(백그라운드에서 돌아온 경우) 여기서 집어 간다.
    ref.listen(pendingBattleOpenProvider, (previous, next) {
      if (next != null) unawaited(_openPendingBattle());
    });

    // 홈 화면 위젯은 앱이 마지막으로 받아온 목록의 기기 캐시를 보여 준다(서버를 직접 부르지
    // 않는다). 그래서 목록이 바뀌는 순간(추가·수정·삭제·체크 뒤의 invalidate 포함) 그 자리에서
    // 발행한다 — 앱을 나갈 때를 기다리지 않는다. 이 자리에 두는 이유는 할 일 화면에 두면 탭을
    // 떠난 뒤의 변경을 놓치기 때문이다. 발행 실패는 서비스가 로그만 남긴다(위젯은 관문이 아니다).
    ref.listen(todosProvider, (previous, next) {
      // 새로고침 중에는 직전 캐시를 그대로 둔다(빈 화면이나 낡았다는 안내를 깜빡이지 않게).
      if (next.isLoading) return;
      final service = ref.read(todoWidgetServiceProvider);
      final now = DateTime.now();
      final error = next.error;
      if (error != null) {
        // 로그는 화면(TodoListScreen)의 error 갈래가 이미 남긴다. 여기서 또 남기지 않는다.
        // 마지막으로 받아온 목록은 그대로 두고 "지금은 못 불러왔어요"만 붙인다.
        unawaited(
          service.publish(
            TodoWidgetPayload.fetchFailed(service.lastPublished, now: now),
          ),
        );
        return;
      }
      final todos = next.value;
      if (todos == null) return;
      unawaited(
        service.publish(TodoWidgetPayload.fromTodos(todos, now: now)),
      );
    });

    return Scaffold(
      // IndexedStack이라 탭을 오가도 스크롤 위치와 입력 중이던 내용이 남는다.
      body: IndexedStack(
        index: tab.index,
        children: const [
          MyBattlesScreen(),
          BattleRecruitsScreen(),
          TodoListScreen(),
          ProfileScreen(),
        ],
      ),
      // NavigationBar에는 shape가 없어 위 경계선을 셸에서 따로 긋는다(1dp line — design 5.1).
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            height: 1,
            width: double.infinity,
            child: ColoredBox(color: AppPalette.line),
          ),
          NavigationBar(
            selectedIndex: tab.index,
            onDestinationSelected: (index) =>
                ref.read(selectedTabProvider.notifier).select(AppTab.values[index]),
            // 선택은 색·표시기·아이콘 채움·라벨 굵기 넷으로 구분한다(찾기만 윤곽 변형이 없어 셋).
            destinations: const [
              NavigationDestination(
                icon: Icon(AppIcons.battleOutlined),
                selectedIcon: Icon(AppIcons.battle),
                label: AppStrings.battleMyBattles,
              ),
              NavigationDestination(
                icon: Icon(AppIcons.search),
                selectedIcon: Icon(AppIcons.search),
                label: AppStrings.battleFind,
              ),
              NavigationDestination(
                icon: Icon(AppIcons.todoOutlined),
                selectedIcon: Icon(AppIcons.todo),
                label: AppStrings.todoTitle,
              ),
              NavigationDestination(
                icon: Icon(AppIcons.profileOutlined),
                selectedIcon: Icon(AppIcons.profile),
                label: AppStrings.profileTitle,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
