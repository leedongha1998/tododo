import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/push/push_providers.dart';
import '../../../core/supabase/supabase_init.dart';
import '../data/due_alarm_host.dart';
import '../data/todo.dart';
import '../data/todo_repository.dart';
import '../data/todo_widget_host.dart';
import '../data/todo_widget_notice_store.dart';
import 'due_alarm_service.dart';
import 'todo_widget_service.dart';
import 'todo_widget_tap_settler.dart';

final todoRepositoryProvider = Provider<TodoRepository>((ref) {
  return TodoRepository(supabase);
});

/// 할 일 목록. **순서는 서버가 만든다**(order by position — todo-reorder design 2장).
///
/// 이 provider는 그 결과를 그대로 들고, 홈 위젯 캐시도 `MainShell`의
/// `ref.listen(todosProvider)`를 지나므로 앱 목록과 위젯이 **같은 리스트 객체**를 본다.
/// 위젯 체크의 백그라운드 경로는 이 provider를 지나지 않고 레포지토리를 직접 부르는데,
/// 정렬이 서버에 있어 그쪽도 같은 순서를 본다.
final todosProvider = FutureProvider<List<Todo>>((ref) async {
  final userId = supabase.auth.currentUser!.id;
  return ref.watch(todoRepositoryProvider).fetchTodos(userId);
});

/// 홈 화면 위젯의 네이티브 접점. 위젯 테스트에서 가짜로 바꾸는 지점이다.
final todoWidgetHostProvider = Provider<TodoWidgetHost>((ref) {
  return const TodoWidgetHost();
});

/// 위젯 캐시 발행. 직전 발행을 기억해야 하므로 앱 수명 동안 하나만 산다.
final todoWidgetServiceProvider = Provider<TodoWidgetService>((ref) {
  return TodoWidgetService(ref.watch(todoWidgetHostProvider));
});

/// 위젯에서 누른 체크 **묶음**을 앱의 세션으로 쓰고 결말을 발행하는 조립(design 9장).
/// 앱 쪽 두 자리(`AuthGate`의 핸드오프, `MainShell`의 앱 열림 계기)가 **같은 규칙**을 지나게 한다.
final todoWidgetTapSettlerProvider = Provider<TodoWidgetTapSettler>((ref) {
  return TodoWidgetTapSettler(ref, ref.watch(todoWidgetHostProvider));
});

/// 홈 화면 노출 안내를 봤는지 기억하는 곳(기기 로컬·계정별). 테스트에서 가짜로 바꾸는 지점이다.
final todoWidgetNoticeStoreProvider = Provider<TodoWidgetNoticeStore>((ref) {
  return const TodoWidgetNoticeStore();
});

/// 기한 알림(기기 로컬)의 네이티브 접점. 테스트에서 가짜로 바꾸는 지점이다.
final dueAlarmHostProvider = Provider<DueAlarmHost>((ref) {
  return const DueAlarmHost();
});

/// 기한 알림 예약·보정. 직전에 맞춘 집합을 기억해야 하므로 앱 수명 동안 하나만 산다.
///
/// ref를 함께 넘기는 이유: 알림을 탭하면 할 일 탭으로 보내야 하고(`selectedTabProvider`),
/// 권한을 물은 뒤 `notificationPermissionProvider`를 다시 읽혀야 한다(`PushService`와 같다).
final dueAlarmServiceProvider = Provider<DueAlarmService>((ref) {
  return DueAlarmService(
    ref,
    ref.watch(dueAlarmHostProvider),
    ref.watch(pushMessagingProvider),
  );
});

/// 목록이 읽는 "지금". 남은 시간 문구가 **시간이 흐르는 것만으로** 바뀌는 유일한 입력이라
/// 테스트에서 손으로 돌릴 수 있는 자리가 필요하다(`todo_due_tick_test.dart`).
///
/// 앱에서는 늘 `DateTime.now`다. 다른 화면의 "지금"까지 여기로 모으지 않는다 — **스스로 다시
/// 그려야 하는 목록만** 이 접점을 쓴다.
final todoNowProvider = Provider<DateTime Function()>((ref) => DateTime.now);
