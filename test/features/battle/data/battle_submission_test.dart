import 'package:flutter_test/flutter_test.dart';
import 'package:todododo/features/battle/data/battle_submission.dart';

void main() {
  test('사람 제출은 촬영 시각이 있다', () {
    final submission = BattleSubmission.fromMap({
      'id': 1,
      'battle_id': 'b1',
      'user_id': 'me',
      'object_path': 'b1/me/1.jpg',
      'captured_at': '2026-11-21T03:00:00.000Z',
      'submitted_at': '2026-11-21T03:01:00.000Z',
      'meets_criteria': true,
      'verdict_source': 'auto',
      'reason': null,
    });

    expect(submission.capturedAt, DateTime.utc(2026, 11, 21, 3));
    expect(submission.objectPath, 'b1/me/1.jpg');
  });

  test('봇 제출은 사진도 촬영 시각도 없다 — 그래도 읽을 수 있어야 한다', () {
    // 봇은 사진을 찍지 않으므로 서버가 두 칸을 null로 둔다(없는 것을 있는 것처럼 꾸미지 않는다).
    // 이 행은 **종결 뒤에 공개되므로**, 여기서 터지면 봇전 결과 화면이 통째로 오류 화면이 된다.
    final submission = BattleSubmission.fromMap({
      'id': 2,
      'battle_id': 'b1',
      'user_id': 'bot',
      'object_path': null,
      'captured_at': null,
      'submitted_at': '2026-11-21T03:07:00.000Z',
      'meets_criteria': true,
      'verdict_source': 'auto',
      'reason': null,
    });

    expect(submission.capturedAt, isNull);
    expect(submission.objectPath, isNull);
    // 승부 기준 시각은 서버가 찍은 제출 시각이고, 그것은 봇 행에도 늘 있다.
    expect(submission.submittedAt, DateTime.utc(2026, 11, 21, 3, 7));
  });
}
