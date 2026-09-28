import 'package:flutter_test/flutter_test.dart';
import 'package:todododo/core/strings.dart';
import 'package:todododo/features/battle/data/battle.dart';
import 'package:todododo/features/battle/data/battle_participant.dart';
import 'package:todododo/features/battle/domain/battle_summary.dart';

final _now = DateTime(2026, 9, 17, 12);

BattleSummary _summary({
  String type = 'speed',
  String status = 'active',
  DateTime? deadlineAt,
  DateTime? judgeDeadlineAt,
  bool mySubmitted = false,
  bool myJudged = false,
  bool opponentSubmitted = false,
  bool opponentJudged = false,
  bool withParticipants = true,
}) {
  final battle = Battle(
    id: 'b1',
    type: type,
    status: status,
    title: '책상 정리하기',
    creatorId: 'me',
    opponentId: 'friend',
    createdAt: DateTime(2026, 9, 16),
    startedAt: DateTime(2026, 9, 16),
    deadlineAt: deadlineAt ?? _now.add(const Duration(days: 1)),
    judgeDeadlineAt: judgeDeadlineAt,
  );
  return BattleSummary(
    battle: battle,
    otherPartyName: '친구',
    me: withParticipants
        ? BattleParticipant(
            battleId: 'b1',
            userId: 'me',
            hasSubmitted: mySubmitted,
            hasJudged: myJudged,
          )
        : null,
    opponent: withParticipants
        ? BattleParticipant(
            battleId: 'b1',
            userId: 'friend',
            hasSubmitted: opponentSubmitted,
            hasJudged: opponentJudged,
          )
        : null,
  );
}

/// 목록 상태 줄은 푸시가 붙기 전까지 "알림 대상 사건"을 앱 안에서 확인하는 자리다.
/// 서버 요약(제출·판정 여부)을 문장으로 옮길 뿐 승패를 판단하지 않는다.
void main() {
  group('제출 창', () {
    test('상대가 아직 내지 않았으면 알릴 것이 없다', () {
      expect(_summary().statusLineAt(_now), isNull);
    });

    for (final type in ['speed', 'quality']) {
      test('$type: 상대가 제출하면 제출 사실만 알린다(합격 여부·시각은 없다)', () {
        final summary = _summary(type: type, opponentSubmitted: true);
        expect(summary.statusLineAt(_now), AppStrings.battleListOpponentSubmitted);
      });
    }

    test('양쪽 다 냈으면 그렇게 알린다', () {
      final summary = _summary(mySubmitted: true, opponentSubmitted: true);
      expect(summary.statusLineAt(_now), AppStrings.battleListBothSubmitted);
    });

    test('마감이 지났는데 아직 제출 창이면 정리 중이라고 알린다', () {
      final summary = _summary(
        deadlineAt: _now.subtract(const Duration(minutes: 1)),
        opponentSubmitted: true,
      );
      expect(summary.statusLineAt(_now), AppStrings.battleListSettling);
    });

    test('요약을 읽지 못했으면 알릴 것이 없다', () {
      expect(_summary(withParticipants: false).statusLineAt(_now), isNull);
    });
  });

  group('판정 창', () {
    test('상대 증거가 있고 내가 아직 판정하지 않았으면 남은 시간과 함께 내 차례라고 알린다', () {
      final summary = _summary(
        status: 'judging',
        judgeDeadlineAt: _now.add(const Duration(hours: 5, minutes: 30)),
        mySubmitted: true,
        opponentSubmitted: true,
      );
      expect(summary.statusLineAt(_now), AppStrings.battleListMyJudgeTurnLeft('5시간'));
    });

    test('판정 기한 값이 없거나 지났으면 남은 시간 없이 알린다', () {
      final summary = _summary(
        status: 'judging',
        judgeDeadlineAt: _now.subtract(const Duration(minutes: 1)),
        opponentSubmitted: true,
      );
      expect(summary.statusLineAt(_now), AppStrings.battleListMyJudgeTurn);
    });

    test('나는 판정했고 상대가 아직이면 상대 판정을 기다린다', () {
      final summary = _summary(
        status: 'judging',
        mySubmitted: true,
        myJudged: true,
        opponentSubmitted: true,
      );
      expect(summary.statusLineAt(_now), AppStrings.battleListWaitingOpponentJudgment);
    });

    test('속도전 한쪽 제출에서 제출자는 판정할 것 없이 상대 판정을 기다린다', () {
      final summary = _summary(status: 'judging', mySubmitted: true);
      expect(summary.statusLineAt(_now), AppStrings.battleListWaitingOpponentJudgment);
    });

    test('필요한 판정이 다 끝났는데 아직 판정 창이면 AI가 다시 보는 중이다', () {
      final summary = _summary(
        status: 'judging',
        mySubmitted: true,
        myJudged: true,
        opponentSubmitted: true,
        opponentJudged: true,
      );
      expect(summary.statusLineAt(_now), AppStrings.battleListAiRejudging);
    });

    test('판정 창에서는 사진 마감이 지난 것을 다시 알리지 않는다', () {
      final summary = _summary(
        status: 'judging',
        deadlineAt: _now.subtract(const Duration(hours: 1)),
        judgeDeadlineAt: _now.add(const Duration(hours: 23)),
        opponentSubmitted: true,
      );
      expect(summary.statusLineAt(_now), AppStrings.battleListMyJudgeTurnLeft('23시간'));
    });
  });
}
