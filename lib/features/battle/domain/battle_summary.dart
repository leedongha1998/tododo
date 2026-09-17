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

  /// 상대의 진행 요약(제출 사실·속도전 최근 판정). 서버가 진행 중에도 내주는 값만 담긴 행이다 —
  /// 사진과 판정 사유는 여기에 없다.
  final BattleParticipant? opponent;

  /// 목록 카드에 붙는 상태 한 줄.
  ///
  /// MVP에는 푸시가 없으므로(발송은 `push-notification` feature), spec "알림 대상 사건"을
  /// 앱 안에서 확인하는 자리가 이 줄이다. 서버가 기록한 요약을 문장으로 옮길 뿐 판정하지 않는다.
  /// 알릴 일이 없으면 null이고, 그때는 카드에 줄을 그리지 않는다.
  String? statusLineAt(DateTime now) {
    // 마감이 지났는데 아직 목록에 있다 = 서버가 판정을 마무리하는 중이다(속도전 판정 대기,
    // 품질전 재시도 등). 사용자가 할 일은 없다.
    final deadline = battle.deadlineAt;
    if (deadline != null && !deadline.isAfter(now)) {
      return AppStrings.battleListSettling;
    }

    // 품질전은 두 사진이 모두 올라온 뒤 대결 단위로 판정한다.
    if (battle.status == 'judging') return AppStrings.battleListJudging;

    final opponent = this.opponent;
    if (opponent == null) return null;

    // 속도전은 상대 제출의 합격/불합격까지 공개된다(사유는 종결 뒤에 열린다).
    if (battle.type == 'speed') {
      switch (opponent.lastVerdict) {
        case 'passed':
          return AppStrings.battleListOpponentPassed;
        case 'failed':
          return AppStrings.battleListOpponentFailed;
      }
    }

    if (opponent.firstSubmittedAt != null) return AppStrings.battleListOpponentSubmitted;
    return null;
  }

  String? get statusLine => statusLineAt(DateTime.now());
}
