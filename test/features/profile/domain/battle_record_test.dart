import 'package:flutter_test/flutter_test.dart';
import 'package:todododo/core/strings.dart';
import 'package:todododo/features/battle/data/battle.dart';
import 'package:todododo/features/battle/domain/battle_outcome.dart';
import 'package:todododo/features/profile/domain/battle_record.dart';

Battle _buildBattle({
  required String type,
  required String status,
  String? winnerId,
  String? forfeitedBy,
}) {
  return Battle(
    id: 'b1',
    type: type,
    status: status,
    title: '테스트 대결',
    creatorId: 'me',
    opponentId: 'friend',
    winnerId: winnerId,
    forfeitedBy: forfeitedBy,
    createdAt: DateTime(2026, 9, 15),
  );
}

BattleRecord? _record(Battle battle, {String? outcome}) =>
    BattleRecord.fromBattle(battle, myId: 'me', otherPartyName: '친구', outcome: outcome);

String? _label(Battle battle, {String? outcome}) => _record(battle, outcome: outcome)?.resultLabel;

void main() {
  group('BattleRecord.fromBattle 결과 라벨', () {
    // 품질전도 승자가 있으므로 두 유형 모두 승/패로 표시한다.
    for (final type in ['speed', 'quality']) {
      test('$type: 서버가 적은 outcome이 win이면 승이다', () {
        final battle = _buildBattle(type: type, status: 'finished', winnerId: 'me');
        expect(_label(battle, outcome: 'win'), AppStrings.battleRecordWin);
      });

      test('$type: outcome이 loss면 패다', () {
        final battle = _buildBattle(type: type, status: 'finished', winnerId: 'friend');
        expect(_label(battle, outcome: 'loss'), AppStrings.battleRecordLose);
      });

      test('$type: 내가 포기해서 끝난 대결은 패다', () {
        final battle = _buildBattle(
          type: type,
          status: 'finished',
          winnerId: 'friend',
          forfeitedBy: 'me',
        );
        expect(_label(battle, outcome: 'forfeit'), AppStrings.battleRecordLose);
      });

      test('$type: 무승부는 무다', () {
        final battle = _buildBattle(type: type, status: 'draw');
        expect(_label(battle, outcome: 'draw'), AppStrings.battleRecordDraw);
      });

      test('$type: AI 판정 실패로 끝난 대결은 무승부와 구분해 무효로 표시한다', () {
        final label = _label(_buildBattle(type: type, status: 'voided'));
        expect(label, AppStrings.battleRecordVoided);
        expect(label, isNot(AppStrings.battleRecordDraw));
      });
    }

    // 감면은 점수에만 있다. 전적 목록에서는 그냥 "패"로 센다(spec 대결 결과 어휘).
    test('속도전 완료한 패배도 전적에서는 패다', () {
      final battle = _buildBattle(type: 'speed', status: 'finished', winnerId: 'friend');
      final record = _record(battle, outcome: 'completed_loss');
      expect(record!.result, BattleResult.loss);
      expect(record.resultLabel, AppStrings.battleRecordLose);
    });

    test('outcome을 읽지 못해도 서버가 적은 승자로 라벨을 고른다', () {
      final battle = _buildBattle(type: 'speed', status: 'finished', winnerId: 'me');
      expect(_label(battle), AppStrings.battleRecordWin);
    });

    // 취소·진행 중 대결은 기록 목록에 들어가지 않는다.
    test('결과가 없는 대결은 기록으로 만들지 않는다', () {
      for (final status in ['pending', 'active', 'judging', 'cancelled']) {
        expect(_record(_buildBattle(type: 'speed', status: status)), isNull, reason: status);
      }
    });

    test('otherPartyName과 battle은 그대로 보존된다', () {
      final battle = _buildBattle(type: 'speed', status: 'finished', winnerId: 'me');
      final record = _record(battle, outcome: 'win');
      expect(record!.otherPartyName, '친구');
      expect(record.battle, same(battle));
    });
  });
}
