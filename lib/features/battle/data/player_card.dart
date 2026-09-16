/// 상대·모집 생성자의 공개 전적 카드.
///
/// 공개 범위는 서버(`get_player_card`, `list_open_recruits`)가 정한다 —
/// 대결 상대와 모집 생성자만 볼 수 있고, 임의 사용자를 조회하는 경로는 없다.
class PlayerCard {
  const PlayerCard({
    required this.userId,
    required this.displayName,
    this.score,
    this.wins,
    this.losses,
    this.draws,
    this.deleted = false,
  });

  final String userId;
  final String displayName;

  /// 탈퇴한 사용자는 점수 행이 없어 전부 null이다.
  final int? score;
  final int? wins;
  final int? losses;
  final int? draws;

  final bool deleted;

  bool get hasStats => score != null;

  static int? _intOf(Object? value) => value == null ? null : (value as num).toInt();

  factory PlayerCard.fromMap(Map<String, dynamic> map) => PlayerCard(
        userId: map['user_id'] as String,
        displayName: map['display_name'] as String,
        score: _intOf(map['score']),
        wins: _intOf(map['wins']),
        losses: _intOf(map['losses']),
        draws: _intOf(map['draws']),
        deleted: (map['deleted'] as bool?) ?? false,
      );
}
