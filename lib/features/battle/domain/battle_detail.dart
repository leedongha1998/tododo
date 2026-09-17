import 'dart:math';

import '../data/battle.dart';
import '../data/battle_participant.dart';
import '../data/battle_submission.dart';
import 'battle_outcome.dart';
import 'submission_rules.dart';

/// 대결 상세 화면이 쓰는 상태 판별 모음.
///
/// 승패는 AI 판정 사실로 서버(DB 함수)가 정한다. 여기서는 서버가 기록한 `status`,
/// `winner_id`, `forfeited_by`, 제출 행을 화면 분기용 이름으로 옮길 뿐 승패를 계산하지 않는다.
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

  /// 서버가 내준 제출 행. 진행 중에는 내 것만 들어 있다(RLS가 상대 것을 막는다).
  final List<BattleSubmission> submissions;

  /// 매칭된 뒤 종결 전. 속도전은 한쪽이 먼저 통과해도 여기에 속한다(spec "진행 중" 표시).
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

  // 속도전 아무도 통과 못 함, 품질전 제출 없음·둘 다 기준 미달.
  bool get isDraw => battle.status == 'draw';

  // AI 판정이 끝내 실패해 승자 없이 끝난 대결. 점수·전적에 반영되지 않는다.
  bool get isVoided => battle.status == 'voided';

  bool get isSpeed => battle.type == 'speed';

  bool get isQuality => battle.type == 'quality';

  /// 품질전 AI 판정 대기(두 사진이 모두 올라왔다). 속도전은 이 상태를 쓰지 않는다.
  bool get isQualityJudging => battle.status == 'judging';

  /// 품질전 판정의 한 줄 사유. 판정과 동시에 종결되므로 종결된 뒤에만 값이 있다.
  String? get verdictReason => battle.verdictReason;

  List<BattleSubmission> get mySubmissions =>
      submissions.where((submission) => submission.userId == me.userId).toList();

  /// AI 판정을 기다리는 내 제출. 있으면 새로 낼 수 없다(서버도 거부한다).
  bool get isMyJudgingInProgress => mySubmissions.any((submission) => submission.isJudging);

  /// 통과 여부는 서버 요약(passed_at)이 정답이고, 방금 돌아온 판정은 제출 행에 먼저 보인다.
  bool get didIPass =>
      me.passedAt != null || mySubmissions.any((submission) => submission.isPassed);

  /// 판정 사용 횟수(합격 + 불합격). AI 실패는 세지 않는다.
  int get myAttemptsUsed => max(
        me.attemptsUsed,
        mySubmissions.where((submission) => submission.countsTowardAttempts).length,
      );

  int get myAttemptsLeft => max(speedJudgeMaxAttempts - myAttemptsUsed, 0);

  bool get didIUseAllAttempts => myAttemptsLeft == 0;

  /// 통과했거나 판정 횟수를 다 썼다. 두 경우 모두 이 대결에서 더 낼 수 없다(속도전).
  bool get isMySubmissionLocked => didIPass || didIUseAllAttempts;

  /// 품질전 내 제출. 한 번뿐이고 재제출 수단이 없다(결정 14).
  bool get hasMyQualitySubmission =>
      mySubmissions.any((submission) => submission.status == 'submitted');

  bool isPastDeadline(DateTime now) {
    final deadline = battle.deadlineAt;
    return deadline != null && !deadline.isAfter(now);
  }

  /// 사진을 낼 수 있는지. **활성화 판단이지 승패 계산이 아니다** — 같은 검사를 서버가 다시 한다.
  ///
  /// 속도전은 통과·판정 중·5회 소진이면 막히고, 품질전은 이미 냈으면 막힌다.
  /// 품질전이 `judging`이면 status 검사에서 걸린다(두 사진이 다 올라와 판정 중이다).
  bool canSubmitEvidenceAt(DateTime now) {
    if (battle.status != 'active' || isPastDeadline(now)) return false;
    if (isSpeed) return !isMySubmissionLocked && !isMyJudgingInProgress;
    return !hasMyQualitySubmission;
  }

  bool get canSubmitEvidence => canSubmitEvidenceAt(DateTime.now());

  /// 상대가 한 번이라도 제출했는지. 사진·사유가 아니라 "냈다"는 사실만이다.
  bool get hasOpponentSubmitted => opponent.firstSubmittedAt != null;

  /// 진행 중 상대에게 공개되는 속도전 판정 결과(사유 없음).
  String? get opponentLastVerdict => opponent.lastVerdict;

  /// 종결된 뒤에만 양쪽 증거와 사유가 열린다.
  bool get areSubmissionsRevealed => !isOngoing && battle.status != 'pending';

  /// 종결 뒤 열린 상대 제출. 진행 중에는 서버가 주지 않으므로 항상 비어 있다.
  List<BattleSubmission> get opponentSubmissions =>
      submissions.where((submission) => submission.userId == opponent.userId).toList();

  /// 이 대결이 나에게 어떤 결과였는지. 서버가 기록한 status·outcome을 옮길 뿐이다.
  BattleResult? get result => battleResultOf(
        status: battle.status,
        outcome: me.outcome,
        winnerId: battle.winnerId,
        myId: me.userId,
      );

  /// 서버가 점수 하한(0)까지 적용해 실제로 반영한 점수 변화. 무효·취소면 null이다.
  int? get myScoreDelta => me.scoreDeltaApplied;

  /// 속도전에서 졌지만 마감 전에 기준을 통과한 경우(감점이 -3이 아니라 -1).
  /// 전적에는 그냥 "패"로 들어가고 차이는 점수에만 있다.
  bool get didICompleteButLose => me.outcome == 'completed_loss';

  /// 품질전에서 상대가 끝내 제출하지 않아 AI 판정 없이 이긴 경우.
  bool get didIWinByOpponentNoShow =>
      didIWin && isQuality && !didOpponentForfeit && opponent.firstSubmittedAt == null;
}
