import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_init.dart';
import '../data/todo.dart';
import '../data/todo_repository.dart';
import '../data/todo_widget_host.dart';
import 'due_date_rules.dart';
import 'todo_widget_service.dart';

final todoRepositoryProvider = Provider<TodoRepository>((ref) {
  return TodoRepository(supabase);
});

/// 할 일 목록. **화면에 보이는 순서를 만드는 자리가 여기 하나다**(design 원칙 3).
///
/// `fetchTodos`를 부르는 곳은 이 provider뿐이고, 홈 위젯 캐시도 `MainShell`의
/// `ref.listen(todosProvider)`를 지나므로 앱 목록과 위젯이 **같은 리스트 객체**를 본다.
final todosProvider = FutureProvider<List<Todo>>((ref) async {
  final userId = supabase.auth.currentUser!.id;
  final todos = await ref.watch(todoRepositoryProvider).fetchTodos(userId);
  return sortedForList(todos);
});

/// 홈 화면 위젯의 네이티브 접점. 위젯 테스트에서 가짜로 바꾸는 지점이다.
final todoWidgetHostProvider = Provider<TodoWidgetHost>((ref) {
  return const TodoWidgetHost();
});

/// 위젯 캐시 발행. 직전 발행을 기억해야 하므로 앱 수명 동안 하나만 산다.
final todoWidgetServiceProvider = Provider<TodoWidgetService>((ref) {
  return TodoWidgetService(ref.watch(todoWidgetHostProvider));
});
