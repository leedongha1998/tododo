import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_init.dart';
import '../data/battle_repository.dart';

final battleRepositoryProvider = Provider<BattleRepository>((ref) {
  return BattleRepository(supabase);
});
