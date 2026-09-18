import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthState, User;

import 'package:todododo/core/strings.dart';
import 'package:todododo/features/auth/data/auth_repository.dart';
import 'package:todododo/features/auth/domain/auth_providers.dart';
import 'package:todododo/features/battle/data/ai_consent.dart';
import 'package:todododo/features/battle/data/ai_consent_repository.dart';
import 'package:todododo/features/battle/data/battle_submission.dart';
import 'package:todododo/features/battle/data/submission_result.dart';
import 'package:todododo/features/battle/data/battle.dart';
import 'package:todododo/features/battle/data/battle_participant.dart';
import 'package:todododo/features/battle/data/battle_repository.dart';
import 'package:todododo/features/battle/data/criteria_check_result.dart';
import 'package:todododo/features/battle/data/open_recruit.dart';
import 'package:todododo/features/battle/data/player_card.dart';
import 'package:todododo/features/battle/data/profile.dart';
import 'package:todododo/features/battle/data/vs_intro_seen_store.dart';
import 'package:todododo/features/battle/domain/ai_consent_providers.dart';
import 'package:todododo/features/battle/domain/battle_providers.dart';
import 'package:todododo/features/battle/presentation/ai_consent_screen.dart';
import 'package:todododo/features/battle/presentation/battle_recruits_screen.dart';
import 'package:todododo/features/profile/domain/battle_record.dart';
import 'package:todododo/features/profile/data/player_stats.dart';
import 'package:todododo/features/profile/domain/profile_providers.dart';
import 'package:todododo/features/profile/presentation/profile_screen.dart';

class _FakeAiConsentRepository implements AiConsentRepository {
  _FakeAiConsentRepository({
    this.consent,
    this.impact = const ConsentWithdrawalImpact(activeCount: 0, pendingCount: 0),
    this.impactCompleter,
  });

  AiConsent? consent;
  final ConsentWithdrawalImpact impact;
  final Completer<ConsentWithdrawalImpact>? impactCompleter;
  int giveCount = 0;
  int withdrawCount = 0;

  @override
  Future<AiConsent?> fetchMyConsent() async => consent;

  @override
  Future<void> giveConsent() async {
    giveCount++;
    consent = AiConsent(version: '2026-09-14', consentedAt: DateTime(2026, 9, 16));
  }

  @override
  Future<ConsentWithdrawalImpact> fetchWithdrawalImpact() {
    return impactCompleter?.future ?? Future.value(impact);
  }

  @override
  Future<void> withdrawConsent() async {
    withdrawCount++;
    consent = null;
  }
}

class _JoinOnlyBattleRepository implements BattleRepository {
  int joinCount = 0;

  @override
  Future<void> joinBattle(String battleId, int criteriaVersion) async {
    joinCount++;
  }

  @override
  Future<PlayerCard> fetchPlayerCard(String userId) async =>
      const PlayerCard(userId: 'creator1', displayName: '도윤');

  @override
  Future<String> createBattle({required String checkId, required int durationMinutes}) async =>
      'new-battle';

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

class _SignedInAuthRepository implements AuthRepository {
  @override
  Stream<AuthState> get authStateChanges => const Stream.empty();

  @override
  User? get currentUser => const User(
        id: 'me',
        appMetadata: {},
        userMetadata: {},
        aud: 'authenticated',
        createdAt: '2026-09-16T00:00:00Z',
      );

  @override
  Future<void> signInWithGoogle() async {}

  @override
  Future<void> signOut() async {}

  @override
  Future<void> deleteAccount() async {}
}

/// VS 인트로가 참가 흐름 검증에 끼어들지 않게 이미 봤다고 답한다.
class _SeenAllStore extends VsIntroSeenStore {
  const _SeenAllStore();

  @override
  Future<bool> hasSeen(String userId, String battleId) async => true;

  @override
  Future<void> markSeen(String userId, String battleId) async {}
}

Future<void> _pumpRecruits(
  WidgetTester tester, {
  required _FakeAiConsentRepository consentRepository,
  required _JoinOnlyBattleRepository battleRepository,
}) async {
  final battle = Battle(
    id: 'b1',
    type: 'speed',
    status: 'pending',
    title: '아침 운동하기',
    creatorId: 'creator1',
    createdAt: DateTime(2026, 9, 16),
    minCriteria: const ['운동화를 신고 밖에 있다'],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        aiConsentRepositoryProvider.overrideWithValue(consentRepository),
        battleRepositoryProvider.overrideWithValue(battleRepository),
        authRepositoryProvider.overrideWithValue(_SignedInAuthRepository()),
        vsIntroSeenStoreProvider.overrideWithValue(const _SeenAllStore()),
        myProfileProvider.overrideWith((ref) async => const Profile(id: 'me', displayName: '민지')),
        openRecruitsProvider.overrideWith(
          (ref) async => [
            OpenRecruit(
              battle: battle,
              creator: const PlayerCard(userId: 'creator1', displayName: '도윤'),
            ),
          ],
        ),
        myRecruitsProvider.overrideWith((ref) async => const []),
        myBattlesProvider.overrideWith((ref) async => const []),
      ],
      child: const MaterialApp(home: BattleRecruitsScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpProfile(
  WidgetTester tester, {
  required _FakeAiConsentRepository consentRepository,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        aiConsentRepositoryProvider.overrideWithValue(consentRepository),
        myProfileProvider.overrideWith((ref) async => const Profile(id: 'me', displayName: '나')),
        myPlayerStatsProvider.overrideWith((ref) async => PlayerStats.empty),
        battleRecordsProvider.overrideWith((ref) async => <BattleRecord>[]),
      ],
      child: const MaterialApp(home: ProfileScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  // spec 수용 기준: 동의 내용에 받는 자·항목·목적·보유 기간·거부 권리와 불이익이 모두 들어 있다.
  testWidgets('동의 화면에 받는 자·항목·목적·보유 기간·거부 권리가 모두 보인다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          aiConsentRepositoryProvider.overrideWithValue(_FakeAiConsentRepository()),
        ],
        child: const MaterialApp(home: AiConsentScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.aiConsentRecipient), findsOneWidget);
    expect(find.text(AppStrings.aiConsentItems), findsOneWidget);
    expect(find.text(AppStrings.aiConsentPurpose), findsOneWidget);
    expect(find.text(AppStrings.aiConsentRetention), findsOneWidget);
    expect(find.text(AppStrings.aiConsentRefusal), findsOneWidget);
    expect(find.text(AppStrings.aiConsentAgree), findsOneWidget);
    expect(find.text(AppStrings.aiConsentDisagree), findsOneWidget);
    // 촬영 시각은 제공 항목이 아니다(decisions 69).
    expect(find.textContaining('촬영 시각'), findsNothing);
    // 정책 문서 주소가 아직 없으므로 링크를 보여 주지 않는다.
    expect(find.text(AppStrings.aiConsentPrivacyPolicy), findsNothing);
  });

  testWidgets('동의하지 않은 사용자가 참가를 누르면 동의 화면이 먼저 뜨고, 거부하면 참가하지 않는다', (tester) async {
    final consentRepository = _FakeAiConsentRepository();
    final battleRepository = _JoinOnlyBattleRepository();
    await _pumpRecruits(
      tester,
      consentRepository: consentRepository,
      battleRepository: battleRepository,
    );

    // 참가는 카드를 눌러 연 모집 상세 시트에서 한다.
    await tester.tap(find.text('아침 운동하기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.battleRecruitJoinWithCriteria));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.aiConsentTitle), findsOneWidget);
    expect(battleRepository.joinCount, 0);

    await tester.tap(find.text(AppStrings.aiConsentDisagree));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.aiConsentRequired), findsOneWidget);
    expect(battleRepository.joinCount, 0);
    expect(consentRepository.giveCount, 0);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('동의하면 동의가 저장되고 참가가 이어진다', (tester) async {
    final consentRepository = _FakeAiConsentRepository();
    final battleRepository = _JoinOnlyBattleRepository();
    await _pumpRecruits(
      tester,
      consentRepository: consentRepository,
      battleRepository: battleRepository,
    );

    // 참가는 카드를 눌러 연 모집 상세 시트에서 한다.
    await tester.tap(find.text('아침 운동하기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.battleRecruitJoinWithCriteria));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.aiConsentAgree));
    await tester.pumpAndSettle();

    expect(consentRepository.giveCount, 1);
    expect(battleRepository.joinCount, 1);
    expect(find.text(AppStrings.battleJoined), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('이미 동의한 사용자는 참가할 때 동의 화면을 다시 보지 않는다', (tester) async {
    final consentRepository = _FakeAiConsentRepository(
      consent: AiConsent(version: '2026-09-14', consentedAt: DateTime(2026, 9, 16)),
    );
    final battleRepository = _JoinOnlyBattleRepository();
    await _pumpRecruits(
      tester,
      consentRepository: consentRepository,
      battleRepository: battleRepository,
    );

    // 참가는 카드를 눌러 연 모집 상세 시트에서 한다.
    await tester.tap(find.text('아침 운동하기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.battleRecruitJoinWithCriteria));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.aiConsentTitle), findsNothing);
    expect(battleRepository.joinCount, 1);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('대결 만들기도 동의를 먼저 묻는다', (tester) async {
    final consentRepository = _FakeAiConsentRepository();
    await _pumpRecruits(
      tester,
      consentRepository: consentRepository,
      battleRepository: _JoinOnlyBattleRepository(),
    );

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.aiConsentTitle), findsOneWidget);
    expect(find.text(AppStrings.battleCreate), findsNothing);
  });

  testWidgets('프로필에서 동의 상태를 보고 철회하면 영향 안내를 거쳐 철회된다', (tester) async {
    final consentRepository = _FakeAiConsentRepository(
      consent: AiConsent(version: '2026-09-14', consentedAt: DateTime(2026, 9, 16)),
      impact: const ConsentWithdrawalImpact(activeCount: 2, pendingCount: 1),
    );
    await _pumpProfile(tester, consentRepository: consentRepository);

    expect(find.text(AppStrings.aiConsentStatusGiven('2026년 9월 16일')), findsOneWidget);

    await tester.tap(find.text(AppStrings.aiConsentWithdraw));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.aiConsentWithdrawConfirmTitle), findsOneWidget);
    expect(find.textContaining('진행 중인 대결 2개'), findsOneWidget);
    expect(find.textContaining('모집 중인 대결 1개'), findsOneWidget);

    await tester.tap(find.text(AppStrings.aiConsentWithdrawConfirm));
    await tester.pumpAndSettle();

    expect(consentRepository.withdrawCount, 1);
    expect(find.text(AppStrings.aiConsentWithdrawDone), findsOneWidget);
    // 철회하면 다시 동의하기 전까지 대결을 만들거나 참가할 수 없다.
    expect(find.text(AppStrings.aiConsentStatusNotGiven), findsOneWidget);
    expect(find.text(AppStrings.aiConsentGive), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('철회 영향을 조회하는 동안에는 확인 버튼을 누를 수 없다', (tester) async {
    final completer = Completer<ConsentWithdrawalImpact>();
    final consentRepository = _FakeAiConsentRepository(
      consent: AiConsent(version: '2026-09-14', consentedAt: DateTime(2026, 9, 16)),
      impactCompleter: completer,
    );
    await _pumpProfile(tester, consentRepository: consentRepository);

    // 조회가 끝나지 않아 대화상자 안 로더가 계속 돈다. pumpAndSettle은 끝나지 않는다.
    await tester.tap(find.text(AppStrings.aiConsentWithdraw));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final disabled = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, AppStrings.aiConsentWithdrawConfirm),
    );
    expect(disabled.onPressed, isNull);

    completer.complete(const ConsentWithdrawalImpact(activeCount: 0, pendingCount: 0));
    await tester.pumpAndSettle();

    // 처리될 대결이 없으면 뒷문장만 보여 준다.
    expect(find.text(AppStrings.aiConsentWithdrawAfter), findsOneWidget);
    final enabled = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, AppStrings.aiConsentWithdrawConfirm),
    );
    expect(enabled.onPressed, isNotNull);

    await tester.tap(find.text(AppStrings.cancel));
    await tester.pumpAndSettle();
    expect(consentRepository.withdrawCount, 0);
  });
}
