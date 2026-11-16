import 'package:flutter_test/flutter_test.dart';
import 'package:todododo/features/notification/data/notification_inbox.dart';
import 'package:todododo/features/notification/data/notification_item.dart';

/// 원장 한 줄의 변환과 **배지 판정**(새 알림인가).
///
/// 경계가 중요하다: 서버 `has_new_notifications`는 `created_at > seen_at`으로 세므로,
/// 앱의 줄 표시도 **같은 경계**를 써야 한다. 어긋나면 배지는 꺼져 있는데 줄에는 점이 붙는다.
void main() {
  Map<String, dynamic> row({
    int id = 1,
    String kind = 'matched',
    String createdAt = '2026-11-08T06:04:00+00:00',
    Map<String, dynamic>? payload,
  }) => {
    'id': id,
    'kind': kind,
    'battle_id': 'b0b0b0b0-0000-0000-0000-000000000000',
    'payload': payload ?? {'title': '아침 달리기', 'battle_type': 'speed'},
    'created_at': createdAt,
  };

  group('NotificationItem.fromMap', () {
    test('다섯 키를 그대로 옮긴다', () {
      final item = NotificationItem.fromMap(row(id: 42, kind: 'judge_turn'));
      expect(item.id, 42);
      expect(item.kind, 'judge_turn');
      expect(item.battleId, 'b0b0b0b0-0000-0000-0000-000000000000');
      expect(item.payload['title'], '아침 달리기');
      expect(item.createdAt, DateTime.parse('2026-11-08T06:04:00+00:00'));
    });

    test('payload가 없으면 빈 맵이다(줄 문구가 대체값으로 그린다)', () {
      final map = row()..['payload'] = null;
      expect(NotificationItem.fromMap(map).payload, isEmpty);
    });
  });

  group('isNewSince — 배지·줄의 점 판정', () {
    final item = NotificationItem.fromMap(row(createdAt: '2026-11-08T06:04:00Z'));

    test('한 번도 열지 않았으면(null) 전부 새 알림이다', () {
      expect(item.isNewSince(null), isTrue);
    });

    test('읽은 시각보다 나중에 생긴 것이 새 알림이다', () {
      expect(item.isNewSince(DateTime.parse('2026-11-08T06:03:59Z')), isTrue);
    });

    test('읽은 시각과 **같은** 시각의 행은 새 알림이 아니다(서버의 > 비교와 같은 경계)', () {
      expect(item.isNewSince(DateTime.parse('2026-11-08T06:04:00Z')), isFalse);
    });

    test('읽은 시각보다 먼저 생긴 것은 새 알림이 아니다', () {
      expect(item.isNewSince(DateTime.parse('2026-11-08T06:04:01Z')), isFalse);
    });

    test('시간대 표기가 달라도 같은 순간이면 같게 판정한다', () {
      expect(item.isNewSince(DateTime.parse('2026-11-08T15:04:00+09:00')), isFalse);
      expect(item.isNewSince(DateTime.parse('2026-11-08T15:03:59+09:00')), isTrue);
    });
  });

  group('NotificationInbox.fromMap', () {
    test('seen_at이 null이면 null로 둔다(별도 플래그를 두지 않는다)', () {
      final inbox = NotificationInbox.fromMap({'seen_at': null, 'items': [row()]});
      expect(inbox.seenAt, isNull);
      expect(inbox.items, hasLength(1));
    });

    test('빈 목록도 그대로 받는다', () {
      final inbox = NotificationInbox.fromMap({'seen_at': null, 'items': []});
      expect(inbox.items, isEmpty);
    });

    test('서버가 준 순서를 바꾸지 않는다(최신순 정렬과 50건 상한의 기준이다)', () {
      final inbox = NotificationInbox.fromMap({
        'seen_at': '2026-11-08T06:00:00Z',
        'items': [row(id: 9), row(id: 7), row(id: 3)],
      });
      expect(inbox.seenAt, DateTime.parse('2026-11-08T06:00:00Z'));
      expect(inbox.items.map((item) => item.id), [9, 7, 3]);
    });
  });
}
