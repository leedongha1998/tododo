import 'package:flutter_test/flutter_test.dart';
import 'package:todododo/core/strings.dart';
import 'package:todododo/features/battle/data/battle.dart';
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

String _label(Battle battle) =>
    BattleRecord.fromBattle(battle, myId: 'me', otherPartyName: '친구').resultLabel;

void main() {
  group('BattleRecord.fromBattle 결과 라벨', () {
    // 품질전도 승자가 있으므로 두 유형 모두 승/패로 표시한다.
    for (final type in ['speed', 'quality']) {
      test('$type: 내가 winner면 승이다', () {
        expect(_label(_buildBattle(type: type, status: 'finished', winnerId: 'me')),
            AppStrings.battleRecordWin);
      });

      test('$type: 상대가 winner면 패다', () {
        expect(_label(_buildBattle(type: type, status: 'finished', winnerId: 'friend')),
            AppStrings.battleRecordLose);
      });

      test('$type: 내가 포기해서 끝난 대결은 패다', () {
        final battle = _buildBattle(
          type: type,
          status: 'finished',
          winnerId: 'friend',
          forfeitedBy: 'me',
        );
        expect(_label(battle), AppStrings.battleRecordLose);
      });

      test('$type: 무승부는 무다', () {
        expect(_label(_buildBattle(type: type, status: 'draw')), AppStrings.battleRecordDraw);
      });

      test('$type: AI 판정 실패로 끝난 대결은 무승부와 구분해 무효로 표시한다', () {
        final label = _label(_buildBattle(type: type, status: 'voided'));
        expect(label, AppStrings.battleRecordVoided);
        expect(label, isNot(AppStrings.battleRecordDraw));
      });
    }

    test('otherPartyName과 battle은 그대로 보존된다', () {
      final battle = _buildBattle(type: 'speed', status: 'finished', winnerId: 'me');
      final record = BattleRecord.fromBattle(battle, myId: 'me', otherPartyName: '친구');
      expect(record.otherPartyName, '친구');
      expect(record.battle, same(battle));
    });
  });
}
