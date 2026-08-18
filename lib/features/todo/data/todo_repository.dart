import 'package:supabase_flutter/supabase_flutter.dart';

import 'todo.dart';

class TodoRepository {
  TodoRepository(this._client);

  final SupabaseClient _client;

  Future<List<Todo>> fetchTodos(String userId) async {
    final rows = await _client
        .from('todos')
        .select()
        .eq('user_id', userId)
        .order('created_at');
    return rows.map(Todo.fromMap).toList();
  }

  Future<void> addTodo(String userId, String title) {
    return _client.from('todos').insert({'user_id': userId, 'title': title});
  }

  Future<void> setDone(String id, bool isDone) {
    return _client.from('todos').update({'is_done': isDone}).eq('id', id);
  }

  Future<void> updateTitle(String id, String title) {
    return _client.from('todos').update({'title': title}).eq('id', id);
  }

  Future<void> deleteTodo(String id) {
    return _client.from('todos').delete().eq('id', id);
  }
}
