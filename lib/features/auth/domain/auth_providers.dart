import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/push/push_providers.dart';
import '../../../core/supabase/supabase_init.dart';
import '../../todo/domain/todo_providers.dart';
import '../data/auth_repository.dart';
import 'login_method.dart';

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

/// 인증 상태. **자동 재시도를 끈다**(kakao-login design 흐름 2).
///
/// gotrue의 `onAuthStateChange`는 지난 이벤트·오류를 **전부 다시 내주는** 스트림(ReplaySubject)이다.
/// Riverpod 3의 기본 재시도는 오류가 나면 provider를 다시 만들어 스트림을 새로 듣는데, 그러면 같은
/// 오류가 또 재생되어 재시도만 10번 반복되고, 그동안 상태가 "재시도 중 로딩"이라 `AuthGate`가 로딩
/// 화면과 로그인 화면을 번갈아 그린다. 돌아온 로그인의 오류(카카오 취소·코드 교환 실패)는 그대로
/// `AsyncError`가 되어야 로그인 화면이 그 자리에 남아 취소인지 오류인지 가를 수 있다. 오류 뒤에도 스트림
/// 구독은 이어지므로 다음 로그인 이벤트는 그대로 들어온다.
final authStateProvider = StreamProvider<AuthState>(
  (ref) => ref.watch(authRepositoryProvider).authStateChanges,
  retry: (retryCount, error) => null,
);

/// 이 계정의 로그인 수단(kakao-login design 흐름 3). 프로필의 "○○ 계정으로 로그인했어요" 한 줄이 읽는다.
///
/// **세션에서 읽는다** — 서버 왕복도 새 테이블·컬럼·RPC도 없어 다른 사용자에게 새는 경로가 원천적으로
/// 없다. `authStateProvider`를 거치는 이유: 프로필 화면은 `MainShell`에 늘 함께 그려지는데, 인증
/// 레포지토리를 만들 수 없는 상황(Supabase 미초기화 등)에서도 이 값은 null이 될 뿐 화면이 깨지지 않는다
/// (`StreamProvider`가 실패를 `AsyncValue` 안에 담는다). null이면 화면은 그 줄을 그리지 않는다.
final myLoginMethodProvider = Provider.autoDispose<LoginMethod?>((ref) {
  final user = ref.watch(authStateProvider).value?.session?.user;
  return loginMethodFrom(user?.appMetadata);
});
