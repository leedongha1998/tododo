import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_init.dart';
import '../data/todo.dart';
import '../data/todo_repository.dart';
import '../data/todo_widget_host.dart';
import 'todo_widget_service.dart';

final todoRepositoryProvider = Provider<TodoRepository>((ref) {
  return TodoRepository(supabase);
});

final todosProvider = FutureProvider<List<Todo>>((ref) {
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
