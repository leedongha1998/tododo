import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_init.dart';
import '../data/todo.dart';
import '../data/todo_repository.dart';

final todoRepositoryProvider = Provider<TodoRepository>((ref) {
  return TodoRepository(supabase);
});

final todosProvider = FutureProvider<List<Todo>>((ref) {
  final userId = supabase.auth.currentUser!.id;
  return ref.watch(todoRepositoryProvider).fetchTodos(userId);
});
