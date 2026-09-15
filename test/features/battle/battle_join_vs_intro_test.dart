import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthState, User;

import 'package:todododo/core/strings.dart';
import 'package:todododo/features/auth/data/auth_repository.dart';
import 'package:todododo/features/auth/domain/auth_providers.dart';
import 'package:todododo/features/battle/data/battle.dart';
import 'package:todododo/features/battle/data/battle_participant.dart';
import 'package:todododo/features/battle/data/battle_repository.dart';
import 'package:todododo/features/battle/data/profile.dart';
import 'package:todododo/features/battle/data/vs_intro_seen_store.dart';
import 'package:todododo/features/battle/domain/battle_providers.dart';
import 'package:todododo/features/battle/domain/battle_recruit.dart';
import 'package:todododo/features/battle/presentation/battle_recruits_screen.dart';
import 'package:todododo/features/battle/presentation/vs_intro.dart';
import 'package:todododo/features/profile/domain/profile_providers.dart';

/// 참가만 성공하거나 실패하게 두고 나머지는 비워 둔 저장소.
class _JoinOnlyBattleRepository implements BattleRepository {
  _JoinOnlyBattleRepository({this.joinError});

  final Object? joinError;
  int joinCount = 0;

  @override
  Future<void> joinBattle(String battleId) async {
    joinCount++;
    final error = joinError;
    if (error != null) throw error;
  }

  @override
  Future<void> createBattle({
    required String type,
    required String title,
    required int durationHours,
  }) async {}

  @override
  Future<List<Battle>> fetchOpenRecruits() async => const [];

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
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        battleRepositoryProvider.overrideWithValue(repository),
        authRepositoryProvider.overrideWithValue(_SignedInAuthRepository()),
        vsIntroSeenStoreProvider.overrideWithValue(store),
        myProfileProvider.overrideWith((ref) async => const Profile(id: 'me', displayName: '민지')),
        openRecruitsProvider.overrideWith(
          (ref) async => [BattleRecruit(battle: battle, creatorName: '도윤')],
        ),
        myRecruitsProvider.overrideWith((ref) async => const []),
        myBattlesProvider.overrideWith((ref) async => const []),
      ],
      child: const MaterialApp(home: BattleRecruitsScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  // spec 수용 기준: "대결에 참가해 매칭에 성공한 사람에게 VS 인트로가 뜬다",
  // "인트로 때문에 참가 성공 안내가 가려져 사용자가 결과를 모르는 일이 없다".
  testWidgets('참가에 성공하면 VS 인트로가 먼저 뜨고, 닫힌 뒤에 성공 토스트가 뜬다', (tester) async {
    final repository = _JoinOnlyBattleRepository();
    final store = _MemorySeenStore();
    await _pumpRecruits(tester, repository: repository, store: store);

    await tester.tap(find.text(AppStrings.battleJoin));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

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

    await tester.tap(find.text(AppStrings.battleJoin));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(repository.joinCount, 1);
    expect(find.byType(VsIntro), findsNothing);
    expect(find.text(AppStrings.battleJoinFailed), findsOneWidget);
    expect(find.text(AppStrings.battleJoined), findsNothing);
    expect(store.seen, isEmpty);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('이미 본 대결이면 참가 직후 인트로 없이 성공 토스트가 바로 뜬다', (tester) async {
    final repository = _JoinOnlyBattleRepository();
    final store = _MemorySeenStore()..seen.add(VsIntroSeenStore.keyFor('me', 'b1'));
    await _pumpRecruits(tester, repository: repository, store: store);

    await tester.tap(find.text(AppStrings.battleJoin));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(VsIntro), findsNothing);
    expect(find.text(AppStrings.battleJoined), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });
}
