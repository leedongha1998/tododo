// 기한 알림의 예약 계획과 보정(todo-due-date 8단계). spec "P1. 기한 알림"의 규칙 전부가
// 이 두 순수 함수에 들어 있어서, 알림이 실제로 오는지는 실기기에서 보더라도 **무엇을 언제
// 걸어야 하는가**는 여기서 자동으로 고정된다(design 10장).

import 'package:flutter_test/flutter_test.dart';
import 'package:todododo/core/strings.dart';
import 'package:todododo/features/todo/data/todo.dart';
import 'package:todododo/features/todo/domain/due_alarm_plan.dart';

final _now = DateTime.utc(2026, 11, 10, 9, 0);

Todo _todo(
  String id, {
  String title = '설거지하기',
  bool isDone = false,
  DateTime? dueAt,
  DateTime? createdAt,
}) => Todo(
  id: id,
  title: title,
  isDone: isDone,
  createdAt: createdAt ?? DateTime.utc(2026, 11, 1),
  dueAt: dueAt,
);

void main() {
  group('planDueAlarms', () {
    test('미래 기한 하나에 1시간 전과 기한 시각 두 건을 만든다', () {
      final dueAt = _now.add(const Duration(days: 1));

      final alarms = planDueAlarms([_todo('a', dueAt: dueAt)], now: _now);

      expect(alarms, hasLength(2));
      expect(alarms[0].kind, DueAlarmKind.hourBefore);
      expect(alarms[0].at, dueAt.subtract(const Duration(hours: 1)));
      expect(alarms[0].title, AppStrings.todoDueAlarmBeforeTitle);
      expect(alarms[1].kind, DueAlarmKind.atDue);
      expect(alarms[1].at, dueAt);
      expect(alarms[1].title, AppStrings.todoDueAlarmAtTitle);
      // 본문은 할 일 제목 하나다. 남은 시간·날짜·대결 정보를 섞지 않는다(spec).
      expect(alarms.map((alarm) => alarm.body), everyElement('설거지하기'));
      // 두 제목이 서로 달라야 어느 시점인지 알 수 있다.
      expect(alarms[0].title, isNot(alarms[1].title));
    });

    test('기한이 1시간 이내면 기한 시각 알림만 만든다', () {
      final alarms = planDueAlarms([
        _todo('a', dueAt: _now.add(const Duration(minutes: 30))),
      ], now: _now);

      expect(alarms, hasLength(1));
      expect(alarms.single.kind, DueAlarmKind.atDue);
    });

    test('정확히 1시간 남았으면 1시간 전 알림을 건너뛴다 - 저장하는 순간 울리지 않게', () {
      final alarms = planDueAlarms([
        _todo('a', dueAt: _now.add(const Duration(hours: 1))),
      ], now: _now);

      expect(alarms, hasLength(1));
      expect(alarms.single.kind, DueAlarmKind.atDue);
    });

    test('기한이 이미 지났으면 하나도 만들지 않는다', () {
      final alarms = planDueAlarms([
        _todo('a', dueAt: _now.subtract(const Duration(minutes: 1))),
        // 기한 == 지금도 "지남"이다(기한은 그 시각까지다).
        _todo('b', dueAt: _now),
      ], now: _now);

      expect(alarms, isEmpty);
    });

    test('완료한 할 일과 기한 없는 할 일은 제외한다', () {
      final alarms = planDueAlarms([
        _todo('done', isDone: true, dueAt: _now.add(const Duration(days: 1))),
        _todo('nodue'),
      ], now: _now);

      expect(alarms, isEmpty);
    });

    test('완료를 해제하면 다시 들어오고, 기한이 지났으면 그래도 비어 있다', () {
      final future = _now.add(const Duration(days: 1));
      final past = _now.subtract(const Duration(days: 1));

      expect(
        planDueAlarms([_todo('a', dueAt: future)], now: _now),
        hasLength(2),
      );
      expect(planDueAlarms([_todo('a', dueAt: past)], now: _now), isEmpty);
    });
  });

  group('상한과 순서', () {
    test('울릴 시각이 이른 것부터 상한만큼만 남긴다', () {
      final todos = [
        _todo('far', dueAt: _now.add(const Duration(days: 30))),
        _todo('near', dueAt: _now.add(const Duration(days: 2))),
        _todo('middle', dueAt: _now.add(const Duration(days: 10))),
      ];

      final alarms = planDueAlarms(todos, now: _now, limit: 3);

      // 잘리는 것은 늘 가장 먼 기한이다(사용자에게 오류로 보이지 않고, 가까워지면 다음
      // 보정에서 저절로 들어온다).
      expect(alarms.map((alarm) => alarm.todoId), ['near', 'near', 'middle']);
      expect(alarms.map((alarm) => alarm.kind), [
        DueAlarmKind.hourBefore,
        DueAlarmKind.atDue,
        DueAlarmKind.hourBefore,
      ]);
    });

    test('기본 상한은 100이다', () {
      final todos = [
        for (var i = 0; i < 80; i++)
          _todo('t$i', dueAt: _now.add(Duration(days: 2 + i))),
      ];

      expect(planDueAlarms(todos, now: _now), hasLength(maxDueAlarms));
    });

    test('같은 입력을 여러 번 계획해도 같은 결과다', () {
      final todos = [
        _todo('b', dueAt: _now.add(const Duration(days: 3))),
        _todo('a', dueAt: _now.add(const Duration(days: 3))),
      ];

      final first = planDueAlarms(todos, now: _now);
      final second = planDueAlarms(todos.reversed.toList(), now: _now);

      // 울릴 시각이 같으면 todoId·시점으로 갈라 순서가 흔들리지 않는다.
      expect(
        first.map((alarm) => alarm.payload),
        second.map((alarm) => alarm.payload),
      );
    });

    test('한 계획 안의 id는 모두 다르고 31비트 양수다', () {
      final todos = [
        for (var i = 0; i < 40; i++)
          _todo('todo-$i', dueAt: _now.add(Duration(hours: 2 + i))),
      ];

      final alarms = planDueAlarms(todos, now: _now);
      final ids = alarms.map((alarm) => alarm.id).toList();

      expect(ids.toSet(), hasLength(ids.length));
      expect(
        ids,
        everyElement(
          allOf(greaterThanOrEqualTo(0), lessThanOrEqualTo(0x7FFFFFFF)),
        ),
      );
    });

    test('자리가 겹치면 +1씩 밀어 빈 자리를 찾는다', () {
      // 해시 충돌(design 8.4)이 났을 때 지나는 줄이다. 실제 충돌 쌍을 찾는 것은 30비트 공간
      // 탐색이라, 비켜 앉기만 떼어 직접 부른다 — "계획의 id가 모두 다르다"만 보는 테스트는
      // 충돌이 없는 입력에서 이 줄과 무관하게 통과한다.
      expect(freeDueAlarmId(10, {}), 10);
      expect(freeDueAlarmId(10, {10}), 11);
      expect(freeDueAlarmId(10, {10, 11, 12}), 13);
    });

    test('31비트를 넘으면 되돌아 감는다', () {
      // 안드로이드의 알림 id는 32비트 부호 있는 정수다. 음수로 넘어가면 안 된다.
      expect(freeDueAlarmId(0x7FFFFFFF, {0x7FFFFFFF}), 0);
      expect(freeDueAlarmId(0x7FFFFFFF, {0x7FFFFFFF, 0}), 1);
    });

    test('울릴 시각의 식은 한 곳에서 나온다', () {
      final dueAt = _now.add(const Duration(days: 1));
      final alarms = planDueAlarms([_todo('a', dueAt: dueAt)], now: _now);

      // DueAlarm.at과 planDueAlarms의 정렬 키가 같은 함수를 쓴다 — 두 곳에 같은 식을 적으면
      // 한쪽만 고쳐져 "임박한 것 우선"이 조용히 깨진다.
      expect(
        alarms.map((alarm) => alarm.at),
        alarms.map((alarm) => dueAlarmFireTime(alarm.dueAt, alarm.kind)),
      );
      expect(
        dueAlarmFireTime(dueAt, DueAlarmKind.hourBefore),
        dueAt.subtract(dueAlarmLeadTime),
      );
      expect(dueAlarmFireTime(dueAt, DueAlarmKind.atDue), dueAt);
    });

    test('알림 본문을 앱이 자르지 않는다', () {
      final long = '아' * 300;

      final alarms = planDueAlarms([
        _todo('a', title: long, dueAt: _now.add(const Duration(days: 1))),
      ], now: _now);

      expect(alarms.first.body, long);
    });
  });

  group('id와 payload', () {
    test('id의 최하위 비트가 시점이다', () {
      final before = dueAlarmIdOf('a1b2', DueAlarmKind.hourBefore);
      final atDue = dueAlarmIdOf('a1b2', DueAlarmKind.atDue);

      expect(before.isEven, isTrue);
      expect(atDue, before + 1);
      // 판이 바뀌어도 같은 값이어야 한다(String.hashCode를 쓰지 않는 이유).
      expect(dueAlarmIdOf('a1b2', DueAlarmKind.hourBefore), before);
    });

    test('할 일이 다르면 id도 다르다', () {
      expect(
        dueAlarmIdOf('one', DueAlarmKind.atDue),
        isNot(dueAlarmIdOf('two', DueAlarmKind.atDue)),
      );
    });

    test('payload를 왕복하면 할 일 id가 나온다', () {
      final payload = encodeDueAlarmPayload(
        todoId: 'todo-7',
        kind: DueAlarmKind.atDue,
        dueAt: _now,
      );

      expect(todoIdOfPayload(payload), 'todo-7');
    });

    test('기한이 다르면 payload가 달라진다 - 보정이 이것으로 기한 변경을 알아본다', () {
      final first = encodeDueAlarmPayload(
        todoId: 'a',
        kind: DueAlarmKind.atDue,
        dueAt: _now,
      );
      final second = encodeDueAlarmPayload(
        todoId: 'a',
        kind: DueAlarmKind.atDue,
        dueAt: _now.add(const Duration(minutes: 1)),
      );

      expect(first, isNot(second));
    });

    test('local 기한과 UTC 기한의 payload가 같다', () {
      final local = DateTime(2026, 11, 12, 18);

      expect(
        encodeDueAlarmPayload(
          todoId: 'a',
          kind: DueAlarmKind.atDue,
          dueAt: local,
        ),
        encodeDueAlarmPayload(
          todoId: 'a',
          kind: DueAlarmKind.atDue,
          dueAt: local.toUtc(),
        ),
      );
    });

    test('모양이 어긋난 payload는 null이다', () {
      expect(todoIdOfPayload(null), isNull);
      expect(todoIdOfPayload(''), isNull);
      expect(todoIdOfPayload('todo-7'), isNull);
      expect(todoIdOfPayload('|1|2'), isNull);
    });
  });

  group('reconcileDueAlarms', () {
    List<DueAlarm> plan(List<Todo> todos) => planDueAlarms(todos, now: _now);

    List<PendingDueAlarm> asPending(List<DueAlarm> alarms) => [
      for (final alarm in alarms)
        PendingDueAlarm(id: alarm.id, payload: alarm.payload),
    ];

    test('걸린 것이 없으면 원하는 것을 모두 예약한다', () {
      final desired = plan([
        _todo('a', dueAt: _now.add(const Duration(days: 1))),
      ]);

      final result = reconcileDueAlarms(desired: desired, pending: const []);

      expect(result.cancel, isEmpty);
      expect(result.schedule, hasLength(2));
    });

    test('변화가 없으면 아무 호출도 내지 않는다', () {
      final desired = plan([
        _todo('a', dueAt: _now.add(const Duration(days: 1))),
      ]);

      final result = reconcileDueAlarms(
        desired: desired,
        pending: asPending(desired),
      );

      expect(result.cancel, isEmpty);
      expect(result.schedule, isEmpty);
    });

    test('기한을 지우거나 할 일을 지우면 걸린 것을 취소만 한다', () {
      final pending = asPending(
        plan([_todo('a', dueAt: _now.add(const Duration(days: 1)))]),
      );

      final result = reconcileDueAlarms(desired: const [], pending: pending);

      expect(result.cancel, pending.map((alarm) => alarm.id));
      expect(result.schedule, isEmpty);
    });

    test('기한을 바꾸면 옛 예약을 취소하고 새로 건다', () {
      final pending = asPending(
        plan([_todo('a', dueAt: _now.add(const Duration(days: 1)))]),
      );
      final desired = plan([
        _todo('a', dueAt: _now.add(const Duration(days: 2))),
      ]);

      final result = reconcileDueAlarms(desired: desired, pending: pending);

      // id는 todoId·시점에서 나오므로 그대로인데 payload의 기한이 달라졌다 → 취소 후 재예약.
      expect(result.cancel, pending.map((alarm) => alarm.id));
      expect(result.schedule, hasLength(2));
    });

    test('모르는 id는 취소한다', () {
      final result = reconcileDueAlarms(
        desired: const [],
        pending: const [PendingDueAlarm(id: 42)],
      );

      expect(result.cancel, [42]);
    });

    test('같은 id라도 payload가 다르면 취소하고 다시 건다', () {
      final desired = plan([
        _todo('a', dueAt: _now.add(const Duration(days: 1))),
      ]);
      final stale = [
        for (final alarm in desired)
          PendingDueAlarm(id: alarm.id, payload: 'something-else'),
      ];

      final result = reconcileDueAlarms(desired: desired, pending: stale);

      expect(result.cancel, desired.map((alarm) => alarm.id));
      expect(result.schedule, desired);
    });

    test('완료한 할 일의 예약만 걷어낸다', () {
      final a = _todo('a', dueAt: _now.add(const Duration(days: 1)));
      final b = _todo('b', dueAt: _now.add(const Duration(days: 2)));
      final pending = asPending(plan([a, b]));
      final desired = plan([
        _todo('a', isDone: true, dueAt: _now.add(const Duration(days: 1))),
        b,
      ]);

      final result = reconcileDueAlarms(desired: desired, pending: pending);

      expect(result.schedule, isEmpty);
      expect(result.cancel.toSet(), plan([a]).map((alarm) => alarm.id).toSet());
    });
  });
}
