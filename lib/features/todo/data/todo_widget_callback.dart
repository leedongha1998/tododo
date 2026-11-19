// 홈 화면 위젯의 **체크 칸 탭**을 받는 백그라운드 진입점(design 4장).
//
// 이 파일은 앱이 꺼져 있어도 돌 수 있는 자리라 계층의 바깥에 있다 — 백그라운드 isolate의 `main`
// 같은 것이고, 그래서 `data/`에 있으면서도 같은 feature의 `domain`(TodoWidgetService)을 조립해
// 쓴다(앱에서는 provider가 하는 일이다). `main.dart`에 두지 않는 것은 design 10장의 결정이다.
//
// 가장 중요한 결정은 **쓰기를 누가 하는가**다(design 4.2의 W5). 백그라운드에서 무조건
// `Supabase.initialize`를 하면 토큰이 돌고(refresh), 메모리에 옛 세션을 든 앱이 다음 refresh에서
// `refresh_token_already_used`를 받아 **조용히 로그아웃된다**. 그래서 먼저 "앱의 main isolate가
// 살아 있는가"를 보고(`IsolateNameServer`), 살아 있으면 그쪽에 쓰기를 맡기고 죽어 있을 때만
// 직접 쓴다 — 프로세스가 죽었으면 회전으로 깨뜨릴 상대가 애초에 없다.
//
// **거짓 성공을 만들지 않는다**: 성공 발행은 서버 쓰기가 끝난 뒤에만 일어나고, 어떤 예외든
// `checkFailed`로 끝나 위젯 안 한 줄로 말한다(spec "P0. 쓰기 동작").

import 'dart:async';
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../../core/supabase/supabase_init.dart';
import '../domain/todo_widget_service.dart';
import 'todo_repository.dart';
import 'todo_widget_host.dart';
import 'todo_widget_payload.dart';

/// 앱의 main isolate가 등록하는 포트 이름(`AuthGate`). 백그라운드는 이 이름이 **찾히는지**로
/// 앱 프로세스의 생존을 안다 — 프로세스가 죽으면 등록도 함께 사라지므로 따로 정리할 것이 없다.
const todoWidgetWritePortName = 'todododo/todo_widget_write';

/// 포트로 오가는 답. `SendPort`에는 원시 값만 실을 수 있어 문자열로 둔다.
const todoWidgetCheckOk = 'ok';
const todoWidgetCheckFailed = 'fail';
const todoWidgetCheckLoggedOut = 'loggedOut';

/// 앱의 답을 기다리는 상한. 넘기면 **직접 쓰지 않고 실패로 끝낸다** — 앱 프로세스가 얼어 있거나
/// 바쁜 경우이고, 그때 클라이언트를 하나 더 만드는 것이 바로 W5가 피하려는 상황이다.
/// 안전(design 원칙 5)을 UX보다 앞에 둔다.
///
/// **2026-11-19에 8초에서 6초로 조였다**(design 4.7 (7)). spec이 8초를 "어떤 경우에도 그 안에 세
/// 모양 중 하나로 끝난다"는 **사용자에게 보이는 약속**으로 올렸고, 네이티브의 쓸어내기(탭+7초)와
/// Dart의 포기 시각이 그 안에서 만나야 하기 때문이다 — 둘이 **같은 시각에 같은 결론**(실패)에
/// 닿게 하려는 것이다. 대가는 "앱이 6~8초 동안 바빠서 답을 못 하는 경우가 실패로 끝난다"인데,
/// 그 경우는 어차피 사용자에게 끝나지 않는 탭으로 보인다.
///
/// **직접 쓰기(`_writeHere`)의 결말까지도 같은 상한을 쓴다.** 보정 재조회는 결말 뒤의 일이라
/// 이 상한 밖이다.
const todoWidgetHandOffTimeout = Duration(seconds: 6);

/// 위젯의 체크 칸을 눌렀을 때 `home_widget`이 백그라운드 engine에서 실행한다.
///
/// 등록은 `AuthGate`가 앱 실행마다 다시 한다(앱을 업데이트하면 콜백 핸들이 낡는다).
@pragma('vm:entry-point')
Future<void> onTodoWidgetAction(Uri? uri) async {
  final action = todoWidgetActionOf(uri);
  final todoId = action.todoId;
  // uuid 모양이 아니거나 체크가 아닌 Uri면 아무 일도 하지 않는다.
  if (todoId == null) return;

  const host = TodoWidgetHost();
  final service = TodoWidgetService(host);
  final now = DateTime.now();

  TodoWidgetPayload? cached;
  try {
    cached = await host.read();
  } catch (error) {
    // 되읽기 실패는 막지 않는다(중복 판단만 못 하게 된다). 서버 쓰기는 멱등이다.
    debugPrint('todoWidget read failed: $error');
  }

  final port = IsolateNameServer.lookupPortByName(todoWidgetWritePortName);
  final decision = todoWidgetCheckDecisionOf(
    action: action,
    cached: cached,
    appAlive: port != null,
    now: now,
  );
  if (decision == TodoWidgetCheckDecision.ignore) return;

  // 그 줄을 `쓰는 중`으로 바꿔 즉시 다시 그린다. 백그라운드 engine이 뜨는 데 1초 안쪽이 걸릴 수
  // 있어 탭과 표시 사이에 짧은 공백이 있다 — 위젯에 진행 표시를 더 그릴 자리가 없어 받아들인다.
  // 목록이 없는 캐시(로그아웃·안내 화면)에는 바꿀 줄이 없으므로 건너뛴다.
  if (cached != null && cached.hasItems) {
    await service.publish(TodoWidgetPayload.pending(cached, todoId, now: now));
  }

  try {
    if (port != null && decision == TodoWidgetCheckDecision.handOff) {
      await _handOff(port, action, service, cached, now);
    } else {
      // 결말까지에만 상한을 건다. 뒤따르는 보정 재조회는 사용자가 이미 결말을 본 뒤의 일이라
      // 이 상한 밖이고, 실패해도 `checkFailed`로 새지 않는다(아래 `_refreshAfterCheck`).
      final checked = await _writeHere(
        action,
        service,
        cached,
        now,
      ).timeout(todoWidgetHandOffTimeout);
      if (checked != null) {
        await _refreshAfterCheck(checked, service, action.todoId!);
      }
    }
  } catch (error) {
    // 네트워크가 없으면 여기로 온다 → 위젯에 `체크하지 못했어요`가 뜨고 그 할 일은 목록에
    // 그대로 있다(지운 적이 없으므로 저절로 되살아난다).
    debugPrint('todoWidget check failed: $error');
    await service.publish(TodoWidgetPayload.checkFailed(cached, now: now));
  }
}

/// 앱의 main isolate에 쓰기를 맡긴다. 답만 받고 끝낸다 — **Supabase 클라이언트를 만들지 않는다.**
///
/// 성공이면 발행도 앱이 한다(`setDone` → `invalidate(todosProvider)` → `MainShell`의 `ref.listen`).
/// 그래서 이쪽은 아무것도 더 쓰지 않는다.
Future<void> _handOff(
  SendPort port,
  TodoWidgetAction action,
  TodoWidgetService service,
  TodoWidgetPayload? cached,
  DateTime now,
) async {
  final reply = ReceivePort();
  try {
    // 메시지는 **셋**이다(2026-11-18 추가 범위 2): 할 일 id, **목표 값**, 답을 보낼 포트.
    // 받는 쪽(`AuthGate`)이 길이와 타입 셋을 검사하고 어긋나면 아무 일도 하지 않는다.
    port.send([action.todoId, action.done, reply.sendPort]);
    final answer = await reply.first.timeout(todoWidgetHandOffTimeout);
    if (answer == todoWidgetCheckOk) return;
    if (answer == todoWidgetCheckLoggedOut) {
      // 앱이 떠 있지만 로그인 화면이다. 이전 사용자의 목록을 홈 화면에 남기지 않는다.
      await service.publishLoggedOut(now: now);
      return;
    }
    await service.publish(TodoWidgetPayload.checkFailed(cached, now: now));
  } on TimeoutException {
    debugPrint('todoWidget check hand-off timed out');
    await service.publish(TodoWidgetPayload.checkFailed(cached, now: now));
  } finally {
    reply.close();
  }
}

/// 결말을 발행한 뒤 **보정 재조회**에 필요한 것만 들고 나온다. null이면 보정할 것이 없다
/// (로그아웃이었거나, 지름길이 성립하지 않아 이미 서버에서 받은 목록으로 발행했다).
class _CheckedSession {
  const _CheckedSession(this.repository, this.userId);

  final TodoRepository repository;
  final String userId;
}

/// 앱 프로세스가 죽어 있을 때. 이 isolate에 다른 클라이언트가 없으므로 세션 복구·갱신이 안전하다.
Future<_CheckedSession?> _writeHere(
  TodoWidgetAction action,
  TodoWidgetService service,
  TodoWidgetPayload? cached,
  DateTime now,
) async {
  final todoId = action.todoId!;
  // 이미 초기화돼 있으면(같은 백그라운드 engine이 두 번 깨어난 경우) 그대로 지나간다.
  await initSupabase();
  final session = supabase.auth.currentSession;
  if (session == null) {
    await service.publishLoggedOut(now: now);
    return null;
  }
  // `Supabase.initialize`는 저장된 세션을 메모리에 올리기만 하고 **갱신을 기다리지 않는다**
  // (recoverSession이 unawaited다). 그래서 액세스 토큰이 만료된 상태 — 하루에 한 번 앱을 여는
  // 사용자가 바로 이 경우다 — 로 쓰면 거의 항상 실패한다. gotrue가 같은 refresh token의 갱신을
  // 하나로 합치므로(`_pendingRefreshes`) 여기서 기다려도 토큰이 두 번 돌지 않는다.
  if (session.isExpired) await supabase.auth.refreshSession();

  final userId = supabase.auth.currentUser?.id;
  if (userId == null) {
    await service.publishLoggedOut(now: now);
    return null;
  }

  final repository = TodoRepository(supabase);
  // **목표 값**을 그대로 쓴다(뒤집지 않는다 — 낡은 그림을 누른 탭이 사용자가 본 것과 반대로
  // 쓰이지 않게 하는 장치다. design 4.6 (1)). 되돌리기도 이 한 줄을 지난다.
  await repository.setDone(todoId, action.done);

  // **결말을 여기서 끝낸다**(design 4.7 (2)의 경로 B). 여기에는 고칠 목록이 없고 캐시만 있으므로
  // 그 캐시를 **그 체크만큼만** 고쳐 발행한다 — 목록 재조회(왕복 2)가 빠진다. 서버 쓰기가 끝난
  // 뒤의 일이라 거짓 성공이 아니다(낙관 반영과 다른 자리다).
  final checked = TodoWidgetPayload.applyCheck(
    cached,
    todoId: todoId,
    done: action.done,
  );
  if (checked == null) {
    // 지름길이 성립하지 않으면(캐시 없음·줄 없는 안내 화면·목록에 없는 id) 느린 길이 남는다.
    // 이 isolate는 id를 직접 들고 있어 `markJustChecked`를 쓰지 않는다(그 기억은 앱 쪽 서비스의
    // 것이고, 여기서 적어 두면 같은 isolate 안에서만 유효한 기억이 되어 번거로울 뿐이다).
    await _publishFromServer(repository, service, userId, todoId);
    return null;
  }
  await service.publish(checked);
  return _CheckedSession(repository, userId);
}

/// 결말을 보여 준 **뒤** 서버 값으로 맞추는 보정 발행. 기한 키·다른 기기의 변경·개수를 되돌린다.
///
/// **자기 `try`를 갖는다**(design 4.7 (2)). 지금까지는 쓰기와 재조회가 한 `try` 안이라 **쓰기가
/// 성공한 뒤 재조회가 실패하면 `체크하지 못했어요`가 떴다**(= 서버에는 반영됐는데 실패라고
/// 말했다). 결말을 재조회에서 떼어 내면서 그 거짓 실패도 함께 사라진다 — 여기의 실패는 발행
/// 실패와 같은 등급이라 `debugPrint`만 남긴다(design 원칙 4).
Future<void> _refreshAfterCheck(
  _CheckedSession checked,
  TodoWidgetService service,
  String todoId,
) async {
  try {
    await _publishFromServer(
      checked.repository,
      service,
      checked.userId,
      todoId,
    );
  } catch (error) {
    debugPrint('todoWidget refresh after check failed: $error');
  }
}

/// 목록을 서버에서 받아 캐시를 통째로 새로 만든다.
Future<void> _publishFromServer(
  TodoRepository repository,
  TodoWidgetService service,
  String userId,
  String todoId,
) async {
  final todos = await repository.fetchTodos(userId);
  await service.publish(
    TodoWidgetPayload.fromTodos(
      todos,
      now: DateTime.now(),
      justCheckedId: todoId,
    ),
  );
}
