import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import 'package:todododo/core/strings.dart';
import 'package:todododo/features/battle/domain/judgment_rules.dart';

final _now = DateTime.utc(2026, 10, 28, 12);
final _laterDeadline = _now.add(const Duration(hours: 23));
final _pastDeadline = _now.subtract(const Duration(minutes: 1));

JudgmentStage _stage({
  String status = 'judging',
  bool opponentSubmitted = true,
  bool iSubmitted = true,
  bool iJudged = false,
  bool opponentJudged = false,
  DateTime? judgeDeadlineAt,
}) {
  return judgmentStageOf(
    status: status,
    opponentSubmitted: opponentSubmitted,
    iSubmitted: iSubmitted,
    iJudged: iJudged,
    opponentJudged: opponentJudged,
    judgeDeadlineAt: judgeDeadlineAt ?? _laterDeadline,
    now: _now,
  );
}

void main() {
  group('judgmentStageOf — 판정 창 단계', () {
    test('판정 창이 아니면 판정 영역이 없다', () {
      for (final status in ['pending', 'active', 'finished', 'draw', 'voided', 'cancelled']) {
        expect(_stage(status: status), JudgmentStage.notOpen, reason: status);
      }
    });

    test('상대가 제출하지 않았으면 내가 판정할 증거가 없다', () {
      expect(
        _stage(opponentSubmitted: false),
        JudgmentStage.nothingToJudge,
      );
    });

    test('상대 증거가 있고 내가 아직 판정하지 않았으면 내 차례다', () {
      expect(_stage(), JudgmentStage.myTurn);
    });

    test('판정 기한이 지났으면 내 차례가 아니라 자동 처리 대기다', () {
      expect(
        _stage(judgeDeadlineAt: _pastDeadline),
        JudgmentStage.windowClosed,
      );
    });

    // 서버가 창을 열 때 judge_deadline_at을 함께 찍는다(제약으로 강제). 값이 없는 judging은
    // 있을 수 없지만, 들어오면 판정을 받지 않는 쪽으로 닫는다.
    test('판정 기한이 없는 judging은 판정을 받지 않는다', () {
      expect(
        judgmentStageOf(
          status: 'judging',
          opponentSubmitted: true,
          iSubmitted: true,
          iJudged: false,
          opponentJudged: false,
          judgeDeadlineAt: null,
          now: _now,
        ),
        JudgmentStage.windowClosed,
      );
    });

    test('내 판정을 보냈고 상대가 아직 판정하지 않았으면 상대를 기다린다', () {
      expect(
        _stage(iJudged: true),
        JudgmentStage.waitingOpponent,
      );
    });

    test('양쪽 판정이 끝났는데 아직 judging이면 AI 재판정이 남은 것이다', () {
      expect(
        _stage(iJudged: true, opponentJudged: true),
        JudgmentStage.waitingAi,
      );
    });

    // 속도전 한쪽 제출에서 내가 비제출자인 경우. 상대는 판정할 증거가 없으므로 상대 판정을
    // 기다리지 않는다 — 내 판정이 마지막 판정이다.
    test('내가 제출하지 않았으면 상대 판정을 기다리지 않는다', () {
      expect(
        _stage(iSubmitted: false, iJudged: true),
        JudgmentStage.waitingAi,
      );
    });

    // 기한이 지나도 내가 이미 판정했으면 서버가 상대 몫만 자동 승인으로 채운다.
    test('내가 판정한 뒤 기한이 지나면 자동 처리 안내가 아니라 대기 안내가 맞다', () {
      expect(
        _stage(iJudged: true, judgeDeadlineAt: _pastDeadline),
        JudgmentStage.waitingOpponent,
      );
    });
  });

  group('judgmentErrorMessage — 서버 거부 코드', () {
    String messageOf(String? hint) => judgmentErrorMessage(
          PostgrestException(message: 'server message', hint: hint),
        );

    test('코드마다 무엇이 문제인지 다르게 말한다', () {
      expect(messageOf('JUDGING_NOT_OPEN'), AppStrings.battleErrorJudgingNotOpen);
      expect(messageOf('JUDGE_WINDOW_CLOSED'), AppStrings.battleErrorJudgeWindowClosed);
      expect(messageOf('ALREADY_JUDGED'), AppStrings.battleErrorAlreadyJudged);
      expect(messageOf('NOTHING_TO_JUDGE'), AppStrings.battleErrorNothingToJudge);
      expect(messageOf('SUPERIORITY_REQUIRED'), AppStrings.battleErrorSuperiorityRequired);
    });

    test('모르는 코드와 코드 없는 오류는 일반 실패 문구로 말한다', () {
      expect(messageOf('WHAT_IS_THIS'), AppStrings.battleJudgmentSendFailed);
      expect(messageOf(null), AppStrings.battleJudgmentSendFailed);
      expect(judgmentErrorMessage(Exception('네트워크')), AppStrings.battleJudgmentSendFailed);
    });

    test('서버 메시지를 그대로 보여 주지 않는다', () {
      expect(messageOf('ALREADY_JUDGED'), isNot(contains('server message')));
    });
  });
}
