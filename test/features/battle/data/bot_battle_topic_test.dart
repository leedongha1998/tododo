import 'package:flutter_test/flutter_test.dart';
import 'package:todododo/features/battle/data/bot_battle_topic.dart';

/// `list_bot_battle_topics()`가 돌려주는 jsonb를 그대로 흉내 낸 행.
/// 남은 횟수도 **서버가 센다** — 앱은 그 숫자를 보여 주기만 한다.
void main() {
  test('주제 목록과 남은 횟수를 서버 응답 모양 그대로 읽는다', () {
    final topics = BotBattleTopics.fromMap({
      'daily_limit': 3,
      'daily_left': 2,
      'topics': [
        {
          'id': '11111111-1111-1111-1111-111111111111',
          'title': '설거지하기',
          'min_criteria': ['싱크대 안에 씻지 않은 그릇이나 컵이 보이지 않는다', '싱크대 바닥에 음식물 찌꺼기가 남아 있지 않다'],
          'duration_minutes': 10,
        },
      ],
    });

    expect(topics.dailyLimit, 3);
    expect(topics.dailyLeft, 2);
    expect(topics.hasLeft, isTrue);
    expect(topics.topics, hasLength(1));
    expect(topics.topics.single.title, '설거지하기');
    expect(topics.topics.single.minCriteria, hasLength(2));
    expect(topics.topics.single.durationMinutes, 10);
  });

  test('남은 횟수 0은 "오늘은 끝"이고 주제 목록은 그대로 온다', () {
    final topics = BotBattleTopics.fromMap({
      'daily_limit': 3,
      'daily_left': 0,
      'topics': [
        {
          'id': 't1',
          'title': '이불 정리하기',
          'min_criteria': ['이불이 펼쳐진 채 자리 위에 네모지게 정돈돼 있다'],
          'duration_minutes': 5,
        },
      ],
    });

    expect(topics.hasLeft, isFalse);
    expect(topics.topics, hasLength(1));
  });

  test('운영자가 주제를 전부 내리면 빈 목록이 온다', () {
    final topics = BotBattleTopics.fromMap({
      'daily_limit': 3,
      'daily_left': 3,
      'topics': <Object?>[],
    });

    expect(topics.topics, isEmpty);
    expect(topics.hasLeft, isTrue);
  });
}
