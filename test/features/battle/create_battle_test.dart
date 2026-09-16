import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:todododo/core/strings.dart';
import 'package:todododo/features/battle/data/battle.dart';
import 'package:todododo/features/battle/data/battle_criteria_repository.dart';
import 'package:todododo/features/battle/data/battle_participant.dart';
import 'package:todododo/features/battle/data/battle_submission.dart';
import 'package:todododo/features/battle/data/submission_result.dart';
import 'package:todododo/features/battle/data/battle_repository.dart';
import 'package:todododo/features/battle/data/criteria_check_result.dart';
import 'package:todododo/features/battle/data/open_recruit.dart';
import 'package:todododo/features/battle/data/player_card.dart';
import 'package:todododo/features/battle/domain/battle_providers.dart';
import 'package:todododo/features/battle/presentation/create_battle_screen.dart';

class _FakeCriteriaRepository implements BattleCriteriaRepository {
  _FakeCriteriaRepository({this.generateResult, this.checkResult, this.generateError});

  CriteriaCheckResult? generateResult;
  CriteriaCheckResult? checkResult;
  Object? generateError;
  int generateCount = 0;
  int checkCount = 0;
  List<String>? lastCheckedMin;
  List<String>? lastCheckedSuperiority;

  @override
  Future<CriteriaCheckResult> generate({
    required String title,
    required String type,
    required int durationHours,
  }) async {
    generateCount++;
    final error = generateError;
    if (error != null) throw error;
    return generateResult!;
  }

  @override
  Future<CriteriaCheckResult> check({
    required String title,
    required String type,
    required int durationHours,
    required List<String> minCriteria,
    List<String>? superiorityCriteria,
    String? battleId,
  }) async {
    checkCount++;
    lastCheckedMin = minCriteria;
    lastCheckedSuperiority = superiorityCriteria;
    return checkResult!;
  }
}

class _FakeBattleRepository implements BattleRepository {
  String? createdCheckId;
  int? createdDuration;

  @override
  Future<String> createBattle({required String checkId, required int durationHours}) async {
    createdCheckId = checkId;
    createdDuration = durationHours;
    return 'new-battle';
  }

  @override
  Future<MyLimits> fetchMyLimits() async => const MyLimits(
        consented: true,
        hasPending: false,
        dailyBattleUsed: false,
        criteriaCallsLeft: 9,
      );

  @override
  Future<int> updateBattleCriteria({required String battleId, required String checkId}) async => 2;

  @override
  Future<List<OpenRecruit>> fetchOpenRecruits() async => const [];

  @override
  Future<PlayerCard> fetchPlayerCard(String userId) async =>
      const PlayerCard(userId: 'creator1', displayName: '친구');

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
  Future<String> createEvidencePhotoUrl(String path) async => 'https://example.com/$path';

  @override
  Future<List<BattleSubmission>> fetchSubmissions(String battleId) async => const [];

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

const _qualityResult = CriteriaCheckResult(
  checkId: 'check-1',
  provable: true,
  minCriteria: ['책상 상판이 보인다'],
  superiorityCriteria: ['먼지나 얼룩이 없다'],
  callsLeft: 9,
);

const _speedResult = CriteriaCheckResult(
  checkId: 'check-2',
  provable: true,
  minCriteria: ['운동화를 신고 밖에 있다'],
  callsLeft: 9,
);

const _blockedResult = CriteriaCheckResult(
  checkId: 'check-3',
  provable: false,
  blockReason: '사진으로 확인할 수 없는 미션이에요',
  callsLeft: 8,
);

Future<void> _pumpCreate(
  WidgetTester tester, {
  required _FakeCriteriaRepository criteria,
  _FakeBattleRepository? battles,
  MyLimits? limits,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        battleCriteriaRepositoryProvider.overrideWithValue(criteria),
        battleRepositoryProvider.overrideWithValue(battles ?? _FakeBattleRepository()),
        if (limits != null) myLimitsProvider.overrideWith((ref) async => limits),
      ],
      child: const MaterialApp(home: CreateBattleScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _enterTitleAndGenerate(WidgetTester tester, String title) async {
  await tester.enterText(find.byType(TextField).first, title);
  await tester.pumpAndSettle();
  await tester.tap(find.text(AppStrings.battleCriteriaGenerate));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('품질전은 최소 기준과 우열 기준 두 목록을 보여 주고 그대로 올릴 수 있다', (tester) async {
    final criteria = _FakeCriteriaRepository(generateResult: _qualityResult);
    final battles = _FakeBattleRepository();
    await _pumpCreate(tester, criteria: criteria, battles: battles);

    await tester.tap(find.text(AppStrings.battleTypeQuality));
    await tester.pumpAndSettle();
    await _enterTitleAndGenerate(tester, '책상 정리하기');

    expect(criteria.generateCount, 1);
    expect(find.text(AppStrings.battleCriteriaMinTitle), findsOneWidget);
    expect(find.text(AppStrings.battleCriteriaSuperiorityTitle), findsOneWidget);
    expect(find.text('책상 상판이 보인다'), findsOneWidget);
    expect(find.text('먼지나 얼룩이 없다'), findsOneWidget);

    await tester.tap(find.text(AppStrings.battleCriteriaSubmit));
    await tester.pumpAndSettle();

    // 서버에는 기준 텍스트가 아니라 증서 id만 넘어간다.
    expect(battles.createdCheckId, 'check-1');
    expect(battles.createdDuration, 72);
  });

  testWidgets('속도전에는 우열 기준 블록이 없다', (tester) async {
    final criteria = _FakeCriteriaRepository(generateResult: _speedResult);
    await _pumpCreate(tester, criteria: criteria);

    await _enterTitleAndGenerate(tester, '아침 운동하기');

    expect(find.text(AppStrings.battleCriteriaMinTitle), findsOneWidget);
    expect(find.text(AppStrings.battleCriteriaSuperiorityTitle), findsNothing);
  });

  testWidgets('증명할 수 없는 미션은 차단되고 제목 고치기만 할 수 있다', (tester) async {
    final criteria = _FakeCriteriaRepository(generateResult: _blockedResult);
    await _pumpCreate(tester, criteria: criteria);

    await _enterTitleAndGenerate(tester, '책 읽기');

    expect(find.text(AppStrings.battleCriteriaBlocked), findsOneWidget);
    expect(find.text('사진으로 확인할 수 없는 미션이에요'), findsOneWidget);
    // 차단이면 기준을 고쳐서 우회할 수 없다.
    expect(find.text(AppStrings.battleCriteriaSubmit), findsNothing);
    expect(find.text(AppStrings.battleCriteriaEdit), findsNothing);
    expect(find.text(AppStrings.battleCriteriaFixTitle), findsOneWidget);

    await tester.tap(find.text(AppStrings.battleCriteriaFixTitle));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.battleCriteriaGenerate), findsOneWidget);
  });

  testWidgets('기준을 고치면 다시 검사해야 올릴 수 있다', (tester) async {
    final criteria = _FakeCriteriaRepository(
      generateResult: _speedResult,
      checkResult: const CriteriaCheckResult(
        checkId: 'check-4',
        provable: true,
        minCriteria: ['운동화를 신고 공원에 있다'],
        callsLeft: 8,
      ),
    );
    final battles = _FakeBattleRepository();
    await _pumpCreate(tester, criteria: criteria, battles: battles);

    await _enterTitleAndGenerate(tester, '아침 운동하기');
    await tester.tap(find.text(AppStrings.battleCriteriaEdit));
    await tester.pumpAndSettle();

    // 마지막 TextField가 기준 입력칸이다(첫 칸은 제목).
    await tester.enterText(find.byType(TextField).last, '운동화를 신고 공원에 있다');
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.battleCriteriaRecheck), findsOneWidget);
    expect(find.text(AppStrings.battleCriteriaSubmit), findsNothing);

    await tester.tap(find.text(AppStrings.battleCriteriaRecheck));
    await tester.pumpAndSettle();

    expect(criteria.checkCount, 1);
    expect(criteria.lastCheckedMin, ['운동화를 신고 공원에 있다']);
    expect(criteria.lastCheckedSuperiority, isNull);
    expect(find.text(AppStrings.battleCriteriaSubmit), findsOneWidget);

    await tester.tap(find.text(AppStrings.battleCriteriaSubmit));
    await tester.pumpAndSettle();
    expect(battles.createdCheckId, 'check-4');
  });

  testWidgets('오늘 기준 만들기 횟수를 다 쓰면 안내가 뜨고 생성 버튼이 비활성이다', (tester) async {
    final criteria = _FakeCriteriaRepository();
    await _pumpCreate(
      tester,
      criteria: criteria,
      limits: const MyLimits(
        consented: true,
        hasPending: false,
        dailyBattleUsed: false,
        criteriaCallsLeft: 0,
      ),
    );

    await tester.enterText(find.byType(TextField).first, '아침 운동하기');
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.battleErrorCriteriaCallLimit), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, AppStrings.battleCriteriaGenerate),
    );
    expect(button.onPressed, isNull);
    expect(criteria.generateCount, 0);
  });

  testWidgets('모집 중인 대결이 이미 있으면 이유를 안내한다', (tester) async {
    await _pumpCreate(
      tester,
      criteria: _FakeCriteriaRepository(),
      limits: const MyLimits(
        consented: true,
        hasPending: true,
        dailyBattleUsed: false,
        criteriaCallsLeft: 9,
      ),
    );

    expect(find.text(AppStrings.battleErrorPendingExists), findsOneWidget);
  });

  testWidgets('AI 호출이 실패하면 횟수가 차감되지 않았다고 알리고 다시 시도할 수 있다', (tester) async {
    final criteria = _FakeCriteriaRepository(
      generateError: const CriteriaException('AI_FAILED', callsLeft: 9),
      generateResult: _speedResult,
    );
    await _pumpCreate(tester, criteria: criteria);

    await _enterTitleAndGenerate(tester, '아침 운동하기');

    expect(find.text(AppStrings.battleErrorAiFailed), findsOneWidget);
    expect(find.text(AppStrings.retry), findsOneWidget);

    // 다시 시도하면 같은 입력으로 한 번 더 부른다.
    criteria.generateError = null;
    await tester.tap(find.text(AppStrings.retry));
    await tester.pumpAndSettle();

    expect(criteria.generateCount, 2);
    expect(find.text('운동화를 신고 밖에 있다'), findsOneWidget);
  });
}
