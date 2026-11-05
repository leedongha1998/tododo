import 'package:flutter/foundation.dart';

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
