import 'package:flutter_test/flutter_test.dart';
import 'package:todododo/core/strings.dart';
import 'package:todododo/features/battle/domain/battle_outcome.dart';

/// 서버가 정한 값을 화면 결과 키로 옮기는 변환만 검사한다.
/// 승패 규칙 자체는 DB 순수 함수(`speed_outcome`, `quality_outcome`)와 그 SQL 테스트가 덮는다.
void main() {
  group('battleResultOf: outcome을 결과 키로 옮긴다', () {
    test('win은 승이다', () {
      expect(
        battleResultOf(status: 'finished', outcome: 'win', winnerId: 'me', myId: 'me'),
        BattleResult.win,
      );
    });

    // 감면(-1)은 점수에만 있고 전적에는 그냥 "패"다(spec 대결 결과 어휘).
    test('완료한 패배·기준 미달 패배·포기는 모두 패다', () {
      for (final outcome in ['completed_loss', 'loss', 'forfeit']) {
        expect(
          battleResultOf(status: 'finished', outcome: outcome, winnerId: 'friend', myId: 'me'),
          BattleResult.loss,
          reason: outcome,
        );
      }
    });

    test('draw는 무다', () {
      expect(battleResultOf(status: 'draw', outcome: 'draw', myId: 'me'), BattleResult.draw);
    });

    // "AI 판정이 실패했다"와 "시간이 다 됐다"는 다른 끝이다(spec: 둘을 합치지 말 것).
    test('voided는 무효이고 무승부와 구분된다', () {
      final result = battleResultOf(status: 'voided', myId: 'me');
      expect(result, BattleResult.voided);
      expect(result, isNot(BattleResult.draw));
    });

    test('아직 끝나지 않았거나 전적에 넣지 않는 대결에는 결과가 없다', () {
      for (final status in ['pending', 'active', 'judging', 'cancelled', 'disputed']) {
        expect(
          battleResultOf(status: status, winnerId: 'me', myId: 'me'),
          isNull,
          reason: status,
        );
      }
    });

    test('outcome을 함께 읽지 않은 자리에서는 서버가 적은 승자로 갈음한다', () {
      expect(
        battleResultOf(status: 'finished', winnerId: 'me', myId: 'me'),
        BattleResult.win,
      );
      expect(
        battleResultOf(status: 'finished', winnerId: 'friend', myId: 'me'),
        BattleResult.loss,
      );
    });
  });

  group('battleResultLabel', () {
    test('결과 키가 승/패/무/무효 라벨로 바뀐다', () {
      expect(battleResultLabel(BattleResult.win), AppStrings.battleRecordWin);
      expect(battleResultLabel(BattleResult.loss), AppStrings.battleRecordLose);
      expect(battleResultLabel(BattleResult.draw), AppStrings.battleRecordDraw);
      expect(battleResultLabel(BattleResult.voided), AppStrings.battleRecordVoided);
    });
  });
}
