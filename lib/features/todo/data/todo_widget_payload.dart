// 홈 화면 투두 위젯이 읽는 기기 캐시의 내용.
//
// 설계 원칙 하나가 이 파일에 모여 있다(design.md 원칙 2): 네이티브는 그리기만 하고 판단은
// Dart가 한다. 어떤 상태인지, 어떤 문구를 쓰는지, 몇 개까지 담는지, 기준 시각을 어떻게 적는지를
// 여기서 전부 정해 JSON 하나로 적어 둔다. 네이티브(TodoWidgetProvider.kt)가 하는 판단은
// "이 높이에 몇 줄이 들어가나"(visibleRows와 같은 규칙)와 "moreFormat에 숫자 하나 끼우기"뿐이다.
//
// 플랫폼 타입이 섞이지 않아 전부 유닛 테스트로 고정할 수 있다
// (test/features/todo/todo_widget_payload_test.dart).

import 'dart:convert';

import '../../../core/strings.dart';
import 'todo.dart';

/// 캐시 JSON의 판 번호. 네이티브가 모르는 판이면 대체 한 줄로 떨어진다.
const todoWidgetSchemaVersion = 1;

/// 캐시에 담는 할 일의 최대 개수. 위젯이 그리는 줄은 최대 6이고(design 6.2) 여유로 두 개를 더 담는다.
const todoWidgetMaxItems = 8;

/// 제목을 자르는 길이. 한 줄에 들어갈 수 있는 글자 수보다 넉넉하다 — 캐시를 작게 두기 위한 상한이다.
const todoWidgetMaxTitleLength = 80;

/// `pending` 표시가 유효한 시간(초). 네이티브는 이 시간이 지난 `pending`을 무시하고 그 줄을
/// 평소대로 그린다 — 쓰기 도중에 프로세스가 죽어도 "체크된 것처럼" 남지 않는다(design 4.3).
const todoWidgetPendingTimeoutSeconds = 60;

/// 위젯이 쓰는 Uri의 스킴·호스트. OAuth 콜백(`com.todododo.todododo://login-callback`)과 다르고,
/// `supabase_flutter`의 딥링크 관찰자는 인증 파라미터가 없는 Uri를 무시한다(design 5장).
const todoWidgetUriScheme = 'todododo';
const todoWidgetUriHost = 'widget';

final _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

/// note 줄의 색. 네이티브는 색만 고른다.
enum TodoWidgetNoteTone { muted, danger }

/// 위젯을 눌렀을 때 앱에서 열려야 하는 곳. 지금은 네이티브가 분기하지 않는다(둘 다 앱 열기이고,
/// 미로그인이면 `AuthGate`가 알아서 로그인 화면을 띄운다). 대결용으로 확장하지 않는다.
enum TodoWidgetTapTarget { todo, login }

/// 위젯에 그릴 할 일 한 줄. 제목과 id뿐이다 — 완료 여부·생성 시각·대결 정보는 담지 않는다.
class TodoWidgetItem {
  const TodoWidgetItem({required this.id, required this.title});

  final String id;
  final String title;

  Map<String, dynamic> toJson() => {'id': id, 'title': title};

  static TodoWidgetItem? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final title = raw['title'];
    if (id is! String || title is! String) return null;
    return TodoWidgetItem(id: id, title: title);
  }

  @override
  bool operator ==(Object other) =>
      other is TodoWidgetItem && other.id == id && other.title == title;

  @override
  int get hashCode => Object.hash(id, title);

  @override
  String toString() => 'TodoWidgetItem($id, $title)';
}

/// 기기 캐시에 적히는 JSON 한 개(design 2.2). 키를 여러 개로 쪼개지 않는 이유는 네이티브가
/// 반쯤 갱신된 상태를 읽지 않게 하기 위함이다.
class TodoWidgetPayload {
  const TodoWidgetPayload({
    required this.items,
    required this.totalCount,
    required this.updatedAtMs,
    this.centerText,
    this.note = '',
    this.noteTone = TodoWidgetNoteTone.muted,
    this.pendingId,
    this.pendingAtMs,
    this.tapTarget = TodoWidgetTapTarget.todo,
  });

  /// 그릴 줄. **미완료만**, 앱과 같은 순서(`created_at` 오름차순)로 최대 [todoWidgetMaxItems]개.
  final List<TodoWidgetItem> items;

  /// 미완료 **전체** 개수. "그 외 N개"를 여기서 계산한다([visibleRows]).
  final int totalCount;

  /// 이 페이로드의 **기준 시각**(= 목록을 받아온 시각). note의 시각 문장과 뜻이 같아야 하므로,
  /// 목록을 그대로 물려받는 발행([fetchFailed]·[checkFailed]·[pending])은 이 값도 물려받는다.
  final int updatedAtMs;

  /// 목록 대신 가운데에 띄울 안내. [items]가 빈 상태에서만 채운다.
  final String? centerText;

  /// 아래 한 줄. 상태 문구·기준 시각·실패 안내가 모두 여기로 모인다(완성된 문장을 넣는다).
  final String note;

  final TodoWidgetNoteTone noteTone;

  /// 지금 체크를 쓰고 있는 할 일. 네이티브는 [todoWidgetPendingTimeoutSeconds]가 지나지 않은
  /// `pending`만 `쓰는 중`으로 그린다.
  final String? pendingId;
  final int? pendingAtMs;

  final TodoWidgetTapTarget tapTarget;

  /// 네이티브가 하는 유일한 문자열 조립. 숫자 하나를 끼운다.
  static const moreFormat = AppStrings.widgetMoreFormat;

  bool get hasItems => items.isNotEmpty;

  /// 상태 3 — 정상 / 상태 6 — 할 일이 하나도 없음 / 상태 7 — 미완료가 없음(전부 완료).
  ///
  /// 6과 7을 가르는 값은 "완료까지 포함한 전체 할 일 개수"다. `fetchTodos`가 완료 여부로
  /// 필터하지 않으므로 둘 다 이미 손에 있다.
  factory TodoWidgetPayload.fromTodos(
    List<Todo> todos, {
    required DateTime now,
  }) {
    final at = now.millisecondsSinceEpoch;
    if (todos.isEmpty) {
      return TodoWidgetPayload(
        items: const [],
        totalCount: 0,
        updatedAtMs: at,
        centerText: AppStrings.widgetEmpty,
      );
    }
    final undone = todos.where((todo) => !todo.isDone).toList();
    if (undone.isEmpty) {
      return TodoWidgetPayload(
        items: const [],
        totalCount: 0,
        updatedAtMs: at,
        centerText: AppStrings.widgetAllDone,
      );
    }
    final items = undone
        .take(todoWidgetMaxItems)
        .map((todo) => TodoWidgetItem(id: todo.id, title: _clip(todo.title)))
        .toList();
    return TodoWidgetPayload(
      items: items,
      totalCount: undone.length,
      updatedAtMs: at,
      note: AppStrings.widgetNoteFresh(formatWidgetTime(now)),
    );
  }

  /// 상태 1 — 로그인하지 않음. 이전 사용자의 내용을 **즉시 지운다**(키를 지우지 않고 덮어쓴다).
  factory TodoWidgetPayload.loggedOut({required DateTime now}) {
    return TodoWidgetPayload(
      items: const [],
      totalCount: 0,
      updatedAtMs: now.millisecondsSinceEpoch,
      centerText: AppStrings.widgetLoggedOut,
      tapTarget: TodoWidgetTapTarget.login,
    );
  }

  /// 상태 2 — 로그인 직후 첫 조회 중. 로그아웃 캐시가 로그인한 사용자에게 잠깐 보이는 것을 막는다.
  factory TodoWidgetPayload.loading({required DateTime now}) {
    return TodoWidgetPayload(
      items: const [],
      totalCount: 0,
      updatedAtMs: now.millisecondsSinceEpoch,
      centerText: AppStrings.widgetLoading,
    );
  }

  /// 상태 4·5 — 조회 실패. 직전 목록이 있으면 **그대로 두고** note만 바꾼다(기준 시각은 목록의
  /// 나이를 뜻하므로 직전 값을 쓴다). 없으면 안내 한 줄만 남는다.
  factory TodoWidgetPayload.fetchFailed(
    TodoWidgetPayload? previous, {
    required DateTime now,
  }) {
    if (previous == null || !previous.hasItems) {
      return TodoWidgetPayload(
        items: const [],
        totalCount: 0,
        updatedAtMs: now.millisecondsSinceEpoch,
        centerText: AppStrings.widgetFetchFailed,
      );
    }
    final at = DateTime.fromMillisecondsSinceEpoch(previous.updatedAtMs);
    return TodoWidgetPayload(
      items: previous.items,
      totalCount: previous.totalCount,
      updatedAtMs: previous.updatedAtMs,
      note: AppStrings.widgetNoteStale(formatWidgetTime(at)),
    );
  }

  /// 상태 8 — 체크가 반영되지 않음. 목록을 **지운 적이 없으므로** 그 할 일은 자동으로 되살아난다.
  /// 이 note는 다음 발행(목록 재조회·다른 체크 성공)에서 사라진다 — 지우는 타이머를 두지 않는다.
  factory TodoWidgetPayload.checkFailed(TodoWidgetPayload? previous) {
    if (previous == null || !previous.hasItems) {
      return TodoWidgetPayload(
        items: const [],
        totalCount: 0,
        updatedAtMs: previous?.updatedAtMs ?? 0,
        centerText: AppStrings.widgetCheckFailed,
        noteTone: TodoWidgetNoteTone.danger,
      );
    }
    return TodoWidgetPayload(
      items: previous.items,
      totalCount: previous.totalCount,
      updatedAtMs: previous.updatedAtMs,
      note: AppStrings.widgetCheckFailed,
      noteTone: TodoWidgetNoteTone.danger,
      tapTarget: previous.tapTarget,
    );
  }

  /// 체크를 쓰는 중. 그 줄만 `쓰는 중`으로 바뀌고 나머지는 직전 그대로다.
  factory TodoWidgetPayload.pending(
    TodoWidgetPayload previous,
    String todoId, {
    required DateTime now,
  }) {
    return TodoWidgetPayload(
      items: previous.items,
      totalCount: previous.totalCount,
      updatedAtMs: previous.updatedAtMs,
      centerText: previous.centerText,
      note: previous.note,
      noteTone: previous.noteTone,
      pendingId: todoId,
      pendingAtMs: now.millisecondsSinceEpoch,
      tapTarget: previous.tapTarget,
    );
  }

  /// **null인 키는 아예 넣지 않는다.** 안드로이드(AOSP)의 `org.json`은 upstream과 달라
  /// `optString(name, fallback)`이 **명시적 null에는 fallback이 아니라 `"null"` 네 글자**를
  /// 돌려준다(fallback은 키가 아예 없을 때만 쓰인다). 그래서 `centerText: null`을 그대로 실으면
  /// 정상 상태에서 위젯 가운데에 `null`이 뜬다. 네이티브도 `isNull`을 먼저 검사하지만, 한쪽이
  /// 바뀌어도 깨지지 않게 두 곳 모두에서 막는다. `fromJson`은 키가 없으면 null로 읽는다.
  Map<String, dynamic> toJson() => {
        'v': todoWidgetSchemaVersion,
        'items': items.map((item) => item.toJson()).toList(),
        'totalCount': totalCount,
        if (centerText != null) 'centerText': centerText,
        'note': note,
        'noteTone': noteTone.name,
        // 이 둘은 앱 판마다 고정인 문구다. 캐시에 실어 보내는 이유는 네이티브가 한국어 문자열을
        // 따로 갖지 않게 하기 위함이다(문구의 출처는 언제나 AppStrings 하나다).
        'moreFormat': moreFormat,
        'pendingLabel': AppStrings.widgetPendingLabel,
        if (pendingId != null) 'pendingId': pendingId,
        if (pendingAtMs != null) 'pendingAtMs': pendingAtMs,
        'tapTarget': tapTarget.name,
        'updatedAtMs': updatedAtMs,
      };

  String encode() => jsonEncode(toJson());

  /// 네이티브가 쓰는 것과 같은 규칙으로 되읽는다. 판 번호를 모르거나 모양이 어긋나면 null이다 —
  /// 그 경우 호출자는 "직전 캐시가 없다"로 다루면 된다.
  static TodoWidgetPayload? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return fromJson(decoded);
    } on FormatException {
      return null;
    }
  }

  static TodoWidgetPayload? fromJson(Map<String, dynamic> json) {
    if (json['v'] != todoWidgetSchemaVersion) return null;
    final rawItems = json['items'];
    final items = <TodoWidgetItem>[];
    if (rawItems is List) {
      for (final raw in rawItems) {
        final item = TodoWidgetItem.fromJson(raw);
        if (item != null) items.add(item);
      }
    }
    final totalCount = json['totalCount'];
    final updatedAtMs = json['updatedAtMs'];
    if (totalCount is! int || updatedAtMs is! int) return null;
    final centerText = json['centerText'];
    final note = json['note'];
    final pendingId = json['pendingId'];
    final pendingAtMs = json['pendingAtMs'];
    return TodoWidgetPayload(
      items: items,
      totalCount: totalCount,
      updatedAtMs: updatedAtMs,
      centerText: centerText is String ? centerText : null,
      note: note is String ? note : '',
      noteTone: json['noteTone'] == TodoWidgetNoteTone.danger.name
          ? TodoWidgetNoteTone.danger
          : TodoWidgetNoteTone.muted,
      pendingId: pendingId is String ? pendingId : null,
      pendingAtMs: pendingAtMs is int ? pendingAtMs : null,
      tapTarget: json['tapTarget'] == TodoWidgetTapTarget.login.name
          ? TodoWidgetTapTarget.login
          : TodoWidgetTapTarget.todo,
    );
  }

  static String _clip(String title) {
    final trimmed = title.trim();
    return trimmed.length <= todoWidgetMaxTitleLength
        ? trimmed
        : trimmed.substring(0, todoWidgetMaxTitleLength);
  }
}

/// 자리가 [rowCount]줄일 때 **할 일 몇 줄을 그리고 "그 외 N개"는 몇인가.**
///
/// 네이티브가 그대로 옮길 규칙이라 Dart에 두고 유닛 테스트로 고정한다(design 12장).
/// 담기지 않는 할 일이 있으면 **마지막 줄 하나를 "더 있음" 줄로 바꿔 쓴다** — 그러지 않으면
/// "3개 보이고 그 외 0개"처럼 어긋난다. 단 [rowCount]가 1이면 그 유일한 줄을 안내로 바꾸지 않는다
/// (할 일을 하나도 못 보는 위젯이 되는 것보다 "더 있다"를 생략하는 쪽이 낫다).
({List<TodoWidgetItem> rows, int moreCount}) visibleRows(
  List<TodoWidgetItem> items,
  int totalCount,
  int rowCount,
) {
  if (rowCount <= 0 || items.isEmpty) {
    return (rows: const <TodoWidgetItem>[], moreCount: 0);
  }
  if (rowCount == 1 || totalCount <= rowCount) {
    return (rows: items.take(rowCount).toList(), moreCount: 0);
  }
  final rows = items.take(rowCount - 1).toList();
  return (rows: rows, moreCount: totalCount - rows.length);
}

/// 기준 시각 문장에 쓰는 시각(`오전 9:14`). 서버 시각이 아니라 **기기 시계**를 쓰는 유일한 자리이고,
/// 이 값으로 달라지는 판정·승부는 없다(spec "도메인 경계").
String formatWidgetTime(DateTime at) {
  final isAm = at.hour < 12;
  final hour12 = at.hour % 12 == 0 ? 12 : at.hour % 12;
  return AppStrings.widgetTime(isAm: isAm, hour: hour12, minute: at.minute);
}

/// 위젯의 체크 칸을 눌렀을 때 백그라운드가 받는 동작.
class TodoWidgetAction {
  const TodoWidgetAction.check(String this.todoId);
  const TodoWidgetAction.none() : todoId = null;

  /// 완료 처리할 할 일. null이면 아무 일도 하지 않는다.
  final String? todoId;

  bool get isCheck => todoId != null;

  @override
  bool operator ==(Object other) =>
      other is TodoWidgetAction && other.todoId == todoId;

  @override
  int get hashCode => todoId.hashCode;

  @override
  String toString() => 'TodoWidgetAction(${todoId ?? 'none'})';
}

/// `todododo://widget/check?id=<uuid>` 해석.
///
/// uuid 모양을 검사하는 이유는 `notification_payload.dart`의 `battleIdOf`와 같다 — 틀린 값을
/// 그대로 쓰기에 넘기면 서버 오류로만 드러나고, 사용자에게는 "눌렀는데 실패했다"로 보인다.
TodoWidgetAction todoWidgetActionOf(Uri? uri) {
  if (!_isWidgetUri(uri) || uri!.pathSegments.length != 1) {
    return const TodoWidgetAction.none();
  }
  if (uri.pathSegments.first != 'check') return const TodoWidgetAction.none();
  final id = uri.queryParameters['id']?.trim();
  if (id == null || !_uuid.hasMatch(id)) return const TodoWidgetAction.none();
  return TodoWidgetAction.check(id);
}

/// 위젯 탭으로 앱이 열렸을 때 어디로 보낼 것인가. 해석할 수 없으면 아무것도 하지 않는다
/// (오류 화면을 보이지 않는다 — 알림 탭 규칙과 같은 태도).
TodoWidgetTapTarget? widgetTargetOf(Uri? uri) {
  if (!_isWidgetUri(uri) || uri!.pathSegments.length != 1) return null;
  return uri.pathSegments.first == 'todo' ? TodoWidgetTapTarget.todo : null;
}

bool _isWidgetUri(Uri? uri) {
  return uri != null &&
      uri.scheme == todoWidgetUriScheme &&
      uri.host == todoWidgetUriHost;
}
