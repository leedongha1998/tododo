import 'package:home_widget/home_widget.dart';

import 'todo_widget_payload.dart';

/// `home_widget` 접점. 위젯 테스트에서 가짜로 바꾸는 지점이다
/// (선례: `PushMessaging`, `EvidenceCamera`, `VsIntroSeenStore`).
///
/// 여기서는 예외를 삼키지 않는다. 호출자(`TodoWidgetService`)가 로그를 남기고 삼킨다 —
/// 위젯은 관문이 아니므로 캐시 발행 실패로 앱 동작을 막지 않는다(design 원칙 4).
class TodoWidgetHost {
  const TodoWidgetHost();

  /// Dart가 쓰고 Kotlin이 읽는 캐시 키. `TodoWidgetProvider.PAYLOAD_KEY`와 같아야 한다.
  static const payloadKey = 'todo_widget_payload';

  /// 다시 그릴 위젯. manifest의 `<receiver android:name=".TodoWidgetProvider">`와 같아야 한다.
  static const providerName = 'com.todododo.todododo.TodoWidgetProvider';

  /// 캐시를 덮어쓴다. 키 하나에 JSON 하나만 쓴다 — 여러 키로 쪼개면 네이티브가 반쯤 갱신된
  /// 상태를 읽을 수 있다.
  Future<void> save(TodoWidgetPayload payload) async {
    await HomeWidget.saveWidgetData<String>(payloadKey, payload.encode());
  }

  /// 지금 캐시에 있는 것. 판 번호를 모르거나 모양이 어긋나면 null이다.
  Future<TodoWidgetPayload?> read() async {
    final raw = await HomeWidget.getWidgetData<String>(payloadKey);
    return TodoWidgetPayload.decode(raw);
  }

  /// 홈 화면의 위젯을 다시 그리게 한다(네이티브 브로드캐스트).
  Future<void> update() async {
    await HomeWidget.updateWidget(qualifiedAndroidName: providerName);
  }
}
