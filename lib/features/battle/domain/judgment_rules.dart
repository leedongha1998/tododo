import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/strings.dart';

/// 판정 창(`judging`)에서 화면이 무엇을 보여줄지 가르는 단계.
///
/// **승패를 계산하지 않는다.** 서버가 기록한 값(`battles.status`·`judge_deadline_at`,
/// `battle_participants.has_submitted`·`has_judged`)만 보고 "지금 내가 할 일이 있는가"를 고른다.
/// 결론은 언제나 서버(`submit_judgment` → `resolve_battle`)가 낸다.
enum JudgmentStage {
  /// 판정 창이 아니다(모집·제출 창·종결). 판정 영역을 그리지 않는다.
  notOpen,

  /// 상대가 사진을 내지 않아 내가 판정할 증거가 없다(속도전 한쪽 제출의 제출자).
  /// 서버도 `NOTHING_TO_JUDGE`로 거부한다.
  nothingToJudge,

  /// 내가 판정할 차례다.
  myTurn,

  /// 판정 기한이 지났는데 내가 판정하지 않았다. 미판정은 승인으로 간주되고 cron이 정리한다.
  windowClosed,

  /// 내 판정은 보냈고 상대 판정을 기다린다.
  waitingOpponent,

  /// 양쪽 판정이 끝났는데 아직 `judging`이다 = 불복 건의 AI 재판정이 남았다.
  ///
  /// 추측이 아니다: `submit_judgment`가 마지막 판정과 같은 트랜잭션에서 `resolve_battle`을
  /// 부르므로, 양쪽이 판정했는데 종결되지 않은 경우는 결론이 `pending`인 경우뿐이다.
  waitingAi,
}

/// 위에서부터 먼저 맞는 줄이 단계가 된다(plan.md 4단계 "단계 판정 표").
JudgmentStage judgmentStageOf({
  required String status,
  required bool opponentSubmitted,
  required bool iSubmitted,
  required bool iJudged,
  required bool opponentJudged,
  required DateTime? judgeDeadlineAt,
  required DateTime now,
}) {
  if (status != 'judging') return JudgmentStage.notOpen;

  // 상대 증거가 없으면 내가 할 일이 없다. 내 증거에 대한 상대의 판정만 남아 있다.
  if (!opponentSubmitted) return JudgmentStage.nothingToJudge;

  final windowOpen = judgeDeadlineAt != null && judgeDeadlineAt.isAfter(now);

  if (!iJudged) {
    return windowOpen ? JudgmentStage.myTurn : JudgmentStage.windowClosed;
  }

  // 상대가 판정할 대상은 내 증거다. 내가 내지 않았으면 상대는 판정할 것이 없다.
  if (iSubmitted && !opponentJudged) return JudgmentStage.waitingOpponent;

  return JudgmentStage.waitingAi;
}

/// 서버가 준 오류 코드. RPC는 `PostgrestException.hint`로 코드를 보낸다.
String? judgmentErrorCodeOf(Object error) {
  if (error is PostgrestException) return error.hint;
  return null;
}

/// 오류 코드 → 사용자 문구. 서버 메시지를 그대로 보여 주지 않는다.
String judgmentErrorMessage(Object error) {
  return switch (judgmentErrorCodeOf(error)) {
    'JUDGING_NOT_OPEN' => AppStrings.battleErrorJudgingNotOpen,
    'JUDGE_WINDOW_CLOSED' => AppStrings.battleErrorJudgeWindowClosed,
    'ALREADY_JUDGED' => AppStrings.battleErrorAlreadyJudged,
    'NOTHING_TO_JUDGE' => AppStrings.battleErrorNothingToJudge,
    'SUPERIORITY_REQUIRED' => AppStrings.battleErrorSuperiorityRequired,
    _ => AppStrings.battleJudgmentSendFailed,
  };
}
