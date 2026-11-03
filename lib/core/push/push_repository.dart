import 'package:supabase_flutter/supabase_flutter.dart';

/// 기기 알림 토큰 등록·해제. 두 RPC 모두 로그인 세션이 있어야 통한다.
class PushRepository {
  PushRepository(this._client);

  final SupabaseClient _client;

  /// 멱등이다(`on conflict (token)`). 앱이 열릴 때마다 불러도 행이 늘지 않는다.
  Future<void> register(String token) {
    return _client.rpc('register_push_token', params: {'p_token': token});
  }

  /// 내 행만 지워진다. 로그아웃 **직전**에 불러야 한다 — 세션이 끊기면 지울 수 없다.
  Future<void> unregister(String token) {
    return _client.rpc('unregister_push_token', params: {'p_token': token});
  }
}
