import 'package:supabase_flutter/supabase_flutter.dart';

import 'notification_inbox.dart';

/// 앱 안 알림함이 서버에 묻는 세 가지. **원장 테이블을 직접 읽지 않는다** — 그 테이블에는
/// 정책이 하나도 없어 어떤 질의로도 0행이고, 읽기를 여는 자리는 `security definer` 함수 셋이다
/// (design 2장). 그래서 `status`·`last_error` 같은 서버 내부 값이 앱에 올 길이 구조적으로 없다.
///
/// 쓰기는 "마지막으로 본 시각" 하나뿐이고 그 값은 승부와 무관하다. 알림함은 읽기 전용 거울이라
/// 판정·점수·상태 전이에 한 줄도 닿지 않는다(design 원칙 1).
class NotificationRepository {
  NotificationRepository(this._client);

  final SupabaseClient _client;

  /// 최근 50건 + 마지막으로 본 시각. 상한·정렬은 **서버 상수**라 인자가 없다.
  Future<NotificationInbox> fetchInbox() async {
    final row = await _client.rpc('list_notifications');
    return NotificationInbox.fromMap(Map<String, dynamic>.from(row as Map));
  }

  /// 배지(점 하나)가 보는 값. 개수를 세지 않는다. 비교는 서버가 한다(클라이언트 시계를
  /// 신뢰하지 않는다) — 앱은 시각을 주지도, 받지도 않고 참/거짓만 받는다.
  Future<bool> hasNew() async {
    final value = await _client.rpc('has_new_notifications');
    return value as bool;
  }

  /// 알림함을 열었다. 시각은 서버가 찍는다(인자 없음, 멱등).
  Future<void> markSeen() {
    return _client.rpc('mark_notifications_seen');
  }
}
