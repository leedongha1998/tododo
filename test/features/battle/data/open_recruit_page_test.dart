import 'package:flutter_test/flutter_test.dart';

import 'package:todododo/features/battle/data/open_recruit_page.dart';

Map<String, dynamic> _row(String id, String createdAt) => {
  'battle': {
    'id': id,
    'type': 'speed',
    'status': 'pending',
    'title': '설거지하기',
    'creator_id': 'creator1',
    'created_at': createdAt,
    'duration_minutes': 30,
    'criteria_version': 1,
    'min_criteria': ['싱크대가 비어 있다'],
    'superiority_criteria': null,
  },
  'creator': {
    'user_id': 'creator1',
    'display_name': '도윤',
    'deleted': false,
    'score': 3,
    'wins': 1,
    'losses': 0,
    'draws': 0,
  },
};

void main() {
  test('행 순서(서버의 최신순)를 그대로 둔다', () {
    final page = OpenRecruitPage.fromRows([
      _row('b1', '2026-10-28T10:00:00+00:00'),
      _row('b2', '2026-10-28T09:00:00+00:00'),
    ], 20);

    expect(page.items.map((item) => item.battle.id), ['b1', 'b2']);
    expect(page.items.first.creator.displayName, '도윤');
  });

  // 커서가 깎이거나 포맷이 바뀌면 다음 묶음에서 행이 조용히 빠지거나 두 번 나온다.
  test('커서는 마지막 행이 준 문자열 원문 그대로다', () {
    final page = OpenRecruitPage.fromRows([
      _row('b1', '2026-10-28T10:00:00+00:00'),
      _row('b2', '2026-10-28T09:00:00.123456+00:00'),
    ], 20);

    expect(page.nextCursor!.id, 'b2');
    expect(page.nextCursor!.createdAt, '2026-10-28T09:00:00.123456+00:00');
  });

  test('묶음이 꽉 찼으면 더 있을 수 있다고 본다', () {
    final full = OpenRecruitPage.fromRows([
      _row('b1', '2026-10-28T10:00:00+00:00'),
      _row('b2', '2026-10-28T09:00:00+00:00'),
    ], 2);
    expect(full.hasMore, isTrue);
  });

  test('묶음이 덜 찼으면 끝이다', () {
    final partial = OpenRecruitPage.fromRows([
      _row('b1', '2026-10-28T10:00:00+00:00'),
    ], 2);
    expect(partial.hasMore, isFalse);
  });

  test('0건이면 커서도 없고 끝이다', () {
    final empty = OpenRecruitPage.fromRows(const [], 20);
    expect(empty.items, isEmpty);
    expect(empty.nextCursor, isNull);
    expect(empty.hasMore, isFalse);
  });
}
