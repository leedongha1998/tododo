import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// AndroidManifest.xml의 login-callback intent-filter와 반드시 일치해야 한다.
const _googleRedirectUrl = 'com.todododo.todododo://login-callback/';

class AuthRepository {
  AuthRepository(this._client);

  final SupabaseClient _client;

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  User? get currentUser => _client.auth.currentUser;

  /// 브라우저에 이미 로그인된 구글 계정이 있으면 선택 없이 그대로 통과해버린다.
  /// 계정을 여러 개 쓰는 사용자가 원하는 계정을 고를 수 없으므로 항상 선택 화면을 띄운다.
  Future<void> signInWithGoogle() {
    return _client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: _googleRedirectUrl,
      queryParams: const {'prompt': 'select_account'},
    );
  }

  Future<void> signOut() {
    return _client.auth.signOut();
  }

  /// 계정 삭제(탈퇴). 되돌릴 수 없다.
  ///
  /// 증거 사진은 Storage API로 먼저 지운다 — storage.objects 행만 지우면 실제 파일이 버킷에
  /// 남기 때문이다. 나머지 삭제는 delete_account RPC가 하고, 끝나면 로컬 세션을 정리한다.
  Future<void> deleteAccount() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('로그인 상태가 아닙니다.');
    }

    try {
      // 내 제출 행만 읽힌다(RLS). 경로가 null인 행은 이미 정리된 것이다.
      final rows = await _client
          .from('battle_submissions')
          .select('object_path')
          .eq('user_id', userId);
      final paths = rows
          .map((row) => row['object_path'] as String?)
          .whereType<String>()
          .toSet()
          .toList();
      if (paths.isNotEmpty) {
        await _client.storage.from('battle_evidence').remove(paths);
      }
    } catch (error) {
      // 사진 정리에 실패해도 계정 삭제까지 막지는 않는다. 참조는 RPC가 지운다.
      debugPrint('evidence photo cleanup failed: $error');
    }

    await _client.rpc('delete_account');
    await _client.auth.signOut();
  }
}
