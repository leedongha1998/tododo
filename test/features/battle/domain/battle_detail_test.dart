import 'package:flutter_test/flutter_test.dart';
import 'package:todododo/features/battle/data/battle.dart';
import 'package:todododo/features/battle/data/battle_participant.dart';
import 'package:todododo/features/battle/domain/battle_detail.dart';

BattleDetail _buildDetail({
  required String type,
  required String status,
  String? winnerId,
  String? forfeitedBy,
  String? myOutcome,
  String? opponentOutcome,
}) {
  final battle = Battle(
    id: 'b1',
    type: type,
    status: status,
    title: '테스트 대결',
    creatorId: 'me',
    opponentId: 'friend',
    winnerId: winnerId,
    createdAt: DateTime(2026, 9, 15),
    forfeitedBy: forfeitedBy,
  );
  return BattleDetail(
    battle: battle,
    me: BattleParticipant(battleId: 'b1', userId: 'me', outcome: myOutcome),
    opponent: BattleParticipant(battleId: 'b1', userId: 'friend', outcome: opponentOutcome),
    myName: '나',
    opponentName: '친구',
  );
}

const _types = ['speed', 'quality'];

void main() {
  group('진행 중 여부와 포기 가능', () {
    for (final type in _types) {
      test('$type: active와 judging은 진행 중이고 포기할 수 있다', () {
        for (final status in ['active', 'judging']) {
          final detail = _buildDetail(type: type, status: status);
          expect(detail.isOngoing, isTrue, reason: status);
          expect(detail.canForfeit, isTrue, reason: status);
        }
      });

      test('$type: 모집 중이거나 종결된 대결은 진행 중이 아니고 포기할 수 없다', () {
        for (final status in ['pending', 'finished', 'draw', 'voided', 'cancelled', 'disputed']) {
          final detail = _buildDetail(type: type, status: status, winnerId: 'me');
          expect(detail.isOngoing, isFalse, reason: status);
          expect(detail.canForfeit, isFalse, reason: status);
        }
      });
    }

    test('속도전에서 한쪽이 먼저 통과해도 서버가 종결하기 전까지는 진행 중이다', () {
      final detail = _buildDetail(type: 'speed', status: 'active');
      expect(detail.isOngoing, isTrue);
      expect(detail.didIWin, isFalse);
      expect(detail.didILose, isFalse);
    });
  });

  // 품질전도 승자가 있다. 승패는 서버가 기록한 winner_id를 그대로 읽는다.
  group('승패 판별 (유형 공통)', () {
    for (final type in _types) {
      test('$type: finished이고 내가 winner면 승리다', () {
        final detail = _buildDetail(type: type, status: 'finished', winnerId: 'me');
        expect(detail.isFinished, isTrue);
        expect(detail.didIWin, isTrue);
        expect(detail.didILose, isFalse);
      });

      test('$type: finished이고 상대가 winner면 패배다', () {
        final detail = _buildDetail(type: type, status: 'finished', winnerId: 'friend');
        expect(detail.didIWin, isFalse);
        expect(detail.didILose, isTrue);
      });

      test('$type: 무승부는 승패 어느 쪽도 아니다', () {
        final detail = _buildDetail(type: type, status: 'draw');
        expect(detail.isDraw, isTrue);
        expect(detail.isVoided, isFalse);
        expect(detail.didIWin, isFalse);
        expect(detail.didILose, isFalse);
      });

      test('$type: 무효는 무승부와 구분되고 승패 어느 쪽도 아니다', () {
        final detail = _buildDetail(type: type, status: 'voided');
        expect(detail.isVoided, isTrue);
        expect(detail.isDraw, isFalse);
        expect(detail.didIWin, isFalse);
        expect(detail.didILose, isFalse);
      });
    }

    test('속도전 완료한 패배도 결과 판별은 패배다(감면은 점수에만)', () {
      final detail = _buildDetail(
        type: 'speed',
        status: 'finished',
        winnerId: 'friend',
        myOutcome: 'completed_loss',
        opponentOutcome: 'win',
      );
      expect(detail.didILose, isTrue);
      expect(detail.me.outcome, 'completed_loss');
    });
  });

  // 매칭된 대결에서 빠져나가는 유일한 길. 유형과 상관없이 포기한 쪽이 진다.
  group('포기(기권) 판별', () {
    for (final type in _types) {
      test('$type: 내가 기권하면 상대 승리로 끝난다', () {
        final detail = _buildDetail(
          type: type,
          status: 'finished',
          winnerId: 'friend',
          forfeitedBy: 'me',
          myOutcome: 'forfeit',
          opponentOutcome: 'win',
        );
        expect(detail.didIForfeit, isTrue);
        expect(detail.didOpponentForfeit, isFalse);
        expect(detail.didILose, isTrue);
      });

      test('$type: 상대가 기권하면 내 승리로 끝난다', () {
        final detail = _buildDetail(
          type: type,
          status: 'finished',
          winnerId: 'me',
          forfeitedBy: 'friend',
          myOutcome: 'win',
          opponentOutcome: 'forfeit',
        );
        expect(detail.didOpponentForfeit, isTrue);
        expect(detail.didIForfeit, isFalse);
        expect(detail.didIWin, isTrue);
      });
    }

    test('기권 없이 끝난 대결은 기권 판별에 걸리지 않는다', () {
      final detail = _buildDetail(type: 'speed', status: 'finished', winnerId: 'me');
      expect(detail.didIForfeit, isFalse);
      expect(detail.didOpponentForfeit, isFalse);
    });
  });
}
