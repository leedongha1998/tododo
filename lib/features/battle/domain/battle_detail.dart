import '../data/battle.dart';
import '../data/battle_participant.dart';
import '../data/battle_submission.dart';
import 'battle_outcome.dart';

/// 대결 상세 화면이 쓰는 상태 판별 모음.
///
/// 승패는 참가자 판정·AI 재판정이라는 사실로 서버(DB 함수)가 정한다. 여기서는 서버가 기록한
/// `status`, `winner_id`, `forfeited_by`, 요약·제출 행을 화면 분기용 이름으로 옮길 뿐 승패를 계산하지 않는다.
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

  /// 서버가 내준 제출 행. 판정 창 전에는 내 것만 들어 있다(RLS가 상대 것을 막는다).
  final List<BattleSubmission> submissions;

  /// 매칭된 뒤 종결 전(제출 창 + 판정 창).
  bool get isOngoing => battle.status == 'active' || battle.status == 'judging';

  // 매칭된 대결에서 빠져나가는 유일한 길. 판정 창에서도 포기할 수 있다. 끝난 대결은 서버도 거부한다.
  bool get canForfeit => isOngoing;

  bool get didIForfeit => battle.forfeitedBy != null && battle.forfeitedBy == me.userId;

  bool get didOpponentForfeit =>
      battle.forfeitedBy != null && battle.forfeitedBy == opponent.userId;

  bool get isFinished => battle.status == 'finished';

  // finished는 서버 제약상 항상 승자가 있다(속도전·품질전·포기 공통).
  bool get didIWin => isFinished && battle.winnerId == me.userId;

  bool get didILose => isFinished && battle.winnerId != null && battle.winnerId != me.userId;

  // 유효한 완료가 없음, 아무도 제출하지 않음, 품질전 우열을 아무도 판정하지 않음.
  bool get isDraw => battle.status == 'draw';

  // 불복·불일치 AI 재판정이 끝내 실패해 승자 없이 끝난 대결. 점수·전적에 반영되지 않는다.
  bool get isVoided => battle.status == 'voided';

  bool get isSpeed => battle.type == 'speed';

  bool get isQuality => battle.type == 'quality';

  /// 제출 창(사진을 내고, 속도전이면 바꾸는 구간).
  bool get isSubmissionWindow => battle.status == 'active';

  /// 판정 창(양쪽 증거가 공개되고 참가자가 판정하는 구간). 두 유형 공통이다.
  bool get isJudgingWindow => battle.status == 'judging';

  /// 우열 AI 재판정의 한 줄 사유. 종결된 뒤에만 값이 있다.
  String? get verdictReason => battle.verdictReason;

  /// 내 제출(참가자당 한 행). 아직 내지 않았으면 null.
  BattleSubmission? get mySubmission => _submissionOf(me.userId);

  /// 상대 제출. 판정 창 전에는 서버가 주지 않으므로 항상 null이다.
  BattleSubmission? get opponentSubmission => _submissionOf(opponent.userId);

  BattleSubmission? _submissionOf(String userId) {
    for (final submission in submissions) {
      if (submission.userId == userId) return submission;
    }
    return null;
  }

  /// 방금 낸 제출은 요약보다 제출 행에 먼저 보일 수 있어 둘 다 본다.
  bool get hasMySubmission => me.hasSubmitted || mySubmission != null;

  /// 상대가 제출했는지. 사진·시각이 아니라 "냈다"는 사실만이다.
  bool get hasOpponentSubmitted => opponent.hasSubmitted;

  bool isPastDeadline(DateTime now) {
    final deadline = battle.deadlineAt;
    return deadline != null && !deadline.isAfter(now);
  }

  /// 첫 사진을 낼 수 있는지. **활성화 판단이지 승패 계산이 아니다** — 같은 검사를 서버가 다시 한다.
  bool canSubmitEvidenceAt(DateTime now) {
    if (!isSubmissionWindow || isPastDeadline(now)) return false;
    return !hasMySubmission;
  }

  bool get canSubmitEvidence => canSubmitEvidenceAt(DateTime.now());

  /// 낸 사진을 바꿀 수 있는지. 속도전에서 상대가 아직 내지 않은 동안만이고, 품질전에는 교체가 없다.
  /// 상대가 제출하는 순간 판정 창이 열려 내 사진도 잠긴다.
  bool canReplaceEvidenceAt(DateTime now) {
    if (!isSpeed || !isSubmissionWindow || isPastDeadline(now)) return false;
    return hasMySubmission && !hasOpponentSubmitted;
  }

  bool get canReplaceEvidence => canReplaceEvidenceAt(DateTime.now());

  /// 판정 창에서 내가 판정할 상대 증거가 있는지. 속도전에서 상대가 내지 않고 마감되면 없다.
  bool get hasSomethingToJudge => isJudgingWindow && hasOpponentSubmitted;

  /// 판정 창에서 내 판정이 남았는지.
  bool get isMyJudgmentDue => hasSomethingToJudge && !me.hasJudged;

  /// 판정 창이 열린 뒤 또는 종결 뒤에는 서버가 양쪽 제출을 내준다.
  bool get areSubmissionsRevealed => battle.status != 'pending' && battle.status != 'active';

  /// 이 대결이 나에게 어떤 결과였는지. 서버가 기록한 status·outcome을 옮길 뿐이다.
  BattleResult? get result => battleResultOf(
        status: battle.status,
        outcome: me.outcome,
        winnerId: battle.winnerId,
        myId: me.userId,
      );

  /// 서버가 점수 하한(0)까지 적용해 실제로 반영한 점수 변화. 무효·취소면 null이다.
  int? get myScoreDelta => me.scoreDeltaApplied;

  /// 속도전에서 졌지만 유효한 완료를 인정받은 경우(감점이 -3이 아니라 -1).
  /// 전적에는 그냥 "패"로 들어가고 차이는 점수에만 있다.
  bool get didICompleteButLose => me.outcome == 'completed_loss';

  /// 품질전에서 상대가 끝내 제출하지 않아 판정 없이 이긴 경우.
  bool get didIWinByOpponentNoShow =>
      didIWin && isQuality && !didOpponentForfeit && !opponent.hasSubmitted;
}
