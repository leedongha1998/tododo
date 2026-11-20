import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/domain/auth_providers.dart';
import '../data/todo_repository.dart';
import '../data/todo_widget_host.dart';
import '../data/todo_widget_payload.dart';
import 'todo_providers.dart';
import 'todo_widget_service.dart';

/// 묶음 하나의 결말. 백그라운드 isolate에 돌려 줄 답과 1:1이다.
enum TodoWidgetSettleOutcome {
  /// **결말을 발행했다.** 줄마다 성공·실패가 갈렸어도 그 사실이 이미 위젯에 그려졌다.
  settled,

  /// 아무것도 하지 못했다 — 백그라운드가 실패 한 줄을 띄운다.
  failed,

  /// 앱은 떠 있지만 로그인 화면이다.
  loggedOut,
}

/// 위젯에서 누른 체크 **묶음을 앱의 살아 있는 세션으로 쓰고 결말을 한 번 발행한다**
/// (design 9장의 신규 파일 · 6.2).
///
/// **이 파일이 있는 이유는 앱 쪽에 그 일을 하는 자리가 둘이기 때문이다**:
///   1. 백그라운드가 맡긴 쓰기(`AuthGate`의 포트 — design 4.2의 W5),
///   2. **앱이 열리는 계기**(`MainShell`의 `initState`·`onResume` — 계기 ④, design 6.3).
/// 둘이 **같은 claim 규칙과 같은 발행 규칙**을 지나게 하는 것이 이 클래스의 존재 이유다. 규칙
/// 자체는 `todo_widget_payload.dart`의 순수 함수에 있고(백그라운드 isolate도 **같은 함수**를
/// 쓴다) 여기서는 조립만 한다.
///
/// 실패는 전부 `debugPrint`만 남긴다 — 위젯은 관문이 아니고, 이 자리에 토스트를 띄울 맥락이
/// 없다(design 원칙 4). **단, 백그라운드가 맡긴 쓰기의 실패는 답으로 돌려준다** — 그쪽이 위젯 안
/// 한 줄로 말한다(spec "P0. 쓰기 동작").
class TodoWidgetTapSettler {
  TodoWidgetTapSettler(this._ref, this._host);

  final Ref _ref;
  final TodoWidgetHost _host;

  /// 백그라운드가 맡긴 묶음을 쓴다(경로 A).
  ///
  /// [claimedGen]은 그 묶음이 가져간 마지막 자국 세대다. 결말 발행이 `settledGen`을 그 값으로
  /// 올려 **그 묶음에 들어간 자국만** 효력을 잃게 한다(design 4.1).
  Future<TodoWidgetSettleOutcome> settle(
    List<TodoWidgetCheckTarget> targets, {
    required int claimedGen,
  }) async {
    if (targets.isEmpty) return TodoWidgetSettleOutcome.settled;
    final service = _ref.read(todoWidgetServiceProvider);
    try {
      final userId = _ref.read(authRepositoryProvider).currentUser?.id;
      if (userId == null) return TodoWidgetSettleOutcome.loggedOut;

      // **`setDone` 앞에서** 적어 둔다. 그 뒤 `invalidate`가 일으키는 발행(= 보정)이 "방금 누른
      // 줄들"을 알게 하는 유일한 길이다(이 자리만 id를 안다. design 7.2 (1)).
      service.markJustChecked([for (final target in targets) target.id]);

      final repository = _ref.read(todoRepositoryProvider);
      // **줄마다 자기 `try`**를 갖는다(design 10.2): 한 줄이 실패해도 나머지는 그대로 쓰이고
      // 결말이 줄마다 다르게 그려진다(spec S). 그래서 `Future.wait`의 `eagerError`를 쓰지 않는다.
      // 병렬인 이유는 순차로 돌리면 N줄 × 왕복이라 5초 창을 넘길 수 있기 때문이다.
      final results = await Future.wait([
        for (final target in targets) _writeOne(repository, target),
      ]);

      await _publishSettled(service, results, claimedGen);
      _ref.invalidate(todosProvider);
      return TodoWidgetSettleOutcome.settled;
    } catch (error) {
      // 삼키지 않는다 — 부르는 쪽이 이 답을 받아 위젯 안 한 줄로 말한다(spec).
      debugPrint('todoWidget settle (app) failed: $error');
      return TodoWidgetSettleOutcome.failed;
    }
  }

  /// **앱이 열리는 계기**(④). 자국 중 **떠날 시각이 이미 지난 묶음만** 그 자리에서 마무리한다.
  ///
  /// 지나지 않았으면 **건드리지 않는다** — 1초 안에 백그라운드 일꾼이 할 일이고, 두 일꾼을
  /// 만들지 않는 쪽을 고른다(design 4.4의 11번). 즉 이 경로는 **"일꾼이 오지 않았을 때의 최후
  /// 보루"**다.
  ///
  /// 실패는 `debugPrint`만 남긴다(위젯은 관문이 아니다). 앱이 뜨는 것을 막지 않는다.
  Future<void> settleLapsed({DateTime? now}) async {
    final at = now ?? DateTime.now();
    final service = _ref.read(todoWidgetServiceProvider);
    try {
      final marks = await _host.readTapMarks();
      if (marks == null) return;
      final cached = service.lastPublished ?? await _host.read();
      final batch = todoWidgetBatchOf(marks: marks, payload: cached, now: at);
      if (batch == null) return;
      // 아직 모으는 중인 묶음은 **일꾼의 것**이다.
      if (at.millisecondsSinceEpoch < batch.leaveAtMs) return;
      // 이미 정산된 묶음이면 할 일이 없다.
      if (batch.claimedGen <= service.settledGen) return;
      if (batch.isEmpty) {
        // 상쇄만 있었던 묶음이다 — 서버 호출도 발행도 없다(그림은 이미 맞다. spec P).
        service.noteSettledGen(batch.claimedGen);
        return;
      }
      await settle(batch.writes, claimedGen: batch.claimedGen);
    } catch (error) {
      debugPrint('todoWidget settle on open failed: $error');
    }
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
      debugPrint('todoWidget check (app) failed: $error');
      return TodoWidgetCheckResult(id: target.id, done: target.done, ok: false);
    }
  }

  /// **결말을 여기서 끝낸다**(design 4.7 (2)의 경로 A): 서버 쓰기가 끝났으므로 목록을 다시 받지
  /// 않고 앱이 이미 든 목록에서 그 줄들만 바꿔 발행한다. 뒤따르는 `invalidate`의 발행은 결말이
  /// 아니라 **보정**이다.
  ///
  /// 목록을 아직 한 번도 못 받아왔으면 **캐시로** 같은 결말을 만든다(경로 B와 같은 재료). 그조차
  /// 없으면 **세대만 올린다** — 올리지 않으면 쓰기가 끝난 줄의 낙관 그림이 되돌림 시각까지
  /// 남는다(design 4.2).
  Future<void> _publishSettled(
    TodoWidgetService service,
    List<TodoWidgetCheckResult> results,
    int claimedGen,
  ) async {
    // `AsyncError`도 직전 값을 들고 있으므로 `value`를 그대로 쓴다 — 조회가 실패한 뒤의 그
    // 목록은 위젯이 지금 보여 주고 있는 것과 같은 나이다(riverpod 3에 `valueOrNull`은 없다).
    final todos = _ref.read(todosProvider).value;
    if (todos != null) {
      await service.publishSettled(
        todos,
        results: results,
        claimedGen: claimedGen,
        now: DateTime.now(),
      );
      return;
    }
    service.noteSettledGen(claimedGen);
    // 발행한 적이 없으면(앱이 막 떴다) **기기 캐시**가 마지막 재료다.
    final cached = service.lastPublished ?? await _host.read();
    final fromCache = TodoWidgetPayload.applyChecks(
      cached,
      results: results,
      settledGen: claimedGen,
    );
    if (fromCache != null) await service.publish(fromCache);
  }
}

