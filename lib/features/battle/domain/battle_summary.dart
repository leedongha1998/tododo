import '../../../core/strings.dart';
import '../data/battle.dart';
import '../data/battle_participant.dart';

class BattleSummary {
  const BattleSummary({
    required this.battle,
    required this.otherPartyName,
    this.opponent,
  });

  final Battle battle;
  final String otherPartyName;

  /// 상대의 진행 요약(제출·판정 사실). 서버가 진행 중에도 내주는 값만 담긴 행이다 —
  /// 사진과 판정 내용은 여기에 없다.
  final BattleParticipant? opponent;

  /// 목록 카드에 붙는 상태 한 줄.
  ///
  /// MVP에는 푸시가 없으므로(발송은 `push-notification` feature), spec "알림 대상 사건"을
  /// 앱 안에서 확인하는 자리가 이 줄이다. 서버가 기록한 요약을 문장으로 옮길 뿐 판정하지 않는다.
  /// 알릴 일이 없으면 null이고, 그때는 카드에 줄을 그리지 않는다.
  String? statusLineAt(DateTime now) {
    // 마감이 지났는데 아직 목록에 있다 = 서버가 정리하는 중이다(판정 창 열기 등).
    // 사용자가 할 일은 없다.
    final deadline = battle.deadlineAt;
    if (deadline != null && !deadline.isAfter(now)) {
      return AppStrings.battleListSettling;
    }

    // 상호 판정 창. 속도전·품질전 공통.
    if (battle.status == 'judging') return AppStrings.battleListJudging;

    final opponent = this.opponent;
    if (opponent == null) return null;

    // 마감 전에 상대에 대해 보이는 것은 "제출했다"는 사실 하나뿐이다(시각·사진·통과 여부는 숨긴다).
    if (opponent.hasSubmitted) return AppStrings.battleListOpponentSubmitted;
    return null;
  }

  String? get statusLine => statusLineAt(DateTime.now());
}
