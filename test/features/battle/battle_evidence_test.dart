import 'dart:convert';
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
import 'package:todododo/features/battle/data/evidence_camera.dart';
import 'package:todododo/features/battle/data/open_recruit.dart';
import 'package:todododo/features/battle/data/player_card.dart';
import 'package:todododo/features/battle/data/submission_result.dart';
import 'package:todododo/features/battle/data/vs_intro_seen_store.dart';
import 'package:todododo/features/battle/domain/battle_detail.dart';
import 'package:todododo/features/battle/domain/battle_providers.dart';
import 'package:todododo/features/battle/presentation/battle_detail_screen.dart';

/// 1x1 PNG. 미리보기 틀이 진짜 사진을 그리게 하려고 쓴다.
final _photoBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

class _FakeCamera implements EvidenceCamera {
  int captureCount = 0;

  @override
  Future<EvidenceShot?> capture() async {
    captureCount++;
    return EvidenceShot(bytes: _photoBytes, capturedAt: DateTime.utc(2026, 9, 16, 3));
  }
}

class _FakeBattleRepository implements BattleRepository {
  String? uploadedBattleId;
  DateTime? sentCapturedAt;
  int submitCount = 0;

  @override
  Future<String> uploadEvidencePhoto({
    required String battleId,
    required Uint8List bytes,
  }) async {
    uploadedBattleId = battleId;
    return '$battleId/me/photo.jpg';
  }

  @override
  Future<SubmissionResult> submitEvidence({
    required String battleId,
    required String objectPath,
    required DateTime capturedAt,
  }) async {
    submitCount++;
    sentCapturedAt = capturedAt;
    return const SubmissionResult(submissionId: 1);
  }

  @override
  Future<List<BattleSubmission>> fetchSubmissions(String battleId) async => const [];

  @override
  Future<String> createEvidencePhotoUrl(String path) async => 'https://example.com/$path';

  @override
  Future<PlayerCard> fetchPlayerCard(String userId) async =>
      const PlayerCard(userId: 'friend', displayName: '친구', score: 3, wins: 1, losses: 0, draws: 0);

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
  Future<List<OpenRecruit>> fetchOpenRecruits() async => const [];

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
}

class _SeenAllStore implements VsIntroSeenStore {
  const _SeenAllStore();

  @override
  Future<bool> hasSeen(String userId, String battleId) async => true;

  @override
  Future<void> markSeen(String userId, String battleId) async {}
}

BattleDetail _detail({
  String type = 'speed',
  String status = 'active',
  bool mySubmitted = false,
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
    deadlineAt: DateTime.now().add(const Duration(days: 1)),
    minCriteria: const ['상판이 보인다'],
    superiorityCriteria: type == 'quality' ? const ['먼지가 없다'] : null,
    judgingOpenedAt: status == 'judging' ? DateTime.now() : null,
    judgeDeadlineAt: status == 'judging' ? DateTime.now().add(const Duration(hours: 24)) : null,
  );
  return BattleDetail(
    battle: battle,
    me: BattleParticipant(battleId: 'b1', userId: 'me', hasSubmitted: mySubmitted),
    opponent: BattleParticipant(battleId: 'b1', userId: 'friend', hasSubmitted: opponentSubmitted),
    myName: '나',
    opponentName: '친구',
    submissions: submissions,
  );
}

BattleSubmission _submission({
  int id = 1,
  String userId = 'me',
  bool? meetsCriteria,
  String? verdictSource,
  String? reason,
}) {
  final when = DateTime.now().subtract(const Duration(hours: 2));
  return BattleSubmission(
    id: id,
    battleId: 'b1',
    userId: userId,
    objectPath: null,
    capturedAt: when,
    submittedAt: when,
    meetsCriteria: meetsCriteria,
    verdictSource: verdictSource,
    reason: reason,
  );
}

Widget _screen(BattleDetail detail, _FakeBattleRepository repository, _FakeCamera camera) {
  return ProviderScope(
    overrides: [
      battleDetailProvider(detail.battle.id).overrideWith((ref) async => detail),
      battleRepositoryProvider.overrideWithValue(repository),
      evidenceCameraProvider.overrideWithValue(camera),
      vsIntroSeenStoreProvider.overrideWithValue(const _SeenAllStore()),
    ],
    child: MaterialApp(home: BattleDetailScreen(battleId: detail.battle.id)),
  );
}

Future<void> _captureAndTapSubmit(WidgetTester tester, String submitLabel) async {
  await tester.tap(find.text(AppStrings.battleEvidenceTakePhoto));
  await tester.pumpAndSettle();
  final submitButton = find.text(submitLabel);
  // 미리보기가 길어 제출 버튼이 기본 테스트 화면(800x600) 아래로 밀린다.
  await tester.ensureVisible(submitButton);
  await tester.pumpAndSettle();
  await tester.tap(submitButton);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('속도전 제출 창이면 사진 찍기 버튼과 제출 시각 안내가 보인다', (tester) async {
    await tester.pumpWidget(_screen(_detail(), _FakeBattleRepository(), _FakeCamera()));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.battleEvidenceTakePhoto), findsOneWidget);
    expect(find.text(AppStrings.battleEvidenceSpeedHint), findsOneWidget);
    // 갤러리에서 고르는 길은 어디에도 없다.
    expect(find.textContaining('갤러리'), findsNothing);
  });

  testWidgets('사진을 찍으면 미리보기와 제출·다시 찍기가 나온다', (tester) async {
    final camera = _FakeCamera();
    await tester.pumpWidget(_screen(_detail(), _FakeBattleRepository(), camera));
    await tester.pumpAndSettle();

    await tester.tap(find.text(AppStrings.battleEvidenceTakePhoto));
    await tester.pumpAndSettle();

    expect(camera.captureCount, 1);
    expect(find.text(AppStrings.battleEvidenceSubmit), findsOneWidget);
    expect(find.text(AppStrings.battleEvidenceRetake), findsOneWidget);
  });

  testWidgets('속도전은 확인 없이 바로 제출하고 촬영 시각을 UTC로 보낸다', (tester) async {
    final repository = _FakeBattleRepository();
    await tester.pumpWidget(_screen(_detail(), repository, _FakeCamera()));
    await tester.pumpAndSettle();

    await _captureAndTapSubmit(tester, AppStrings.battleEvidenceSubmit);

    expect(repository.submitCount, 1);
    expect(repository.uploadedBattleId, 'b1');
    // 촬영 시각은 UTC로 서버에 간다(서버가 수신 시각과 대조한다).
    expect(repository.sentCapturedAt!.isUtc, isTrue);
  });

  testWidgets('제출한 뒤에는 제출 완료와 판정이 언제 시작되는지 보인다', (tester) async {
    await tester.pumpWidget(
      _screen(
        _detail(mySubmitted: true, submissions: [_submission()]),
        _FakeBattleRepository(),
        _FakeCamera(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.battleEvidenceSubmittedTitle), findsOneWidget);
    expect(find.text(AppStrings.battleEvidenceWaitingOpponent), findsOneWidget);
    expect(find.text(AppStrings.battleEvidenceTakePhoto), findsNothing);
  });

  testWidgets('상대 영역은 제출 사실만 보여 준다(시각·합격 여부 없음)', (tester) async {
    await tester.pumpWidget(
      _screen(_detail(opponentSubmitted: true), _FakeBattleRepository(), _FakeCamera()),
    );
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.battleEvidenceOpponentSubmitted), findsOneWidget);
    expect(find.text(AppStrings.battleEvidenceVerdictPassed), findsNothing);
    expect(find.text(AppStrings.battleEvidenceVerdictFailed), findsNothing);
  });

  testWidgets('상대가 아직 내지 않았으면 그 사실만 보인다', (tester) async {
    await tester.pumpWidget(_screen(_detail(), _FakeBattleRepository(), _FakeCamera()));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.battleEvidenceOpponentWaiting), findsOneWidget);
  });

  testWidgets('품질전은 확인 다이얼로그를 거쳐야 제출된다', (tester) async {
    final repository = _FakeBattleRepository();
    await tester.pumpWidget(_screen(_detail(type: 'quality'), repository, _FakeCamera()));
    await tester.pumpAndSettle();

    // 품질전에는 "한 번만" 안내가 붙는다.
    expect(find.text(AppStrings.battleEvidenceQualityOnce), findsOneWidget);
    expect(find.text(AppStrings.battleEvidenceSpeedHint), findsNothing);

    await _captureAndTapSubmit(tester, AppStrings.battleEvidenceQualitySubmit);

    // 확인하기 전에는 제출하지 않는다(재제출 수단이 없으므로).
    expect(find.text(AppStrings.battleEvidenceQualityConfirm), findsOneWidget);
    expect(repository.submitCount, 0);

    await tester.tap(find.text(AppStrings.battleEvidenceSubmit));
    await tester.pumpAndSettle();

    expect(repository.submitCount, 1);
  });

  testWidgets('판정 창에서는 제출 자리 대신 판정 안내와 양쪽 제출이 보인다', (tester) async {
    await tester.pumpWidget(
      _screen(
        _detail(
          status: 'judging',
          mySubmitted: true,
          opponentSubmitted: true,
          submissions: [_submission(id: 1), _submission(id: 2, userId: 'friend')],
        ),
        _FakeBattleRepository(),
        _FakeCamera(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.battleJudgingTitle), findsOneWidget);
    expect(find.text(AppStrings.battleJudgingPreparing), findsOneWidget);
    expect(find.text(AppStrings.battleEvidenceTakePhoto), findsNothing);
    // 양쪽 모두 아직 결론이 없다.
    expect(find.text(AppStrings.battleEvidenceVerdictPending), findsNWidgets(2));
    // 헤더에 사진 마감 대신 판정 마감이 나온다.
    expect(find.textContaining('${AppStrings.battleJudgeDeadlineLabel} '), findsWidgets);
    expect(find.textContaining(AppStrings.battleDeadlineLabel), findsNothing);
  });

  testWidgets('속도전에서 상대가 내지 않고 마감됐으면 판정할 것이 없다고 알린다', (tester) async {
    await tester.pumpWidget(
      _screen(
        _detail(status: 'judging', mySubmitted: true, submissions: [_submission()]),
        _FakeBattleRepository(),
        _FakeCamera(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.battleJudgingNothingToJudge), findsOneWidget);
  });

  // 종결 후에는 양쪽이 서로의 증거와 결론을 볼 수 있다.
  // 그 전에 가리는 일은 서버(RLS)가 하므로, 화면은 받은 행을 그대로 보여 주기만 한다.
  testWidgets('종결된 뒤에는 양쪽 제출이 결론·AI 사유와 함께 열린다', (tester) async {
    await tester.pumpWidget(
      _screen(
        _detail(
          status: 'finished',
          submissions: [
            _submission(id: 1, meetsCriteria: true, verdictSource: 'opponent'),
            _submission(
              id: 2,
              userId: 'friend',
              meetsCriteria: false,
              verdictSource: 'ai',
              reason: '물건이 그대로 남아 있다',
            ),
          ],
        ),
        _FakeBattleRepository(),
        _FakeCamera(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.battleEvidenceVerdictPassed), findsOneWidget);
    expect(find.text(AppStrings.battleEvidenceVerdictFailed), findsOneWidget);
    expect(find.text('물건이 그대로 남아 있다'), findsOneWidget);
    // 끝난 대결에는 제출 자리가 없다.
    expect(find.text(AppStrings.battleEvidenceTakePhoto), findsNothing);
  });
}
