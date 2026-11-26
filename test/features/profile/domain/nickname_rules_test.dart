import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:todododo/core/strings.dart';
import 'package:todododo/features/profile/data/nickname_state.dart';
import 'package:todododo/features/profile/domain/nickname_rules.dart';

const _unconfirmed = NicknameState(nickname: '부지런한 수달', confirmed: false, wasReset: false);
const _confirmed = NicknameState(nickname: '부지런한 수달', confirmed: true, wasReset: false);

PostgrestException _rejection(String? hint, {Object? details}) =>
    PostgrestException(message: '서버 로그용 메시지', hint: hint, details: details);

void main() {
  group('NicknameState.fromMap', () {
    test('서버 jsonb를 그대로 옮긴다', () {
      final state = NicknameState.fromMap({
        'nickname': '수달 왕',
        'confirmed': true,
        'was_reset': true,
      });

      expect(state.nickname, '수달 왕');
      expect(state.confirmed, isTrue);
      expect(state.wasReset, isTrue);
    });

    test('키가 빠지거나 타입이 어긋나면 미확정·안내 없음·빈 이름으로 읽는다', () {
      // 관문을 한 번 더 보여 주는 쪽이 별명을 정하지 않은 사용자를 조용히 통과시키는 쪽보다 낫다.
      final missing = NicknameState.fromMap({});
      expect(missing.nickname, '');
      expect(missing.confirmed, isFalse);
      expect(missing.wasReset, isFalse);

      final wrongTypes = NicknameState.fromMap({
        'nickname': 3,
        'confirmed': 'true',
        'was_reset': 1,
      });
      expect(wrongTypes.nickname, '');
      expect(wrongTypes.confirmed, isFalse);
      expect(wrongTypes.wasReset, isFalse);
    });
  });

  group('nicknameGateView', () {
    test('첫 조회 중이면 로더', () {
      expect(nicknameGateView(const AsyncLoading<NicknameState>()), NicknameGateView.loading);
    });

    test('미확정이면 별명 정하기, 확정했으면 본 화면', () {
      expect(nicknameGateView(const AsyncData(_unconfirmed)), NicknameGateView.setup);
      expect(nicknameGateView(const AsyncData(_confirmed)), NicknameGateView.shell);
    });

    test('조회가 실패하면 본 화면으로 통과시킨다(오너 결정 1의 a)', () {
      expect(
        nicknameGateView(AsyncError<NicknameState>(StateError('offline'), StackTrace.empty)),
        NicknameGateView.shell,
      );
    });

    test('직전 값(미확정)을 든 실패도 본 화면이다 - 오류를 값보다 먼저 본다', () async {
      // riverpod의 AsyncError는 직전 값을 들고 있다. 값부터 보면 재조회 실패가 "미확정"으로 읽혀
      // 관문으로 되돌아간다. 그 모양을 실제 provider로 만든다(copyWithPrevious는 내부 API다).
      var calls = 0;
      final provider = FutureProvider<NicknameState>((ref) async {
        calls++;
        if (calls == 1) return _unconfirmed;
        throw StateError('offline');
      });
      final container = ProviderContainer(retry: (retryCount, error) => null);
      addTearDown(container.dispose);
      final subscription = container.listen(provider, (previous, next) {});
      addTearDown(subscription.close);

      await container.read(provider.future);
      container.invalidate(provider);
      await expectLater(container.read(provider.future), throwsStateError);
      final state = container.read(provider);

      // 전제: 실패가 직전 값을 들고 있다(이 전제가 깨지면 테스트가 아무것도 보장하지 않는다).
      expect(state.hasError, isTrue);
      expect(state.value?.confirmed, isFalse);
      expect(nicknameGateView(state), NicknameGateView.shell);
    });
  });

  group('nicknameRejectionOf', () {
    test('NICKNAME_* 네 코드를 규칙 위반으로 읽는다', () {
      expect(nicknameRejectionOf(_rejection('NICKNAME_LENGTH'))?.kind, NicknameRejectionKind.length);
      expect(nicknameRejectionOf(_rejection('NICKNAME_CHARS'))?.kind, NicknameRejectionKind.chars);
      expect(
        nicknameRejectionOf(_rejection('NICKNAME_RESERVED', details: '공식'))?.kind,
        NicknameRejectionKind.reserved,
      );
      expect(nicknameRejectionOf(_rejection('NICKNAME_BANNED'))?.kind, NicknameRejectionKind.banned);
    });

    test('예약어는 서버가 준 말(details)을 들고, 비었거나 없으면 말 없이', () {
      expect(nicknameRejectionOf(_rejection('NICKNAME_RESERVED', details: '공식'))?.term, '공식');
      expect(nicknameRejectionOf(_rejection('NICKNAME_RESERVED', details: ''))?.term, isNull);
      expect(nicknameRejectionOf(_rejection('NICKNAME_RESERVED', details: '  '))?.term, isNull);
      expect(nicknameRejectionOf(_rejection('NICKNAME_RESERVED'))?.term, isNull);
      expect(nicknameRejectionOf(_rejection('NICKNAME_RESERVED', details: 3))?.term, isNull);
    });

    test('금칙어는 details가 와도 말을 들지 않는다(욕설을 화면에 되돌려 보여 주지 않는다)', () {
      expect(nicknameRejectionOf(_rejection('NICKNAME_BANNED', details: '씨발'))?.term, isNull);
    });

    test('그 밖의 오류는 규칙 위반이 아니다(토스트로 간다)', () {
      expect(nicknameRejectionOf(_rejection('ACCOUNT_DELETED')), isNull);
      expect(nicknameRejectionOf(_rejection(null)), isNull);
      expect(nicknameRejectionOf(StateError('network')), isNull);
      expect(nicknameRejectionOf(Exception('timeout')), isNull);
    });
  });

  group('nicknameRejectionMessage', () {
    test('코드마다 문구가 하나씩이다', () {
      expect(
        nicknameRejectionMessage(const NicknameRejection(NicknameRejectionKind.length)),
        AppStrings.nicknameErrorLength,
      );
      expect(
        nicknameRejectionMessage(const NicknameRejection(NicknameRejectionKind.chars)),
        AppStrings.nicknameErrorChars,
      );
      expect(
        nicknameRejectionMessage(const NicknameRejection(NicknameRejectionKind.banned)),
        AppStrings.nicknameErrorBanned,
      );
    });

    test('예약어는 걸린 말이 있으면 말까지, 없으면 일반 문구', () {
      expect(
        nicknameRejectionMessage(
          const NicknameRejection(NicknameRejectionKind.reserved, term: '공식'),
        ),
        AppStrings.nicknameErrorReserved('공식'),
      );
      expect(AppStrings.nicknameErrorReserved('공식'), endsWith(': 공식'));
      expect(
        nicknameRejectionMessage(const NicknameRejection(NicknameRejectionKind.reserved)),
        AppStrings.nicknameErrorReservedGeneric,
      );
    });
  });

  group('nicknameDisplayLength (P1-2 글자 수)', () {
    test('앞뒤 공백을 지우고 연속 공백을 한 칸으로 센다', () {
      expect(nicknameDisplayLength('  수달   왕 '), 4);
      expect(nicknameDisplayLength('부지런한 수달'), 7);
    });

    test('탭·줄바꿈·NBSP·전각 공백도 공백 한 칸이다(서버 정규화와 같은 목록)', () {
      expect(nicknameDisplayLength('수달\t\n왕'), 4);
      expect(nicknameDisplayLength(' 수달　왕　'), 4);
    });

    test('빈 칸과 공백만은 0, 코드 포인트로 센다(이모지 하나는 1)', () {
      expect(nicknameDisplayLength(''), 0);
      expect(nicknameDisplayLength('   '), 0);
      expect(nicknameDisplayLength('가😀'), 2);
    });
  });
}
