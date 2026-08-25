import 'package:flutter_test/flutter_test.dart';
import 'package:todododo/core/strings.dart';
import 'package:todododo/features/battle/data/battle.dart';
import 'package:todododo/features/profile/domain/battle_record.dart';

Battle _buildBattle({
  required String type,
  required String status,
  String? winnerId,
}) {
  return Battle(
    id: 'b1',
    type: type,
    status: status,
    title: '테스트 대결',
    creatorId: 'me',
    opponentId: 'friend',
    winnerId: winnerId,
    createdAt: DateTime(2026, 8, 20),
  );
}

void main() {
  group('BattleRecord.fromBattle 결과 라벨', () {
    test('속도전에서 내가 winner면 승리로 표시한다', () {
      final battle = _buildBattle(type: 'speed', status: 'finished', winnerId: 'me');
      final record = BattleRecord.fromBattle(battle, myId: 'me', otherPartyName: '친구');
      expect(record.resultLabel, AppStrings.battleRecordWin);
    });

    test('속도전에서 상대가 winner면 패배로 표시한다', () {
      final battle = _buildBattle(type: 'speed', status: 'finished', winnerId: 'friend');
      final record = BattleRecord.fromBattle(battle, myId: 'me', otherPartyName: '친구');
      expect(record.resultLabel, AppStrings.battleRecordLose);
    });

    test('품질전은 승자를 두지 않는다 — finished면 완료로만 표시한다', () {
      final battle = _buildBattle(type: 'quality', status: 'finished');
      final record = BattleRecord.fromBattle(battle, myId: 'me', otherPartyName: '친구');
      expect(record.resultLabel, AppStrings.battleStatusFinished);
    });

    test('품질전이 disputed면 미결로 표시한다', () {
      final battle = _buildBattle(type: 'quality', status: 'disputed');
      final record = BattleRecord.fromBattle(battle, myId: 'me', otherPartyName: '친구');
      expect(record.resultLabel, AppStrings.battleStatusDisputed);
    });

    test('otherPartyName과 battle은 그대로 보존된다', () {
      final battle = _buildBattle(type: 'speed', status: 'finished', winnerId: 'me');
      final record = BattleRecord.fromBattle(battle, myId: 'me', otherPartyName: '친구');
      expect(record.otherPartyName, '친구');
      expect(record.battle, same(battle));
    });
  });
}
