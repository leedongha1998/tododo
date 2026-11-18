// 홈 화면 투두 위젯이 읽는 기기 캐시의 내용.
//
// 설계 원칙 하나가 이 파일에 모여 있다(design.md 원칙 2): 네이티브는 그리기만 하고 판단은
// Dart가 한다. 어떤 상태인지, 어떤 문구를 쓰는지, 몇 개까지 담는지, 기준 시각을 어떻게 적는지를
// 여기서 전부 정해 JSON 하나로 적어 둔다. 네이티브(TodoWidgetProvider.kt)가 하는 판단은 **여섯**
// 이고 전부 "비교하고 Dart가 보낸 것 중에서 고르기"다(design 원칙 2의 2026-11-18 각주 둘):
//   1. 높이 → 줄 수(widgetRowCount와 같은 식)
//   2. moreFormat에 숫자 하나 끼우기
//   3. now - pendingAtMs < 60초 → `쓰는 중`을 그릴지
//   4. now >= dueAtMs → 기한 줄의 문장(due/dueOver)과 색 고르기
//   5. rank < limit → 이 항목을 그릴지(줄 자리 수는 네이티브만 아는 값이라 Dart가 순서만 굳혀
//      보낸다 — 정책은 여기, 비교 한 줄은 거기)
//   6. done → 줄 면·제목 색·취소선·체크 그림 고르기(사실은 Dart가 적어 보낸다)
// 문장을 **만드는** 일은 한 자도 네이티브에 두지 않는다. 개수 문구(`할 일 2/5`)도 완성된 문장으로
// 실려 가고, 네이티브는 숫자를 세거나 분수를 조립하지 않는다.
//
// 플랫폼 타입이 섞이지 않아 전부 유닛 테스트로 고정할 수 있다
// (test/features/todo/todo_widget_payload_test.dart).

import 'dart:convert';

import '../../../core/strings.dart';
import 'todo.dart';

/// 캐시 JSON의 판 번호. 네이티브가 모르는 판이면 대체 한 줄로 떨어진다.
const todoWidgetSchemaVersion = 1;

/// 캐시에 담는 할 일의 최대 개수. 위젯이 그리는 줄은 최대 6이고([todoWidgetMaxRows]) 여유로
/// 두 개를 더 담는다.
///
/// **줄이 두꺼워진 뒤에도 8을 그대로 둔다**(design 6.2.1): 줄 수의 상한은 여전히 6이고 276dp
/// 이상인 위젯에서 실제로 6줄에 도달한다. 상한을 6~7로 줄이면 그 큰 위젯에서 마지막 줄이 비는데,
/// 8개를 담는 비용은 기한 키 셋을 더해도 1KB 안쪽이다 — 줄이고 얻는 것이 없다.
const todoWidgetMaxItems = 8;

/// 캐시에 담는 **완료한** 할 일의 최대 개수. 미완료 몫([todoWidgetMaxItems])과 **따로 둔다** —
/// 한 상한에 섞어 담으면 완료가 앞에 몰린 사용자의 캐시가 완료로 채워져, 보이는 줄에 넣을 미완료가
/// 캐시에 없어 **빈자리**가 생긴다(spec 추가 범위 2 F가 금지한 그 경우다).
///
/// 6인 이유: 완료 줄은 미완료가 0일 때에만 줄 상한(6)까지 쓰므로 그보다 많이 담을 이유가 없다.
/// 최악의 경우 항목 14개이고 기한 키까지 합쳐 JSON 2KB 안쪽이다(design 2.2.2).
const todoWidgetMaxDoneItems = 6;

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

/// 위젯에 그릴 할 일 한 줄. 제목·id·기한뿐이다 — 완료 여부·생성 시각·대결 정보는 담지 않는다.
///
/// **기한은 문장 둘과 절대 시각 하나로 싣는다**(design 2.2.1). Dart는 발행 시점에 "그 줄을 다시
/// 그릴 때 기한이 지났을지"를 알 수 없으므로(주기 갱신은 Dart를 깨우지 않는다) 두 문장을 미리
/// 보내고 네이티브는 [dueAtMs]를 기기 시계와 비교해 **고르기만** 한다. 그래서 "지남"이 발행
/// 시점에 굳지 않는다 — 이 객체에 `overdue` 같은 불값이 없는 것이 그 보장이다.
class TodoWidgetItem {
  const TodoWidgetItem({
    required this.id,
    required this.title,
    required this.rank,
    this.done = false,
    this.due,
    this.dueOver,
    this.dueAtMs,
  });

  final String id;
  final String title;

  /// **줄 자리 우선순위**(0이 가장 먼저). 네이티브는 `rank < 줄 자리 수`인 항목만 그린다.
  ///
  /// **그리는 순서가 아니다** — 그리는 순서는 [TodoWidgetPayload.items]의 **배열 순서**(= 앱 목록의
  /// `position`)다. 이 분리가 spec의 두 요구를 동시에 지키는 장치다(design 2.2.2): "줄 자리는
  /// 미완료가 먼저 쓴다"(고르기 = rank)와 "체크한 줄이 **제자리에서** 완료 모양으로 바뀌고 아래
  /// 줄이 올라오지 않는다"(그리기 = 배열 순서). 둘을 한 순서로 합치면 체크한 줄이 목록 맨 아래로
  /// 뛰어내린다.
  final int rank;

  /// 완료한 할 일. 네이티브는 이 사실에 대응하는 리소스(면·글자색·취소선·체크 그림)를 고른다.
  /// **거짓이면 캐시에 키째로 싣지 않는다**(네이티브는 `optBoolean("done", false)`).
  final bool done;

  /// 기한이 **아직 지나지 않았을 때** 그릴 문장(`오후 6:00` / `11/20 오후 6:00`).
  /// 기한이 없으면 null이고 캐시에 키째로 실리지 않는다.
  final String? due;

  /// 기한이 **이미 지났을 때** 그릴 문장([due] + `지남`).
  final String? dueOver;

  /// 기한의 epoch 밀리초(UTC 절대 시각). **네이티브가 `now`와 비교하는 유일한 값**이고
  /// 시간대와 무관하다.
  final int? dueAtMs;

  /// **null인 키는 싣지 않는다** — 안드로이드(AOSP) `org.json`의 `optString`이 명시적 null에
  /// `"null"` 네 글자를 돌려주기 때문이다(`TodoWidgetPayload.toJson`의 주석과 같은 이유).
  /// 기한이 없는 줄에 `"null"`이나 대체 기호가 그려지면 spec 조항("아무것도 보이지 않는다")을
  /// 어긴다.
  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'rank': rank,
        if (done) 'done': true,
        if (due != null) 'due': due,
        if (dueOver != null) 'dueOver': dueOver,
        if (dueAtMs != null) 'dueAtMs': dueAtMs,
      };

  /// [index]는 **배열에서의 자리**이고 `rank` 키가 없는 **옛 캐시의 기본값**이다.
  ///
  /// 그 기본값이 판 번호(`v`)를 올리지 않아도 되게 하는 장치다(design 2.2.2): 옛 캐시는 미완료만
  /// position 순서로 담겨 있으므로 `rank = index`를 주면 `rank < limit`이 옛 규칙 `take(limit)`과
  /// **정확히 같아진다.** 네이티브도 `optInt("rank", index)`로 같은 규칙을 쓴다.
  static TodoWidgetItem? fromJson(Object? raw, int index) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final title = raw['title'];
    if (id is! String || title is! String) return null;
    final rank = raw['rank'];
    final due = raw['due'];
    final dueOver = raw['dueOver'];
    final dueAtMs = raw['dueAtMs'];
    return TodoWidgetItem(
      id: id,
      title: title,
      rank: rank is int ? rank : index,
      done: raw['done'] == true,
      due: due is String ? due : null,
      dueOver: dueOver is String ? dueOver : null,
      dueAtMs: dueAtMs is int ? dueAtMs : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TodoWidgetItem &&
      other.id == id &&
      other.title == title &&
      other.rank == rank &&
      other.done == done &&
      other.due == due &&
      other.dueOver == dueOver &&
      other.dueAtMs == dueAtMs;

  @override
  int get hashCode => Object.hash(id, title, rank, done, due, dueOver, dueAtMs);

  @override
  String toString() =>
      'TodoWidgetItem($id, $title, rank $rank, ${done ? '완료' : '미완료'}, '
      '${due ?? '기한 없음'})';
}

/// 기기 캐시에 적히는 JSON 한 개(design 2.2). 키를 여러 개로 쪼개지 않는 이유는 네이티브가
/// 반쯤 갱신된 상태를 읽지 않게 하기 위함이다.
class TodoWidgetPayload {
  const TodoWidgetPayload({
    required this.items,
    required this.totalCount,
    required this.updatedAtMs,
    this.header = AppStrings.widgetHeader,
    this.centerText,
    this.note = '',
    this.noteTone = TodoWidgetNoteTone.muted,
    this.pendingId,
    this.pendingAtMs,
    this.tapTarget = TodoWidgetTapTarget.todo,
  });

  /// 그릴 줄. **앱과 같은 순서**로 미완료 최대 [todoWidgetMaxItems]개 + 완료 최대
  /// [todoWidgetMaxDoneItems]개(2026-11-18 추가 범위 2: 완료도 캐시에 담긴다).
  ///
  /// "앱과 같은 순서"는 **사용자가 끌어 정한 순서**다(todos.position, todo-reorder design 2장).
  /// 그 순서를 만드는 자리는 서버 쿼리 하나이고 [fromTodos]는 받은 순서를 보존하기만 한다.
  /// **이 배열 순서가 그리는 순서**이고, 어느 줄이 보일지는 [TodoWidgetItem.rank]가 정한다.
  final List<TodoWidgetItem> items;

  /// 미완료 **전체** 개수. "그 외 N개"를 여기서 계산한다([visibleRows]).
  final int totalCount;

  /// 머리 줄 왼쪽에 그릴 **완성된 문장**(`할 일 2/5` 또는 `할 일`).
  ///
  /// 숫자 둘을 따로 싣지 않는 이유는 원칙 2다 — 네이티브가 `할 일 %d/%d`를 조립하면 그것은
  /// "문장을 만드는 일"이고, 분수 꼴 자체가 오너가 고른 **문구**다(design 2.2.2).
  ///
  /// 개수를 적는 상태는 **줄이 보이는 상태뿐**이다(정상·전부 완료·조회 실패·체크 실패).
  /// 로그인하지 않음·조회 중·목록 없는 조회 실패·할 일 없음에서는 `할 일`만 남는다 — 셀 목록이
  /// 손에 없거나 숫자가 전부 0이라 `0/0`은 허전한 거짓이 된다(design 2.3.1).
  final String header;

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

  /// 상태 3 — 정상 / 상태 3b — 미완료가 없음(전부 완료) / 상태 6 — 할 일이 하나도 없음.
  ///
  /// 3b와 6을 가르는 값은 "완료까지 포함한 전체 할 일 개수"다. `fetchTodos`가 완료 여부로
  /// 필터하지 않으므로 둘 다 이미 손에 있다. **3b는 안내 한 줄이 아니라 완료 줄을 보여 준다**
  /// (2026-11-18 추가 범위 2: 가운데 안내는 줄 영역을 덮어 목록과 공존할 수 없으므로 그 문장을
  /// 머리 줄의 note로 옮겼다 — design 2.3.1).
  ///
  /// **배열 순서를 여기서 정하지 않는다.** 받은 리스트의 순서(= 서버의 `order by position` = 앱
  /// 목록 순서)를 그대로 보존한다. 자리를 **고르는** 순서는 따로 매긴 [TodoWidgetItem.rank]가
  /// 들고 간다.
  ///
  /// [justCheckedId]는 **"방금 누른 줄은 반드시 보인다"는 예외 하나**를 위해 있다(spec 추가 범위
  /// 2 F). 그 줄이 밀려 사라지면 "체크하면 사라진다"로 되돌아가 이번 요구가 무의미해진다. 그래서
  /// `rank 0`을 주고(어떤 줄 자리 수에서도 보이려면 0이어야 한다) 캐시 상한 안에 반드시 담는다.
  /// **그 항목이 목록에 있고 완료 상태일 때만** 쓴다 — 되돌린 줄은 미완료가 되어 어차피 앞 순위다.
  factory TodoWidgetPayload.fromTodos(
    List<Todo> todos, {
    required DateTime now,
    String? justCheckedId,
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
    final undone = <Todo>[];
    final done = <Todo>[];
    for (final todo in todos) {
      (todo.isDone ? done : undone).add(todo);
    }
    // 분자는 완료, 분모는 **전체(미완료+완료)**다. 누적 숫자가 되는 것은 오너가 보고 고른 쪽이다
    // (spec 추가 범위 2의 오너 확정 2).
    final header = AppStrings.widgetHeaderCount(
      done: done.length,
      total: todos.length,
    );

    // 캐시 상한을 **둘로 나눠** 담는다(완료가 미완료를 밀어내지 않는다).
    final keptDone = _keepDone(done, justCheckedId);
    final ranks = _ranksOf(
      undone: undone.take(todoWidgetMaxItems),
      keptDone: keptDone,
      justCheckedId: justCheckedId,
    );
    final items = [
      for (final todo in todos)
        if (ranks[todo.id] case final rank?) _itemOf(todo, now, rank: rank),
    ];

    return TodoWidgetPayload(
      items: items,
      totalCount: undone.length,
      updatedAtMs: at,
      header: header,
      // 전부 완료면 그 사실을 note로 말한다(문구는 그대로 재사용하고 자리만 옮겼다).
      note: undone.isEmpty
          ? AppStrings.widgetAllDone
          : AppStrings.widgetNoteFresh(formatWidgetTime(now)),
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
      // 개수도 **같은 시점의 값**이어야 화면과 어긋나지 않는다(새로 셀 목록이 손에 없다).
      header: previous.header,
      note: AppStrings.widgetNoteStale(formatWidgetTime(at)),
    );
  }

  /// 상태 8 — 체크가 반영되지 않음. 목록을 **지운 적이 없으므로** 그 할 일은 자동으로 되살아난다.
  /// 이 note는 다음 발행(목록 재조회·다른 체크 성공)에서 사라진다 — 지우는 타이머를 두지 않는다.
  factory TodoWidgetPayload.checkFailed(
    TodoWidgetPayload? previous, {
    required DateTime now,
  }) {
    if (previous == null || !previous.hasItems) {
      return TodoWidgetPayload(
        items: const [],
        totalCount: 0,
        // 직전 목록이 없을 때 0(=1970년)을 적지 않는다. 지금 이 갈래는 note가 비어 있어 화면에
        // 1970이 보이지 않지만, **값 자체가 거짓**이고 다음에 이 갈래에 note가 붙으면
        // `오전 12:00 기준`이 찍힌다(2026-11-05 리뷰 정리 1건, design 4.5 (3)).
        updatedAtMs: previous?.updatedAtMs ?? now.millisecondsSinceEpoch,
        centerText: AppStrings.widgetCheckFailed,
        noteTone: TodoWidgetNoteTone.danger,
      );
    }
    return TodoWidgetPayload(
      items: previous.items,
      totalCount: previous.totalCount,
      updatedAtMs: previous.updatedAtMs,
      // 서버 반영에 실패한 체크를 성공으로 센 숫자를 적지 않는다 — 직전 값을 그대로 쓴다.
      header: previous.header,
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
      header: previous.header,
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
        'header': header,
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
      for (var index = 0; index < rawItems.length; index++) {
        final item = TodoWidgetItem.fromJson(rawItems[index], index);
        if (item != null) items.add(item);
      }
    }
    final totalCount = json['totalCount'];
    final updatedAtMs = json['updatedAtMs'];
    if (totalCount is! int || updatedAtMs is! int) return null;
    final centerText = json['centerText'];
    final note = json['note'];
    final header = json['header'];
    final pendingId = json['pendingId'];
    final pendingAtMs = json['pendingAtMs'];
    return TodoWidgetPayload(
      items: items,
      totalCount: totalCount,
      updatedAtMs: updatedAtMs,
      // 옛 캐시(header 키가 없다)는 `할 일`로 읽는다 — 네이티브가 그때 레이아웃 기본값을 남기는
      // 것과 같은 뜻이다(개수를 모르면 말하지 않는다. design 2.2.2).
      header: header is String && header.isNotEmpty
          ? header
          : AppStrings.widgetHeader,
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

  /// 할 일 하나를 줄 하나로 옮긴다. **기한이 없으면 세 키를 전부 만들지 않는다**(design 2.2.1).
  ///
  /// 문장을 둘 만드는 비용은 항목당 수십 바이트이고, 그 대가로 네이티브가 문구를 한 자도
  /// 만들지 않는다(원칙 2).
  ///
  /// **완료한 할 일에도 기한 키를 싣지 않는다**(spec: 완료 줄에는 기한을 보여 주지 않는다 — 앱과
  /// 같다). 그 규칙을 여기서 끝내므로 네이티브에 "완료면 기한을 숨겨라"는 분기가 생기지 않는다:
  /// 기한 키가 없으면 `GONE`인 기존 첫 분기가 그대로 처리한다(design 2.2.2 · 6.3.1).
  static TodoWidgetItem _itemOf(Todo todo, DateTime now, {required int rank}) {
    final dueAt = todo.dueAt;
    if (dueAt == null || todo.isDone) {
      return TodoWidgetItem(
        id: todo.id,
        title: _clip(todo.title),
        rank: rank,
        done: todo.isDone,
      );
    }
    final due = formatWidgetDue(dueAt, now);
    return TodoWidgetItem(
      id: todo.id,
      title: _clip(todo.title),
      rank: rank,
      due: due,
      dueOver: AppStrings.widgetDueOverdue(due),
      dueAtMs: dueAt.millisecondsSinceEpoch,
    );
  }

  /// 캐시에 담을 **완료한** 할 일을 고른다(최대 [todoWidgetMaxDoneItems]개, position 순서).
  ///
  /// **방금 누른 줄은 반드시 담는다**: 완료가 7개 이상이고 그것이 앞 6개에 없으면
  /// `앞 5개 + 그것`으로 담는다. 그 줄은 앞 6개에 없었으므로 position이 그들보다 뒤이고, 그래서
  /// 이렇게 담아도 **배열이 position 순서를 유지한다**(design 2.2.2).
  static List<Todo> _keepDone(List<Todo> done, String? justCheckedId) {
    final kept = done.take(todoWidgetMaxDoneItems).toList();
    if (justCheckedId == null) return kept;
    if (kept.any((todo) => todo.id == justCheckedId)) return kept;
    for (final todo in done) {
      if (todo.id != justCheckedId) continue;
      return [...done.take(todoWidgetMaxDoneItems - 1), todo];
    }
    return kept;
  }

  /// 항목마다 **줄 자리 우선순위**를 매긴다(design 2.2.2):
  ///
  /// ```
  /// 0        : justCheckedId (그 항목이 목록에 있고 완료 상태일 때만)
  /// 1, 2, ...: 미완료, position 순서
  /// 그 뒤    : 나머지 완료, position 순서
  /// ```
  ///
  /// 자리 수(줄 수)는 런처가 주는 높이에서 나와 **네이티브만 아는 값**이다. 그래서 Dart가 최종
  /// 선택을 끝낼 수 없고, 대신 순서를 숫자로 굳혀 보내 네이티브가 `rank < limit` 하나만 비교하게
  /// 한다 — 정책은 여기 남고 네이티브에는 비교 한 줄이 간다.
  static Map<String, int> _ranksOf({
    required Iterable<Todo> undone,
    required List<Todo> keptDone,
    required String? justCheckedId,
  }) {
    final ranks = <String, int>{};
    if (justCheckedId != null &&
        keptDone.any((todo) => todo.id == justCheckedId)) {
      ranks[justCheckedId] = ranks.length;
    }
    for (final todo in undone) {
      ranks.putIfAbsent(todo.id, () => ranks.length);
    }
    for (final todo in keptDone) {
      ranks.putIfAbsent(todo.id, () => ranks.length);
    }
    return ranks;
  }

  static String _clip(String title) {
    final trimmed = title.trim();
    return trimmed.length <= todoWidgetMaxTitleLength
        ? trimmed
        : trimmed.substring(0, todoWidgetMaxTitleLength);
  }
}

/// 자리가 [rowCount]줄일 때 **어느 항목을 그리고 "그 외 N개"는 몇인가.**
///
/// 네이티브가 그대로 옮길 규칙이라 Dart에 두고 유닛 테스트로 고정한다(design 12장·6.2.2).
/// 담기지 않는 **미완료**가 있으면 **마지막 줄 하나를 "더 있음" 줄로 바꿔 쓴다** — 그러지 않으면
/// "3개 보이고 그 외 0개"처럼 어긋난다. 단 [rowCount]가 1이면 그 유일한 줄을 안내로 바꾸지 않는다
/// (할 일을 하나도 못 보는 위젯이 되는 것보다 "더 있다"를 생략하는 쪽이 낫다).
///
/// 고르는 기준은 **`rank < limit` 하나**다. "미완료 먼저 + 방금 누른 줄 예외"라는 규칙은 랭크를
/// 매길 때 이미 끝났으므로(`TodoWidgetPayload.fromTodos`) 여기서는 자리 수만 적용한다 — 그래서
/// 자리가 미완료로 가득 차면 완료 줄의 랭크가 자연히 밖으로 밀려 **하나도 보이지 않는다**
/// (그 사실은 머리 줄의 개수가 말한다).
///
/// [totalCount]는 **미완료 전체** 개수이고 `그 외 N개`도 미완료만 센다(spec 추가 범위 2 F:
/// 완료 쪽은 헤더가 센다 — 한 위젯에서 같은 것을 두 자리가 세지 않는다). 그래서 완료 줄이 자리를
/// 쓰면 보이는 미완료가 줄어 `그 외 N개`가 그만큼 커진다.
({List<TodoWidgetItem> rows, int moreCount}) visibleRows(
  List<TodoWidgetItem> items,
  int totalCount,
  int rowCount,
) {
  if (rowCount <= 0 || items.isEmpty) {
    return (rows: const <TodoWidgetItem>[], moreCount: 0);
  }
  int undoneShown(int limit) =>
      items.where((item) => item.rank < limit && !item.done).length;

  var limit = rowCount;
  var moreCount = 0;
  if (rowCount > 1 && totalCount > undoneShown(rowCount)) {
    // 한 번만 줄여도 되는 근거: limit를 1 줄이면 보이는 미완료는 **늘어날 수 없으므로**
    // `totalCount > undoneShown(limit)`이 여전히 참이고 moreCount가 1 이상이 보장된다.
    limit = rowCount - 1;
    moreCount = totalCount - undoneShown(limit);
  }
  return (
    rows: items.where((item) => item.rank < limit).toList(),
    moreCount: moreCount,
  );
}

/// 위젯의 **고정 비용**. 줄 수를 셀 때 먼저 뗀다.
///
/// 내역은 2026-11-18(추가 범위 2)에 바뀌었지만 **합은 그대로다**(design 6.2.2):
/// 옛 내역 = 루트 위·아래 여백 4+4 + 아래 note 16dp, 지금 = 루트 위·아래 여백 4+2 + 머리 줄 18dp.
/// 머리 줄이 옛 note의 자리를 그대로 물려받았으므로 **모든 높이에서 줄 수가 같다** — 그것이
/// spec G의 두 조건(기본 크기 2줄 / 실기기 225dp에서 4줄)을 가장 강하게 지키는 방식이다.
const todoWidgetFixedHeightDp = 24;

/// 줄 하나가 쓰는 세로(줄 minHeight 40dp + 아래 여백 2dp). 레이아웃(`todo_widget.xml`)의 수치와
/// 같아야 한다.
const todoWidgetRowPitchDp = 42;

/// 그릴 수 있는 줄의 상한. 레이아웃이 선언한 줄 개수와 같아야 한다.
const todoWidgetMaxRows = 6;

/// 위젯 높이(dp) → **그릴 줄 수**.
///
/// 표를 하드코딩하지 않고 상수 셋으로 적는 이유는, 레이아웃 수치를 고칠 때 표를 따로 고치는 것을
/// 잊어 **잘린 줄**이 나오는 것을 막으려는 것이다(design 6.2.1). 그래서 이 함수가 규칙의 주인이고
/// 네이티브(`TodoWidgetProvider.rowCountFor`)는 같은 상수로 같은 식을 옮겨 쓴다(`visibleRows`와
/// 같은 방식).
///
/// 4x2(기본 크기)에서 2줄이 보장되는 근거: 2줄에 필요한 높이는 `24 + 84 = 108dp`이고
/// `todo_widget_info.xml`이 선언한 `minHeight`가 **110dp**여서 런처가 그보다 작은 자리에 이 위젯을
/// 놓지 않는다. 런처가 높이를 알려 주지 않을 때의 기본값(110)도 같은 구간에 떨어진다.
///
/// 틀리는 방향은 **"줄이 하나 덜 보인다"** 다(잘리지 않는다) — 마지막 줄의 아래 여백과 "더 있음"
/// 줄(12sp)이 전부 예산 안에 들어 있어 실제로 쓰는 높이는 계산보다 작다. spec이 금지한 것은
/// 반쯤 잘린 줄이므로 보수적으로 틀리는 쪽을 골랐다.
int widgetRowCount(int heightDp) {
  final rows = (heightDp - todoWidgetFixedHeightDp) ~/ todoWidgetRowPitchDp;
  return rows.clamp(1, todoWidgetMaxRows);
}

/// 기준 시각 문장에 쓰는 시각(`오전 9:14`). 서버 시각이 아니라 **기기 시계**를 쓰는 유일한 자리이고,
/// 이 값으로 달라지는 판정·승부는 없다(spec "도메인 경계").
String formatWidgetTime(DateTime at) {
  final isAm = at.hour < 12;
  final hour12 = at.hour % 12 == 0 ? 12 : at.hour % 12;
  return AppStrings.widgetTime(isAm: isAm, hour: hour12, minute: at.minute);
}

/// 위젯 줄에 적는 **할 일 기한의 절대 시각 문장**(design 6.1.1). 세 꼴이고 12시간제다:
/// 같은 날이면 `오후 6:00`, 다른 날·같은 해면 `11/20 오후 6:00`, 다른 해면 `2027/1/5 오후 6:00`.
///
/// **`오늘`·`내일` 같은 낱말을 쓰지 않는다.** 그 꼴은 자정을 넘기면 틀린 문장이 되는데(발행 뒤
/// Dart는 깨어나지 않으므로 `내일`이 `오늘`로 바뀌지 않고, 기한이 아직 안 지났으니 `지남`도
/// 붙지 않아 **아무것도 그 거짓을 알려 주지 않는다**) spec이 상대 표현을 버린 이유가 그대로
/// 적용된다. 반대로 "같은 날이면 시각만" 꼴은 안전하다 — 날이 바뀐 뒤 그 시각은 **반드시 지난
/// 시각**이라 네이티브가 `지남`과 실패색을 함께 붙인다(어느 날인지 모호해지지만 거짓은 아니고,
/// 앱을 한 번 열면 `M/D` 꼴로 바뀐다).
///
/// 서식을 `due_date_rules.dart`가 아니라 여기에 두는 이유는 계층이다 — 페이로드는 `data/`이고
/// 거기서 `domain/`을 import하면 방향이 거꾸로 선다. 게다가 이 꼴은 **위젯 전용**이다(앱 목록은
/// `formatDueLabel`, 대화상자는 `formatDueValue`를 쓴다).
///
/// [dueAtUtc]는 모델이 들고 다니는 UTC 값이고(`Todo.dueAt`), 문장을 만들 때만 로컬로 바꾼다.
/// [now]도 로컬로 맞춰 **같은 기준끼리** 연·월·일을 비교한다.
String formatWidgetDue(DateTime dueAtUtc, DateTime now) {
  final due = dueAtUtc.toLocal();
  final at = now.toLocal();
  final time = formatWidgetTime(due);
  if (due.year == at.year && due.month == at.month && due.day == at.day) {
    return time;
  }
  if (due.year == at.year) {
    return AppStrings.widgetDueDate(
      month: due.month,
      day: due.day,
      time: time,
    );
  }
  return AppStrings.widgetDueDateYear(
    year: due.year,
    month: due.month,
    day: due.day,
    time: time,
  );
}

/// 위젯의 체크 칸을 눌렀을 때 백그라운드가 받는 동작.
class TodoWidgetAction {
  /// 그 할 일의 완료 여부를 [done]으로 **만든다**(뒤집는 것이 아니다 — 아래 근거).
  const TodoWidgetAction.setDone(String this.todoId, {required this.done});
  const TodoWidgetAction.none() : todoId = null, done = true;

  /// 완료 여부를 바꿀 할 일. null이면 아무 일도 하지 않는다.
  final String? todoId;

  /// **목표 값**. `true`면 완료 처리, `false`면 되돌리기다([todoId]가 null이면 뜻이 없다).
  final bool done;

  bool get isWrite => todoId != null;

  @override
  bool operator ==(Object other) =>
      other is TodoWidgetAction && other.todoId == todoId && other.done == done;

  @override
  int get hashCode => Object.hash(todoId, done);

  @override
  String toString() => todoId == null
      ? 'TodoWidgetAction(none)'
      : 'TodoWidgetAction($todoId, done: $done)';
}

/// `todododo://widget/check?id=<uuid>&done=1|0` 해석.
///
/// uuid 모양을 검사하는 이유는 `notification_payload.dart`의 `battleIdOf`와 같다 — 틀린 값을
/// 그대로 쓰기에 넘기면 서버 오류로만 드러나고, 사용자에게는 "눌렀는데 실패했다"로 보인다.
///
/// **토글(`현재 값을 뒤집어라`)로 만들지 않는다**(design 4.6 (1)). 백그라운드는 **낡은 그림을 누른
/// 탭**을 받을 수 있다(캐시가 30분 낡았을 수 있고 발행이 실패해 화면이 뒤처져 있을 수도 있다).
/// 토글이면 그때 **사용자가 본 것과 반대로** 쓰게 된다. 목표 값을 싣으면 그 탭은 멱등이고
/// "사용자가 본 줄을 본 대로 만든다"가 보장된다.
///
/// **`done`이 없거나 `1`/`0`이 아니면 완료(`true`)로 읽는다.** `PendingIntent`는 앱 업데이트를 넘어
/// 시스템에 남아 있고, 업데이트 직후 위젯이 아직 다시 그려지지 않은 사이에 옛 APK가 만든 Uri
/// (`done`이 없는 꼴)가 발사될 수 있다 — 그때의 옳은 동작이 정확히 완료 처리다(옛 위젯의 체크 칸은
/// 완료 전용이었다). 경로는 `check` 하나로 두고 `uncheck`를 새로 만들지 않는다.
TodoWidgetAction todoWidgetActionOf(Uri? uri) {
  if (!_isWidgetUri(uri) || uri!.pathSegments.length != 1) {
    return const TodoWidgetAction.none();
  }
  if (uri.pathSegments.first != 'check') return const TodoWidgetAction.none();
  final id = uri.queryParameters['id']?.trim();
  if (id == null || !_uuid.hasMatch(id)) return const TodoWidgetAction.none();
  final done = uri.queryParameters['done']?.trim() != '0';
  return TodoWidgetAction.setDone(id, done: done);
}

/// 체크 탭 하나를 어떻게 처리할지. 백그라운드 콜백에서 **결정만** 떼어 낸 것이다.
///
/// 그 콜백은 실기기에서만 검증되므로(isolate·네트워크·백그라운드 engine을 테스트하지 않는다)
/// 판단할 수 있는 부분을 전부 여기로 옮겨 유닛 테스트로 덮는다(design 12장).
enum TodoWidgetCheckDecision {
  /// 아무 일도 하지 않는다 — 체크가 아닌 Uri, 중복 탭, 이미 목록에서 사라진 할 일.
  ignore,

  /// **앱의 main isolate에 쓰기를 맡긴다.** 그쪽의 살아 있는 Supabase 클라이언트가 쓰므로
  /// 이 isolate가 클라이언트를 또 만들지 않는다 — 토큰이 돌아 앱이 로그아웃되는 경로를 막는
  /// 것이 W5의 핵심이다(design 4.2).
  handOff,

  /// 이 isolate에서 직접 쓴다. 앱 프로세스가 죽어 있으므로 토큰 회전으로 깨뜨릴 상대가 없다.
  writeHere,
}

/// [action]·캐시 상태·앱 생존 여부로 [TodoWidgetCheckDecision]을 고른다.
///
/// 캐시를 보는 세 가지 이유(design 4.3의 2번 · 4.6 (2)):
///   - **중복 탭**: 같은 줄을 연속으로 두 번 누르면 첫 탭이 아직 쓰고 있다. 서버 쓰기가 멱등이라
///     두 번 가도 해롭지는 않지만, 두 번째 발행이 첫 번째의 `쓰는 중`을 흔든다. 방향과 무관하다.
///   - **이미 목표 값인 줄**: 아무것도 바꾸지 않는 쓰기를 서버에 보내지 않고, 그 때문에 `쓰는 중`이
///     깜빡이지도 않게 한다. 완료 줄이 목록에 남게 된 뒤로는 **"없어짐"이 더 이상 성공의 표시가
///     아니어서**(2026-11-18 추가 범위 2) 옛 조건을 이 조건으로 바꿨다.
///   - **목록에 아예 없는 id**: 아주 낡은 그림이나 로그아웃 뒤 남은 그림을 누른 경우다.
///
/// 캐시를 아예 읽지 못했으면(판 번호를 모르거나 읽기 실패) **막지 않는다** — 그때는 중복인지
/// 알 수 없고, 사용자가 누른 것을 조용히 버리는 쪽이 더 나쁘다(서버 쓰기는 멱등이다). 그래서 세
/// 조건 모두 **캐시가 분명히 말할 때만** 막는다.
TodoWidgetCheckDecision todoWidgetCheckDecisionOf({
  required TodoWidgetAction action,
  required TodoWidgetPayload? cached,
  required bool appAlive,
  required DateTime now,
}) {
  final todoId = action.todoId;
  if (todoId == null) return TodoWidgetCheckDecision.ignore;
  if (cached != null) {
    if (cached.pendingId == todoId && !_pendingExpired(cached, now)) {
      return TodoWidgetCheckDecision.ignore;
    }
    final item = cached.items.where((item) => item.id == todoId).firstOrNull;
    if (item == null || item.done == action.done) {
      return TodoWidgetCheckDecision.ignore;
    }
  }
  return appAlive
      ? TodoWidgetCheckDecision.handOff
      : TodoWidgetCheckDecision.writeHere;
}

/// `쓰는 중` 표시가 이미 효력을 잃었는지. 네이티브가 그 줄을 평소대로 그리는 기준과 같다
/// (쓰기 도중에 프로세스가 죽은 경우 다음 탭이 막히지 않아야 한다).
bool _pendingExpired(TodoWidgetPayload cached, DateTime now) {
  final at = cached.pendingAtMs;
  if (at == null) return true;
  return now.millisecondsSinceEpoch - at >=
      todoWidgetPendingTimeoutSeconds * 1000;
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
