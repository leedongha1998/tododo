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
  DateTime? opponentFirstSubmittedAt,
  String? opponentLastVerdict,
  bool withOpponent = true,
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
  );
  return BattleSummary(
    battle: battle,
    otherPartyName: '친구',
    opponent: withOpponent
        ? BattleParticipant(
            battleId: 'b1',
            userId: 'friend',
            firstSubmittedAt: opponentFirstSubmittedAt,
            lastVerdict: opponentLastVerdict,
          )
        : null,
  );
}

/// 목록 상태 줄은 푸시가 없는 MVP에서 "알림 대상 사건"을 앱 안에서 확인하는 자리다
/// (spec "알림 대상 정의"). 서버 요약을 문장으로 옮길 뿐 승패를 판단하지 않는다.
void main() {
  group('BattleSummary.statusLineAt', () {
    test('마감이 지났는데 아직 목록에 있으면 판정 마무리 중이라고 알린다', () {
      final summary = _summary(deadlineAt: _now.subtract(const Duration(minutes: 1)));
      expect(summary.statusLineAt(_now), AppStrings.battleListSettling);
    });

    test('품질전 판정 중이면 AI가 판정하는 중이라고 알린다', () {
      final summary = _summary(type: 'quality', status: 'judging');
      expect(summary.statusLineAt(_now), AppStrings.battleListJudging);
    });

    // 속도전은 상대 제출의 합격/불합격까지 공개된다(사유는 종결 뒤에 열린다).
    test('속도전은 상대의 합격·불합격이 드러난다', () {
      expect(
        _summary(opponentLastVerdict: 'passed', opponentFirstSubmittedAt: _now).statusLineAt(_now),
        AppStrings.battleListOpponentPassed,
      );
      expect(
        _summary(opponentLastVerdict: 'failed', opponentFirstSubmittedAt: _now).statusLineAt(_now),
        AppStrings.battleListOpponentFailed,
      );
    });

    test('품질전은 합격 여부를 알리지 않고 제출 사실만 알린다', () {
      final summary = _summary(type: 'quality', opponentFirstSubmittedAt: _now);
      expect(summary.statusLineAt(_now), AppStrings.battleListOpponentSubmitted);
    });

    test('상대가 아직 내지 않았으면 알릴 것이 없다', () {
      expect(_summary().statusLineAt(_now), isNull);
    });

    test('상대 요약을 읽지 못했으면 알릴 것이 없다', () {
      expect(_summary(withOpponent: false).statusLineAt(_now), isNull);
    });

    test('마감 경과가 다른 어떤 소식보다 앞선다', () {
      final summary = _summary(
        deadlineAt: _now.subtract(const Duration(minutes: 1)),
        opponentLastVerdict: 'passed',
        opponentFirstSubmittedAt: _now,
      );
      expect(summary.statusLineAt(_now), AppStrings.battleListSettling);
    });
  });
}
