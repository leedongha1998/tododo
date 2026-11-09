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
  bool opponentSubmitted = false,
  bool opponentJudged = false,
  bool iSubmitted = true,
  bool iJudged = false,
  bool withOpponent = true,
  bool withMe = true,
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
    me: withMe
        ? BattleParticipant(
            battleId: 'b1',
            userId: 'me',
            hasSubmitted: iSubmitted,
            hasJudged: iJudged,
          )
        : null,
    opponent: withOpponent
        ? BattleParticipant(
            battleId: 'b1',
            userId: 'friend',
            hasSubmitted: opponentSubmitted,
            hasJudged: opponentJudged,
          )
        : null,
  );
}

/// 판정 창이 열린 대결. 서버는 창을 열 때 judge_deadline_at을 함께 찍는다.
BattleSummary _judgingSummary({
  String type = 'speed',
  bool opponentSubmitted = true,
  bool opponentJudged = false,
  bool iSubmitted = true,
  bool iJudged = false,
  DateTime? judgeDeadlineAt,
  bool withMe = true,
  bool withOpponent = true,
}) {
  return _summary(
    type: type,
    status: 'judging',
    // 속도전 판정 창은 대개 마감이 지난 뒤에 열린다. 그 상태를 기본값으로 둔다.
    deadlineAt: _now.subtract(const Duration(minutes: 10)),
    judgeDeadlineAt: judgeDeadlineAt ?? _now.add(const Duration(hours: 23)),
    opponentSubmitted: opponentSubmitted,
    opponentJudged: opponentJudged,
    iSubmitted: iSubmitted,
    iJudged: iJudged,
    withMe: withMe,
    withOpponent: withOpponent,
  );
}

/// 목록 상태 줄은 푸시가 없는 MVP에서 "알림 대상 사건"을 앱 안에서 확인하는 자리다
/// (spec "알림 대상 정의"). 서버 요약을 문장으로 옮길 뿐 승패를 판단하지 않는다.
void main() {
  group('BattleSummary.statusLineAt — 제출 창', () {
    test('마감이 지났는데 아직 목록에 있으면 판정 마무리 중이라고 알린다', () {
      final summary = _summary(
        deadlineAt: _now.subtract(const Duration(minutes: 1)),
      );
      expect(summary.statusLineAt(_now), AppStrings.battleListSettling);
      expect(summary.noticeAt(_now).needsMyAction, isFalse);
    });

    // 푸시가 없으니 "내 사진이 아직 없다"를 말해 주는 자리가 이 줄뿐이다(M1).
    test('내가 아직 사진을 내지 않았으면 그것을 가장 먼저 알리고 강조한다', () {
      for (final type in ['speed', 'quality']) {
        final summary = _summary(type: type, iSubmitted: false);
        final notice = summary.noticeAt(_now);
        expect(notice.line, AppStrings.battleListNotSubmitted, reason: type);
        expect(notice.needsMyAction, isTrue, reason: type);
      }
    });

    test('내가 안 냈고 상대는 냈으면 내 할 일을 먼저 말한다', () {
      final summary = _summary(iSubmitted: false, opponentSubmitted: true);
      expect(summary.statusLineAt(_now), AppStrings.battleListNotSubmitted);
    });

    // 마감 전에 상대에 대해 보이는 것은 "제출했다"는 사실 하나뿐이다(두 유형 공통, D2).
    test('내가 이미 냈고 상대도 냈으면 상대 제출 사실만 알린다', () {
      for (final type in ['speed', 'quality']) {
        final summary = _summary(type: type, opponentSubmitted: true);
        final notice = summary.noticeAt(_now);
        expect(
          notice.line,
          AppStrings.battleListOpponentSubmitted,
          reason: type,
        );
        // 상대 제출은 소식일 뿐 내가 할 일이 아니다.
        expect(notice.needsMyAction, isFalse, reason: type);
      }
    });

    test('둘 다 아직 내지 않았고 내 행도 있으면 내 미제출을 알린다', () {
      expect(
        _summary(iSubmitted: false).statusLineAt(_now),
        AppStrings.battleListNotSubmitted,
      );
    });

    test('내가 냈고 상대가 아직이면 알릴 것이 없다', () {
      expect(_summary().statusLineAt(_now), isNull);
    });

    test('내 요약을 읽지 못했으면 미제출을 단정하지 않는다', () {
      expect(_summary(withMe: false).statusLineAt(_now), isNull);
    });

    test('상대 요약을 읽지 못했으면 상대 소식을 알리지 않는다', () {
      expect(
        _summary(
          withOpponent: false,
          opponentSubmitted: true,
        ).statusLineAt(_now),
        isNull,
      );
    });

    test('마감 경과가 제출 창의 어떤 소식보다 앞선다', () {
      final summary = _summary(
        deadlineAt: _now.subtract(const Duration(minutes: 1)),
        iSubmitted: false,
        opponentSubmitted: true,
      );
      expect(summary.statusLineAt(_now), AppStrings.battleListSettling);
    });
  });

  // 판정 창에서는 "내가 들어가서 눌러야 하는가"가 갈려야 한다(M1). 단계 판정은
  // judgmentStageOf가 하고 여기서는 문장만 고른다.
  group('BattleSummary.statusLineAt — 판정 창', () {
    test('내가 판정하지 않았고 기한이 남았으면 내 차례라고 알리고 강조한다', () {
      for (final type in ['speed', 'quality']) {
        final notice = _judgingSummary(type: type).noticeAt(_now);
        expect(notice.line, AppStrings.battleListMyJudgeTurn, reason: type);
        expect(notice.needsMyAction, isTrue, reason: type);
      }
    });

    // 판정 창은 마감 뒤에 열린다. 마감 경과를 먼저 보면 이 안내가 영원히 가려진다.
    test('마감이 지났어도 판정 단계가 마감 경과 문구를 덮는다', () {
      final summary = _judgingSummary();
      expect(summary.battle.deadlineAt!.isBefore(_now), isTrue);
      expect(summary.statusLineAt(_now), AppStrings.battleListMyJudgeTurn);
    });

    test('내 판정을 보냈고 상대가 아직이면 상대를 기다린다고 알린다', () {
      final notice = _judgingSummary(iJudged: true).noticeAt(_now);
      expect(notice.line, AppStrings.battleListWaitingOpponentJudge);
      expect(notice.needsMyAction, isFalse);
    });

    test('양쪽 판정이 끝났는데 아직 판정 창이면 AI 재판정이라고 알린다', () {
      final notice = _judgingSummary(
        iJudged: true,
        opponentJudged: true,
      ).noticeAt(_now);
      // 상세 화면과 같은 문구를 쓴다(새 문구를 만들지 않는다).
      expect(notice.line, AppStrings.battleJudgmentAiTitle);
      expect(notice.needsMyAction, isFalse);
    });

    test('상대가 사진을 내지 않아 판정할 것이 없으면 기존 중립 문구를 쓴다', () {
      final notice = _judgingSummary(opponentSubmitted: false).noticeAt(_now);
      expect(notice.line, AppStrings.battleListJudging);
      expect(notice.needsMyAction, isFalse);
    });

    test('판정 기한이 지났으면 내 차례가 아니라 중립 문구로 돌아간다', () {
      final notice = _judgingSummary(
        judgeDeadlineAt: _now.subtract(const Duration(minutes: 1)),
      ).noticeAt(_now);
      expect(notice.line, AppStrings.battleListJudging);
      expect(notice.needsMyAction, isFalse);
    });

    test('참가자 행을 읽지 못한 판정 창은 기존 중립 문구로 떨어진다', () {
      final notice = _judgingSummary(
        withMe: false,
        withOpponent: false,
      ).noticeAt(_now);
      expect(notice.line, AppStrings.battleListJudging);
      expect(notice.needsMyAction, isFalse);
    });
  });

  // 남은 시간은 "지금 흐르는 시계"만 말한다. 어느 시계인지 라벨로 밝힌다.
  group('BattleSummary.deadlineLineAt', () {
    test('제출 창에서는 사진 마감까지 남은 시간을 말한다', () {
      final summary = _summary(deadlineAt: _now.add(const Duration(hours: 5)));
      expect(
        summary.deadlineLineAt(_now),
        '${AppStrings.battleSubmitDeadlineLabel} · '
        '${AppStrings.battleDeadlineLeft('5시간')}',
      );
    });

    test('판정 창에서는 판정 기한까지 남은 시간을 말한다', () {
      final summary = _judgingSummary(
        judgeDeadlineAt: _now.add(const Duration(minutes: 90)),
      );
      expect(
        summary.deadlineLineAt(_now),
        '${AppStrings.battleJudgeDeadlineLabel} · '
        '${AppStrings.battleDeadlineLeft('1시간 30분')}',
      );
    });

    test('마감이 지났으면 남은 시간을 말하지 않는다', () {
      final summary = _summary(
        deadlineAt: _now.subtract(const Duration(minutes: 1)),
      );
      expect(summary.deadlineLineAt(_now), isNull);
    });

    test('마감 시각 그 순간에는 남은 시간을 말하지 않는다', () {
      expect(_summary(deadlineAt: _now).deadlineLineAt(_now), isNull);
    });

    test('모집 중처럼 마감이 없으면 남은 시간을 말하지 않는다', () {
      final summary = BattleSummary(
        battle: Battle(
          id: 'b1',
          type: 'speed',
          status: 'active',
          title: '책상 정리하기',
          creatorId: 'me',
          createdAt: DateTime(2026, 9, 16),
        ),
        otherPartyName: '친구',
      );
      expect(summary.deadlineLineAt(_now), isNull);
    });

    test('판정 창인데 판정 기한이 없으면 사진 마감으로 바꿔 말하지 않는다', () {
      final summary = _summary(
        status: 'judging',
        deadlineAt: _now.add(const Duration(hours: 3)),
      );
      expect(summary.deadlineLineAt(_now), isNull);
    });
  });
}
