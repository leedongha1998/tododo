import 'package:supabase_flutter/supabase_flutter.dart';

/// AndroidManifest.xml의 login-callback intent-filter와 반드시 일치해야 한다.
const _googleRedirectUrl = 'com.todododo.todododo://login-callback/';

class AuthRepository {
  AuthRepository(this._client);

  final SupabaseClient _client;

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  User? get currentUser => _client.auth.currentUser;

  Future<void> signInWithGoogle() {
    return _client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: _googleRedirectUrl,
    );
  }

  Future<void> signOut() {
    return _client.auth.signOut();
  }
}
