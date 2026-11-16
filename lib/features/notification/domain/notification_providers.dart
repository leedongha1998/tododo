import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_init.dart';
import '../data/notification_inbox.dart';
import '../data/notification_repository.dart';

final notificationRepositoryProvider = Provider<NotificationRepository>((ref) {
  return NotificationRepository(supabase);
});

/// 알림함 화면이 여는 유일한 조회. 최근 50건과 마지막으로 본 시각을 함께 받는다.
///
/// `autoDispose`라 화면을 닫고 다시 열면 새로 읽는다 — 그래서 당겨서 새로고침을 두지 않는다
/// (design 5.2). 상세를 열었다 뒤로 나오는 동안은 알림함 화면이 살아 있어 목록이 유지된다.
final notificationInboxProvider = FutureProvider.autoDispose<NotificationInbox>((ref) {
  return ref.watch(notificationRepositoryProvider).fetchInbox();
});

/// 네 탭 앱바의 종 아이콘이 보는 값 하나. **네 앱바가 같은 provider를 보므로 값이 어긋날 수 없다.**
///
/// `autoDispose`인데도 탭을 오가며 버려지지 않는 이유: 네 탭은 `MainShell`의 `IndexedStack`에
/// 동시에 살아 있어 구독이 끊기지 않는다. 그리고 로그아웃으로 셸이 사라지면 값이 버려진다 —
/// 다음 사용자가 이전 사용자의 배지를 보는 일이 없다.
///
/// 다시 읽는 계기는 네 가지다(design 흐름 2): 셸이 처음 뜰 때, 탭 전환, 앱 재개, 포그라운드 푸시
/// 수신. 주기 폴링은 두지 않는다.
///
/// 실패는 **종 위젯**이 받는다 — 점을 그리지 않고 `debugPrint`만 남긴다(design 5.1).
final hasNewNotificationsProvider = FutureProvider.autoDispose<bool>((ref) {
  return ref.watch(notificationRepositoryProvider).hasNew();
});
