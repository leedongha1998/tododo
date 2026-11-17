import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todododo/core/strings.dart';
import 'package:todododo/core/theme/app_theme.dart';
import 'package:todododo/core/widgets/app_panel.dart';
import 'package:todododo/features/battle/data/battle.dart';
import 'package:todododo/features/battle/data/battle_repository.dart';
import 'package:todododo/features/battle/domain/battle_providers.dart';
import 'package:todododo/features/battle/presentation/battle_detail_screen.dart';
import 'package:todododo/features/notification/data/notification_inbox.dart';
import 'package:todododo/features/notification/data/notification_item.dart';
import 'package:todododo/features/notification/domain/notification_providers.dart';
import 'package:todododo/features/notification/presentation/notification_bell.dart';
import 'package:todododo/features/notification/presentation/notification_inbox_screen.dart';

import '../../helpers/text_finders.dart';
import 'notification_fakes.dart';

const _battleId = '3f2504e0-4f89-11d3-9a0c-0305e82c3301';

NotificationItem _item({
  int id = 1,
  String kind = 'judge_turn',
  String createdAt = '2026-11-08T06:04:00Z',
  String title = '아침 달리기',
}) => NotificationItem(
  id: id,
  kind: kind,
  battleId: _battleId,
  payload: {'title': title, 'battle_type': 'speed'},
  createdAt: DateTime.parse(createdAt),
);

/// 알림함이 쓰는 것은 `fetchBattle` 하나뿐이다("열 수 있는가"를 묻는 관문).
class _GateRepository implements BattleRepository {
  _GateRepository({this.fetchError});

  final Object? fetchError;
  int fetchCount = 0;

  @override
  Future<Battle> fetchBattle(String battleId) async {
    fetchCount++;
    final error = fetchError;
    if (error != null) throw error;
    return Battle(
      id: battleId,
      type: 'speed',
      status: 'finished',
      title: '아침 달리기',
      creatorId: 'me',
      opponentId: 'friend',
      createdAt: DateTime(2026, 11, 6),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Future<ProviderContainer> _pumpInbox(
  WidgetTester tester, {
  required FakeNotificationRepository notifications,
  _GateRepository? battles,
  bool stubDetail = false,
  double textScale = 1.0,
}) async {
  final container = ProviderContainer(
    overrides: [
      notificationRepositoryProvider.overrideWithValue(notifications),
      battleRepositoryProvider.overrideWithValue(battles ?? _GateRepository()),
      // 상세가 실제로 열리는 경로를 보는 테스트에서만. 가짜 대결 레포지토리는 `noSuchMethod`로
      // 막혀 있어 상세 화면이 그대로는 그려지지 않으므로, 선례(`battle_detail_load_test`)대로
      // 상세 provider를 덮는다 — 상세 화면의 내용은 이 파일의 관심이 아니다.
      if (stubDetail)
        battleDetailProvider(_battleId).overrideWith((ref) async => throw Exception('detail')),
    ],
    // Riverpod의 자동 재시도 타이머가 테스트 종료 뒤까지 남지 않게 끈다.
    retry: (retryCount, error) => null,
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const NotificationInboxScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  group('알림함 화면', () {
    testWidgets('알림이 없으면 사실 한 줄만 보이고 카드가 없다', (tester) async {
      await _pumpInbox(tester, notifications: FakeNotificationRepository());

      expect(findText(AppStrings.notificationInboxEmpty), findsOneWidget);
      expect(find.byType(AppPanel), findsNothing);
      // 대결을 재촉하는 버튼을 두지 않는다(spec).
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('조회가 실패하면 문구와 다시 시도가 보인다', (tester) async {
      await _pumpInbox(
        tester,
        notifications: FakeNotificationRepository(listError: Exception('network down')),
      );

      expect(findText(AppStrings.notificationInboxLoadFailed), findsOneWidget);
      expect(findText(AppStrings.retry), findsOneWidget);
    });

    testWidgets('줄에 사건 문구·대결 제목·시각이 보인다', (tester) async {
      await _pumpInbox(
        tester,
        notifications: FakeNotificationRepository(
          inbox: NotificationInbox(seenAt: null, items: [_item()]),
        ),
      );

      expect(findText(AppStrings.notificationJudgeTurn), findsOneWidget);
      expect(findText('아침 달리기'), findsOneWidget);
      expect(findTextContaining('월'), findsOneWidget);
    });

    // 2026-11-17 줄넘김 점검: 시각이 줄 오른쪽 끝에 있을 때 `Row`의 비유연 자식이라 자기 폭
    // (배율 1.0에서 106dp, 1.5에서 159dp)을 먼저 가져가, 360dp에서 글자 칸이 86 → 66dp까지
    // 줄어 사건 문구가 두세 줄이 되고 제목이 사실상 사라졌다. 시각은 이제 같은 칸의 셋째 줄이다.
    for (final scale in [1.0, 1.5]) {
      testWidgets('360dp·$scale배: 글자 칸이 줄 폭을 거의 다 쓰고 시각이 그 아래 줄에 있다', (tester) async {
        tester.view.physicalSize = const Size(360, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await _pumpInbox(
          tester,
          notifications: FakeNotificationRepository(
            inbox: NotificationInbox(seenAt: null, items: [_item()]),
          ),
          textScale: scale,
        );

        // 카드 안쪽 288 − (점 8 + 8 + 아이콘 20 + 12) = 240dp가 글자 칸이다.
        // (글자 위젯 자체는 한 줄일 때 글자 폭만 차지하므로 칸은 그 Column으로 잰다.)
        final column = tester.getRect(
          find.descendant(of: find.byType(NotificationTile), matching: find.byType(Column)),
        );
        expect(column.width, greaterThan(220));

        final text = tester.getRect(findText(AppStrings.notificationJudgeTurn));

        // 시각은 사건 문구와 같은 왼쪽 선에서 시작해 그 아래에 있다(오른쪽 칸을 선점하지 않는다).
        final time = tester.getRect(findTextContaining('월'));
        expect(time.left, moreOrLessEquals(text.left, epsilon: 0.5));
        expect(time.top, greaterThan(text.bottom - 0.5));
      });
    }

    testWidgets('첫 성공 로드에서 읽음을 한 번만 찍는다', (tester) async {
      final notifications = FakeNotificationRepository(
        inbox: NotificationInbox(seenAt: null, items: [_item()]),
      );
      final container = await _pumpInbox(tester, notifications: notifications);

      expect(notifications.markSeenCalls, 1);

      // 목록이 다시 읽혀도 다시 찍지 않는다.
      container.invalidate(notificationInboxProvider);
      await tester.pumpAndSettle();
      expect(notifications.markSeenCalls, 1);
    });

    testWidgets('조회가 실패하면 읽음을 찍지 않는다(보지 못한 알림이 읽은 것이 되지 않게)', (tester) async {
      final notifications = FakeNotificationRepository(listError: Exception('network down'));
      await _pumpInbox(tester, notifications: notifications);

      expect(notifications.markSeenCalls, 0);
    });

    testWidgets('열 수 없는 대결을 누르면 상세가 열리지 않고 토스트만 보인다', (tester) async {
      final battles = _GateRepository(fetchError: Exception('gone'));
      await _pumpInbox(
        tester,
        notifications: FakeNotificationRepository(
          inbox: NotificationInbox(seenAt: null, items: [_item()]),
        ),
        battles: battles,
      );

      await tester.tap(findText(AppStrings.notificationJudgeTurn));
      await tester.pumpAndSettle();

      expect(battles.fetchCount, 1);
      expect(find.byType(BattleDetailScreen), findsNothing);
      expect(findText(AppStrings.notificationBattleGone), findsOneWidget);
      // 알림함에 머문다.
      expect(findText(AppStrings.notificationInboxTitle), findsOneWidget);
    });

    // 2026-11-16 오너 추가: "알림을 확인하면 걔는 리스트에서 지워주고".
    // **원장을 지우는 것이 아니다** — 치운 사실이 따로 적히고 목록 조회가 그 줄을 빼고 돌려준다.
    testWidgets('줄을 누르면 그 줄을 치우고 대결 상세로 간다', (tester) async {
      final notifications = FakeNotificationRepository(
        inbox: NotificationInbox(seenAt: null, items: [_item()]),
      );
      await _pumpInbox(tester, notifications: notifications, stubDetail: true);

      await tester.tap(findText(AppStrings.notificationJudgeTurn));
      await tester.pumpAndSettle();

      expect(notifications.dismissedIds, [1]);
      expect(find.byType(BattleDetailScreen), findsOneWidget);
    });

    testWidgets('치운 줄은 목록에서 사라지고 나머지는 남는다', (tester) async {
      final notifications = FakeNotificationRepository(
        inbox: NotificationInbox(
          seenAt: null,
          items: [_item(), _item(id: 2, kind: 'submitted')],
        ),
      );
      // 상세를 열지 못하는 대결로 둔다 — 알림함에 머물러야 목록을 눈으로 확인할 수 있고,
      // **열 수 없는 대결의 줄도 누르면 사라진다**가 수용 기준이다(영원히 열 수 없는 줄이
      // 목록에 남지 않게).
      await _pumpInbox(
        tester,
        notifications: notifications,
        battles: _GateRepository(fetchError: Exception('gone')),
      );

      await tester.tap(findText(AppStrings.notificationJudgeTurn));
      await tester.pumpAndSettle();

      expect(findText(AppStrings.notificationJudgeTurn), findsNothing);
      expect(findText(AppStrings.notificationSubmitted), findsOneWidget);
      expect(findText(AppStrings.notificationInboxTitle), findsOneWidget);
    });

    testWidgets('치우기가 실패하면 줄이 그대로 남는다', (tester) async {
      final notifications = FakeNotificationRepository(
        inbox: NotificationInbox(seenAt: null, items: [_item()]),
        dismissError: Exception('dismiss down'),
      );
      await _pumpInbox(
        tester,
        notifications: notifications,
        battles: _GateRepository(fetchError: Exception('gone')),
      );

      await tester.tap(findText(AppStrings.notificationJudgeTurn));
      await tester.pumpAndSettle();

      expect(notifications.dismissedIds, isEmpty);
      // 줄이 남은 것이 실패를 이미 말한다 — 치우기 실패에 토스트를 띄우지 않는다.
      expect(findText(AppStrings.notificationJudgeTurn), findsOneWidget);
    });
  });

  group('종 아이콘(NotificationBell)', () {
    // overrides를 인자로 받지 않는 이유: riverpod 3은 `Override` 타입을 공개 export하지 않아
    // 그 목록의 타입을 적을 수 없다. 필요한 갈래만 플래그로 받는다.
    Future<void> pumpBell(
      WidgetTester tester, {
      bool hasNew = false,
      bool badgeFails = false,
      bool slowBadge = false,
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            if (badgeFails)
              hasNewNotificationsProvider.overrideWith(
                (ref) => Future.error(Exception('down')),
              )
            else if (slowBadge)
              // 다시 읽는 동안을 눈으로 잡으려면 즉시 끝나지 않아야 한다.
              hasNewNotificationsProvider.overrideWith(
                (ref) => Future<bool>.delayed(const Duration(milliseconds: 50), () => true),
              )
            else
              notificationRepositoryProvider.overrideWithValue(
                FakeNotificationRepository(hasNewValue: hasNew),
              ),
            battleRepositoryProvider.overrideWithValue(_GateRepository()),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              appBar: AppBar(
                title: const Text('어느 탭'),
                actions: const [NotificationBell()],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    bool badgeVisible(WidgetTester tester) =>
        tester.widget<Badge>(find.byType(Badge)).isLabelVisible;

    testWidgets('새 알림이 있으면 점이 보인다', (tester) async {
      await pumpBell(tester, hasNew: true);
      expect(badgeVisible(tester), isTrue);
      // 숫자 배지를 만들지 않는다(점 하나 — spec 결정 3).
      expect(find.byType(Badge), findsOneWidget);
      expect(tester.widget<Badge>(find.byType(Badge)).label, isNull);
    });

    testWidgets('새 알림이 없으면 점이 없다', (tester) async {
      await pumpBell(tester);
      expect(badgeVisible(tester), isFalse);
    });

    testWidgets('배지 조회가 실패하면 점을 그리지 않는다(잘못된 안내를 띄우지 않는다)', (tester) async {
      await pumpBell(tester, badgeFails: true);
      expect(badgeVisible(tester), isFalse);
    });

    // `MainShell`은 탭 전환·앱 재개마다 이 provider를 invalidate한다. riverpod의 재조회 상태는
    // **이전 값을 든 AsyncLoading**이라, 로딩으로 점을 끄면 탭을 옮길 때마다 점이 깜빡이고
    // 느린 망에서는 "사라졌다"로 읽힌다(2026-11-13 리뷰).
    testWidgets('다시 읽는 동안에는 점이 꺼지지 않는다', (tester) async {
      await pumpBell(tester, slowBadge: true);
      expect(badgeVisible(tester), isTrue);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(NotificationBell)),
      );
      container.invalidate(hasNewNotificationsProvider);
      await tester.pump();

      expect(badgeVisible(tester), isTrue, reason: '재조회 중');

      await tester.pumpAndSettle();
      expect(badgeVisible(tester), isTrue, reason: '재조회 뒤');
    });

    testWidgets('누르면 알림함이 열린다', (tester) async {
      await pumpBell(tester);

      await tester.tap(find.byType(NotificationBell));
      await tester.pumpAndSettle();

      expect(find.byType(NotificationInboxScreen), findsOneWidget);
    });
  });
}
