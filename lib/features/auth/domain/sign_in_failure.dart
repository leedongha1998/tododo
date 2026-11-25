import 'package:supabase_flutter/supabase_flutter.dart';

/// 브라우저(구글·카카오 로그인)에서 앱으로 돌아온 결과가 **사용자가 취소하거나 동의를 거부한 것**인지
/// (kakao-login design 흐름 2, 오너 확정 1번 — 두 공급자 공통).
///
/// 돌아온 딥링크에 `error`가 있으면 supabase_flutter가 `AuthException(code: <error>)`를
/// `onAuthStateChange` 스트림에 오류로 흘린다. 취소·거부는 OAuth 표준 오류 `access_denied`로 온다.
/// 그 밖(코드 교환 실패·네트워크 등)은 전부 실제 오류다.
///
/// **애매하면 오류 쪽**이다 — 토스트가 한 번 더 뜨는 쪽이 오류를 삼키는 쪽보다 낫다(CLAUDE.md
/// "에러는 삼키지 않는다"). 카카오 취소의 실제 모양은 실기기(design §8.4 M3)에서 확인하고, 다르면 이
/// 조건만 고친다.
bool isOAuthCancellation(Object error) {
  if (error is! AuthException) return false;
  const marker = 'access_denied';
  final code = error.code;
  return (code != null && code.contains(marker)) || error.message.contains(marker);
}
