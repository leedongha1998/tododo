/// 증거 사진 제출 한 건.
///
/// 진행 중에는 내 행만 읽힌다. 상대 행(사진 경로·판정 사유)은 대결이 종결된 뒤에야 서버가 내준다
/// — 화면에서 가리는 것이 아니라 RLS가 막는다.
class BattleSubmission {
  const BattleSubmission({
    required this.id,
    required this.battleId,
    required this.userId,
    this.objectPath,
    required this.capturedAt,
    required this.submittedAt,
    required this.status,
    this.reason,
    this.meetsCriteria,
  });

  final int id;
  final String battleId;
  final String userId;

  /// 증거 사진 경로. 제출자가 탈퇴하면 null이 된다.
  final String? objectPath;

  /// 앱이 보낸 촬영 시각. 서버가 수신 시각과 대조하는 데만 쓴다.
  final DateTime capturedAt;

  /// 서버 수신 시각. 속도전 승부 기준 시각이다.
  final DateTime submittedAt;

  /// `judging`(판정 중) / `passed` / `failed` / `error`(AI 실패) / `submitted`(품질전 접수).
  final String status;

  /// AI가 준 한 줄 사유. AI 실패면 없다.
  final String? reason;

  /// 품질전 1단계(최소 기준 충족) 결과.
  final bool? meetsCriteria;

  bool get isJudging => status == 'judging';

  bool get isPassed => status == 'passed';

  bool get isFailed => status == 'failed';

  /// AI 호출이 실패한 제출. 판정 5회 상한에 들어가지 않는다.
  bool get isError => status == 'error';

  bool get countsTowardAttempts => isPassed || isFailed;

  factory BattleSubmission.fromMap(Map<String, dynamic> map) => BattleSubmission(
        id: (map['id'] as num).toInt(),
        battleId: map['battle_id'] as String,
        userId: map['user_id'] as String,
        objectPath: map['object_path'] as String?,
        capturedAt: DateTime.parse(map['captured_at'] as String),
        submittedAt: DateTime.parse(map['submitted_at'] as String),
        status: map['status'] as String,
        reason: map['reason'] as String?,
        meetsCriteria: map['meets_criteria'] as bool?,
      );
}
