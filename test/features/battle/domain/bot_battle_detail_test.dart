import 'package:flutter_test/flutter_test.dart';
import 'package:todododo/features/battle/data/battle.dart';
import 'package:todododo/features/battle/data/battle_participant.dart';
import 'package:todododo/features/battle/data/battle_submission.dart';
import 'package:todododo/features/battle/domain/battle_detail.dart';

final _now = DateTime(2026, 11, 21, 12);

/// 연습 대결(봇전) 상세. 서버가 준 `is_bot` 하나에서 화면 분기가 갈린다 —
/// 봇의 uuid도, 봇의 목표 시각도 앱에 들어오지 않는다.
BattleDetail _botDetail({
  bool isBot = true,
  String status = 'active',
  bool myHasSubmitted = false,
  List<BattleSubmission> submissions = const [],
}) {
  final battle = Battle(
    id: 'b1',
    type: 'speed',
    status: status,
    title: '설거지하기',
    creatorId: 'me',
    opponentId: 'bot',
    createdAt: _now,
    startedAt: _now,
    deadlineAt: _now.add(const Duration(minutes: 10)),
    judgingOpenedAt: status == 'active' ? null : _now,
    durationMinutes: 10,
    minCriteria: const ['싱크대 안에 씻지 않은 그릇이나 컵이 보이지 않는다'],
    isBot: isBot,
    botTopicId: isBot ? 't1' : null,
  );
  return BattleDetail(
    battle: battle,
    me: BattleParticipant(battleId: 'b1', userId: 'me', hasSubmitted: myHasSubmitted),
    opponent: const BattleParticipant(battleId: 'b1', userId: 'bot', hasSubmitted: false),
    myName: '나',
    opponentName: '연습 봇',
    submissions: submissions,
  );
}

BattleSubmission _submission({
  required String userId,
  required DateTime submittedAt,
  String? objectPath,
  DateTime? capturedAt,
  String? verdictSource,
}) =>
    BattleSubmission(
      id: userId == 'me' ? 1 : 2,
      battleId: 'b1',
      userId: userId,
      objectPath: objectPath,
      capturedAt: capturedAt,
      submittedAt: submittedAt,
      verdictSource: verdictSource,
    );

void main() {
  test('봇전이면 판정 섹션을 그리지 않는다 — 묻는 것이 없다', () {
    // 봇은 사진을 내지 않아 판정할 증거가 없고, 불복이라는 입력이 서버에 들어올 수 없어야
    // AI 재판정 경로가 닫힌다(봇전 1판의 AI 호출 0회가 합격선이다).
    final judging = _botDetail(status: 'judging');
    expect(judging.isJudging, isTrue);
    expect(judging.showsJudgmentQuestions, isFalse);

    // 사람 대결은 그대로 묻는다.
    final human = _botDetail(isBot: false, status: 'judging');
    expect(human.showsJudgmentQuestions, isTrue);
  });

  test('봇전이면 상대 전적을 조회하지 않는다', () {
    expect(_botDetail().showsOpponentStats, isFalse);
    expect(_botDetail(isBot: false).showsOpponentStats, isTrue);
  });

  test('봇의 완료 시각은 서버가 그 제출 행을 내준 뒤에만 있다', () {
    // 진행 중에는 RLS가 상대 행을 주지 않으므로 알 길이 없다(미리 보여 주지 않는다).
    expect(_botDetail().botDoneAt, isNull);

    final doneAt = _now.add(const Duration(minutes: 6));
    final finished = _botDetail(
      status: 'finished',
      submissions: [_submission(userId: 'bot', submittedAt: doneAt, verdictSource: 'auto')],
    );
    expect(finished.botDoneAt, doneAt);
  });

  test('사람 대결에서는 봇 완료 시각을 묻지 않는다', () {
    final human = _botDetail(
      isBot: false,
      status: 'finished',
      submissions: [
        _submission(
          userId: 'bot',
          submittedAt: _now,
          objectPath: 'b1/friend/1.jpg',
          capturedAt: _now,
        ),
      ],
    );
    expect(human.botDoneAt, isNull);
  });

  test('내 사진은 "봇이 판정하지 않아 그대로 인정됐다"로 설명된다', () {
    final finished = _botDetail(
      status: 'finished',
      myHasSubmitted: true,
      submissions: [
        _submission(
          userId: 'me',
          submittedAt: _now.add(const Duration(minutes: 3)),
          objectPath: 'b1/me/1.jpg',
          capturedAt: _now.add(const Duration(minutes: 3)),
          verdictSource: 'auto',
        ),
      ],
    );
    expect(finished.wasMySubmissionAutoApproved, isTrue);

    // 사람 대결의 `auto`는 "판정 기한이 지나 자동 승인"이라 다른 말이어야 한다.
    final human = _botDetail(
      isBot: false,
      status: 'finished',
      myHasSubmitted: true,
      submissions: [
        _submission(
          userId: 'me',
          submittedAt: _now,
          objectPath: 'b1/me/1.jpg',
          capturedAt: _now,
          verdictSource: 'auto',
        ),
      ],
    );
    expect(human.wasMySubmissionAutoApproved, isFalse);
  });

  test('주기 재조회는 내 사진을 이미 낸 진행 중 봇전에서만 돈다', () {
    expect(_botDetail(myHasSubmitted: true).needsBotSettlePolling, isTrue);
    // 아직 내지 않았으면 할 일이 "사진 찍기"이고, 봇이 완료해도 내 첫 제출로 끝난다.
    expect(_botDetail().needsBotSettlePolling, isFalse);
    // 끝난 대결은 더 바뀔 것이 없다.
    expect(_botDetail(status: 'finished', myHasSubmitted: true).needsBotSettlePolling, isFalse);
    // 사람 대결에는 이 비용을 들이지 않는다.
    expect(_botDetail(isBot: false, myHasSubmitted: true).needsBotSettlePolling, isFalse);
  });

  test('봇전도 사진 교체는 사람 대결과 같은 규칙이다', () {
    // 잠기는 시점은 서버만 안다(봇의 목표 시각). 그래서 화면은 막지 않고, 서버가
    // SUBMISSION_LOCKED로 거부하면 그 문구를 봇전용으로 바꿔 말한다.
    final detail = _botDetail(myHasSubmitted: true);
    expect(detail.canSubmitEvidenceAt(_now), isTrue);
    expect(detail.isReplacingEvidenceAt(_now), isTrue);
    // 마감이 지나면 양쪽 다 닫힌다.
    final past = _now.add(const Duration(minutes: 11));
    expect(detail.canSubmitEvidenceAt(past), isFalse);
    expect(detail.isReplacingEvidenceAt(past), isFalse);
  });
}
