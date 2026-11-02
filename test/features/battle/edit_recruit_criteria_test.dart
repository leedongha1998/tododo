import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:todododo/core/strings.dart';
import 'package:todododo/features/battle/data/battle.dart';
import 'package:todododo/features/battle/data/battle_criteria_repository.dart';
import 'package:todododo/features/battle/data/battle_repository.dart';
import 'package:todododo/features/battle/data/criteria_check_result.dart';
import 'package:todododo/features/battle/domain/battle_providers.dart';
import 'package:todododo/features/battle/presentation/edit_recruit_criteria_screen.dart';

/// mobile-ux M7: 모집 기준 수정 화면도 재검사로 하루 10회 중 1회를 쓴다.
/// 그 결과를 들고 있을 때만 뒤로가기를 막고, 고치는 중에는 막지 않는다.
class _FakeCriteriaRepository implements BattleCriteriaRepository {
  int checkCount = 0;

  @override
  Future<CriteriaCheckResult> generate({
    required String title,
    required String type,
    required int durationMinutes,
  }) =>
      throw UnimplementedError();

  @override
  Future<CriteriaCheckResult> check({
    required String title,
    required String type,
    required int durationMinutes,
    required List<String> minCriteria,
    List<String>? superiorityCriteria,
    String? battleId,
  }) async {
    checkCount++;
    return CriteriaCheckResult(
      checkId: 'check-$checkCount',
      provable: true,
      minCriteria: minCriteria,
      callsLeft: 8,
    );
  }
}

class _FakeBattleRepository implements BattleRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final _recruit = Battle(
  id: 'b1',
  type: 'speed',
  status: 'pending',
  title: '아침 7시 기상',
  creatorId: 'me',
  createdAt: DateTime(2026, 11, 2),
  durationMinutes: 1440,
  minCriteria: const ['시계가 7시 이전을 가리킨다'],
);

const _hostLabel = '기준 수정 열기';

Future<_FakeCriteriaRepository> _pushEdit(WidgetTester tester) async {
  final criteria = _FakeCriteriaRepository();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        battleCriteriaRepositoryProvider.overrideWithValue(criteria),
        battleRepositoryProvider.overrideWithValue(_FakeBattleRepository()),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => EditRecruitCriteriaScreen(battle: _recruit),
                ),
              ),
              child: const Text(_hostLabel),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text(_hostLabel));
  await tester.pumpAndSettle();
  return criteria;
}

/// 시스템 뒤로가기·앱바 뒤로가기와 같은 길. `Navigator.pop`은 `PopScope`를 거치지 않는다.
Future<void> _back(WidgetTester tester) async {
  await tester.state<NavigatorState>(find.byType(Navigator)).maybePop();
  await tester.pumpAndSettle();
}

/// 기준 한 칸을 고친다(마지막 TextField가 기준 입력칸이다).
Future<void> _editCriterion(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField).last, text);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('고치는 중(재검사 전)에는 뒤로가기가 확인창 없이 그냥 나간다', (tester) async {
    await _pushEdit(tester);

    await _editCriterion(tester, '시계가 6시 59분 이전을 가리킨다');
    expect(find.text(AppStrings.battleCriteriaRecheck), findsOneWidget);

    await _back(tester);

    // 아직 횟수를 쓰지 않았으므로 잃는 것이 없다. 묻지 않고 나간다.
    expect(find.text(AppStrings.battleCriteriaLeaveEditTitle), findsNothing);
    expect(find.text(_hostLabel), findsOneWidget);
  });

  testWidgets('재검사를 통과한 기준을 들고 있으면 확인창이 뜨고 계속하기로 남는다', (tester) async {
    final criteria = await _pushEdit(tester);

    await _editCriterion(tester, '시계가 6시 59분 이전을 가리킨다');
    await tester.tap(find.text(AppStrings.battleCriteriaRecheck));
    await tester.pumpAndSettle();

    // 횟수를 1회 썼고 그 결과(증서)를 들고 있다.
    expect(criteria.checkCount, 1);
    expect(find.text(AppStrings.battleCriteriaApply), findsOneWidget);

    await _back(tester);

    expect(find.text(AppStrings.battleCriteriaLeaveEditTitle), findsOneWidget);
    expect(find.text(_hostLabel), findsNothing);

    await tester.tap(find.text(AppStrings.stay));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.battleCriteriaApply), findsOneWidget);

    // 나가기를 고르면 그때는 나간다.
    await _back(tester);
    await tester.tap(find.text(AppStrings.leave));
    await tester.pumpAndSettle();
    expect(find.text(_hostLabel), findsOneWidget);
  });

  // ── reviewer W1(2026-11-02): 재검사를 쓴 뒤 한 글자 고치면 가드가 풀렸다 ──
  //
  // `CriteriaEditor.onChanged`는 증서(`_checked`)를 버린다. 그래서 "증서를 들고 있는가"로 막으면
  // 재검사로 1회를 쓴 사람이 마음을 바꿔 기준을 더 고치는 순간 가드가 풀리고,
  // 뒤로가기 한 번에 고친 기준과 쓴 1회가 **확인창 없이** 사라진다.
  testWidgets('재검사를 쓴 뒤 기준을 또 고쳐도 뒤로가기에 확인창이 뜬다', (tester) async {
    final criteria = await _pushEdit(tester);

    await _editCriterion(tester, '시계가 6시 59분 이전을 가리킨다');
    await tester.tap(find.text(AppStrings.battleCriteriaRecheck));
    await tester.pumpAndSettle();
    expect(criteria.checkCount, 1);

    // 마음이 바뀌어 한 글자 더 고친다 — 증서는 버려지지만 쓴 1회는 돌아오지 않는다.
    await _editCriterion(tester, '시계가 6시 50분 이전을 가리킨다');
    expect(find.text(AppStrings.battleCriteriaApply), findsNothing);
    expect(find.text(AppStrings.battleCriteriaRecheck), findsOneWidget);

    await _back(tester);

    expect(find.text(AppStrings.battleCriteriaLeaveEditTitle), findsOneWidget);
    expect(find.text(_hostLabel), findsNothing);

    // 계속하기를 고르면 고친 기준이 그대로 남는다.
    await tester.tap(find.text(AppStrings.stay));
    await tester.pumpAndSettle();
    expect(find.text(_hostLabel), findsNothing);
  });

  // reviewer W2: 공통 위젯(CriteriaLeaveGuard)을 쓰더라도 제목은 화면이 넘긴다.
  testWidgets('확인창은 만들기가 아니라 수정을 그만둘지 묻는다', (tester) async {
    await _pushEdit(tester);

    await _editCriterion(tester, '시계가 6시 59분 이전을 가리킨다');
    await tester.tap(find.text(AppStrings.battleCriteriaRecheck));
    await tester.pumpAndSettle();

    await _back(tester);

    expect(find.text(AppStrings.battleCriteriaLeaveEditTitle), findsOneWidget);
    expect(find.text(AppStrings.battleCriteriaLeaveTitle), findsNothing);
    // 본문은 양쪽이 같다(만든 기준이 사라지고 쓴 횟수는 돌아오지 않는다).
    expect(find.text(AppStrings.battleCriteriaLeaveBody), findsOneWidget);
  });
}
