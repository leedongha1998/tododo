// 기한 알림(todo-due-date P1)의 예약 계획과 보정. Flutter·플러그인에 의존하지 않는 순수
// 함수만 둔다 — spec의 알림 규칙 전부를 유닛 테스트로 고정하기 위해서다(design 원칙 2·8.5).
//
// **spec의 알림 조항이 전부 이 한 경로로 모인다.** 기한 변경·기한 삭제·할 일 삭제·완료·완료
// 해제·다른 기기에서의 수정·기기 교체·재설치가 모두 "지금 있어야 하는 집합이 달라졌다"로
// 같게 표현되고, 그 차이를 reconcileDueAlarms가 취소·예약으로 낸다.

import '../../../core/strings.dart';
import '../data/todo.dart';

/// 기한 1시간 전에 한 번. 투두별로 시점을 고르는 설정은 만들지 않는다(spec).
const dueAlarmLeadTime = Duration(hours: 1);

/// 한 기기에 걸어 두는 예약의 상한(= 임박한 할 일 50개 × 2건).
///
/// 안드로이드는 앱당 예약 수에 한계가 있고, 플러그인이 부팅 복구를 위해 예약 전부를 한 파일에
/// 적어 두므로 수가 커지면 그 읽기·쓰기도 커진다. 개인 투두 규모에서 사실상 닿지 않고, 닿아도
/// **잘리는 것은 늘 가장 먼 기한**이며 사용자에게 오류로 보이지 않는다(spec).
const maxDueAlarms = 100;

/// 알림 하나를 뜻하는 시점. index가 예약 id의 최하위 비트이자 payload의 두 번째 칸이다.
enum DueAlarmKind { hourBefore, atDue }

/// 기한과 시점에서 **울릴 절대 시각**을 낸다. `DueAlarm.at`과 [planDueAlarms]의 정렬 키가
/// 모두 이것을 쓴다 — 같은 식을 두 곳에 적으면 한쪽만 고쳐져 "임박한 것 우선"이 조용히 깨진다.
DateTime dueAlarmFireTime(DateTime dueAt, DueAlarmKind kind) =>
    kind == DueAlarmKind.hourBefore ? dueAt.subtract(dueAlarmLeadTime) : dueAt;

/// [wanted] 자리가 이미 [used]에 있으면 +1씩 밀어 **빈 자리**를 찾는다(해시 충돌 비켜 앉기).
///
/// 밀린 id는 "자리 번호"일 뿐이고 그 예약의 뜻은 payload가 들고 있다. 31비트를 넘지 않게
/// 되돌아 감는다 — 안드로이드의 알림 id는 32비트 부호 있는 정수다.
/// [used]가 꽉 찰 일은 없다(상한이 [maxDueAlarms]개다).
int freeDueAlarmId(int wanted, Set<int> used) {
  var id = wanted & 0x7FFFFFFF;
  while (used.contains(id)) {
    id = (id + 1) & 0x7FFFFFFF;
  }
  return id;
}

/// 예약 하나. **울릴 시각·제목·본문·payload가 모두 기한과 시점에서 나온다** — 같은 값을 두
/// 곳에서 각자 판정하지 않게 필드는 둘(기한, 시점)뿐이고 나머지는 모두 파생이다.
class DueAlarm {
  const DueAlarm({
    required this.id,
    required this.todoId,
    required this.kind,
    required this.dueAt,
    required this.body,
  });

  /// OS에 거는 자리 번호. 뜻은 [payload]가 들고 있다([dueAlarmIdOf] 주석 참고).
  final int id;

  final String todoId;
  final DueAlarmKind kind;

  /// 할 일의 기한(UTC).
  final DateTime dueAt;

  /// 알림 본문 = 할 일 제목. **앱이 자르지 않는다**(spec) — 길면 안드로이드가 줄여 보여 주고
  /// 펼치면 전체가 보인다. 앱이 먼저 자르면 펼쳐도 복구되지 않는다.
  final String body;

  /// 울릴 절대 시각(UTC). 식은 [dueAlarmFireTime] 하나뿐이다 — [planDueAlarms]의 정렬 키도
  /// 그것을 쓴다. 두 곳에 같은 식을 적으면 한쪽만 고쳐져 "임박한 것 우선"이 조용히 깨진다.
  DateTime get at => dueAlarmFireTime(dueAt, kind);

  /// 두 알림의 제목은 서로 다르다 — 같은 할 일에 두 번 오므로 제목이 같으면 뭐가 왔는지
  /// 알 수 없다(spec).
  String get title => kind == DueAlarmKind.hourBefore
      ? AppStrings.todoDueAlarmBeforeTitle
      : AppStrings.todoDueAlarmAtTitle;

  String get payload =>
      encodeDueAlarmPayload(todoId: todoId, kind: kind, dueAt: dueAt);
}

/// 지금 OS에 걸려 있는 예약 하나. 플러그인 타입을 순수 함수·테스트에 들이지 않기 위한 우리 값이다.
class PendingDueAlarm {
  const PendingDueAlarm({required this.id, this.payload});

  final int id;
  final String? payload;
}

/// uuid → 31비트 양수 id. 최하위 한 비트가 시점(1시간 전/기한 시각)이다.
///
/// `String.hashCode`를 쓰지 않는다 — Dart 판이 바뀌면 값이 달라질 수 있고, 그러면 **앱을
/// 업데이트한 순간 걸려 있던 예약을 아무도 알아보지 못한다**(옛 예약이 떠돌고 보정이 전부
/// 다시 건다). 그래서 FNV-1a를 직접 돈다.
///
/// 해시라 충돌이 가능하다(30비트 공간에 동시 예약 50건이면 약 1.2e-6). 충돌을 세 겹으로 다룬다:
/// ① **뜻의 진실은 payload다** — [reconcileDueAlarms]는 id가 같아도 payload가 다르면 "다른 것"으로
/// 보고 취소 후 다시 걸며, 취소를 **전부 돌린 뒤에** 예약한다. 그래서 충돌이 나도 "남의 알림이
/// 조용히 사라진 채로 남는" 상태가 되지 않는다(`DueAlarmService.sync`의 순서 주석 참고).
/// ② [planDueAlarms]가 [freeDueAlarmId]로 이미 쓰인 자리를 비켜 앉는다(밀린 id는 자리 번호일
/// 뿐이다). ③ 보정이 "지금 원하는 집합"에 없는 id를 전부 취소하므로 밀린 자리나 옛 예약이
/// 남지 않는다.
int dueAlarmIdOf(String todoId, DueAlarmKind kind) =>
    ((_fnv1a32(todoId) & 0x3FFFFFFF) << 1) | kind.index;

/// 알림에 함께 싣는 뜻: `<todoId>|<시점 index>|<기한 epochMs>`.
///
/// 기한을 함께 싣는 이유가 보정의 핵심이다 — **기한이 바뀌면 payload가 달라져** 걸려 있던
/// 예약이 자동으로 "원하는 것과 다른 것"이 되고, 그래서 취소 후 재예약된다.
String encodeDueAlarmPayload({
  required String todoId,
  required DueAlarmKind kind,
  required DateTime dueAt,
}) => '$todoId|${kind.index}|${dueAt.toUtc().millisecondsSinceEpoch}';

/// payload가 가리키는 할 일. 모양이 어긋나거나 비면 null이다.
String? todoIdOfPayload(String? payload) {
  if (payload == null) return null;
  final parts = payload.split('|');
  if (parts.length != 3) return null;
  final todoId = parts.first;
  return todoId.isEmpty ? null : todoId;
}

/// 지금 있어야 하는 예약의 **전체 집합**. 이 함수가 spec의 알림 규칙 전부를 들고 있다.
///
/// - 완료한 할 일·기한 없는 할 일은 제외한다(완료하면 알림이 오지 않는다. 완료를 해제하면
///   다시 들어오고, 그때 기한이 이미 지났으면 아래 규칙에 걸려 하나도 만들어지지 않는다)
/// - 기한이 이미 지났으면 **하나도** 만들지 않는다(지난 시각을 기한으로 넣어도 저장하는 순간
///   알림이 울리지 않는다)
/// - 기한이 1시간 이내면 1시간 전 알림만 건너뛴다(기한 시각 알림은 남는다)
/// - 울릴 시각이 이른 것부터 [limit]개까지만 남긴다(**임박한 것 우선**, 잘리는 것은 늘 가장 먼
///   기한이고 가까워지면 다음 보정에서 저절로 들어온다)
/// - 같은 id를 두 예약이 원하면 뒤에 오는 쪽이 +1씩 밀어 빈 자리를 찾는다
///
/// [now]와 할 일의 기한은 같은 기준이면 된다(둘 다 UTC로 다룬다). 돌려주는 순서는 울릴 시각
/// 오름차순이고, 같으면 todoId·시점으로 갈라 **같은 입력에 늘 같은 결과**가 나온다.
List<DueAlarm> planDueAlarms(
  List<Todo> todos, {
  required DateTime now,
  int limit = maxDueAlarms,
}) {
  final nowUtc = now.toUtc();
  final wanted =
      <({String todoId, DueAlarmKind kind, DateTime dueAt, String body})>[];
  for (final todo in todos) {
    final dueAt = todo.dueAt?.toUtc();
    if (todo.isDone || dueAt == null) continue;
    if (!dueAt.isAfter(nowUtc)) continue;
    if (dueAt.subtract(dueAlarmLeadTime).isAfter(nowUtc)) {
      wanted.add((
        todoId: todo.id,
        kind: DueAlarmKind.hourBefore,
        dueAt: dueAt,
        body: todo.title,
      ));
    }
    wanted.add((
      todoId: todo.id,
      kind: DueAlarmKind.atDue,
      dueAt: dueAt,
      body: todo.title,
    ));
  }

  wanted.sort((a, b) {
    // 울릴 시각의 식은 dueAlarmFireTime 하나뿐이다(DueAlarm.at도 그것을 쓴다).
    final byAt = dueAlarmFireTime(
      a.dueAt,
      a.kind,
    ).compareTo(dueAlarmFireTime(b.dueAt, b.kind));
    if (byAt != 0) return byAt;
    final byTodo = a.todoId.compareTo(b.todoId);
    if (byTodo != 0) return byTodo;
    return a.kind.index.compareTo(b.kind.index);
  });

  final used = <int>{};
  final alarms = <DueAlarm>[];
  for (final item in wanted.take(limit)) {
    final id = freeDueAlarmId(dueAlarmIdOf(item.todoId, item.kind), used);
    used.add(id);
    alarms.add(
      DueAlarm(
        id: id,
        todoId: item.todoId,
        kind: item.kind,
        dueAt: item.dueAt,
        body: item.body,
      ),
    );
  }
  return alarms;
}

/// 원하는 집합과 실제 걸려 있는 것을 맞춘다. **이 함수가 추가·수정·삭제를 한 번에 낸다.**
///
/// - 취소: 걸려 있는데 원하는 집합에 **id가 없거나 payload가 다른** 것 전부
///   (기한이 바뀌면 payload의 epochMs가 달라져 자동으로 "다른 것"이 된다. 모르는 id도 취소한다 —
///   이 플러그인으로 거는 알림이 기한 알림뿐이라 안전하다. 대결 알림은 FCM이 직접 그린다)
/// - 예약: 원하는데 같은 id·같은 payload로 걸려 있지 않은 것 전부
/// - 둘 다 비면 플랫폼 호출이 한 번도 일어나지 않는다(가장 흔한 경우다)
({List<int> cancel, List<DueAlarm> schedule}) reconcileDueAlarms({
  required List<DueAlarm> desired,
  required List<PendingDueAlarm> pending,
}) {
  final desiredPayloads = {
    for (final alarm in desired) alarm.id: alarm.payload,
  };
  final pendingPayloads = {
    for (final alarm in pending) alarm.id: alarm.payload,
  };

  // containsKey를 먼저 본다. payload가 null인 예약(옛 판이 걸어 둔 것 등)에서 "없음"과
  // "null이 같다"가 섞이면 그 예약을 영원히 취소하지 못한다.
  final cancel = <int>[];
  for (final alarm in pending) {
    if (!desiredPayloads.containsKey(alarm.id) ||
        desiredPayloads[alarm.id] != alarm.payload) {
      cancel.add(alarm.id);
    }
  }

  final schedule = <DueAlarm>[];
  for (final alarm in desired) {
    if (!pendingPayloads.containsKey(alarm.id) ||
        pendingPayloads[alarm.id] != alarm.payload) {
      schedule.add(alarm);
    }
  }

  return (cancel: cancel, schedule: schedule);
}

/// FNV-1a 32비트. 판이 바뀌어도 같은 값이어야 하므로 직접 돈다(위 [dueAlarmIdOf] 주석).
/// uuid는 ASCII라 코드 단위를 바이트로 그대로 써도 같다.
int _fnv1a32(String value) {
  var hash = 0x811C9DC5;
  for (final unit in value.codeUnits) {
    hash ^= unit & 0xFF;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash;
}
