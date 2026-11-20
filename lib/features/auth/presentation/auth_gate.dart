import 'dart:async';
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/navigation/main_shell.dart';
import '../../../core/widgets/app_loader.dart';
import '../../todo/data/todo_repository.dart';
import '../../todo/data/todo_widget_callback.dart';
import '../../todo/data/todo_widget_payload.dart';
import '../../todo/domain/todo_providers.dart';
import '../domain/auth_providers.dart';
import 'login_screen.dart';

/// 로그인 상태에 따라 화면을 분기한다. 로그인하면 탭바가 있는 본 화면으로 들어간다.
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

    try {
      final userId = ref.read(authRepositoryProvider).currentUser?.id;
      if (userId == null) {
        // 앱은 떠 있지만 로그인 화면이다. 백그라운드가 캐시를 로그아웃 상태로 덮는다.
        reply.send(todoWidgetCheckLoggedOut);
        return;
      }
      // **`setDone` 앞에서** 적어 둔다. 그 뒤 `invalidate`가 일으키는 발행이 "방금 누른 줄들"을
      // 알게 하는 유일한 길이다(이 자리만 id를 안다. design 7.2 (1)).
      final widgetService = ref.read(todoWidgetServiceProvider);
      widgetService.markJustChecked([
        for (final target in targets) target.id,
      ]);
      final repository = ref.read(todoRepositoryProvider);
      // **줄마다 자기 `try`**를 갖는다(design 10.2): 한 줄이 실패해도 나머지는 그대로 쓰이고,
      // 결말이 줄마다 다르게 그려진다(spec S). `Future.wait`의 `eagerError`를 쓰지 않는 이유가
      // 그것이다.
      final results = await Future.wait([
        for (final target in targets) _writeOne(repository, target),
      ]);
      // **결말을 여기서 끝낸다**(design 4.7 (2)의 경로 A). 서버 쓰기가 끝났으므로 목록을 다시
      // 받지 않고 앱이 이미 든 목록에서 그 한 줄만 바꿔 발행한다 — 체크 한 번의 왕복이 둘에서
      // 하나로 준다. 아래 `invalidate`가 일으키는 발행은 이제 결말이 아니라 **보정**이다.
      //
      // 목록을 아직 한 번도 못 받아왔으면 **건너뛴다**(그때는 지금까지의 경로 그대로 `invalidate`가
      // 발행한다). `AsyncError`도 직전 값을 들고 있으므로 `value`를 그대로 쓴다 — 조회가 실패한
      // 뒤의 그 목록은 위젯이 지금 보여 주고 있는 것과 같은 나이다(riverpod 3에 `valueOrNull`은
      // 없다).
      final todos = ref.read(todosProvider).value;
      if (todos != null) {
        await widgetService.publishSettled(
          todos,
          results: results,
          claimedGen: claimedGen,
          now: DateTime.now(),
        );
      } else {
        // 발행할 재료가 없어도 **세대는 올린다** — 올리지 않으면 쓰기가 끝난 줄의 낙관 그림이
        // 되돌림 시각까지 남는다(design 4.2).
        widgetService.noteSettledGen(claimedGen);
      }
      ref.invalidate(todosProvider);
      // **한 줄이라도 실패했으면 실패로 답한다** — 백그라운드가 그 답으로 위젯 안 한 줄을 띄운다.
      // 여기서 이미 발행한 결말에도 그 한 줄이 들어 있으므로(spec S) 두 자리가 같은 말을 한다.
      reply.send(
        results.every((result) => result.ok)
            ? todoWidgetCheckOk
            : todoWidgetCheckFailed,
      );
    } catch (error) {
      // 삼키지 않는다 — 백그라운드가 이 답을 받아 위젯 안 한 줄로 말한다(spec).
      debugPrint('todoWidget check (app) failed: $error');
      reply.send(todoWidgetCheckFailed);
    }
  }

  /// 한 줄을 쓰고 **결과로 돌려준다**(던지지 않는다 — 한 줄의 실패가 묶음 전체를 실패로 만들지
  /// 않게 한다. design 10.2).
  Future<TodoWidgetCheckResult> _writeOne(
    TodoRepository repository,
    TodoWidgetCheckTarget target,
  ) async {
    try {
      await repository.setDone(target.id, target.done);
      return TodoWidgetCheckResult(
        id: target.id,
        done: target.done,
        ok: true,
      );
    } catch (error) {
      debugPrint('todoWidget check (app) failed: $error');
      return TodoWidgetCheckResult(
        id: target.id,
        done: target.done,
        ok: false,
      );
    }
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
        return state.session == null ? const LoginScreen() : const MainShell();
      },
      loading: () => const Scaffold(body: Center(child: AppLoader.medium())),
      error: (error, stackTrace) {
        debugPrint('authStateProvider error: $error');
        return const LoginScreen();
      },
    );
  }
}
