import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 하단 탭바의 탭. 선언 순서가 곧 탭바 순서다.
enum AppTab { myBattles, find, todo, profile }

/// 지금 선택된 탭.
///
/// 탭바뿐 아니라 화면 안에서도 다른 탭으로 보낼 수 있어야 해서 provider로 둔다
/// (내 대결이 비었을 때 `대결 찾기`로 유도하는 버튼 등).
class SelectedTab extends Notifier<AppTab> {
  @override
  AppTab build() => AppTab.myBattles;

  void select(AppTab tab) => state = tab;
}

final selectedTabProvider = NotifierProvider<SelectedTab, AppTab>(SelectedTab.new);
