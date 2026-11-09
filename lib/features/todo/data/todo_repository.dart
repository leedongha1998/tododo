import 'package:supabase_flutter/supabase_flutter.dart';

import 'todo.dart';

class TodoRepository {
  TodoRepository(this._client);

  final SupabaseClient _client;

  /// 서버 정렬은 `created_at` 그대로다. **화면·위젯이 보는 순서는 여기서 만들지 않는다** —
  /// `todosProvider`가 `sortedForList`로 기한 우선 순서를 만든다(design 2.1을 그 자리로 옮긴
  /// 이유는 plan.md "설계와 다른 점": data 레이어가 domain·사용자 문구에 의존하지 않게 한다).
  Future<List<Todo>> fetchTodos(String userId) async {
    final rows = await _client
        .from('todos')
        .select()
        .eq('user_id', userId)
        .order('created_at');
    return rows.map(Todo.fromMap).toList();
  }

  Future<void> addTodo(String userId, String title, {DateTime? dueAt}) {
    return _client.from('todos').insert({
      'user_id': userId,
      'title': title,
      // insert에서 null은 "컬럼 기본값(= null)"과 같다. 둘을 구분할 필요가 없는 유일한 경로다.
      'due_at': dueAt?.toUtc().toIso8601String(),
    });
  }

  Future<void> setDone(String id, bool isDone) {
    return _client.from('todos').update({'is_done': isDone}).eq('id', id);
  }

  /// 제목과 기한을 **언제나 함께** 쓴다(`updateTitle`을 대신한다).
  ///
  /// 기한을 지우는 길이 이 서명 안에 이미 있다: `dueAt: null`을 넘기면 본문에
  /// `"due_at": null`이 **키로 들어가** PostgREST가 컬럼을 NULL로 바꾼다. "값을 안 보냄"은
  /// 아예 표현할 수 없다 — 두 인자가 모두 required이므로 호출자가 둘 다 정해야 한다.
  /// 부분 업데이트(제목만/기한만)를 만들지 않은 이유: 대화상자가 늘 두 값을 손에 들고 닫히고,
  /// 부분 업데이트를 두면 "기한을 지운다"와 "기한을 건드리지 않는다"를 구분하는 센티널이
  /// 필요해진다. 마지막 쓰기가 이긴다(개인 투두에 충돌 해결을 들이지 않는다 — 제목이 이미 그렇다).
  Future<void> updateTodo(
    String id, {
    required String title,
    required DateTime? dueAt,
  }) {
    return _client.from('todos').update({
      'title': title,
      'due_at': dueAt?.toUtc().toIso8601String(),
    }).eq('id', id);
  }

  Future<void> deleteTodo(String id) {
    return _client.from('todos').delete().eq('id', id);
  }
}
