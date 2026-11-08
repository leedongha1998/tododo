import 'judgment_rules.dart';

/// 판정 진행 줄의 주체(design-judging-buttons 1C 확장형).
enum JudgmentProgressParty { me, opponent, ai }

/// 진행 줄 하나가 말하는 상태. **승패가 아니라** "판정을 보냈는가"만 말한다.
enum JudgmentProgressState {
  /// 판정을 보냈다. 상대 줄이면 무엇을 골랐는지는 보여 주지 않는다(서버가 주지 않는다).
  sent,

  /// 아직 보내지 않았다(기한 안).
  waiting,

  /// AI가 다시 보고 있다.
  reviewing,

  /// 상대가 사진을 내지 않아 내가 판정할 것이 없다.
  nothingToJudge,

  /// 내가 판정하지 않은 채 기한이 지났다(미판정 = 승인 간주는 패널 본문이 말한다).
  missedDeadline,
}

typedef JudgmentProgressRow = ({JudgmentProgressParty party, JudgmentProgressState state});

/// 판정을 보낸 뒤·대기 단계에서 진행 카드에 그릴 줄들. 위에서부터 내 판정 → 상대 판정 → AI 재판정.
///
/// 서버가 이미 준 값([stage]는 `judgmentStageOf`, `has_submitted`·`has_judged`)만 읽는다. 결론을 내지 않는다.
/// - 상대 줄은 상대가 판정할 대상(= 내 사진)이 있을 때만 그린다. 내가 내지 않았으면 상대는 판정할 것이 없어서
///   "기다리는 중"도 "보냈어요"도 사실이 아니다.
/// - AI 줄은 [JudgmentStage.waitingAi]에서만.
/// - 판정 창이 아니거나 내 차례면 빈 목록(진행 카드를 그리지 않는다).
List<JudgmentProgressRow> judgmentProgressOf({
  required JudgmentStage stage,
  required bool iSubmitted,
  required bool opponentJudged,
}) {
  final JudgmentProgressState mine;
  switch (stage) {
    case JudgmentStage.notOpen:
    case JudgmentStage.myTurn:
      return const [];
    case JudgmentStage.waitingOpponent:
    case JudgmentStage.waitingAi:
      mine = JudgmentProgressState.sent;
    case JudgmentStage.nothingToJudge:
      mine = JudgmentProgressState.nothingToJudge;
    case JudgmentStage.windowClosed:
      mine = JudgmentProgressState.missedDeadline;
  }

  return [
    (party: JudgmentProgressParty.me, state: mine),
    if (iSubmitted)
      (
        party: JudgmentProgressParty.opponent,
        state: opponentJudged ? JudgmentProgressState.sent : JudgmentProgressState.waiting,
      ),
    if (stage == JudgmentStage.waitingAi)
      (party: JudgmentProgressParty.ai, state: JudgmentProgressState.reviewing),
  ];
}
