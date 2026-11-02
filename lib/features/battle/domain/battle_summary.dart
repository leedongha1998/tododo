import '../../../core/strings.dart';
import '../data/battle.dart';
import '../data/battle_participant.dart';
import 'judgment_rules.dart';
import 'remaining_time.dart';

/// 목록 카드가 말하는 소식 한 줄.
///
/// [needsMyAction]은 "지금 내가 손을 써야 한다"는 뜻이고, 카드가 이 줄을 강조할지 고르는 데만 쓴다.
/// 승패와 무관하다 — 서버가 기록한 제출·판정 사실에서 그대로 따라온다.
typedef BattleSummaryNotice = ({String? line, bool needsMyAction});

const BattleSummaryNotice _nothingToTell = (line: null, needsMyAction: false);

class BattleSummary {
  const BattleSummary({
    required this.battle,
    required this.otherPartyName,
    this.me,
    this.opponent,
  });

  final Battle battle;
  final String otherPartyName;

  /// 내 진행 요약(제출·판정 사실). 상대 행과 같은 요청으로 함께 받아 온다 — 추가 조회가 없다.
  final BattleParticipant? me;

  /// 상대의 진행 요약(제출·판정 사실). 서버가 진행 중에도 내주는 값만 담긴 행이다 —
  /// 사진과 판정 내용은 여기에 없다.
  final BattleParticipant? opponent;

  /// 목록 카드에 붙는 상태 한 줄 + 강조 여부.
  ///
  /// MVP에는 푸시가 없으므로(발송은 `push-notification` feature), spec "알림 대상 사건"을
  /// 앱 안에서 확인하는 자리가 이 줄이다. 서버가 기록한 요약을 문장으로 옮길 뿐 판정하지 않는다.
  /// 알릴 일이 없으면 line이 null이고, 그때는 카드에 줄을 그리지 않는다.
  ///
  /// 위에서부터 먼저 맞는 줄이 소식이 된다. 한 줄만 고른다 — "내가 할 일"이 상대 소식보다 앞이다.
  BattleSummaryNotice noticeAt(DateTime now) {
    // 1. 판정 창. 마감 경과보다 먼저 본다 — 속도전 판정 창은 대개 마감 뒤에 열리므로
    //    마감을 먼저 보면 "내가 판정할 차례"가 영원히 가려진다.
    if (battle.status == 'judging') return _judgingNoticeAt(now);

    // 2. 마감이 지났는데 판정 창도 아니다 = 서버가 정리하는 중이다. 사용자가 할 일은 없다.
    final deadline = battle.deadlineAt;
    if (deadline != null && !deadline.isAfter(now)) {
      return (line: AppStrings.battleListSettling, needsMyAction: false);
    }

    // 3. 제출 창인데 내 사진이 아직 없다. 이 카드에서 가장 급한 소식이다.
    final me = this.me;
    if (battle.status == 'active' && me != null && !me.hasSubmitted) {
      return (line: AppStrings.battleListNotSubmitted, needsMyAction: true);
    }

    // 4. 마감 전에 상대에 대해 보이는 것은 "제출했다"는 사실 하나뿐이다(시각·사진·통과 여부는 숨긴다).
    if (opponent?.hasSubmitted ?? false) {
      return (
        line: AppStrings.battleListOpponentSubmitted,
        needsMyAction: false,
      );
    }

    return _nothingToTell;
  }

  /// 판정 창의 단계별 문구. 단계 판정은 [judgmentStageOf]가 하고 여기서는 문장만 고른다.
  /// 참가자 행을 읽지 못했으면 입력이 모두 false가 되어 기존 중립 문구로 떨어진다.
  BattleSummaryNotice _judgingNoticeAt(DateTime now) {
    final stage = judgmentStageOf(
      status: battle.status,
      opponentSubmitted: opponent?.hasSubmitted ?? false,
      iSubmitted: me?.hasSubmitted ?? false,
      iJudged: me?.hasJudged ?? false,
      opponentJudged: opponent?.hasJudged ?? false,
      judgeDeadlineAt: battle.judgeDeadlineAt,
      now: now,
    );

    return switch (stage) {
      JudgmentStage.myTurn => (
        line: AppStrings.battleListMyJudgeTurn,
        needsMyAction: true,
      ),
      JudgmentStage.waitingOpponent => (
        line: AppStrings.battleListWaitingOpponentJudge,
        needsMyAction: false,
      ),
      JudgmentStage.waitingAi => (
        line: AppStrings.battleJudgmentAiTitle,
        needsMyAction: false,
      ),
      // nothingToJudge·windowClosed: 내가 할 일이 없다. notOpen은 여기까지 오지 않는다.
      _ => (line: AppStrings.battleListJudging, needsMyAction: false),
    };
  }

  String? statusLineAt(DateTime now) => noticeAt(now).line;

  /// 카드에 붙는 남은 시간 한 줄. 지금 실제로 흐르는 시계만 말한다 —
  /// 판정 창이면 판정 기한, 제출 창이면 사진 마감이다. 어느 시계인지 라벨로 밝힌다
  /// ("1일 남음"만 두면 무엇의 1일인지 알 수 없다). 지났거나 값이 없으면 null.
  String? deadlineLineAt(DateTime now) {
    final isJudging = battle.status == 'judging';
    final deadline = isJudging ? battle.judgeDeadlineAt : battle.deadlineAt;
    if (deadline == null || !deadline.isAfter(now)) return null;

    final label = isJudging
        ? AppStrings.battleJudgeDeadlineLabel
        : AppStrings.battleSubmitDeadlineLabel;
    final left = AppStrings.battleDeadlineLeft(
      formatRemaining(deadline.difference(now)),
    );
    return '$label · $left';
  }
}
