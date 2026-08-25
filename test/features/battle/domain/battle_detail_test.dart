import 'package:flutter_test/flutter_test.dart';
import 'package:todododo/features/battle/data/battle.dart';
import 'package:todododo/features/battle/data/battle_participant.dart';
import 'package:todododo/features/battle/domain/battle_detail.dart';

BattleDetail _buildDetail({
  required String type,
  required String status,
  String? winnerId,
  DateTime? meCompletedAt,
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
      completedAt: meCompletedAt,
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
  group('속도전 상태 전이', () {
    test('active이고 내가 완료 전이면 완료 버튼을 보여줄 수 있다', () {
      final detail = _buildDetail(type: 'speed', status: 'active');
      expect(detail.canCompleteSpeedTask, isTrue);
      expect(detail.isWaitingForOpponentSpeed, isFalse);
    });

    test('active이고 내가 이미 완료했으면 상대를 기다린다', () {
      final detail = _buildDetail(type: 'speed', status: 'active', meCompletedAt: DateTime(2026, 8, 21));
      expect(detail.canCompleteSpeedTask, isFalse);
      expect(detail.isWaitingForOpponentSpeed, isTrue);
    });

    test('finished이고 내가 winner면 승리로 판정한다', () {
      final detail = _buildDetail(type: 'speed', status: 'finished', winnerId: 'me');
      expect(detail.didIWinSpeedBattle, isTrue);
    });

    test('finished이고 상대가 winner면 패배로 판정한다', () {
      final detail = _buildDetail(type: 'speed', status: 'finished', winnerId: 'friend');
      expect(detail.didIWinSpeedBattle, isFalse);
    });

    test('pending 상태에서는 완료 버튼도 대기 상태도 아니다', () {
      final detail = _buildDetail(type: 'speed', status: 'pending');
      expect(detail.canCompleteSpeedTask, isFalse);
      expect(detail.isWaitingForOpponentSpeed, isFalse);
    });
  });

  group('품질전 상태 전이', () {
    test('active 상태에서 아직 증거를 제출하지 않았으면 제출할 수 있다', () {
      final detail = _buildDetail(type: 'quality', status: 'active');
      expect(detail.canSubmitEvidence, isTrue);
    });

    test('judging 상태에서도 아직 제출 전이면 제출할 수 있다', () {
      final detail = _buildDetail(type: 'quality', status: 'judging');
      expect(detail.canSubmitEvidence, isTrue);
    });

    test('이미 제출했으면 다시 제출할 수 없다', () {
      final detail = _buildDetail(
        type: 'quality',
        status: 'judging',
        meEvidenceSubmittedAt: DateTime(2026, 8, 21),
      );
      expect(detail.canSubmitEvidence, isFalse);
    });

    test('disputed/finished 상태에서는 증거를 제출할 수 없다', () {
      expect(_buildDetail(type: 'quality', status: 'disputed').canSubmitEvidence, isFalse);
      expect(_buildDetail(type: 'quality', status: 'finished').canSubmitEvidence, isFalse);
    });

    test('상대가 증거를 제출했고 아직 판정 전이면 내가 승인/이의제기할 수 있다', () {
      final detail = _buildDetail(
        type: 'quality',
        status: 'judging',
        opponentEvidenceSubmittedAt: DateTime(2026, 8, 21),
      );
      expect(detail.canReviewOpponentEvidence, isTrue);
    });

    test('상대가 증거를 제출하지 않았으면 판정할 수 없다', () {
      final detail = _buildDetail(type: 'quality', status: 'judging');
      expect(detail.canReviewOpponentEvidence, isFalse);
    });

    test('상대 증거를 이미 판정했으면 다시 판정할 수 없다', () {
      final detail = _buildDetail(
        type: 'quality',
        status: 'judging',
        opponentEvidenceSubmittedAt: DateTime(2026, 8, 21),
        opponentDecision: 'approve',
      );
      expect(detail.canReviewOpponentEvidence, isFalse);
    });

    test('disputed 상태는 isDisputed로, finished 상태는 isQualityFinished로 판별된다', () {
      expect(_buildDetail(type: 'quality', status: 'disputed').isDisputed, isTrue);
      expect(_buildDetail(type: 'quality', status: 'finished').isQualityFinished, isTrue);
      expect(_buildDetail(type: 'quality', status: 'judging').isDisputed, isFalse);
      expect(_buildDetail(type: 'quality', status: 'judging').isQualityFinished, isFalse);
    });

    test('속도전은 finished여도 isQualityFinished가 아니다 (품질전 전용 판정)', () {
      final detail = _buildDetail(type: 'speed', status: 'finished', winnerId: 'me');
      expect(detail.isQualityFinished, isFalse);
    });
  });
}
