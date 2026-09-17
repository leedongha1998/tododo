/// 내 점수와 승/패/무 전적.
///
/// 서버 `player_stats` 행을 그대로 옮긴다. 쓰기는 `finalize_battle`만 하고, 앱은 본인 행만
/// 읽을 수 있다(RLS). 무효·취소로 끝난 대결은 서버가 애초에 세지 않는다.
class PlayerStats {
  const PlayerStats({
    required this.score,
    required this.wins,
    required this.losses,
    required this.draws,
  });

  /// 시작 점수는 0점이고 하한도 0점이다(서버 제약).
  final int score;
  final int wins;
  final int losses;
  final int draws;

  /// 아직 행이 없는 계정(백필 전)에 쓰는 기본값.
  static const empty = PlayerStats(score: 0, wins: 0, losses: 0, draws: 0);

  static int _intOf(Object? value) => value == null ? 0 : (value as num).toInt();

  factory PlayerStats.fromMap(Map<String, dynamic> map) => PlayerStats(
        score: _intOf(map['score']),
        wins: _intOf(map['wins']),
        losses: _intOf(map['losses']),
        draws: _intOf(map['draws']),
      );
}
