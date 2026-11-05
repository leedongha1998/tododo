// ProviderScope의 overrides 타입(`Override`)은 flutter_riverpod.dart가 아니라 misc.dart에 있다.
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:todododo/features/todo/data/todo_widget_host.dart';
import 'package:todododo/features/todo/data/todo_widget_payload.dart';
import 'package:todododo/features/todo/domain/todo_providers.dart';

/// `home_widget` 대신 쓰는 가짜. 발행된 페이로드를 순서대로 모아 둔다.
///
/// 테스트에서 실제 플러그인을 건드리면 MethodChannel이 없어 던지고, `TodoWidgetService`가 그
/// 예외를 로그로 삼킨다 — 통과하지만 아무것도 검증되지 않는다(푸시 가짜와 같은 이유).
class FakeTodoWidgetHost extends TodoWidgetHost {
  FakeTodoWidgetHost({this.saveError, this.updateError, this.readError, this.stored});

  /// 캐시 쓰기가 실패하는 상황을 만든다.
  final Object? saveError;

  /// 위젯 다시 그리기 요청이 실패하는 상황을 만든다.
  final Object? updateError;

  /// 캐시 되읽기가 실패하는 상황을 만든다.
  final Object? readError;

  final saved = <TodoWidgetPayload>[];
  int updateCount = 0;
  int readCount = 0;

  /// 기기에 남아 있는 캐시. 앱을 다시 켠 상황을 만들 때 생성자로 넣는다.
  TodoWidgetPayload? stored;

  @override
  Future<void> save(TodoWidgetPayload payload) async {
    saved.add(payload);
    final error = saveError;
    if (error != null) throw error;
    stored = payload;
  }

  @override
  Future<TodoWidgetPayload?> read() async {
    readCount++;
    final error = readError;
    if (error != null) throw error;
    return stored;
  }

  @override
  Future<void> update() async {
    updateCount++;
    final error = updateError;
    if (error != null) throw error;
  }
}

/// 위젯 발행이 플러그인에 닿지 않게 하는 override. 위젯을 검증하지 않는 화면 테스트에도 넣는다.
List<Override> todoWidgetOverrides({FakeTodoWidgetHost? host}) {
  return [todoWidgetHostProvider.overrideWithValue(host ?? FakeTodoWidgetHost())];
}
