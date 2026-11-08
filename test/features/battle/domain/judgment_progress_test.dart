import 'package:flutter_test/flutter_test.dart';
import 'package:todododo/features/battle/domain/judgment_progress.dart';
import 'package:todododo/features/battle/domain/judgment_rules.dart';

/// 판정 진행 줄(design-judging-buttons 1C 확장형). 서버 값만 읽고, 상대 판정은 "보냈는가"만 말한다.
void main() {
  const me = JudgmentProgressParty.me;
  const opponent = JudgmentProgressParty.opponent;
  const ai = JudgmentProgressParty.ai;
  const sent = JudgmentProgressState.sent;
  const waiting = JudgmentProgressState.waiting;

  List<JudgmentProgressRow> rows(JudgmentStage stage, {bool iSubmitted = true, bool opponentJudged = false}) =>
      judgmentProgressOf(stage: stage, iSubmitted: iSubmitted, opponentJudged: opponentJudged);

  test('판정 창이 아니거나 내 차례면 진행 줄이 없다', () {
    expect(rows(JudgmentStage.notOpen), isEmpty);
    expect(rows(JudgmentStage.myTurn), isEmpty);
  });

  test('상대 판정 대기: 내 판정 보냈어요, 상대 판정 기다리는 중, AI 줄 없음', () {
    expect(rows(JudgmentStage.waitingOpponent), [
      (party: me, state: sent),
      (party: opponent, state: waiting),
    ]);
  });

  test('AI 재판정 중: 내·상대 보냈어요 + AI 보고 있어요', () {
    expect(rows(JudgmentStage.waitingAi, opponentJudged: true), [
      (party: me, state: sent),
      (party: opponent, state: sent),
      (party: ai, state: JudgmentProgressState.reviewing),
    ]);
  });

  test('AI 재판정 중인데 내가 사진을 내지 않았으면 상대는 판정할 것이 없어 상대 줄을 뺀다', () {
    // 속도전 한쪽 제출: 내가 상대 사진을 불복 → AI. 상대는 판정할 대상이 없다.
    expect(rows(JudgmentStage.waitingAi, iSubmitted: false), [
      (party: me, state: sent),
      (party: ai, state: JudgmentProgressState.reviewing),
    ]);
  });

  test('판정할 것이 없음: 내 줄은 판정할 사진 없음, 상대 줄은 서버 값대로', () {
    expect(rows(JudgmentStage.nothingToJudge), [
      (party: me, state: JudgmentProgressState.nothingToJudge),
      (party: opponent, state: waiting),
    ]);
    expect(rows(JudgmentStage.nothingToJudge, opponentJudged: true)[1], (party: opponent, state: sent));
  });

  test('기한 경과: 내 줄은 기한 지남, 상대 줄은 서버 값대로, 내가 안 냈으면 상대 줄 없음', () {
    expect(rows(JudgmentStage.windowClosed), [
      (party: me, state: JudgmentProgressState.missedDeadline),
      (party: opponent, state: waiting),
    ]);
    expect(rows(JudgmentStage.windowClosed, opponentJudged: true)[1], (party: opponent, state: sent));
    expect(rows(JudgmentStage.windowClosed, iSubmitted: false), [
      (party: me, state: JudgmentProgressState.missedDeadline),
    ]);
  });

  test('상대 줄은 상대가 고른 내용을 담지 않는다(보냈는가 두 값뿐)', () {
    for (final stage in JudgmentStage.values) {
      for (final judged in [true, false]) {
        for (final row in rows(stage, opponentJudged: judged)) {
          if (row.party == opponent) expect(row.state, anyOf(sent, waiting));
        }
      }
    }
  });
}
