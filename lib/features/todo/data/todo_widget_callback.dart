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
// 되돌림+실패 한 줄로 끝나 위젯 안에서 말한다(spec "P0. 쓰기 동작").
//
// **2026-11-19 추기.** spec이 그 조항을 뒤집어 **낙관적 반영**을 허용했지만(추가 범위 3의 L),
// 뒤집힌 자리는 **네이티브의 그리기**이고 이 파일은 그대로다 — 여기서 성공을 발행하는 것은
// 여전히 **서버 쓰기가 끝난 뒤**뿐이다.
//
// **2026-11-20(추가 범위 4): 이 일꾼이 "탭 하나"에서 "묶음 하나"를 맡게 됐다**(design 2·3·4장).
// 깨어나면 먼저 **입력이 멎기를 기다리고**(`leaveAtMs`까지 — 기다림은 네트워크도 권한도 필요
// 없는 그냥 시간이고 engine 기동이 그 1초와 겹친다), 그때의 자국으로 **묶음을 확정(claim)**해
// 여러 줄을 **병렬로** 쓰고 **결말을 한 번** 발행한다. 발행 뒤 자국을 한 번 더 읽어 claim보다
// 새 세대가 남아 있으면 **한 라운드 더** 돈다(design 4.5 — 가장 좁은 구멍을 닫는 장치다).

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
///
/// **[todoWidgetCheckOk]는 "결말을 발행했다"는 뜻이다**(2026-11-20): 줄마다 성공·실패가 갈렸어도
/// 그 사실이 이미 위젯에 그려져 있으므로(spec S) 백그라운드가 그 위에 실패 한 줄을 덮어쓰지
/// 않는다. [todoWidgetCheckFailed]는 앱이 **아무것도 하지 못했다**는 뜻이고, 그때만 이쪽이
/// 되돌림+이유를 발행한다.
const todoWidgetCheckOk = 'ok';
const todoWidgetCheckFailed = 'fail';
const todoWidgetCheckLoggedOut = 'loggedOut';

/// 앱의 답을 기다리는 상한. 넘기면 **직접 쓰지 않고 실패로 끝낸다** — 앱 프로세스가 얼어 있거나
/// 바쁜 경우이고, 그때 클라이언트를 하나 더 만드는 것이 바로 W5가 피하려는 상황이다.
/// 안전(design 원칙 5)을 UX보다 앞에 둔다.
///
/// **2026-11-19에 8초에서 6초로, 2026-11-20에 다시 5초로 조였다**(design 7장). spec이 8초를
/// "어떤 경우에도 그 안에 세 모양 중 하나로 끝난다"는 **사용자에게 보이는 약속**으로 올렸고,
/// 이번에 앞에 **대기 1초**가 붙었으므로 그만큼 줄여야 그 약속이 지켜진다. 기준점도 "탭"이 아니라
/// **"묶음이 떠난 순간"**이다. 네이티브의 되돌림 시각(`dueAtMs` = 떠난 시각 + 5초 + 1초)과 같은
/// 상수에서 나온다.
///
/// **직접 쓰기(`_writeHere`)의 결말까지도 같은 상한을 쓴다.** 보정 재조회는 결말 뒤의 일이라
/// 이 상한 밖이다.
const todoWidgetHandOffTimeout = Duration(
  milliseconds: todoWidgetWriteWindowMs,
);

/// 한 일꾼이 도는 **라운드의 상한**(design 4.5). 발행 뒤에 남은 자국을 집어 한 번 더 도는 장치의
/// 끝을 못 박는 값이다 — 그 뒤는 쓸어내기·앱 열림 계기에 맡긴다(일꾼을 무한히 붙잡지 않는다).
const todoWidgetSettleRounds = 3;

/// 위젯의 체크 칸을 눌렀을 때 `home_widget`이 백그라운드 engine에서 실행한다.
///
/// 등록은 `AuthGate`가 앱 실행마다 다시 한다(앱을 업데이트하면 콜백 핸들이 낡는다).
@pragma('vm:entry-point')
Future<void> onTodoWidgetAction(Uri? uri) async {
  final action = todoWidgetActionOf(uri);
  // uuid 모양이 아니거나 체크가 아닌 Uri면 아무 일도 하지 않는다.
  if (action.todoId == null) return;

  const host = TodoWidgetHost();
  final service = TodoWidgetService(host);
  // **기다림의 절대 상한.** 묶음 상한(첫 탭+5초)과 멎음(1초)을 합친 것이고, 이 시각을 넘겨
  // 기다리는 경로는 없다 — "어느 계기도 오지 않는 경로가 있어서는 안 된다"(spec O)를 루프 밖에서
  // 한 번 더 못 박는다. 기기 시간만 재므로 외부 신호가 필요 없다.
  final waitUntilMs =
      DateTime.now().millisecondsSinceEpoch +
      todoWidgetTapBatchCapMs +
      todoWidgetTapQuietMs;

  var claimedGen = 0;
  for (var round = 1; round <= todoWidgetSettleRounds; round++) {
    final marks = await _readMarks(host);
    if (marks == null) {
      // **대비 경로**(design 4.4의 13번): payload가 없어 네이티브가 자국을 쓰지 못한 경우다
      // (설치 직후·판 번호 모름). 그 Uri 한 줄만 즉시 쓴다 — 기다릴 근거가 캐시에 없다.
      if (round == 1) await _settleFallback(host, service, action);
      return;
    }
    // 남은 자국이 없으면 끝이다(이 비교가 "한 라운드 더"의 종료 조건이다 — design 4.5).
    if (marks.gen <= claimedGen) return;

    final quiet = await _waitForQuiet(host, marks, waitUntilMs);
    final cached = await _readCache(host, service);
    final batch = todoWidgetBatchOf(
      marks: quiet,
      payload: cached,
      now: DateTime.now(),
    );
    if (batch == null || batch.claimedGen <= claimedGen) return;
    // **다른 일꾼이 이미 정산했으면 조용히 끝낸다**(design 4.3의 3번). 원자적 보장이 아니라
    // 왕복을 아끼는 가드다 — 정확성은 멱등한 쓰기와 같은 지문의 발행이 든다.
    if (batch.claimedGen <= (cached?.settledGen ?? 0)) return;
    claimedGen = batch.claimedGen;

    if (batch.isEmpty) {
      // **상쇄**(spec P): 보낼 것이 없다 → 서버 호출 0번 · 발행 0번(그림은 이미 맞다). 세대만
      // 들고 다음 라운드를 본다 — 실패 한 줄도 띄우지 않는다(실패가 아니다).
      service.noteSettledGen(claimedGen);
      continue;
    }
    await _settleBatch(host, service, cached, batch);
  }
}

/// **입력이 멎기를 기다린다**(design 3장의 (나)). `leaveAtMs`까지 기다린 뒤 자국을 다시 읽어
/// **마지막 탭이 움직였으면 다시 계산해 또 기다린다.**
///
/// 끝나는 것이 구조로 보장된다: `leaveAtMs`는 `min(마지막 탭+1초, 첫 탭+5초)`이고, 그 위에
/// [waitUntilMs]라는 절대 상한이 걸려 있다. `writing` 자국이 섞인 묶음은 `leaveAtMs`가 이미
/// 지나 있어 **한 줄도 기다리지 않는다**(spec U 조건 ②의 조임).
Future<TodoWidgetTapMarks> _waitForQuiet(
  TodoWidgetHost host,
  TodoWidgetTapMarks marks,
  int waitUntilMs,
) async {
  var current = marks;
  while (true) {
    final until = current.leaveAtMs < waitUntilMs
        ? current.leaveAtMs
        : waitUntilMs;
    final waitMs = until - DateTime.now().millisecondsSinceEpoch;
    if (waitMs <= 0) return current;
    await Future<void>.delayed(Duration(milliseconds: waitMs));
    final next = await _readMarks(host);
    if (next == null) return current;
    // 기다리는 사이에 탭이 더 들어왔으면 그 묶음의 새 시각으로 다시 기다린다.
    if (next.lastAtMs <= current.lastAtMs) return next;
    current = next;
  }
}

/// 묶음 하나를 쓰고 **결말을 한 번** 발행한다.
Future<void> _settleBatch(
  TodoWidgetHost host,
  TodoWidgetService service,
  TodoWidgetPayload? cached,
  TodoWidgetBatch batch,
) async {
  final port = IsolateNameServer.lookupPortByName(todoWidgetWritePortName);
  // **`쓰는 중` 발행이 없다**(2026-11-19, design 4.7 (1)의 7). 그 그림은 **네이티브가 탭 순간에
  // 이미 그렸다** — 여기까지 오는 데만 engine 기동으로 1초 안쪽이 걸리므로, 이 자리에서 그리면
  // 사용자가 기다린 뒤에야 "눌렸다"를 보게 된다. 그래서 이 isolate가 하는 발행은 **결말 하나**다.
  // 덤으로 조건 ①("되돌림과 이유가 같은 화면에")이 자동으로 성립한다 — 중간 상태가 생길 자리가
  // 없기 때문이다.
  try {
    if (port != null) {
      await _handOff(port, batch, service, cached);
      return;
    }
    // 결말까지에만 상한을 건다. 뒤따르는 보정 재조회는 사용자가 이미 결말을 본 뒤의 일이라
    // 이 상한 밖이고, 실패해도 되돌림으로 새지 않는다(아래 `_refreshAfterCheck`).
    final checked = await _writeHere(
      batch,
      service,
      cached,
    ).timeout(todoWidgetHandOffTimeout);
    if (checked != null) await _refreshAfterCheck(checked, service);
  } catch (error) {
    // 네트워크가 없으면 여기로 온다 → 누른 줄이 되돌아가고 위젯에 `체크하지 못했어요`가 뜬다
    // (목록을 지운 적이 없으므로 그 할 일은 저절로 되살아난다).
    debugPrint('todoWidget check failed: $error');
    await _publishFailed(service, cached, batch);
  }
}

/// 자국을 읽지 못한 경우의 **대비 경로**: 그 Uri 한 줄만 즉시 쓴다(design 2장의 7번).
///
/// 이 갈래에만 [todoWidgetCheckDecisionOf]가 남아 있다 — 묶음 경로에서는 그 두 조건(목록에 없는
/// id·이미 목표 값)을 [todoWidgetBatchOf]가 claim에서 끝낸다.
Future<void> _settleFallback(
  TodoWidgetHost host,
  TodoWidgetService service,
  TodoWidgetAction action,
) async {
  final cached = await _readCache(host, service);
  final port = IsolateNameServer.lookupPortByName(todoWidgetWritePortName);
  // **중복 탭은 여기서 가르지 않는다**(2026-11-20): 네이티브가 탭 자국을 `commit()`한 뒤에 이
  // isolate를 깨우므로 여기서 읽는 자국은 언제나 **이번 탭의 것**이다. 그래서 이 함수는 기준
  // 시각조차 받지 않는다(design 4.7 (6)의 정정).
  final decision = todoWidgetCheckDecisionOf(
    action: action,
    cached: cached,
    appAlive: port != null,
  );
  if (decision == TodoWidgetCheckDecision.ignore) return;

  await _settleBatch(
    host,
    service,
    cached,
    TodoWidgetBatch(
      // 걷을 자국이 없으므로 세대를 올리지 않는다(캐시의 값을 그대로 쓴다).
      claimedGen: cached?.settledGen ?? 0,
      leaveAtMs: DateTime.now().millisecondsSinceEpoch,
      writes: [
        TodoWidgetCheckTarget(id: action.todoId!, done: action.done),
      ],
    ),
  );
}

/// 앱의 main isolate에 쓰기를 맡긴다. 답만 받고 끝낸다 — **Supabase 클라이언트를 만들지 않는다.**
///
/// 성공이면 발행도 앱이 한다(정산기 → `publishSettled` → `invalidate(todosProvider)`).
/// 그래서 이쪽은 아무것도 더 쓰지 않는다.
Future<void> _handOff(
  SendPort port,
  TodoWidgetBatch batch,
  TodoWidgetService service,
  TodoWidgetPayload? cached,
) async {
  final reply = ReceivePort();
  try {
    // 메시지는 **넷**이다(2026-11-20 추가 범위 4): 할 일 id **목록**, **목표 값** 목록,
    // **claimedGen**, 답을 보낼 포트. 받는 쪽(`AuthGate`)이 길이와 타입을 검사하고 어긋나면
    // 아무 일도 하지 않는다. `claimedGen`을 함께 보내는 이유는 **발행하는 쪽이 걷을 자국의
    // 세대를 알아야** 하기 때문이다(design 4.2).
    port.send([
      [for (final write in batch.writes) write.id],
      [for (final write in batch.writes) write.done],
      batch.claimedGen,
      reply.sendPort,
    ]);
    final answer = await reply.first.timeout(todoWidgetHandOffTimeout);
    if (answer == todoWidgetCheckOk) return;
    if (answer == todoWidgetCheckLoggedOut) {
      // 앱이 떠 있지만 로그인 화면이다. 이전 사용자의 목록을 홈 화면에 남기지 않는다.
      await service.publishLoggedOut(now: DateTime.now());
      return;
    }
    await _publishFailed(service, cached, batch);
  } on TimeoutException {
    debugPrint('todoWidget check hand-off timed out');
    await _publishFailed(service, cached, batch);
  } finally {
    reply.close();
  }
}

/// 결말을 발행한 뒤 **보정 재조회**에 필요한 것만 들고 나온다. null이면 보정할 것이 없다
/// (로그아웃이었거나, 한 줄도 쓰이지 않았거나, 이미 서버에서 받은 목록으로 발행했다).
class _CheckedSession {
  const _CheckedSession(this.repository, this.userId, this.frontIds);

  final TodoRepository repository;
  final String userId;

  /// 보정 발행에서도 **보이는 자리를 먼저 받을** 줄들(실패한 줄 → 성공한 줄 순서).
  final List<String> frontIds;
}

/// 앱 프로세스가 죽어 있을 때. 이 isolate에 다른 클라이언트가 없으므로 세션 복구·갱신이 안전하다.
Future<_CheckedSession?> _writeHere(
  TodoWidgetBatch batch,
  TodoWidgetService service,
  TodoWidgetPayload? cached,
) async {
  // 이미 초기화돼 있으면(같은 백그라운드 engine이 두 번 깨어난 경우) 그대로 지나간다.
  await initSupabase();
  final session = supabase.auth.currentSession;
  if (session == null) {
    await service.publishLoggedOut(now: DateTime.now());
    return null;
  }
  // `Supabase.initialize`는 저장된 세션을 메모리에 올리기만 하고 **갱신을 기다리지 않는다**
  // (recoverSession이 unawaited다). 그래서 액세스 토큰이 만료된 상태 — 하루에 한 번 앱을 여는
  // 사용자가 바로 이 경우다 — 로 쓰면 거의 항상 실패한다. gotrue가 같은 refresh token의 갱신을
  // 하나로 합치므로(`_pendingRefreshes`) 여기서 기다려도 토큰이 두 번 돌지 않는다.
  if (session.isExpired) await supabase.auth.refreshSession();

  final userId = supabase.auth.currentUser?.id;
  if (userId == null) {
    await service.publishLoggedOut(now: DateTime.now());
    return null;
  }

  final repository = TodoRepository(supabase);
  // **목표 값**을 그대로 쓴다(뒤집지 않는다 — 낡은 그림을 누른 탭이 사용자가 본 것과 반대로
  // 쓰이지 않게 하는 장치다. design 4.6 (1)). 되돌리기도 이 길을 지난다.
  //
  // **병렬이고 줄마다 자기 `try`다**(design 10.2): 순차로 돌리면 N줄 × 왕복이라 5초 창을 넘길 수
  // 있고, 한 줄의 실패가 나머지를 막으면 "하나는 됐고 하나는 안 됐다"를 그릴 수 없다(spec S).
  final results = await Future.wait([
    for (final write in batch.writes) _writeOne(repository, write),
  ]);
  service.noteSettledGen(batch.claimedGen);
  final frontIds = [
    for (final result in results)
      if (!result.ok) result.id,
    for (final result in results)
      if (result.ok) result.id,
  ];

  // **결말을 여기서 끝낸다**(design 4.7 (2)의 경로 B). 여기에는 고칠 목록이 없고 캐시만 있으므로
  // 그 캐시를 **그 체크들만큼만** 고쳐 발행한다 — 목록 재조회(왕복 2)가 빠진다. 서버 쓰기가 끝난
  // 뒤의 일이라 거짓 성공이 아니다(낙관 반영과 다른 자리다).
  final checked = TodoWidgetPayload.applyChecks(
    cached,
    results: results,
    settledGen: batch.claimedGen,
  );
  final wrote = results.any((result) => result.ok);
  if (checked == null) {
    // 지름길이 성립하지 않으면(캐시 없음·줄 없는 안내 화면·목록에 없는 id) 느린 길이 남는다.
    if (!wrote) {
      await _publishFailed(service, cached, batch);
      return null;
    }
    await _publishFromServer(repository, service, userId, frontIds);
    return null;
  }
  await service.publish(checked);
  if (!wrote) return null;
  return _CheckedSession(repository, userId, frontIds);
}

/// 한 줄을 쓰고 **결과로 돌려준다**(던지지 않는다 — 한 줄의 실패가 묶음 전체를 실패로 만들지
/// 않게 한다).
Future<TodoWidgetCheckResult> _writeOne(
  TodoRepository repository,
  TodoWidgetCheckTarget target,
) async {
  try {
    await repository.setDone(target.id, target.done);
    return TodoWidgetCheckResult(id: target.id, done: target.done, ok: true);
  } catch (error) {
    debugPrint('todoWidget check failed: $error');
    return TodoWidgetCheckResult(id: target.id, done: target.done, ok: false);
  }
}

/// 실패의 결말. **`settledGen`을 함께 올린다**(design 6.2의 표): 실패한 자국도 **효력을 잃어야**
/// 그 줄이 되돌아간다. 올리지 않으면 낙관 그림이 되돌림 시각까지(7초쯤) 남아 "실패했다는 한 줄"과
/// "눌린 줄"이 같은 화면에 함께 보인다.
Future<void> _publishFailed(
  TodoWidgetService service,
  TodoWidgetPayload? cached,
  TodoWidgetBatch batch,
) async {
  // 지름길이 성립하지 않는 갈래(아래 `??`)에서도 세대가 올라가게 서비스에 먼저 적어 둔다.
  service.noteSettledGen(batch.claimedGen);
  final failed = TodoWidgetPayload.applyChecks(
    cached,
    results: [
      for (final write in batch.writes)
        TodoWidgetCheckResult(id: write.id, done: write.done, ok: false),
    ],
    settledGen: batch.claimedGen,
  );
  await service.publish(
    failed ?? TodoWidgetPayload.checkFailed(cached, now: DateTime.now()),
  );
}

/// 결말을 보여 준 **뒤** 서버 값으로 맞추는 보정 발행. 기한 키·다른 기기의 변경·개수를 되돌린다.
///
/// **자기 `try`를 갖는다**(design 4.7 (2)). 지금까지는 쓰기와 재조회가 한 `try` 안이라 **쓰기가
/// 성공한 뒤 재조회가 실패하면 `체크하지 못했어요`가 떴다**(= 서버에는 반영됐는데 실패라고
/// 말했다). 결말을 재조회에서 떼어 내면서 그 거짓 실패도 함께 사라진다 — 여기의 실패는 발행
/// 실패와 같은 등급이라 `debugPrint`만 남긴다(design 원칙 4).
///
/// **대개 다시 그리지 않는다**(2026-11-20): 보이는 것이 결말과 같으면 지문이 같아 브로드캐스트가
/// 나가지 않는다(design 5.2).
Future<void> _refreshAfterCheck(
  _CheckedSession checked,
  TodoWidgetService service,
) async {
  try {
    await _publishFromServer(
      checked.repository,
      service,
      checked.userId,
      checked.frontIds,
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
  List<String> frontIds,
) async {
  final todos = await repository.fetchTodos(userId);
  await service.publish(
    TodoWidgetPayload.fromTodos(
      todos,
      now: DateTime.now(),
      frontIds: frontIds,
      // 이 isolate의 서비스가 들고 있는 값을 그대로 물려준다 — **내리지 않는다**(design 4.2).
      settledGen: service.settledGen,
    ),
  );
}

/// 캐시를 되읽고 **결말 세대를 서비스에 물려준다**(design 4.2).
///
/// 되읽기 실패는 막지 않는다(상쇄를 못 보게 될 뿐이고 서버 쓰기는 멱등이다). 세대를 물려받는
/// 것이 중요한 이유: 이 isolate의 서비스는 방금 만들어져 0에서 시작하므로, 물려받지 않으면
/// 다음 발행이 캐시의 세대를 **내려** 이미 끝난 자국이 되살아난다.
Future<TodoWidgetPayload?> _readCache(
  TodoWidgetHost host,
  TodoWidgetService service,
) async {
  try {
    final cached = await host.read();
    if (cached != null) service.noteSettledGen(cached.settledGen);
    return cached;
  } catch (error) {
    debugPrint('todoWidget read failed: $error');
    return null;
  }
}

/// 자국 레코드를 읽는다. **읽기만 한다**(그 키의 writer는 네이티브 하나다 — design 1.1).
Future<TodoWidgetTapMarks?> _readMarks(TodoWidgetHost host) async {
  try {
    return await host.readTapMarks();
  } catch (error) {
    debugPrint('todoWidget read marks failed: $error');
    return null;
  }
}
