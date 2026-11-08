import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:todododo/core/push/push_messaging.dart';
import 'package:todododo/core/push/push_providers.dart';
import 'package:todododo/core/strings.dart';
import 'package:todododo/features/profile/presentation/notification_section.dart';

import '../../core/push/push_fakes.dart';
import '../../helpers/text_finders.dart';

Future<void> _pump(WidgetTester tester, List<Override> overrides) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: const MaterialApp(home: Scaffold(body: NotificationSection())),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('알림이 꺼져 있으면 안내와 켜는 방법을 보여준다', (tester) async {
    await _pump(
      tester,
      pushOverrides(messaging: FakePushMessaging(permission: NotificationPermission.denied)),
    );

    expect(findText(AppStrings.notificationDisabled), findsOneWidget);
    expect(findText(AppStrings.notificationDisabledGuide), findsOneWidget);
  });

  testWidgets('알림이 켜져 있으면 아무것도 그리지 않는다', (tester) async {
    await _pump(
      tester,
      pushOverrides(messaging: FakePushMessaging(permission: NotificationPermission.granted)),
    );

    expect(findText(AppStrings.notificationDisabled), findsNothing);
  });

  testWidgets('아직 묻지 않은 상태에서는 안내하지 않는다 — 기기 설정으로 보낼 일이 아니다', (tester) async {
    await _pump(
      tester,
      pushOverrides(
        messaging: FakePushMessaging(permission: NotificationPermission.notDetermined),
      ),
    );

    expect(findText(AppStrings.notificationDisabled), findsNothing);
  });

  testWidgets('권한 상태를 못 읽으면 틀린 안내를 띄우지 않는다', (tester) async {
    await _pump(tester, [
      notificationPermissionProvider.overrideWith((ref) async => throw Exception('no firebase')),
    ]);

    expect(findText(AppStrings.notificationDisabled), findsNothing);
  });
}
