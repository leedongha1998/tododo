import 'dart:async';

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

  /// 위젯의 체크 칸 탭을 받을 백그라운드 콜백을 등록한다.
  ///
  /// **앱 실행마다 다시 등록한다**(`AuthGate`): 등록되는 것은 Dart 콜백의 핸들이고 앱을
  /// 업데이트하면 그 값이 낡는다. 등록 실패는 `debugPrint`만 남긴다 — 체크가 안 되는 것은
  /// 위젯의 손해이고 앱의 로그인·화면을 막을 이유가 없다.
  Future<void> registerCallback(FutureOr<void> Function(Uri?) callback) async {
    await HomeWidget.registerInteractivityCallback(callback);
  }
}
