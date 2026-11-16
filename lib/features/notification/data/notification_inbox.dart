import 'notification_item.dart';

/// `list_notifications` RPC의 반환값 한 묶음 — 최근 50건과 **마지막으로 알림함을 본 시각**.
///
/// 두 값을 한 호출에서 함께 받는 이유: 따로 물으면 그 사이에 찍히는 값 때문에 "새 알림" 표시가
/// 어긋날 수 있다. 화면은 이 스냅샷 하나로 새/읽음을 가른다(design 3.1).
class NotificationInbox {
  const NotificationInbox({required this.seenAt, required this.items});

  /// 한 번도 알림함을 열지 않았으면 null이다(서버에 행이 없다). 그때는 전부 새 알림이다.
  final DateTime? seenAt;

  /// 최신순(서버가 `created_at desc, id desc`로 정렬했다). 앱이 다시 정렬하지 않는다 —
  /// 50건으로 자르는 기준도 그 정렬이라, 여기서 순서를 바꾸면 "최근 50건"의 뜻이 흔들린다.
  final List<NotificationItem> items;

  static const empty = NotificationInbox(seenAt: null, items: []);

  factory NotificationInbox.fromMap(Map<String, dynamic> map) => NotificationInbox(
    seenAt: map['seen_at'] == null ? null : DateTime.parse(map['seen_at'] as String),
    items: ((map['items'] as List?) ?? const [])
        .map((row) => NotificationItem.fromMap(Map<String, dynamic>.from(row as Map)))
        .toList(),
  );
}
