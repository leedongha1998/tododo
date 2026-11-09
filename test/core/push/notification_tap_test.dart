// 알림을 탭했을 때 셸이 하는 일(push-notification 5단계).
//
// 보는 것: 열 수 있는 대결이면 상세가 뜬다 / 열 수 없으면 오류 화면 없이 그대로 머문다 /
// 탭이 없으면 아무 일도 없다. 실제 FCM은 부르지 않는다(가짜 pushMessagingProvider).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todododo/core/navigation/app_tab.dart';
import 'package:todododo/core/navigation/main_shell.dart';
import 'package:todododo/features/battle/data/battle.dart';
import 'package:todododo/features/battle/data/battle_participant.dart';
import 'package:todododo/features/battle/data/battle_repository.dart';
import 'package:todododo/features/battle/data/criteria_check_result.dart';
import 'package:todododo/features/battle/data/open_recruit_page.dart';
import 'package:todododo/features/battle/data/profile.dart';
import 'package:todododo/features/battle/data/vs_intro_seen_store.dart';
import 'package:todododo/features/battle/domain/ai_consent_providers.dart';
import 'package:todododo/features/battle/domain/battle_detail.dart';
import 'package:todododo/features/battle/domain/battle_providers.dart';
import 'package:todododo/features/battle/presentation/battle_detail_screen.dart';
import 'package:todododo/features/profile/data/player_stats.dart';
import 'package:todododo/features/profile/domain/profile_providers.dart';
import 'package:todododo/features/todo/domain/todo_providers.dart';

import '../../features/todo/due_alarm_fakes.dart';
import '../../features/todo/todo_widget_fakes.dart';
import 'push_fakes.dart';

const _battleId = '3f2504e0-4f89-11d3-9a0c-0305e82c3301';

/// 알림이 가리키는 대결만 돌려주는 저장소. 나머지는 쓰이지 않는다.
class _TapRepository implements BattleRepository {
  _TapRepository({this.fetchError});

  final Object? fetchError;
  int fetchCount = 0;

  @override
  Future<Battle> fetchBattle(String battleId) async {
    fetchCount++;
    final error = fetchError;
    if (error != null) throw error;
    return _battle;
  }

  @override
  Future<OpenRecruitPage> fetchOpenRecruits({
    int limit = openRecruitPageSize,
    RecruitCursor? cursor,
    String? query,
    String? type,
    String? durationBand,
  }) async =>
      const OpenRecruitPage(items: [], nextCursor: null, hasMore: false);

  @override
  Future<MyLimits> fetchMyLimits() async =>
      const MyLimits(consented: true, criteriaCallsLeft: 10);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _SeenAllStore extends VsIntroSeenStore {
  const _SeenAllStore();

  @override
  Future<bool> hasSeen(String userId, String battleId) async => true;

  @override
  Future<void> markSeen(String userId, String battleId) async {}
}

final _battle = Battle(
  id: _battleId,
  type: 'speed',
  status: 'finished',
  title: '아침 달리기',
  creatorId: 'me',
  opponentId: 'friend',
  winnerId: 'me',
  createdAt: DateTime(2026, 11, 6),
);

final _detail = BattleDetail(
  battle: _battle,
  me: const BattleParticipant(battleId: _battleId, userId: 'me'),
  opponent: const BattleParticipant(battleId: _battleId, userId: 'friend'),
  myName: '나',
  opponentName: '친구',
);

Future<void> _pumpShell(
  WidgetTester tester, {
  required FakePushMessaging messaging,
  required _TapRepository repository,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...pushOverrides(messaging: messaging),
        ...dueAlarmOverrides(),
        ...todoWidgetOverrides(),
        battleRepositoryProvider.overrideWithValue(repository),
        battleDetailProvider(_battleId).overrideWith((ref) async => _detail),
        vsIntroSeenStoreProvider.overrideWithValue(const _SeenAllStore()),
        todosProvider.overrideWith((ref) async => []),
        myBattlesProvider.overrideWith((ref) async => []),
        myRecruitsProvider.overrideWith((ref) async => []),
        myAiConsentProvider.overrideWith((ref) async => null),
        myProfileProvider.overrideWith(
          (ref) async => const Profile(id: 'me', displayName: '나'),
        ),
        myPlayerStatsProvider.overrideWith((ref) async => PlayerStats.empty),
        battleRecordsProvider.overrideWith((ref) async => []),
      ],
      child: const MaterialApp(home: MainShell()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('알림을 탭해 시작하면 그 대결 상세가 열린다', (tester) async {
    final repository = _TapRepository();
    await _pumpShell(
      tester,
      // 앱이 종료된 상태에서 알림을 탭한 경우. start()가 집어 온다.
      messaging: FakePushMessaging()..initial = {'battle_id': _battleId, 'kind': 'finished'},
      repository: repository,
    );

    expect(find.byType(BattleDetailScreen), findsOneWidget);
    // 띄우기 전에 열 수 있는지 서버에 한 번 물어본다.
    expect(repository.fetchCount, 1);
  });

  testWidgets('탭한 알림이 없으면 상세를 열지 않는다', (tester) async {
    final repository = _TapRepository();
    await _pumpShell(tester, messaging: FakePushMessaging(), repository: repository);

    expect(find.byType(BattleDetailScreen), findsNothing);
    expect(repository.fetchCount, 0);
  });

  testWidgets('열 수 없는 대결이면 오류 화면 없이 셸에 머문다', (tester) async {
    // 취소됐거나 더 볼 수 없는 대결. spec: 알림을 눌러서 오류 화면을 보는 일은 없어야 한다.
    final repository = _TapRepository(fetchError: Exception('없는 대결'));
    await _pumpShell(
      tester,
      messaging: FakePushMessaging()..initial = {'battle_id': _battleId, 'kind': 'cancelled'},
      repository: repository,
    );

    expect(find.byType(BattleDetailScreen), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(repository.fetchCount, 1);
  });

  testWidgets('앱이 떠 있는 동안 탭해도 상세가 열린다', (tester) async {
    final messaging = FakePushMessaging();
    final repository = _TapRepository();
    await _pumpShell(tester, messaging: messaging, repository: repository);

    expect(find.byType(BattleDetailScreen), findsNothing);

    messaging.emitOpened({'battle_id': _battleId, 'kind': 'judge_turn'});
    await tester.pumpAndSettle();

    expect(find.byType(BattleDetailScreen), findsOneWidget);
  });

  testWidgets('알림으로 열면 내 대결 탭으로 옮겨 둔다 - 상세를 닫으면 그 목록이 보인다', (tester) async {
    final messaging = FakePushMessaging();
    final repository = _TapRepository();
    await _pumpShell(tester, messaging: messaging, repository: repository);

    // 다른 탭을 보고 있다가 알림을 탭한 상황.
    final element = tester.element(find.byType(MainShell));
    final container = ProviderScope.containerOf(element);
    container.read(selectedTabProvider.notifier).select(AppTab.todo);
    await tester.pumpAndSettle();

    messaging.emitOpened({'battle_id': _battleId, 'kind': 'finished'});
    await tester.pumpAndSettle();

    expect(find.byType(BattleDetailScreen), findsOneWidget);
    expect(container.read(selectedTabProvider), AppTab.myBattles);
  });
}
