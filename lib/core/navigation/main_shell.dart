import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/battle/domain/battle_providers.dart';
import '../../features/battle/presentation/battle_recruits_screen.dart';
import '../../features/battle/presentation/my_battles_screen.dart';
import '../../features/profile/domain/profile_providers.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/todo/presentation/todo_list_screen.dart';
import '../strings.dart';
import '../theme/pixel_icons.dart';
import '../theme/retro_palette.dart';
import '../widgets/pixel_icon.dart';
import 'app_tab.dart';

/// 로그인 후 앱의 뼈대. 탭 전환만 맡고, 각 탭은 자기 앱바와 FAB를 그대로 갖는다.
class MainShell extends ConsumerWidget {
  const MainShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
      }
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
