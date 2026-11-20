// 홈 화면 투두 위젯이 읽는 기기 캐시의 내용.
//
// 설계 원칙 하나가 이 파일에 모여 있다(design.md 원칙 2): 네이티브는 그리기만 하고 판단은
// Dart가 한다. 어떤 상태인지, 어떤 문구를 쓰는지, 몇 개까지 담는지, 기준 시각을 어떻게 적는지를
// 여기서 전부 정해 JSON 하나로 적어 둔다. 네이티브(TodoWidgetProvider.kt)가 하는 판단은 **열**
// 이고 거의 전부 "비교하고 Dart가 보낸 것 중에서 고르기"다(design 원칙 2의 각주들):
//   1. 높이 → 줄 수(widgetRowCount와 같은 식)
//   2. moreFormat에 숫자 하나 끼우기
//   3. 자국이 아직 효력이 있나(60초) → `쓰는 중`을 그릴지
//   4. now >= dueAtMs → 기한 줄의 문장(due/dueOver)과 색 고르기
//   5. rank < limit → 이 항목을 그릴지(줄 자리 수는 네이티브만 아는 값이라 Dart가 순서만 굳혀
//      보낸다 — 정책은 여기, 비교 한 줄은 거기)
//   6. done → 줄 면·제목 색·취소선·체크 그림 고르기(사실은 Dart가 적어 보낸다)
//   7. (2026-11-19) 탭 순간의 기기 상태 → 낙관 모드인가 `쓰는 중` 모드인가
//   8. (2026-11-19 · 2026-11-20 추가 범위 4에서 자람) **자국마다** 효력이 있나(세 조건) +
//      묶음의 되돌림 시각(dueAtMs)이 지났나. 3의 두 갈래가 자국 배열 전체로 넓어진 것이고,
//      규칙은 이 파일의 [todoWidgetOverlayOf]에 테스트와 함께 있다
//   9. (2026-11-20) 이 탭이 중복인가 → **그 id의 가장 새 자국**과 비교 셋(같은 줄·같은 목표 값·
//      창 안쪽). **Dart에 있던 판단이 네이티브로 옮겨 간 것**이고, 규칙 자체는 이 파일의
//      isDuplicateWidgetTap에 테스트와 함께 남아 있다(네이티브는 그 규칙을 따른다)
//  10. (2026-11-20) 이 탭이 **새 묶음을 시작하는가** → engine을 깨우나 마나. 비교하는 것은
//      `now >= leaveAtMs`와 "자국 레코드가 있나"·"이 탭이 writing인가" 셋뿐이고, 그 시각을
//      **만드는** 규칙은 이 파일의 [widgetTapLeaveAt]이 들고 있다(design 8.4)
// 문장을 **만드는** 일은 한 자도 네이티브에 두지 않는다. 개수 문구(`할 일 2/5`)도 완성된 문장으로
// 실려 가고, 네이티브는 숫자를 세거나 분수를 조립하지 않는다.
//
// **캐시 키는 둘이고 각 키의 writer는 하나다(2026-11-20 추가 범위 4, design 1.1).**
//   - `todo_widget_payload` — writer는 **Dart 하나**(아래 `toJson`). 통째로 덮어쓴다.
//   - `todo_widget_tap_marks` — writer는 **네이티브 하나**(탭 자국 레코드). **Dart는 읽기만 한다**
//     ([TodoWidgetHost.readTapMarks]) — 쓰는 메서드를 만드는 순간 두 writer가 같은 키를 다투고
//     읽고-고쳐-쓰기 사이에 들어온 탭이 통째로 사라진다(= 이 범위에서 가장 잃기 쉬운 것).
// 그래서 **Dart는 자국을 지우지 않는다.** 대신 "어디까지 결말이 났는지"를 숫자 하나로 적고
// ([settledGen]) 네이티브가 `g > settledGen`인 자국만 효력 있는 것으로 본다 — "그 묶음에 들어간
// 것만 걷는다"가 **지우기가 아니라 비교**로 성립한다(design 1.3 · 4.1). 지우는 코드가 없으므로
// 지우다가 잃는 일도 없다.
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

/// 탭 자국을 **잊는** 시간(초). 네이티브는 이 시간이 지난 자국을 무시하고 그 줄을 평소대로
/// 그린다 — 쓰기 도중에 프로세스가 죽어도 "체크된 것처럼" 남지 않는다(design 4.3 · 2.2.3).
///
/// **네이티브의 `PENDING_TIMEOUT_MS`와 값이 같아야 한다**(TodoWidgetProvider.kt).
/// `todoWidgetRowPitchDp`/`ROW_PITCH_DP`와 같은 규칙이고 **테스트로 잡히지 않는다** — 어긋나면
/// 증상이 "그림이 영영 안 걷힌다"거나 "너무 일찍 걷힌다"로 나온다.
const todoWidgetPendingTimeoutSeconds = 60;

/// **중복 탭 창**(ms). 그 안에 같은 줄·같은 목표 값이 또 들어오면 네이티브가 그 탭을 버린다
/// ([isDuplicateWidgetTap] · [widgetTapMarkFresh]).
///
/// 2026-11-20(추가 범위 4)에 **이름만** 또렷해졌다(옛 `todoWidgetTapMarkFreshSeconds`의 값·뜻
/// 그대로다 — 자국의 "신선함"이 그리기에서 떨어져 나가면서 이 창은 중복 판정에만 쓰인다).
/// **네이티브의 `TAP_DUP_WINDOW_MS`와 값이 같아야 한다**(design 7장).
///
/// 0에 가까우면 런처의 중복 전달을 막지 못하고, 길면 **같은 목표 값**의 정당한 재시도까지 막는다.
const todoWidgetTapDupWindowMs = 6000;

/// **묶음의 기본 계기** — 마지막 탭에서 이만큼 멎으면 묶음이 떠난다(design 7장, spec O).
///
/// **네이티브의 `TAP_QUIET_MS`와 값이 같아야 한다.** 0.5초 아래면 "한 줄 누르고 다음 줄 찾기"라는
/// 흔한 리듬이 묶이지 않아 지금과 같아지고, 2초 위면 실패를 그만큼 늦게 안다.
const todoWidgetTapQuietMs = 1000;

/// **묶음의 상한** — 첫 탭에서 이만큼 지나면 멎지 않아도 떠난다(spec O).
///
/// **네이티브의 `TAP_BATCH_CAP_MS`와 값이 같아야 한다.** 늘리면 "아직 안 보낸 체크가 기기에만
/// 있는 시간"이 늘고 **마지막 탭에서 8초** 약속이 깨진다.
const todoWidgetTapBatchCapMs = 5000;

/// 묶음이 떠난 뒤 **쓰기에 주는 창**(ms). 핸드오프·직접 쓰기의 상한이고, 네이티브의 되돌림 시각
/// 계산에도 들어간다(`dueAtMs = leaveAtMs + 이 값 + [todoWidgetSettleGraceMs]`).
///
/// 2026-11-20에 **6초에서 5초로 조였다**(design 7장): 앞에 대기 1초가 붙었으므로 8초 약속을
/// 지키려면 그만큼 줄여야 한다. **네이티브의 `WRITE_WINDOW_MS`와 값이 같아야 한다.**
const todoWidgetWriteWindowMs = 5000;

/// 쓰기 창이 끝난 뒤 **결말 발행·그리기에 주는 여유**(ms). 0이면 Dart의 실패 발행과 네이티브의
/// 쓸어내기가 같은 순간에 겹쳐 그림이 두 번 바뀐다. **네이티브의 `SETTLE_GRACE_MS`와 같아야 한다.**
const todoWidgetSettleGraceMs = 1000;

/// 자국 레코드가 들고 있는 자국의 최대 개수. 보이는 줄이 최대 6이고 되돌림까지 두 번씩 눌러도
/// 12다. 넘으면 **오래된 것부터 버린다**(버려진 자국은 그 줄이 평소 모양으로 돌아가는 것이
/// 전부다 — 거짓 성공이 아니다). **네이티브의 `MAX_MARKS`와 같아야 한다.**
const todoWidgetMaxTapMarks = 12;

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
    this.headerAfterChecks = const [],
    this.headerAfterUnchecks = const [],
    this.centerText,
    this.note = '',
    this.noteTone = TodoWidgetNoteTone.muted,
    this.settledGen = 0,
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

  /// **이 캐시에서 완료 개수가 +1, +2, … 됐을 때의 머리 줄 문장들**(`[할 일 3/5, 할 일 4/5, …]`).
  ///
  /// 2026-11-20(추가 범위 4)에 **문장 하나에서 배열로 자랐다**(design 1.4): N줄이 **동시에** 눌릴
  /// 수 있으므로 ∓1 문장 하나로는 개수를 덮지 못한다. 네이티브는 효력 있는 자국들의 순 델타로
  /// **첨자를 골라 쓰기만** 하고(`headerAfterChecks[delta-1]`), 범위를 넘거나 키가 없으면 머리 줄을
  /// **그대로 둔다**("모르면 말하지 않는다"). 숫자를 세거나 분수를 조립하는 일은 여전히 네이티브에
  /// 없다(원칙 2).
  ///
  /// 길이는 `min(6, 미완료 개수)`다 — 자국은 **보이는 줄**에만 생기고 줄 상한이 6이므로 한 묶음이
  /// 움직일 수 있는 개수가 6을 넘지 못한다. 더 완료할 것이 없으면(전부 완료) **빈 배열**이고 캐시에
  /// 키째로 실리지 않는다 — `할 일 6/5`는 거짓이다.
  final List<String> headerAfterChecks;

  /// 같은 꼴의 **−1, −2, …** 문장들(`[할 일 1/5, 할 일 0/5]`). 길이는 `min(6, 완료 개수)`이고
  /// 완료가 0이면 빈 배열이다(되돌릴 줄이 없다).
  final List<String> headerAfterUnchecks;

  /// 이 페이로드의 **기준 시각**(= 목록을 받아온 시각). note의 시각 문장과 뜻이 같아야 하므로,
  /// 목록을 그대로 물려받는 발행([fetchFailed]·[checkFailed]·[pending])은 이 값도 물려받는다.
  final int updatedAtMs;

  /// 목록 대신 가운데에 띄울 안내. [items]가 빈 상태에서만 채운다.
  final String? centerText;

  /// 아래 한 줄. 상태 문구·기준 시각·실패 안내가 모두 여기로 모인다(완성된 문장을 넣는다).
  final String note;

  final TodoWidgetNoteTone noteTone;

  /// **어디까지 결말이 났는가**(2026-11-20 추가 범위 4, design 1.1·4.1).
  ///
  /// 탭 자국은 세대(`g`)를 하나씩 올려 가며 **별도 키**에 쌓이고, 결말 발행이 이 숫자를 그
  /// 묶음의 마지막 세대(`claimedGen`)로 올린다. 네이티브는 `g > settledGen`인 자국만 효력 있는
  /// 것으로 보므로 **"그 묶음에 들어간 것만 걷고 나머지는 남긴다"가 지우기가 아니라 비교로**
  /// 성립한다 — 결말 하나가 아직 끝나지 않은 다른 줄의 그림을 걷어 가지 않는다(spec R).
  ///
  /// **어떤 발행도 이 값을 내리지 않는다.** 내리면 이미 끝난 자국이 되살아나 눌린 그림이 다시
  /// 뜬다. 그래서 목록을 물려받는 팩토리는 직전 값을 물려받고([fetchFailed]·[checkFailed]),
  /// 목록이 없는 팩토리는 서비스가 들고 있는 값을 받는다([loggedOut]·[loading]) — 마지막
  /// 방어선은 `TodoWidgetService.publish`가 발행마다 `max`를 취하는 것이다(design 4.2).
  final int settledGen;

  final TodoWidgetTapTarget tapTarget;

  /// 네이티브가 하는 유일한 문자열 조립. 숫자 하나를 끼운다.
  static const moreFormat = AppStrings.widgetMoreFormat;

  /// 네이티브가 **자국이 지난 줄을 되돌릴 때** 머리 줄에 적는 한 줄(design 2.2.3, 조건 ①).
  ///
  /// `checkFailed`의 note와 **같은 문구**다 — 되돌림과 그 이유가 한 화면에 보여야 하고, 그 말을
  /// 할 수 있는 자리가 Dart일 때도 네이티브일 때도 같은 문장이어야 하기 때문이다. 네이티브는
  /// 고르기만 하고 문구의 출처는 여전히 `AppStrings` 하나다.
  static const failNote = AppStrings.widgetCheckFailed;

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
  /// [frontIds]는 **"방금 누른 줄들은 반드시 보인다"는 예외**를 위해 있다(spec 추가 범위 2 F,
  /// 2026-11-20에 **하나에서 순서 있는 목록으로** 자랐다 — design 6.2). 그 줄이 밀려 사라지면
  /// "체크하면 사라진다"로 되돌아가 요구가 무의미해진다. 그래서 들어온 **순서대로 rank 0,1,…**을
  /// 주고(어떤 줄 자리 수에서도 보이려면 앞 번호여야 한다) 완료 줄이면 캐시 상한 안에 반드시
  /// 담는다. **목록에 없는 id가 섞여 있어도 무해하다**(그냥 건너뛴다).
  ///
  /// 앞자리를 **실패한 줄 → 이번에 성공한 줄** 순서로 채우는 것이 spec S의 요구다("되돌아간 줄이
  /// 보이는 자리를 먼저 받는다"). 그 순서를 만드는 것은 부르는 쪽이고 여기서는 받은 순서를 쓴다.
  ///
  /// [failedCheck]가 참이면 note가 **실패 한 줄**(`체크하지 못했어요 · 앱에서 확인해요`)이 되고
  /// 톤이 `danger`가 된다. 개수를 넣지 않는다(오너 확정 2) — 몇 개가 실패했는지는 되돌아간 줄이
  /// 이미 화면에서 말한다.
  ///
  /// [basisAt]은 **목록의 나이**다(epoch 밀리초). 주지 않으면 [now]다.
  ///
  /// 위젯 체크의 결말을 만들 때 쓴다(design 4.7 (2)): 체크는 목록을 **새로 받아온 것이 아니므로**
  /// `updatedAtMs`와 `… 기준` 문장이 직전 발행의 값 그대로여야 한다. 재조회를 없앴으면
  /// "지금 받아왔다"고 말하지 않는다 — 이것이 K가 치르는 정직성의 값이다.
  ///
  /// 기한 문장(`formatWidgetDue`)은 **[now]로 만든다.** 그것은 "오늘인가"를 가르는 기기 시계이지
  /// 목록의 나이가 아니다.
  factory TodoWidgetPayload.fromTodos(
    List<Todo> todos, {
    required DateTime now,
    List<String> frontIds = const [],
    bool failedCheck = false,
    int settledGen = 0,
    int? basisAt,
  }) {
    final at = basisAt ?? now.millisecondsSinceEpoch;
    if (todos.isEmpty) {
      return TodoWidgetPayload(
        items: const [],
        totalCount: 0,
        updatedAtMs: at,
        centerText: AppStrings.widgetEmpty,
        settledGen: settledGen,
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
    final keptDone = _keepDone(done, frontIds);
    final keptUndone = undone.take(todoWidgetMaxItems).toList();
    final ranks = _ranksOf(
      undone: keptUndone,
      keptDone: keptDone,
      frontIds: frontIds,
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
      settledGen: settledGen,
      // N줄이 **동시에** 눌릴 수 있으므로 ∓1 문장 하나로는 개수를 덮지 못한다(design 1.4).
      // 상한이 6인 근거: 자국은 보이는 줄에만 생기고 줄 상한이 6이다. 움직일 것이 없는 쪽은
      // **빈 배열**이고 캐시에 키째로 실리지 않는다.
      headerAfterChecks: [
        for (var k = 1; k <= _headerStepsOf(undone.length); k++)
          AppStrings.widgetHeaderCount(
            done: done.length + k,
            total: todos.length,
          ),
      ],
      headerAfterUnchecks: [
        for (var k = 1; k <= _headerStepsOf(done.length); k++)
          AppStrings.widgetHeaderCount(
            done: done.length - k,
            total: todos.length,
          ),
      ],
      // 하나라도 실패했으면 **실패 한 줄**이 모든 것을 덮는다(개수를 넣지 않는다 — spec S).
      // 전부 완료면 그 사실을 note로 말한다(문구는 그대로 재사용하고 자리만 옮겼다).
      note: failedCheck
          ? AppStrings.widgetCheckFailed
          : undone.isEmpty
              ? AppStrings.widgetAllDone
              : AppStrings.widgetNoteFresh(
                  formatWidgetTime(DateTime.fromMillisecondsSinceEpoch(at)),
                ),
      noteTone: failedCheck
          ? TodoWidgetNoteTone.danger
          : TodoWidgetNoteTone.muted,
    );
  }

  /// 대체 머리 줄 배열의 길이. 한 묶음이 움직일 수 있는 개수는 **보이는 줄 수**를 넘지 못한다
  /// (자국은 보이는 줄에만 생긴다 — design 1.4).
  static int _headerStepsOf(int count) =>
      count < todoWidgetMaxRows ? count : todoWidgetMaxRows;

  /// 상태 1 — 로그인하지 않음. 이전 사용자의 내용을 **즉시 지운다**(키를 지우지 않고 덮어쓴다).
  /// [settledGen]은 **내리지 않기 위해** 받는다(design 4.2) — 목록이 없는 갈래라 물려받을 직전이
  /// 없으므로 서비스가 들고 있는 값을 넘겨 준다.
  factory TodoWidgetPayload.loggedOut({
    required DateTime now,
    int settledGen = 0,
  }) {
    return TodoWidgetPayload(
      items: const [],
      totalCount: 0,
      updatedAtMs: now.millisecondsSinceEpoch,
      centerText: AppStrings.widgetLoggedOut,
      settledGen: settledGen,
      tapTarget: TodoWidgetTapTarget.login,
    );
  }

  /// 상태 2 — 로그인 직후 첫 조회 중. 로그아웃 캐시가 로그인한 사용자에게 잠깐 보이는 것을 막는다.
  factory TodoWidgetPayload.loading({
    required DateTime now,
    int settledGen = 0,
  }) {
    return TodoWidgetPayload(
      items: const [],
      totalCount: 0,
      updatedAtMs: now.millisecondsSinceEpoch,
      centerText: AppStrings.widgetLoading,
      settledGen: settledGen,
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
      // 줄이 그대로 보이는 상태이므로 그 줄을 누를 수 있다 → 대체 문장도 그대로 물려받는다.
      headerAfterChecks: previous.headerAfterChecks,
      headerAfterUnchecks: previous.headerAfterUnchecks,
      // **내리지 않는다**(design 4.2) — 내리면 이미 끝난 자국이 되살아난다.
      settledGen: previous.settledGen,
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
        settledGen: previous?.settledGen ?? 0,
      );
    }
    return TodoWidgetPayload(
      items: previous.items,
      totalCount: previous.totalCount,
      updatedAtMs: previous.updatedAtMs,
      // 서버 반영에 실패한 체크를 성공으로 센 숫자를 적지 않는다 — 직전 값을 그대로 쓴다.
      header: previous.header,
      headerAfterChecks: previous.headerAfterChecks,
      headerAfterUnchecks: previous.headerAfterUnchecks,
      settledGen: previous.settledGen,
      note: AppStrings.widgetCheckFailed,
      noteTone: TodoWidgetNoteTone.danger,
      tapTarget: previous.tapTarget,
    );
  }

  /// 서버 쓰기가 **끝난 뒤**, 목록을 다시 받지 않고 **그 체크만큼만** 고친 캐시를 만든다
  /// (design 4.7 (2)의 경로 B = 앱이 죽어 있을 때).
  ///
  /// **낙관적 반영(L)과 혼동하지 말 것.** 이 함수는 서버 쓰기가 끝난 뒤에만 불리므로 **거짓 성공
  /// 위험이 없다.** 낙관 그림은 네이티브가 탭 순간에 그리는 것이고(캐시를 고치지 않는다) 이쪽은
  /// 결말이다.
  ///
  /// **2026-11-20(추가 범위 4): 한 줄에서 묶음으로 자랐다**(design 6.2). 한 번의 저장 계기에
  /// 여러 줄이 들어오고 그중 일부만 성공할 수 있으므로, 이 함수가 **줄마다 다른 결말**을 한
  /// 발행으로 그린다 — 성공한 줄은 선이 그어진 채 남고 실패한 줄만 원래 모양으로 되돌아간다
  /// (spec S). 안내는 **한 줄뿐이고 개수를 넣지 않는다**(오너 확정 2).
  ///
  /// 고치는 것은 표 그대로다:
  /// - **성공한** 줄의 `done`을 목표 값으로. 완료가 되면 **기한 키 셋이 빠진다**(완료 줄에는
  ///   기한을 싣지 않는다는 규칙을 Dart가 캐시에서 끝낸다). 되돌릴 때 기한을 되살릴 재료는 캐시에
  ///   없다 — **받아들이는 한계**이고 1~2초 뒤 보정 발행이 돌려준다.
  /// - **실패한** 줄은 손대지 않는다(= 낙관 그림이 걷히며 되돌아간다. [settledGen]이 그 자국의
  ///   효력을 없애는 것이 되돌림의 실제 수단이다).
  /// - `totalCount`(미완료 전체)를 **순 델타만큼** 움직인다(완료 −1, 되돌리기 +1씩). **보이는
  ///   미완료도 같은 수만큼 줄므로 `그 외 N개`는 그대로다** — "그 체크들만큼만"의 핵심이다.
  /// - 머리 줄은 [headerAfterChecks]/[headerAfterUnchecks]에서 **첨자로 고르기만** 한다(범위를
  ///   넘거나 배열이 없으면 직전 그대로 — "모르면 말하지 않는다").
  /// - `rank`를 다시 매긴다: **실패한 줄 → 이번에 성공한 줄 → 나머지 미완료 → 나머지 완료.**
  ///   실패한 줄이 앞자리를 먼저 받는 것이 spec S의 요구다(되돌림과 이유가 같은 화면에).
  /// - **배열 순서는 손대지 않는다**(그리는 순서 = position. 체크한 줄이 제자리에 남는 근거다).
  /// - `updatedAtMs`는 직전 값 그대로. 체크가 목록을 새것으로 만들지 않는다.
  /// - `settledGen`을 [settledGen](= `claimedGen`)으로 올린다. **실패한 자국도 효력을 잃어야**
  ///   되돌아가므로 성공·실패를 가리지 않고 같은 숫자를 적는다.
  ///
  /// 지름길이 성립하지 않으면 **null**을 준다(캐시 없음·줄 없는 안내 화면·결과가 빈 목록·캐시에
  /// 없는 id뿐). 그때는 부르는 쪽이 느린 길(목록 재조회)로 되돌아간다.
  static TodoWidgetPayload? applyChecks(
    TodoWidgetPayload? cached, {
    required List<TodoWidgetCheckResult> results,
    required int settledGen,
  }) {
    if (cached == null || !cached.hasItems || results.isEmpty) return null;
    final byId = {for (final item in cached.items) item.id: item};
    final applied = [
      for (final result in results)
        if (byId.containsKey(result.id)) result,
    ];
    if (applied.isEmpty) return null;

    final targets = <String, bool>{
      for (final result in applied)
        if (result.ok) result.id: result.done,
    };
    final failedIds = [
      for (final result in applied)
        if (!result.ok) result.id,
    ];
    final checkedIds = [
      for (final result in applied)
        if (result.ok) result.id,
    ];

    var delta = 0;
    final items = [
      for (final item in cached.items)
        if (targets[item.id] case final done? when done != item.done)
          // 완료가 되는 줄에서는 기한 키 셋이 빠진다(되돌아가는 줄에는 애초에 없었다).
          TodoWidgetItem(
            id: item.id,
            title: item.title,
            rank: item.rank,
            done: done,
          )
        else
          item,
    ];
    for (final item in cached.items) {
      if (targets[item.id] case final done? when done != item.done) {
        delta += done ? 1 : -1;
      }
    }

    // 실패한 줄이 보이는 자리를 **먼저** 받는다(spec S). 그 뒤가 이번에 성공한 줄이다.
    final ranks = <String, int>{};
    for (final id in [...failedIds, ...checkedIds]) {
      ranks.putIfAbsent(id, () => ranks.length);
    }
    for (final item in items) {
      if (!item.done) ranks.putIfAbsent(item.id, () => ranks.length);
    }
    for (final item in items) {
      ranks.putIfAbsent(item.id, () => ranks.length);
    }

    final totalCount = cached.totalCount - delta;
    final basisAt = DateTime.fromMillisecondsSinceEpoch(cached.updatedAtMs);
    final failed = failedIds.isNotEmpty;
    return TodoWidgetPayload(
      items: [
        for (final item in items)
          TodoWidgetItem(
            id: item.id,
            title: item.title,
            rank: ranks[item.id] ?? item.rank,
            done: item.done,
            due: item.due,
            dueOver: item.dueOver,
            dueAtMs: item.dueAtMs,
          ),
      ],
      totalCount: totalCount < 0 ? 0 : totalCount,
      updatedAtMs: cached.updatedAtMs,
      header: _headerAfter(cached, delta),
      // 대체 문장 배열은 셀 목록이 손에 없어 다시 만들 수 없다. 싣지 않으면 네이티브가 머리 줄을
      // 그대로 두므로(design 1.4) 거짓이 생기지 않고, 1~2초 뒤 보정 발행이 채워 준다.
      note: failed
          ? AppStrings.widgetCheckFailed
          : _noteAfterCheck(cached, totalCount, basisAt),
      noteTone: failed ? TodoWidgetNoteTone.danger : TodoWidgetNoteTone.muted,
      settledGen: settledGen,
      tapTarget: cached.tapTarget,
    );
  }

  /// 순 델타로 대체 머리 줄을 **고른다**(design 1.4). 범위를 넘거나 배열이 없으면 직전 그대로다.
  static String _headerAfter(TodoWidgetPayload cached, int delta) {
    final sentences = delta > 0
        ? cached.headerAfterChecks
        : cached.headerAfterUnchecks;
    final index = (delta > 0 ? delta : -delta) - 1;
    if (delta == 0 || index >= sentences.length) return cached.header;
    return sentences[index];
  }

  /// 체크가 성공한 뒤의 note. 상태 3 ↔ 3b 전이와 "앞선 실패가 지워진다"를 이 경로에서도 지킨다.
  ///
  /// `못 불러왔어요 · … 기준`은 **그대로 남긴다** — 체크가 성공했다고 목록이 새것이 되지는 않는다.
  /// 반대로 직전이 `danger`(= 앞선 체크 실패)였으면 그 문장을 **지운다**: 성공한 화면에 `체크하지
  /// 못했어요`를 색만 내려 남겨 두면 그것이 더 나쁜 거짓말이다(design 4.7 (2)의 근거 그대로).
  static String _noteAfterCheck(
    TodoWidgetPayload cached,
    int totalCount,
    DateTime basisAt,
  ) {
    if (totalCount <= 0) return AppStrings.widgetAllDone;
    if (cached.note == AppStrings.widgetAllDone ||
        cached.noteTone == TodoWidgetNoteTone.danger) {
      return AppStrings.widgetNoteFresh(formatWidgetTime(basisAt));
    }
    return cached.note;
  }

  /// **null인 키는 아예 넣지 않는다.** 안드로이드(AOSP)의 `org.json`은 upstream과 달라
  /// `optString(name, fallback)`이 **명시적 null에는 fallback이 아니라 `"null"` 네 글자**를
  /// 돌려준다(fallback은 키가 아예 없을 때만 쓰인다). 그래서 `centerText: null`을 그대로 실으면
  /// 정상 상태에서 위젯 가운데에 `null`이 뜬다. 네이티브도 `isNull`을 먼저 검사하지만, 한쪽이
  /// 바뀌어도 깨지지 않게 두 곳 모두에서 막는다. `fromJson`은 키가 없으면 null로 읽는다.
  Map<String, dynamic> toJson() => {
        'v': todoWidgetSchemaVersion,
        'header': header,
        // **빈 배열이면 키째로 싣지 않는다**(없으면 네이티브가 머리 줄을 그대로 둔다 — design 1.4).
        if (headerAfterChecks.isNotEmpty) 'headerAfterChecks': headerAfterChecks,
        if (headerAfterUnchecks.isNotEmpty)
          'headerAfterUnchecks': headerAfterUnchecks,
        'items': items.map((item) => item.toJson()).toList(),
        'totalCount': totalCount,
        if (centerText != null) 'centerText': centerText,
        'note': note,
        'noteTone': noteTone.name,
        // 이 둘은 앱 판마다 고정인 문구다. 캐시에 실어 보내는 이유는 네이티브가 한국어 문자열을
        // 따로 갖지 않게 하기 위함이다(문구의 출처는 언제나 AppStrings 하나다).
        'moreFormat': moreFormat,
        'pendingLabel': AppStrings.widgetPendingLabel,
        'failNote': failNote,
        // **탭 자국은 이 JSON에 한 자도 없다**(2026-11-20 추가 범위 4). 자국은 **별도 키**
        // (`todo_widget_tap_marks`)에 있고 그 키의 writer는 네이티브 하나다(design 1.1). Dart가
        // 자국을 지우는 대신 "어디까지 결말이 났는지"를 아래 숫자로 적어 **그 묶음에 들어간
        // 자국만** 효력을 잃게 한다 — 결말 하나가 아직 끝나지 않은 다른 줄을 걷어 가지 않는다.
        'settledGen': settledGen,
        'tapTarget': tapTarget.name,
        'updatedAtMs': updatedAtMs,
      };

  String encode() => jsonEncode(toJson());

  /// **보이는 지문**(2026-11-20 추가 범위 4, design 5.2). `toJson()`에서 [updatedAtMs]를 뺀 것이다.
  ///
  /// 지문이 같으면 **화면에 달라질 것이 없다** → 다시 그리라는 브로드캐스트를 보내지 않는다
  /// (`TodoWidgetService.publish`). 발행 시각만 다른 보정 발행이 같은 그림을 한 번 더 그려
  /// 번쩍이던 것이 그것 때문이었다 — `updatedAtMs`는 화면에 나오지 않고, 사람이 읽는 기준 시각은
  /// [note] 문장이 들고 있다.
  ///
  /// **`settledGen`은 지문에 들어간다**(빼지 말 것): 자국을 걷는 발행은 **보이는 변화**(실패한
  /// 줄의 되돌림)를 함께 들고 오므로 반드시 그려야 한다. 뒤따르는 보정은 같은 `settledGen`을
  /// 실어 지문이 같아지므로 조용히 지나간다.
  String fingerprint() => jsonEncode(toJson()..remove('updatedAtMs'));

  /// [settledGen]만 바꾼 사본. **올리는 데만 쓴다**(`TodoWidgetService.publish`가 발행마다
  /// `max`를 취하는 마지막 방어선 — design 4.2). 값이 같으면 자기 자신을 돌려준다.
  TodoWidgetPayload withSettledGen(int gen) {
    if (gen == settledGen) return this;
    return TodoWidgetPayload(
      items: items,
      totalCount: totalCount,
      updatedAtMs: updatedAtMs,
      header: header,
      headerAfterChecks: headerAfterChecks,
      headerAfterUnchecks: headerAfterUnchecks,
      centerText: centerText,
      note: note,
      noteTone: noteTone,
      settledGen: gen,
      tapTarget: tapTarget,
    );
  }

  /// 대체 머리 줄 배열을 되읽는다. 배열이 아니거나 문자열이 아닌 것이 섞이면 **그 칸만** 버린다.
  static List<String> _sentencesOf(Object? raw) {
    if (raw is! List) return const [];
    return [
      for (final value in raw)
        if (value is String && value.isNotEmpty) value,
    ];
  }

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
    final settledGen = json['settledGen'];
    return TodoWidgetPayload(
      items: items,
      totalCount: totalCount,
      updatedAtMs: updatedAtMs,
      // 옛 캐시(header 키가 없다)는 `할 일`로 읽는다 — 네이티브가 그때 레이아웃 기본값을 남기는
      // 것과 같은 뜻이다(개수를 모르면 말하지 않는다. design 2.2.2).
      header: header is String && header.isNotEmpty
          ? header
          : AppStrings.widgetHeader,
      // 옛 캐시에는 배열이 없다 → 빈 배열로 읽히고 네이티브는 머리 줄을 그대로 둔다(거짓이
      // 아니다 — design 1.4의 호환 서술).
      headerAfterChecks: _sentencesOf(json['headerAfterChecks']),
      headerAfterUnchecks: _sentencesOf(json['headerAfterUnchecks']),
      centerText: centerText is String ? centerText : null,
      note: note is String ? note : '',
      noteTone: json['noteTone'] == TodoWidgetNoteTone.danger.name
          ? TodoWidgetNoteTone.danger
          : TodoWidgetNoteTone.muted,
      settledGen: settledGen is int ? settledGen : 0,
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
  /// **방금 누른 줄들은 반드시 담는다**(design 1.4·6.2): [frontIds]의 완료 줄에게 상한을 먼저
  /// 나눠 주고 남은 자리를 position 순서로 채운다. 담는 것은 **집합**이고, 돌려주는 리스트는
  /// 다시 [done]의 순서(= position)로 걸러 내므로 **배열이 position 순서를 유지한다.**
  static List<Todo> _keepDone(List<Todo> done, List<String> frontIds) {
    if (done.length <= todoWidgetMaxDoneItems) return done;
    final keptIds = <String>{};
    for (final todo in done) {
      if (keptIds.length >= todoWidgetMaxDoneItems) break;
      if (frontIds.contains(todo.id)) keptIds.add(todo.id);
    }
    for (final todo in done) {
      if (keptIds.length >= todoWidgetMaxDoneItems) break;
      keptIds.add(todo.id);
    }
    return [
      for (final todo in done)
        if (keptIds.contains(todo.id)) todo,
    ];
  }

  /// 항목마다 **줄 자리 우선순위**를 매긴다(design 2.2.2):
  ///
  /// ```
  /// 0, 1, …  : frontIds (들어온 순서. 캐시에 담긴 줄만)
  /// 그 뒤    : 미완료, position 순서
  /// 그 뒤    : 나머지 완료, position 순서
  /// ```
  ///
  /// 자리 수(줄 수)는 런처가 주는 높이에서 나와 **네이티브만 아는 값**이다. 그래서 Dart가 최종
  /// 선택을 끝낼 수 없고, 대신 순서를 숫자로 굳혀 보내 네이티브가 `rank < limit` 하나만 비교하게
  /// 한다 — 정책은 여기 남고 네이티브에는 비교 한 줄이 간다.
  static Map<String, int> _ranksOf({
    required List<Todo> undone,
    required List<Todo> keptDone,
    required List<String> frontIds,
  }) {
    final ranks = <String, int>{};
    if (frontIds.isNotEmpty) {
      // 캐시에 담기는 줄만 앞자리를 받는다 — 담기지도 않는 id에 rank를 주면 그 자리가 빈다.
      final kept = {
        for (final todo in undone) todo.id,
        for (final todo in keptDone) todo.id,
      };
      for (final id in frontIds) {
        if (kept.contains(id)) ranks.putIfAbsent(id, () => ranks.length);
      }
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

/// 묶음이 **서버에 쓸 줄 하나**(design 4.1). 결과는 아직 없다 — 쓰고 나서 [TodoWidgetCheckResult]가
/// 된다.
class TodoWidgetCheckTarget {
  const TodoWidgetCheckTarget({required this.id, required this.done});

  final String id;

  /// **목표 값**(토글이 아니다 — design 4.6 (1)).
  final bool done;

  @override
  bool operator ==(Object other) =>
      other is TodoWidgetCheckTarget && other.id == id && other.done == done;

  @override
  int get hashCode => Object.hash(id, done);

  @override
  String toString() => 'TodoWidgetCheckTarget($id, done: $done)';
}

/// 위젯에서 누른 체크 **한 줄의 결과**(design 6.2). [ok]가 거짓이면 서버에 닿지 못한 줄이고,
/// 그 줄은 결말에서 **원래 모양으로 되돌아간다**(목표 값을 적용하지 않는다).
class TodoWidgetCheckResult {
  const TodoWidgetCheckResult({
    required this.id,
    required this.done,
    required this.ok,
  });

  final String id;

  /// **목표 값**(토글이 아니다 — design 4.6 (1)).
  final bool done;

  /// 서버 쓰기가 끝났는가.
  final bool ok;

  @override
  bool operator ==(Object other) =>
      other is TodoWidgetCheckResult &&
      other.id == id &&
      other.done == done &&
      other.ok == ok;

  @override
  int get hashCode => Object.hash(id, done, ok);

  @override
  String toString() =>
      'TodoWidgetCheckResult($id, done: $done, ${ok ? 'ok' : 'fail'})';
}

/// [todos]에서 [results] 중 **성공한 줄들**의 완료 여부만 목표 값으로 바꾼 **새 목록**을 돌려준다
/// (순서·나머지 필드는 그대로). 목록에 없는 id는 그냥 건너뛴다.
///
/// 위젯 체크의 결말을 **목록을 다시 받지 않고** 만들기 위한 것이다(design 4.7 (2)의 경로 A):
/// 앱이 이미 들고 있는 목록에서 그 줄들만 바꿔 `fromTodos`에 넣는다. `Todo`에 `copyWith`를
/// 만들지 않는 이유는 위젯 때문에 모델을 건드리지 않기 위해서다.
///
/// 2026-11-20(추가 범위 4)에 **한 줄에서 여러 줄로** 자랐다(옛 `todosWithDone`).
List<Todo> todosWithChecks(
  List<Todo> todos,
  List<TodoWidgetCheckResult> results,
) {
  final targets = <String, bool>{
    for (final result in results)
      if (result.ok) result.id: result.done,
  };
  if (targets.isEmpty) return todos;
  return [
    for (final todo in todos)
      if (targets[todo.id] case final done?)
        Todo(
          id: todo.id,
          title: todo.title,
          isDone: done,
          createdAt: todo.createdAt,
          dueAt: todo.dueAt,
        )
      else
        todo,
  ];
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
  /// 아무 일도 하지 않는다 — 체크가 아닌 Uri, 목록에 없는 id, 이미 목표 값인 줄.
  /// (중복 탭을 버리는 일은 네이티브가 한다 — [isDuplicateWidgetTap].)
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
/// 캐시를 보는 이유는 **둘**이다(design 4.3의 2번 · 4.6 (2)):
///   - **이미 목표 값인 줄**: 아무것도 바꾸지 않는 쓰기를 서버에 보내지 않고, 그 때문에 `쓰는 중`이
///     깜빡이지도 않게 한다. 완료 줄이 목록에 남게 된 뒤로는 **"없어짐"이 더 이상 성공의 표시가
///     아니어서**(2026-11-18 추가 범위 2) 옛 조건을 이 조건으로 바꿨다.
///   - **목록에 아예 없는 id**: 아주 낡은 그림이나 로그아웃 뒤 남은 그림을 누른 경우다.
///
/// **중복 탭은 여기서 가르지 않는다**(2026-11-20에 네이티브로 옮겼다 — [isDuplicateWidgetTap]).
/// 네이티브가 탭 자국을 `commit()`한 **뒤에** 이 isolate를 깨우므로 여기서 읽는 `pendingId`는
/// 언제나 **이번 탭의 것**이고, 그것으로 중복을 가르면 **모든 탭이 버려진다**(그 회귀가 실제로
/// 났다: 위젯 체크가 서버에 하나도 쓰이지 않고 7초 뒤 되돌아갔다). 그래서 이 함수는 자국을
/// **아예 보지 않고**, 기준 시각도 **인자로 받지 않는다** — 자국의 나이를 볼 수 없는 것이
/// 시그니처로 못 박혀 있다.
///
/// 캐시를 아예 읽지 못했으면(판 번호를 모르거나 읽기 실패) **막지 않는다** — 사용자가 누른 것을
/// 조용히 버리는 쪽이 더 나쁘다(서버 쓰기는 멱등이다). 그래서 두 조건 모두 **캐시가 분명히 말할
/// 때만** 막는다.
TodoWidgetCheckDecision todoWidgetCheckDecisionOf({
  required TodoWidgetAction action,
  required TodoWidgetPayload? cached,
  required bool appAlive,
}) {
  final todoId = action.todoId;
  if (todoId == null) return TodoWidgetCheckDecision.ignore;
  if (cached != null) {
    final item = cached.items.where((item) => item.id == todoId).firstOrNull;
    if (item == null || item.done == action.done) {
      return TodoWidgetCheckDecision.ignore;
    }
  }
  return appAlive
      ? TodoWidgetCheckDecision.handOff
      : TodoWidgetCheckDecision.writeHere;
}

/// **중복 탭인가.** 자국(mark)과 이번 탭을 비교하는 규칙 하나다.
///
/// **이 규칙을 실제로 쓰는 자리는 네이티브다**(`TodoWidgetProvider.onCheckTap` →
/// `isDuplicateTap`). 탭을 처음 보는 자리도, 자국을 쓰는 자리도 거기이므로 판정도 거기 있어야
/// 한다(2026-11-20). Dart에 이 함수가 있는 이유는 하나다 — **네이티브는 유닛 테스트가 없으므로
/// 규칙만 순수 함수로 뽑아 여기서 고정**하고 네이티브가 그것을 그대로 따르게 묶는 것이다
/// (`ROW_PITCH_DP`·`TAP_MARK_FRESH_MS`와 같은 방식. 바꿀 때는 **양쪽을 함께** 바꾼다).
///
/// 규칙은 셋이 모두 맞을 때만 중복이다:
///   - 같은 줄([markId] == [tapId]),
///   - **같은 목표 값**([markDone] == [tapDone]),
///   - 자국이 아직 **신선하다**([markFresh] — [widgetTapMarkFresh], 네이티브의 `Mark.FRESH`).
///
/// **방향이 다른 탭은 중복이 아니다.** 낙관적 반영 때문에 사용자는 이미 바뀐 줄을 보고 있고, 그
/// 줄을 다시 누르는 것은 "되돌리겠다"는 뜻이다 — 막으면 되돌리기가 6초 동안 먹지 않는다.
///
/// **이 판정을 `todoWidgetCheckDecisionOf`에 두면 안 된다**(2026-11-20 회귀의 원인): 네이티브가
/// 자국을 `commit()`한 **뒤에** 백그라운드 Dart를 깨우므로, 그 자리에서 읽는 자국은 언제나
/// **이번 탭의 것**이고 모든 탭이 중복으로 버려진다.
bool isDuplicateWidgetTap({
  required String? markId,
  required bool markDone,
  required bool markFresh,
  required String tapId,
  required bool tapDone,
}) {
  if (!markFresh || markId == null) return false;
  return markId == tapId && markDone == tapDone;
}

/// 자국이 아직 **중복 탭 창 안쪽인지**. 쓰기 도중에 프로세스가 죽어 자국만 남은 경우 다음 탭이
/// 영영 막히지 않아야 하므로 창에 상한을 둔다.
///
/// 2026-11-19에 창이 60초에서 **6초**로 좁아졌고(결말이 정상 2~4초에 오므로 60초짜리 창은
/// "결말을 보고 다시 누른 탭"까지 막는다), 2026-11-20에 그 창이 **중복 판정 전용**이 되면서
/// 이름이 [todoWidgetTapDupWindowMs]로 또렷해졌다. 네이티브의 `TAP_DUP_WINDOW_MS`와 같은 값이고,
/// 그 비교를 하는 자리가 `isDuplicateTap`이다.
bool widgetTapMarkFresh({required int? markAtMs, required DateTime now}) {
  if (markAtMs == null) return false;
  return now.millisecondsSinceEpoch - markAtMs < todoWidgetTapDupWindowMs;
}

/// **탭 자국 하나**(design 1.2). 네이티브가 `todo_widget_tap_marks` 키에 적고 Dart는 읽기만 한다.
class TodoWidgetTapMark {
  const TodoWidgetTapMark({
    required this.gen,
    required this.id,
    required this.done,
    required this.atMs,
    this.writing = false,
  });

  /// 그 자국의 **세대**. 단조 증가하고, `gen <= payload.settledGen`이면 효력이 없다(결말이 났다).
  final int gen;

  final String id;

  /// **목표 값**.
  final bool done;

  /// 찍힌 시각(epoch 밀리초).
  final int atMs;

  /// `writing` 모드 자국 = **낙관 반영이 꺼진 탭**(절전·비행기·데이터 세이버). 그 줄은 완료 모양으로
  /// 뒤집지 않고 체크 칸 자리에 `쓰는 중`을 그린다.
  ///
  /// **모드를 묶음이 아니라 자국마다 드는 이유**: 모드가 바뀌는 순간에는 모드가 다른 자국이 섞여
  /// 있을 수 있고, 그리기는 **줄마다** 결정된다(design 1.2).
  final bool writing;

  @override
  String toString() =>
      'TodoWidgetTapMark(g$gen, $id, done: $done, '
      '${writing ? 'writing' : 'optimistic'})';
}

/// **탭 자국 레코드 하나**(design 1.2). 지금 모으는 묶음의 시각들과 자국 배열이다.
class TodoWidgetTapMarks {
  const TodoWidgetTapMarks({
    required this.gen,
    required this.batchAtMs,
    required this.lastAtMs,
    required this.leaveAtMs,
    required this.dueAtMs,
    required this.marks,
  });

  /// 마지막 자국의 세대.
  final int gen;

  /// 지금 모으는 묶음의 **첫 탭** 시각.
  final int batchAtMs;

  /// **마지막 탭** 시각.
  final int lastAtMs;

  /// **떠날 시각**([widgetTapLeaveAt]). Dart 일꾼이 그때까지 기다린다.
  final int leaveAtMs;

  /// **되돌릴 시각**([widgetTapDueAt]). 그때까지 결말이 오지 않으면 효력 있는 자국 전부가
  /// 되돌아가고 실패 한 줄이 뜬다.
  final int dueAtMs;

  /// 오래된 것이 앞인 자국 배열.
  final List<TodoWidgetTapMark> marks;

  /// 그 줄의 **가장 새 자국**. 중복 탭 판정([isDuplicateWidgetTap])의 입력이다.
  TodoWidgetTapMark? latestFor(String id) {
    TodoWidgetTapMark? found;
    for (final mark in marks) {
      if (mark.id != id) continue;
      if (found == null || mark.gen >= found.gen) found = mark;
    }
    return found;
  }
}

/// 자국 레코드 JSON을 되읽는다. **네이티브의 `readMarks`와 같은 방어를 한다**(키 없음·빈 문자열·
/// 모양 어긋남 → null). 모르는 키가 섞여 있어도 깨지지 않는다.
TodoWidgetTapMarks? todoWidgetMarksOf(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException {
    return null;
  }
  if (decoded is! Map) return null;
  final gen = decoded['gen'];
  final batchAtMs = decoded['batchAtMs'];
  final lastAtMs = decoded['lastAtMs'];
  final leaveAtMs = decoded['leaveAtMs'];
  final dueAtMs = decoded['dueAtMs'];
  final rawMarks = decoded['marks'];
  if (gen is! int ||
      batchAtMs is! int ||
      lastAtMs is! int ||
      leaveAtMs is! int ||
      dueAtMs is! int ||
      rawMarks is! List) {
    return null;
  }
  final marks = <TodoWidgetTapMark>[];
  for (final entry in rawMarks) {
    if (entry is! Map) continue;
    final id = entry['id'];
    final at = entry['at'];
    final markGen = entry['g'];
    if (id is! String || id.isEmpty || at is! int || markGen is! int) continue;
    marks.add(
      TodoWidgetTapMark(
        gen: markGen,
        id: id,
        // 없으면 완료로 읽는다(네이티브의 `optBoolean("done", true)`와 같은 기준).
        done: entry['done'] != false,
        atMs: at,
        writing: entry['w'] == true,
      ),
    );
  }
  return TodoWidgetTapMarks(
    gen: gen,
    batchAtMs: batchAtMs,
    lastAtMs: lastAtMs,
    leaveAtMs: leaveAtMs,
    dueAtMs: dueAtMs,
    marks: marks,
  );
}

/// **묶음이 떠날 시각** = `min(마지막 탭 + 1초, 첫 탭 + 5초)`(design 7장, spec O).
///
/// 네이티브의 `markTap`이 탭마다 이 식으로 다시 계산하고, Dart 일꾼은 그 값까지 기다린다.
/// **상한이 식 안에 있는 것이 "어느 계기도 오지 않는 경로가 없다"는 보장이다** — 기기 시간만
/// 재므로 외부 신호가 필요 없다. 네이티브와 **같은 상수**를 쓴다
/// ([todoWidgetTapQuietMs]·[todoWidgetTapBatchCapMs]).
int widgetTapLeaveAt({required int batchAtMs, required int lastAtMs}) {
  final quiet = lastAtMs + todoWidgetTapQuietMs;
  final cap = batchAtMs + todoWidgetTapBatchCapMs;
  return quiet < cap ? quiet : cap;
}

/// **되돌릴 시각** = 떠날 시각 + 쓰기 창 + 여유 ≈ 마지막 탭 + 7초(design 7장).
///
/// 네이티브가 쓸어내기 알람을 **이 절대 시각**에 걸고, 그 시각이 지나면 효력 있는 자국 전부를
/// 되돌리며 실패 한 줄을 적는다.
int widgetTapDueAt(int leaveAtMs) =>
    leaveAtMs + todoWidgetWriteWindowMs + todoWidgetSettleGraceMs;

/// 자국들이 그리기에 주는 **겹침**(design 1.5). 네이티브가 `render`에서 한 번 만들고 **네 자리**가
/// 이것만 본다 — 줄 그리기, `그 외 N개`의 기준(`undoneShown`), `totalCount` 보정, 머리 줄.
/// **하나라도 빠지면 숫자가 어긋난다.**
class TodoWidgetOverlay {
  const TodoWidgetOverlay({
    this.flips = const {},
    this.writingIds = const {},
    this.doneDelta = 0,
    this.lapsed = false,
  });

  /// 낙관으로 **뒤집어 그릴** 줄들(id → 목표 값).
  final Map<String, bool> flips;

  /// 체크 칸 자리에 `쓰는 중`을 그릴 줄들. **뒤집지 않는다**(낙관이 꺼진 탭이다).
  final Set<String> writingIds;

  /// Σ(flips: 완료 +1 / 되돌리기 −1). `totalCount − doneDelta`가 보정된 미완료 전체 개수이고,
  /// 머리 줄은 이 숫자로 문장을 고른다.
  final int doneDelta;

  /// **되돌릴 시각이 지났다** — 효력 있던 자국 전부를 걷고 실패 한 줄을 적는다. 효력 있는 자국이
  /// 하나도 없으면 **거짓이다**(상쇄만 있었던 묶음에 실패 한 줄을 띄우지 않는다 — spec P).
  final bool lapsed;

  bool get isEmpty => flips.isEmpty && writingIds.isEmpty && !lapsed;

  /// 그 줄을 **어느 쪽으로 그릴지**. 네이티브의 `effectiveDone`과 같은 규칙이다.
  bool doneOf(TodoWidgetItem item) => flips[item.id] ?? item.done;
}

/// 자국 배열을 한 번 훑어 [TodoWidgetOverlay]를 만든다. **이 범위에서 가장 틀리기 쉬운 자리**라
/// 규칙을 여기 두고 유닛 테스트로 고정하며, 네이티브(`overlayOf`)가 그것을 베낀다(design 8.3).
///
/// 자국은 **셋을 모두 만족할 때만** 효력이 있다(design 1.3):
///   1. `gen > settledGen` — **결말이 난 묶음의 자국은 효력이 없다.** 이 비교 하나가 "그 묶음에
///      들어간 것만 걷는다"의 전부다.
///   2. 아직 [todoWidgetPendingTimeoutSeconds]가 지나지 않았다 — 아무도 결말을 내지 못한 자국이
///      영원히 남지 않는다(박제 금지).
///   3. **목표 값이 캐시의 `done`과 다르다** — 값이 이미 맞은 자국은 아무 일도 하지 않는다.
///      이 조건이 **상쇄**(spec P)를 그리기 쪽에서 공짜로 성립시킨다.
///
/// 같은 줄의 자국이 여럿이면 **가장 새 것 하나만** 본다.
TodoWidgetOverlay todoWidgetOverlayOf({
  required List<TodoWidgetItem> items,
  required TodoWidgetTapMarks? marks,
  required int settledGen,
  required DateTime now,
}) {
  if (marks == null || marks.marks.isEmpty) return const TodoWidgetOverlay();
  final nowMs = now.millisecondsSinceEpoch;
  final doneById = {for (final item in items) item.id: item.done};

  final latest = <String, TodoWidgetTapMark>{};
  for (final mark in marks.marks) {
    final found = latest[mark.id];
    if (found == null || mark.gen >= found.gen) latest[mark.id] = mark;
  }

  final effective = <TodoWidgetTapMark>[];
  for (final mark in latest.values) {
    if (mark.gen <= settledGen) continue;
    if (nowMs - mark.atMs >= todoWidgetPendingTimeoutSeconds * 1000) continue;
    final done = doneById[mark.id];
    if (done == null || done == mark.done) continue;
    effective.add(mark);
  }
  if (effective.isEmpty) return const TodoWidgetOverlay();
  // 되돌릴 시각이 지났다 → 전부 걷고 이유를 적는다. `쓰는 중` 자국도 함께 걷는다(그 줄도
  // 결말을 받지 못한 것이고, 남겨 두면 `쓰는 중`이 박제된다).
  if (nowMs >= marks.dueAtMs) return const TodoWidgetOverlay(lapsed: true);

  final flips = <String, bool>{};
  final writingIds = <String>{};
  var doneDelta = 0;
  for (final mark in effective) {
    if (mark.writing) {
      writingIds.add(mark.id);
      continue;
    }
    flips[mark.id] = mark.done;
    doneDelta += mark.done ? 1 : -1;
  }
  return TodoWidgetOverlay(
    flips: flips,
    writingIds: writingIds,
    doneDelta: doneDelta,
    lapsed: false,
  );
}

/// 일꾼이 **claim한 묶음 하나**(design 4.1). `writes`가 비면 서버 호출이 0번이다(상쇄).
class TodoWidgetBatch {
  const TodoWidgetBatch({
    required this.claimedGen,
    required this.leaveAtMs,
    required this.writes,
  });

  /// 이 묶음이 가져간 **마지막 세대.** 결말 발행이 `settledGen`을 이 값으로 올리고, 그보다 **큰**
  /// 세대의 자국(= 읽은 뒤에 들어온 탭)은 **건드리지 않는다.**
  final int claimedGen;

  /// 기다릴 시각. `writing` 자국이 섞여 있으면 **기다리지 않는다**(spec U 조건 ②의 조임).
  final int leaveAtMs;

  /// 실제로 서버에 쓸 줄들(id마다 마지막 값, 상쇄된 줄 제외).
  final List<TodoWidgetCheckTarget> writes;

  bool get isEmpty => writes.isEmpty;
}

/// 자국 레코드와 캐시로 **묶음을 확정한다**(claim·상쇄·쓸 목록 — design 4.1·6.1).
///
/// - `claimedGen`은 **그때의 마지막 세대**다. 그보다 큰 세대의 자국은 다음 묶음의 것이다.
/// - id마다 **마지막 값만** 남긴다("같은 줄을 두 번 눌러도 서버 쓰기는 한 번").
/// - 그 값이 캐시의 `done`과 같으면 **쓸 목록에서 뺀다**(상쇄). 전부 상쇄면 [TodoWidgetBatch.isEmpty]다.
/// - 캐시에 **아예 없는 id**도 뺀다(아주 낡은 그림이나 로그아웃 뒤 남은 그림을 누른 경우).
///   캐시를 읽지 못했으면(payload가 null) **빼지 않는다** — 사용자가 누른 것을 조용히 버리는 쪽이
///   더 나쁘고 서버 쓰기는 멱등이다.
/// - 이미 결말이 난 세대(`gen <= payload.settledGen`)는 가져가지 않는다 — **한 라운드 더**
///   도는 일꾼이 자기가 방금 쓴 것을 또 쓰지 않게 하는 한 줄이다(design 4.5).
///
/// 자국이 없으면 **null**이다(그때는 부르는 쪽이 Uri 한 줄만 쓰는 대비 경로로 간다).
TodoWidgetBatch? todoWidgetBatchOf({
  required TodoWidgetTapMarks? marks,
  required TodoWidgetPayload? payload,
  required DateTime now,
}) {
  if (marks == null) return null;
  final nowMs = now.millisecondsSinceEpoch;
  final claimedGen = marks.gen;
  final settledGen = payload?.settledGen ?? 0;

  final targets = <String, TodoWidgetTapMark>{};
  for (final mark in marks.marks) {
    if (mark.gen > claimedGen || mark.gen <= settledGen) continue;
    final found = targets[mark.id];
    if (found == null || mark.gen >= found.gen) targets[mark.id] = mark;
  }

  final doneById = payload != null && payload.hasItems
      ? {for (final item in payload.items) item.id: item.done}
      : null;
  final writes = <TodoWidgetCheckTarget>[];
  var writing = false;
  for (final mark in targets.values) {
    if (mark.writing) writing = true;
    if (doneById != null) {
      final done = doneById[mark.id];
      if (done == null || done == mark.done) continue;
    }
    writes.add(TodoWidgetCheckTarget(id: mark.id, done: mark.done));
  }

  return TodoWidgetBatch(
    claimedGen: claimedGen,
    leaveAtMs: writing && marks.leaveAtMs > nowMs ? nowMs : marks.leaveAtMs,
    writes: writes,
  );
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
