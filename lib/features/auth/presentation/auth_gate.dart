import 'dart:async';
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/navigation/main_shell.dart';
import '../../../core/widgets/app_loader.dart';
import '../../profile/presentation/nickname_gate.dart';
import '../../todo/data/todo_widget_callback.dart';
import '../../todo/data/todo_widget_payload.dart';
import '../../todo/domain/todo_providers.dart';
import '../../todo/domain/todo_widget_tap_settler.dart';
import '../domain/auth_providers.dart';
import 'login_screen.dart';

/// 로그인 상태에 따라 화면을 분기한다. 로그인하면 별명 관문(`NicknameGate`)을 지나 탭바가 있는 본
/// 화면으로 들어간다.
///
/// 홈 화면 위젯의 **앱 쪽 배선**도 여기서 한다(design 7장·10장): 로그인 여부와 상관없이 늘 떠
/// 있는 화면이고, `main.dart`를 열지 않아도 되는 자리다. 셋 다 관문이 아니라서 어느 단계가
/// 실패해도 `debugPrint`만 남기고 로그인·본 화면은 그대로 뜬다.
class AuthGate extends ConsumerStatefulWidget {
  const AuthGate({super.key});

  @override
  ConsumerState<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<AuthGate> {
  /// 백그라운드 isolate가 "앱이 살아 있다"를 알고 쓰기를 맡기는 길(design 4.2의 W5).
  ReceivePort? _checkPort;

  @override
  void initState() {
    super.initState();
    unawaited(_registerWidgetCallback());
    _listenWidgetCheck();
  }

  /// 위젯의 체크 칸 탭을 받을 백그라운드 콜백 등록. **앱 실행마다** 다시 한다(앱을 업데이트하면
  /// 콜백 핸들이 낡는다).
  Future<void> _registerWidgetCallback() async {
    try {
      await ref
          .read(todoWidgetHostProvider)
          .registerCallback(onTodoWidgetAction);
    } catch (error) {
      debugPrint('todoWidget callback register failed: $error');
    }
  }

  /// 쓰기 요청을 받는 포트를 이름으로 등록한다.
  ///
  /// 백그라운드는 이 이름이 찾히면 **자기 Supabase 클라이언트를 만들지 않고** 이쪽에 쓰기를
  /// 맡긴다 — 백그라운드에서 토큰이 돌면 메모리에 옛 세션을 든 앱이 다음 refresh에서 조용히
  /// 로그아웃되기 때문이다(design 4.2). 프로세스가 죽으면 이 등록도 함께 사라지므로 "앱이
  /// 살아 있는가"가 그 사실 하나로 정확히 표현된다.
  void _listenWidgetCheck() {
    try {
      // 핫 리스타트로 옛 등록이 남아 있으면 같은 이름의 등록이 실패한다. 먼저 지운다.
      IsolateNameServer.removePortNameMapping(todoWidgetWritePortName);
      final port = ReceivePort();
      IsolateNameServer.registerPortWithName(
        port.sendPort,
        todoWidgetWritePortName,
      );
      _checkPort = port;
      port.listen((message) => unawaited(_onWidgetCheck(message)));
    } catch (error) {
      debugPrint('todoWidget port register failed: $error');
    }
  }

  /// 백그라운드가 맡긴 체크 하나를 앱의 살아 있는 세션으로 쓴다.
  ///
  /// 답은 셋뿐이다(`ok`/`loggedOut`/`fail`). 성공하면 `invalidate`가 목록을 다시 받아 오고 그
  /// 결과가 `MainShell`의 `ref.listen`을 지나며 위젯 캐시까지 새로 발행된다 — 그래서 여기서
  /// 캐시를 직접 쓰지 않는다. 사용자가 앱으로 돌아왔을 때 화면과 위젯이 어긋나지 않는 것도
  /// 그 `invalidate` 덕이다.
  Future<void> _onWidgetCheck(Object? message) async {
    // [id 목록, 목표 값 목록, claimedGen, 답을 보낼 포트]. 모양이 어긋나면 아무 일도 하지 않는다
    // (답할 곳도 모른다). **목표 값**을 받는 이유는 토글이 아니기 때문이다 — 낡은 그림을 누른 탭이
    // 사용자가 본 것과 반대로 쓰이지 않게 한다(design 4.6 (1)). **목록**인 이유는 묶음이 여러 줄을
    // 한 번에 맡기기 때문이고(2026-11-20 추가 범위 4), `claimedGen`은 **결말이 걷을 자국의
    // 세대**다(design 4.2).
    if (message is! List || message.length != 4) return;
    final ids = message[0];
    final dones = message[1];
    final claimedGen = message[2];
    final reply = message[3];
    if (reply is! SendPort) return;
    if (ids is! List || dones is! List || claimedGen is! int) return;
    if (ids.isEmpty || ids.length != dones.length) return;
    final targets = <TodoWidgetCheckTarget>[];
    for (var index = 0; index < ids.length; index++) {
      final id = ids[index];
      final done = dones[index];
      if (id is! String || done is! bool) return;
      targets.add(TodoWidgetCheckTarget(id: id, done: done));
    }

    // **쓰기와 발행은 정산기가 한다**(design 9장): 앱 쪽에서 그 일을 하는 자리가 둘이고
    // (이 포트, `MainShell`의 앱 열림 계기) 둘이 **같은 claim·발행 규칙**을 지나야 한다.
    // 이 메서드에 남는 일은 메시지 모양 검사와 답 보내기뿐이다.
    final outcome = await ref
        .read(todoWidgetTapSettlerProvider)
        .settle(targets, claimedGen: claimedGen);
    // **답은 셋 그대로다.** `settled`는 "결말을 발행했다"는 뜻이고 **줄마다 성공·실패가 갈렸어도
    // 그 사실이 이미 위젯에 그려져 있다**(spec S) — 그래서 백그라운드가 그 위에 실패 한 줄을
    // 덮어쓰지 않는다. `fail`은 앱이 **아무것도 하지 못했다**는 뜻이고, 그때만 백그라운드가
    // 되돌림+이유를 발행한다.
    reply.send(switch (outcome) {
      TodoWidgetSettleOutcome.settled => todoWidgetCheckOk,
      TodoWidgetSettleOutcome.loggedOut => todoWidgetCheckLoggedOut,
      TodoWidgetSettleOutcome.failed => todoWidgetCheckFailed,
    });
  }

  @override
  void dispose() {
    IsolateNameServer.removePortNameMapping(todoWidgetWritePortName);
    _checkPort?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);

    // 홈 화면 위젯 캐시를 비우는 **세 번째 방어선**(design 8장). 앞의 둘(`signOut`·`deleteAccount`)이
    // "그 자리에서 즉시"를 보장하고, 이 블록은 사용자가 로그아웃을 누르지 않은 경로를 덮는다 —
    // 세션 만료·서버에서의 무효화 때 gotrue가 세션을 지우고 `signedOut`을 쏘기 때문이다.
    // 겹쳐서 두 번 발행되는 것은 무해하다(같은 JSON이면 서비스가 건너뛴다).
    //
    // `isLoading`에서는 **아무것도 하지 않는다** — 앱이 막 떠서 세션을 복구하는 중에 캐시를
    // 비우면 홈 화면에서 지난 목록이 사라진다(그게 네트워크가 없을 때 유일하게 보여 줄 것이다).
    ref.listen(authStateProvider, (previous, next) {
      if (next.isLoading) return;
      // AsyncError는 직전 값을 들고 있다. 스트림 자체가 실패한 것은 로그아웃이 아니므로, 직전에
      // 세션이 있었으면 그대로 둔다(세션이 없었던 경우만 아래로 떨어진다).
      if (next.value?.session != null) return;
      unawaited(ref.read(todoWidgetServiceProvider).publishLoggedOut());
    });

    return authState.when(
      data: (state) {
        final session = state.session;
        if (session == null) return const LoginScreen();
        // 본 화면 앞에 별명 관문(nickname design 7.1). 계정마다 키를 나눠, 로그아웃 뒤 다른 계정이
        // 들어오면 관문 상태(통과 래치 포함)를 새로 시작한다.
        final userId = session.user.id;
        return NicknameGate(
          key: ValueKey(userId),
          userId: userId,
          child: const MainShell(),
        );
      },
      loading: () => const Scaffold(body: Center(child: AppLoader.medium())),
      error: (error, stackTrace) {
        debugPrint('authStateProvider error: $error');
        return const LoginScreen();
      },
    );
  }
}
