import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../supabase/supabase_init.dart';
import 'push_messaging.dart';
import 'push_repository.dart';
import 'push_service.dart';

/// `FirebaseMessaging` 접점. 위젯 테스트에서 가짜로 바꾸는 지점이다.
final pushMessagingProvider = Provider<PushMessaging>((ref) => const PushMessaging());

final pushRepositoryProvider = Provider<PushRepository>((ref) {
  return PushRepository(supabase);
});

final pushServiceProvider = Provider<PushService>((ref) {
  // ref를 함께 넘기는 이유: 포그라운드 수신은 화면이 보고 있는 provider를 다시 읽게 해야 하고,
  // 알림 탭은 아래 pendingBattleOpenProvider에 기록해야 한다(design 흐름 6·7).
  return PushService(
    ref,
    ref.watch(pushMessagingProvider),
    ref.watch(pushRepositoryProvider),
  );
});

/// 알림을 탭해 열어야 할 대결. `PushService`가 적고 `MainShell`이 읽어 비운다.
///
/// 값을 들고 있는 이유: 알림은 앱이 종료된 상태에서도 올 수 있어 "열어 달라"는 요청과 "열 수 있는
/// 화면이 떠 있다"가 시점이 다르다. 셸이 준비됐을 때 집어 가게 한 칸에 적어 둔다.
/// 로그인 전에 적히면 `MainShell`이 없으므로 아무도 집어 가지 않고 그대로 버려진다 —
/// 알림을 눌러서 오류 화면을 보는 일이 없어야 한다는 spec 그대로다.
class PendingBattleOpen extends Notifier<String?> {
  @override
  String? build() => null;

  void request(String battleId) => state = battleId;

  /// 읽으면서 비운다. 같은 알림으로 두 번 열지 않는다.
  String? take() {
    final battleId = state;
    if (battleId != null) state = null;
    return battleId;
  }
}

final pendingBattleOpenProvider =
    NotifierProvider<PendingBattleOpen, String?>(PendingBattleOpen.new);

/// 알림 권한 상태. 프로필의 "알림이 꺼져 있어요" 안내가 이 값만 본다.
/// 기기 설정에서 켜고 돌아온 경우를 잡으려고 프로필 탭에 들어올 때 `MainShell`이 무효화한다.
final notificationPermissionProvider = FutureProvider.autoDispose<NotificationPermission>((ref) {
  return ref.watch(pushMessagingProvider).permissionStatus();
});
