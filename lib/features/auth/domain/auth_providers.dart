import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/push/push_providers.dart';
import '../../../core/supabase/supabase_init.dart';
import '../../todo/domain/todo_providers.dart';
import '../data/auth_repository.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  // 로그아웃이 알림 토큰 정리를 먼저 해야 하므로 PushService를 함께 받는다.
  // 기한 알림 예약 취소와 홈 화면 위젯 캐시 비우기는 함수로 넘긴다 — 레포지토리(data)가 투두
  // domain을 import하지 않게 조립을 이 자리에서 한다(auth_repository.dart의 CancelDeviceAlarms·
  // ClearWidgetCache 주석). 이 파일이 보는 것은 todo/domain 하나뿐이고 페이로드 타입은 보지 않는다.
  return AuthRepository(
    supabase,
    ref.watch(pushServiceProvider),
    () => ref.read(dueAlarmServiceProvider).cancelAll(),
    () => ref.read(todoWidgetServiceProvider).publishLoggedOut(),
  );
});

final authStateProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges;
});
