import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthState, User;

import 'package:todododo/core/strings.dart';
import 'package:todododo/features/auth/data/auth_repository.dart';
import 'package:todododo/features/auth/domain/auth_providers.dart';
import 'package:todododo/features/battle/data/ai_consent.dart';
import 'package:todododo/features/battle/data/battle.dart';
import 'package:todododo/features/battle/data/battle_participant.dart';
import 'package:todododo/features/battle/data/battle_submission.dart';
import 'package:todododo/features/battle/data/submission_result.dart';
import 'package:todododo/features/battle/data/battle_repository.dart';
import 'package:todododo/features/battle/data/criteria_check_result.dart';
import 'package:todododo/features/battle/data/open_recruit.dart';
import 'package:todododo/features/battle/data/player_card.dart';
import 'package:todododo/features/battle/data/profile.dart';
import 'package:todododo/features/battle/data/vs_intro_seen_store.dart';
import 'package:todododo/features/battle/domain/ai_consent_providers.dart';
import 'package:todododo/features/battle/domain/battle_providers.dart';
import 'package:todododo/features/battle/presentation/battle_recruits_screen.dart';
import 'package:todododo/features/battle/presentation/vs_intro.dart';
import 'package:todododo/features/profile/domain/profile_providers.dart';

/// 참가만 성공하거나 실패하게 두고 나머지는 비워 둔 저장소.
class _JoinOnlyBattleRepository implements BattleRepository {
  _JoinOnlyBattleRepository({this.joinError});

  final Object? joinError;
  int joinCount = 0;

  @override
  Future<void> joinBattle(String battleId, int criteriaVersion) async {
    joinCount++;
    final error = joinError;
    if (error != null) throw error;
  }

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
  Future<PlayerCard> fetchPlayerCard(String userId) async =>
      const PlayerCard(userId: 'creator1', displayName: '도윤');

  @override
  Future<List<Battle>> fetchMyRecruits() async => const [];

  @override
  Future<Map<String, String>> fetchDisplayNames(Iterable<String> ids) async => {};

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

/// 로그인한 사용자 `me`를 돌려주는 인증 저장소.
class _SignedInAuthRepository implements AuthRepository {
  @override
  Stream<AuthState> get authStateChanges => const Stream.empty();

  @override
  User? get currentUser => const User(
        id: 'me',
        appMetadata: {},
        userMetadata: {},
        aud: 'authenticated',
        createdAt: '2026-09-15T00:00:00Z',
      );

  @override
  Future<void> signInWithGoogle() async {}

  @override
  Future<void> signOut() async {}

  @override
  Future<void> deleteAccount() async {}
}

class _MemorySeenStore extends VsIntroSeenStore {
  _MemorySeenStore();

  final seen = <String>{};

  @override
  Future<bool> hasSeen(String userId, String battleId) async =>
      seen.contains(VsIntroSeenStore.keyFor(userId, battleId));

  @override
  Future<void> markSeen(String userId, String battleId) async {
    seen.add(VsIntroSeenStore.keyFor(userId, battleId));
  }
}

Future<void> _pumpRecruits(
  WidgetTester tester, {
  required BattleRepository repository,
  required VsIntroSeenStore store,
}) async {
  final battle = Battle(
    id: 'b1',
    type: 'speed',
    status: 'pending',
    title: '아침 운동하기',
    creatorId: 'creator1',
    createdAt: DateTime(2026, 9, 15),
    minCriteria: const ['운동화를 신고 밖에 있다'],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        battleRepositoryProvider.overrideWithValue(repository),
        // 동의 절차는 ai_consent_test.dart에서 따로 본다. 여기서는 이미 동의한 사용자로 둔다.
        myAiConsentProvider.overrideWith(
          (ref) async => AiConsent(version: '2026-09-14', consentedAt: DateTime(2026, 9, 16)),
        ),
        authRepositoryProvider.overrideWithValue(_SignedInAuthRepository()),
        vsIntroSeenStoreProvider.overrideWithValue(store),
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

/// 카드를 눌러 모집 상세 시트를 열고 "이 기준으로 참가"를 누른다.
Future<void> _joinFromSheet(WidgetTester tester) async {
  await tester.tap(find.text('아침 운동하기'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(AppStrings.battleRecruitJoinWithCriteria));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  // spec 수용 기준: "대결에 참가해 매칭에 성공한 사람에게 VS 인트로가 뜬다",
  // "인트로 때문에 참가 성공 안내가 가려져 사용자가 결과를 모르는 일이 없다".
  testWidgets('참가에 성공하면 VS 인트로가 먼저 뜨고, 닫힌 뒤에 성공 토스트가 뜬다', (tester) async {
    final repository = _JoinOnlyBattleRepository();
    final store = _MemorySeenStore();
    await _pumpRecruits(tester, repository: repository, store: store);

    await _joinFromSheet(tester);

    expect(repository.joinCount, 1);
    expect(find.byType(VsIntro), findsOneWidget);
    expect(find.text('민지'), findsOneWidget);
    expect(find.text('도윤'), findsWidgets);
    // 인트로가 떠 있는 동안에는 성공 토스트가 나오지 않는다.
    expect(find.text(AppStrings.battleJoined), findsNothing);
    // 표시를 시작하는 순간 "봤음"을 기록한다.
    expect(store.seen, contains(VsIntroSeenStore.keyFor('me', 'b1')));

    await tester.tap(find.byType(VsIntro));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(VsIntro), findsNothing);
    expect(find.text(AppStrings.battleJoined), findsOneWidget);

    // 토스트 표시 타이머까지 흘려보내 테스트가 대기 중인 타이머 없이 끝나게 한다.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('참가에 실패하면 VS 인트로 없이 오류 토스트만 뜬다', (tester) async {
    final repository = _JoinOnlyBattleRepository(joinError: Exception('join failed'));
    final store = _MemorySeenStore();
    await _pumpRecruits(tester, repository: repository, store: store);

    await _joinFromSheet(tester);

    expect(repository.joinCount, 1);
    expect(find.byType(VsIntro), findsNothing);
    expect(find.text(AppStrings.battleErrorUnknown), findsOneWidget);
    expect(find.text(AppStrings.battleJoined), findsNothing);
    expect(store.seen, isEmpty);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('이미 본 대결이면 참가 직후 인트로 없이 성공 토스트가 바로 뜬다', (tester) async {
    final repository = _JoinOnlyBattleRepository();
    final store = _MemorySeenStore()..seen.add(VsIntroSeenStore.keyFor('me', 'b1'));
    await _pumpRecruits(tester, repository: repository, store: store);

    await _joinFromSheet(tester);

    expect(find.byType(VsIntro), findsNothing);
    expect(find.text(AppStrings.battleJoined), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });
}
