class Todo {
  const Todo({
    required this.id,
    required this.title,
    required this.isDone,
    required this.createdAt,
    this.dueAt,
  });

  final String id;
  final String title;
  final bool isDone;
  final DateTime createdAt;

  /// 기한. null이면 기한 없음(선택 입력이라 이게 기본값이다).
  ///
  /// **UTC로 들고 다니고** 보여 줄 때만 `toLocal()`한다 — 서버가 timestamptz를 ISO8601로 주고,
  /// 비교·정렬은 절대 시각이면 되기 때문이다. 기한이 지나도 서버는 아무 일도 하지 않는다
  /// (자동 완료·삭제 없음, spec "P1. 도메인 경계").
  final DateTime? dueAt;

  factory Todo.fromMap(Map<String, dynamic> map) => Todo(
        id: map['id'] as String,
        title: map['title'] as String,
        isDone: map['is_done'] as bool,
        createdAt: DateTime.parse(map['created_at'] as String),
        dueAt: switch (map['due_at']) {
          final String raw => DateTime.parse(raw).toUtc(),
          _ => null,
        },
      );
}
