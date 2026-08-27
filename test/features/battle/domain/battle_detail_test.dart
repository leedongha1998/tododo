import 'package:flutter_test/flutter_test.dart';
import 'package:todododo/features/battle/data/battle.dart';
import 'package:todododo/features/battle/data/battle_participant.dart';
import 'package:todododo/features/battle/domain/battle_detail.dart';

BattleDetail _buildDetail({
  required String type,
  required String status,
  String? winnerId,
  DateTime? meEvidenceSubmittedAt,
  String? meDecision,
  DateTime? opponentEvidenceSubmittedAt,
  String? opponentDecision,
}) {
  final battle = Battle(
    id: 'b1',
    type: type,
    status: status,
    title: '테스트 대결',
    creatorId: 'me',
    opponentId: 'friend',
    winnerId: winnerId,
    createdAt: DateTime(2026, 8, 20),
  );
  return BattleDetail(
    battle: battle,
    me: BattleParticipant(
      battleId: 'b1',
      userId: 'me',
      evidenceSubmittedAt: meEvidenceSubmittedAt,
      decision: meDecision,
    ),
    opponent: BattleParticipant(
      battleId: 'b1',
      userId: 'friend',
      evidenceSubmittedAt: opponentEvidenceSubmittedAt,
      decision: opponentDecision,
    ),
    myName: '나',
    opponentName: '친구',
  );
}

void main() {
  // 속도전/품질전은 증거 제출 -> 상호 판정이라는 절차를 공유한다.
  group('증거 제출 (유형 공통)', () {
    for (final type in ['speed', 'quality']) {
      test('$type: active 상태에서 아직 제출 전이면 제출할 수 있다', () {
        final detail = _buildDetail(type: type, status: 'active');
        expect(detail.canSubmitEvidence, isTrue);
        expect(detail.canResubmitEvidence, isFalse);
      });

      test('$type: judging 상태에서도 아직 제출 전이면 제출할 수 있다', () {
        expect(_buildDetail(type: type, status: 'judging').canSubmitEvidence, isTrue);
      });

      test('$type: 이미 제출했으면 신규 제출이 아니라 재제출이 된다', () {
        final detail = _buildDetail(
          type: type,
          status: 'judging',
          meEvidenceSubmittedAt: DateTime(2026, 8, 21),
        );
        expect(detail.canSubmitEvidence, isFalse);
        expect(detail.canResubmitEvidence, isTrue);
        expect(detail.isWaitingMyEvidenceDecision, isTrue);
      });

      test('$type: 종결된 대결에는 제출도 재제출도 할 수 없다', () {
        for (final status in ['finished', 'disputed']) {
          final detail = _buildDetail(
            type: type,
            status: status,
            meEvidenceSubmittedAt: DateTime(2026, 8, 21),
          );
          expect(detail.canSubmitEvidence, isFalse);
          expect(detail.canResubmitEvidence, isFalse);
        }
      });
    }

    test('이의제기당한 뒤에도 재제출로 복구할 수 있다', () {
      final detail = _buildDetail(
        type: 'speed',
        status: 'judging',
        meEvidenceSubmittedAt: DateTime(2026, 8, 21),
        meDecision: 'dispute',
      );
      expect(detail.wasMyEvidenceDisputed, isTrue);
      expect(detail.isWaitingMyEvidenceDecision, isFalse);
      expect(detail.canResubmitEvidence, isTrue);
    });

    test('품질전만 사진 증거가 필수다', () {
      expect(_buildDetail(type: 'quality', status: 'active').requiresPhotoEvidence, isTrue);
      expect(_buildDetail(type: 'speed', status: 'active').requiresPhotoEvidence, isFalse);
    });
  });

  group('상대 증거 판정 (유형 공통)', () {
    test('judging이고 상대가 제출했고 아직 판정 전이면 판정할 수 있다', () {
      final detail = _buildDetail(
        type: 'speed',
        status: 'judging',
        opponentEvidenceSubmittedAt: DateTime(2026, 8, 21),
      );
      expect(detail.canReviewOpponentEvidence, isTrue);
    });

    test('상대가 제출하지 않았으면 판정할 수 없다', () {
      final detail = _buildDetail(type: 'quality', status: 'judging');
      expect(detail.canReviewOpponentEvidence, isFalse);
      expect(detail.isWaitingOpponentSubmit, isTrue);
    });

    test('이미 판정했으면 다시 판정할 수 없다', () {
      final detail = _buildDetail(
        type: 'quality',
        status: 'judging',
        opponentEvidenceSubmittedAt: DateTime(2026, 8, 21),
        opponentDecision: 'approve',
      );
      expect(detail.canReviewOpponentEvidence, isFalse);
    });

    test('종결된 대결에서는 판정 버튼을 내보내지 않는다 (서버도 거부한다)', () {
      for (final status in ['finished', 'disputed']) {
        final detail = _buildDetail(
          type: 'speed',
          status: status,
          opponentEvidenceSubmittedAt: DateTime(2026, 8, 21),
        );
        expect(detail.canReviewOpponentEvidence, isFalse);
      }
    });
  });

  group('속도전 결과 판정', () {
    test('내가 상대를 판정했어도 상대가 나를 판정하기 전엔 결과가 미확정이다', () {
      final detail = _buildDetail(
        type: 'speed',
        status: 'judging',
        meEvidenceSubmittedAt: DateTime(2026, 8, 21),
        opponentEvidenceSubmittedAt: DateTime(2026, 8, 21),
        opponentDecision: 'dispute',
      );
      expect(detail.isAwaitingBothDecisions, isTrue);
      expect(detail.wasOpponentEvidenceDisputed, isTrue);
      expect(detail.isFinished, isFalse);
    });

    test('양쪽 판정이 모두 내려졌으면 더 이상 대기 상태가 아니다', () {
      final detail = _buildDetail(
        type: 'speed',
        status: 'judging',
        meEvidenceSubmittedAt: DateTime(2026, 8, 21),
        meDecision: 'approve',
        opponentEvidenceSubmittedAt: DateTime(2026, 8, 21),
        opponentDecision: 'approve',
      );
      expect(detail.isAwaitingBothDecisions, isFalse);
    });

    test('품질전에는 양쪽 판정 대기라는 개념이 없다 (dispute 즉시 종결)', () {
      final detail = _buildDetail(
        type: 'quality',
        status: 'judging',
        meEvidenceSubmittedAt: DateTime(2026, 8, 21),
        opponentEvidenceSubmittedAt: DateTime(2026, 8, 21),
        opponentDecision: 'dispute',
      );
      expect(detail.isAwaitingBothDecisions, isFalse);
    });

    test('finished이고 내가 winner면 승리, 상대가 winner면 패배로 판정한다', () {
      expect(
        _buildDetail(type: 'speed', status: 'finished', winnerId: 'me').didIWinSpeedBattle,
        isTrue,
      );
      expect(
        _buildDetail(type: 'speed', status: 'finished', winnerId: 'friend').didILoseSpeedBattle,
        isTrue,
      );
    });

    test('이의제기로 상대 완료가 무효가 되어 이긴 경우도 승리로 판정한다', () {
      final detail = _buildDetail(
        type: 'speed',
        status: 'finished',
        winnerId: 'me',
        opponentEvidenceSubmittedAt: DateTime(2026, 8, 21),
        opponentDecision: 'dispute',
      );
      expect(detail.didIWinSpeedBattle, isTrue);
      expect(detail.wasOpponentEvidenceDisputed, isTrue);
    });

    test('양쪽 다 이의제기당하면 승자 없이 미결로 끝난다', () {
      final detail = _buildDetail(type: 'speed', status: 'disputed');
      expect(detail.isSpeedDisputed, isTrue);
      expect(detail.didIWinSpeedBattle, isFalse);
      expect(detail.didILoseSpeedBattle, isFalse);
    });
  });

  group('품질전 결과 판정', () {
    test('품질전은 승자를 두지 않는다', () {
      final detail = _buildDetail(type: 'quality', status: 'finished');
      expect(detail.isQualityFinished, isTrue);
      expect(detail.didIWinSpeedBattle, isFalse);
      expect(detail.didILoseSpeedBattle, isFalse);
    });

    test('disputed는 isDisputed로 판별되고, 속도전 전용 미결 문구는 쓰지 않는다', () {
      final detail = _buildDetail(type: 'quality', status: 'disputed');
      expect(detail.isDisputed, isTrue);
      expect(detail.isSpeedDisputed, isFalse);
    });

    test('속도전은 finished여도 isQualityFinished가 아니다', () {
      final detail = _buildDetail(type: 'speed', status: 'finished', winnerId: 'me');
      expect(detail.isQualityFinished, isFalse);
    });
  });
}
