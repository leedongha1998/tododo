import '../../../core/strings.dart';
import 'criteria_rules.dart';

/// 연습 대결(봇전)에서 화면이 고르는 문구 매핑. **서버가 정한 값을 글자로 바꿀 뿐이고 승패를
/// 계산하지 않는다** — 들어오는 `outcome`·오류 코드는 전부 서버가 기록·반환한 것이다.

/// 결과 배너의 부제. 봇전은 완료한 패배와 미착수가 같은 점수(-1)라 **점수로는 구분되지 않으므로**
/// 문장이 그 차이를 말한다. 포기는 사람 대결과 같은 문구를 쓰므로 여기서 다루지 않는다(null).
String? botResultSubtitle(String? outcome) {
  return switch (outcome) {
    'win' => AppStrings.botBattleWon,
    'completed_loss' => AppStrings.botBattleCompletedLoss,
    'loss' => AppStrings.botBattleLossNoSubmission,
    _ => null,
  };
}

/// 시작 실패의 사용자 문구. 서버 메시지를 그대로 보여 주지 않는다.
String botBattleStartErrorMessage(Object error) {
  return switch (errorCodeOf(error)) {
    'BOT_DAILY_LIMIT' => AppStrings.botBattleErrorDailyLimit,
    'BOT_TOPIC_INVALID' => AppStrings.botBattleErrorTopicInvalid,
    _ => AppStrings.botBattleStartFailed,
  };
}

/// 서버가 포기를 거부한 이유가 "그 사이에 결과가 확정됐다"인가.
///
/// 봇전에는 "봇의 목표 시각은 지났는데 아직 정산되지 않은" 어긋남 구간이 있고(cron 1분 +
/// 화면의 깨우기), 그 구간에 들어올 수 있는 판은 **사용자가 그 시각 전에 제출한 판뿐이라
/// 결과가 언제나 승리다.** 그래서 `forfeit_battle`이 포기 전에 먼저 정산하고 이 힌트로 거부한다 —
/// 거부가 없으면 확정된 승리(+1)가 포기 패배(-1)로 뒤집힌다(reviewer W1).
bool isBotAlreadySettled(Object error) => errorCodeOf(error) == 'BOT_ALREADY_SETTLED';

/// 봇전 포기 실패의 사용자 문구. 위 거부는 실패가 아니라 사실이므로 다른 문장을 쓴다.
String botBattleForfeitErrorMessage(Object error) {
  return isBotAlreadySettled(error)
      ? AppStrings.botBattleAlreadySettled
      : AppStrings.battleForfeitFailed;
}
