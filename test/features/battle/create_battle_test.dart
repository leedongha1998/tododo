import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:todododo/core/navigation/app_tab.dart';
import 'package:todododo/core/strings.dart';
import 'package:todododo/core/theme/app_palette.dart';
import 'package:todododo/core/theme/app_theme.dart';
import 'package:todododo/features/battle/data/battle.dart';
import 'package:todododo/features/battle/data/battle_criteria_repository.dart';
import 'package:todododo/features/battle/data/battle_participant.dart';
import 'package:todododo/features/battle/data/battle_submission.dart';
import 'package:todododo/features/battle/data/submission_result.dart';
import 'package:todododo/features/battle/data/battle_repository.dart';
import 'package:todododo/features/battle/data/criteria_check_result.dart';
import 'package:todododo/features/battle/data/open_recruit_page.dart';
import 'package:todododo/features/battle/data/player_card.dart';
import 'package:todododo/features/battle/domain/battle_providers.dart';
import 'package:todododo/features/battle/domain/criteria_rules.dart';
import 'package:todododo/features/battle/domain/duration_rules.dart';
import 'package:todododo/features/battle/presentation/battle_chips.dart';
import 'package:todododo/features/battle/presentation/create_battle_screen.dart';
import '../../helpers/text_finders.dart';

class _FakeCriteriaRepository implements BattleCriteriaRepository {
  _FakeCriteriaRepository({
    this.generateResult,
    this.checkResult,
    this.generateError,
    this.checkError,
  });

  CriteriaCheckResult? generateResult;
  CriteriaCheckResult? checkResult;
  Object? generateError;
  Object? checkError;
  int generateCount = 0;
  int checkCount = 0;
  List<String>? lastCheckedMin;
  List<String>? lastCheckedSuperiority;

  @override
  Future<CriteriaCheckResult> generate({
    required String title,
    required String type,
    required int durationMinutes,
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
    required int durationMinutes,
    required List<String> minCriteria,
    List<String>? superiorityCriteria,
    String? battleId,
  }) async {
    checkCount++;
    lastCheckedMin = minCriteria;
    lastCheckedSuperiority = superiorityCriteria;
    final error = checkError;
    if (error != null) throw error;
    return checkResult!;
  }
}

class _FakeBattleRepository implements BattleRepository {
  String? createdCheckId;
  int? createdDuration;

  @override
  Future<String> createBattle({required String checkId, required int durationMinutes}) async {
    createdCheckId = checkId;
    createdDuration = durationMinutes;
    return 'new-battle';
  }

  @override
  Future<MyLimits> fetchMyLimits() async => const MyLimits(
        consented: true,
        criteriaCallsLeft: 9,
      );

  @override
  Future<int> updateBattleCriteria({required String battleId, required String checkId}) async => 2;

  @override
  Future<OpenRecruitPage> fetchOpenRecruits({int limit = openRecruitPageSize, RecruitCursor? cursor, String? query, String? type, String? durationBand}) async => const OpenRecruitPage.empty();

  @override
  Future<Battle?> fetchOpenRecruitBattle(String battleId) async => null;

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
  Future<String> submitJudgment({
    required String battleId,
    required bool passed,
    String? superiorId,
  }) async =>
      'judging';

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
  ThemeData? theme,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        battleCriteriaRepositoryProvider.overrideWithValue(criteria),
        battleRepositoryProvider.overrideWithValue(battles ?? _FakeBattleRepository()),
        if (limits != null) myLimitsProvider.overrideWith((ref) async => limits),
      ],
      child: MaterialApp(theme: theme, home: const CreateBattleScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

/// 뒤로가기를 검증하려면 **되돌아갈 화면이 있어야** 한다. 그래서 생성 화면을 push해서 띄운다.
const _hostLabel = '생성 화면 열기';

Future<void> _pushCreate(
  WidgetTester tester, {
  required _FakeCriteriaRepository criteria,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        battleCriteriaRepositoryProvider.overrideWithValue(criteria),
        battleRepositoryProvider.overrideWithValue(_FakeBattleRepository()),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CreateBattleScreen()),
              ),
              child: const Text(_hostLabel),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(findText(_hostLabel));
  await tester.pumpAndSettle();
}

/// 시스템 뒤로가기 제스처·앱바 뒤로가기와 같은 길(`maybePop`)로 나가 본다.
/// `Navigator.pop`은 `PopScope`를 거치지 않으므로 여기서 쓰면 아무것도 검증하지 못한다.
Future<void> _back(WidgetTester tester) async {
  await tester.state<NavigatorState>(find.byType(Navigator)).maybePop();
  await tester.pumpAndSettle();
}

Future<void> _enterTitleAndGenerate(WidgetTester tester, String title) async {
  await tester.enterText(find.byType(TextField).first, title);
  await tester.pumpAndSettle();
  // 입력 단계에 안내 줄이 늘어나면서(M3·M4) 기본 테스트 화면(800x600)에서는 이 버튼이 접힌 아래로 간다.
  // 실기기에서는 보이는 자리이므로 테스트가 스크롤해서 누른다.
  await tester.ensureVisible(findText(AppStrings.battleCriteriaGenerate));
  await tester.pumpAndSettle();
  await tester.tap(findText(AppStrings.battleCriteriaGenerate));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('품질전은 최소 기준과 우열 기준 두 목록을 보여 주고 그대로 올릴 수 있다', (tester) async {
    final criteria = _FakeCriteriaRepository(generateResult: _qualityResult);
    final battles = _FakeBattleRepository();
    await _pumpCreate(tester, criteria: criteria, battles: battles);

    await tester.tap(findText(AppStrings.battleTypeQuality));
    await tester.pumpAndSettle();
    await _enterTitleAndGenerate(tester, '책상 정리하기');

    expect(criteria.generateCount, 1);
    expect(findText(AppStrings.battleCriteriaMinTitle), findsOneWidget);
    expect(findText(AppStrings.battleCriteriaSuperiorityTitle), findsOneWidget);
    expect(findText('책상 상판이 보인다'), findsOneWidget);
    expect(findText('먼지나 얼룩이 없다'), findsOneWidget);

    await tester.tap(findText(AppStrings.battleCriteriaSubmit));
    await tester.pumpAndSettle();

    // 서버에는 기준 텍스트가 아니라 증서 id만 넘어간다.
    expect(battles.createdCheckId, 'check-1');
    expect(battles.createdDuration, 4320);
  });

  // 찾기 탭에는 더 이상 내 모집이 보이지 않는다. 올린 모집이 어느 화면에도 없는 구간을 만들지 않는다.
  testWidgets('모집을 올리면 내 모집이 보이는 내 대결 탭으로 보낸다', (tester) async {
    final criteria = _FakeCriteriaRepository(generateResult: _speedResult);
    final battles = _FakeBattleRepository();
    final container = ProviderContainer(
      overrides: [
        battleCriteriaRepositoryProvider.overrideWithValue(criteria),
        battleRepositoryProvider.overrideWithValue(battles),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: CreateBattleScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await _enterTitleAndGenerate(tester, '아침 운동하기');

    await tester.tap(findText(AppStrings.battleCriteriaSubmit));
    await tester.pumpAndSettle();

    expect(battles.createdCheckId, 'check-2');
    expect(container.read(selectedTabProvider), AppTab.myBattles);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('속도전에는 우열 기준 블록이 없다', (tester) async {
    final criteria = _FakeCriteriaRepository(generateResult: _speedResult);
    await _pumpCreate(tester, criteria: criteria);

    await _enterTitleAndGenerate(tester, '아침 운동하기');

    expect(findText(AppStrings.battleCriteriaMinTitle), findsOneWidget);
    expect(findText(AppStrings.battleCriteriaSuperiorityTitle), findsNothing);
  });

  testWidgets('증명할 수 없는 미션은 차단되고 제목 고치기만 할 수 있다', (tester) async {
    final criteria = _FakeCriteriaRepository(generateResult: _blockedResult);
    await _pumpCreate(tester, criteria: criteria);

    await _enterTitleAndGenerate(tester, '책 읽기');

    expect(findText(AppStrings.battleCriteriaBlocked), findsOneWidget);
    expect(findText('사진으로 확인할 수 없는 미션이에요'), findsOneWidget);
    // 차단이면 기준을 고쳐서 우회할 수 없다.
    expect(findText(AppStrings.battleCriteriaSubmit), findsNothing);
    expect(findText(AppStrings.battleCriteriaEdit), findsNothing);
    expect(findText(AppStrings.battleCriteriaFixTitle), findsOneWidget);

    await tester.tap(findText(AppStrings.battleCriteriaFixTitle));
    await tester.pumpAndSettle();
    expect(findText(AppStrings.battleCriteriaGenerate), findsOneWidget);
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
    await tester.tap(findText(AppStrings.battleCriteriaEdit));
    await tester.pumpAndSettle();

    // 마지막 TextField가 기준 입력칸이다(첫 칸은 제목).
    await tester.enterText(find.byType(TextField).last, '운동화를 신고 공원에 있다');
    await tester.pumpAndSettle();

    expect(findText(AppStrings.battleCriteriaRecheck), findsOneWidget);
    expect(findText(AppStrings.battleCriteriaSubmit), findsNothing);

    await tester.tap(findText(AppStrings.battleCriteriaRecheck));
    await tester.pumpAndSettle();

    expect(criteria.checkCount, 1);
    expect(criteria.lastCheckedMin, ['운동화를 신고 공원에 있다']);
    expect(criteria.lastCheckedSuperiority, isNull);
    expect(findText(AppStrings.battleCriteriaSubmit), findsOneWidget);

    await tester.tap(findText(AppStrings.battleCriteriaSubmit));
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
        criteriaCallsLeft: 0,
      ),
    );

    await tester.enterText(find.byType(TextField).first, '아침 운동하기');
    await tester.pumpAndSettle();

    expect(findText(AppStrings.battleErrorCriteriaCallLimit), findsOneWidget);
    final button = tester.widget<FilledButton>(
      findWidgetWithText(FilledButton, AppStrings.battleCriteriaGenerate),
    );
    expect(button.onPressed, isNull);
    expect(criteria.generateCount, 0);
  });

  testWidgets('AI 호출이 실패하면 횟수가 차감되지 않았다고 알리고 다시 시도할 수 있다', (tester) async {
    final criteria = _FakeCriteriaRepository(
      generateError: const CriteriaException('AI_FAILED', callsLeft: 9),
      generateResult: _speedResult,
    );
    await _pumpCreate(tester, criteria: criteria);

    await _enterTitleAndGenerate(tester, '아침 운동하기');

    expect(findText(AppStrings.battleErrorAiFailed), findsOneWidget);
    expect(findText(AppStrings.retry), findsOneWidget);

    // 다시 시도하면 같은 입력으로 한 번 더 부른다.
    criteria.generateError = null;
    await tester.tap(findText(AppStrings.retry));
    await tester.pumpAndSettle();

    expect(criteria.generateCount, 2);
    expect(findText('운동화를 신고 밖에 있다'), findsOneWidget);
  });

  // redesign 후속 결정 7: 카운터가 입력 글자만큼 진하고 굵었고, "직접 입력"이 위아래 글보다 들여 써져 있었다.
  testWidgets('글자 수 카운터는 보조 글자색·보통 굵기이고 "직접 입력" 글자는 입력칸 왼쪽 끝과 맞는다', (tester) async {
    await _pumpCreate(
      tester,
      criteria: _FakeCriteriaRepository(generateResult: _speedResult),
      theme: AppTheme.light,
    );

    final counter = tester.widget<Text>(findText('0/$battleTitleMaxLength')).style!;
    expect(counter.color, AppPalette.inkMuted);
    expect(counter.fontWeight, FontWeight.w400);

    final fieldLeft = tester.getRect(find.byType(TextField)).left;
    final customLeft = tester.getRect(findText(AppStrings.battleDurationCustom)).left;
    expect(customLeft, moreOrLessEquals(fieldLeft, epsilon: 0.5));
    // 옮긴 버튼도 그대로 눌린다.
    await tester.tap(findText(AppStrings.battleDurationCustom));
    await tester.pumpAndSettle();
    expect(findText(AppStrings.battleDurationQuick), findsOneWidget);
  });

  testWidgets('기간은 빠른 선택과 직접 입력으로 정하고 범위 밖이면 즉시 알린다', (tester) async {
    final criteria = _FakeCriteriaRepository(generateResult: _speedResult);
    final battles = _FakeBattleRepository();
    await _pumpCreate(tester, criteria: criteria, battles: battles);

    // 자주 쓰는 기간이 한 줄에 다 보이고, 짧은 기간의 위험과 제출 창/판정 창 구분을 함께 알린다.
    for (final minutes in battleDurationQuickPicks) {
      expect(findText(battleDurationLabel(minutes)), findsWidgets, reason: '$minutes분');
    }
    expect(findText(AppStrings.battleDurationShortWarning), findsOneWidget);
    expect(findText(AppStrings.battleDurationWindowNotice), findsOneWidget);

    // 직접 입력으로 넘어가 범위 밖 값을 넣으면 그 자리에서 문구가 나온다.
    await tester.tap(findText(AppStrings.battleDurationCustom));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '0');
    await tester.pumpAndSettle();
    expect(findText(AppStrings.battleDurationOutOfRange), findsOneWidget);

    // 1분은 통과하고, 서버에는 분으로 넘어간다.
    await tester.tap(findText(AppStrings.battleDurationUnitMinute));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '1');
    await tester.pumpAndSettle();
    expect(findText(AppStrings.battleDurationOutOfRange), findsNothing);

    await _enterTitleAndGenerate(tester, '아침 운동하기');
    await tester.tap(findText(AppStrings.battleCriteriaSubmit));
    await tester.pumpAndSettle();

    expect(battles.createdDuration, 1);
  });

  // ── mobile-ux M7(2026-11-02): 뒤로가기로 기준과 차감된 횟수를 조용히 잃지 않게 ──
  //
  // 이 두 건은 **반드시 지켜야 하는 양쪽 경계**다. 앞의 것이 깨지면 사용자가 화면에 갇히고,
  // 뒤의 것이 깨지면 쓴 횟수가 조용히 사라진다.

  testWidgets('입력 단계에서는 뒤로가기가 확인창 없이 그냥 나간다', (tester) async {
    await _pushCreate(tester, criteria: _FakeCriteriaRepository());

    await tester.enterText(find.byType(TextField).first, '아침 운동하기');
    await tester.pumpAndSettle();

    await _back(tester);

    // 확인창을 띄우지 않고 host 화면으로 돌아왔다.
    expect(findText(AppStrings.battleCriteriaLeaveTitle), findsNothing);
    expect(findText(_hostLabel), findsOneWidget);
    expect(findText(AppStrings.battleCreate), findsNothing);
  });

  // `제목 고치기`는 단계만 입력으로 되돌리고 결과(_result)는 들고 있다.
  // "결과를 들고 있으면 막는다"만 보면 이 자리에서 사용자가 갇힌다.
  testWidgets('차단 뒤 제목 고치기로 돌아온 입력 단계에서도 그냥 나간다', (tester) async {
    await _pushCreate(
      tester,
      criteria: _FakeCriteriaRepository(generateResult: _blockedResult),
    );

    await _enterTitleAndGenerate(tester, '책 읽기');
    await tester.tap(findText(AppStrings.battleCriteriaFixTitle));
    await tester.pumpAndSettle();
    expect(findText(AppStrings.battleCriteriaGenerate), findsOneWidget);

    await _back(tester);

    expect(findText(AppStrings.battleCriteriaLeaveTitle), findsNothing);
    expect(findText(_hostLabel), findsOneWidget);
  });

  testWidgets('만든 기준을 들고 있으면 뒤로가기에 확인창이 뜨고 계속하기로 남는다', (tester) async {
    await _pushCreate(
      tester,
      criteria: _FakeCriteriaRepository(generateResult: _speedResult),
    );

    await _enterTitleAndGenerate(tester, '아침 운동하기');
    expect(findText('운동화를 신고 밖에 있다'), findsOneWidget);

    await _back(tester);

    // 아직 나가지 않았고, 무엇을 잃는지 확인창이 말한다.
    expect(findText(AppStrings.battleCriteriaLeaveTitle), findsOneWidget);
    expect(findText(AppStrings.battleCriteriaLeaveBody), findsOneWidget);
    expect(findText(_hostLabel), findsNothing);

    await tester.tap(findText(AppStrings.stay));
    await tester.pumpAndSettle();

    // 기준이 그대로 남아 있다.
    expect(findText('운동화를 신고 밖에 있다'), findsOneWidget);
    expect(findText(_hostLabel), findsNothing);

    // 나가기를 고르면 그때는 정말 나간다(막는 것이 아니라 한 번 묻는 것이다).
    await _back(tester);
    await tester.tap(findText(AppStrings.leave));
    await tester.pumpAndSettle();

    expect(findText(_hostLabel), findsOneWidget);
  });

  // ── reviewer W3(2026-11-02): 오류 화면에서는 막지 않는다 ──
  //
  // 재검사가 실패하면 `_result`는 남지만 화면은 `(횟수는 차감되지 않았어요)`를 보여 준다.
  // 거기서 `사용한 횟수는 돌아오지 않아요`라고 묻는 것은 화면과 정반대이고, 지키려고 막은
  // `_result`로 되돌아갈 길도 없다(오류 화면의 `다시 시도`는 `_generate`다).
  testWidgets('재검사가 실패한 오류 화면에서는 확인창 없이 그냥 나간다', (tester) async {
    await _pushCreate(
      tester,
      criteria: _FakeCriteriaRepository(
        generateResult: _speedResult,
        checkError: const CriteriaException('AI_FAILED', callsLeft: 9),
      ),
    );

    await _enterTitleAndGenerate(tester, '아침 운동하기');
    await tester.tap(findText(AppStrings.battleCriteriaEdit));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '운동화를 신고 공원에 있다');
    await tester.pumpAndSettle();
    await tester.tap(findText(AppStrings.battleCriteriaRecheck));
    await tester.pumpAndSettle();

    // 화면이 말하는 것: 횟수는 차감되지 않았다.
    expect(findText(AppStrings.battleErrorAiFailed), findsOneWidget);

    await _back(tester);

    // 그러니 묻지 않고 그냥 나간다.
    expect(findText(AppStrings.battleCriteriaLeaveTitle), findsNothing);
    expect(findText(AppStrings.battleCriteriaLeaveBody), findsNothing);
    expect(findText(_hostLabel), findsOneWidget);
  });

  // M4 — 유형을 고르는 자리에 설명이 없었다. 그 문장은 이미 있었고(`battleTypeTagline`)
  // 모집 상세 시트에서만 쓰였다. 즉 참가자는 읽는데 만드는 사람만 못 읽는 상태였다.
  testWidgets('유형 세그먼트 아래에 유형 설명 한 줄이 있고, 유형을 바꾸면 그 줄도 바뀐다', (tester) async {
    await _pumpCreate(
      tester,
      criteria: _FakeCriteriaRepository(generateResult: _speedResult),
    );

    // 기본값은 속도전이다.
    expect(findText(battleTypeTagline('speed')), findsOneWidget);
    expect(findText(battleTypeTagline('quality')), findsNothing);

    await tester.tap(findText(AppStrings.battleTypeQuality));
    await tester.pumpAndSettle();

    // 유형을 바꾸면 설명도 같이 바뀐다. 두 문장이 동시에 보이지 않는다.
    expect(findText(battleTypeTagline('quality')), findsOneWidget);
    expect(findText(battleTypeTagline('speed')), findsNothing);
  });

  // M4② — 테마가 주는 체크 아이콘이 라벨 폭을 먹어 글자가 잘린다. 이 세그먼트 하나만 끄지 않고 있었다.
  // 잘림 자체는 `SegmentedButton`이 자식을 clamp해 테스트로 측정할 수 없으므로(에이전트 메모)
  // 설정값을 직접 단정한다.
  testWidgets('유형 세그먼트는 선택 체크 아이콘을 쓰지 않는다', (tester) async {
    await _pumpCreate(
      tester,
      criteria: _FakeCriteriaRepository(generateResult: _speedResult),
    );

    final segments = tester.widget<SegmentedButton<String>>(
      find.byType(SegmentedButton<String>),
    );
    expect(segments.showSelectedIcon, isFalse);
  });

  // M3 — 사진으로 증명할 수 없는 제목은 서버가 차단하는데, 그때는 AI 호출 1회가 이미 차감된 뒤다.
  // 그 함정을 제목을 쓰는 동안 말해 준다. 차단은 그대로 서버가 한다(이 줄은 안내일 뿐이다).
  testWidgets('제목 입력 아래에 사진으로 증명할 수 있어야 한다는 안내와 예시가 보인다', (tester) async {
    await _pumpCreate(
      tester,
      criteria: _FakeCriteriaRepository(generateResult: _speedResult),
    );

    expect(findText(AppStrings.battleTitleProvableHint), findsOneWidget);
    // 힌트를 대체한 것이 아니라 더한 것이다.
    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.decoration?.hintText, AppStrings.battleTitleHint);
    // 입력창 "아래"여야 한다 — 위에 두면 예시가 무엇에 대한 예시인지 흐려진다.
    expect(
      tester.getTopLeft(findText(AppStrings.battleTitleProvableHint)).dy,
      greaterThan(tester.getTopLeft(find.byType(TextField).first).dy),
    );
  });
}
