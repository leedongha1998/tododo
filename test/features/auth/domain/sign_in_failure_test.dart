import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:todododo/features/auth/domain/sign_in_failure.dart';

/// 브라우저에서 돌아온 로그인 오류 중 **취소·동의 거부만** 조용히 넘긴다(kakao-login design 흐름 2·8.3).
/// 애매하면 오류 쪽(토스트)이다.
void main() {
  test('access_denied 코드는 취소다', () {
    expect(isOAuthCancellation(const AuthException('User denied', code: 'access_denied')), isTrue);
  });

  test('메시지나 코드에 access_denied가 들어 있으면 취소다', () {
    expect(isOAuthCancellation(const AuthException('error=access_denied')), isTrue);
    expect(isOAuthCancellation(const AuthException('x', code: 'oauth_access_denied')), isTrue);
  });

  test('그 밖의 인증 오류는 실제 오류다', () {
    expect(isOAuthCancellation(const AuthException('invalid flow state')), isFalse);
    expect(
      isOAuthCancellation(const AuthException('Code verifier not found', code: 'flow_state_not_found')),
      isFalse,
    );
  });

  test('네트워크류 예외는 실제 오류다', () {
    expect(isOAuthCancellation(Exception('SocketException: Failed host lookup')), isFalse);
    expect(isOAuthCancellation(StateError('access_denied')), isFalse);
  });
}
