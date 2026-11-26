import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:todododo/core/strings.dart';
import 'package:todododo/core/theme/app_icons.dart';
import 'package:todododo/features/battle/domain/ai_consent_providers.dart';
import 'package:todododo/features/profile/data/player_stats.dart';
import 'package:todododo/features/profile/domain/battle_record.dart';
import 'package:todododo/features/profile/domain/profile_providers.dart';
import 'package:todododo/features/profile/presentation/nickname_edit_screen.dart';
import 'package:todododo/features/profile/presentation/profile_screen.dart';

import '../../core/push/push_fakes.dart';
import '../../helpers/text_finders.dart';
import '../notification/notification_fakes.dart';
import 'nickname_fakes.dart';

void main() {
  group('프로필에서 별명 바꾸기', () {
    testWidgets('연필 → 현재 이름이 채워진 바꾸기 화면 → 저장하면 닫히고 토스트와 새 이름', (tester) async {
      final repo = FakeNicknameProfileRepository(
        states: [confirmedNickname()],
        currentName: '부지런한 수달',
      );

      await _pumpProfile(tester, repo: repo);
      expect(findText('부지런한 수달'), findsOneWidget);

      await tester.tap(find.byTooltip(AppStrings.nicknameEditTooltip));
      await tester.pumpAndSettle();

      expect(find.byType(NicknameEditScreen), findsOneWidget);
      expect(nicknameFieldText(tester), '부지런한 수달');
      // 추천받기는 첫 화면에만 있다(spec P1-1).
      expect(findText(AppStrings.nicknameSuggestAnother), findsNothing);

      await tester.enterText(find.byType(TextField), '  수달   왕 ');
      await tester.pump();
      await tester.tap(findText(AppStrings.save));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(repo.setCalls, ['  수달   왕 ']);
      expect(find.byType(NicknameEditScreen), findsNothing);
      expect(findText(AppStrings.nicknameChanged), findsOneWidget);
      // 프로필을 다시 읽어 서버가 저장한 값(정규화된 이름)이 머리에 선다.
      expect(findText('수달 왕'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('바꾸기 화면에서 규칙 위반은 칸 아래, 화면은 닫히지 않는다', (tester) async {
      final repo = FakeNicknameProfileRepository(
        states: [confirmedNickname()],
        currentName: '부지런한 수달',
        setError: const PostgrestException(
          message: 'banned',
          hint: 'NICKNAME_BANNED',
        ),
      );

      await _pumpProfile(tester, repo: repo);
      await tester.tap(find.byTooltip(AppStrings.nicknameEditTooltip));
      await tester.pumpAndSettle();
      await tester.tap(findText(AppStrings.save));
      await tester.pumpAndSettle();

      expect(find.byType(NicknameEditScreen), findsOneWidget);
      expect(findText(AppStrings.nicknameErrorBanned), findsOneWidget);
      expect(findText(AppStrings.nicknameChanged), findsNothing);
    });

    testWidgets('바꾸기 화면에서 저장이 실패하면 토스트로 알리고 화면에 남는다', (tester) async {
      final repo = FakeNicknameProfileRepository(
        states: [confirmedNickname()],
        currentName: '부지런한 수달',
        setError: StateError('network'),
      );

      await _pumpProfile(tester, repo: repo);
      await tester.tap(find.byTooltip(AppStrings.nicknameEditTooltip));
      await tester.pumpAndSettle();
      await tester.tap(findText(AppStrings.save));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(NicknameEditScreen), findsOneWidget);
      expect(findText(AppStrings.nicknameSaveFailed), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('프로필을 불러오지 못하면 연필이 없다', (tester) async {
      final repo = FakeNicknameProfileRepository(
        states: [confirmedNickname()],
        profileError: StateError('offline'),
      );

      await _pumpProfile(tester, repo: repo);

      expect(findText(AppStrings.profileLoadFailed), findsOneWidget);
      expect(find.byTooltip(AppStrings.nicknameEditTooltip), findsNothing);
      expect(find.byIcon(AppIcons.edit), findsNothing);
    });
  });
}

/// 프로필 탭을 띄운다. 프로필 머리는 가짜 레포지토리의 지금 이름을 읽는다 — 그래서 저장 뒤 무효화가
/// 새 이름을 그리는지 화면에서 볼 수 있다.
Future<void> _pumpProfile(
  WidgetTester tester, {
  required FakeNicknameProfileRepository repo,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      // 프로필 조회 실패를 그리는 테스트가 재시도 타이머를 남기지 않게 한다.
      retry: (retryCount, error) => null,
      overrides: [
        ...notificationOverrides,
        ...pushOverrides(),
        profileRepositoryProvider.overrideWithValue(repo),
        myAiConsentProvider.overrideWith((ref) async => null),
        myPlayerStatsProvider.overrideWith((ref) async => PlayerStats.empty),
        battleRecordsProvider.overrideWith((ref) async => <BattleRecord>[]),
      ],
      child: const MaterialApp(home: ProfileScreen()),
    ),
  );
  await tester.pumpAndSettle();
}
