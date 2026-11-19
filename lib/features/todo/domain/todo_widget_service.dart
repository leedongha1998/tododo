import 'package:flutter/foundation.dart';

import '../data/todo.dart';
import '../data/todo_widget_host.dart';
import '../data/todo_widget_payload.dart';

/// 홈 화면 위젯 캐시를 발행한다. 캐시를 쓰고 위젯을 다시 그리게 하는 것이 전부다.
///
/// **발행 실패는 `debugPrint`만 남긴다.** 위젯은 관문이 아니고, 발행이 일어나는 자리(`MainShell`의
/// `ref.listen`, 백그라운드 isolate)에는 토스트를 띄울 맥락이 없다(design 원칙 4). 사용자가 할 수
/// 있는 일도 없다 — 다음 발행에서 저절로 맞춰진다. 반대로 **체크(쓰기) 실패는 삼키지 않고** 위젯
/// 안 한 줄로 말한다(`TodoWidgetPayload.checkFailed`).
///
/// 직전에 발행한 것을 들고 있으므로 앱 수명 동안 하나만 둔다(`todoWidgetServiceProvider`).
class TodoWidgetService {
  TodoWidgetService(this._host);

  final TodoWidgetHost _host;

  TodoWidgetPayload? _lastPublished;
  String? _lastJson;
  int _publishCount = 0;

  /// **다음 한 번의 [publishTodos]만** 쓰는 기억(design 7.2 (1)).
  String? _justCheckedId;
  DateTime? _justCheckedAt;

  /// 위젯이 지금 보여 주고 있는 것. 조회·체크가 실패했을 때 "직전 목록"으로 쓴다.
  TodoWidgetPayload? get lastPublished => _lastPublished;

  /// 앱이 시작될 때 한 번 부른다. 기기 캐시를 되읽어 "직전 목록"을 채우고, **보여 줄 것이 없을
  /// 때만** `loading()`을 발행한다.
  ///
  /// 되읽지 않으면 앱을 다시 켤 때마다 캐시가 "불러오는 중"으로 덮이고, 그 뒤 조회가 실패하면
  /// (네트워크 없는 가장 흔한 경우) 마지막으로 받아온 목록이 홈 화면에서 사라진다 —
  /// spec "P1" 2행과 design 2.3 상태 4가 요구하는 "목록은 그대로 두고 낡았다는 사실만 한 줄로"가
  /// 성립하지 않는다. 상태 2(불러오는 중)의 목적은 **이전 사용자의 로그아웃 캐시**를 가리는 것이고
  /// 내 지난 목록을 지우는 것이 아니다.
  Future<void> primeFromCache({required DateTime now}) async {
    TodoWidgetPayload? cached;
    try {
      cached = await _host.read();
    } catch (error) {
      debugPrint('todoWidget read failed: $error');
    }
    // 되읽는 동안 실제 목록이 이미 발행됐으면 그쪽이 더 새 것이다. 되읽은 값으로 덮지 않는다.
    if (_publishCount > 0) return;
    if (cached != null) {
      _lastPublished = cached;
      _lastJson = cached.encode();
      if (cached.hasItems) return;
    }
    await publish(TodoWidgetPayload.loading(now: now));
  }

  /// 캐시를 **"로그인하지 않음"으로 덮는다**(키를 지우지 않는다 — 키가 없으면 네이티브가 "아직
  /// 아무것도 모른다" 화면을 띄우는데 그건 로그아웃 상태와 다른 뜻이다. design 2.1).
  ///
  /// 페이로드 타입을 바깥에 내보내지 않는 얇은 창구다. 부르는 쪽(`features/auth`)이 `todo/data`의
  /// 타입을 import하지 않게 하려는 것이고(design 8.1), 그래서 로그아웃·탈퇴 경로는 함수 하나만
  /// 받아 쓴다(`AuthRepository`의 `ClearWidgetCache`).
  ///
  /// 실패는 [publish]가 안에서 삼키고 `debugPrint`만 남기므로 호출부에 `try`가 필요 없다 —
  /// 위젯 캐시 때문에 로그아웃·탈퇴가 막히지 않는다.
  Future<void> publishLoggedOut({DateTime? now}) {
    return publish(TodoWidgetPayload.loggedOut(now: now ?? DateTime.now()));
  }

  /// **"방금 누른 줄"의 id를 한 번만 적어 둔다**(design 7.2 (1)).
  ///
  /// 이 기억이 필요한 이유는 자리의 문제다 — 앱의 발행 지점(`MainShell`의 `ref.listen`)은
  /// "목록이 바뀌었다"만 알고 **어느 줄을 눌렀는지 모른다**. 그리고 위젯 탭이 앱에 쓰기를 맡기는
  /// 경로에서는 `pendingId`를 적은 캐시를 **백그라운드 isolate가** 썼으므로 앱 쪽 서비스는 그
  /// 값을 들고 있지도 않다(두 isolate가 각자 인스턴스를 갖는다). 그래서 id를 아는 자리
  /// (`AuthGate._onWidgetCheck`)가 적어 두고 다음 발행이 소비한다.
  void markJustChecked(String id, {DateTime? at}) {
    _justCheckedId = id;
    _justCheckedAt = at ?? DateTime.now();
  }

  /// 목록 하나를 캐시로 발행한다. **앱 안에서 `fromTodos`를 부르는 자리를 여기 하나로 줄인다**
  /// (백그라운드 직접 쓰기만 예외다 — 그쪽은 자기가 id를 들고 있다).
  ///
  /// [markJustChecked]로 적어 둔 id는 **이 한 번의 발행에만** 쓰이고 바로 지워진다. 그것이
  /// spec 조항("이 예외가 유효한 동안 = 그 발행 동안")의 구현이다. 60초 상한을 함께 두는 이유는
  /// 쓰기가 성공했는데 목록 재조회가 늦어져 발행이 한참 뒤에 올 때 **엉뚱한 발행이 그 예외를
  /// 쓰지 않게** 하려는 것이다(`pending` 만료와 같은 수명을 쓴다).
  Future<void> publishTodos(List<Todo> todos, {required DateTime now}) {
    return publish(
      TodoWidgetPayload.fromTodos(
        todos,
        now: now,
        justCheckedId: _consumeJustChecked(now),
      ),
    );
  }

  /// 위젯에서 누른 체크의 **결말**을 그 자리에서 발행한다(design 4.7 (2)의 경로 A).
  ///
  /// 서버 쓰기가 **끝난 뒤**에만 불린다 — 거짓 성공이 아니다. 목록을 다시 받지 않고 앱이 이미
  /// 들고 있는 [todos]에서 그 한 줄만 바꿔 캐시를 만든다. 그래서 체크 한 번의 네트워크 왕복이
  /// 둘에서 하나로 준다(K).
  ///
  /// 두 가지를 일부러 하지 않는다:
  /// - **[markJustChecked]로 적어 둔 기억을 소비하지 않는다.** 그것은 뒤따르는 `invalidate` →
  ///   `MainShell` 발행(= 보정)이 써야 한다. 여기서 소비하면 1~2초 뒤 **방금 누른 줄이 사라진다.**
  ///   대신 [todoId]를 직접 넘겨 이 발행에도 같은 예외를 준다.
  /// - **기준 시각을 앞당기지 않는다.** 직전 발행의 `updatedAtMs`를 그대로 물려준다 — 체크는
  ///   목록을 새로 받아온 것이 아니다.
  Future<void> publishChecked(
    List<Todo> todos, {
    required String todoId,
    required bool done,
    required DateTime now,
  }) {
    return publish(
      TodoWidgetPayload.fromTodos(
        todosWithDone(todos, todoId, done),
        now: now,
        justCheckedId: todoId,
        basisAt: _lastPublished?.updatedAtMs,
      ),
    );
  }

  String? _consumeJustChecked(DateTime now) {
    final id = _justCheckedId;
    final at = _justCheckedAt;
    _justCheckedId = null;
    _justCheckedAt = null;
    if (id == null || at == null) return null;
    final elapsed = now.millisecondsSinceEpoch - at.millisecondsSinceEpoch;
    if (elapsed < 0 || elapsed >= todoWidgetPendingTimeoutSeconds * 1000) {
      return null;
    }
    return id;
  }

  Future<void> publish(TodoWidgetPayload payload) async {
    _publishCount++;
    final json = payload.encode();
    // 같은 값을 다시 쓰고 브로드캐스트를 또 보낼 이유가 없다(탭을 오갈 때마다 목록이 다시 와도
    // 내용이 같으면 조용하다).
    if (json == _lastJson) return;
    try {
      await _host.save(payload);
      await _host.update();
      // 성공한 발행만 "직전"으로 기억한다. 실패했으면 위젯에는 옛 내용이 남아 있으므로
      // 다음 발행이 같은 값이어도 다시 시도해야 한다.
      _lastJson = json;
      _lastPublished = payload;
    } catch (error) {
      debugPrint('todoWidget publish failed: $error');
    }
  }
}
