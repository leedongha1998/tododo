import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthState, User;

import 'package:todododo/core/strings.dart';
import 'package:todododo/core/theme/app_icons.dart';
import 'package:todododo/features/auth/data/auth_repository.dart';
import 'package:todododo/features/auth/domain/auth_providers.dart';
import 'package:todododo/features/battle/domain/battle_providers.dart';
import 'package:todododo/features/todo/data/todo.dart';
import 'package:todododo/features/todo/data/todo_repository.dart';
import 'package:todododo/features/todo/domain/todo_providers.dart';
import 'package:todododo/features/todo/presentation/todo_list_screen.dart';

import '../../core/push/push_fakes.dart';
import '../../helpers/text_finders.dart';
import 'due_alarm_fakes.dart';

/// 손으로 끌어 순서를 바꾸는 길 전부(todo-reorder spec "끌어서 옮기기"·"저장 실패").
///
/// 자리 값(`position`) 계산은 서버(`move_todo`)에 있어 여기서 볼 수 없다. 여기서 보는 것은
/// **화면이 서버에 무엇을 보내는가**(기준 할 일 하나)와 **실패했을 때 무엇을 되돌리는가**다.
/// 가짜 레포지토리가 "기준 바로 아래로 옮긴다"는 서버의 약속만 흉내 내어 목록을 들고 있다.
///
/// **끌기는 줄을 꾹 눌러 시작한다**(2026-11-10 오너 확정 — 전용 손잡이를 없앴다). 그래서 이
/// 파일은 제스처가 갈리는 세 갈래도 함께 고정한다: 짧게 누르면 수정, 꾹 누르면 집기(놓아도
/// 수정이 열리지 않는다), 쥐지 않고 밀면 스크롤.
void main() {
  testWidgets('줄을 꾹 눌러 끌면 그 할 일을 새 기준 아래로 옮긴다', (tester) async {
    final repository = _FakeTodoRepository(_todos());

    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();

    await _longPressDragRow(tester, index: 0, rows: 1);

    // 첫 줄을 한 칸 내렸으니 기준은 둘째 줄이었던 '빨래하기'다. 자리 값은 보내지 않는다.
    expect(repository.moves, hasLength(1));
    expect(repository.moves.single.todoId, '1');
    expect(repository.moves.single.afterId, '2');
    expect(_titleOrder(tester), ['빨래하기', '장보기', '설거지하기']);
  });

  testWidgets('맨 위로 끌면 기준 없이(afterId == null) 보낸다', (tester) async {
    final repository = _FakeTodoRepository(_todos());

    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();

    await _longPressDragRow(tester, index: 2, rows: -2);

    expect(repository.moves.single.todoId, '3');
    expect(repository.moves.single.afterId, isNull);
    expect(_titleOrder(tester), ['설거지하기', '장보기', '빨래하기']);
  });

  testWidgets('맨 아래로 끌면 마지막 줄의 아래로 보낸다', (tester) async {
    final repository = _FakeTodoRepository(_todos());

    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();

    await _longPressDragRow(tester, index: 0, rows: 2);

    expect(repository.moves.single.todoId, '1');
    expect(repository.moves.single.afterId, '3');
    expect(_titleOrder(tester), ['빨래하기', '설거지하기', '장보기']);
  });

  // 꾹 쥐지 않고 바로 미는 세로 이동은 스크롤이다 — 목록을 훑는 일이 어려워지면 안 된다(spec).
  testWidgets('꾹 누르지 않고 끌면 순서를 바꾸지 않는다(= 스크롤이다)', (tester) async {
    final repository = _FakeTodoRepository(_todos());

    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(
      tester.getCenter(findText('장보기')),
    );
    await gesture.moveBy(const Offset(0, 20));
    await tester.pump();
    await gesture.moveBy(const Offset(0, 100));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(repository.moves, isEmpty);
    expect(_titleOrder(tester), ['장보기', '빨래하기', '설거지하기']);
  });

  // 제스처가 겹치는 지점이다 — 줄 전체가 끌기의 입구이면서 짧게 누르면 수정이기 때문이다.
  // 꾹 눌러 옮긴 사용자는 수정을 요청한 적이 없다(2026-11-10 메인 세션 확정).
  testWidgets('꾹 눌러 끌어 놓았을 때 수정 대화상자가 열리지 않는다', (tester) async {
    final repository = _FakeTodoRepository(_todos());

    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();

    await _longPressDragRow(tester, index: 0, rows: 1);

    expect(repository.moves, hasLength(1));
    expect(findText(AppStrings.editTodo), findsNothing);
    expect(find.byType(TextField), findsNothing);
  });

  // 집었다가 **옮기지 않고** 놓는 길. 여기서 수정이 열리면 "꾹 누르기"가 수정의 느린 입구가 된다.
  testWidgets('꾹 눌러 집었다가 제자리에 놓아도 수정 대화상자가 열리지 않는다', (tester) async {
    final repository = _FakeTodoRepository(_todos());

    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();

    final gesture = await _pickUpRow(tester, index: 0);
    await gesture.up();
    await tester.pumpAndSettle();

    expect(findText(AppStrings.editTodo), findsNothing);
    // 제자리면 서버를 부르지 않는다(끌기도 일어나지 않았다).
    expect(repository.moves, isEmpty);
    expect(_titleOrder(tester), ['장보기', '빨래하기', '설거지하기']);
  });

  testWidgets('짧게 누르면 수정 대화상자가 열린다', (tester) async {
    final repository = _FakeTodoRepository(_todos());

    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();

    await tester.tap(findText('장보기'));
    await tester.pumpAndSettle();

    expect(findText(AppStrings.editTodo), findsOneWidget);
    expect(repository.moves, isEmpty);
  });

  // 가장 자주 쓰는 동작(체크)과 가장 비싼 동작(삭제)이 끌기 때문에 어려워지면 안 된다(spec).
  testWidgets('체크박스와 삭제는 짧게 누르면 그대로 동작한다', (tester) async {
    final repository = _FakeTodoRepository(_todos());

    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(AppStrings.delete).at(1));
    await tester.pumpAndSettle();

    expect(repository.doneCalls, [('1', true)]);
    expect(repository.deleteCalls, ['2']);
    // 짧은 탭이 끌기나 수정으로 번지지 않는다.
    expect(repository.moves, isEmpty);
    expect(findText(AppStrings.editTodo), findsNothing);
  });

  // 같은 두 버튼 위에서 **꾹** 눌렀을 때(짧은 탭은 위 테스트가 본다). 끌기의 입구가 줄 전체라
  // 버튼 위에서도 꾹 누를 수 있는데, 거기서 "가장 비싼 동작"이 저절로 일어나면 안 된다.
  // 실측 결과를 그대로 고정한다: 체크박스 위에서는 **줄이 집히고**(완료 토글은 일어나지 않는다),
  // 삭제 버튼 위에서는 **아무 일도 없다**(툴팁이 긴 누르기를 가져간다 — 삭제도, 끌기도 아니다).
  testWidgets('체크박스 위에서 꾹 누르면 줄이 집히고, 삭제 위에서 꾹 눌러도 지워지지 않는다', (tester) async {
    final repository = _FakeTodoRepository(_todos());

    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();

    await _longPressDragFrom(tester, find.byType(Checkbox).first, rows: 1);

    expect(repository.moves, hasLength(1));
    expect(repository.moves.single.todoId, '1');
    expect(repository.moves.single.afterId, '2');
    expect(repository.doneCalls, isEmpty);

    await _longPressDragFrom(
      tester,
      find.byTooltip(AppStrings.delete).first,
      rows: 1,
    );

    expect(repository.deleteCalls, isEmpty);
    expect(repository.moves, hasLength(1));
  });

  // 체크박스 위에서 **꾹 눌렀다 움직이지 않고 떼는** 갈래. 끌기 인식기가 탭을 가져가므로
  // **아무 일도 일어나지 않는다**(완료 토글도, 순서 변경도, 수정도 아니다. 손잡이가 있던 때는
  // 600ms를 눌러도 토글됐다 — 끌기 입구가 줄 전체가 되면서 "느린 탭으로 완료"가 사라졌다).
  //
  // **이 동작을 그대로 받아들이기로 했다**(2026-11-10 메인 세션): 대안은 끌기 입구를 제목 칸으로
  // 좁히는 것인데, 그러면 줄을 옮기려고 왼쪽을 잡았을 때 **할 일이 완료 처리된다** — 아무 일도
  // 안 나는 쪽이 싸다. 받아들인 동작이라 **테스트로 고정해 둔다**(나중에 조용히 바뀌지 않게).
  testWidgets('체크박스를 꾹 눌러 집었다 제자리에 놓으면 아무 일도 일어나지 않는다', (tester) async {
    final repository = _FakeTodoRepository(_todos());

    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(Checkbox).first),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 60));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(repository.doneCalls, isEmpty);
    expect(repository.moves, isEmpty);
    expect(findText(AppStrings.editTodo), findsNothing);
    expect(_titleOrder(tester), ['장보기', '빨래하기', '설거지하기']);
    // 완료는 **짧게** 누르면 그대로 된다(같은 화면에서 바로 확인한다).
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    expect(repository.doneCalls, [('1', true)]);
  });

  testWidgets('완료한 할 일도 꾹 눌러 같은 방법으로 옮겨진다', (tester) async {
    final repository = _FakeTodoRepository(_todos(doneIndex: 1));

    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();

    // 어떤 줄은 잡히고 어떤 줄은 안 잡히는 목록을 만들지 않는다(spec 확정 결정 2).
    expect(
      find.byType(ReorderableDelayedDragStartListener),
      findsNWidgets(3),
    );

    await _longPressDragRow(tester, index: 1, rows: 1);

    expect(repository.moves.single.todoId, '2');
    expect(repository.moves.single.afterId, '3');
    expect(_titleOrder(tester), ['장보기', '설거지하기', '빨래하기']);
  });

  // 손잡이가 없어진 뒤 **스크린리더 사용자가 순서를 바꾸는 유일한 수단**이 이 시맨틱 액션이다
  // (spec "깨지면 안 되는 것"의 2026-11-10 추가 조항). `SliverReorderableList`가 줄마다 붙여
  // 주는 것이고 우리가 만든 UI가 아니지만, **리스너를 감싸는 자리나 `onReorderItem`을 손대면
  // 조용히 깨진다** — 그래서 라벨이 있다는 것으로 끝내지 않고 **서버 저장까지** 확인한다.
  //
  // 액션 수는 줄 위치에 따라 다르다: 첫 줄·마지막 줄은 **둘**(첫 줄에 "위로"가 없는 것이 맞는
  // 동작이다), 가운데 줄은 넷. 라벨은 이 테스트 환경의 기본 번역(`DefaultWidgetsLocalizations`)
  // 에서 가져온다 — 앱은 `locale: ko` 고정이라 사용자에게는 같은 액션이 한국어로 읽힌다.
  testWidgets('스크린리더의 "아래로 이동" 액션으로도 순서가 바뀌고 서버에 저장된다', (tester) async {
    final repository = _FakeTodoRepository(_todos());
    // `addTearDown`으로 치우면 안 된다 — 테스트 끝 검사가 tearDown보다 먼저 돌아
    // "SemanticsHandle이 살아 있다"로 실패한다. 본문 끝에서 직접 치운다.
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();

    const localizations = DefaultWidgetsLocalizations();
    // 시맨틱 트리의 주인은 아무 노드에서나 얻는다(`pipelineOwner`는 폐기됐다).
    final owner = tester.getSemantics(findText('장보기')).owner!;
    final rows = _reorderActionNodes(owner.rootSemanticsNode!);
    expect(rows, hasLength(3));
    expect(_actionLabels(rows.first), [
      localizations.reorderItemDown,
      localizations.reorderItemToEnd,
    ]);
    expect(_actionLabels(rows[1]), hasLength(4));
    expect(_actionLabels(rows.last), [
      localizations.reorderItemToStart,
      localizations.reorderItemUp,
    ]);

    owner.performAction(
      rows.first.id,
      SemanticsAction.customAction,
      _actionId(rows.first, localizations.reorderItemDown),
    );
    await tester.pumpAndSettle();

    // 끌기와 **같은 길**을 지난다(planTodoMove → moveTodo). 기준도 같다.
    expect(repository.moves.single.todoId, '1');
    expect(repository.moves.single.afterId, '2');
    expect(_titleOrder(tester), ['빨래하기', '장보기', '설거지하기']);

    semantics.dispose();
  });

  // 새 할 일이 화면 밖에 생기면 저장이 됐는지 알 수 없다(spec "새 할 일" 수용 기준 3번).
  testWidgets('할 일을 추가하면 그것이 생긴 맨 아래를 보여 준다', (tester) async {
    final repository = _FakeTodoRepository(_longList());

    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();

    final list = tester.widget<ReorderableListView>(
      find.byType(ReorderableListView),
    );
    final controller = list.scrollController!;
    expect(controller.offset, 0);

    await tester.tap(find.byIcon(AppIcons.add));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '우산 챙기기');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(controller.offset, controller.position.maxScrollExtent);
    expect(findText('우산 챙기기'), findsOneWidget);
  });

  testWidgets('저장이 실패하면 끌기 전 순서로 되돌리고 알린다', (tester) async {
    final repository = _FakeTodoRepository(
      _todos(),
      moveError: Exception('network down'),
    );

    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();

    await _longPressDragRow(tester, index: 0, rows: 1);

    // 조용히 넘어가지 않는다 — 순서는 사용자가 방금 한 조작 그 자체다.
    expect(findText(AppStrings.todoReorderFailed), findsOneWidget);
    // 저장 문구(saveTodoFailed)와 섞이지 않는다.
    expect(findText(AppStrings.saveTodoFailed), findsNothing);
    expect(_titleOrder(tester), ['장보기', '빨래하기', '설거지하기']);
  });

  testWidgets('순서 저장이 실패해도 방금 한 완료가 함께 되돌아가지 않는다', (tester) async {
    final repository = _FakeTodoRepository(
      _todos(),
      moveError: Exception('network down'),
    );

    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    expect(repository.doneCalls, [('1', true)]);

    await _longPressDragRow(tester, index: 0, rows: 1);

    // 되돌린 것은 순서뿐이다. 완료를 취소하는 쓰기가 새로 나가지 않는다.
    expect(findText(AppStrings.todoReorderFailed), findsOneWidget);
    expect(repository.doneCalls, [('1', true)]);
  });

  // 겹친 끌기(앞 끌기의 답을 기다리는 동안 또 끄는 것). 두 가지를 본다 — ① 서버로는 **한 번에
  // 하나씩, 끈 순서대로** 나간다, ② 앞 끌기의 재조회가 **뒤 끌기의 화면을 되돌리지 않는다**.
  testWidgets('끌기가 겹치면 끈 순서대로 하나씩 나가고 화면이 튀지 않는다', (tester) async {
    final repository = _FakeTodoRepository(_todos(), gateMoves: true);

    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();

    await _longPressDragRow(tester, index: 0, rows: 1);
    expect(repository.moves, hasLength(1));
    expect(_titleOrder(tester), ['빨래하기', '장보기', '설거지하기']);

    // 앞 끌기가 아직 답을 받지 못한 상태에서 또 끈다.
    await _longPressDragRow(tester, index: 2, rows: -2);
    // 두 번째 호출은 **줄에서 기다린다**(동시에 나가지 않는다).
    expect(repository.moves, hasLength(1));
    expect(_titleOrder(tester), ['설거지하기', '빨래하기', '장보기']);

    // 앞 끌기만 성공시킨다 → 그 재조회가 돌아온다.
    repository.answerOne();
    await tester.pumpAndSettle();

    // 이제 두 번째가 나갔고, 화면은 앞 끌기까지만 반영된 순서로 **되돌아가지 않았다**.
    expect(repository.moves, hasLength(2));
    expect(repository.moves[0].todoId, '1');
    expect(repository.moves[0].afterId, '2');
    expect(repository.moves[1].todoId, '3');
    expect(repository.moves[1].afterId, isNull);
    expect(_titleOrder(tester), ['설거지하기', '빨래하기', '장보기']);

    repository.answerOne();
    await tester.pumpAndSettle();

    // 서버가 둘을 그 순서로 적용한 결과와 화면이 같다.
    expect(_titleOrder(tester), ['설거지하기', '빨래하기', '장보기']);
  });

  // spec "P0. 저장 실패"의 마지막 규칙: 되돌리는 사이 사용자가 또 끌었으면 **그 조작을 내 실패로
  // 덮지 않는다**(나중 끌기가 자기 결말을 낸다).
  testWidgets('실패를 되돌릴 때 그 사이 한 끌기를 덮지 않는다', (tester) async {
    final repository = _FakeTodoRepository(
      _todos(),
      gateMoves: true,
      moveError: Exception('network down'),
    );

    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();

    await _longPressDragRow(tester, index: 0, rows: 1);
    await _longPressDragRow(tester, index: 2, rows: -2);
    expect(_titleOrder(tester), ['설거지하기', '빨래하기', '장보기']);

    // 앞 끌기만 답한다(실패).
    repository.answerOne();
    await tester.pumpAndSettle();

    expect(findText(AppStrings.todoReorderFailed), findsOneWidget);
    // 끌기 전 순서(['장보기', '빨래하기', '설거지하기'])로 되돌리지 않는다 — 나중 끌기의 순서다.
    expect(_titleOrder(tester), ['설거지하기', '빨래하기', '장보기']);
  });

  testWidgets('실패한 뒤 다시 끌면 저장된다', (tester) async {
    final repository = _FakeTodoRepository(
      _todos(),
      moveError: Exception('network down'),
    );

    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();

    await _longPressDragRow(tester, index: 0, rows: 1);
    expect(repository.moves, hasLength(1));

    repository.moveError = null;
    await _longPressDragRow(tester, index: 0, rows: 1);

    expect(repository.moves, hasLength(2));
    expect(repository.moves.last.afterId, '2');
    expect(_titleOrder(tester), ['빨래하기', '장보기', '설거지하기']);
  });
}

/// 줄 하나의 높이(최소 60 + 줄 간격 12). 끌어 옮기는 거리를 줄 수로 세는 기준이다.
const _rowExtent = 72.0;

/// [index]번째 줄을 **꾹 눌러 집은 뒤** [rows]줄만큼(양수는 아래로) 끌어 놓는다.
///
/// 먼저 `kLongPressTimeout`을 넘겨 쥔다 — 그 전에 움직이면 끌기가 아니라 스크롤이 된다
/// (`DelayedMultiDragGestureRecognizer`가 touch slop을 넘는 이동에 스스로 진다).
///
/// 그다음 **20dp 남짓씩 나눠 움직이고 걸음마다 프레임을 흘려 준다.** 한 번에 크게 밀면 목록이
/// 한 칸만 비켜 주고 끝난다 — 놓일 자리를 그 순간의 줄 위치로 계산하기 때문이다(한 번에 220dp를
/// 밀어도 한 줄만 내려가는 것을 확인했다). 반대로 걸음마다 `pumpAndSettle`을 하면 끌기 자체가
/// 인정되지 않는다.
Future<void> _longPressDragRow(
  WidgetTester tester, {
  required int index,
  required int rows,
}) {
  // 줄 묶음은 줄마다 하나이고 트리 순서 = 목록 순서다(= 쥐는 자리는 카드 가운데 = 제목 칸).
  return _longPressDragFrom(
    tester,
    find.byType(ReorderableDelayedDragStartListener).at(index),
    rows: rows,
  );
}

/// [target]의 가운데를 꾹 눌러 [rows]줄만큼 끌어 놓는다(버튼 위에서 꾹 누르는 길도 같은 헬퍼로
/// 본다 — 끌기의 입구는 줄 전체이므로 시작 자리마다 결과가 달라질 수 있다).
Future<void> _longPressDragFrom(
  WidgetTester tester,
  FinderBase<Element> target, {
  required int rows,
}) async {
  final gesture = await tester.startGesture(tester.getCenter(target));
  await tester.pump(kLongPressTimeout + const Duration(milliseconds: 60));
  final total = rows * _rowExtent;
  final steps = (total.abs() / 20).floor().clamp(1, 100);
  final step = total / steps;
  for (var i = 0; i < steps; i++) {
    await gesture.moveBy(Offset(0, step));
    await tester.pump(const Duration(milliseconds: 40));
  }
  await gesture.up();
  await tester.pumpAndSettle();
}

/// 시맨틱 트리에서 **순서 바꾸기 액션을 가진 노드**를 트리 순서(= 목록 순서)로 모은다.
/// `SliverReorderableList`가 줄마다 하나씩 붙인다.
List<SemanticsNode> _reorderActionNodes(SemanticsNode root) {
  final found = <SemanticsNode>[];
  void visit(SemanticsNode node) {
    final ids = node.getSemanticsData().customSemanticsActionIds;
    if (ids != null && ids.isNotEmpty) found.add(node);
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  visit(root);
  return found;
}

List<String?> _actionLabels(SemanticsNode node) => [
  for (final id in node.getSemanticsData().customSemanticsActionIds!)
    CustomSemanticsAction.getAction(id)!.label,
];

int _actionId(SemanticsNode node, String label) =>
    node.getSemanticsData().customSemanticsActionIds!.firstWhere(
      (id) => CustomSemanticsAction.getAction(id)!.label == label,
    );

/// [index]번째 줄을 꾹 눌러 집기만 한다(아직 놓지 않는다).
Future<TestGesture> _pickUpRow(WidgetTester tester, {required int index}) async {
  // 줄 묶음은 줄마다 하나이고 트리 순서 = 목록 순서다(= 쥐는 자리는 카드 가운데 = 제목 칸).
  final row = find.byType(ReorderableDelayedDragStartListener).at(index);
  final gesture = await tester.startGesture(tester.getCenter(row));
  await tester.pump(kLongPressTimeout + const Duration(milliseconds: 60));
  return gesture;
}

/// 화면에 보이는 줄 순서(위에서 아래로).
List<String> _titleOrder(WidgetTester tester) {
  final shown = [
    for (final title in _titles) (title, tester.getTopLeft(findText(title)).dy),
  ]..sort((a, b) => a.$2.compareTo(b.$2));
  return shown.map((entry) => entry.$1).toList();
}

const _titles = ['장보기', '빨래하기', '설거지하기'];

/// 한 화면에 들어가지 않는 목록(새 할 일이 화면 밖에 생기는 상황을 만든다).
List<Todo> _longList() {
  return [
    for (var i = 0; i < 20; i++)
      Todo(
        id: '$i',
        title: '할 일 $i번',
        isDone: false,
        createdAt: DateTime(2026, 11, 10, 8),
      ),
  ];
}

List<Todo> _todos({int? doneIndex}) {
  return [
    for (var i = 0; i < _titles.length; i++)
      Todo(
        id: '${i + 1}',
        title: _titles[i],
        isDone: i == doneIndex,
        createdAt: DateTime(2026, 11, 10, 8 + i),
      ),
  ];
}

Widget _app(TodoRepository repository) {
  return ProviderScope(
    overrides: [
      todoRepositoryProvider.overrideWithValue(repository),
      authRepositoryProvider.overrideWithValue(_SignedInAuthRepository()),
      // 실제 provider는 `supabase.auth`를 읽으므로 사용자 id만 가짜로 끼운다. 목록은 여전히
      // **레포지토리가 주는 순서** 그대로다(순서를 만드는 자리는 서버 하나다 — design 2장).
      todosProvider.overrideWith((ref) {
        return ref.watch(todoRepositoryProvider).fetchTodos('me');
      }),
      myBattlesProvider.overrideWith((ref) async => const []),
      ...pushOverrides(),
      ...dueAlarmOverrides(),
    ],
    child: const MaterialApp(home: TodoListScreen()),
  );
}

/// 쓰기 호출을 받아 적는 가짜(선례: `todo_input_dialog_test.dart`).
///
/// 목록을 들고 있으면서 `moveTodo`에 **"기준 바로 아래로 옮긴다"는 서버의 약속만** 흉내 낸다 —
/// 자리 값 산수(1024 간격·중간값·재번호)는 흉내 내지 않는다. 그건 SQL의 몫이고 이 테스트가
/// 볼 수 있는 것이 아니다(design 9장).
class _FakeTodoRepository implements TodoRepository {
  _FakeTodoRepository(this._stored, {this.moveError, this.gateMoves = false});

  final List<Todo> _stored;

  /// 순서 저장이 실패하는 상황을 만든다. 테스트 중에 비워 "다시 끌면 저장된다"를 본다.
  Object? moveError;

  /// true면 `moveTodo`가 **답하지 않고 기다린다**([answerOne]으로 하나씩 답한다). 끌기가 겹치는
  /// 상황을 만드는 장치다.
  final bool gateMoves;

  /// 아직 답하지 않은 호출들(보낸 순서).
  final _gates = <Completer<void>>[];

  final moves = <_Move>[];
  final doneCalls = <(String, bool)>[];
  final deleteCalls = <String>[];

  /// 기다리는 호출 하나를 답하게 한다(보낸 순서대로).
  void answerOne() => _gates.removeAt(0).complete();

  @override
  Future<List<Todo>> fetchTodos(String userId) async => List.of(_stored);

  @override
  Future<void> moveTodo(String todoId, {required String? afterId}) async {
    moves.add(_Move(todoId: todoId, afterId: afterId));
    if (gateMoves) {
      final gate = Completer<void>();
      _gates.add(gate);
      await gate.future;
    }
    final error = moveError;
    if (error != null) throw error;
    final moved = _stored.removeAt(
      _stored.indexWhere((todo) => todo.id == todoId),
    );
    final at = afterId == null
        ? 0
        : _stored.indexWhere((todo) => todo.id == afterId) + 1;
    _stored.insert(at, moved);
  }

  @override
  Future<void> setDone(String id, bool isDone) async {
    doneCalls.add((id, isDone));
  }

  @override
  Future<void> addTodo(String userId, String title, {DateTime? dueAt}) async {
    // 새 할 일은 맨 아래다 — 서버에서는 position 컬럼 기본값이 그 자리를 만든다(design 1.5).
    _stored.add(
      Todo(
        id: 'new-${_stored.length + 1}',
        title: title,
        isDone: false,
        createdAt: DateTime(2026, 11, 10, 20),
        dueAt: dueAt,
      ),
    );
  }

  @override
  Future<void> updateTodo(
    String id, {
    required String title,
    required DateTime? dueAt,
  }) async {}

  @override
  Future<void> deleteTodo(String id) async {
    deleteCalls.add(id);
    _stored.removeWhere((todo) => todo.id == id);
  }
}

class _Move {
  const _Move({required this.todoId, required this.afterId});

  final String todoId;
  final String? afterId;
}

class _SignedInAuthRepository implements AuthRepository {
  @override
  Stream<AuthState> get authStateChanges => const Stream.empty();

  @override
  User? get currentUser => const User(
    id: 'me',
    appMetadata: {},
    userMetadata: {},
    aud: 'authenticated',
    createdAt: '2026-11-10T00:00:00Z',
  );

  @override
  Future<void> signInWithGoogle() async {}

  @override
  Future<void> signOut() async {}

  @override
  Future<void> deleteAccount() async {}
}
