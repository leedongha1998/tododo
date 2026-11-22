/// 연습 대결(봇전) 주제 하나. **운영자가 미리 쓰고 검수한 고정 묶음**에서만 오고 AI가 만들지
/// 않는다 — 그래서 봇전 한 판이 일으키는 AI 호출이 0회다.
///
/// 기간이 주제에 붙어 있다(사용자가 고르지 않는다). 봇의 목표 시각이 기간의 비율로 정해지므로
/// 기간을 길게 잡는 것이 곧 난이도를 낮추는 것이기 때문이다.
class BotBattleTopic {
  const BotBattleTopic({
    required this.id,
    required this.title,
    required this.minCriteria,
    required this.durationMinutes,
  });

  final String id;
  final String title;

  /// 합격/불합격을 가르는 최소 기준. 시작 전에 공개된다(사람 대결과 같은 규칙).
  final List<String> minCriteria;

  /// 사진을 내는 시간(분). 주제마다 정해져 있다.
  final int durationMinutes;

  factory BotBattleTopic.fromMap(Map<String, dynamic> map) => BotBattleTopic(
        id: map['id'] as String,
        title: map['title'] as String,
        minCriteria:
            ((map['min_criteria'] as List?) ?? const []).map((item) => item as String).toList(),
        durationMinutes: (map['duration_minutes'] as num).toInt(),
      );
}

/// 주제 고르기 화면이 한 번에 받는 것: 주제 목록 + 오늘 남은 횟수.
///
/// 남은 횟수를 `get_my_limits`가 아니라 이 응답에 담는다 — 기준 생성 하루 10회와 봇전 하루 3회는
/// **완전히 별개의 한도**이고, 한 응답에 섞으면 화면이 "오늘 남은 횟수"를 두 개 들게 된다.
class BotBattleTopics {
  const BotBattleTopics({
    required this.dailyLimit,
    required this.dailyLeft,
    required this.topics,
  });

  /// 하루 상한(서버가 정한다. 지금은 3).
  final int dailyLimit;

  /// 오늘 남은 횟수. 0이면 자정(KST)이 지나야 다시 할 수 있다 — 판단은 전부 서버가 한다.
  final int dailyLeft;

  final List<BotBattleTopic> topics;

  bool get hasLeft => dailyLeft > 0;

  factory BotBattleTopics.fromMap(Map<String, dynamic> map) => BotBattleTopics(
        dailyLimit: (map['daily_limit'] as num).toInt(),
        dailyLeft: (map['daily_left'] as num).toInt(),
        topics: ((map['topics'] as List?) ?? const [])
            .map((row) => BotBattleTopic.fromMap(Map<String, dynamic>.from(row as Map)))
            .toList(),
      );
}
