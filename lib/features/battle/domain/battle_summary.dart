import '../../../core/strings.dart';
import '../data/battle.dart';
import '../data/battle_participant.dart';

class BattleSummary {
  const BattleSummary({
    required this.battle,
    required this.otherPartyName,
    this.me,
    this.opponent,
  });

  final Battle battle;
  final String otherPartyName;

  /// 내 진행 요약(제출·판정 여부). 판정 차례인지 가르는 데 쓴다.
  final BattleParticipant? me;

  /// 상대의 진행 요약(제출·판정 여부). 서버가 진행 중에도 내주는 값만 담긴 행이다 —
  /// 제출 시각·사진·판정 내용은 여기에 없다.
  final BattleParticipant? opponent;

  /// 목록 카드에 붙는 상태 한 줄.
  ///
  /// 푸시가 붙기 전까지 "그 사이 무슨 일이 있었는지"를 앱 안에서 확인하는 자리가 이 줄이다.
  /// 서버가 기록한 요약을 문장으로 옮길 뿐 판정하지 않는다. 알릴 일이 없으면 null이다.
  String? statusLineAt(DateTime now) {
    final me = this.me;
    final opponent = this.opponent;

    if (battle.status == 'judging') {
      if (me == null || opponent == null) return null;

      // 판정할 사람은 상대 증거가 있는 쪽이다(속도전 한쪽 제출이면 제출하지 않은 사람만).
      final myJudgmentDue = opponent.hasSubmitted && !me.hasJudged;
      final opponentJudgmentDue = me.hasSubmitted && !opponent.hasJudged;

      if (myJudgmentDue) {
        final deadline = battle.judgeDeadlineAt;
        if (deadline == null || !deadline.isAfter(now)) return AppStrings.battleListMyJudgeTurn;
        return AppStrings.battleListMyJudgeTurnLeft(_remainingText(deadline.difference(now)));
      }
      if (opponentJudgmentDue) return AppStrings.battleListWaitingOpponentJudgment;
      // 필요한 판정이 다 끝났는데 아직 판정 창이면 AI 재판정이 남아 있다는 뜻이다
      // (결론은 마지막 판정과 같은 트랜잭션에서 나므로 다른 경우가 없다).
      return AppStrings.battleListAiRejudging;
    }

    // 제출 창인데 마감이 지났다 = 서버가 판정 창을 열거나 결과를 정리하는 중이다(최대 1분).
    final deadline = battle.deadlineAt;
    if (deadline != null && !deadline.isAfter(now)) {
      return AppStrings.battleListSettling;
    }

    if (opponent == null || !opponent.hasSubmitted) return null;
    if (me != null && me.hasSubmitted) return AppStrings.battleListBothSubmitted;
    return AppStrings.battleListOpponentSubmitted;
  }

  String? get statusLine => statusLineAt(DateTime.now());
}

// 목록 한 줄에는 가장 큰 단위 하나면 충분하다.
String _remainingText(Duration gap) {
  if (gap.inDays > 0) return '${gap.inDays}일';
  if (gap.inHours > 0) return '${gap.inHours}시간';
  if (gap.inMinutes > 0) return '${gap.inMinutes}분';
  return '${gap.inSeconds}초';
}
