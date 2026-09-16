import 'battle.dart';
import 'player_card.dart';

/// 모집 목록 한 줄. 대결(기준 두 목록과 기준 버전 포함)과 생성자 카드를 함께 담는다.
/// `list_open_recruits()`가 한 번에 돌려주므로 생성자 전적을 목록 수만큼 따로 부르지 않는다.
class OpenRecruit {
  const OpenRecruit({required this.battle, required this.creator});

  final Battle battle;
  final PlayerCard creator;

  factory OpenRecruit.fromMap(Map<String, dynamic> map) => OpenRecruit(
        battle: Battle.fromMap(Map<String, dynamic>.from(map['battle'] as Map)),
        creator: PlayerCard.fromMap(Map<String, dynamic>.from(map['creator'] as Map)),
      );
}
