import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/battle/domain/battle_providers.dart';
import '../../features/battle/presentation/battle_recruits_screen.dart';
import '../../features/battle/presentation/my_battles_screen.dart';
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

    // 상대가 증거를 내거나 판정해도 알림이 없다. 내 대결 탭으로 돌아오는 순간에만
    // 목록을 다시 읽어 최신 상태를 보여준다.
    ref.listen(selectedTabProvider, (previous, next) {
      if (next == AppTab.myBattles && previous != AppTab.myBattles) {
        ref.invalidate(myBattlesProvider);
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
