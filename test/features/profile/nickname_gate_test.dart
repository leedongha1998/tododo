import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:todododo/core/navigation/main_shell.dart';
import 'package:todododo/core/strings.dart';
import 'package:todododo/features/auth/data/auth_repository.dart';
import 'package:todododo/features/auth/domain/auth_providers.dart';
import 'package:todododo/features/auth/presentation/auth_gate.dart';
import 'package:todododo/features/profile/domain/profile_providers.dart';
import 'package:todododo/features/profile/presentation/nickname_gate.dart';
import 'package:todododo/features/profile/presentation/nickname_setup_screen.dart';

import '../../helpers/text_finders.dart';
import '../todo/todo_widget_fakes.dart';
import 'nickname_fakes.dart';

/// 별명 관문과 프로필의 별명 바꾸기(nickname design 7장, 11.5).
///
/// 관문은 **모든 사용자가 반드시 지나는 길**이라(여기서 깨지면 아무도 앱에 못 들어온다) 화면 테스트가
/// 선택인 이 저장소에서도 만든다.
void main() {
  group('관문', () {
    testWidgets('로그인하면 AuthGate가 본 화면 전에 별명 관문을 세운다', (tester) async {
      final repo = FakeNicknameProfileRepository(
        states: [unconfirmedNickname()],
      );
      final session = Session(
        accessToken: 'token',
        tokenType: 'bearer',
        user: const User(
          id: 'me',
          appMetadata: {},
          userMetadata: {},
          aud: 'authenticated',
          createdAt: '2026-11-24T00:00:00Z',
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...todoWidgetOverrides(),
            authStateProvider.overrideWith(
              (ref) =>
                  Stream.value(AuthState(AuthChangeEvent.signedIn, session)),
            ),
            profileRepositoryProvider.overrideWithValue(repo),
          ],
          child: const MaterialApp(home: AuthGate()),
        ),
      );
      await tester.pumpAndSettle();

      // 미확정이라 본 화면(MainShell)은 아직 만들어지지 않는다 — 푸시 등록·기한 알림·위젯 캐시도 관문
      // 뒤에서 시작한다(design 7.1).
      expect(find.byType(NicknameGate), findsOneWidget);
      expect(find.byType(NicknameSetupScreen), findsOneWidget);
      expect(find.byType(MainShell), findsNothing);
    });

    testWidgets('미확정이면 서버가 채운 별명으로 별명 정하기가 뜨고, 그대로 확정하면 본 화면으로 간다', (
      tester,
    ) async {
      final repo = FakeNicknameProfileRepository(
        states: [unconfirmedNickname(), confirmedNickname()],
      );

      await _pumpGate(tester, repo: repo);

      expect(find.byType(NicknameSetupScreen), findsOneWidget);
      expect(findText(AppStrings.nicknameSetupTitle), findsOneWidget);
      expect(nicknameFieldText(tester), '부지런한 수달');
      // 새 계정에게는 "이름이 바뀌었어요" 안내가 없다.
      expect(findText(AppStrings.nicknameResetNoticeTitle), findsNothing);
      expect(findText(_shell), findsNothing);

      await tester.tap(findText(AppStrings.nicknameConfirm));
      await tester.pumpAndSettle();

      // 원문 그대로 보낸다(다듬기·검사는 서버 몫).
      expect(repo.setCalls, ['부지런한 수달']);
      expect(findText(_shell), findsOneWidget);
      expect(find.byType(NicknameSetupScreen), findsNothing);
    });

    testWidgets('확정한 사용자는 관문 없이 바로 본 화면이다', (tester) async {
      final repo = FakeNicknameProfileRepository(states: [confirmedNickname()]);

      await _pumpGate(tester, repo: repo);

      expect(findText(_shell), findsOneWidget);
      expect(find.byType(NicknameSetupScreen), findsNothing);
    });

    testWidgets('서버가 이름을 덮은 기존 사용자에게만 이유 안내가 보인다', (tester) async {
      final repo = FakeNicknameProfileRepository(
        states: [unconfirmedNickname(wasReset: true)],
      );

      await _pumpGate(tester, repo: repo);

      expect(findText(AppStrings.nicknameResetNoticeTitle), findsOneWidget);
      expect(findText(AppStrings.nicknameResetNoticeBody), findsOneWidget);
    });

    testWidgets('규칙 위반은 칸 아래에 이유를 말하고, 칸 내용을 두고, 다시 치면 지운다', (tester) async {
      final repo = FakeNicknameProfileRepository(
        states: [unconfirmedNickname()],
        setError: const PostgrestException(
          message: 'reserved',
          hint: 'NICKNAME_RESERVED',
          details: '공식',
        ),
      );

      await _pumpGate(tester, repo: repo);
      await tester.enterText(find.byType(TextField), '공식왕');
      await tester.pump();
      await tester.tap(findText(AppStrings.nicknameConfirm));
      await tester.pumpAndSettle();

      expect(repo.setCalls, ['공식왕']);
      expect(findText(AppStrings.nicknameErrorReserved('공식')), findsOneWidget);
      expect(nicknameFieldText(tester), '공식왕');
      // 관문은 그대로다(확정되지 않았다).
      expect(findText(_shell), findsNothing);
      // 오류 줄이 서 있는 동안 안내 줄은 그 자리를 비켜 준다.
      expect(findText(AppStrings.nicknameRuleHint), findsNothing);

      await tester.enterText(find.byType(TextField), '수달왕');
      // 오류 줄은 바로 사라지지 않고 안내 줄과 잠깐 겹쳐 바뀐다(InputDecorator의 전환). 끝까지 돌린다.
      await tester.pumpAndSettle();

      expect(findText(AppStrings.nicknameErrorReserved('공식')), findsNothing);
      expect(findText(AppStrings.nicknameRuleHint), findsOneWidget);
    });

    testWidgets('저장이 실패하면 토스트로 알리고 버튼이 다시 살아난다', (tester) async {
      final repo = FakeNicknameProfileRepository(
        states: [unconfirmedNickname()],
        setError: StateError('network'),
      );

      await _pumpGate(tester, repo: repo);
      await tester.tap(findText(AppStrings.nicknameConfirm));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500)); // 스낵바 등장

      expect(findText(AppStrings.nicknameSaveFailed), findsOneWidget);
      expect(_confirmButton(tester).onPressed, isNotNull);
      // 규칙 위반이 아니므로 칸 아래 오류 줄은 없다.
      expect(findText(AppStrings.nicknameErrorReservedGeneric), findsNothing);
      expect(findText(_shell), findsNothing);
      await tester.pump(const Duration(seconds: 5)); // 스낵바 타이머 소진
    });

    testWidgets('로그아웃을 누르면 로그아웃하고, 실패하면 토스트로 알린다', (tester) async {
      final auth = _FakeAuthRepository(signOutError: StateError('network'));
      final repo = FakeNicknameProfileRepository(
        states: [unconfirmedNickname()],
      );

      await _pumpGate(tester, repo: repo, auth: auth);
      await tester.tap(findText(AppStrings.logout));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(auth.signOutCount, 1);
      // 관문에서는 로그아웃이 유일한 출구라 실패를 받는다.
      expect(findText(AppStrings.logoutFailed), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('로그아웃이 성공하면 토스트가 없다', (tester) async {
      final auth = _FakeAuthRepository();
      final repo = FakeNicknameProfileRepository(
        states: [unconfirmedNickname()],
      );

      await _pumpGate(tester, repo: repo, auth: auth);
      await tester.tap(findText(AppStrings.logout));
      await tester.pump();

      expect(auth.signOutCount, 1);
      expect(findText(AppStrings.logoutFailed), findsNothing);
    });

    testWidgets('상태 조회가 실패하면 본 화면으로 통과하고, 그 뒤 미확정으로 읽혀도 되돌리지 않는다', (
      tester,
    ) async {
      final repo = FakeNicknameProfileRepository(
        states: [StateError('offline'), unconfirmedNickname()],
      );

      await _pumpGate(tester, repo: repo);

      expect(findText(_shell), findsOneWidget);
      expect(find.byType(NicknameSetupScreen), findsNothing);

      // 무언가가 상태를 다시 읽게 해도(재시도·무효화) 본 화면에서 관문으로 끌려 나가지 않는다(래치).
      final container = ProviderScope.containerOf(
        tester.element(find.byType(NicknameGate)),
      );
      container.invalidate(myNicknameStateProvider('me'));
      await tester.pumpAndSettle();

      expect(findText(_shell), findsOneWidget);
      expect(find.byType(NicknameSetupScreen), findsNothing);
    });
  });

  group('P1', () {
    testWidgets('다른 별명 추천받기는 칸을 새 별명으로 덮고 오류 줄을 지운다', (tester) async {
      final repo = FakeNicknameProfileRepository(
        states: [unconfirmedNickname()],
        setError: const PostgrestException(
          message: 'length',
          hint: 'NICKNAME_LENGTH',
        ),
        suggestion: '느긋한 펭귄',
      );

      await _pumpGate(tester, repo: repo);
      await tester.enterText(find.byType(TextField), '가');
      await tester.pump();
      await tester.tap(findText(AppStrings.nicknameConfirm));
      await tester.pumpAndSettle();
      expect(findText(AppStrings.nicknameErrorLength), findsOneWidget);

      await tester.tap(findText(AppStrings.nicknameSuggestAnother));
      await tester.pumpAndSettle();

      expect(nicknameFieldText(tester), '느긋한 펭귄');
      expect(findText(AppStrings.nicknameErrorLength), findsNothing);
      // 추천은 아무것도 쓰지 않는다 - 확정은 여전히 사용자가 누른다.
      expect(repo.setCalls, ['가']);
    });

    testWidgets('추천받기가 실패하면 칸은 그대로 두고 토스트만 띄운다', (tester) async {
      final repo = FakeNicknameProfileRepository(
        states: [unconfirmedNickname()],
        suggestError: StateError('network'),
      );

      await _pumpGate(tester, repo: repo);
      await tester.tap(findText(AppStrings.nicknameSuggestAnother));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(nicknameFieldText(tester), '부지런한 수달');
      expect(findText(AppStrings.nicknameSuggestFailed), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('규칙 안내와 글자 수가 보이고, 글자 수는 공백을 정리한 뒤 센다', (tester) async {
      final repo = FakeNicknameProfileRepository(
        states: [unconfirmedNickname()],
      );

      await _pumpGate(tester, repo: repo);

      expect(findText(AppStrings.nicknameRuleHint), findsOneWidget);
      expect(findText(AppStrings.nicknameLength(7)), findsOneWidget);

      await tester.enterText(find.byType(TextField), '  수달   왕 ');
      await tester.pump();

      expect(findText(AppStrings.nicknameLength(4)), findsOneWidget);
    });
  });
}

const _shell = '본 화면';

FilledButton _confirmButton(WidgetTester tester) => tester.widget<FilledButton>(
  findWidgetWithText(FilledButton, AppStrings.nicknameConfirm),
);

Future<void> _pumpGate(
  WidgetTester tester, {
  required FakeNicknameProfileRepository repo,
  _FakeAuthRepository? auth,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        profileRepositoryProvider.overrideWithValue(repo),
        authRepositoryProvider.overrideWithValue(auth ?? _FakeAuthRepository()),
      ],
      child: const MaterialApp(
        home: NicknameGate(
          userId: 'me',
          child: Scaffold(body: Text(_shell)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository({this.signOutError});

  final Object? signOutError;
  int signOutCount = 0;

  @override
  Future<void> signOut() async {
    signOutCount++;
    final error = signOutError;
    if (error != null) throw error;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
