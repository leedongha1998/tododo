import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/battle/domain/battle_providers.dart';
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
import '../theme/pixel_icons.dart';
import '../theme/retro_palette.dart';
import '../widgets/pixel_icon.dart';
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
      // 찾기 탭의 안내 배너와 만들기 버튼 분기가 "이미 모집 중인지"에 걸려 있고, 그 값은 서버에서 바뀐다.
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
      // NavigationBar에는 shape가 없어 위 경계선을 셸에서 따로 긋는다.
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 2, width: double.infinity, child: ColoredBox(color: RetroPalette.ink)),
          NavigationBar(
            selectedIndex: tab.index,
            onDestinationSelected: (index) =>
                ref.read(selectedTabProvider.notifier).select(AppTab.values[index]),
            // 선택 표시는 표시기 면색이 맡으므로 selectedIcon을 따로 두지 않는다.
            destinations: const [
              NavigationDestination(
                icon: PixelIcon(PixelIcons.battle),
                label: AppStrings.battleMyBattles,
              ),
              NavigationDestination(
                icon: PixelIcon(PixelIcons.search),
                label: AppStrings.battleFind,
              ),
              NavigationDestination(
                icon: PixelIcon(PixelIcons.todo),
                label: AppStrings.todoTitle,
              ),
              NavigationDestination(
                icon: PixelIcon(PixelIcons.profile),
                label: AppStrings.profileTitle,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
