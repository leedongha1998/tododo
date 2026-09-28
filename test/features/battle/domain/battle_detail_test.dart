import 'package:flutter_test/flutter_test.dart';
import 'package:todododo/features/battle/data/battle.dart';
import 'package:todododo/features/battle/data/battle_participant.dart';
import 'package:todododo/features/battle/data/battle_submission.dart';
import 'package:todododo/features/battle/domain/battle_detail.dart';

BattleDetail _buildDetail({
  required String type,
  required String status,
  String? winnerId,
  String? forfeitedBy,
  String? myOutcome,
  String? opponentOutcome,
  bool opponentSubmitted = false,
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
    opponent: BattleParticipant(
      battleId: 'b1',
      userId: 'friend',
      outcome: opponentOutcome,
      hasSubmitted: opponentSubmitted,
    ),
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

      test('$type: active는 제출 창, judging은 판정 창이다', () {
        final active = _buildDetail(type: type, status: 'active');
        expect(active.isSubmissionWindow, isTrue);
        expect(active.isJudgingWindow, isFalse);

        final judging = _buildDetail(type: type, status: 'judging');
        expect(judging.isSubmissionWindow, isFalse);
        expect(judging.isJudgingWindow, isTrue);
      });
    }

    test('판정 창에서도 서버가 종결하기 전까지는 승패가 없다', () {
      final detail = _buildDetail(type: 'speed', status: 'judging');
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
      expect(detail.didICompleteButLose, isTrue);
    });

    test('품질전에서 상대가 끝내 내지 않아 이긴 경우를 구분한다', () {
      final noShow = _buildDetail(type: 'quality', status: 'finished', winnerId: 'me');
      expect(noShow.didIWinByOpponentNoShow, isTrue);

      final judged = _buildDetail(
        type: 'quality',
        status: 'finished',
        winnerId: 'me',
        opponentSubmitted: true,
      );
      expect(judged.didIWinByOpponentNoShow, isFalse);
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
    for (final type in _types) {
      test('$type: 제출 창이고 마감 전이며 아직 내지 않았으면 낼 수 있다', () {
        final detail = _detail(type: type);
        expect(detail.hasMySubmission, isFalse);
        expect(detail.canSubmitEvidenceAt(_now), isTrue);
      });

      test('$type: 이미 냈으면 첫 제출 버튼은 닫힌다', () {
        final bySummary = _detail(type: type, mySubmitted: true);
        expect(bySummary.hasMySubmission, isTrue);
        expect(bySummary.canSubmitEvidenceAt(_now), isFalse);

        // 요약보다 제출 행이 먼저 보여도 같다.
        final byRow = _detail(type: type, submissions: [_submission()]);
        expect(byRow.hasMySubmission, isTrue);
        expect(byRow.canSubmitEvidenceAt(_now), isFalse);
      });

      test('$type: 마감이 지나면 낼 수 없다', () {
        final detail = _detail(type: type, deadlineAt: _now.subtract(const Duration(minutes: 1)));
        expect(detail.isPastDeadline(_now), isTrue);
        expect(detail.canSubmitEvidenceAt(_now), isFalse);
      });

      test('$type: 판정 창이나 종결 상태에서는 낼 수 없다', () {
        for (final status in ['judging', 'finished', 'draw', 'voided', 'cancelled']) {
          final detail = _detail(type: type, status: status);
          expect(detail.canSubmitEvidenceAt(_now), isFalse, reason: status);
        }
      });
    }
  });

  // 교체는 속도전에서 상대가 아직 내지 않은 동안만이다(spec D3).
  group('교체 가능 판단', () {
    test('속도전은 내가 냈고 상대가 아직 내지 않았으면 바꿀 수 있다', () {
      final detail = _detail(mySubmitted: true, submissions: [_submission()]);
      expect(detail.canReplaceEvidenceAt(_now), isTrue);
    });

    test('상대가 제출하면 내 사진도 잠긴다', () {
      final detail = _detail(mySubmitted: true, opponentSubmitted: true);
      expect(detail.canReplaceEvidenceAt(_now), isFalse);
    });

    test('아직 내지 않았으면 바꿀 것이 없다', () {
      expect(_detail().canReplaceEvidenceAt(_now), isFalse);
    });

    test('마감이 지나거나 판정 창이면 바꿀 수 없다', () {
      final pastDeadline = _detail(
        mySubmitted: true,
        deadlineAt: _now.subtract(const Duration(minutes: 1)),
      );
      expect(pastDeadline.canReplaceEvidenceAt(_now), isFalse);

      final judging = _detail(mySubmitted: true, status: 'judging');
      expect(judging.canReplaceEvidenceAt(_now), isFalse);
    });

    test('품질전에는 교체가 없다', () {
      final detail = _detail(type: 'quality', mySubmitted: true);
      expect(detail.canReplaceEvidenceAt(_now), isFalse);
    });
  });

  group('판정 창에서 할 일', () {
    test('상대가 제출했고 내가 아직 판정하지 않았으면 내 판정 차례다', () {
      final detail = _detail(status: 'judging', mySubmitted: true, opponentSubmitted: true);
      expect(detail.hasSomethingToJudge, isTrue);
      expect(detail.isMyJudgmentDue, isTrue);
    });

    test('판정했으면(자동 승인 포함) 더 할 일이 없다', () {
      final detail = _detail(
        status: 'judging',
        mySubmitted: true,
        opponentSubmitted: true,
        myJudged: true,
      );
      expect(detail.isMyJudgmentDue, isFalse);
    });

    test('속도전에서 상대가 내지 않고 마감됐으면 판정할 것이 없다', () {
      final detail = _detail(status: 'judging', mySubmitted: true);
      expect(detail.hasSomethingToJudge, isFalse);
      expect(detail.isMyJudgmentDue, isFalse);
    });

    test('제출 창에서는 판정할 것이 없다', () {
      final detail = _detail(mySubmitted: true, opponentSubmitted: true);
      expect(detail.hasSomethingToJudge, isFalse);
    });
  });

  group('제출 공개 범위', () {
    test('제출 창에서는 서버가 내 제출만 주고, 판정 창과 종결 뒤에는 양쪽이 열린다', () {
      final ongoing = _detail(submissions: [_submission()]);
      expect(ongoing.mySubmission, isNotNull);
      expect(ongoing.opponentSubmission, isNull);
      expect(ongoing.areSubmissionsRevealed, isFalse);

      for (final status in ['judging', 'finished', 'draw', 'voided', 'cancelled']) {
        final revealed = _detail(
          status: status,
          submissions: [_submission(id: 1), _submission(id: 2, userId: 'friend')],
        );
        expect(revealed.areSubmissionsRevealed, isTrue, reason: status);
        // 내 제출과 상대 제출이 섞이지 않는다.
        expect(revealed.mySubmission?.id, 1, reason: status);
        expect(revealed.opponentSubmission?.id, 2, reason: status);
      }
    });

    test('상대 제출 사실은 요약 컬럼에서 읽는다(시각·사진은 없다)', () {
      final detail = _detail(opponentSubmitted: true);
      expect(detail.hasOpponentSubmitted, isTrue);
      expect(detail.opponentSubmission, isNull);
    });
  });
}

final _now = DateTime(2026, 9, 16, 12);

BattleSubmission _submission({int id = 1, String userId = 'me'}) {
  return BattleSubmission(
    id: id,
    battleId: 'b1',
    userId: userId,
    objectPath: 'b1/$userId/$id.jpg',
    capturedAt: _now,
    submittedAt: _now,
  );
}

BattleDetail _detail({
  String type = 'speed',
  String status = 'active',
  DateTime? deadlineAt,
  bool mySubmitted = false,
  bool myJudged = false,
  bool opponentSubmitted = false,
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
    minCriteria: const ['상판이 보인다'],
  );
  return BattleDetail(
    battle: battle,
    me: BattleParticipant(
      battleId: 'b1',
      userId: 'me',
      hasSubmitted: mySubmitted,
      hasJudged: myJudged,
    ),
    opponent: BattleParticipant(
      battleId: 'b1',
      userId: 'friend',
      hasSubmitted: opponentSubmitted,
    ),
    myName: '나',
    opponentName: '친구',
    submissions: submissions,
  );
}
