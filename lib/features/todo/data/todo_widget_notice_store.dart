import 'package:shared_preferences/shared_preferences.dart';

/// "홈 화면 위젯 노출 안내를 봤다"는 기억(design 7.1).
///
/// 기기 로컬 + 계정별 키라서 같은 기기에서 다른 계정으로 로그인하면 그 계정 기준으로 한 번 더
/// 뜬다(선례: `VsIntroSeenStore`). 재설치·다른 기기에서 다시 뜨는 것은 받아들인다 — 스키마를
/// 바꾸지 않는 안내라 서버에 저장하지 않는다. 키는 지우지 않는다(키 하나당 수십 바이트).
///
/// 닫으면 끝이고 **다시 꺼내는 설정을 만들지 않는다**(spec: 위젯 설정 화면은 범위 밖).
class TodoWidgetNoticeStore {
  const TodoWidgetNoticeStore();

  static String keyFor(String userId) => 'todo_widget_notice_seen/$userId';

  Future<bool> hasSeen(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(keyFor(userId)) ?? false;
  }

  Future<void> markSeen(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(keyFor(userId), true);
  }
}
