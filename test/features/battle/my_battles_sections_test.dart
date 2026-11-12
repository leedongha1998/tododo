import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:todododo/core/strings.dart';
import 'package:todododo/core/theme/app_icons.dart';
import 'package:todododo/core/theme/app_palette.dart';
import 'package:todododo/core/theme/app_theme.dart';
import 'package:todododo/core/widgets/app_panel.dart';
import 'package:todododo/core/widgets/app_tag.dart';
import 'package:todododo/features/battle/data/battle.dart';
import 'package:todododo/features/battle/data/battle_participant.dart';
import 'package:todododo/features/battle/data/battle_repository.dart';
import 'package:todododo/features/battle/data/criteria_check_result.dart';
import 'package:todododo/features/battle/domain/battle_providers.dart';
import 'package:todododo/features/battle/domain/battle_summary.dart';
import 'package:todododo/features/battle/presentation/battle_chips.dart';
import 'package:todododo/features/battle/presentation/battle_summary_list.dart';
import 'package:todododo/features/battle/presentation/my_battles_screen.dart';
import 'package:todododo/core/widgets/keep_words_text.dart';
import '../../helpers/line_breaks.dart';
import '../../helpers/text_finders.dart';

Battle _recruit() => Battle(
  id: 'p1',
  type: 'speed',
  status: 'pending',
  title: '설거지하기',
  creatorId: 'me',
  createdAt: DateTime(2026, 10, 28),
  durationMinutes: 30,
  minCriteria: const ['싱크대가 비어 있다'],
);

BattleSummary _activeSummary() => BattleSummary(
  battle: Battle(
    id: 'a1',
    type: 'quality',
    status: 'active',
    title: '방 청소하기',
    creatorId: 'me',
    opponentId: 'friend',
    createdAt: DateTime(2026, 10, 28),
    startedAt: DateTime(2026, 10, 28),
    deadlineAt: DateTime(2026, 10, 31),
    durationMinutes: 4320,
    minCriteria: const ['바닥이 보인다'],
    superiorityCriteria: const ['먼지가 없다'],
  ),
  otherPartyName: '도윤',
);

class _MyBattlesRepository implements BattleRepository {
  _MyBattlesRepository({List<Battle> recruits = const []})
    : recruits = [...recruits];

  List<Battle> recruits;
  int cancelCount = 0;

  /// 채워 두면 다음 모집 조회만 실패한다.
  Object? failNextRecruits;

  @override
  Future<List<Battle>> fetchMyRecruits() async {
    final error = failNextRecruits;
    if (error != null) {
      failNextRecruits = null;
      throw error;
    }
    return recruits;
  }

  @override
  Future<void> cancelBattle(String battleId) async {
    cancelCount++;
    recruits = recruits.where((battle) => battle.id != battleId).toList();
  }

  @override
  Future<MyLimits> fetchMyLimits() async => const MyLimits(consented: true, criteriaCallsLeft: 10);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Future<ProviderContainer> _pumpMyBattles(
  WidgetTester tester, {
  required _MyBattlesRepository repository,
  List<BattleSummary> summaries = const [],
  // 칩 줄 검증만 실제 테마와 글자 배율을 쓴다(나머지 테스트는 기본 테마 그대로 둔다).
  ThemeData? theme,
  double textScale = 1,
}) async {
  final container = ProviderContainer(
    overrides: [
      battleRepositoryProvider.overrideWithValue(repository),
      // 진행 중 목록은 로그인 세션을 직접 읽으므로 테스트에서는 값으로 고정한다.
      myBattlesProvider.overrideWith((ref) async => summaries),
    ],
    // Riverpod의 자동 재시도 타이머가 테스트 종료 뒤까지 남지 않게 끈다.
    retry: (retryCount, error) => null,
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const MyBattlesScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// 카드 우측 상단의 아이콘 동작. **글자가 없으므로 툴팁으로 찾는다** — 그 툴팁이 길게 누르면
/// 뜨는 이름이고 스크린 리더가 읽는 이름이다(2026-11-12부터 아이콘만 남았다).
Finder _iconAction(String label) => find.ancestor(
  of: find.byTooltip(label),
  matching: find.byType(IconButton),
);

/// 대화상자의 버튼. 글자가 있으므로 라벨로 찾는다.
Finder _dialogButton<T extends ButtonStyleButton>(String label) => find.ancestor(
  of: findText(label),
  matching: find.byWidgetPredicate((widget) => widget is T),
);

void main() {
  testWidgets('내가 등록한 모집이 진행 중 목록과 구분된 구역으로 보인다', (tester) async {
    await _pumpMyBattles(
      tester,
      repository: _MyBattlesRepository(recruits: [_recruit()]),
      summaries: [_activeSummary()],
    );

    // 구역 A: 머리글 + 모집 제목 + 모집 중 칩 + 기간 + 기다리는 중 안내 + 두 아이콘 동작.
    expect(findText(AppStrings.battleMyRecruits), findsOneWidget);
    expect(findText('설거지하기'), findsOneWidget);
    expect(findText(AppStrings.battleStatusPending), findsOneWidget);
    expect(findText(battleDurationLabel(30)), findsOneWidget);
    expect(findText(AppStrings.battleMyRecruitWaiting), findsOneWidget);

    // 머리글은 **카드 밖**이다 — 안에 두면 모집이 여러 건일 때 카드마다 반복된다.
    final recruitCard = find
        .ancestor(of: findText('설거지하기'), matching: find.byType(AppPanel))
        .first;
    expect(
      find.descendant(of: recruitCard, matching: findText(AppStrings.battleMyRecruits)),
      findsNothing,
    );

    // 두 동작은 아이콘만이고 글자는 툴팁으로만 남는다.
    expect(_iconAction(AppStrings.battleCriteriaEditRecruit), findsOneWidget);
    expect(_iconAction(AppStrings.battleRecruitCancel), findsOneWidget);
    expect(findText(AppStrings.battleCriteriaEditRecruit), findsNothing);
    expect(findText(AppStrings.battleRecruitCancel), findsNothing);
    expect(find.byIcon(AppIcons.edit), findsOneWidget);
    // X가 아니라 휴지통이다 — 일어나는 일은 "카드를 닫는다"가 아니라 "모집이 없어진다"다.
    expect(find.byIcon(AppIcons.delete), findsOneWidget);
    expect(
      tester.widget<IconButton>(_iconAction(AppStrings.battleRecruitCancel)).color,
      AppPalette.danger,
    );

    // 구역 B: 머리글이 생겼고, 카드는 그대로다(상대·유형·상태 칩).
    expect(findText(AppStrings.battleMyActiveBattles), findsOneWidget);
    expect(findText('방 청소하기'), findsOneWidget);
    expect(findText('${AppStrings.battleVersus} 도윤'), findsOneWidget);
    expect(findText(AppStrings.battleStatusActive), findsOneWidget);
  });

  // 머리글을 박스 밖으로 뺀 이유가 이것이다. 모집 수 제한은 2026-11-06에 없어졌으므로 모집이
  // 여러 건일 수 있고, 안에 두면 카드마다 같은 제목이 반복됐다.
  testWidgets('모집이 여러 건이어도 머리글은 하나이고 카드마다 두 동작이 붙는다', (tester) async {
    final second = Battle(
      id: 'p2',
      type: 'quality',
      status: 'pending',
      title: '빨래 개기',
      creatorId: 'me',
      createdAt: DateTime(2026, 10, 29),
      durationMinutes: 60,
      minCriteria: const ['갠 빨래가 보인다'],
      superiorityCriteria: const ['주름이 없다'],
    );
    await _pumpMyBattles(
      tester,
      repository: _MyBattlesRepository(recruits: [_recruit(), second]),
    );

    expect(findText(AppStrings.battleMyRecruits), findsOneWidget);
    expect(findText('설거지하기'), findsOneWidget);
    expect(findText('빨래 개기'), findsOneWidget);
    expect(_iconAction(AppStrings.battleCriteriaEditRecruit), findsNWidgets(2));
    expect(_iconAction(AppStrings.battleRecruitCancel), findsNWidgets(2));
  });

  testWidgets('모집 1건만 있으면 "비었다"가 아니라 진행 중이 아직 없다고만 말한다', (tester) async {
    await _pumpMyBattles(
      tester,
      repository: _MyBattlesRepository(recruits: [_recruit()]),
    );

    expect(findText(AppStrings.battleMyRecruits), findsOneWidget);
    // 한 줄짜리 안내에도 머리글은 둔다 — 무엇에 대한 말인지를 머리글이 말한다.
    expect(findText(AppStrings.battleMyActiveBattles), findsOneWidget);
    expect(findText(AppStrings.battleNoActiveBattlesYet), findsOneWidget);
    // 모집 구역이 이미 "기다리는 중"을 말하므로 찾기 탭으로 보내는 버튼을 두 번 권하지 않는다.
    expect(findText(AppStrings.battleMyBattlesEmpty), findsNothing);
    expect(
      findWidgetWithText(FilledButton, AppStrings.battleFind),
      findsNothing,
    );
  });

  testWidgets('모집도 진행 중도 없으면 기존 빈 상태 안내가 그대로 보인다', (tester) async {
    await _pumpMyBattles(tester, repository: _MyBattlesRepository());

    expect(findText(AppStrings.battleMyRecruits), findsNothing);
    // 빈 목록에 이름을 붙이면 없는 것을 가리키는 머리글이 된다. 그 자리는 소개 블록이 말한다.
    expect(findText(AppStrings.battleMyActiveBattles), findsNothing);
    expect(findText(AppStrings.battleMyBattlesEmpty), findsOneWidget);
    expect(findText(AppStrings.battleFinishedInProfile), findsOneWidget);
    expect(
      findWidgetWithText(FilledButton, AppStrings.battleFind),
      findsOneWidget,
    );
  });

  // riverpod은 실패해도 직전 값을 들고 있다. 그 값을 그대로 그리면 이미 사라졌을 수도 있는
  // 모집에 기준 수정을 시도하게 된다.
  testWidgets('모집을 다시 읽다 실패하면 낡은 모집을 그대로 두지 않고 실패를 알린다', (tester) async {
    final repository = _MyBattlesRepository(recruits: [_recruit()]);
    final container = await _pumpMyBattles(tester, repository: repository);
    expect(findText('설거지하기'), findsOneWidget);

    repository.failNextRecruits = Exception('network down');
    container.invalidate(myRecruitsProvider);
    await tester.pumpAndSettle();

    expect(findText('설거지하기'), findsNothing);
    expect(findText(AppStrings.battleLoadRecruitsFailed), findsOneWidget);
    expect(findWidgetWithText(TextButton, AppStrings.retry), findsOneWidget);

    // 다시 시도하면 구역이 돌아온다.
    await tester.tap(findWidgetWithText(TextButton, AppStrings.retry));
    await tester.pumpAndSettle();
    expect(findText('설거지하기'), findsOneWidget);
  });

  // 아이콘만 남으면서 "모집 취소"라는 글자가 사라졌다. 오탭 한 번에 모집이 없어지고 그 모집의
  // AI 기준도 함께 사라지므로 한 번 확인받는다(2026-11-12 오너 확정, 포기와 같은 급).
  testWidgets('취소 아이콘을 눌러도 확인하기 전에는 모집이 그대로다', (tester) async {
    final repository = _MyBattlesRepository(recruits: [_recruit()]);
    await _pumpMyBattles(tester, repository: repository);

    await tester.tap(_iconAction(AppStrings.battleRecruitCancel));
    await tester.pumpAndSettle();

    // 무엇이 사라지는지 대화상자가 먼저 말한다.
    expect(findText(AppStrings.battleRecruitCancelConfirmTitle), findsOneWidget);
    expect(findText(AppStrings.battleRecruitCancelConfirm), findsOneWidget);
    expect(repository.cancelCount, 0);

    // 물러나면 아무 일도 없다.
    await tester.tap(_dialogButton<TextButton>(AppStrings.cancel));
    await tester.pumpAndSettle();

    expect(repository.cancelCount, 0);
    expect(findText('설거지하기'), findsOneWidget);
  });

  testWidgets('모집을 취소하면 그 구역이 사라지고 새로 올릴 수 있는 상태로 돌아온다', (tester) async {
    final repository = _MyBattlesRepository(recruits: [_recruit()]);
    await _pumpMyBattles(tester, repository: repository);

    await tester.tap(_iconAction(AppStrings.battleRecruitCancel));
    await tester.pumpAndSettle();
    await tester.tap(_dialogButton<FilledButton>(AppStrings.battleRecruitCancel));
    await tester.pumpAndSettle();

    expect(repository.cancelCount, 1);
    expect(findText(AppStrings.battleRecruitCancelled), findsOneWidget);
    expect(findText(AppStrings.battleMyRecruits), findsNothing);
    expect(findText('설거지하기'), findsNothing);
    // 모집이 없어졌으므로 빈 상태 안내로 돌아온다.
    expect(findText(AppStrings.battleMyBattlesEmpty), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  // 칩 라벨이 12dp 픽셀에서 14dp 본문 글꼴로 커졌다(readability.md 방안 2).
  // 좁은 화면·큰 글자에서 한 줄에 다 못 들어가면 칩을 빼지 않고 다음 줄로 내린다(3-1).
  // 배율은 앱의 글자 크기 상한(maxTextScale 1.5, redesign design 3.3)에 맞춘다. 테스트 글꼴은 정사각형이라
  // 실제 글리프 폭과 다르다 — "예외 없이 그려지고 칩이 화면 밖으로 안 나간다"까지만 보장한다.
  testWidgets('글자 크기 1.5배·360dp 폭에서도 모집 카드 칩 세 개가 다 남고 칸을 넘지 않는다', (tester) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await _pumpMyBattles(
      tester,
      repository: _MyBattlesRepository(recruits: [_recruit()]),
      theme: AppTheme.light,
      textScale: 1.5,
    );

    expect(tester.takeException(), isNull);

    // 유형 배지 + 모집 중 + 기간. 하나라도 빼면 사용자가 정보를 잃는다.
    final badge = find.byType(BattleTypeBadge);
    expect(badge, findsOneWidget);
    expect(findText(AppStrings.battleStatusPending), findsOneWidget);
    expect(findText(battleDurationLabel(30)), findsOneWidget);

    // Row로 되돌리면(= 줄바꿈이 사라지면) 이 단정이 깨진다.
    final wrap = find.ancestor(of: badge, matching: find.byType(Wrap));
    expect(wrap, findsOneWidget);

    // 어떤 칩도 화면 밖으로 나가지 않는다(세 개가 한 줄에 다 못 들어가면 아래 줄로 내려간다).
    final screen = tester.getRect(find.byType(MyBattlesScreen));
    expect(screen.width, 360);
    final chips = <Finder>[badge, ...List.generate(2, (i) => find.byType(AppTag).at(i))];
    for (final chip in chips) {
      final rect = tester.getRect(chip);
      expect(rect.left, greaterThanOrEqualTo(screen.left - 0.5));
      expect(rect.right, lessThanOrEqualTo(screen.right + 0.5));
    }
  });

  // 두 동작은 **칩 줄의 오른쪽 끝**(= 카드 우측 상단)에 있고 제목은 그 아래 가운데다
  // (2026-11-12 오너 확정). 표적 크기는 `myBattleCardBlockHeight` 하나로 묶인다 — 이 버튼이
  // 카드 윗줄의 높이를 정하므로 그 값이 흔들리면 제목의 가운데까지 함께 흔들린다.
  for (final scale in [1.0, 1.5]) {
    testWidgets('360dp·$scale배에서 두 아이콘이 윗줄 높이를 지키고 칩 줄 오른쪽 끝에 있다', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await _pumpMyBattles(
        tester,
        repository: _MyBattlesRepository(recruits: [_recruit()]),
        theme: AppTheme.light,
        textScale: scale,
      );
      expect(tester.takeException(), isNull);

      final card = tester.getRect(
        find.ancestor(of: findText('설거지하기'), matching: find.byType(AppPanel)).first,
      );
      final edit = _iconAction(AppStrings.battleCriteriaEditRecruit);
      final cancel = _iconAction(AppStrings.battleRecruitCancel);
      for (final button in [edit, cancel]) {
        final rect = tester.getRect(button);
        expect(rect.left, greaterThanOrEqualTo(card.left), reason: '$button');
        expect(rect.right, lessThanOrEqualTo(card.right), reason: '$button');
        expect(
          rect.height,
          greaterThanOrEqualTo(myBattleCardBlockHeight),
          reason: '$button',
        );
        expect(
          rect.width,
          greaterThanOrEqualTo(myBattleCardBlockHeight),
          reason: '$button',
        );
      }

      final editRect = tester.getRect(edit);
      final cancelRect = tester.getRect(cancel);
      final title = tester.getRect(findText('설거지하기'));
      final badge = tester.getRect(find.byType(BattleTypeBadge));
      // 한 줄이다 — 기준 수정이 왼쪽, 모집 취소가 오른쪽 끝.
      expect(editRect.top, moreOrLessEquals(cancelRect.top, epsilon: 0.5));
      expect(editRect.right, lessThanOrEqualTo(cancelRect.left));
      // 칩과 겹치지 않는다(칩 칸이 두 버튼만큼 좁아진 것이 이 배치의 대가다).
      expect(badge.right, lessThanOrEqualTo(editRect.left + 0.5));
      // 읽는 순서: 칩 줄 → 제목. 두 동작은 그 칩 줄에 있다(= 카드 우측 상단).
      expect(badge.bottom, lessThanOrEqualTo(title.top));
      expect(cancelRect.bottom, lessThanOrEqualTo(title.top + 0.5));
    });
  }

  // 칩은 제목보다 먼저 읽히는 **곁들이는 정보**다. 제목과 같은 무게로 서 있으면 무엇이 이
  // 카드의 이름인지 흐려진다 — 그래서 두 카드 모두 한 단계 줄였다(14 → 12, 2026-11-12 오너 확정).
  testWidgets('모집 카드와 진행 중 카드의 칩이 모두 한 단계 작다', (tester) async {
    await _pumpMyBattles(
      tester,
      repository: _MyBattlesRepository(recruits: [_recruit()]),
      summaries: [_activeSummary()],
      theme: AppTheme.light,
    );

    for (final label in [
      AppStrings.battleStatusPending,
      AppStrings.battleStatusActive,
    ]) {
      expect(
        tester.widget<KeepWordsText>(findText(label)).style?.fontSize,
        12,
        reason: label,
      );
    }
    // 유형 배지도 같이 줄어야 한 줄이 들쭉날쭉해지지 않는다.
    final badges = find.byType(BattleTypeBadge);
    expect(badges, findsNWidgets(2));
    for (var i = 0; i < 2; i++) {
      expect(tester.widget<BattleTypeBadge>(badges.at(i)).compact, isTrue);
    }
  });

  // 제목은 **카드의 정확한 가운데**다(2026-11-12 오너 확정). 윗줄(48dp 버튼이 높이를 정한다)과
  // 아랫줄을 같은 높이로 두어 맞췄으므로 글자 배율이 커져도 대칭이 깨지지 않는다.
  for (final scale in [1.0, 1.5]) {
    testWidgets('360dp·$scale배에서 모집 카드 제목이 카드 한가운데에 선다', (tester) async {
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await _pumpMyBattles(
        tester,
        repository: _MyBattlesRepository(recruits: [_recruit()]),
        theme: AppTheme.light,
        textScale: scale,
      );
      expect(tester.takeException(), isNull);

      final card = tester.getRect(
        find.ancestor(of: findText('설거지하기'), matching: find.byType(AppPanel)).first,
      );
      final title = tester.getRect(findText('설거지하기'));
      // 허용 오차 4의 이유: **대칭은 윗줄 높이를 아이콘 버튼이 정할 때 정확하다.** 칩이 두 줄로
      // 넘어가면 윗줄만 그만큼 자라고 아랫줄은 그대로라 가운데가 그 절반만큼 내려간다.
      // 테스트 글꼴은 글자마다 정사각형이라 실제보다 훨씬 넓어 여기서는 칩이 두 줄이 된다
      // (실기기 360dp·1배에서는 세 칩이 한 줄이고 정확히 가운데다 — 2026-11-12 확인).
      expect(title.center.dy, moreOrLessEquals(card.center.dy, epsilon: 4));

      // 목록 본문(16)보다 한 단계 위다 — 이 카드에서 제목은 유일한 주인공이다.
      expect(
        tester.widget<KeepWordsText>(findText('설거지하기')).style?.fontSize,
        18,
      );
    });
  }

  // 두 카드는 **같은 포맷**이다(2026-11-12 오너 — "둘이 같은 포맷을 써야지 디자인이 왜 달라?").
  // 모집 카드만 고치는 동안 진행 중 카드가 옛 짜임새(제목이 맨 위, 상태 칩이 오른쪽 끝)로
  // 남아 한 화면에 두 디자인이 섞였다. 짜임새가 다시 갈라지면 이 테스트가 깨진다.
  testWidgets('모집 카드와 진행 중 카드가 같은 짜임새를 쓴다 — 칩 줄 → 제목 → 안내', (tester) async {
    tester.view.physicalSize = const Size(360, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await _pumpMyBattles(
      tester,
      repository: _MyBattlesRepository(recruits: [_recruit()]),
      summaries: [_activeSummary()],
      theme: AppTheme.light,
    );
    expect(tester.takeException(), isNull);

    final insets = <double>[];
    for (final title in ['설거지하기', '방 청소하기']) {
      final card = tester.getRect(
        find.ancestor(of: findText(title), matching: find.byType(AppPanel)).first,
      );
      final titleRect = tester.getRect(findText(title));
      final badge = tester.getRect(
        find.descendant(
          of: find.ancestor(of: findText(title), matching: find.byType(AppPanel)).first,
          matching: find.byType(BattleTypeBadge),
        ),
      );
      // 유형 배지(= 칩 줄)가 제목보다 위다.
      expect(badge.bottom, lessThanOrEqualTo(titleRect.top), reason: title);
      // 제목 크기가 같다.
      expect(
        tester.widget<KeepWordsText>(findText(title)).style?.fontSize,
        18,
        reason: title,
      );
      // 제목이 카드 가운데다(오차는 위 중앙 테스트와 같은 이유).
      expect(
        titleRect.center.dy,
        moreOrLessEquals(card.center.dy, epsilon: 4),
        reason: title,
      );
      insets.add(titleRect.left - card.left);
    }
    // 카드 안쪽 여백도 같다(두 카드가 같은 `myBattleCardPadding`을 쓴다).
    expect(insets.first, moreOrLessEquals(insets.last, epsilon: 0.5));
  });

  // 상태 칩은 **칩 줄의 오른쪽 끝**이다(2026-11-12 오너 — "판정중 표시는 우측 상단에 둬").
  // 모집 카드가 그 자리에 두 동작을 두는 것과 같은 자리이고, 유형 배지·상대 이름은 왼쪽에 남는다.
  testWidgets('진행 중 카드의 상태 칩은 칩 줄 오른쪽 끝에 있다', (tester) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await _pumpMyBattles(
      tester,
      repository: _MyBattlesRepository(),
      summaries: [_activeSummary()],
      theme: AppTheme.light,
    );
    expect(tester.takeException(), isNull);

    final card = tester.getRect(
      find.ancestor(of: findText('방 청소하기'), matching: find.byType(AppPanel)).first,
    );
    expect(findText(AppStrings.battleStatusActive), findsOneWidget);
    final chip = tester.getRect(find.byType(BattleStatusChip));
    final badge = tester.getRect(find.byType(BattleTypeBadge));
    final title = tester.getRect(findText('방 청소하기'));
    // 오른쪽 끝 — 카드 오른쪽 여백(16 + 테두리) 안쪽에 붙는다.
    expect(chip.right, greaterThan(card.right - 24));
    expect(chip.right, lessThanOrEqualTo(card.right));
    // 유형 배지와 같은 줄이고, 둘 다 제목보다 위다.
    expect(badge.right, lessThanOrEqualTo(chip.left));
    expect(chip.bottom, lessThanOrEqualTo(title.top));
  });

  // redesign 후속 2 W2: 대결 제목은 카드 제목(titleMedium)이라 균형 줄바꿈을 쓴다.
  // "냉장고 안 유통기한 지난 음식 전부 / 버리기"처럼 한 어절만 넘어가지 않는다.
  testWidgets('진행 중 카드의 긴 대결 제목은 360dp·1.5배에서 줄 길이가 고르다', (tester) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const title = '냉장고 안 유통기한 지난 음식 전부 버리기';
    final active = _activeSummary().battle;
    final battle = Battle(
      id: active.id,
      type: active.type,
      status: active.status,
      title: title,
      creatorId: active.creatorId,
      opponentId: active.opponentId,
      createdAt: active.createdAt,
      startedAt: active.startedAt,
      deadlineAt: active.deadlineAt,
      durationMinutes: active.durationMinutes,
      minCriteria: active.minCriteria,
      superiorityCriteria: active.superiorityCriteria,
    );
    await _pumpMyBattles(
      tester,
      repository: _MyBattlesRepository(),
      summaries: [BattleSummary(battle: battle, otherPartyName: '도윤')],
      theme: AppTheme.light,
      textScale: 1.5,
    );
    expect(tester.takeException(), isNull);
    final text = tester.widget<KeepWordsText>(findText(title));
    expect(text.wrap, KeepWordsWrap.balanced);
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: findText(title), matching: find.byType(RichText)),
    );
    final widths = lineWidths(paragraph);
    expect(widths.length, greaterThanOrEqualTo(2));
    // 가장 짧은 줄도 가장 긴 줄의 절반을 넘는다(한 어절만 넘어가면 이 단정이 깨진다).
    expect(widths.reduce(math.min), greaterThan(widths.reduce(math.max) / 2));
    expect(breaksOnlyAtSpaces(paragraph), isTrue);
  });

  // 푸시가 없는 MVP에서 "지금 내가 할 일"을 말하는 자리가 이 카드뿐이다(mobile-ux M1).
  // 카드는 DateTime.now()를 읽으므로 고정 날짜 픽스처가 아니라 지금 시각 기준으로 만든다
  // (유닛 테스트는 statusLineAt(now)로 덮는다).
  testWidgets('판정 창에서 내 차례면 카드가 그 말을 강조하고 판정 기한을 함께 보여 준다', (tester) async {
    await _pumpMyBattles(
      tester,
      repository: _MyBattlesRepository(),
      summaries: [_judgingSummaryNow()],
      theme: AppTheme.light,
    );

    expect(findText(AppStrings.battleListMyJudgeTurn), findsOneWidget);
    expect(
      findText(
        '${AppStrings.battleJudgeDeadlineLabel} · '
        '${AppStrings.battleDeadlineLeft('2시간')}',
      ),
      findsOneWidget,
    );

    // 할 일이 있는 줄만 굵게 띄운다. 모든 줄을 같은 모양으로 그리면 구분이 사라진다.
    // 굵기는 700 — Pretendard는 400/700/800만 번들한다(redesign design 3.1).
    final line = tester.widget<KeepWordsText>(
      findText(AppStrings.battleListMyJudgeTurn),
    );
    expect(line.style?.fontWeight, FontWeight.w700);
    // 놓치면 손해 보는 줄은 13dp 메타데이터 슬롯이 아니라 16dp(titleSmall) — redesign 후속 결정 2.
    expect(line.style?.fontSize, 16);
  });

  testWidgets('제출 창에서 내 사진이 없으면 카드가 그 말을 하고, 상대 소식은 흐리게 둔다', (tester) async {
    await _pumpMyBattles(
      tester,
      repository: _MyBattlesRepository(),
      summaries: [_activeSummaryNow(iSubmitted: false)],
      theme: AppTheme.light,
    );

    expect(findText(AppStrings.battleListNotSubmitted), findsOneWidget);
    expect(
      findText(
        '${AppStrings.battleSubmitDeadlineLabel} · '
        '${AppStrings.battleDeadlineLeft('5시간')}',
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<KeepWordsText>(findText(AppStrings.battleListNotSubmitted))
          .style
          ?.fontWeight,
      FontWeight.w700,
    );
    expect(
      tester.widget<KeepWordsText>(findText(AppStrings.battleListNotSubmitted)).style?.fontSize,
      16,
    );
  });

  // 내가 이미 냈으면 남은 소식은 "상대가 제출했어요"이고, 그것은 내 할 일이 아니다.
  testWidgets('상대 제출 소식은 내 할 일 줄과 다른 모양으로 둔다', (tester) async {
    await _pumpMyBattles(
      tester,
      repository: _MyBattlesRepository(),
      summaries: [_activeSummaryNow(opponentSubmitted: true)],
    );

    expect(findText(AppStrings.battleListNotSubmitted), findsNothing);
    final news = tester.widget<KeepWordsText>(
      findText(AppStrings.battleListOpponentSubmitted),
    );
    expect(news.style?.fontWeight, isNot(FontWeight.w700));
  });

  // M6 — 로그인 직후 첫 탭이 여기다. 새 계정은 이 앱이 무엇인지 어디서도 듣지 못한 상태로
  // `진행 중인 대결이 없어요.` 한 줄을 본다. 온보딩 화면을 만들지 않고 빈 상태 위 블록 한 장으로 말한다.
  testWidgets('대결도 모집도 없는 첫 화면은 이 앱이 무엇인지 세 줄로 먼저 말한다', (tester) async {
    await _pumpMyBattles(tester, repository: _MyBattlesRepository());

    expect(findText(AppStrings.battleIntroMatching), findsOneWidget);
    expect(findText(AppStrings.battleIntroEvidence), findsOneWidget);
    expect(findText(AppStrings.battleIntroJudging), findsOneWidget);

    // 기존 빈 상태와 CTA는 그대로 남는다. 블록이 그것을 대신하지 않는다.
    expect(findText(AppStrings.battleMyBattlesEmpty), findsOneWidget);
    expect(
      findWidgetWithText(FilledButton, AppStrings.battleFind),
      findsOneWidget,
    );

    // 빈 상태 "위"다 — 설명을 읽고 나서 다음 행동 버튼에 닿는다.
    expect(
      tester.getTopLeft(findText(AppStrings.battleIntroMatching)).dy,
      lessThan(tester.getTopLeft(findText(AppStrings.battleMyBattlesEmpty)).dy),
    );
  });

  // 음성 단언. 이 블록은 빈 상태 전용이다 — 대결이 하나라도 있으면 소개를 다시 읽힐 이유가 없고,
  // 목록 맨 위를 설명으로 밀어내면 "지금 내가 할 일"이 그만큼 내려간다.
  testWidgets('진행 중인 대결이 있으면 소개 블록이 보이지 않는다', (tester) async {
    await _pumpMyBattles(
      tester,
      repository: _MyBattlesRepository(),
      summaries: [_activeSummary()],
    );

    expect(findText('방 청소하기'), findsOneWidget);
    expect(findText(AppStrings.battleIntroMatching), findsNothing);
    expect(findText(AppStrings.battleIntroEvidence), findsNothing);
    expect(findText(AppStrings.battleIntroJudging), findsNothing);
  });

  // audit.md가 적지 않은 자리(developer 재량). 모집을 이미 올려 본 사람은 만들기 흐름을 한 번 지났고
  // 기준·동의 화면에서 설명을 다 읽은 뒤다. 거기서는 빈 상태 자체가 뜨지 않으므로 블록도 두지 않는다.
  testWidgets('모집 1건만 있는 화면에도 소개 블록을 두지 않는다', (tester) async {
    await _pumpMyBattles(
      tester,
      repository: _MyBattlesRepository(recruits: [_recruit()]),
    );

    expect(findText(AppStrings.battleNoActiveBattlesYet), findsOneWidget);
    expect(findText(AppStrings.battleIntroMatching), findsNothing);
    expect(findText(AppStrings.battleIntroEvidence), findsNothing);
    expect(findText(AppStrings.battleIntroJudging), findsNothing);
  });
}

/// 판정 창(판정 기한 2시간 남음)에 들어간 내 대결. 상대는 사진을 냈고 나는 아직 판정하지 않았다.
BattleSummary _judgingSummaryNow() {
  final now = DateTime.now();
  return BattleSummary(
    battle: Battle(
      id: 'j1',
      type: 'quality',
      status: 'judging',
      title: '방 청소하기',
      creatorId: 'me',
      opponentId: 'friend',
      createdAt: now.subtract(const Duration(days: 2)),
      startedAt: now.subtract(const Duration(days: 2)),
      deadlineAt: now.subtract(const Duration(hours: 1)),
      judgingOpenedAt: now.subtract(const Duration(hours: 1)),
      judgeDeadlineAt: now.add(const Duration(hours: 2, minutes: 1)),
      durationMinutes: 2880,
      minCriteria: const ['바닥이 보인다'],
      superiorityCriteria: const ['먼지가 없다'],
    ),
    otherPartyName: '도윤',
    me: const BattleParticipant(battleId: 'j1', userId: 'me', hasSubmitted: true),
    opponent: const BattleParticipant(
      battleId: 'j1',
      userId: 'friend',
      hasSubmitted: true,
    ),
  );
}

/// 제출 창(사진 마감 5시간 남음)인 내 대결.
BattleSummary _activeSummaryNow({
  bool iSubmitted = true,
  bool opponentSubmitted = false,
}) {
  final now = DateTime.now();
  return BattleSummary(
    battle: Battle(
      id: 'a2',
      type: 'speed',
      status: 'active',
      title: '아침 운동하기',
      creatorId: 'me',
      opponentId: 'friend',
      createdAt: now.subtract(const Duration(hours: 1)),
      startedAt: now.subtract(const Duration(hours: 1)),
      deadlineAt: now.add(const Duration(hours: 5, minutes: 1)),
      durationMinutes: 360,
      minCriteria: const ['운동복을 입은 사진'],
    ),
    otherPartyName: '도윤',
    me: BattleParticipant(battleId: 'a2', userId: 'me', hasSubmitted: iSubmitted),
    opponent: BattleParticipant(
      battleId: 'a2',
      userId: 'friend',
      hasSubmitted: opponentSubmitted,
    ),
  );
}
