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
  _FakeBattleRepository({this.result = const SubmissionResult(submissionId: 1)});

  SubmissionResult result;
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
    return result;
  }

  @override
  Future<List<BattleSubmission>> fetchSubmissions(String battleId) async => const [];

  @override
  Future<String> createEvidencePhotoUrl(String path) async => 'https://example.com/$path';

  @override
  Future<PlayerCard> fetchPlayerCard(String userId) async =>
      const PlayerCard(userId: 'friend', displayName: '친구', score: 3, wins: 1, losses: 0, draws: 0);

  @override
  Future<String> createBattle({required String checkId, required int durationHours}) async => 'b';

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
  int attemptsUsed = 0,
  DateTime? passedAt,
  DateTime? opponentFirstSubmittedAt,
  String? opponentLastVerdict,
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
  );
  return BattleDetail(
    battle: battle,
    me: BattleParticipant(
      battleId: 'b1',
      userId: 'me',
      attemptsUsed: attemptsUsed,
      passedAt: passedAt,
    ),
    opponent: BattleParticipant(
      battleId: 'b1',
      userId: 'friend',
      firstSubmittedAt: opponentFirstSubmittedAt,
      lastVerdict: opponentLastVerdict,
    ),
    myName: '나',
    opponentName: '친구',
    submissions: submissions,
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

void main() {
  testWidgets('속도전 진행 중이면 사진 찍기 버튼과 남은 판정 횟수가 보인다', (tester) async {
    await tester.pumpWidget(_screen(_detail(), _FakeBattleRepository(), _FakeCamera()));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.battleEvidenceTakePhoto), findsOneWidget);
    expect(find.text(AppStrings.battleEvidenceAttemptsLeft(5)), findsOneWidget);
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

  testWidgets('불합격이면 사유가 보이고 다시 찍을 수 있다', (tester) async {
    final repository = _FakeBattleRepository(
      result: const SubmissionResult(
        submissionId: 7,
        verdict: 'failed',
        reason: '상판에 물건이 남아 있다',
        battleStatus: 'active',
      ),
    );
    await tester.pumpWidget(_screen(_detail(), repository, _FakeCamera()));
    await tester.pumpAndSettle();

    await tester.tap(find.text(AppStrings.battleEvidenceTakePhoto));
    await tester.pumpAndSettle();
    final submitButton = find.text(AppStrings.battleEvidenceSubmit);
    // 미리보기가 길어 제출 버튼이 기본 테스트 화면(800x600) 아래로 밀린다.
    await tester.ensureVisible(submitButton);
    await tester.pumpAndSettle();
    await tester.tap(submitButton);
    await tester.pumpAndSettle();

    expect(repository.submitCount, 1);
    // 촬영 시각은 UTC로 서버에 간다(서버가 수신 시각과 대조한다).
    expect(repository.sentCapturedAt!.isUtc, isTrue);
    expect(find.text(AppStrings.battleEvidenceFailedTitle), findsOneWidget);
    expect(find.text('상판에 물건이 남아 있다'), findsOneWidget);
    expect(find.text(AppStrings.battleEvidenceTakePhoto), findsOneWidget);
  });

  testWidgets('AI 판정이 실패하면 횟수가 차감되지 않았음을 알린다', (tester) async {
    final repository = _FakeBattleRepository(
      result: const SubmissionResult(submissionId: 8, verdict: 'error', battleStatus: 'active'),
    );
    await tester.pumpWidget(_screen(_detail(), repository, _FakeCamera()));
    await tester.pumpAndSettle();

    await tester.tap(find.text(AppStrings.battleEvidenceTakePhoto));
    await tester.pumpAndSettle();
    final submitButton = find.text(AppStrings.battleEvidenceSubmit);
    // 미리보기가 길어 제출 버튼이 기본 테스트 화면(800x600) 아래로 밀린다.
    await tester.ensureVisible(submitButton);
    await tester.pumpAndSettle();
    await tester.tap(submitButton);
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.battleEvidenceErrorTitle), findsOneWidget);
    expect(find.text(AppStrings.battleEvidenceErrorDetail), findsOneWidget);
  });

  testWidgets('통과한 뒤에는 제출이 잠기고 진행 중임을 알린다', (tester) async {
    final passedAt = DateTime.now().subtract(const Duration(hours: 1));
    final detail = _detail(
      attemptsUsed: 1,
      passedAt: passedAt,
      submissions: [
        BattleSubmission(
          id: 1,
          battleId: 'b1',
          userId: 'me',
          objectPath: null,
          capturedAt: passedAt,
          submittedAt: passedAt,
          status: 'passed',
          reason: '상판이 모두 보인다',
        ),
      ],
    );

    await tester.pumpWidget(_screen(detail, _FakeBattleRepository(), _FakeCamera()));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.battleEvidencePassedTitle), findsOneWidget);
    expect(find.text(AppStrings.battleEvidencePassedLocked), findsOneWidget);
    expect(find.text(AppStrings.battleEvidenceTakePhoto), findsNothing);
  });

  testWidgets('판정 5회를 다 쓰면 촬영 버튼이 사라진다', (tester) async {
    await tester.pumpWidget(
      _screen(_detail(attemptsUsed: 5), _FakeBattleRepository(), _FakeCamera()),
    );
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.battleEvidenceExhausted), findsOneWidget);
    expect(find.text(AppStrings.battleEvidenceTakePhoto), findsNothing);
  });

  testWidgets('상대 영역은 제출 사실과 합격/불합격만 보여 준다', (tester) async {
    final detail = _detail(
      opponentFirstSubmittedAt: DateTime.now().subtract(const Duration(minutes: 30)),
      opponentLastVerdict: 'passed',
    );

    await tester.pumpWidget(_screen(detail, _FakeBattleRepository(), _FakeCamera()));
    await tester.pumpAndSettle();

    expect(find.textContaining('제출했어요'), findsOneWidget);
    expect(find.textContaining(AppStrings.battleEvidenceVerdictPassed), findsWidgets);
    // 진행 중 상대의 사유는 서버가 주지 않으므로 화면에도 없다.
    expect(find.text('상판이 모두 보인다'), findsNothing);
  });

  testWidgets('상대가 아직 내지 않았으면 그 사실만 보인다', (tester) async {
    await tester.pumpWidget(_screen(_detail(), _FakeBattleRepository(), _FakeCamera()));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.battleEvidenceOpponentWaiting), findsOneWidget);
  });

  testWidgets('품질전은 아직 제출을 열지 않고 준비 중 안내를 보여 준다', (tester) async {
    await tester.pumpWidget(
      _screen(_detail(type: 'quality'), _FakeBattleRepository(), _FakeCamera()),
    );
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.battleSubmissionPreparing), findsOneWidget);
    expect(find.text(AppStrings.battleEvidenceTakePhoto), findsNothing);
  });
}
