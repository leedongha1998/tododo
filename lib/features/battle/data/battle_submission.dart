/// 증거 사진 제출 한 건. 참가자당 한 행이고, 속도전 교체는 이 행을 덮어쓴다.
///
/// 판정 창이 열리기 전에는 내 행만 읽힌다. 상대 행(사진 경로·제출 시각·결론)은 판정 창이 열리거나
/// 대결이 끝난 뒤에야 서버가 내준다 — 화면에서 가리는 것이 아니라 RLS가 막는다.
class BattleSubmission {
  const BattleSubmission({
    required this.id,
    required this.battleId,
    required this.userId,
    this.objectPath,
    required this.capturedAt,
    required this.submittedAt,
    this.meetsCriteria,
    this.verdictSource,
    this.reason,
  });

  final int id;
  final String battleId;
  final String userId;

  /// 증거 사진 경로. 제출자가 탈퇴하면 null이 된다.
  final String? objectPath;

  /// 앱이 보낸 촬영 시각. 서버가 수신 시각과 대조하는 데만 쓴다.
  final DateTime capturedAt;

  /// 서버 수신 시각. 속도전 승부 기준 시각이고, 교체하면 다시 찍힌다.
  final DateTime submittedAt;

  /// 최소 기준 결론. 아직 정해지지 않았으면 null이다.
  final bool? meetsCriteria;

  /// 결론을 누가 냈나: `opponent`(상대가 승인) / `auto`(판정 기한 경과) / `ai`(불복 후 AI).
  final String? verdictSource;

  /// AI 재판정의 한 줄 사유. 사람의 판정에는 사유가 없다.
  final String? reason;

  factory BattleSubmission.fromMap(Map<String, dynamic> map) => BattleSubmission(
        id: (map['id'] as num).toInt(),
        battleId: map['battle_id'] as String,
        userId: map['user_id'] as String,
        objectPath: map['object_path'] as String?,
        capturedAt: DateTime.parse(map['captured_at'] as String),
        submittedAt: DateTime.parse(map['submitted_at'] as String),
        meetsCriteria: map['meets_criteria'] as bool?,
        verdictSource: map['verdict_source'] as String?,
        reason: map['reason'] as String?,
      );
}
