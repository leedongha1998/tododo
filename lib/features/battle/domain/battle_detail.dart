import '../data/battle.dart';
import '../data/battle_participant.dart';
import '../data/battle_submission.dart';
import 'battle_outcome.dart';
import 'judgment_progress.dart';
import 'judgment_rules.dart';

/// 대결 상세 화면이 쓰는 상태 판별 모음.
///
/// 승패는 서버(DB 함수)가 정한다. 여기서는 서버가 기록한 `status`, `winner_id`, `forfeited_by`,
/// 참가자 요약, 제출 행을 화면 분기용 이름으로 옮길 뿐 승패를 계산하지 않는다.
/// 품질전도 승자가 있으므로 결과 판별은 유형과 상관없이 같다.
class BattleDetail {
  const BattleDetail({
    required this.battle,
    required this.me,
    required this.opponent,
    required this.myName,
    required this.opponentName,
    this.submissions = const [],
  });

  final Battle battle;
  final BattleParticipant me;
  final BattleParticipant opponent;
  final String myName;
  final String opponentName;

  /// 서버가 내준 제출 행. 진행 중(제출 창)에는 내 것만 들어 있다(RLS가 상대 것을 막는다).
  /// 참가자당 한 행뿐이다(교체는 덮어쓰기).
  final List<BattleSubmission> submissions;

  /// 매칭된 뒤 종결 전. 속도전·품질전 모두 제출 창(active)과 판정 창(judging)을 거친다.
  bool get isOngoing => battle.status == 'active' || battle.status == 'judging';

  // 매칭된 대결에서 빠져나가는 유일한 길. 끝난 대결은 서버도 거부한다.
  bool get canForfeit => isOngoing;

  bool get didIForfeit => battle.forfeitedBy != null && battle.forfeitedBy == me.userId;

  bool get didOpponentForfeit =>
      battle.forfeitedBy != null && battle.forfeitedBy == opponent.userId;

  bool get isFinished => battle.status == 'finished';

  // finished는 서버 제약상 항상 승자가 있다(속도전·품질전·포기 공통).
  bool get didIWin => isFinished && battle.winnerId == me.userId;

  bool get didILose => isFinished && battle.winnerId != null && battle.winnerId != me.userId;

  // 속도전 유효한 완료 없음, 품질전 제출 없음·둘 다 기준 미달·우열 양쪽 미답.
  bool get isDraw => battle.status == 'draw';

  // AI 재판정이 끝내 실패해 승자 없이 끝난 대결. 점수·전적에 반영되지 않는다.
  bool get isVoided => battle.status == 'voided';

  bool get isSpeed => battle.type == 'speed';

  bool get isQuality => battle.type == 'quality';

  /// 상호 판정 창(두 유형 공통). AI 재판정은 이 안의 갈래다.
  bool get isJudging => battle.status == 'judging';

  /// 판정 기한(판정 창이 열린 시각 + 24시간). 서버가 창을 열 때 함께 기록한다.
  DateTime? get judgeDeadlineAt => battle.judgeDeadlineAt;

  /// 판정 기한이 지났는지. 지나면 미판정이 승인으로 간주되고 cron이 정리한다.
  bool isPastJudgeDeadline(DateTime now) {
    final deadline = battle.judgeDeadlineAt;
    return deadline != null && !deadline.isAfter(now);
  }

  /// 판정 창에서 지금 화면이 보여줄 단계. 판단은 전부 [judgmentStageOf] 순수 함수가 한다.
  JudgmentStage judgmentStageAt(DateTime now) => judgmentStageOf(
        status: battle.status,
        opponentSubmitted: opponent.hasSubmitted,
        iSubmitted: me.hasSubmitted,
        iJudged: me.hasJudged,
        opponentJudged: opponent.hasJudged,
        judgeDeadlineAt: battle.judgeDeadlineAt,
        now: now,
      );

  JudgmentStage get judgmentStage => judgmentStageAt(DateTime.now());

  /// 판정을 보낸 뒤·대기 단계의 진행 줄(내 판정 / 상대 판정 / AI 재판정). 판단은 [judgmentProgressOf] 순수 함수가 한다.
  List<JudgmentProgressRow> judgmentProgressAt(DateTime now) => judgmentProgressOf(
        stage: judgmentStageAt(now),
        iSubmitted: me.hasSubmitted,
        opponentJudged: opponent.hasJudged,
      );

  /// 내가 판정할 차례인지. 같은 검사를 서버(`submit_judgment`)가 다시 한다.
  bool get isMyJudgmentTurn => judgmentStage == JudgmentStage.myTurn;

  /// 품질전은 최소 기준과 우열을 한 번에 답해야 한다(없으면 서버가 `SUPERIORITY_REQUIRED`).
  bool get needsSuperiorityPick => isQuality;

  /// 참가 전에 공개된 우열 기준. 속도전은 비어 있다.
  List<String> get superiorityCriteria => battle.superiorityCriteria ?? const [];

  /// 품질전 판정의 한 줄 사유. 우열 AI 재판정이 확정될 때 함께 종결되므로 종결된 뒤에만 값이 있다.
  String? get verdictReason => battle.verdictReason;

  /// 서버가 내준 내 제출(참가자당 한 행). 아직 제출 전이면 null이다.
  BattleSubmission? get mySubmission =>
      submissions.where((submission) => submission.userId == me.userId).firstOrNull;

  /// 종결 뒤(또는 판정 창이 열린 뒤) 열리는 상대 제출. 그전에는 서버가 주지 않으므로 null이다.
  BattleSubmission? get opponentSubmission =>
      submissions.where((submission) => submission.userId == opponent.userId).firstOrNull;

  bool isPastDeadline(DateTime now) {
    final deadline = battle.deadlineAt;
    return deadline != null && !deadline.isAfter(now);
  }

  /// 사진을 낼 수 있는지(첫 제출이든 교체든). **활성화 판단이지 승패 계산이 아니다** —
  /// 같은 검사를 서버가 다시 한다.
  ///
  /// 속도전은 상태가 `active`인 동안 언제나 가능하다(이 상태에서는 양쪽이 모두 제출한 적이
  /// 없다는 것이 서버의 불변식이라, 내가 이미 냈어도 상대가 아직이면 교체로 받아들여진다).
  /// 품질전은 이미 냈으면 막힌다(재제출 없음).
  bool canSubmitEvidenceAt(DateTime now) {
    if (battle.status != 'active' || isPastDeadline(now)) return false;
    if (isSpeed) return true;
    return !me.hasSubmitted;
  }

  bool get canSubmitEvidence => canSubmitEvidenceAt(DateTime.now());

  /// 이미 냈고(교체가 아니라 처음 내는 것과 구분하는 문구용) 상대가 아직 내지 않아 바꿀 수 있는 상태.
  /// 마감이 지나면 서버가 `DEADLINE_PASSED`로 거부하므로 교체 자리도 닫는다.
  bool isReplacingEvidenceAt(DateTime now) =>
      isSpeed && me.hasSubmitted && canSubmitEvidenceAt(now);

  bool get isReplacingEvidence => isReplacingEvidenceAt(DateTime.now());

  /// 상대가 제출했는지. 사진·시각·통과 여부가 아니라 "냈다"는 사실만이다.
  bool get hasOpponentSubmitted => opponent.hasSubmitted;

  /// 종결 뒤(또는 판정 창이 열린 뒤)에만 양쪽 증거가 열린다. 서버(RLS)가 그 시점을 정한다 —
  /// 이 getter는 화면이 더 보여줄 것이 있는지 판단하는 데만 쓴다.
  bool get areSubmissionsRevealed =>
      battle.judgingOpenedAt != null ||
      const {'finished', 'draw', 'voided', 'cancelled', 'disputed'}.contains(battle.status);

  /// 이 대결이 나에게 어떤 결과였는지. 서버가 기록한 status·outcome을 옮길 뿐이다.
  BattleResult? get result => battleResultOf(
        status: battle.status,
        outcome: me.outcome,
        winnerId: battle.winnerId,
        myId: me.userId,
      );

  /// 서버가 점수 하한(0)까지 적용해 실제로 반영한 점수 변화. 무효·취소면 null이다.
  int? get myScoreDelta => me.scoreDeltaApplied;

  /// 속도전에서 졌지만 유효한 완료가 있는 경우(감점이 -3이 아니라 -1).
  /// 전적에는 그냥 "패"로 들어가고 차이는 점수에만 있다.
  bool get didICompleteButLose => me.outcome == 'completed_loss';

  /// 품질전에서 상대가 끝내 제출하지 않아 상호 판정도 AI 판정도 없이 이긴 경우.
  bool get didIWinByOpponentNoShow =>
      didIWin && isQuality && !didOpponentForfeit && !opponent.hasSubmitted;

  // ---------------------------------------------------------------------------
  // 연습 대결(봇전). 서버가 기록한 `is_bot` 하나에서 갈린다 — 봇의 uuid는 앱에 들어오지 않는다.
  // ---------------------------------------------------------------------------

  /// 연습 봇과의 대결. 판정 창에서 사용자에게 묻는 것이 없고 상대 전적도 없다.
  bool get isBot => battle.isBot;

  /// 판정 섹션(통과/불복·우열 버튼)을 그릴지. **봇전에서는 그리지 않는다** — 봇은 사진을 내지
  /// 않아 판정할 증거가 없고, 불복이라는 입력이 서버 어디에도 들어올 수 없어야 AI 재판정 경로가
  /// 닫힌다(봇전 1판의 AI 호출 0회가 그 기능의 합격선이다).
  bool get showsJudgmentQuestions => isJudging && !isBot;

  /// 상대의 전적 카드를 조회할지. 봇은 모든 사용자의 봇전이 한 마리에 쌓여 숫자에 뜻이 없고,
  /// 서버도 `get_player_card(봇)`을 거부한다(`BOT_NO_STATS`).
  bool get showsOpponentStats => !isBot;

  /// 봇의 완료 시각(종결 뒤에만 서버가 내준다). 그전에는 null이다 — 미리 보여 주면
  /// "그 1초 전에 내면 항상 이긴다"가 되어 대결이 계산 문제가 된다.
  DateTime? get botDoneAt => isBot ? opponentSubmission?.submittedAt : null;

  /// 내 사진이 "봇이 판정하지 않아 그대로 인정됐다"로 설명되는 상태.
  /// `verdict_source`를 새로 만들지 않고 기존 `auto`를 봇전 문구로 읽는다.
  bool get wasMySubmissionAutoApproved => isBot && mySubmission?.verdictSource == 'auto';

  /// 상세를 보고 있는 동안 주기적으로 다시 읽어야 하는 상태.
  ///
  /// 봇의 목표 시각이 지나면 승부는 이미 정해져 있지만 기록은 cron(최대 60초)이 쓴다. 그 구간을
  /// 줄이려면 다시 읽는 수밖에 없다 — **클라이언트는 그 시각을 모르므로**(그게 규칙이다)
  /// "그 시각에 한 번"이 불가능하다. 조건을 좁혀 내 사진을 이미 낸 봇전에서만 돈다.
  bool get needsBotSettlePolling => isBot && battle.status == 'active' && me.hasSubmitted;
}
