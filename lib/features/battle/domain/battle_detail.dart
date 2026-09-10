import '../data/battle.dart';
import '../data/battle_participant.dart';

/// 대결 상세 화면이 쓰는 상태 판별 모음.
///
/// 속도전/품질전 모두 "양쪽이 각자 증거를 제출하고 서로의 증거를 approve/dispute한다"는
/// 절차를 공유하므로, 아래 getter들도 대부분 유형 공통이다. 유형에 따라 갈리는 것은
/// 필수 증거 종류(품질전은 사진 필수)와 결과 표시(속도전만 승자가 있다)뿐이다.
///
/// 승패 자체는 서버가 계산한 `winner_id`/`status`를 읽기만 한다 — 여기서 계산하지 않는다.
class BattleDetail {
  const BattleDetail({
    required this.battle,
    required this.me,
    required this.opponent,
    required this.myName,
    required this.opponentName,
  });

  final Battle battle;
  final BattleParticipant me;
  final BattleParticipant opponent;
  final String myName;
  final String opponentName;

  bool get isOngoing => battle.status == 'active' || battle.status == 'judging';

  bool get _isOngoing => isOngoing;

  // 품질전은 사진 없이는 증거로 인정하지 않는다. 속도전은 사진 또는 텍스트 중 최소 하나.
  bool get requiresPhotoEvidence => battle.type == 'quality';

  bool get hasSubmittedEvidence => me.evidenceSubmittedAt != null;

  // 아직 한 번도 제출하지 않았고 제출 가능한 상태인지.
  bool get canSubmitEvidence => _isOngoing && !hasSubmittedEvidence;

  // 재제출은 판정 전이든 이의제기당한 뒤든 항상 허용된다(실수로 잘못 올린 증거 복구용).
  // 다만 제출 시각이 갱신되므로 속도전에서는 승부 기준 시각이 밀린다.
  bool get canResubmitEvidence => _isOngoing && hasSubmittedEvidence;

  // 내 증거에 대한 상대의 판정을 기다리는 중인지.
  bool get isWaitingMyEvidenceDecision => hasSubmittedEvidence && me.decision == null;

  bool get wasMyEvidenceApproved => me.decision == 'approve';

  // 이의제기당하면 내 완료는 무효가 된다(속도전이면 승부에서 빠진다).
  bool get wasMyEvidenceDisputed => me.decision == 'dispute';

  bool get wasOpponentEvidenceDisputed => opponent.decision == 'dispute';

  bool get isWaitingOpponentSubmit => _isOngoing && opponent.evidenceSubmittedAt == null;

  // 상대 증거를 내가 아직 판정하지 않았는지. 종결된 대결은 서버도 판정을 거부하므로 제외한다.
  bool get canReviewOpponentEvidence =>
      battle.status == 'judging' &&
      opponent.evidenceSubmittedAt != null &&
      opponent.decision == null;

  // 속도전 전용: 내 판정은 끝났지만 상대가 아직 내 증거를 판정하지 않아 결과가 미확정인 상태.
  // 이 안내가 없으면 "이의제기를 눌렀는데 왜 안 끝나지?"라고 느끼게 된다.
  bool get isAwaitingBothDecisions =>
      battle.type == 'speed' &&
      battle.status == 'judging' &&
      opponent.decision != null &&
      me.decision == null;

  // 매칭된 대결에서 빠져나가는 유일한 길. 끝난 대결은 서버도 거부한다.
  bool get canForfeit => _isOngoing;

  bool get didIForfeit => battle.forfeitedBy == me.userId;

  bool get didOpponentForfeit => battle.forfeitedBy == opponent.userId;

  bool get isFinished => battle.status == 'finished';

  bool get isDisputed => battle.status == 'disputed';

  // 마감까지 아무도 유효한 완료를 만들지 못한 경우. 서버가 정하고 여기서는 읽기만 한다.
  bool get isDraw => battle.status == 'draw';

  bool get isQualityFinished => battle.type == 'quality' && isFinished;

  // 속도전에서 disputed는 양쪽 다 이의제기당해 유효한 완료가 하나도 없는 경우뿐이다.
  bool get isSpeedDisputed => battle.type == 'speed' && isDisputed;

  bool get didIWinSpeedBattle =>
      battle.type == 'speed' && isFinished && battle.winnerId == me.userId;

  bool get didILoseSpeedBattle =>
      battle.type == 'speed' &&
      isFinished &&
      battle.winnerId != null &&
      battle.winnerId != me.userId;
}
