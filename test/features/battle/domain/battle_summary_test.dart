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
  bool opponentSubmitted = false,
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
        ? BattleParticipant(battleId: 'b1', userId: 'friend', hasSubmitted: opponentSubmitted)
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

    test('상호 판정 창이면 서로 판정하는 중이라고 알린다(두 유형 공통)', () {
      for (final type in ['speed', 'quality']) {
        final summary = _summary(type: type, status: 'judging');
        expect(summary.statusLineAt(_now), AppStrings.battleListJudging, reason: type);
      }
    });

    // 마감 전에 상대에 대해 보이는 것은 "제출했다"는 사실 하나뿐이다(두 유형 공통, D2).
    test('상대가 제출했으면 그 사실만 알린다', () {
      for (final type in ['speed', 'quality']) {
        final summary = _summary(type: type, opponentSubmitted: true);
        expect(summary.statusLineAt(_now), AppStrings.battleListOpponentSubmitted, reason: type);
      }
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
        opponentSubmitted: true,
      );
      expect(summary.statusLineAt(_now), AppStrings.battleListSettling);
    });
  });
}
