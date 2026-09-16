import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthState, PostgrestException, User;

import 'package:todododo/core/navigation/app_tab.dart';
import 'package:todododo/core/strings.dart';
import 'package:todododo/features/auth/data/auth_repository.dart';
import 'package:todododo/features/auth/domain/auth_providers.dart';
import 'package:todododo/features/battle/data/ai_consent.dart';
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
import 'package:todododo/features/battle/presentation/battle_recruits_screen.dart';
import 'package:todododo/features/profile/domain/profile_providers.dart';

class _FakeBattleRepository implements BattleRepository {
  _FakeBattleRepository({this.joinError});

  Object? joinError;
  int joinCount = 0;
  int? lastVersion;

  @override
  Future<void> joinBattle(String battleId, int criteriaVersion) async {
    joinCount++;
    lastVersion = criteriaVersion;
    final error = joinError;
    if (error != null) throw error;
  }

  @override
  Future<PlayerCard> fetchPlayerCard(String userId) async =>
      const PlayerCard(userId: 'creator1', displayName: '도윤');

  @override
  Future<List<OpenRecruit>> fetchOpenRecruits() async => const [];

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
  Future<String> createEvidencePhotoUrl(String path) async => 'https://example.com/$path';
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

class _SeenAllStore extends VsIntroSeenStore {
  const _SeenAllStore();

  @override
  Future<bool> hasSeen(String userId, String battleId) async => true;

  @override
  Future<void> markSeen(String userId, String battleId) async {}
}

Battle _qualityBattle({int criteriaVersion = 1, List<String>? minCriteria}) {
  return Battle(
    id: 'b1',
    type: 'quality',
    status: 'pending',
    title: '책상 정리하기',
    creatorId: 'creator1',
    createdAt: DateTime(2026, 9, 16),
    durationHours: 72,
    minCriteria: minCriteria ?? const ['상판이 보인다'],
    superiorityCriteria: const ['먼지가 없다'],
    criteriaVersion: criteriaVersion,
  );
}

OpenRecruit _recruitOf(Battle battle) => OpenRecruit(
      battle: battle,
      creator: const PlayerCard(
        userId: 'creator1',
        displayName: '도윤',
        score: 9,
        wins: 3,
        losses: 0,
        draws: 0,
      ),
    );

/// 목록이 다시 읽힐 때마다 다음 값을 돌려준다(기준이 바뀐 상황을 만들기 위해).
class _RecruitFeed {
  _RecruitFeed(this._pages);

  final List<List<OpenRecruit>> _pages;
  int calls = 0;

  List<OpenRecruit> next() {
    final page = _pages[calls < _pages.length ? calls : _pages.length - 1];
    calls++;
    return page;
  }
}

Future<ProviderContainer> _pumpSheet(
  WidgetTester tester, {
  required _FakeBattleRepository repository,
  _RecruitFeed? feed,
  Battle? battle,
}) async {
  final target = battle ?? _qualityBattle();
  final container = ProviderContainer(
    overrides: [
      battleRepositoryProvider.overrideWithValue(repository),
      authRepositoryProvider.overrideWithValue(_SignedInAuthRepository()),
      vsIntroSeenStoreProvider.overrideWithValue(const _SeenAllStore()),
      myAiConsentProvider.overrideWith(
        (ref) async => AiConsent(version: '2026-09-14', consentedAt: DateTime(2026, 9, 16)),
      ),
      myProfileProvider.overrideWith((ref) async => const Profile(id: 'me', displayName: '민지')),
      openRecruitsProvider.overrideWith(
        (ref) async => feed == null ? [_recruitOf(target)] : feed.next(),
      ),
      myRecruitsProvider.overrideWith((ref) async => const []),
      myBattlesProvider.overrideWith((ref) async => const []),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: BattleRecruitsScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<void> _openSheet(WidgetTester tester) async {
  await tester.tap(find.text('책상 정리하기'));
  await tester.pumpAndSettle();
}

Future<void> _tapJoin(WidgetTester tester) async {
  await tester.tap(find.text(AppStrings.battleRecruitJoinWithCriteria));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('모집 상세 시트에 두 기준 목록·유형 설명·기간·생성자 전적이 보인다', (tester) async {
    await _pumpSheet(tester, repository: _FakeBattleRepository());
    await _openSheet(tester);

    expect(find.text(AppStrings.battleCriteriaMinTitle), findsOneWidget);
    // 첫 기준과 생성자 카드는 뒤에 남아 있는 목록 카드에도 있어 두 번 잡힌다.
    expect(find.text('상판이 보인다'), findsWidgets);
    // 품질전은 우열 기준도 참가 전에 공개된다(결정 67). 카드에는 없고 시트에만 있다.
    expect(find.text(AppStrings.battleCriteriaSuperiorityTitle), findsOneWidget);
    expect(find.text('먼지가 없다'), findsOneWidget);
    expect(find.text(AppStrings.battleTypeQualityTagline), findsOneWidget);
    expect(find.text(AppStrings.battleDuration3Days), findsWidgets);
    expect(find.text(AppStrings.playerScoreLabel(9)), findsWidgets);
    expect(find.text(AppStrings.playerRecordLabel(3, 0, 0)), findsWidgets);
    expect(find.text(AppStrings.battleRecruitJoinWithCriteria), findsOneWidget);
  });

  testWidgets('속도전 시트에는 우열 기준 블록이 없다', (tester) async {
    final speed = Battle(
      id: 'b1',
      type: 'speed',
      status: 'pending',
      title: '책상 정리하기',
      creatorId: 'creator1',
      createdAt: DateTime(2026, 9, 16),
      durationHours: 24,
      minCriteria: const ['상판이 보인다'],
    );
    await _pumpSheet(tester, repository: _FakeBattleRepository(), battle: speed);
    await _openSheet(tester);

    expect(find.text(AppStrings.battleCriteriaSuperiorityTitle), findsNothing);
    expect(find.text(AppStrings.battleTypeSpeedTagline), findsOneWidget);
  });

  testWidgets('참가에 성공하면 시트가 닫히고 토스트 뒤 내 대결 탭으로 간다', (tester) async {
    final repository = _FakeBattleRepository();
    final container = await _pumpSheet(tester, repository: repository);
    await _openSheet(tester);
    await _tapJoin(tester);

    // 내가 확인한 기준 버전이 그대로 서버로 간다.
    expect(repository.joinCount, 1);
    expect(repository.lastVersion, 1);
    expect(find.text(AppStrings.battleRecruitJoinWithCriteria), findsNothing);
    expect(find.text(AppStrings.battleJoined), findsOneWidget);
    expect(container.read(selectedTabProvider), AppTab.myBattles);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('그 사이 기준이 바뀌었으면 참가가 성립하지 않고 바뀐 기준을 다시 보여 준다', (tester) async {
    final repository = _FakeBattleRepository(
      joinError: PostgrestException(message: '기준이 바뀌었습니다.', hint: 'CRITERIA_CHANGED'),
    );
    final feed = _RecruitFeed([
      [_recruitOf(_qualityBattle())],
      [
        _recruitOf(_qualityBattle(criteriaVersion: 2, minCriteria: const ['상판이 완전히 비어 있다'])),
      ],
    ]);
    await _pumpSheet(tester, repository: repository, feed: feed);
    await _openSheet(tester);
    await _tapJoin(tester);

    expect(find.text(AppStrings.battleCriteriaChanged), findsOneWidget);
    // 목록을 다시 읽었으므로 카드 미리보기와 시트 기준 목록 양쪽이 새 기준으로 바뀐다.
    expect(find.text('상판이 완전히 비어 있다'), findsWidgets);
    // 시트는 열린 채로 남아 바뀐 기준을 확인한 뒤 다시 참가할 수 있다.
    expect(find.text(AppStrings.battleRecruitJoinWithCriteria), findsOneWidget);
    expect(find.text(AppStrings.battleJoined), findsNothing);

    // 새 버전으로 다시 참가한다.
    repository.joinError = null;
    await _tapJoin(tester);
    expect(repository.lastVersion, 2);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('오늘 한도를 이미 썼으면 유료 예고가 담긴 안내가 뜨고 시트는 남는다', (tester) async {
    final repository = _FakeBattleRepository(
      joinError: PostgrestException(message: '오늘 한도', hint: 'MY_DAILY_LIMIT'),
    );
    await _pumpSheet(tester, repository: repository, feed: null);
    await _openSheet(tester);
    await _tapJoin(tester);

    expect(find.text(AppStrings.battleErrorDailyLimit), findsOneWidget);
    expect(AppStrings.battleErrorDailyLimit, contains('유료'));
    expect(find.text(AppStrings.battleRecruitJoinWithCriteria), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('생성자가 오늘 한도를 다 썼으면 그 이유를 알려 준다', (tester) async {
    final repository = _FakeBattleRepository(
      joinError: PostgrestException(message: '생성자 한도', hint: 'CREATOR_DAILY_LIMIT'),
    );
    await _pumpSheet(tester, repository: repository);
    await _openSheet(tester);
    await _tapJoin(tester);

    expect(find.text(AppStrings.battleErrorCreatorDailyLimit), findsOneWidget);
    expect(AppStrings.battleErrorCreatorDailyLimit, contains('유료'));

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('이미 다른 사람이 참가했으면 시트를 닫고 알린다', (tester) async {
    final repository = _FakeBattleRepository(
      joinError: PostgrestException(message: '이미 매칭', hint: 'ALREADY_MATCHED'),
    );
    await _pumpSheet(tester, repository: repository);
    await _openSheet(tester);
    await _tapJoin(tester);

    expect(find.text(AppStrings.battleErrorAlreadyMatched), findsOneWidget);
    expect(find.text(AppStrings.battleRecruitJoinWithCriteria), findsNothing);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });
}
