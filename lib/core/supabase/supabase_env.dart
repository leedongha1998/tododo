/// Supabase 접속 정보는 코드/커밋에 넣지 않고 --dart-define(-from-file)로 주입한다.
/// 예: flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
class SupabaseEnv {
  SupabaseEnv._();

  static const url = String.fromEnvironment('SUPABASE_URL');
  static const anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static bool get isConfigured => url.isNotEmpty && anonKey.isNotEmpty;
}
