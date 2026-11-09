import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/push/push_providers.dart';
import '../../../core/supabase/supabase_init.dart';
import '../../todo/domain/todo_providers.dart';
import '../data/auth_repository.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  // 로그아웃이 알림 토큰 정리를 먼저 해야 하므로 PushService를 함께 받는다.
  // 기한 알림 예약 취소는 함수로 넘긴다 — 레포지토리(data)가 투두 domain을 import하지 않게
  // 조립을 이 자리에서 한다(auth_repository.dart의 CancelDeviceAlarms 주석).
  return AuthRepository(
    supabase,
    ref.watch(pushServiceProvider),
    () => ref.read(dueAlarmServiceProvider).cancelAll(),
  );
});

final authStateProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges;
});
