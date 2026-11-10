import 'package:supabase_flutter/supabase_flutter.dart';

import 'todo.dart';

class TodoRepository {
  TodoRepository(this._client);

  final SupabaseClient _client;

  /// 목록 순서는 **서버가 만든다**(todo-reorder design 2장). 앱 목록·홈 위젯 캐시 발행·위젯
  /// 체크를 처리할 백그라운드 경로가 이 메서드 하나를 지나므로, 순서를 만드는 자리가 둘이 될 수
  /// 없다. `position`은 사용자가 끌어 정한 값이고(1024 간격), 같은 사용자의 두 행이 같은 값을
  /// 가질 수 없다(unique (user_id, position)).
  ///
  /// **`ascending: true`를 반드시 적는다.** postgrest의 `order`는 기본이 **내림차순**이다 —
  /// 지금까지 `order('created_at')`로 적혀 있던 것도 내림차순이었고, Dart가 다시 정렬해 덮었기
  /// 때문에 드러나지 않았다. 그 정렬을 걷어낸 지금은 이 한 줄이 그대로 화면 순서다.
  /// id까지 적는 이유: 동순위는 제약이 막지만, 순서의 보장을 제약 하나에 매달지 않고 쿼리 자체를
  /// 전순서로 만든다(수십 행 규모에서 비용이 없다).
  Future<List<Todo>> fetchTodos(String userId) async {
    final rows = await _client
        .from('todos')
        .select()
        .eq('user_id', userId)
        .order('position', ascending: true)
        .order('id', ascending: true);
    return rows.map(Todo.fromMap).toList();
  }

  /// 끌기 한 번. [afterId]가 null이면 맨 위다.
  ///
  /// **자리 값을 클라이언트가 계산하지 않는다** — 서버가 그 순간의 실제 이웃에서 만든다(design
  /// 원칙 2). 그래서 보내는 것이 "기준 할 일 하나"뿐이고, 한 번의 호출이 한 트랜잭션이라
  /// 절반만 반영된 순서가 남지 않는다. 실패는 호출자가 토스트로 알린다(삼키지 않는다).
  Future<void> moveTodo(String todoId, {required String? afterId}) {
    return _client.rpc(
      'move_todo',
      params: {'p_todo_id': todoId, 'p_after_id': afterId},
    );
  }

  /// `position`을 **보내지 않는다** — 컬럼 기본값(`nextval * 1024`)이 맨 아래를 만든다
  /// (todo-reorder design 1.5). 두 기기가 같은 순간에 추가해도 시퀀스가 서로 다른 값을 주므로
  /// 둘 다 성공하고 둘 다 맨 아래로 간다.
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
