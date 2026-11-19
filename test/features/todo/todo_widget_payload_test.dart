import 'package:flutter_test/flutter_test.dart';
import 'package:todododo/core/strings.dart';
import 'package:todododo/features/todo/data/todo.dart';
import 'package:todododo/features/todo/data/todo_widget_payload.dart';

/// 홈 화면 위젯 캐시의 판단 전부를 여기서 고정한다. 위젯은 네이티브가 그리지만 "무엇을 그릴지"는
/// 이 순수 함수들이 정하므로(design 원칙 2), 위젯 동작의 유일한 자동 검증 지점이다.
void main() {
  final now = DateTime(2026, 11, 4, 9, 14);

  group('fromTodos', () {
    // 2026-11-18(추가 범위 2): **완료도 담는다.** 배열 순서는 받은 순서(= position) 그대로이고,
    // 완료 줄이 제자리에 남는 것이 이번 요구의 본체다. 어느 줄이 **보일지**는 rank가 정한다.
    test('완료까지 담고 받은 순서(= 앱 목록 순서)를 그대로 지킨다', () {
      final payload = TodoWidgetPayload.fromTodos(
        [
          _todo('1', '장보기'),
          _todo('2', '운동하기', isDone: true),
          _todo('3', '책 반납'),
        ],
        now: now,
      );

      expect(payload.items.map((item) => item.title), ['장보기', '운동하기', '책 반납']);
      expect(payload.items.map((item) => item.done), [false, true, false]);
      // totalCount는 **미완료 전체**다(완료를 세지 않는다). `그 외 N개`가 미완료만 세는 근거다.
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

    // 옛 상태 7(안내만)이 상태 3b가 됐다(design 2.3.1). 가운데 안내는 줄 영역을 **덮는** 자리라
    // 완료 줄과 구조적으로 공존할 수 없어서, 사용자가 방금 끝낸 할 일들을 보여 주고 그 문장을
    // 머리 줄로 옮겼다 — 한 줄보다 정보가 많다.
    test('전부 완료면 완료 줄을 보여 주고 다 끝냈다고 말한다', () {
      final payload = TodoWidgetPayload.fromTodos(
        [_todo('1', '장보기', isDone: true)],
        now: now,
      );

      expect(payload.items.map((item) => item.id), ['1']);
      expect(payload.centerText, isNull);
      expect(payload.note, AppStrings.widgetAllDone);
      expect(payload.header, '할 일 1/1');
      // 할 일이 없는 것과 다 끝낸 것은 여전히 다른 상태다. 가르는 값은 전체 개수다.
      expect(
        TodoWidgetPayload.fromTodos(const [], now: now).centerText,
        AppStrings.widgetEmpty,
      );
    });

    test('정상 상태의 note에 기준 시각이 들어간다', () {
      final payload = TodoWidgetPayload.fromTodos(
        [_todo('1', '장보기')],
        now: now,
      );

      // 2026-11-18(추가 범위 2): `할 일 ·`이 빠졌다 — 머리 줄의 헤더가 이미 그 말을 들고 있어
      // 한 줄에 두 번 보이고, note에 남는 가로가 약 190dp라 꼬리가 잘린다(design 6.1.2).
      expect(payload.note, '오전 9:14 기준');
      expect(payload.note, isNot(contains('할 일')));
      expect(payload.updatedAtMs, now.millisecondsSinceEpoch);
    });
  });

  // 머리 줄의 문장은 **Dart가 완성해** 캐시에 싣는다(네이티브는 숫자를 세지도 분수를 조립하지도
  // 않는다. design 2.2.2). 오너가 직접 고른 꼴이라 테스트로 못 박는다.
  group('header', () {
    test('정상 상태는 완료/전체 분수로 적는다', () {
      final payload = TodoWidgetPayload.fromTodos(
        [
          _todo('1', '장보기'),
          _todo('2', '운동하기', isDone: true),
          _todo('3', '책 반납'),
          _todo('4', '전화하기', isDone: true),
          _todo('5', '청소하기'),
        ],
        now: now,
      );

      // 분자가 완료, 분모가 전체(미완료+완료)다.
      expect(payload.header, '할 일 2/5');
    });

    test('낱말을 덧붙이지 않는다', () {
      final payload = TodoWidgetPayload.fromTodos(
        [_todo('1', '장보기'), _todo('2', '운동하기', isDone: true)],
        now: now,
      );

      // pm이 반대를 권했고 오너가 보고 고른 꼴이다 — `개`·`완료`·`남음` 같은 글자를 넣지 않는다.
      expect(payload.header, '할 일 1/2');
      for (final word in ['개', '완료', '남음', '중']) {
        expect(payload.header, isNot(contains(word)));
      }
    });

    test('전부 완료면 분자와 분모가 같다', () {
      final payload = TodoWidgetPayload.fromTodos(
        [
          _todo('1', '장보기', isDone: true),
          _todo('2', '운동하기', isDone: true),
        ],
        now: now,
      );

      expect(payload.header, '할 일 2/2');
    });

    test('줄이 보이지 않는 상태는 개수 없이 할 일만 적는다', () {
      // `0/0`류의 허전한 숫자를 만들지 않는다(spec 수용 기준). 그 상태들에서는 셀 목록이 손에
      // 없거나(로그아웃·조회 중·목록 없는 조회 실패) 숫자가 전부 0이다(할 일 없음).
      expect(TodoWidgetPayload.loggedOut(now: now).header, AppStrings.widgetHeader);
      expect(TodoWidgetPayload.loading(now: now).header, AppStrings.widgetHeader);
      expect(
        TodoWidgetPayload.fetchFailed(null, now: now).header,
        AppStrings.widgetHeader,
      );
      expect(
        TodoWidgetPayload.fromTodos(const [], now: now).header,
        AppStrings.widgetHeader,
      );
      expect(AppStrings.widgetHeader, '할 일');
    });

    test('조회 실패·체크 실패는 직전 header를 물려받는다', () {
      final previous = TodoWidgetPayload.fromTodos(
        [_todo('1', '장보기'), _todo('2', '운동하기', isDone: true)],
        now: now,
      );
      final later = now.add(const Duration(hours: 1));

      // 그 두 상태는 items를 그대로 물려받으므로 개수도 **같은 시점의 값**이어야 한다. 새로
      // 세면 셀 목록이 없고(조회 실패), 서버 반영에 실패한 체크를 성공으로 센 숫자가 된다.
      expect(
        TodoWidgetPayload.fetchFailed(previous, now: later).header,
        previous.header,
      );
      expect(
        TodoWidgetPayload.checkFailed(previous, now: later).header,
        previous.header,
      );
      // 네이티브가 찍은 탭 자국도 머리 줄을 건드리지 않는다(자국은 그리기의 입력일 뿐이다).
      expect(
        _withTapMark(previous, todoId: '1', at: later).header,
        previous.header,
      );
    });

    test('왕복에서 header가 보존되고 옛 캐시는 할 일로 읽힌다', () {
      final payload = TodoWidgetPayload.fromTodos(
        [_todo('1', '장보기'), _todo('2', '운동하기', isDone: true)],
        now: now,
      );

      expect(TodoWidgetPayload.decode(payload.encode())!.header, '할 일 1/2');
      // 판 번호를 올리지 않았으므로 header 키가 없는 옛 캐시도 그대로 읽힌다 — 개수를 모르면
      // 말하지 않는다(design 2.2.2).
      expect(
        TodoWidgetPayload.fromJson({
          'v': 1,
          'items': const [],
          'totalCount': 0,
          'updatedAtMs': 0,
        })!.header,
        AppStrings.widgetHeader,
      );
    });

    test('낡음·체크 실패 문구가 사실로 시작한다', () {
      // 머리 줄에서 꼬리부터 잘리므로(ellipsize=end) 사실이 앞에 와야 남는다(design 6.1.2).
      expect(AppStrings.widgetNoteStale('오후 7:15'), startsWith('못 불러왔어요'));
      expect(AppStrings.widgetCheckFailed, startsWith('체크하지 못했어요'));
      // `눌러서`로 늘어지던 꼬리를 덜어냈다(design 6.1.2의 폭 표: 한글 17자 ≈ 175dp로 머리 줄에
      // 빡빡하게 들어간다. 공백·가운뎃점까지 세면 20글자다).
      expect(AppStrings.widgetNoteStale('오후 7:15'), isNot(contains('지금은')));
      expect(AppStrings.widgetCheckFailed, isNot(contains('눌러서')));
      expect(AppStrings.widgetCheckFailed, endsWith('앱에서 확인해요'));
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

  // 기한 서식은 **위젯 전용**이고(앱 목록은 formatDueLabel, 대화상자는 formatDueValue) 네이티브는
  // 이 문장들 중에서 고르기만 하므로(테스트하지 않는다) 여기가 유일한 검증이다.
  group('formatWidgetDue', () {
    // 이 묶음의 "오늘"은 11/18이다(파일 맨 위의 now는 11/4라 "같은 날" 칸을 쓸 수 없다).
    final now = DateTime(2026, 11, 18, 9, 14);

    test('같은 날이면 시각만 적는다', () {
      expect(formatWidgetDue(DateTime(2026, 11, 18, 18), now), '오후 6:00');
    });

    test('다른 날·같은 해는 월/일을 붙인다', () {
      expect(
        formatWidgetDue(DateTime(2026, 11, 20, 18), now),
        '11/20 오후 6:00',
      );
    });

    test('다른 해는 연/월/일을 붙이고 0을 채우지 않는다', () {
      expect(
        formatWidgetDue(DateTime(2027, 1, 5, 18), now),
        '2027/1/5 오후 6:00',
      );
    });

    test('날을 가리키는 낱말을 어느 꼴에도 쓰지 않는다', () {
      // `내일 09:00` 꼴은 자정을 넘기면 틀린 문장이 되는데 그 거짓을 알려 주는 표시가 없다
      // (발행 뒤 Dart는 깨어나지 않고, 기한이 아직 안 지났으니 `지남`도 붙지 않는다).
      for (final at in [
        DateTime(2026, 11, 18, 23, 59),
        DateTime(2026, 11, 19, 9),
        DateTime(2026, 11, 20, 18),
        DateTime(2027, 1, 5, 18),
        DateTime(2025, 12, 31, 18),
      ]) {
        final label = formatWidgetDue(at, now);
        for (final word in ['오늘', '내일', '어제', '모레', '남음', '지난']) {
          expect(label.contains(word), isFalse, reason: '$label / $word');
        }
      }
    });

    test('날이 갈리는 경계에서 꼴이 바뀐다', () {
      // 같은 날 23:59는 시각만, 다음 날 00:00은 월/일이 붙는다.
      expect(formatWidgetDue(DateTime(2026, 11, 18, 23, 59), now), '오후 11:59');
      expect(
        formatWidgetDue(DateTime(2026, 11, 19), now),
        '11/19 오전 12:00',
      );
    });

    test('12시간제의 두 함정과 분 0 패딩', () {
      final midnight = DateTime(2026, 11, 18, 0, 30);
      final noon = DateTime(2026, 11, 18, 12, 30);

      // 0시는 오전 12시, 12시는 오후 12시다(0:30·12:30이 아니다).
      expect(formatWidgetDue(midnight, now), '오전 12:30');
      expect(formatWidgetDue(noon, now), '오후 12:30');
      expect(formatWidgetDue(DateTime(2026, 11, 18, 18, 5), now), '오후 6:05');
    });
  });

  group('기한 키', () {
    // 위 묶음과 같은 이유로 "오늘"을 11/18로 둔다.
    final now = DateTime(2026, 11, 18, 9, 14);

    test('기한이 있는 할 일은 문장 둘과 절대 시각을 함께 싣는다', () {
      final payload = TodoWidgetPayload.fromTodos(
        [_todo('1', '장보기', dueAt: DateTime(2026, 11, 18, 18))],
        now: now,
      );

      final item = payload.items.single;
      expect(item.due, '오후 6:00');
      // dueOver는 같은 문장에 꼬리만 붙은 꼴이다(네이티브가 문구를 만들지 않게).
      expect(item.dueOver, '오후 6:00 지남');
      expect(item.dueAtMs, DateTime(2026, 11, 18, 18).millisecondsSinceEpoch);
    });

    test('기한이 없는 할 일은 세 키가 캐시에 **없다**', () {
      final payload = TodoWidgetPayload.fromTodos(
        [_todo('1', '운동하기')],
        now: now,
      );

      final json = payload.items.single.toJson();
      // AOSP org.json의 optString은 명시적 null에 "null" 네 글자를 돌려준다. 키째로 빼지 않으면
      // 기한을 안 쓰는 사용자의 줄마다 `null`이 뜬다(spec: 아무것도 보이지 않는다).
      expect(json.containsKey('due'), isFalse);
      expect(json.containsKey('dueOver'), isFalse);
      expect(json.containsKey('dueAtMs'), isFalse);
      expect(json.values.any((value) => value == null), isFalse);
    });

    test('기한이 섞인 목록도 null 값을 캐시에 넣지 않는다', () {
      final payload = TodoWidgetPayload.fromTodos(
        [
          _todo('1', '장보기', dueAt: DateTime(2026, 11, 18, 18)),
          _todo('2', '운동하기'),
        ],
        now: now,
      );

      final items = payload.toJson()['items'] as List;
      for (final raw in items) {
        final item = raw as Map<String, dynamic>;
        expect(item.values.any((value) => value == null), isFalse, reason: '$item');
      }
    });

    test('왕복에서 기한 키 셋이 그대로 돌아온다', () {
      final payload = TodoWidgetPayload.fromTodos(
        [
          _todo('1', '장보기', dueAt: DateTime(2026, 11, 20, 18)),
          _todo('2', '운동하기'),
        ],
        now: now,
      );

      final decoded = TodoWidgetPayload.decode(payload.encode())!;

      expect(decoded.items, payload.items);
      expect(decoded.items.first.dueOver, '11/20 오후 6:00 지남');
      expect(decoded.items.last.due, isNull);
      expect(decoded.items.last.dueAtMs, isNull);
    });

    test('dueAtMs는 시간대와 무관한 절대 시각이다', () {
      final utc = DateTime.utc(2026, 11, 18, 9);
      final sameMoment = utc.toLocal();

      final a = TodoWidgetPayload.fromTodos(
        [_todo('1', '장보기', dueAt: utc)],
        now: now,
      );
      final b = TodoWidgetPayload.fromTodos(
        [_todo('1', '장보기', dueAt: sameMoment)],
        now: now,
      );

      // 같은 순간을 다른 표현으로 넣어도 네이티브가 비교할 값은 같다.
      expect(a.items.single.dueAtMs, b.items.single.dueAtMs);
      expect(a.items.single.dueAtMs, utc.millisecondsSinceEpoch);
      expect(a.items.single.due, b.items.single.due);
    });

    test('"지남"이 발행 시점에 굳지 않는다', () {
      // 이미 지난 기한으로 발행해도 캐시에는 **상태가 들어 있지 않다** — 문장 둘과 절대 시각뿐이고
      // `overdue: true` 같은 불값이 없다. 어느 쪽을 그릴지는 네이티브가 다시 그릴 때 정한다.
      // 네이티브의 비교 자체는 테스트하지 않으므로 이 단언이 "Dart가 굳히지 않았다"의 유일한 방어선이다.
      final past = TodoWidgetPayload.fromTodos(
        [_todo('1', '장보기', dueAt: DateTime(2026, 11, 18, 1))],
        now: now,
      );

      final json = past.toJson()['items'] as List;
      final keys = (json.single as Map<String, dynamic>).keys.toSet();
      expect(keys, {'id', 'title', 'rank', 'due', 'dueOver', 'dueAtMs'});
      expect(past.items.single.due, '오전 1:00');
      expect(past.items.single.dueOver, '오전 1:00 지남');
    });

    test('완료한 할 일의 기한은 캐시에 들어오지 않는다', () {
      final payload = TodoWidgetPayload.fromTodos(
        [
          _todo('1', '장보기', isDone: true, dueAt: DateTime(2026, 11, 18, 18)),
          _todo('2', '운동하기'),
        ],
        now: now,
      );

      // 완료 줄은 **보이지만** 기한 키가 캐시에 없다(Dart가 그 규칙을 끝낸다) — 네이티브의
      // "기한 키가 없으면 GONE" 첫 분기가 그대로 처리하므로 완료 전용 분기가 생기지 않는다.
      // "끝냈는데 혼난다"로 읽히는 붉은 기한이 완료 줄에 붙을 수 없는 근거이기도 하다.
      expect(payload.items.map((item) => item.id), ['1', '2']);
      final doneItem = payload.items.first;
      expect(doneItem.done, isTrue);
      expect(doneItem.due, isNull);
      expect(doneItem.dueOver, isNull);
      expect(doneItem.dueAtMs, isNull);
      final json = payload.toJson()['items'] as List;
      expect((json.first as Map<String, dynamic>).keys.toSet(), {
        'id',
        'title',
        'rank',
        'done',
      });
    });

    test('목록을 물려받는 발행은 기한도 함께 물려받는다', () {
      final previous = TodoWidgetPayload.fromTodos(
        [_todo('1', '장보기', dueAt: DateTime(2026, 11, 20, 18))],
        now: now,
      );

      final failed = TodoWidgetPayload.fetchFailed(previous, now: now);
      final marked = _withTapMark(previous, todoId: '1', at: now);

      expect(failed.items.single.due, '11/20 오후 6:00');
      expect(marked.items.single.dueAtMs, previous.items.single.dueAtMs);
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
      expect(failed.note, '못 불러왔어요 · 오전 9:14 기준');
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

      final failed = TodoWidgetPayload.checkFailed(previous, now: now);

      // 목록에서 지운 적이 없으므로 체크하려던 할 일이 자동으로 되살아난다(spec의 조건).
      expect(failed.items.map((item) => item.id), ['1', '2']);
      expect(failed.note, AppStrings.widgetCheckFailed);
      expect(failed.noteTone, TodoWidgetNoteTone.danger);
      expect(failed.pendingId, isNull);
    });

    test('체크 실패 안내는 다음 정상 발행에서 사라진다', () {
      final failed = TodoWidgetPayload.checkFailed(
        TodoWidgetPayload.fromTodos([_todo('1', '장보기')], now: now),
        now: now,
      );

      final next = TodoWidgetPayload.fromTodos([_todo('1', '장보기')], now: now);

      expect(failed.noteTone, TodoWidgetNoteTone.danger);
      expect(next.noteTone, TodoWidgetNoteTone.muted);
      expect(next.note, isNot(AppStrings.widgetCheckFailed));
    });

    // 2026-11-19(추가 범위 3 J): `쓰는 중`을 발행하던 팩토리가 없어졌다. 그 그림은 네이티브가
    // 탭 순간에 그리고, Dart는 **결말 하나**만 발행한다.
    test('어떤 Dart 발행도 탭 자국 네 키를 싣지 않는다', () {
      final normal = TodoWidgetPayload.fromTodos(
        [_todo('1', '장보기'), _todo('2', '운동하기', isDone: true)],
        now: now,
      );
      // 네이티브가 찍은 자국이 든 캐시를 재료로 삼아도 마찬가지여야 한다 — 그래서 **모든 발행이
      // 자국을 지운다**("결말이 자국을 걷는다"가 코드 한 줄 없이 성립하는 근거다).
      final marked = _withTapMark(normal, todoId: '1', at: now);
      expect(marked.pendingId, '1');

      for (final payload in [
        normal,
        marked,
        TodoWidgetPayload.loggedOut(now: now),
        TodoWidgetPayload.loading(now: now),
        TodoWidgetPayload.fromTodos(const [], now: now),
        TodoWidgetPayload.fetchFailed(marked, now: now),
        TodoWidgetPayload.fetchFailed(null, now: now),
        TodoWidgetPayload.checkFailed(marked, now: now),
        TodoWidgetPayload.checkFailed(null, now: now),
        TodoWidgetPayload.applyCheck(marked, todoId: '1', done: true)!,
      ]) {
        final json = payload.toJson();
        for (final key in [
          'pendingId',
          'pendingAtMs',
          'pendingDone',
          'pendingMode',
        ]) {
          expect(json.containsKey(key), isFalse, reason: '$key / $json');
        }
      }
    });

    test('자국은 fromJson이 읽고 toJson이 지운다', () {
      final normal = TodoWidgetPayload.fromTodos(
        [_todo('1', '장보기')],
        now: now,
      );
      final tappedAt = now.add(const Duration(hours: 2));

      final marked = _withTapMark(normal, todoId: '1', at: tappedAt);

      // 읽는 쪽만 남는다 — 중복 탭 가드가 그 값을 쓴다.
      expect(marked.pendingId, '1');
      expect(marked.pendingAtMs, tappedAt.millisecondsSinceEpoch);
      expect(marked.items, normal.items);
      expect(marked.updatedAtMs, normal.updatedAtMs);
      // 그 캐시를 다시 쓰면 자국이 사라진다.
      expect(TodoWidgetPayload.decode(marked.encode())!.pendingId, isNull);
    });
  });

  group('JSON', () {
    test('왕복에서 값이 보존된다', () {
      final payload = TodoWidgetPayload.fromTodos(
        [_todo('11111111-1111-1111-1111-111111111111', '장보기')],
        now: now,
      );

      final decoded = TodoWidgetPayload.decode(payload.encode())!;

      expect(decoded.items, payload.items);
      expect(decoded.totalCount, payload.totalCount);
      expect(decoded.note, payload.note);
      expect(decoded.noteTone, payload.noteTone);
      expect(decoded.header, payload.header);
      expect(decoded.updatedAtMs, payload.updatedAtMs);
      expect(decoded.tapTarget, payload.tapTarget);
      expect(decoded.centerText, payload.centerText);
    });

    test('danger note와 로그인 대상도 보존된다', () {
      final payload = TodoWidgetPayload.checkFailed(
        TodoWidgetPayload.fromTodos([_todo('1', '장보기')], now: now),
        now: now,
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
        TodoWidgetPayload.checkFailed(normal, now: now),
        TodoWidgetPayload.applyCheck(normal, todoId: '1', done: true)!,
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

  // 아래 묶음은 **미완료만 있는 캐시**(= 옛 캐시와 같은 모양: rank가 배열 index와 같고 done이
  // 전부 false)를 쓴다. 그래서 이 칸들이 그대로 통과하는 것이 "새 규칙이 옛 규칙과 같게 읽힌다"는
  // 증거이고, 판 번호를 올리지 않은 근거다(design 2.2.2).
  group('visibleRows', () {
    final items = [
      for (var i = 0; i < 8; i++)
        TodoWidgetItem(id: '$i', title: '할 일 $i', rank: i),
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

  // 이번 범위에서 규칙이 가장 많이 늘어난 곳이 줄 자리 계산이고, 그것이 전부 순수 함수라
  // **테스트가 유일한 방어선**이다(네이티브는 `rank < limit` 비교와 리소스 고르기뿐이다).
  group('랭크 규칙', () {
    List<String> ranksOf(TodoWidgetPayload payload) => [
          for (final item in [...payload.items]
            ..sort((a, b) => a.rank.compareTo(b.rank)))
            item.id,
        ];

    test('미완료가 먼저 받고 완료가 그 뒤를 받는다', () {
      final payload = TodoWidgetPayload.fromTodos(
        [
          _todo('1', '장보기', isDone: true),
          _todo('2', '운동하기'),
          _todo('3', '책 반납', isDone: true),
          _todo('4', '전화하기'),
        ],
        now: now,
      );

      // 고르는 순서: 미완료 2·4 → 완료 1·3. 같은 묶음 안에서는 position 순서다.
      expect(ranksOf(payload), ['2', '4', '1', '3']);
      // 그리는 순서는 그대로 position 순서다(제자리에서 모양만 바뀐다).
      expect(payload.items.map((item) => item.id), ['1', '2', '3', '4']);
    });

    test('방금 누른 줄이 rank 0을 받는다', () {
      final payload = TodoWidgetPayload.fromTodos(
        [
          _todo('1', '장보기'),
          _todo('2', '운동하기', isDone: true),
          _todo('3', '책 반납'),
        ],
        now: now,
        justCheckedId: '2',
      );

      expect(ranksOf(payload), ['2', '1', '3']);
      // 배열(그리는 순서)은 흔들리지 않는다 — 합치면 체크한 줄이 목록 맨 아래로 뛴다.
      expect(payload.items.map((item) => item.id), ['1', '2', '3']);
    });

    test('방금 누른 줄이 미완료거나 목록에 없으면 무시된다', () {
      final todos = [
        _todo('1', '장보기'),
        _todo('2', '운동하기', isDone: true),
      ];

      // 되돌린 줄은 미완료가 되어 어차피 앞 순위다 — 방향마다 다른 길을 만들지 않는다.
      expect(
        ranksOf(
          TodoWidgetPayload.fromTodos(todos, now: now, justCheckedId: '1'),
        ),
        ['1', '2'],
      );
      expect(
        ranksOf(
          TodoWidgetPayload.fromTodos(todos, now: now, justCheckedId: '없는id'),
        ),
        ['1', '2'],
      );
    });

    test('미완료 8 + 완료 6을 따로 담아 서로를 밀어내지 않는다', () {
      final todos = [
        for (var i = 0; i < 10; i++) _todo('u$i', '미완료 $i'),
        for (var i = 0; i < 10; i++) _todo('d$i', '완료 $i', isDone: true),
      ];

      final payload = TodoWidgetPayload.fromTodos(todos, now: now);

      final undone = payload.items.where((item) => !item.done);
      final done = payload.items.where((item) => item.done);
      expect(undone, hasLength(todoWidgetMaxItems));
      expect(done, hasLength(todoWidgetMaxDoneItems));
      // 한 상한에 섞어 담으면 완료가 앞에 몰린 사용자의 캐시가 완료로 채워져 빈자리가 생긴다.
      expect(undone.map((item) => item.id).first, 'u0');
      expect(done.map((item) => item.id).first, 'd0');
      expect(payload.totalCount, 10);
      expect(payload.header, '할 일 10/20');
    });

    test('방금 누른 줄이 완료 7번째여도 캐시에 들어오고 배열 순서가 유지된다', () {
      final todos = [
        for (var i = 0; i < 7; i++) _todo('d$i', '완료 $i', isDone: true),
        _todo('u0', '장보기'),
      ];

      final payload = TodoWidgetPayload.fromTodos(
        todos,
        now: now,
        justCheckedId: 'd6',
      );

      // done.take(5) + [그것] — 그 줄은 앞 6개에 없었으므로 position이 그들보다 뒤다.
      expect(
        payload.items.map((item) => item.id),
        ['d0', 'd1', 'd2', 'd3', 'd4', 'd6', 'u0'],
      );
      expect(payload.items.firstWhere((item) => item.id == 'd6').rank, 0);
    });
  });

  group('visibleRows와 완료 줄', () {
    TodoWidgetPayload payloadOf({String? justCheckedId}) {
      return TodoWidgetPayload.fromTodos(
        [
          _todo('B', '책 반납', isDone: true),
          _todo('A', '장보기'),
          _todo('C', '운동하기'),
          _todo('D', '전화하기'),
          _todo('E', '청소하기'),
          _todo('F', '설거지', isDone: true),
        ],
        now: now,
        justCheckedId: justCheckedId,
      );
    }

    test('미완료가 자리를 다 쓰면 완료 줄이 하나도 보이지 않는다', () {
      final payload = payloadOf();
      final result = visibleRows(payload.items, payload.totalCount, 4);

      // 미완료 4개(A·C·D·E)가 자리를 전부 쓰고 완료(B·F)는 밀려 보이지 않는다. 그 사실은
      // 머리 줄의 개수가 말한다(spec F). 미완료가 딱 들어맞으므로 `그 외` 줄도 쓰지 않는다.
      expect(result.rows.map((item) => item.id), ['A', 'C', 'D', 'E']);
      expect(result.rows.every((item) => !item.done), isTrue);
      expect(result.moreCount, 0);
    });

    test('미완료가 자리보다 많으면 완료 줄 없이 그 외 N개로 접힌다', () {
      final payload = payloadOf();
      final result = visibleRows(payload.items, payload.totalCount, 3);

      expect(result.rows.map((item) => item.id), ['A', 'C']);
      expect(result.moreCount, 2);
    });

    test('자리가 남으면 완료가 배열 순서 그대로 들어온다', () {
      final payload = payloadOf();
      final result = visibleRows(payload.items, payload.totalCount, 6);

      expect(result.rows.map((item) => item.id), [
        'B',
        'A',
        'C',
        'D',
        'E',
        'F',
      ]);
      expect(result.moreCount, 0);
    });

    test('design 6.2.2의 보기를 그대로 둔다(방금 누른 줄이 제자리에 보인다)', () {
      final payload = payloadOf(justCheckedId: 'B');
      final result = visibleRows(payload.items, payload.totalCount, 4);

      // 방금 누른 줄이 보이고, 아래 줄이 올라오지 않았고, 미완료가 자리를 먼저 썼다.
      expect(result.rows.map((item) => item.id), ['B', 'A', 'C']);
      expect(result.rows.first.done, isTrue);
      // `그 외 N개`는 미완료만 센다 — 보이는 미완료는 A·C 둘이고 전체 미완료는 4다.
      expect(result.moreCount, 2);
    });

    test('방금 누른 완료 줄은 한 줄짜리 위젯에서도 보인다', () {
      final payload = payloadOf(justCheckedId: 'B');
      final result = visibleRows(payload.items, payload.totalCount, 1);

      // spec이 "미완료 한 줄을 밀어낼 수 있다"로 허용한 경우다.
      expect(result.rows.map((item) => item.id), ['B']);
      expect(result.moreCount, 0);
    });

    test('완료 줄이 자리를 먹으면 그 외 N개가 그만큼 커진다', () {
      final payload = payloadOf(justCheckedId: 'B');

      for (var rowCount = 2; rowCount <= 6; rowCount++) {
        final result = visibleRows(payload.items, payload.totalCount, rowCount);
        final shownUndone = result.rows.where((item) => !item.done).length;
        // 보이는 미완료 + 그 외 N개 = 미완료 전체. 어긋나면 사용자가 센 것과 다르다.
        expect(
          shownUndone + result.moreCount,
          payload.totalCount,
          reason: '$rowCount줄에서 어긋났다',
        );
        expect(result.rows.length, lessThanOrEqualTo(rowCount));
      }
    });
  });

  group('완료 줄의 JSON', () {
    test('done·rank가 왕복에서 그대로 돌아온다', () {
      final payload = TodoWidgetPayload.fromTodos(
        [_todo('1', '장보기', isDone: true), _todo('2', '운동하기')],
        now: now,
        justCheckedId: '1',
      );

      final decoded = TodoWidgetPayload.decode(payload.encode())!;

      expect(decoded.items, payload.items);
      expect(decoded.items.first.done, isTrue);
      expect(decoded.items.first.rank, 0);
      expect(decoded.items.last.done, isFalse);
      expect(decoded.items.last.rank, 1);
    });

    test('done이 false면 키를 싣지 않는다', () {
      final payload = TodoWidgetPayload.fromTodos(
        [_todo('1', '장보기')],
        now: now,
      );

      final json = payload.toJson()['items'] as List;
      expect((json.single as Map<String, dynamic>).containsKey('done'), isFalse);
    });

    test('rank가 없는 옛 캐시는 배열 순서를 rank로 읽는다', () {
      // 판 번호를 올리지 않은 근거다 — 옛 캐시(미완료만, position 순서)에서 `rank < limit`이
      // 옛 규칙 `take(limit)`과 정확히 같아진다(design 2.2.2).
      final decoded = TodoWidgetPayload.fromJson({
        'v': 1,
        'items': [
          {'id': '1', 'title': '장보기'},
          {'id': '2', 'title': '운동하기'},
          {'id': '3', 'title': '책 반납'},
        ],
        'totalCount': 3,
        'updatedAtMs': 0,
      })!;

      expect(decoded.items.map((item) => item.rank), [0, 1, 2]);
      expect(decoded.items.every((item) => !item.done), isTrue);
      expect(
        visibleRows(decoded.items, 3, 2).rows.map((item) => item.id),
        ['1'],
      );
    });
  });

  // 줄 수는 표가 아니라 **공식**이고 그 주인은 Dart다(design 6.2.1). 네이티브는 같은 상수로 같은
  // 식을 옮겨 쓰기만 하므로(테스트하지 않는다) 이 칸들이 공식의 유일한 검증이다.
  group('widgetRowCount', () {
    // **이 칸이 그대로 통과하는 것이 "상수를 바꾸지 않았다"는 증거다**(design 12.3). 머리 줄이
    // 옛 아래 note의 자리를 물려받았으므로 모든 높이에서 줄 수가 같아야 한다.
    test('경계가 42dp 간격으로 한 줄씩 늘어난다', () {
      // 고정 비용 24dp(루트 여백 4+2 + 머리 줄 18) + 줄 간격 42dp.
      expect(widgetRowCount(65), 1);
      expect(widgetRowCount(66), 1);
      expect(widgetRowCount(107), 1);
      expect(widgetRowCount(108), 2);
      expect(widgetRowCount(149), 2);
      expect(widgetRowCount(150), 3);
      expect(widgetRowCount(191), 3);
      expect(widgetRowCount(192), 4);
      expect(widgetRowCount(233), 4);
      expect(widgetRowCount(234), 5);
      expect(widgetRowCount(275), 5);
      expect(widgetRowCount(276), 6);
    });

    test('기본 크기(4x2)에서 할 일이 두 줄 보인다', () {
      // spec 수용 기준이 이 한 칸이다. 110dp는 todo_widget_info.xml이 선언한 minHeight이고,
      // 런처가 높이를 알려 주지 않을 때 네이티브가 쓰는 기본값도 같은 값이다.
      expect(widgetRowCount(110), 2);
    });

    test('실기기(Galaxy S20, 4x2 = 225dp)에서 네 줄이 유지된다', () {
      // spec G의 수용 조건 ②가 이 한 칸이다 — 머리 줄이 생긴 뒤에도 지금 보이는 4줄이 줄면
      // 헤더를 얻고 위젯의 목적을 잃는다. (225 − 24) ÷ 42 = 4.78 → 4.
      expect(widgetRowCount(225), 4);
    });

    test('하한 1줄, 상한 6줄을 넘지 않는다', () {
      // 아주 납작하게 줄여도 할 일 한 줄은 그린다(0줄 위젯은 빈 사각형이다).
      expect(widgetRowCount(0), 1);
      expect(widgetRowCount(-1), 1);
      expect(widgetRowCount(10000), todoWidgetMaxRows);
    });

    test('상수가 레이아웃·캐시 상한과 어긋나지 않는다', () {
      // 줄 상한(6)이 캐시 상한(8)보다 작아야 "그 외 N개"가 어긋나지 않는다.
      expect(todoWidgetMaxRows, lessThanOrEqualTo(todoWidgetMaxItems));
      expect(todoWidgetRowPitchDp, 42);
      expect(todoWidgetFixedHeightDp, 24);
    });
  });

  group('Uri 해석', () {
    const id = '11111111-1111-1111-1111-111111111111';

    test('체크 Uri에서 할 일 id를 꺼낸다', () {
      final action = todoWidgetActionOf(
        Uri.parse('todododo://widget/check?id=$id'),
      );

      expect(action.isWrite, isTrue);
      expect(action.todoId, id);
    });

    test('done 파라미터가 목표 값을 가른다', () {
      // 토글이 아니라 **목표 값**이다 — 낡은 그림을 누른 탭이 사용자가 본 것과 반대로 쓰이지
      // 않게 하는 장치다(design 4.6 (1)).
      expect(
        todoWidgetActionOf(
          Uri.parse('todododo://widget/check?id=$id&done=1'),
        ).done,
        isTrue,
      );
      expect(
        todoWidgetActionOf(
          Uri.parse('todododo://widget/check?id=$id&done=0'),
        ).done,
        isFalse,
      );
    });

    test('done이 없거나 모르는 값이면 완료로 읽는다', () {
      // `PendingIntent`는 앱 업데이트를 넘어 시스템에 남아 있다. 업데이트 직후 위젯이 아직 다시
      // 그려지지 않은 사이에 옛 APK가 만든 Uri(done이 없는 꼴)가 발사될 수 있고, 그때의 옳은
      // 동작이 정확히 완료 처리다(옛 위젯의 체크 칸은 완료 전용이었다).
      expect(
        todoWidgetActionOf(Uri.parse('todododo://widget/check?id=$id')).done,
        isTrue,
      );
      expect(
        todoWidgetActionOf(
          Uri.parse('todododo://widget/check?id=$id&done=yes'),
        ).done,
        isTrue,
      );
    });

    test('uuid 모양이 아니거나 id가 없으면 아무 일도 하지 않는다', () {
      expect(
        todoWidgetActionOf(Uri.parse('todododo://widget/check?id=abc')).isWrite,
        isFalse,
      );
      expect(
        todoWidgetActionOf(Uri.parse('todododo://widget/check')).isWrite,
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
          todoWidgetActionOf(Uri.parse(raw)).isWrite,
          isFalse,
          reason: raw,
        );
      }
      expect(todoWidgetActionOf(null).isWrite, isFalse);
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

  // 체크의 백그라운드 경로는 실기기에서만 검증된다. 그래서 판단할 수 있는 부분을 전부 떼어
  // 여기서 고정한다(design 12.1).
  group('todoWidgetCheckDecisionOf', () {
    const id = '11111111-1111-1111-1111-111111111111';
    const other = '22222222-2222-2222-2222-222222222222';
    final cached = TodoWidgetPayload.fromTodos(
      [_todo(id, '장보기'), _todo(other, '책 반납')],
      now: now,
    );

    TodoWidgetCheckDecision decide({
      TodoWidgetAction action = const TodoWidgetAction.setDone(id, done: true),
      TodoWidgetPayload? payload,
      bool appAlive = false,
    }) {
      return todoWidgetCheckDecisionOf(
        action: action,
        cached: payload,
        appAlive: appAlive,
      );
    }

    test('체크가 아닌 Uri는 아무 일도 하지 않는다', () {
      expect(
        decide(action: const TodoWidgetAction.none(), payload: cached),
        TodoWidgetCheckDecision.ignore,
      );
    });

    test('앱이 살아 있으면 맡기고, 죽어 있으면 직접 쓴다', () {
      // 살아 있는 앱에 맡기는 것이 W5의 핵심이다 — 백그라운드가 클라이언트를 또 만들면
      // 토큰이 돌아 앱이 조용히 로그아웃된다.
      expect(
        decide(payload: cached, appAlive: true),
        TodoWidgetCheckDecision.handOff,
      );
      expect(decide(payload: cached), TodoWidgetCheckDecision.writeHere);
    });

    // 2026-11-20 회귀 수정(이 테스트가 그 버그를 잡는다). 자국 기반 중복 탭 가드는 **여기에
    // 없다** — 네이티브로 옮겼다([isDuplicateWidgetTap]).
    test('네이티브가 이번 탭의 자국을 찍은 캐시여도 쓰기로 간다', () {
      // 네이티브는 자국을 `commit()`한 **뒤에** 이 isolate를 깨운다(design 4.7 (6)의 첫 칸).
      // 그래서 여기서 읽는 `pendingId`는 **언제나 이번 탭의 것**이고, 그것으로 중복을 가르면
      // **모든 탭이 버려진다.** 2026-11-20 실기기 회귀가 정확히 그것이었다(백그라운드 워커가
      // 11ms 만에 SUCCESS → 7초 뒤 줄이 되돌아가고 `체크하지 못했어요`).
      final marked = _withTapMark(cached, todoId: id, at: now);

      expect(decide(payload: marked), TodoWidgetCheckDecision.writeHere);
      expect(
        decide(payload: marked, appAlive: true),
        TodoWidgetCheckDecision.handOff,
      );
      // 탭 직후든 몇 초 뒤든 같다 — 이 함수는 **기준 시각조차 받지 않아** 자국의 나이를 볼
      // 방법이 없다(그 사실이 시그니처로 못 박혀 있다).
      final oldMark = _withTapMark(
        cached,
        todoId: id,
        at: now.subtract(const Duration(seconds: 59)),
      );
      expect(decide(payload: oldMark), TodoWidgetCheckDecision.writeHere);
    });

    test('되돌리기 탭도 자국에 막히지 않는다', () {
      final mixed = TodoWidgetPayload.fromTodos(
        [_todo(id, '장보기', isDone: true), _todo(other, '책 반납')],
        now: now,
      );
      final marked = _withTapMark(mixed, todoId: id, at: now, done: false);

      expect(
        decide(
          action: const TodoWidgetAction.setDone(id, done: false),
          payload: marked,
        ),
        TodoWidgetCheckDecision.writeHere,
      );
    });

    test('목록에 아예 없는 id는 무시한다(아주 낡은 그림을 누른 경우다)', () {
      final onlyOther = TodoWidgetPayload.fromTodos(
        [_todo(other, '책 반납')],
        now: now,
      );

      expect(decide(payload: onlyOther), TodoWidgetCheckDecision.ignore);
      // 로그아웃 캐시의 낡은 그림을 누른 경우도 같다.
      expect(
        decide(payload: TodoWidgetPayload.loggedOut(now: now)),
        TodoWidgetCheckDecision.ignore,
      );
    });

    test('이미 목표 값인 항목은 무시한다', () {
      // 완료 줄이 목록에 남게 된 뒤로는 "없어짐"이 성공의 표시가 아니다. 그래서 옛 조건
      // ("items에 없으면 무시")을 이 조건으로 바꿨다(design 4.6 (2)). 아무것도 바꾸지 않는
      // 쓰기를 서버에 보내지 않고, 그 때문에 `쓰는 중`이 깜빡이지도 않게 한다.
      final mixed = TodoWidgetPayload.fromTodos(
        [_todo(id, '장보기', isDone: true), _todo(other, '책 반납')],
        now: now,
      );

      expect(decide(payload: mixed), TodoWidgetCheckDecision.ignore);
      expect(
        decide(
          action: const TodoWidgetAction.setDone(other, done: false),
          payload: mixed,
        ),
        TodoWidgetCheckDecision.ignore,
      );
      // 반대 값이면 쓴다(되돌리기가 이 갈래다).
      expect(
        decide(
          action: const TodoWidgetAction.setDone(id, done: false),
          payload: mixed,
        ),
        TodoWidgetCheckDecision.writeHere,
      );
      expect(
        decide(
          action: const TodoWidgetAction.setDone(other, done: true),
          payload: mixed,
          appAlive: true,
        ),
        TodoWidgetCheckDecision.handOff,
      );
    });

    test('캐시를 읽지 못했으면 막지 않는다', () {
      // 중복인지 알 수 없을 때 사용자가 누른 것을 조용히 버리는 쪽이 더 나쁘다(서버 쓰기는 멱등).
      expect(decide(), TodoWidgetCheckDecision.writeHere);
      expect(decide(appAlive: true), TodoWidgetCheckDecision.handOff);
    });

    test('기한이 지난 할 일도 같은 결정을 받는다', () {
      // 기한은 체크에 개입하지 않는다 — "지난 할 일의 체크를 막는다" 같은 규칙을 만들지 않았다(spec).
      final withDue = TodoWidgetPayload.fromTodos(
        [_todo(id, '장보기', dueAt: DateTime(2020, 1, 1))],
        now: now,
      );

      expect(decide(payload: withDue), TodoWidgetCheckDecision.writeHere);
      expect(
        decide(payload: withDue, appAlive: true),
        TodoWidgetCheckDecision.handOff,
      );
    });
  });

  // 2026-11-20: 중복 탭 판정이 **네이티브로 옮겨 갔다**(탭을 처음 보는 자리이자 자국을 쓰는
  // 자리가 거기다). 네이티브는 유닛 테스트가 없으므로 **규칙만 이 순수 함수로 뽑아** 여기서
  // 고정하고, `TodoWidgetProvider.onCheckTap`/`isDuplicateTap`이 그 규칙을 그대로 따른다
  // (주석으로 묶어 두었다 — `ROW_PITCH_DP`·`TAP_MARK_FRESH_MS`와 같은 방식).
  group('isDuplicateWidgetTap', () {
    const id = '11111111-1111-1111-1111-111111111111';
    const other = '22222222-2222-2222-2222-222222222222';

    test('같은 줄·같은 목표 값·신선한 자국이면 중복이다', () {
      expect(
        isDuplicateWidgetTap(
          markId: id,
          markDone: true,
          markFresh: true,
          tapId: id,
          tapDone: true,
        ),
        isTrue,
      );
      // 되돌리기도 같다(방향이 아니라 "같은 방향인가"를 본다).
      expect(
        isDuplicateWidgetTap(
          markId: id,
          markDone: false,
          markFresh: true,
          tapId: id,
          tapDone: false,
        ),
        isTrue,
      );
    });

    test('방향이 다른 탭은 중복이 아니다', () {
      // 낙관적 반영 때문에 사용자는 **이미 바뀐 줄**을 보고 있다. 그 줄을 다시 누르는 것은
      // "되돌리겠다"는 뜻이므로 막으면 되돌리기가 6초 동안 먹지 않는다.
      expect(
        isDuplicateWidgetTap(
          markId: id,
          markDone: true,
          markFresh: true,
          tapId: id,
          tapDone: false,
        ),
        isFalse,
      );
    });

    test('다른 줄의 자국은 막지 않는다', () {
      expect(
        isDuplicateWidgetTap(
          markId: other,
          markDone: true,
          markFresh: true,
          tapId: id,
          tapDone: true,
        ),
        isFalse,
      );
    });

    test('자국이 없거나 신선하지 않으면 중복이 아니다', () {
      // 쓰기 도중에 프로세스가 죽으면 캐시에 자국만 남는다. 그 줄을 영영 체크할 수 없게 되면
      // 안 되므로 신선함을 잃은 자국은 다음 탭을 막지 않는다.
      expect(
        isDuplicateWidgetTap(
          markId: id,
          markDone: true,
          markFresh: false,
          tapId: id,
          tapDone: true,
        ),
        isFalse,
      );
      expect(
        isDuplicateWidgetTap(
          markId: null,
          markDone: true,
          markFresh: true,
          tapId: id,
          tapDone: true,
        ),
        isFalse,
      );
    });
  });

  group('widgetTapMarkFresh', () {
    test('6초 창의 경계', () {
      // 네이티브 `markOf`의 FRESH 판정과 같은 값이어야 한다(TAP_MARK_FRESH_MS = 6_000).
      expect(
        widgetTapMarkFresh(
          markAtMs: now.millisecondsSinceEpoch,
          now: now.add(const Duration(milliseconds: 5900)),
        ),
        isTrue,
      );
      expect(
        widgetTapMarkFresh(
          markAtMs: now.millisecondsSinceEpoch,
          now: now.add(const Duration(milliseconds: 6100)),
        ),
        isFalse,
      );
      expect(
        widgetTapMarkFresh(
          markAtMs: now.millisecondsSinceEpoch,
          now: now.add(const Duration(seconds: 59)),
        ),
        isFalse,
      );
    });

    test('자국이 없으면 신선하지 않다', () {
      expect(widgetTapMarkFresh(markAtMs: null, now: now), isFalse);
    });
  });

  group('checkFailed의 기준 시각', () {
    test('직전 목록이 없어도 1970년이 되지 않는다', () {
      final failed = TodoWidgetPayload.checkFailed(null, now: now);

      // 이 갈래는 지금 note가 비어 있어 화면에 보이지 않지만, 값 자체가 거짓이면 다음에 note가
      // 붙는 순간 `오전 12:00 기준`이 찍힌다(2026-11-05 리뷰 정리 1건).
      expect(failed.updatedAtMs, now.millisecondsSinceEpoch);
      expect(failed.updatedAtMs, isNot(0));
      expect(failed.centerText, AppStrings.widgetCheckFailed);
      expect(failed.noteTone, TodoWidgetNoteTone.danger);
    });

    test('직전 목록이 있으면 그 기준 시각을 물려받는다', () {
      final previous = TodoWidgetPayload.fromTodos(
        [_todo('1', '장보기')],
        now: now,
      );

      final failed = TodoWidgetPayload.checkFailed(
        previous,
        now: now.add(const Duration(hours: 3)),
      );

      // 기준 시각은 "목록이 언제 것인가"를 뜻한다. 실패한 시각이 아니다.
      expect(failed.updatedAtMs, previous.updatedAtMs);
    });
  });

  // 2026-11-19(추가 범위 3 K): 체크의 결말을 **목록을 다시 받지 않고** 만든다. 서버 쓰기가 끝난
  // 뒤에만 불리므로 거짓 성공이 아니고(낙관 반영과 다른 자리다), 거는 조건은 하나다 —
  // **보이는 것이 "그 체크만큼만" 바뀐다.**
  group('applyCheck', () {
    TodoWidgetPayload cacheOf(List<Todo> todos, {String? justCheckedId}) =>
        TodoWidgetPayload.fromTodos(
          todos,
          now: now,
          justCheckedId: justCheckedId,
        );

    test('그 항목만 완료가 되고 배열 순서는 그대로다', () {
      final cached = cacheOf([
        _todo('1', '장보기'),
        _todo('2', '운동하기'),
        _todo('3', '책 반납'),
      ]);

      final next = TodoWidgetPayload.applyCheck(
        cached,
        todoId: '2',
        done: true,
      )!;

      // 그리는 순서(= position)가 바뀌면 체크한 줄이 목록 맨 아래로 뛰어내린다.
      expect(next.items.map((item) => item.id), ['1', '2', '3']);
      expect(next.items.map((item) => item.done), [false, true, false]);
      expect(next.items.map((item) => item.title), ['장보기', '운동하기', '책 반납']);
    });

    test('되돌리면 그 반대다', () {
      final cached = cacheOf([
        _todo('1', '장보기'),
        _todo('2', '운동하기', isDone: true),
      ]);

      final next = TodoWidgetPayload.applyCheck(
        cached,
        todoId: '2',
        done: false,
      )!;

      expect(next.items.map((item) => item.id), ['1', '2']);
      expect(next.items.map((item) => item.done), [false, false]);
    });

    test('totalCount가 ∓1 되고 그 외 N개는 그대로다', () {
      final cached = cacheOf([
        for (var i = 0; i < 10; i++) _todo('$i', '할 일 $i'),
      ]);
      final before = visibleRows(cached.items, cached.totalCount, 3);

      final next = TodoWidgetPayload.applyCheck(
        cached,
        todoId: '0',
        done: true,
      )!;
      final after = visibleRows(next.items, next.totalCount, 3);

      expect(cached.totalCount, 10);
      expect(next.totalCount, 9);
      // 보이는 미완료도 하나 줄기 때문에 `그 외 N개`는 움직이지 않는다 — 이것이 "그 체크만큼만"의
      // 핵심이다(헤더·다른 줄·그 외 N개가 그 체크와 어긋나게 바뀌면 안 된다).
      expect(after.moreCount, before.moreCount);

      final back = TodoWidgetPayload.applyCheck(
        next,
        todoId: '0',
        done: false,
      )!;
      expect(back.totalCount, 10);
    });

    test('머리 줄은 미리 만들어 둔 대체 문장을 고르기만 한다', () {
      final cached = cacheOf([
        _todo('1', '장보기'),
        _todo('2', '운동하기', isDone: true),
        _todo('3', '책 반납'),
      ]);

      expect(cached.header, AppStrings.widgetHeaderCount(done: 1, total: 3));

      final checked = TodoWidgetPayload.applyCheck(
        cached,
        todoId: '1',
        done: true,
      )!;
      final unchecked = TodoWidgetPayload.applyCheck(
        cached,
        todoId: '2',
        done: false,
      )!;

      expect(checked.header, cached.headerAfterCheck);
      expect(checked.header, AppStrings.widgetHeaderCount(done: 2, total: 3));
      expect(unchecked.header, cached.headerAfterUncheck);
      expect(unchecked.header, AppStrings.widgetHeaderCount(done: 0, total: 3));
    });

    test('대체 문장이 없으면 직전 머리 줄을 그대로 둔다', () {
      // 옛 캐시(대체 문장을 모르는 판)를 흉내 낸다. 개수가 1~2초 늦게 맞을 뿐 거짓이 아니다.
      const cached = TodoWidgetPayload(
        items: [TodoWidgetItem(id: '1', title: '장보기', rank: 0)],
        totalCount: 1,
        updatedAtMs: 100,
        header: '할 일 0/1',
      );

      final next = TodoWidgetPayload.applyCheck(
        cached,
        todoId: '1',
        done: true,
      )!;

      expect(next.header, '할 일 0/1');
    });

    test('rank를 다시 매기고 방금 누른 완료 줄이 0을 받는다', () {
      final cached = cacheOf([
        _todo('1', '장보기'),
        _todo('2', '운동하기'),
        _todo('3', '책 반납'),
      ]);

      final next = TodoWidgetPayload.applyCheck(
        cached,
        todoId: '2',
        done: true,
      )!;

      // 방금 누른 줄은 어떤 줄 자리 수에서도 보여야 하므로 0이다(design 2.2.2).
      expect(next.items.firstWhere((item) => item.id == '2').rank, 0);
      expect(next.items.firstWhere((item) => item.id == '1').rank, 1);
      expect(next.items.firstWhere((item) => item.id == '3').rank, 2);
      // 한 줄짜리 위젯에서도 그 줄이 보인다.
      expect(visibleRows(next.items, next.totalCount, 1).rows.single.id, '2');
    });

    test('완료가 되면 기한 키 셋이 빠진다', () {
      final cached = cacheOf([
        _todo('1', '장보기', dueAt: DateTime.utc(2026, 11, 4, 9)),
      ]);
      expect(cached.items.single.dueAtMs, isNotNull);

      final next = TodoWidgetPayload.applyCheck(
        cached,
        todoId: '1',
        done: true,
      )!;

      // 완료 줄에는 기한을 보여 주지 않는다 — 그 규칙을 Dart가 캐시에서 끝낸다.
      final item = next.items.single;
      expect(item.due, isNull);
      expect(item.dueOver, isNull);
      expect(item.dueAtMs, isNull);
      expect(item.toJson().containsKey('dueAtMs'), isFalse);
    });

    test('미완료가 0이 되면 다 끝냈다고 말하고 다시 생기면 기준 시각으로 돌아온다', () {
      final cached = cacheOf([_todo('1', '장보기')]);

      final allDone = TodoWidgetPayload.applyCheck(
        cached,
        todoId: '1',
        done: true,
      )!;
      expect(allDone.note, AppStrings.widgetAllDone);

      final back = TodoWidgetPayload.applyCheck(
        allDone,
        todoId: '1',
        done: false,
      )!;
      expect(back.note, AppStrings.widgetNoteFresh(formatWidgetTime(now)));
    });

    test('앞선 체크 실패는 이번 성공으로 지워진다', () {
      final failed = TodoWidgetPayload.checkFailed(
        cacheOf([_todo('1', '장보기'), _todo('2', '운동하기')]),
        now: now,
      );
      expect(failed.noteTone, TodoWidgetNoteTone.danger);

      final next = TodoWidgetPayload.applyCheck(
        failed,
        todoId: '1',
        done: true,
      )!;

      // 성공한 화면에 `체크하지 못했어요`를 색만 내려 남겨 두면 그것이 더 나쁜 거짓말이다.
      expect(next.noteTone, TodoWidgetNoteTone.muted);
      expect(next.note, isNot(AppStrings.widgetCheckFailed));
      expect(next.note, AppStrings.widgetNoteFresh(formatWidgetTime(now)));
    });

    test('못 불러왔다는 사실은 그대로 남는다', () {
      final stale = TodoWidgetPayload.fetchFailed(
        cacheOf([_todo('1', '장보기'), _todo('2', '운동하기')]),
        now: now.add(const Duration(hours: 2)),
      );

      final next = TodoWidgetPayload.applyCheck(
        stale,
        todoId: '1',
        done: true,
      )!;

      // 체크가 성공했다고 목록이 새것이 되지는 않는다.
      expect(next.note, stale.note);
      expect(next.note, AppStrings.widgetNoteStale(formatWidgetTime(now)));
    });

    test('기준 시각을 앞당기지 않는다', () {
      final cached = cacheOf([_todo('1', '장보기'), _todo('2', '운동하기')]);

      final next = TodoWidgetPayload.applyCheck(
        cached,
        todoId: '1',
        done: true,
      )!;

      // 재조회를 없앴으면 "지금 받아왔다"고 말하지 않는다.
      expect(next.updatedAtMs, cached.updatedAtMs);
      expect(next.note, AppStrings.widgetNoteFresh(formatWidgetTime(now)));
    });

    test('지름길이 성립하지 않으면 null이다(느린 길이 남는다)', () {
      final cached = cacheOf([_todo('1', '장보기', isDone: true)]);

      // 캐시가 없다.
      expect(
        TodoWidgetPayload.applyCheck(null, todoId: '1', done: true),
        isNull,
      );
      // 줄이 없는 안내 화면(로그아웃·할 일 없음)에서 온 탭.
      expect(
        TodoWidgetPayload.applyCheck(
          TodoWidgetPayload.loggedOut(now: now),
          todoId: '1',
          done: true,
        ),
        isNull,
      );
      // 목록에 아예 없는 id.
      expect(
        TodoWidgetPayload.applyCheck(cached, todoId: '9', done: true),
        isNull,
      );
      // 이미 목표 값이다.
      expect(
        TodoWidgetPayload.applyCheck(cached, todoId: '1', done: true),
        isNull,
      );
    });

    test('캐시를 되읽은 뒤에도 같은 결말을 만든다', () {
      final cached = TodoWidgetPayload.decode(
        cacheOf([
          _todo('11111111-1111-1111-1111-111111111111', '장보기'),
          _todo('22222222-2222-2222-2222-222222222222', '운동하기'),
        ]).encode(),
      );

      final next = TodoWidgetPayload.applyCheck(
        cached,
        todoId: '11111111-1111-1111-1111-111111111111',
        done: true,
      )!;

      // 백그라운드 isolate가 실제로 쓰는 재료는 **되읽은 캐시**다. 대체 머리 줄이 왕복을
      // 견디지 못하면 개수가 어긋난다.
      expect(next.items.first.done, isTrue);
      expect(next.header, AppStrings.widgetHeaderCount(done: 1, total: 2));
      expect(next.totalCount, 1);
    });
  });

  group('todosWithDone', () {
    test('그 id만 바뀌고 순서와 나머지 필드는 그대로다', () {
      final todos = [
        _todo('1', '장보기', dueAt: DateTime.utc(2026, 11, 4, 9)),
        _todo('2', '운동하기'),
      ];

      final next = todosWithDone(todos, '1', true);

      expect(next.map((todo) => todo.id), ['1', '2']);
      expect(next.map((todo) => todo.isDone), [true, false]);
      expect(next.first.title, '장보기');
      expect(next.first.dueAt, todos.first.dueAt);
      expect(next.first.createdAt, todos.first.createdAt);
      // 들어온 목록을 제자리에서 고치지 않는다(앱 화면이 들고 있는 목록이다).
      expect(todos.first.isDone, isFalse);
    });

    test('없는 id면 목록이 그대로다', () {
      final todos = [_todo('1', '장보기')];

      final next = todosWithDone(todos, '9', true);

      expect(next.map((todo) => todo.isDone), [false]);
    });
  });

  group('기준 시각(basisAt)', () {
    test('주면 그 시각이 기준이 되고, 주지 않으면 지금이다', () {
      final todos = [_todo('1', '장보기')];
      final later = now.add(const Duration(hours: 3));
      final basis = now.millisecondsSinceEpoch;

      final kept = TodoWidgetPayload.fromTodos(
        todos,
        now: later,
        basisAt: basis,
      );
      final fresh = TodoWidgetPayload.fromTodos(todos, now: later);

      // 체크는 목록을 새로 받아온 것이 아니다 — "지금 받아왔다"고 말하지 않는다.
      expect(kept.updatedAtMs, basis);
      expect(kept.note, AppStrings.widgetNoteFresh(formatWidgetTime(now)));
      expect(fresh.updatedAtMs, later.millisecondsSinceEpoch);
      expect(fresh.note, AppStrings.widgetNoteFresh(formatWidgetTime(later)));
    });

    test('기한 문장은 기준 시각이 아니라 기기 시계로 만든다', () {
      final tomorrow = DateTime(2026, 11, 5, 9, 14);

      final payload = TodoWidgetPayload.fromTodos(
        [_todo('1', '장보기', dueAt: DateTime(2026, 11, 5, 18).toUtc())],
        now: tomorrow,
        basisAt: now.millisecondsSinceEpoch,
      );

      // "오늘인가"를 가르는 것은 목록의 나이가 아니라 기기 시계다.
      expect(payload.items.single.due, formatWidgetTime(DateTime(2026, 11, 5, 18)));
    });
  });

  group('대체 머리 줄과 실패 한 줄', () {
    test('줄이 보이는 상태에서만 대체 문장을 싣는다', () {
      final normal = TodoWidgetPayload.fromTodos(
        [_todo('1', '장보기'), _todo('2', '운동하기', isDone: true)],
        now: now,
      );

      expect(normal.toJson()['headerAfterCheck'], '할 일 2/2');
      expect(normal.toJson()['headerAfterUncheck'], '할 일 0/2');
      // 조회 실패·체크 실패는 목록을 그대로 들고 가므로 그 줄을 누를 수 있다 → 함께 물려받는다.
      for (final payload in [
        TodoWidgetPayload.fetchFailed(normal, now: now),
        TodoWidgetPayload.checkFailed(normal, now: now),
      ]) {
        expect(payload.headerAfterCheck, normal.headerAfterCheck);
        expect(payload.headerAfterUncheck, normal.headerAfterUncheck);
      }
      // 줄이 없는 상태에는 셀 목록도 누를 줄도 없다.
      for (final payload in [
        TodoWidgetPayload.loggedOut(now: now),
        TodoWidgetPayload.loading(now: now),
        TodoWidgetPayload.fromTodos(const [], now: now),
        TodoWidgetPayload.fetchFailed(null, now: now),
      ]) {
        expect(payload.toJson().containsKey('headerAfterCheck'), isFalse);
        expect(payload.toJson().containsKey('headerAfterUncheck'), isFalse);
      }
    });

    test('완료가 0이면 되돌릴 문장이 없고 전부 완료면 체크할 문장이 없다', () {
      final none = TodoWidgetPayload.fromTodos([_todo('1', '장보기')], now: now);
      final all = TodoWidgetPayload.fromTodos(
        [_todo('1', '장보기', isDone: true)],
        now: now,
      );

      expect(none.headerAfterCheck, '할 일 1/1');
      expect(none.headerAfterUncheck, isNull);
      // `할 일 2/1`은 거짓이다 — 더 체크할 것이 없으면 말하지 않는다.
      expect(all.headerAfterCheck, isNull);
      expect(all.headerAfterUncheck, '할 일 0/1');
    });

    test('되돌림을 설명할 한 줄은 어떤 상태에도 함께 실린다', () {
      // 네이티브가 자국이 지난 줄을 되돌릴 때 그 자리에서 고를 수 있어야 한다(조건 ①).
      for (final payload in [
        TodoWidgetPayload.fromTodos([_todo('1', '장보기')], now: now),
        TodoWidgetPayload.loggedOut(now: now),
        TodoWidgetPayload.loading(now: now),
      ]) {
        expect(payload.toJson()['failNote'], AppStrings.widgetCheckFailed);
      }
    });

    test('왕복에서 대체 문장이 보존된다', () {
      final payload = TodoWidgetPayload.fromTodos(
        [_todo('1', '장보기'), _todo('2', '운동하기', isDone: true)],
        now: now,
      );

      final decoded = TodoWidgetPayload.decode(payload.encode())!;

      expect(decoded.headerAfterCheck, payload.headerAfterCheck);
      expect(decoded.headerAfterUncheck, payload.headerAfterUncheck);
    });
  });
}

/// **네이티브가 캐시에 찍는 탭 자국**을 흉내 낸다(design 2.2.3).
///
/// Dart에는 그 넷을 **쓰는 코드가 없다**(`toJson`이 싣지 않는다 — 그것이 "결말이 자국을 걷는다"의
/// 구현이다). 그래서 캐시 JSON에 직접 얹어 되읽는다 — 백그라운드 콜백이 실제로 읽는 재료와 같은
/// 모양이다.
TodoWidgetPayload _withTapMark(
  TodoWidgetPayload payload, {
  required String todoId,
  required DateTime at,
  bool done = true,
  String mode = 'writing',
}) {
  final json = payload.toJson();
  json['pendingId'] = todoId;
  json['pendingAtMs'] = at.millisecondsSinceEpoch;
  json['pendingDone'] = done;
  json['pendingMode'] = mode;
  return TodoWidgetPayload.fromJson(json)!;
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
