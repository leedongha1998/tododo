import 'dart:math';

import '../data/battle.dart';
import '../data/battle_participant.dart';
import '../data/battle_submission.dart';
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

  /// 통과했거나 판정 횟수를 다 썼다. 두 경우 모두 이 대결에서 더 낼 수 없다.
  bool get isMySubmissionLocked => didIPass || didIUseAllAttempts;

  bool isPastDeadline(DateTime now) {
    final deadline = battle.deadlineAt;
    return deadline != null && !deadline.isAfter(now);
  }

  /// 사진을 낼 수 있는지. **활성화 판단이지 승패 계산이 아니다** — 같은 검사를 서버가 다시 한다.
  /// 품질전은 두 사진을 비교하는 판정 잡이 붙기 전까지 제출을 열지 않는다.
  bool canSubmitEvidenceAt(DateTime now) {
    return isSpeed &&
        battle.status == 'active' &&
        !isPastDeadline(now) &&
        !isMySubmissionLocked &&
        !isMyJudgingInProgress;
  }

  bool get canSubmitEvidence => canSubmitEvidenceAt(DateTime.now());

  /// 상대가 한 번이라도 제출했는지. 사진·사유가 아니라 "냈다"는 사실만이다.
  bool get hasOpponentSubmitted => opponent.firstSubmittedAt != null;

  /// 진행 중 상대에게 공개되는 속도전 판정 결과(사유 없음).
  String? get opponentLastVerdict => opponent.lastVerdict;

  /// 종결된 뒤에만 양쪽 증거와 사유가 열린다.
  bool get areSubmissionsRevealed => !isOngoing && battle.status != 'pending';
}
