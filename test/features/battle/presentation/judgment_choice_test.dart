import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:todododo/core/strings.dart';
import 'package:todododo/core/theme/app_icons.dart';
import 'package:todododo/core/theme/app_palette.dart';
import 'package:todododo/core/theme/app_theme.dart';
import 'package:todododo/core/widgets/initial_badge.dart';
import 'package:todododo/features/battle/presentation/judgment_choice.dart';

import '../../../helpers/line_breaks.dart';
import '../../../helpers/text_finders.dart';

/// 판정 선택 타일(design-judging-buttons 1A.2). 상태별 모양·낭독·좁을 때 쌓기.
const _passFail = [
  JudgmentChoiceOption<bool>(
    value: true,
    label: AppStrings.battleJudgmentPassed,
    icon: AppIcons.pass,
    iconColor: AppPalette.success,
  ),
  JudgmentChoiceOption<bool>(
    value: false,
    label: AppStrings.battleJudgmentFailed,
    icon: AppIcons.fail,
    iconColor: AppPalette.danger,
  ),
];

final _superiority = [
  const JudgmentChoiceOption<String>(
    value: 'me',
    label: AppStrings.battleJudgmentSuperiorMe,
    badge: InitialBadge(name: '나', fill: AppPalette.primary),
  ),
  const JudgmentChoiceOption<String>(
    value: 'friend',
    label: AppStrings.battleJudgmentSuperiorOpponent,
    badge: InitialBadge(name: '친구', fill: AppPalette.secondary),
  ),
];

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  double width = 288,
  double textScale = 1.0,
}) async {
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: Scaffold(
      body: SingleChildScrollView(
        child: Center(child: SizedBox(width: width, child: child)),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

Finder _tile(String label) => find.ancestor(
      of: findText(label),
      matching: find.byType(JudgmentChoiceTile),
    );

ShapeDecoration _decorationOf(WidgetTester tester, String label) {
  final container = tester.widget<AnimatedContainer>(
    find.descendant(of: _tile(label), matching: find.byType(AnimatedContainer)),
  );
  return container.decoration! as ShapeDecoration;
}

BorderSide _sideOf(WidgetTester tester, String label) =>
    (_decorationOf(tester, label).shape as RoundedRectangleBorder).side;

Finder _checkBadge(String label) => find.descendant(
      of: _tile(label),
      matching: find.byKey(const ValueKey('judgment-choice-check')),
    );

/// 선택을 바꿀 수 있는 상태를 흉내 낸다(화면의 setState와 같다).
class _Harness<T extends Object> extends StatefulWidget {
  const _Harness({required this.choices, this.enabled = true, this.initial});

  final List<JudgmentChoiceOption<T>> choices;
  final bool enabled;
  final T? initial;

  @override
  State<_Harness<T>> createState() => _HarnessState<T>();
}

class _HarnessState<T extends Object> extends State<_Harness<T>> {
  late T? selected = widget.initial;

  @override
  Widget build(BuildContext context) => JudgmentChoicePair<T>(
        choices: widget.choices,
        selected: selected,
        onSelected: widget.enabled ? (value) => setState(() => selected = value) : null,
      );
}

void main() {
  testWidgets('처음에는 아무것도 고르지 않았다: 흰 면 + 1.5dp outline, 체크 배지 없음', (tester) async {
    await _pump(tester, const _Harness<bool>(choices: _passFail));

    for (final label in [AppStrings.battleJudgmentPassed, AppStrings.battleJudgmentFailed]) {
      expect(_decorationOf(tester, label).color, AppPalette.surface, reason: label);
      expect(_sideOf(tester, label), const BorderSide(color: AppPalette.outline, width: 1.5));
      expect(_checkBadge(label), findsNothing);
    }
    // 통과 ✓ 초록, 미달 ✕ 빨강 — 아이콘이 글자보다 먼저 보인다.
    expect(tester.widget<Icon>(find.byIcon(AppIcons.pass)).color, AppPalette.success);
    expect(tester.widget<Icon>(find.byIcon(AppIcons.fail)).color, AppPalette.danger);
    expect(tester.widget<Icon>(find.byIcon(AppIcons.pass)).size, 40);
  });

  testWidgets('고르면 연파랑 면 + 2dp primary 테두리 + 체크 배지, 고르지 않은 쪽은 흐려지지 않는다', (tester) async {
    await _pump(tester, const _Harness<bool>(choices: _passFail));

    await tester.tap(_tile(AppStrings.battleJudgmentFailed));
    await tester.pumpAndSettle();

    expect(_decorationOf(tester, AppStrings.battleJudgmentFailed).color, AppPalette.primaryPale);
    expect(
      _sideOf(tester, AppStrings.battleJudgmentFailed),
      const BorderSide(color: AppPalette.primary, width: 2),
    );
    expect(_checkBadge(AppStrings.battleJudgmentFailed), findsOneWidget);

    // 다른 칸은 미선택 모양 그대로(흐리면 바꿀 수 없다고 오해한다).
    expect(_decorationOf(tester, AppStrings.battleJudgmentPassed).color, AppPalette.surface);
    expect(
      _sideOf(tester, AppStrings.battleJudgmentPassed),
      const BorderSide(color: AppPalette.outline, width: 1.5),
    );
    expect(tester.widget<Icon>(find.byIcon(AppIcons.pass)).color, AppPalette.success);

    // 다시 다른 칸을 고를 수 있다.
    await tester.tap(_tile(AppStrings.battleJudgmentPassed));
    await tester.pumpAndSettle();
    expect(_checkBadge(AppStrings.battleJudgmentPassed), findsOneWidget);
    expect(_checkBadge(AppStrings.battleJudgmentFailed), findsNothing);
  });

  testWidgets('누르는 동안 면이 sunken이 되고 떼면 돌아온다', (tester) async {
    await _pump(tester, const _Harness<bool>(choices: _passFail));

    final gesture = await tester.startGesture(tester.getCenter(_tile(AppStrings.battleJudgmentPassed)));
    await tester.pump();
    expect(_decorationOf(tester, AppStrings.battleJudgmentPassed).color, AppPalette.sunken);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(_decorationOf(tester, AppStrings.battleJudgmentPassed).color, AppPalette.primaryPale);
  });

  testWidgets('보내는 중: 고른 칸은 선택 모양 유지, 다른 칸은 sunken + line + inkDisabled, 누를 수 없다', (tester) async {
    await _pump(tester, const _Harness<bool>(choices: _passFail, enabled: false, initial: true));

    expect(_decorationOf(tester, AppStrings.battleJudgmentPassed).color, AppPalette.primaryPale);
    expect(_checkBadge(AppStrings.battleJudgmentPassed), findsOneWidget);

    expect(_decorationOf(tester, AppStrings.battleJudgmentFailed).color, AppPalette.sunken);
    expect(
      _sideOf(tester, AppStrings.battleJudgmentFailed),
      const BorderSide(color: AppPalette.line, width: 1.5),
    );
    expect(tester.widget<Icon>(find.byIcon(AppIcons.fail)).color, AppPalette.inkDisabled);

    await tester.tap(_tile(AppStrings.battleJudgmentFailed));
    await tester.pumpAndSettle();
    expect(_checkBadge(AppStrings.battleJudgmentFailed), findsNothing);
    expect(_checkBadge(AppStrings.battleJudgmentPassed), findsOneWidget);
  });

  testWidgets('이니셜 배지 타일은 보내는 중에도 배지 색을 바꾸지 않는다', (tester) async {
    await _pump(tester, _Harness<String>(choices: _superiority, enabled: false, initial: 'me'));

    final badges = tester.widgetList<InitialBadge>(find.byType(InitialBadge)).toList();
    expect(badges.map((badge) => badge.fill), [AppPalette.primary, AppPalette.secondary]);
  });

  testWidgets('낭독: 서로 배타적인 버튼 묶음, 라벨은 원문, 고른 칸만 selected', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, const _Harness<bool>(choices: _passFail, initial: false));

    expect(
      tester.getSemantics(_tile(AppStrings.battleJudgmentFailed)),
      matchesSemantics(
        label: AppStrings.battleJudgmentFailed,
        isButton: true,
        isInMutuallyExclusiveGroup: true,
        hasSelectedState: true,
        isSelected: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
      ),
    );
    expect(
      tester.getSemantics(_tile(AppStrings.battleJudgmentPassed)),
      matchesSemantics(
        label: AppStrings.battleJudgmentPassed,
        isButton: true,
        isInMutuallyExclusiveGroup: true,
        hasSelectedState: true,
        isSelected: false,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
      ),
    );
    handle.dispose();
  });

  testWidgets('두 칸은 가로 1:1, 사이 8, 높이가 같고 최소 104', (tester) async {
    await _pump(tester, _Harness<String>(choices: _superiority));

    expect(find.byKey(const ValueKey('judgment-choice-row')), findsOneWidget);
    final left = tester.getRect(_tile(AppStrings.battleJudgmentSuperiorMe));
    final right = tester.getRect(_tile(AppStrings.battleJudgmentSuperiorOpponent));
    expect(left.width, moreOrLessEquals(right.width, epsilon: 0.01));
    expect(right.left - left.right, moreOrLessEquals(8, epsilon: 0.01));
    expect(left.height, moreOrLessEquals(right.height, epsilon: 0.01));
    expect(left.height, greaterThanOrEqualTo(104));
    expect(left.top, right.top);
  });

  // 360dp − 가장자리 40 − 카드 안쪽 32 = 288(판정 화면의 실제 폭). 테스트 글꼴은 정사각형이라 실기기보다 넓다.
  for (final scale in [1.0, 1.5]) {
    testWidgets('288dp·$scale배: 넘치지 않고 라벨은 어절 경계에서만 끊긴다', (tester) async {
      await _pump(
        tester,
        Column(
          children: [
            const _Harness<bool>(choices: _passFail, initial: true),
            const SizedBox(height: 12),
            _Harness<String>(choices: _superiority, initial: 'friend'),
          ],
        ),
        textScale: scale,
      );
      expect(tester.takeException(), isNull);

      for (final label in [
        AppStrings.battleJudgmentPassed,
        AppStrings.battleJudgmentFailed,
        AppStrings.battleJudgmentSuperiorMe,
        AppStrings.battleJudgmentSuperiorOpponent,
      ]) {
        final paragraph = tester.renderObject<RenderParagraph>(
          find.descendant(of: findText(label), matching: find.byType(RichText)),
        );
        expect(breaksOnlyAtSpaces(paragraph), isTrue, reason: label);
        expect(paragraph.didExceedMaxLines, isFalse, reason: label);
        // 라벨이 칸 밖으로 나가지 않는다.
        final tile = tester.getRect(_tile(label));
        final text = tester.getRect(findText(label));
        expect(text.left, greaterThanOrEqualTo(tile.left), reason: label);
        expect(text.right, lessThanOrEqualTo(tile.right), reason: label);
        expect(text.bottom, lessThanOrEqualTo(tile.bottom), reason: label);
      }
    });
  }

  testWidgets('가장 긴 어절이 반 칸에 안 들어가면 두 칸을 위아래로 쌓는다', (tester) async {
    // 테스트 글꼴 16dp × 1.5 = 24/글자 → "통과했어요" 120 > 반 칸 안쪽 (288 − 8) / 2 − 28 = 112.
    await _pump(tester, const _Harness<bool>(choices: _passFail), textScale: 1.5);

    expect(find.byKey(const ValueKey('judgment-choice-stacked')), findsOneWidget);
    final top = tester.getRect(_tile(AppStrings.battleJudgmentPassed));
    final bottom = tester.getRect(_tile(AppStrings.battleJudgmentFailed));
    expect(top.bottom, lessThanOrEqualTo(bottom.top));
    expect(top.width, 288);
    expect(lineStarts(tester.renderObject<RenderParagraph>(
      find.descendant(of: findText(AppStrings.battleJudgmentPassed), matching: find.byType(RichText)),
    )), isEmpty);
  });

  testWidgets('체크 배지는 오른쪽 위 6 안쪽에 있고 가운데 아이콘과 겹치지 않는다', (tester) async {
    await _pump(tester, const _Harness<bool>(choices: _passFail, initial: true));

    final tile = tester.getRect(_tile(AppStrings.battleJudgmentPassed));
    final badge = tester.getRect(_checkBadge(AppStrings.battleJudgmentPassed));
    expect(badge.size, const Size(24, 24));
    // 테두리 2 + 안쪽 6.
    expect(tile.right - badge.right, moreOrLessEquals(8, epsilon: 0.01));
    expect(badge.top - tile.top, moreOrLessEquals(8, epsilon: 0.01));
    final icon = tester.getRect(find.byIcon(AppIcons.pass));
    expect(badge.overlaps(icon), isFalse);
  });
}
