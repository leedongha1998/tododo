import 'package:flutter_test/flutter_test.dart';
import 'package:todododo/features/battle/data/battle.dart';
import 'package:todododo/features/battle/data/battle_participant.dart';
import 'package:todododo/features/battle/data/battle_submission.dart';
import 'package:todododo/features/battle/domain/battle_detail.dart';
import 'package:todododo/features/battle/domain/judgment_rules.dart';

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

    test('속도전에서 상호 판정 창이 열려도 서버가 종결하기 전까지는 진행 중이다', () {
      final detail = _buildDetail(type: 'speed', status: 'judging');
      expect(detail.isOngoing, isTrue);
      expect(detail.isJudging, isTrue);
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

  // 제출 가능 여부는 화면 활성화 판단이다. 같은 검사를 서버가 다시 하므로 여기서 막지 못해도
  // 규칙이 깨지지는 않는다 — 반대로 여기서 열어 두면 사용자가 거부당하는 헛걸음을 한다.
  group('제출 가능 판단', () {
    test('속도전은 active인 동안 언제나 낼 수 있다(처음이든 교체든)', () {
      final detail = _speedDetail();
      expect(detail.canSubmitEvidenceAt(_now), isTrue);
    });

    test('속도전은 이미 냈어도 상대가 아직이면 교체로 받아들여진다', () {
      final detail = _speedDetail(myHasSubmitted: true);
      expect(detail.isReplacingEvidenceAt(_now), isTrue);
      expect(detail.canSubmitEvidenceAt(_now), isTrue);
    });

    test('마감이 지나면 낼 수 없다', () {
      final detail = _speedDetail(deadlineAt: _now.subtract(const Duration(minutes: 1)));
      expect(detail.isPastDeadline(_now), isTrue);
      expect(detail.canSubmitEvidenceAt(_now), isFalse);
    });

    // 마감 뒤 정산(cron 최대 1분)까지는 status가 active로 남는다. 그동안 교체 자리를 열어 두면
    // 서버가 DEADLINE_PASSED로 거부하는 헛걸음이 된다.
    test('속도전은 마감이 지나면 교체 자리도 닫힌다', () {
      final detail = _speedDetail(
        myHasSubmitted: true,
        deadlineAt: _now.subtract(const Duration(minutes: 1)),
      );
      expect(detail.isReplacingEvidenceAt(_now), isFalse);
    });

    // 품질전은 제출이 한 번뿐이고 재제출 수단이 없다(결정 14).
    test('품질전은 아직 내지 않았을 때만 낼 수 있다', () {
      final before = _speedDetail(type: 'quality');
      expect(before.isQuality, isTrue);
      expect(before.canSubmitEvidenceAt(_now), isTrue);

      final after = _speedDetail(type: 'quality', myHasSubmitted: true);
      expect(after.canSubmitEvidenceAt(_now), isFalse);
      // 품질전은 교체가 없다 — isReplacingEvidenceAt은 속도전 전용이다.
      expect(after.isReplacingEvidenceAt(_now), isFalse);
    });

    test('상호 판정 창(judging)에는 낼 수 없다(두 유형 공통)', () {
      for (final type in _types) {
        final detail = _speedDetail(type: type, status: 'judging');
        expect(detail.isJudging, isTrue, reason: type);
        expect(detail.canSubmitEvidenceAt(_now), isFalse, reason: type);
      }
    });

    test('품질전도 마감이 지나면 낼 수 없다', () {
      final detail = _speedDetail(
        type: 'quality',
        deadlineAt: _now.subtract(const Duration(minutes: 1)),
      );
      expect(detail.canSubmitEvidenceAt(_now), isFalse);
    });

    test('종결된 대결에는 낼 수 없다', () {
      for (final status in ['finished', 'draw', 'voided', 'cancelled']) {
        final detail = _speedDetail(status: status);
        expect(detail.canSubmitEvidenceAt(_now), isFalse, reason: status);
      }
    });
  });

  group('제출 공개 범위', () {
    test('진행 중(active)에는 서버가 내 제출만 주고, 판정 창이 열리면 양쪽이 열린다', () {
      final ongoing = _speedDetail(submissions: [_submission()]);
      expect(ongoing.mySubmission, isNotNull);
      expect(ongoing.areSubmissionsRevealed, isFalse);

      final judging = _speedDetail(
        status: 'judging',
        submissions: [
          _submission(id: 1),
          _submission(id: 2, userId: 'friend'),
        ],
      );
      expect(judging.areSubmissionsRevealed, isTrue);
      expect(judging.opponentSubmission, isNotNull);

      final finished = _speedDetail(
        status: 'finished',
        submissions: [
          _submission(id: 1),
          _submission(id: 2, userId: 'friend'),
        ],
      );
      expect(finished.areSubmissionsRevealed, isTrue);
    });

    test('상대 제출 사실은 요약 컬럼에서 읽는다(시각·사진·판정 내용은 없다)', () {
      final detail = _speedDetail(opponentHasSubmitted: true);
      expect(detail.hasOpponentSubmitted, isTrue);
    });
  });

  // 판정 단계 판별은 judgment_rules_test가 전 행을 덮는다. 여기서는 상세 모델이 서버 값을
  // 그 함수에 제대로 넘기는지(내/상대 역할이 뒤집히지 않는지)만 본다.
  group('판정 단계 연결', () {
    test('판정 창에서 상대 증거가 있고 내가 아직 판정하지 않았으면 내 차례다', () {
      final detail = _speedDetail(
        status: 'judging',
        myHasSubmitted: true,
        opponentHasSubmitted: true,
      );
      // 시각을 넘기지 않는 getter(isMyJudgmentTurn)는 DateTime.now()를 쓰므로 고정 픽스처로
      // 검증할 수 없다. 화면이 쓰는 그 경로는 위젯 테스트(battle_judgment_test)가 덮는다.
      expect(detail.judgmentStageAt(_now), JudgmentStage.myTurn);
    });

    test('내가 판정했으면 상대 판정을 기다린다(역할이 뒤집히지 않는다)', () {
      final detail = _speedDetail(
        status: 'judging',
        myHasSubmitted: true,
        opponentHasSubmitted: true,
        myHasJudged: true,
      );
      expect(detail.judgmentStageAt(_now), JudgmentStage.waitingOpponent);

      final reversed = _speedDetail(
        status: 'judging',
        myHasSubmitted: true,
        opponentHasSubmitted: true,
        opponentHasJudged: true,
      );
      expect(reversed.judgmentStageAt(_now), JudgmentStage.myTurn);
    });

    test('제출 창(active)에는 판정 단계가 없다', () {
      final detail = _speedDetail(myHasSubmitted: true, opponentHasSubmitted: true);
      expect(detail.judgmentStageAt(_now), JudgmentStage.notOpen);
      expect(detail.judgeDeadlineAt, isNull);
    });

    test('판정 기한은 서버가 창을 열 때 찍은 값을 그대로 쓴다', () {
      final detail = _speedDetail(status: 'judging', opponentHasSubmitted: true);
      expect(detail.judgeDeadlineAt, _now.add(const Duration(hours: 24)));
      expect(detail.isPastJudgeDeadline(_now), isFalse);
      expect(detail.isPastJudgeDeadline(_now.add(const Duration(hours: 25))), isTrue);
    });

    test('우열 답이 필요한 쪽은 품질전뿐이다', () {
      expect(_speedDetail(type: 'quality').needsSuperiorityPick, isTrue);
      expect(_speedDetail().needsSuperiorityPick, isFalse);
      // 속도전에는 우열 기준 자체가 없다.
      expect(_speedDetail().superiorityCriteria, isEmpty);
    });
  });
}

BattleSubmission _submission({int id = 1, String userId = 'me'}) {
  final now = DateTime(2026, 9, 16, 12);
  return BattleSubmission(
    id: id,
    battleId: 'b1',
    userId: userId,
    objectPath: 'b1/$userId/$id.jpg',
    capturedAt: now,
    submittedAt: now,
  );
}

final _now = DateTime(2026, 9, 16, 12);

BattleDetail _speedDetail({
  String type = 'speed',
  String status = 'active',
  DateTime? deadlineAt,
  DateTime? judgeDeadlineAt,
  bool myHasSubmitted = false,
  bool opponentHasSubmitted = false,
  bool myHasJudged = false,
  bool opponentHasJudged = false,
  List<BattleSubmission> submissions = const [],
}) {
  final battle = Battle(
    id: 'b1',
    type: type,
    status: status,
    title: '책상 정리하기',
    creatorId: 'me',
    opponentId: 'friend',
    createdAt: DateTime(2026, 9, 15),
    startedAt: DateTime(2026, 9, 15),
    deadlineAt: deadlineAt ?? _now.add(const Duration(days: 1)),
    judgingOpenedAt: status == 'judging' ? _now : null,
    // 서버는 창을 열 때 판정 기한을 함께 찍는다(제약으로 강제).
    judgeDeadlineAt: status == 'judging'
        ? (judgeDeadlineAt ?? _now.add(const Duration(hours: 24)))
        : null,
    minCriteria: const ['상판이 보인다'],
  );
  return BattleDetail(
    battle: battle,
    me: BattleParticipant(
      battleId: 'b1',
      userId: 'me',
      hasSubmitted: myHasSubmitted,
      hasJudged: myHasJudged,
    ),
    opponent: BattleParticipant(
      battleId: 'b1',
      userId: 'friend',
      hasSubmitted: opponentHasSubmitted,
      hasJudged: opponentHasJudged,
    ),
    myName: '나',
    opponentName: '친구',
    submissions: submissions,
  );
}
