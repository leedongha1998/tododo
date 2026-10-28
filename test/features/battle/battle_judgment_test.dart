import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:todododo/core/strings.dart';
import 'package:todododo/features/battle/data/battle.dart';
import 'package:todododo/features/battle/data/battle_participant.dart';
import 'package:todododo/features/battle/data/battle_repository.dart';
import 'package:todododo/features/battle/data/battle_submission.dart';
import 'package:todododo/features/battle/data/criteria_check_result.dart';
import 'package:todododo/features/battle/data/open_recruit_page.dart';
import 'package:todododo/features/battle/data/player_card.dart';
import 'package:todododo/features/battle/data/submission_result.dart';
import 'package:todododo/features/battle/data/vs_intro_seen_store.dart';
import 'package:todododo/features/battle/domain/battle_detail.dart';
import 'package:todododo/features/battle/domain/battle_providers.dart';
import 'package:todododo/features/battle/presentation/battle_detail_screen.dart';

/// 상호 판정 화면. 판정 **결론**은 서버가 내므로 여기서 보는 것은
/// "무엇을 묻는가 / 언제 보낼 수 있는가 / 무엇을 보냈는가"뿐이다.
class _FakeBattleRepository implements BattleRepository {
  int judgeCount = 0;
  bool? sentPassed;
  String? sentSuperiorId;
  Object? failWith;

  @override
  Future<String> submitJudgment({
    required String battleId,
    required bool passed,
    String? superiorId,
  }) async {
    judgeCount++;
    sentPassed = passed;
    sentSuperiorId = superiorId;
    final failure = failWith;
    if (failure != null) throw failure;
    return 'judging';
  }

  @override
  Future<String> createEvidencePhotoUrl(String path) async => 'https://example.com/$path';

  @override
  Future<PlayerCard> fetchPlayerCard(String userId) async => const PlayerCard(
        userId: 'friend',
        displayName: '친구',
        score: 3,
        wins: 1,
        losses: 0,
        draws: 0,
      );

  @override
  Future<List<BattleSubmission>> fetchSubmissions(String battleId) async => const [];

  @override
  Future<String> createBattle({required String checkId, required int durationMinutes}) async => 'b';

  @override
  Future<int> updateBattleCriteria({required String battleId, required String checkId}) async => 1;

  @override
  Future<MyLimits> fetchMyLimits() async => const MyLimits(
        consented: true,
        hasPending: false,
        dailyBattleUsed: false,
        criteriaCallsLeft: 10,
      );

  @override
  Future<OpenRecruitPage> fetchOpenRecruits({int limit = openRecruitPageSize, RecruitCursor? cursor, String? query, String? type, String? durationBand}) async => const OpenRecruitPage.empty();

  @override
  Future<Battle?> fetchOpenRecruitBattle(String battleId) async => null;

  @override
  Future<List<Battle>> fetchMyRecruits() async => const [];

  @override
  Future<Map<String, String>> fetchDisplayNames(Iterable<String> ids) async => {};

  @override
  Future<void> joinBattle(String battleId, int criteriaVersion) async {}

  @override
  Future<void> cancelBattle(String battleId) async {}

  @override
  Future<void> forfeitBattle(String battleId) async {}

  @override
  Future<List<Battle>> fetchMyBattles() async => const [];

  @override
  Future<Battle> fetchBattle(String battleId) => throw UnimplementedError();

  @override
  Future<List<BattleParticipant>> fetchParticipants(String battleId) async => const [];

  @override
  Future<List<BattleParticipant>> fetchParticipantsOf(Iterable<String> battleIds) async =>
      const [];

  @override
  Future<String> uploadEvidencePhoto({
    required String battleId,
    required Uint8List bytes,
  }) async =>
      '$battleId/me/photo.jpg';

  @override
  Future<SubmissionResult> submitEvidence({
    required String battleId,
    required String objectPath,
    required DateTime capturedAt,
  }) async =>
      const SubmissionResult(submissionId: 1);
}

class _SeenAllStore implements VsIntroSeenStore {
  const _SeenAllStore();

  @override
  Future<bool> hasSeen(String userId, String battleId) async => true;

  @override
  Future<void> markSeen(String userId, String battleId) async {}
}

const _opponentPhotoPath = 'b1/friend/photo.jpg';

BattleSubmission _submission({required int id, required String userId}) {
  final when = DateTime.now().subtract(const Duration(minutes: 10));
  return BattleSubmission(
    id: id,
    battleId: 'b1',
    userId: userId,
    objectPath: 'b1/$userId/photo.jpg',
    capturedAt: when,
    submittedAt: when,
  );
}

/// 판정 창이 열린 대결. 서버는 창이 열리는 순간 양쪽 제출 행과 판정 기한을 함께 내준다.
BattleDetail _judging({
  String type = 'speed',
  bool myHasSubmitted = true,
  bool opponentHasSubmitted = true,
  bool myHasJudged = false,
  bool opponentHasJudged = false,
  Duration judgeLeft = const Duration(hours: 23),
}) {
  final now = DateTime.now();
  final battle = Battle(
    id: 'b1',
    type: type,
    status: 'judging',
    title: '책상 정리하기',
    creatorId: 'me',
    opponentId: 'friend',
    createdAt: now.subtract(const Duration(hours: 2)),
    startedAt: now.subtract(const Duration(hours: 2)),
    deadlineAt: now.subtract(const Duration(minutes: 5)),
    judgingOpenedAt: now.subtract(const Duration(minutes: 5)),
    judgeDeadlineAt: now.add(judgeLeft),
    minCriteria: const ['상판이 보인다'],
    superiorityCriteria: type == 'quality' ? const ['먼지가 없다'] : null,
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
    submissions: [
      if (myHasSubmitted) _submission(id: 1, userId: 'me'),
      if (opponentHasSubmitted) _submission(id: 2, userId: 'friend'),
    ],
  );
}

Widget _screen(
  BattleDetail detail,
  _FakeBattleRepository repository, {
  AsyncValue<String>? photo,
}) {
  return ProviderScope(
    overrides: [
      battleDetailProvider(detail.battle.id).overrideWith((ref) async => detail),
      battleRepositoryProvider.overrideWithValue(repository),
      vsIntroSeenStoreProvider.overrideWithValue(const _SeenAllStore()),
      // 서명 URL 발급은 Storage 정책을 거친다. 성공/실패를 여기서 갈아 끼운다.
      if (photo != null)
        evidencePhotoUrlProvider(_opponentPhotoPath).overrideWith(
          (ref) => photo.when(
            data: (url) => Future.value(url),
            loading: () => Future<String>.error('loading은 쓰지 않는다'),
            error: (error, stackTrace) => Future<String>.error(error),
          ),
        ),
    ],
    child: MaterialApp(home: BattleDetailScreen(battleId: detail.battle.id)),
  );
}

/// 선택지는 사진·기준 아래라 기본 테스트 화면(800x600) 밖으로 밀린다.
Future<void> _tapChoice(WidgetTester tester, String label) async {
  final choice = find.text(label);
  await tester.ensureVisible(choice);
  await tester.pumpAndSettle();
  await tester.tap(choice);
  await tester.pumpAndSettle();
}

Future<void> _tapSend(WidgetTester tester) async {
  final send = find.widgetWithText(FilledButton, AppStrings.battleJudgmentSend).first;
  await tester.ensureVisible(send);
  await tester.pumpAndSettle();
  await tester.tap(send);
  await tester.pumpAndSettle();
}

void main() {
  const photoOk = AsyncValue<String>.data('https://example.com/$_opponentPhotoPath');

  testWidgets('속도전 판정은 통과/미통과 두 선택지만 묻는다', (tester) async {
    await tester.pumpWidget(_screen(_judging(), _FakeBattleRepository(), photo: photoOk));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.battleJudgmentMinQuestion), findsOneWidget);
    expect(find.text(AppStrings.battleJudgmentPassed), findsOneWidget);
    expect(find.text(AppStrings.battleJudgmentFailed), findsOneWidget);
    // 속도전에는 우열 질문이 없다(서버도 우열 값을 받으면 거부한다).
    expect(find.text(AppStrings.battleJudgmentSuperiorityQuestion), findsNothing);
    // 판정할 기준이 함께 보인다.
    expect(find.text('상판이 보인다'), findsOneWidget);
    // 자유 텍스트 입력은 어디에도 없다.
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('아무것도 고르지 않으면 판정을 보낼 수 없다', (tester) async {
    final repository = _FakeBattleRepository();
    await tester.pumpWidget(_screen(_judging(), repository, photo: photoOk));
    await tester.pumpAndSettle();

    final send = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, AppStrings.battleJudgmentSend).first,
    );
    expect(send.onPressed, isNull);
    expect(repository.judgeCount, 0);
  });

  testWidgets('속도전: 통과를 고르고 확인하면 승인이 서버로 간다', (tester) async {
    final repository = _FakeBattleRepository();
    await tester.pumpWidget(_screen(_judging(), repository, photo: photoOk));
    await tester.pumpAndSettle();

    await _tapChoice(tester, AppStrings.battleJudgmentPassed);
    await _tapSend(tester);

    // 되돌릴 수 없으니 확인 전에는 보내지 않는다.
    expect(find.text(AppStrings.battleJudgmentConfirm), findsOneWidget);
    expect(repository.judgeCount, 0);

    await tester.tap(find.widgetWithText(FilledButton, AppStrings.battleJudgmentSend).last);
    await tester.pumpAndSettle();

    expect(repository.judgeCount, 1);
    expect(repository.sentPassed, isTrue);
    // 속도전은 우열을 매기지 않는다.
    expect(repository.sentSuperiorId, isNull);
  });

  testWidgets('품질전은 최소 기준과 우열을 한 화면에서 묻고 둘 다 고르기 전에는 못 보낸다', (tester) async {
    final repository = _FakeBattleRepository();
    await tester.pumpWidget(
      _screen(_judging(type: 'quality'), repository, photo: photoOk),
    );
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.battleJudgmentMinQuestion), findsOneWidget);
    expect(find.text(AppStrings.battleJudgmentSuperiorityQuestion), findsOneWidget);
    expect(find.text(AppStrings.battleJudgmentSuperiorMe), findsOneWidget);
    expect(find.text(AppStrings.battleJudgmentSuperiorOpponent), findsOneWidget);
    // 우열 기준도 함께 보인다.
    expect(find.text('먼지가 없다'), findsOneWidget);

    FilledButton sendButton() => tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, AppStrings.battleJudgmentSend).first,
        );

    // 최소 기준만 골라도 아직 보낼 수 없다(서버도 SUPERIORITY_REQUIRED로 거부한다).
    await _tapChoice(tester, AppStrings.battleJudgmentPassed);
    expect(sendButton().onPressed, isNull);

    await _tapChoice(tester, AppStrings.battleJudgmentSuperiorOpponent);
    expect(sendButton().onPressed, isNotNull);

    await _tapSend(tester);
    await tester.tap(find.widgetWithText(FilledButton, AppStrings.battleJudgmentSend).last);
    await tester.pumpAndSettle();

    expect(repository.judgeCount, 1);
    expect(repository.sentPassed, isTrue);
    // 고른 사람의 user id가 그대로 간다(상대적 값이 아니다).
    expect(repository.sentSuperiorId, 'friend');
  });

  testWidgets('불복을 고르면 AI가 다시 본다는 안내가 함께 보이고 불복이 서버로 간다', (tester) async {
    final repository = _FakeBattleRepository();
    await tester.pumpWidget(_screen(_judging(), repository, photo: photoOk));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.battleJudgmentRejectHint), findsOneWidget);

    await _tapChoice(tester, AppStrings.battleJudgmentFailed);
    await _tapSend(tester);
    await tester.tap(find.widgetWithText(FilledButton, AppStrings.battleJudgmentSend).last);
    await tester.pumpAndSettle();

    expect(repository.sentPassed, isFalse);
  });

  testWidgets('상대 사진을 받아오지 못하면 판정을 보낼 수 없다', (tester) async {
    final repository = _FakeBattleRepository();
    await tester.pumpWidget(
      _screen(
        _judging(),
        repository,
        photo: AsyncValue<String>.error('forbidden', StackTrace.empty),
      ),
    );
    await tester.pumpAndSettle();

    await _tapChoice(tester, AppStrings.battleJudgmentPassed);

    final send = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, AppStrings.battleJudgmentSend).first,
    );
    expect(send.onPressed, isNull);
    expect(find.text(AppStrings.battleJudgmentPhotoUnavailable), findsOneWidget);
  });

  testWidgets('판정을 보낸 뒤에는 상대 판정 대기 안내만 보인다', (tester) async {
    await tester.pumpWidget(
      _screen(_judging(myHasJudged: true), _FakeBattleRepository(), photo: photoOk),
    );
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.battleJudgmentSentTitle), findsOneWidget);
    expect(find.text(AppStrings.battleJudgmentWaitingOpponent), findsOneWidget);
    expect(find.text(AppStrings.battleJudgmentSend), findsNothing);
  });

  // 양쪽 판정이 끝났는데 아직 judging이면 불복 건의 AI 재판정이 남은 것이다.
  testWidgets('양쪽 판정이 끝나고도 judging이면 AI 재판정 중이라고 알린다', (tester) async {
    await tester.pumpWidget(
      _screen(
        _judging(myHasJudged: true, opponentHasJudged: true),
        _FakeBattleRepository(),
        photo: photoOk,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.battleJudgmentAiTitle), findsOneWidget);
    expect(find.text(AppStrings.battleJudgmentSend), findsNothing);
  });

  testWidgets('상대가 사진을 내지 않았으면 판정할 것이 없다고 알린다', (tester) async {
    await tester.pumpWidget(
      _screen(_judging(opponentHasSubmitted: false), _FakeBattleRepository()),
    );
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.battleJudgmentNothingTitle), findsOneWidget);
    expect(find.text(AppStrings.battleJudgmentSend), findsNothing);
  });

  testWidgets('판정 기한이 지나면 판정 입력 대신 자동 처리 안내가 보인다', (tester) async {
    await tester.pumpWidget(
      _screen(
        _judging(judgeLeft: const Duration(minutes: -1)),
        _FakeBattleRepository(),
        photo: photoOk,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.battleJudgmentWindowClosedTitle), findsOneWidget);
    expect(find.text(AppStrings.battleJudgmentSend), findsNothing);
  });

  testWidgets('서버가 거부하면 코드별 문구를 띄우고 화면을 유지한다', (tester) async {
    final repository = _FakeBattleRepository()..failWith = Exception('boom');
    await tester.pumpWidget(_screen(_judging(), repository, photo: photoOk));
    await tester.pumpAndSettle();

    await _tapChoice(tester, AppStrings.battleJudgmentPassed);
    await _tapSend(tester);
    await tester.tap(find.widgetWithText(FilledButton, AppStrings.battleJudgmentSend).last);
    await tester.pumpAndSettle();

    expect(repository.judgeCount, 1);
    expect(find.text(AppStrings.battleJudgmentSendFailed), findsOneWidget);
  });

  // 포기 버튼이 judging에도 있는지는 widget_test가 덮는다. 여기서는 제출 자리가 닫혔는지만 본다.
  testWidgets('판정 창에서는 제출·교체 자리가 없다', (tester) async {
    await tester.pumpWidget(_screen(_judging(), _FakeBattleRepository(), photo: photoOk));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.battleEvidenceTakePhoto), findsNothing);
    expect(find.text(AppStrings.battleEvidenceReplace), findsNothing);
  });

  testWidgets('헤더가 사진 마감과 판정 마감을 다른 줄로 보여 준다', (tester) async {
    await tester.pumpWidget(_screen(_judging(), _FakeBattleRepository(), photo: photoOk));
    await tester.pumpAndSettle();

    expect(
      find.text('${AppStrings.battleSubmitDeadlineLabel} · ${AppStrings.battleDeadlineClosed}'),
      findsOneWidget,
    );
    expect(
      find.textContaining(AppStrings.battleJudgeDeadlineLabel),
      findsOneWidget,
    );
  });
}
