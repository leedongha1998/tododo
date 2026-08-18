import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_env.dart';

Future<void> initSupabase() async {
  await Supabase.initialize(url: SupabaseEnv.url, publishableKey: SupabaseEnv.anonKey);
}

SupabaseClient get supabase => Supabase.instance.client;
