import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/battle/domain/battle_providers.dart';
import '../../features/battle/presentation/battle_recruits_screen.dart';
import '../../features/battle/presentation/my_battles_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/todo/presentation/todo_list_screen.dart';
import '../strings.dart';

/// 로그인 후 앱의 뼈대. 탭 전환만 맡고, 각 탭은 자기 앱바와 FAB를 그대로 갖는다.
class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  static const _myBattlesTab = 0;

  int _index = _myBattlesTab;

  void _selectTab(int index) {
    // 상대가 증거를 내거나 판정해도 알림이 없다. 대결 탭으로 돌아올 때 한 번 다시 읽어
    // 최신 상태를 보여준다.
    if (index == _myBattlesTab && _index != _myBattlesTab) {
      ref.invalidate(myBattlesProvider);
    }
    setState(() => _index = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // IndexedStack이라 탭을 오가도 스크롤 위치와 입력 중이던 내용이 남는다.
      body: IndexedStack(
        index: _index,
        children: const [
          MyBattlesScreen(),
          BattleRecruitsScreen(),
          TodoListScreen(),
          ProfileScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _selectTab,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.sports_kabaddi),
            label: AppStrings.battleMyBattles,
          ),
          NavigationDestination(
            icon: Icon(Icons.search),
            label: AppStrings.battleFind,
          ),
          NavigationDestination(
            icon: Icon(Icons.check_circle_outline),
            selectedIcon: Icon(Icons.check_circle),
            label: AppStrings.todoTitle,
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: AppStrings.profileTitle,
          ),
        ],
      ),
    );
  }
}
