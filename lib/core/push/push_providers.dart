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
  return PushService(ref.watch(pushMessagingProvider), ref.watch(pushRepositoryProvider));
});

/// 알림 권한 상태. 프로필의 "알림이 꺼져 있어요" 안내가 이 값만 본다.
/// 기기 설정에서 켜고 돌아온 경우를 잡으려고 프로필 탭에 들어올 때 `MainShell`이 무효화한다.
final notificationPermissionProvider = FutureProvider.autoDispose<NotificationPermission>((ref) {
  return ref.watch(pushMessagingProvider).permissionStatus();
});
