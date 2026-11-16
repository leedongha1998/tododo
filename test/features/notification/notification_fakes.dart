import 'package:todododo/features/notification/data/notification_inbox.dart';
import 'package:todododo/features/notification/data/notification_repository.dart';
import 'package:todododo/features/notification/domain/notification_providers.dart';

/// 알림함 레포지토리 가짜. mocking 프레임워크를 쓰지 않고 `implements`로 만든다(기존 관례).
class FakeNotificationRepository implements NotificationRepository {
  FakeNotificationRepository({
    this.inbox = NotificationInbox.empty,
    this.hasNewValue = false,
    this.listError,
  });

  final NotificationInbox inbox;
  final bool hasNewValue;

  /// 목록 조회가 실패하는 경우를 그리고 싶을 때.
  final Object? listError;

  /// 읽음을 몇 번 찍었는지. **한 번만 찍는다**를 확인하는 자리다.
  int markSeenCalls = 0;

  @override
  Future<NotificationInbox> fetchInbox() async {
    final error = listError;
    if (error != null) throw error;
    return inbox;
  }

  @override
  Future<bool> hasNew() async => hasNewValue;

  @override
  Future<void> markSeen() async => markSeenCalls++;
}

/// **네 탭 앱바가 모두 종 아이콘을 들고 있으므로**(notification-inbox) 그 화면을 띄우는 모든
/// 위젯 테스트가 이 레포지토리를 필요로 한다. 넣지 않으면 초기화되지 않은 Supabase를 만지며
/// provider가 예외를 던지고, 그 스택이 테스트 출력을 덮어 실제 실패를 가린다.
///
/// 배지를 보지 않는 테스트는 이것만 깔아 두면 된다(점 없음·빈 목록). 배지나 목록을 실제로 보는
/// 테스트는 `notificationRepositoryProvider.overrideWithValue(...)`를 직접 쓴다.
///
/// 타입을 적지 않는 이유: riverpod 3은 `Override` 타입을 공개 export하지 않아 이름을 쓸 수 없다.
/// 초기화식에서 추론된다.
/// **getter다**(2026-11-13 리뷰). 최종 필드로 두면 한 벌의 가짜를 모든 테스트가 나눠 쓰게 되어
/// `markSeenCalls` 같은 가변 상태가 테스트 사이에 누적된다 — 지금은 그 값을 보는 테스트가 자기
/// 가짜를 따로 만들어 써서 무해하지만, 결합을 남겨 둘 이유가 없다.
List<dynamic> get notificationOverrides => [
  notificationRepositoryProvider.overrideWithValue(FakeNotificationRepository()),
];
