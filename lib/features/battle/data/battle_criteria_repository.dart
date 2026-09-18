import 'package:supabase_flutter/supabase_flutter.dart';

import 'criteria_check_result.dart';

/// Edge Function이 오류 코드로 알려 준 실패. 앱은 코드로 문구를 고른다.
class CriteriaException implements Exception {
  const CriteriaException(this.code, {this.callsLeft});

  final String code;

  /// AI 실패·한도 초과 응답이 함께 준 남은 횟수(모르면 null).
  final int? callsLeft;

  @override
  String toString() => 'CriteriaException($code)';
}

/// 판정 기준 생성·재검사. Gemini 호출은 Edge Function 안에서만 일어난다 —
/// 앱은 키도, 모델명도, 프롬프트도 모른다.
class BattleCriteriaRepository {
  BattleCriteriaRepository(this._client);

  static const _functionName = 'battle-criteria';

  final SupabaseClient _client;

  /// 제목·유형·기간으로 기준을 만든다(하루 10회에 1회 산입, 실패는 미산입).
  Future<CriteriaCheckResult> generate({
    required String title,
    required String type,
    required int durationMinutes,
  }) {
    return _invoke({
      'action': 'generate',
      'title': title,
      'type': type,
      'duration_minutes': durationMinutes,
    });
  }

  /// 사용자가 고친 기준을 다시 검사한다. 품질전이면 두 목록을 함께 보내 한 호출로 검사한다.
  /// [battleId]가 있으면 모집 중 대결의 기준 수정이다.
  Future<CriteriaCheckResult> check({
    required String title,
    required String type,
    required int durationMinutes,
    required List<String> minCriteria,
    List<String>? superiorityCriteria,
    String? battleId,
  }) {
    return _invoke({
      'action': 'check',
      'title': title,
      'type': type,
      'duration_minutes': durationMinutes,
      'min_criteria': minCriteria,
      if (type == 'quality') 'superiority_criteria': superiorityCriteria,
      // 모집 중 기준 수정일 때만 담는다(null이면 항목 자체가 빠진다).
      'battle_id': ?battleId,
    });
  }

  Future<CriteriaCheckResult> _invoke(Map<String, dynamic> body) async {
    try {
      final response = await _client.functions.invoke(_functionName, body: body);
      return CriteriaCheckResult.fromMap(Map<String, dynamic>.from(response.data as Map));
    } on FunctionException catch (error) {
      // 함수가 4xx/5xx면 본문의 {error: CODE}로 분기한다.
      final details = error.details;
      if (details is Map) {
        final code = details['error'];
        if (code is String) {
          final callsLeft = details['calls_left'];
          return Future.error(
            CriteriaException(code, callsLeft: callsLeft is num ? callsLeft.toInt() : null),
          );
        }
      }
      return Future.error(const CriteriaException('SERVER_ERROR'));
    }
  }
}
