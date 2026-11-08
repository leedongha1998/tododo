import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:todododo/core/strings.dart';
import 'package:todododo/features/battle/domain/battle_detail.dart';
import 'package:todododo/features/battle/domain/battle_providers.dart';
import 'package:todododo/features/battle/presentation/battle_detail_screen.dart';
import '../../helpers/text_finders.dart';

/// mobile-ux M2: 대결 상세를 읽다 실패하면 그 자리에서 다시 읽을 수 있어야 하고,
/// 기다리는 동안 빈 화면처럼 보이지 않아야 한다.
/// (당겨서 새로고침은 `data` 갈래 안에 있어 실패·대기 중에는 쓸 수 없다.)
const _battleId = 'b1';

/// Riverpod는 실패한 provider를 스스로 다시 부른다. 그 백오프 타이머가 테스트 끝까지 남아
/// 터지고 호출 횟수도 부풀리므로, 실패 화면을 보는 테스트에서는 재시도를 끈다.
Future<ProviderContainer> _pumpDetail(
  WidgetTester tester,
  Future<BattleDetail> Function(Ref ref) load,
) async {
  final container = ProviderContainer(
    overrides: [battleDetailProvider(_battleId).overrideWith(load)],
    retry: (retryCount, error) => null,
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: BattleDetailScreen(battleId: _battleId)),
    ),
  );
  await tester.pump();
  return container;
}

void main() {
  testWidgets('상세를 못 읽으면 그 자리에서 다시 시도할 수 있다', (tester) async {
    var loads = 0;
    await _pumpDetail(tester, (ref) async {
      loads++;
      throw Exception('detail down');
    });
    await tester.pumpAndSettle();

    expect(loads, 1);
    expect(findText(AppStrings.battleLoadDetailFailed), findsOneWidget);

    // 복구 수단이 "뒤로 갔다가 다시 들어오기"뿐이 되지 않는다.
    await tester.tap(findText(AppStrings.retry));
    await tester.pumpAndSettle();

    expect(loads, 2);
    expect(findText(AppStrings.battleLoadDetailFailed), findsOneWidget);
  });

  testWidgets('상세를 기다리는 동안 무엇을 기다리는지 글자로 말한다', (tester) async {
    final gate = Completer<BattleDetail>();
    await _pumpDetail(tester, (ref) => gate.future);

    // 점 세 개만 놓으면 흰 화면으로 읽힌다.
    expect(findText(AppStrings.loading), findsOneWidget);
    expect(findText(AppStrings.battleLoadDetailFailed), findsNothing);
  });
}
