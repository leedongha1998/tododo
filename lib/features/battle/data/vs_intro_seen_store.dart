import 'package:shared_preferences/shared_preferences.dart';

/// "이 대결의 VS 인트로를 봤다"는 기억(design.md 4.2).
///
/// 기기 로컬 + 계정별 키라서 같은 기기에서 다른 계정으로 로그인하면 그 계정 기준으로 한 번 더
/// 뜬다(대결마다 한 사람에게 한 번). 재설치·다른 기기에서 다시 뜨는 것은 spec이 허용한다.
/// 스키마를 바꾸지 않는 기능이라 서버에 저장하지 않는다. 키는 지우지 않는다(키 하나당 수십 바이트).
class VsIntroSeenStore {
  const VsIntroSeenStore();

  static String keyFor(String userId, String battleId) => 'vs_intro_seen/$userId/$battleId';

  Future<bool> hasSeen(String userId, String battleId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(keyFor(userId, battleId)) ?? false;
  }

  Future<void> markSeen(String userId, String battleId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(keyFor(userId, battleId), true);
  }
}
