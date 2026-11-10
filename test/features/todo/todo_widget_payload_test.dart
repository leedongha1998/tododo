import 'package:flutter_test/flutter_test.dart';
import 'package:todododo/core/strings.dart';
import 'package:todododo/features/todo/data/todo.dart';
import 'package:todododo/features/todo/data/todo_widget_payload.dart';

/// 홈 화면 위젯 캐시의 판단 전부를 여기서 고정한다. 위젯은 네이티브가 그리지만 "무엇을 그릴지"는
/// 이 순수 함수들이 정하므로(design 원칙 2), 위젯 동작의 유일한 자동 검증 지점이다.
void main() {
  final now = DateTime(2026, 11, 4, 9, 14);

  group('fromTodos', () {
    test('미완료만 담고 받은 순서(= 앱 목록 순서)를 그대로 지킨다', () {
      final payload = TodoWidgetPayload.fromTodos(
        [
          _todo('1', '장보기'),
          _todo('2', '운동하기', isDone: true),
          _todo('3', '책 반납'),
        ],
        now: now,
      );

      expect(payload.items.map((item) => item.title), ['장보기', '책 반납']);
      expect(payload.totalCount, 2);
      expect(payload.centerText, isNull);
      expect(payload.noteTone, TodoWidgetNoteTone.muted);
    });

    // "앱과 같은 순서"는 **사용자가 끌어 정한 순서**이고, 그 순서는 서버의 `order by position`이
    // 만든다(todo-reorder design 2장). fromTodos는 순서를 **만들지 않고 보존**한다 — 두 곳에서
    // 정렬하면 한쪽만 고쳐도 "위젯 첫 줄 ≠ 앱 첫 줄"이 되고 아무도 모른다.
    // 그래서 기한이 섞인 목록을 **손으로 적은 순서** 그대로 넘긴다(정렬 함수를 부르지 않는다).
    test('들어온 순서를 그대로 싣는다(순서는 서버가 정한다)', () {
      final payload = TodoWidgetPayload.fromTodos(
        [
          _todo('1', '전화하기'),
          _todo('2', '장보기', dueAt: DateTime(2026, 11, 6, 18)),
          _todo('3', '책 반납', dueAt: DateTime(2026, 11, 3, 18)),
        ],
        now: now,
      );

      // 기한이 이른 '책 반납'이 위로 올라오지 않는다 — 기한은 순서에 개입하지 않는다.
      expect(payload.items.map((item) => item.title), [
        '전화하기',
        '장보기',
        '책 반납',
      ]);
    });

    test('미완료가 많으면 8개까지만 담되 전체 개수는 그대로 센다', () {
      final todos = [
        for (var i = 0; i < 12; i++) _todo('$i', '할 일 $i'),
      ];

      final payload = TodoWidgetPayload.fromTodos(todos, now: now);

      expect(payload.items, hasLength(todoWidgetMaxItems));
      expect(payload.items.first.title, '할 일 0');
      // "그 외 N개"는 담긴 개수가 아니라 전체 개수로 계산한다.
      expect(payload.totalCount, 12);
    });

    test('제목이 상한을 넘으면 자른다', () {
      final payload = TodoWidgetPayload.fromTodos(
        [_todo('1', 'ㄱ' * 200)],
        now: now,
      );

      expect(payload.items.single.title.length, todoWidgetMaxTitleLength);
    });

    test('할 일이 하나도 없으면 추가 안내만 남는다', () {
      final payload = TodoWidgetPayload.fromTodos(const [], now: now);

      expect(payload.items, isEmpty);
      expect(payload.centerText, AppStrings.widgetEmpty);
      expect(payload.note, '');
    });

    test('전부 완료면 다 끝냈다고 말한다', () {
      final payload = TodoWidgetPayload.fromTodos(
        [_todo('1', '장보기', isDone: true)],
        now: now,
      );

      // 할 일이 없는 것과 다 끝낸 것은 다른 상태다. 가르는 값은 완료까지 포함한 전체 개수다.
      expect(payload.centerText, AppStrings.widgetAllDone);
      expect(payload.centerText, isNot(AppStrings.widgetEmpty));
    });

    test('정상 상태의 note에 기준 시각이 들어간다', () {
      final payload = TodoWidgetPayload.fromTodos(
        [_todo('1', '장보기')],
        now: now,
      );

      expect(payload.note, '할 일 · 오전 9:14 기준');
      expect(payload.updatedAtMs, now.millisecondsSinceEpoch);
    });
  });

  group('formatWidgetTime', () {
    test('오전·오후와 두 자리 분으로 적는다', () {
      expect(formatWidgetTime(DateTime(2026, 11, 4, 9, 4)), '오전 9:04');
      expect(formatWidgetTime(DateTime(2026, 11, 4, 13, 30)), '오후 1:30');
    });

    test('0시와 12시는 12로 적는다', () {
      expect(formatWidgetTime(DateTime(2026, 11, 4, 0, 5)), '오전 12:05');
      expect(formatWidgetTime(DateTime(2026, 11, 4, 12, 0)), '오후 12:00');
    });
  });

  group('상태 발행', () {
    test('로그인하지 않음은 목록을 비우고 탭 대상을 로그인으로 둔다', () {
      final payload = TodoWidgetPayload.loggedOut(now: now);

      expect(payload.items, isEmpty);
      expect(payload.totalCount, 0);
      expect(payload.centerText, AppStrings.widgetLoggedOut);
      expect(payload.tapTarget, TodoWidgetTapTarget.login);
    });

    test('조회 중은 불러오는 중 안내만 남는다', () {
      final payload = TodoWidgetPayload.loading(now: now);

      expect(payload.centerText, AppStrings.widgetLoading);
      expect(payload.items, isEmpty);
    });

    test('조회 실패는 직전 목록과 기준 시각을 그대로 두고 note만 바꾼다', () {
      final previous = TodoWidgetPayload.fromTodos(
        [_todo('1', '장보기')],
        now: now,
      );

      final failed = TodoWidgetPayload.fetchFailed(
        previous,
        now: now.add(const Duration(hours: 3)),
      );

      expect(failed.items, previous.items);
      expect(failed.totalCount, previous.totalCount);
      // 기준 시각은 "목록이 언제 것인가"를 뜻한다. 실패한 시각이 아니다.
      expect(failed.note, '지금은 못 불러왔어요 · 오전 9:14 기준');
      expect(failed.updatedAtMs, previous.updatedAtMs);
      expect(failed.noteTone, TodoWidgetNoteTone.muted);
    });

    test('받아온 목록이 없는 조회 실패는 안내 한 줄만 남는다', () {
      final failed = TodoWidgetPayload.fetchFailed(null, now: now);

      expect(failed.items, isEmpty);
      expect(failed.centerText, AppStrings.widgetFetchFailed);
      expect(failed.note, '');
    });

    test('안내만 있던 상태에서 조회가 실패하면 다시 안내만 남는다', () {
      final previous = TodoWidgetPayload.loading(now: now);

      final failed = TodoWidgetPayload.fetchFailed(previous, now: now);

      expect(failed.centerText, AppStrings.widgetFetchFailed);
    });

    test('체크 실패는 목록을 유지하고 note를 danger로 바꾼다', () {
      final previous = TodoWidgetPayload.fromTodos(
        [_todo('1', '장보기'), _todo('2', '책 반납')],
        now: now,
      );

      final failed = TodoWidgetPayload.checkFailed(previous);

      // 목록에서 지운 적이 없으므로 체크하려던 할 일이 자동으로 되살아난다(spec의 조건).
      expect(failed.items.map((item) => item.id), ['1', '2']);
      expect(failed.note, AppStrings.widgetCheckFailed);
      expect(failed.noteTone, TodoWidgetNoteTone.danger);
      expect(failed.pendingId, isNull);
    });

    test('체크 실패 안내는 다음 정상 발행에서 사라진다', () {
      final failed = TodoWidgetPayload.checkFailed(
        TodoWidgetPayload.fromTodos([_todo('1', '장보기')], now: now),
      );

      final next = TodoWidgetPayload.fromTodos([_todo('1', '장보기')], now: now);

      expect(failed.noteTone, TodoWidgetNoteTone.danger);
      expect(next.noteTone, TodoWidgetNoteTone.muted);
      expect(next.note, isNot(AppStrings.widgetCheckFailed));
    });

    test('pending은 그 줄 표시만 더하고 목록·기준 시각은 건드리지 않는다', () {
      final previous = TodoWidgetPayload.fromTodos(
        [_todo('1', '장보기')],
        now: now,
      );
      final tappedAt = now.add(const Duration(hours: 2));

      final pending = TodoWidgetPayload.pending(previous, '1', now: tappedAt);

      expect(pending.pendingId, '1');
      expect(pending.pendingAtMs, tappedAt.millisecondsSinceEpoch);
      expect(pending.items, previous.items);
      expect(pending.note, previous.note);
      expect(pending.updatedAtMs, previous.updatedAtMs);
    });
  });

  group('JSON', () {
    test('왕복에서 값이 보존된다', () {
      final payload = TodoWidgetPayload.pending(
        TodoWidgetPayload.fromTodos(
          [_todo('11111111-1111-1111-1111-111111111111', '장보기')],
          now: now,
        ),
        '11111111-1111-1111-1111-111111111111',
        now: now,
      );

      final decoded = TodoWidgetPayload.decode(payload.encode())!;

      expect(decoded.items, payload.items);
      expect(decoded.totalCount, payload.totalCount);
      expect(decoded.note, payload.note);
      expect(decoded.noteTone, payload.noteTone);
      expect(decoded.pendingId, payload.pendingId);
      expect(decoded.pendingAtMs, payload.pendingAtMs);
      expect(decoded.updatedAtMs, payload.updatedAtMs);
      expect(decoded.tapTarget, payload.tapTarget);
      expect(decoded.centerText, payload.centerText);
    });

    test('danger note와 로그인 대상도 보존된다', () {
      final payload = TodoWidgetPayload.checkFailed(
        TodoWidgetPayload.fromTodos([_todo('1', '장보기')], now: now),
      );

      final decoded = TodoWidgetPayload.decode(payload.encode())!;

      expect(decoded.noteTone, TodoWidgetNoteTone.danger);
      expect(
        TodoWidgetPayload.decode(
          TodoWidgetPayload.loggedOut(now: now).encode(),
        )!.tapTarget,
        TodoWidgetTapTarget.login,
      );
    });

    test('네이티브가 쓰는 서식 문자열이 캐시에 함께 실린다', () {
      final json = TodoWidgetPayload.loading(now: now).toJson();

      expect(json['v'], todoWidgetSchemaVersion);
      expect(json['moreFormat'], AppStrings.widgetMoreFormat);
      expect(json['pendingLabel'], AppStrings.widgetPendingLabel);
    });

    test('null인 키는 캐시에 넣지 않는다', () {
      // 안드로이드(AOSP) org.json의 optString은 **명시적 null에 fallback이 아니라 "null" 네 글자**를
      // 돌려준다. centerText가 null인 정상 상태를 그대로 실으면 위젯 가운데에 `null`이 뜨고 줄이
      // 하나도 그려지지 않는다. 네이티브가 isNull을 검사하긴 하지만 그쪽은 테스트할 수 없으므로
      // 이 단언이 유일한 자동 방어선이다.
      final normal = TodoWidgetPayload.fromTodos([_todo('1', '장보기')], now: now);

      expect(normal.centerText, isNull);
      expect(normal.toJson().containsKey('centerText'), isFalse);
      expect(normal.toJson().containsKey('pendingId'), isFalse);
      expect(normal.toJson().containsKey('pendingAtMs'), isFalse);
      // 상태를 가리지 않고 성립해야 한다.
      for (final payload in [
        normal,
        TodoWidgetPayload.loading(now: now),
        TodoWidgetPayload.loggedOut(now: now),
        TodoWidgetPayload.fetchFailed(normal, now: now),
        TodoWidgetPayload.fetchFailed(null, now: now),
        TodoWidgetPayload.checkFailed(normal),
        TodoWidgetPayload.pending(normal, '1', now: now),
      ]) {
        expect(
          payload.toJson().values.any((value) => value == null),
          isFalse,
          reason: payload.toJson().toString(),
        );
      }
      // 키를 빼도 왕복은 그대로다(fromJson은 없는 키를 null로 읽는다).
      expect(TodoWidgetPayload.decode(normal.encode())!.centerText, isNull);
    });

    test('판 번호를 모르거나 깨진 값이면 null이다', () {
      expect(TodoWidgetPayload.decode('{"v":99,"items":[]}'), isNull);
      expect(TodoWidgetPayload.decode('그냥 글자'), isNull);
      expect(TodoWidgetPayload.decode(''), isNull);
      expect(TodoWidgetPayload.decode(null), isNull);
    });
  });

  group('visibleRows', () {
    final items = [
      for (var i = 0; i < 8; i++) TodoWidgetItem(id: '$i', title: '할 일 $i'),
    ];

    test('자리가 넉넉하면 그대로 그리고 그 외 줄을 쓰지 않는다', () {
      final result = visibleRows(items.take(3).toList(), 3, 6);

      expect(result.rows, hasLength(3));
      expect(result.moreCount, 0);
    });

    test('담기지 않으면 마지막 줄을 그 외 N개로 바꿔 쓴다', () {
      final result = visibleRows(items, 7, 3);

      // 3줄 자리에 7개 → 할 일 2줄 + "그 외 5개". 2 + 5 = 7로 어긋나지 않는다.
      expect(result.rows.map((item) => item.id), ['0', '1']);
      expect(result.moreCount, 5);
      expect(result.rows.length + result.moreCount, 7);
    });

    test('캐시 상한을 넘는 개수도 전체 개수로 계산한다', () {
      final result = visibleRows(items, 12, 6);

      expect(result.rows, hasLength(5));
      expect(result.moreCount, 7);
    });

    test('딱 맞는 개수는 그 외 줄을 쓰지 않고, 하나만 넘치면 두 개를 접는다', () {
      // off-by-one이 가장 잘 나는 두 칸이다.
      final exact = visibleRows(items.take(6).toList(), 6, 6);
      expect(exact.rows, hasLength(6));
      expect(exact.moreCount, 0);

      final oneOver = visibleRows(items.take(7).toList(), 7, 6);
      // 6줄에 7개 → 마지막 줄을 "그 외 2개"로 바꾼다(5 + 2 = 7).
      expect(oneOver.rows, hasLength(5));
      expect(oneOver.moreCount, 2);
    });

    test('두 줄짜리 자리는 한 줄만 할 일에 쓰고 나머지를 접는다', () {
      final result = visibleRows(items, 9, 2);

      expect(result.rows, hasLength(1));
      expect(result.moreCount, 8);
      expect(result.rows.length + result.moreCount, 9);
    });

    test('한 줄짜리 자리는 그 줄을 할 일에 쓴다', () {
      final result = visibleRows(items, 5, 1);

      // 유일한 줄을 안내로 바꾸면 할 일을 하나도 못 보는 위젯이 된다.
      expect(result.rows, hasLength(1));
      expect(result.moreCount, 0);
    });

    test('그릴 줄이나 항목이 없으면 아무것도 돌려주지 않는다', () {
      expect(visibleRows(items, 8, 0).rows, isEmpty);
      expect(visibleRows(const [], 0, 6).moreCount, 0);
    });
  });

  group('Uri 해석', () {
    const id = '11111111-1111-1111-1111-111111111111';

    test('체크 Uri에서 할 일 id를 꺼낸다', () {
      final action = todoWidgetActionOf(
        Uri.parse('todododo://widget/check?id=$id'),
      );

      expect(action.isCheck, isTrue);
      expect(action.todoId, id);
    });

    test('uuid 모양이 아니거나 id가 없으면 아무 일도 하지 않는다', () {
      expect(
        todoWidgetActionOf(Uri.parse('todododo://widget/check?id=abc')).isCheck,
        isFalse,
      );
      expect(
        todoWidgetActionOf(Uri.parse('todododo://widget/check')).isCheck,
        isFalse,
      );
    });

    test('다른 스킴·호스트·경로는 체크로 읽지 않는다', () {
      for (final raw in [
        'com.todododo.todododo://login-callback?access_token=x',
        'todododo://battle/check?id=$id',
        'todododo://widget/todo',
        'todododo://widget/check/extra?id=$id',
      ]) {
        expect(
          todoWidgetActionOf(Uri.parse(raw)).isCheck,
          isFalse,
          reason: raw,
        );
      }
      expect(todoWidgetActionOf(null).isCheck, isFalse);
    });

    test('탭 Uri는 할 일 화면을 가리킨다', () {
      expect(
        widgetTargetOf(Uri.parse('todododo://widget/todo')),
        TodoWidgetTapTarget.todo,
      );
    });

    test('해석할 수 없는 탭 Uri는 null이다(오류 화면을 띄우지 않는다)', () {
      expect(widgetTargetOf(null), isNull);
      expect(widgetTargetOf(Uri.parse('todododo://widget/battle')), isNull);
      expect(widgetTargetOf(Uri.parse('https://example.com/todo')), isNull);
    });
  });
}

Todo _todo(
  String id,
  String title, {
  bool isDone = false,
  DateTime? dueAt,
}) {
  return Todo(
    id: id,
    title: title,
    isDone: isDone,
    createdAt: DateTime(2026, 11, 4, 8),
    dueAt: dueAt,
  );
}
