/// 알림 원장(`notification_outbox`) 한 줄. `list_notifications` RPC가 돌려주는 다섯 키를 그대로 옮긴다.
///
/// **발송 상태(`status`)·오류(`last_error`)·dedup 키는 여기 없다.** 서버 함수가 애초에 돌려주지
/// 않기 때문이다(design 2장) — 사용자가 할 수 있는 일이 없고, `last_error`는 FCM이 준 서버 오류
/// 문자열이다. 그래서 "발송 상태를 보여 주지 않는다"는 화면의 규율이 아니라 API 경계다.
///
/// [payload]는 **사건이 확정된 시점의 스냅샷**이고 판정 사유·사진 경로·상대 표시 이름을 담지
/// 않는다. 줄 문구는 이 스냅샷과 [kind]만으로 만든다(`notification_line.dart`) — 알림함은
/// `battles`·`profiles`·`battle_submissions`를 한 번도 읽지 않는다.
class NotificationItem {
  const NotificationItem({
    required this.id,
    required this.kind,
    required this.battleId,
    required this.payload,
    required this.createdAt,
  });

  /// 원장 행 번호(`bigserial`). 같은 [createdAt]을 가진 두 행의 순서를 가르는 축이기도 하다.
  final int id;

  /// 사건 종류. 7종(`matched`/`submitted`/`judge_turn`/`deadline_soon`/`finished`/`voided`/`cancelled`).
  final String kind;

  /// 이 사건이 일어난 대결. 줄을 누르면 이 대결의 상세로 간다.
  final String battleId;

  final Map<String, dynamic> payload;

  /// 사건이 적재된 **서버 시각**(UTC). 보여 줄 때만 `toLocal()`한다.
  final DateTime createdAt;

  /// 이 줄이 "새 알림"인가. [seenAt]은 알림함을 **열었을 때 받은 스냅샷**이고, 보고 있는 동안
  /// 기준을 바꾸지 않는다(그래야 표시가 눈앞에서 사라지지 않는다 — design 5.2).
  ///
  /// 한 번도 알림함을 열지 않았으면(null) 전부 새 알림이다. 경계는 서버
  /// `has_new_notifications`의 `>` 비교와 **같게** 둔다 — 읽은 시각과 **같은** 시각의 행은
  /// 새 알림이 아니다. 어긋나면 배지는 꺼져 있는데 줄에는 점이 붙는다.
  bool isNewSince(DateTime? seenAt) {
    if (seenAt == null) return true;
    return createdAt.isAfter(seenAt);
  }

  factory NotificationItem.fromMap(Map<String, dynamic> map) => NotificationItem(
    id: (map['id'] as num).toInt(),
    kind: map['kind'] as String,
    battleId: map['battle_id'] as String,
    payload: map['payload'] == null
        ? const <String, dynamic>{}
        : Map<String, dynamic>.from(map['payload'] as Map),
    createdAt: DateTime.parse(map['created_at'] as String),
  );
}
