import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:todododo/core/strings.dart';
import 'package:todododo/core/theme/app_icons.dart';
import 'package:todododo/core/theme/app_palette.dart';
import 'package:todododo/core/theme/app_theme.dart';
import 'package:todododo/core/widgets/keep_words_text.dart';
import 'package:todododo/features/battle/data/battle.dart';
import 'package:todododo/features/battle/data/battle_participant.dart';
import 'package:todododo/features/battle/data/battle_repository.dart';
import 'package:todododo/features/battle/data/battle_submission.dart';
import 'package:todododo/features/battle/data/criteria_check_result.dart';
import 'package:todododo/features/battle/data/open_recruit_page.dart';
import 'package:todododo/features/battle/data/player_card.dart';
import 'package:todododo/features/battle/data/submission_result.dart';
import 'package:todododo/features/battle/data/vs_intro_seen_store.dart';
import 'package:todododo/features/battle/domain/battle_detail.dart';
import 'package:todododo/features/battle/domain/battle_providers.dart';
import 'package:todododo/features/battle/presentation/battle_detail_screen.dart';
import 'package:todododo/features/battle/presentation/judgment_choice.dart';
import 'package:todododo/features/battle/presentation/judgment_section.dart';

import '../../helpers/line_breaks.dart';
import '../../helpers/text_finders.dart';

/// 상호 판정 화면. 판정 **결론**은 서버가 내므로 여기서 보는 것은
/// "무엇을 묻는가 / 언제 보낼 수 있는가 / 무엇을 보냈는가"뿐이다.
class _FakeBattleRepository implements BattleRepository {
  int judgeCount = 0;
  bool? sentPassed;
  String? sentSuperiorId;
  Object? failWith;

  @override
  Future<String> submitJudgment({
    required String battleId,
    required bool passed,
    String? superiorId,
  }) async {
    judgeCount++;
    sentPassed = passed;
    sentSuperiorId = superiorId;
    final failure = failWith;
    if (failure != null) throw failure;
    return 'judging';
  }

  @override
  Future<String> createEvidencePhotoUrl(String path) async => 'https://example.com/$path';

  @override
  Future<PlayerCard> fetchPlayerCard(String userId) async => const PlayerCard(
        userId: 'friend',
        displayName: '친구',
        score: 3,
        wins: 1,
        losses: 0,
        draws: 0,
      );

  @override
  Future<List<BattleSubmission>> fetchSubmissions(String battleId) async => const [];

  @override
  Future<String> createBattle({required String checkId, required int durationMinutes}) async => 'b';

  @override
  Future<int> updateBattleCriteria({required String battleId, required String checkId}) async => 1;

  @override
  Future<MyLimits> fetchMyLimits() async => const MyLimits(
        consented: true,
        criteriaCallsLeft: 10,
      );

  @override
  Future<OpenRecruitPage> fetchOpenRecruits({int limit = openRecruitPageSize, RecruitCursor? cursor, String? query, String? type, String? durationBand}) async => const OpenRecruitPage.empty();

  @override
  Future<Battle?> fetchOpenRecruitBattle(String battleId) async => null;

  @override
  Future<List<Battle>> fetchMyRecruits() async => const [];

  @override
  Future<Map<String, String>> fetchDisplayNames(Iterable<String> ids) async => {};

  @override
  Future<void> joinBattle(String battleId, int criteriaVersion) async {}

  @override
  Future<void> cancelBattle(String battleId) async {}

  @override
  Future<void> forfeitBattle(String battleId) async {}

  @override
  Future<List<Battle>> fetchMyBattles() async => const [];

  @override
  Future<Battle> fetchBattle(String battleId) => throw UnimplementedError();

  @override
  Future<List<BattleParticipant>> fetchParticipants(String battleId) async => const [];

  @override
  Future<List<BattleParticipant>> fetchParticipantsOf(Iterable<String> battleIds) async =>
      const [];

  @override
  Future<String> uploadEvidencePhoto({
    required String battleId,
    required Uint8List bytes,
  }) async =>
      '$battleId/me/photo.jpg';

  @override
  Future<SubmissionResult> submitEvidence({
    required String battleId,
    required String objectPath,
    required DateTime capturedAt,
  }) async =>
      const SubmissionResult(submissionId: 1);
}

class _SeenAllStore implements VsIntroSeenStore {
  const _SeenAllStore();

  @override
  Future<bool> hasSeen(String userId, String battleId) async => true;

  @override
  Future<void> markSeen(String userId, String battleId) async {}
}

const _opponentPhotoPath = 'b1/friend/photo.jpg';

BattleSubmission _submission({required int id, required String userId}) {
  final when = DateTime.now().subtract(const Duration(minutes: 10));
  return BattleSubmission(
    id: id,
    battleId: 'b1',
    userId: userId,
    objectPath: 'b1/$userId/photo.jpg',
    capturedAt: when,
    submittedAt: when,
  );
}

/// 판정 창이 열린 대결. 서버는 창이 열리는 순간 양쪽 제출 행과 판정 기한을 함께 내준다.
BattleDetail _judging({
  String type = 'speed',
  bool myHasSubmitted = true,
  bool opponentHasSubmitted = true,
  bool myHasJudged = false,
  bool opponentHasJudged = false,
  Duration judgeLeft = const Duration(hours: 23),
}) {
  final now = DateTime.now();
  final battle = Battle(
    id: 'b1',
    type: type,
    status: 'judging',
    title: '책상 정리하기',
    creatorId: 'me',
    opponentId: 'friend',
    createdAt: now.subtract(const Duration(hours: 2)),
    startedAt: now.subtract(const Duration(hours: 2)),
    deadlineAt: now.subtract(const Duration(minutes: 5)),
    judgingOpenedAt: now.subtract(const Duration(minutes: 5)),
    judgeDeadlineAt: now.add(judgeLeft),
    minCriteria: const ['상판이 보인다'],
    superiorityCriteria: type == 'quality' ? const ['먼지가 없다'] : null,
  );
  return BattleDetail(
    battle: battle,
    me: BattleParticipant(
      battleId: 'b1',
      userId: 'me',
      hasSubmitted: myHasSubmitted,
      hasJudged: myHasJudged,
    ),
    opponent: BattleParticipant(
      battleId: 'b1',
      userId: 'friend',
      hasSubmitted: opponentHasSubmitted,
      hasJudged: opponentHasJudged,
    ),
    myName: '나',
    opponentName: '친구',
    submissions: [
      if (myHasSubmitted) _submission(id: 1, userId: 'me'),
      if (opponentHasSubmitted) _submission(id: 2, userId: 'friend'),
    ],
  );
}

Widget _screen(
  BattleDetail detail,
  _FakeBattleRepository repository, {
  AsyncValue<String>? photo,
  ThemeData? theme,
  double textScale = 1.0,
}) {
  return ProviderScope(
    overrides: [
      battleDetailProvider(detail.battle.id).overrideWith((ref) async => detail),
      battleRepositoryProvider.overrideWithValue(repository),
      vsIntroSeenStoreProvider.overrideWithValue(const _SeenAllStore()),
      // 서명 URL 발급은 Storage 정책을 거친다. 성공/실패를 여기서 갈아 끼운다.
      if (photo != null)
        evidencePhotoUrlProvider(_opponentPhotoPath).overrideWith(
          (ref) => photo.when(
            data: (url) => Future.value(url),
            loading: () => Future<String>.error('loading은 쓰지 않는다'),
            error: (error, stackTrace) => Future<String>.error(error),
          ),
        ),
    ],
    child: MaterialApp(
      theme: theme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: BattleDetailScreen(battleId: detail.battle.id),
    ),
  );
}

/// 선택지는 사진·기준 아래라 기본 테스트 화면(800x600) 밖으로 밀린다.
/// 판정 선택지 라벨. 화면은 어절 단위 줄바꿈을 위해 글자 사이에 WORD JOINER를 끼워 그리므로
/// 원문으로 찾는다([KeepWordsText.text]).
Finder _choice(String label) =>
    find.byWidgetPredicate((widget) => widget is KeepWordsText && widget.text == label);

Future<void> _tapChoice(WidgetTester tester, String label) async {
  final choice = _choice(label);
  await tester.ensureVisible(choice);
  await tester.pumpAndSettle();
  await tester.tap(choice);
  await tester.pumpAndSettle();
}

Future<void> _tapSend(WidgetTester tester) async {
  final send = findWidgetWithText(FilledButton, AppStrings.battleJudgmentSend).first;
  await tester.ensureVisible(send);
  await tester.pumpAndSettle();
  await tester.tap(send);
  await tester.pumpAndSettle();
}

void main() {
  const photoOk = AsyncValue<String>.data('https://example.com/$_opponentPhotoPath');

  testWidgets('속도전 판정은 통과/미통과 두 선택지만 묻는다', (tester) async {
    await tester.pumpWidget(_screen(_judging(), _FakeBattleRepository(), photo: photoOk));
    await tester.pumpAndSettle();

    expect(findText(AppStrings.battleJudgmentMinQuestion), findsOneWidget);
    expect(_choice(AppStrings.battleJudgmentPassed), findsOneWidget);
    expect(_choice(AppStrings.battleJudgmentFailed), findsOneWidget);
    // 속도전에는 우열 질문이 없다(서버도 우열 값을 받으면 거부한다).
    expect(findText(AppStrings.battleJudgmentSuperiorityQuestion), findsNothing);
    // 판정할 기준이 함께 보인다.
    expect(findText('상판이 보인다'), findsOneWidget);
    // 자유 텍스트 입력은 어디에도 없다.
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('아무것도 고르지 않으면 판정을 보낼 수 없다', (tester) async {
    final repository = _FakeBattleRepository();
    await tester.pumpWidget(_screen(_judging(), repository, photo: photoOk));
    await tester.pumpAndSettle();

    final send = tester.widget<FilledButton>(
      findWidgetWithText(FilledButton, AppStrings.battleJudgmentSend).first,
    );
    expect(send.onPressed, isNull);
    expect(repository.judgeCount, 0);
  });

  testWidgets('속도전: 통과를 고르고 확인하면 승인이 서버로 간다', (tester) async {
    final repository = _FakeBattleRepository();
    await tester.pumpWidget(_screen(_judging(), repository, photo: photoOk));
    await tester.pumpAndSettle();

    await _tapChoice(tester, AppStrings.battleJudgmentPassed);
    await _tapSend(tester);

    // 되돌릴 수 없으니 확인 전에는 보내지 않는다.
    expect(findText(AppStrings.battleJudgmentConfirm), findsOneWidget);
    expect(repository.judgeCount, 0);

    await tester.tap(findWidgetWithText(FilledButton, AppStrings.battleJudgmentSend).last);
    await tester.pumpAndSettle();

    expect(repository.judgeCount, 1);
    expect(repository.sentPassed, isTrue);
    // 속도전은 우열을 매기지 않는다.
    expect(repository.sentSuperiorId, isNull);
  });

  testWidgets('품질전은 최소 기준과 우열을 한 화면에서 묻고 둘 다 고르기 전에는 못 보낸다', (tester) async {
    final repository = _FakeBattleRepository();
    await tester.pumpWidget(
      _screen(_judging(type: 'quality'), repository, photo: photoOk),
    );
    await tester.pumpAndSettle();

    expect(findText(AppStrings.battleJudgmentMinQuestion), findsOneWidget);
    expect(findText(AppStrings.battleJudgmentSuperiorityQuestion), findsOneWidget);
    expect(_choice(AppStrings.battleJudgmentSuperiorMe), findsOneWidget);
    expect(_choice(AppStrings.battleJudgmentSuperiorOpponent), findsOneWidget);
    // 우열 기준도 함께 보인다.
    expect(findText('먼지가 없다'), findsOneWidget);

    FilledButton sendButton() => tester.widget<FilledButton>(
          findWidgetWithText(FilledButton, AppStrings.battleJudgmentSend).first,
        );

    // 최소 기준만 골라도 아직 보낼 수 없다(서버도 SUPERIORITY_REQUIRED로 거부한다).
    await _tapChoice(tester, AppStrings.battleJudgmentPassed);
    expect(sendButton().onPressed, isNull);

    await _tapChoice(tester, AppStrings.battleJudgmentSuperiorOpponent);
    expect(sendButton().onPressed, isNotNull);

    await _tapSend(tester);
    await tester.tap(findWidgetWithText(FilledButton, AppStrings.battleJudgmentSend).last);
    await tester.pumpAndSettle();

    expect(repository.judgeCount, 1);
    expect(repository.sentPassed, isTrue);
    // 고른 사람의 user id가 그대로 간다(상대적 값이 아니다).
    expect(repository.sentSuperiorId, 'friend');
  });

  testWidgets('불복을 고르면 AI가 다시 본다는 안내가 함께 보이고 불복이 서버로 간다', (tester) async {
    final repository = _FakeBattleRepository();
    await tester.pumpWidget(_screen(_judging(), repository, photo: photoOk));
    await tester.pumpAndSettle();

    expect(findText(AppStrings.battleJudgmentRejectHint), findsOneWidget);

    await _tapChoice(tester, AppStrings.battleJudgmentFailed);
    await _tapSend(tester);
    await tester.tap(findWidgetWithText(FilledButton, AppStrings.battleJudgmentSend).last);
    await tester.pumpAndSettle();

    expect(repository.sentPassed, isFalse);
  });

  testWidgets('상대 사진을 받아오지 못하면 판정을 보낼 수 없다', (tester) async {
    final repository = _FakeBattleRepository();
    await tester.pumpWidget(
      _screen(
        _judging(),
        repository,
        photo: AsyncValue<String>.error('forbidden', StackTrace.empty),
      ),
    );
    await tester.pumpAndSettle();

    await _tapChoice(tester, AppStrings.battleJudgmentPassed);

    final send = tester.widget<FilledButton>(
      findWidgetWithText(FilledButton, AppStrings.battleJudgmentSend).first,
    );
    expect(send.onPressed, isNull);
    expect(findText(AppStrings.battleJudgmentPhotoUnavailable), findsOneWidget);
  });

  testWidgets('판정을 보낸 뒤에는 상대 판정 대기 안내만 보인다', (tester) async {
    await tester.pumpWidget(
      _screen(_judging(myHasJudged: true), _FakeBattleRepository(), photo: photoOk),
    );
    await tester.pumpAndSettle();

    expect(findText(AppStrings.battleJudgmentSentTitle), findsOneWidget);
    expect(findText(AppStrings.battleJudgmentWaitingOpponent), findsOneWidget);
    expect(findText(AppStrings.battleJudgmentSend), findsNothing);
  });

  // 양쪽 판정이 끝났는데 아직 judging이면 불복 건의 AI 재판정이 남은 것이다.
  testWidgets('양쪽 판정이 끝나고도 judging이면 AI 재판정 중이라고 알린다', (tester) async {
    await tester.pumpWidget(
      _screen(
        _judging(myHasJudged: true, opponentHasJudged: true),
        _FakeBattleRepository(),
        photo: photoOk,
      ),
    );
    await tester.pumpAndSettle();

    expect(findText(AppStrings.battleJudgmentAiTitle), findsOneWidget);
    expect(findText(AppStrings.battleJudgmentSend), findsNothing);
  });

  testWidgets('상대가 사진을 내지 않았으면 판정할 것이 없다고 알린다', (tester) async {
    await tester.pumpWidget(
      _screen(_judging(opponentHasSubmitted: false), _FakeBattleRepository()),
    );
    await tester.pumpAndSettle();

    expect(findText(AppStrings.battleJudgmentNothingTitle), findsOneWidget);
    expect(findText(AppStrings.battleJudgmentSend), findsNothing);
  });

  testWidgets('판정 기한이 지나면 판정 입력 대신 자동 처리 안내가 보인다', (tester) async {
    await tester.pumpWidget(
      _screen(
        _judging(judgeLeft: const Duration(minutes: -1)),
        _FakeBattleRepository(),
        photo: photoOk,
      ),
    );
    await tester.pumpAndSettle();

    expect(findText(AppStrings.battleJudgmentWindowClosedTitle), findsOneWidget);
    expect(findText(AppStrings.battleJudgmentSend), findsNothing);
  });

  testWidgets('서버가 거부하면 코드별 문구를 띄우고 화면을 유지한다', (tester) async {
    final repository = _FakeBattleRepository()..failWith = Exception('boom');
    await tester.pumpWidget(_screen(_judging(), repository, photo: photoOk));
    await tester.pumpAndSettle();

    await _tapChoice(tester, AppStrings.battleJudgmentPassed);
    await _tapSend(tester);
    await tester.tap(findWidgetWithText(FilledButton, AppStrings.battleJudgmentSend).last);
    await tester.pumpAndSettle();

    expect(repository.judgeCount, 1);
    expect(findText(AppStrings.battleJudgmentSendFailed), findsOneWidget);
  });

  // 포기 버튼이 judging에도 있는지는 widget_test가 덮는다. 여기서는 제출 자리가 닫혔는지만 본다.
  testWidgets('판정 창에서는 제출·교체 자리가 없다', (tester) async {
    await tester.pumpWidget(_screen(_judging(), _FakeBattleRepository(), photo: photoOk));
    await tester.pumpAndSettle();

    expect(findText(AppStrings.battleEvidenceTakePhoto), findsNothing);
    expect(findText(AppStrings.battleEvidenceReplace), findsNothing);
  });

  testWidgets('헤더가 사진 마감과 판정 마감을 다른 줄로 보여 준다', (tester) async {
    await tester.pumpWidget(_screen(_judging(), _FakeBattleRepository(), photo: photoOk));
    await tester.pumpAndSettle();

    expect(
      findText('${AppStrings.battleSubmitDeadlineLabel} · ${AppStrings.battleDeadlineClosed}'),
      findsOneWidget,
    );
    expect(
      findTextContaining(AppStrings.battleJudgeDeadlineLabel),
      findsOneWidget,
    );
  });

  group('선택지 라벨은 단어 중간에서 줄을 바꾸지 않는다(360dp 폭, 앱 테마)', () {
    const labels = [
      AppStrings.battleJudgmentPassed,
      AppStrings.battleJudgmentFailed,
      AppStrings.battleJudgmentSuperiorMe,
      AppStrings.battleJudgmentSuperiorOpponent,
    ];

    Future<void> pumpPicked(WidgetTester tester, double scale) async {
      tester.view.physicalSize = const Size(720, 1600);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_screen(
        _judging(type: 'quality'),
        _FakeBattleRepository(),
        photo: photoOk,
        theme: AppTheme.light,
        textScale: scale,
      ));
      await tester.pumpAndSettle();
      // 체크 아이콘이 붙으면 칸이 가장 좁아진다 — 두 질문 모두 고른 상태로 본다.
      await _tapChoice(tester, AppStrings.battleJudgmentPassed);
      await _tapChoice(tester, AppStrings.battleJudgmentSuperiorOpponent);
    }

    RenderParagraph paragraphOf(WidgetTester tester, String label) =>
        tester.renderObject<RenderParagraph>(
          find.descendant(of: _choice(label), matching: find.byType(RichText)),
        );

    // 선택 타일 두 칸이 가로(1:1)로 놓였는지 위아래로 쌓였는지(design-judging-buttons 1A.2 "좁을 때").
    Axis directionOf(WidgetTester tester, String label) {
      final pair = find.ancestor(
        of: _choice(label),
        matching: find.byWidgetPredicate((widget) => widget is JudgmentChoicePair),
      );
      final stacked = find.descendant(
        of: pair,
        matching: find.byKey(const ValueKey('judgment-choice-stacked')),
      );
      return tester.any(stacked) ? Axis.vertical : Axis.horizontal;
    }

    testWidgets('배율 1.0: 두 줄이 되는 라벨도 어절 경계에서만 끊긴다', (tester) async {
      await pumpPicked(tester, 1.0);
      for (final label in labels) {
        expect(breaksOnlyAtSpaces(paragraphOf(tester, label)), isTrue, reason: label);
      }
      // 실제로 줄바꿈이 일어나는 라벨이 있어야 이 검사가 의미 있다(테스트 글꼴은 정사각형이라 실기기보다 넓다).
      expect(labels.any((label) => lineStarts(paragraphOf(tester, label)).isNotEmpty), isTrue);
      expect(directionOf(tester, AppStrings.battleJudgmentPassed), Axis.horizontal);
      expect(directionOf(tester, AppStrings.battleJudgmentSuperiorOpponent), Axis.horizontal);
    });

    // 앱 전체 어절 줄바꿈(redesign 후속 결정 1): 선택지 라벨뿐 아니라 판정 질문·안내 문장도 어절 경계에서만 끊긴다.
    for (final scale in [1.0, 1.5]) {
      testWidgets('배율 $scale: 판정 질문·안내 문장도 어절 경계에서만 끊긴다', (tester) async {
        await pumpPicked(tester, scale);
        const sentences = [
          AppStrings.battleJudgmentOnce,
          AppStrings.battleJudgmentRejectHint,
          AppStrings.battleJudgmentMinQuestion,
          AppStrings.battleJudgmentSuperiorityQuestion,
        ];
        var wrapped = 0;
        for (final sentence in sentences) {
          final paragraph = tester.renderObject<RenderParagraph>(
            find.descendant(of: findText(sentence), matching: find.byType(RichText)),
          );
          expect(breaksOnlyAtSpaces(paragraph), isTrue, reason: sentence);
          if (lineStarts(paragraph).isNotEmpty) wrapped++;
        }
        // 실제로 줄이 바뀌는 문장이 있어야 이 검사가 의미 있다.
        expect(wrapped, greaterThan(0));
      });
    }

    testWidgets('배율 1.5: 한 어절이 칸보다 넓으면 위아래로 쌓아 어절 안에서 끊기지 않는다', (tester) async {
      await pumpPicked(tester, 1.5);
      for (final label in labels) {
        expect(breaksOnlyAtSpaces(paragraphOf(tester, label)), isTrue, reason: label);
      }
      // "통과했어요"는 체크 아이콘과 함께 반 칸에 들어가지 않는다 → 위아래로 쌓는다.
      expect(directionOf(tester, AppStrings.battleJudgmentPassed), Axis.vertical);
      expect(lineStarts(paragraphOf(tester, AppStrings.battleJudgmentPassed)), isEmpty);
    });
  });

  // design-judging-buttons 1A: 질문 하나 = 단계 카드 하나, 기준은 그 카드 안, 경고는 보내기 위.
  group('판정 묶음 1A(단계 카드 + 큰 선택 타일)', () {
    Finder badge(int step) => find.byKey(ValueKey('judgment-step-badge-$step'));
    bool badgeChecked(WidgetTester tester, int step) =>
        tester.any(find.descendant(of: badge(step), matching: find.byIcon(AppIcons.check)));

    testWidgets('품질전: 단계 배지는 답하기 전 숫자, 답하면 초록 체크(1·2 각각)', (tester) async {
      await tester.pumpWidget(_screen(_judging(type: 'quality'), _FakeBattleRepository(), photo: photoOk));
      await tester.pumpAndSettle();

      for (final step in [1, 2]) {
        expect(badge(step), findsOneWidget);
        expect(find.descendant(of: badge(step), matching: findText('$step')), findsOneWidget);
        expect(badgeChecked(tester, step), isFalse);
        expect(
          (tester.widget<Container>(badge(step)).decoration! as ShapeDecoration).color,
          AppPalette.primary,
        );
      }

      // 질문 순서를 강제하지 않는다 — 2부터 답해도 된다.
      await _tapChoice(tester, AppStrings.battleJudgmentSuperiorMe);
      expect(badgeChecked(tester, 2), isTrue);
      expect(badgeChecked(tester, 1), isFalse);
      expect(
        (tester.widget<Container>(badge(2)).decoration! as ShapeDecoration).color,
        AppPalette.success,
      );

      await _tapChoice(tester, AppStrings.battleJudgmentPassed);
      expect(badgeChecked(tester, 1), isTrue);
    });

    testWidgets('속도전: 질문이 하나라 번호 배지를 그리지 않는다', (tester) async {
      await tester.pumpWidget(_screen(_judging(), _FakeBattleRepository(), photo: photoOk));
      await tester.pumpAndSettle();

      expect(badge(1), findsNothing);
      expect(find.byType(JudgmentStepBadge), findsNothing);
      expect(find.byType(JudgmentStepCard), findsOneWidget);
    });

    testWidgets('기준은 질문 카드 안에 있고, 따로 떨어진 기준 블록·안내문은 없다', (tester) async {
      await tester.pumpWidget(_screen(_judging(type: 'quality'), _FakeBattleRepository(), photo: photoOk));
      await tester.pumpAndSettle();

      final cards = find.byType(JudgmentStepCard);
      expect(cards, findsNWidgets(2));
      expect(find.descendant(of: cards.at(0), matching: findText('상판이 보인다')), findsOneWidget);
      expect(find.descendant(of: cards.at(0), matching: findText(AppStrings.battleCriteriaMinTitle)), findsOneWidget);
      expect(find.descendant(of: cards.at(1), matching: findText('먼지가 없다')), findsOneWidget);
      expect(
        find.descendant(of: cards.at(1), matching: findText(AppStrings.battleCriteriaSuperiorityTitle)),
        findsOneWidget,
      );
      // 기준 제목은 카드 머리 꼬리표로 한 번씩만 나온다.
      expect(findText(AppStrings.battleCriteriaMinTitle), findsOneWidget);
      expect(findText(AppStrings.battleCriteriaSuperiorityTitle), findsOneWidget);
    });

    testWidgets('불복을 고르면 힌트 줄이 같은 자리에서 안내 블록으로 바뀐다', (tester) async {
      await tester.pumpWidget(_screen(_judging(), _FakeBattleRepository(), photo: photoOk));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('judgment-reject-hint')), findsOneWidget);
      expect(find.byKey(const ValueKey('judgment-reject-hint-emphasized')), findsNothing);

      await _tapChoice(tester, AppStrings.battleJudgmentFailed);
      expect(find.byKey(const ValueKey('judgment-reject-hint')), findsNothing);
      expect(find.byKey(const ValueKey('judgment-reject-hint-emphasized')), findsOneWidget);
      // 문구는 같다.
      expect(findText(AppStrings.battleJudgmentRejectHint), findsOneWidget);

      await _tapChoice(tester, AppStrings.battleJudgmentPassed);
      expect(find.byKey(const ValueKey('judgment-reject-hint')), findsOneWidget);
    });

    testWidgets('"판정은 한 번만" 경고는 보내기 버튼 바로 위에 있다', (tester) async {
      await tester.pumpWidget(_screen(_judging(type: 'quality'), _FakeBattleRepository(), photo: photoOk));
      await tester.pumpAndSettle();

      final note = tester.getRect(find.byKey(const ValueKey('judgment-once-note')));
      final send = tester.getRect(findWidgetWithText(FilledButton, AppStrings.battleJudgmentSend));
      expect(note.bottom, lessThanOrEqualTo(send.top));
      expect(send.top - note.bottom, moreOrLessEquals(8, epsilon: 0.5));
      // 마지막 단계 카드보다는 아래.
      final lastCard = tester.getRect(find.byType(JudgmentStepCard).last);
      expect(lastCard.bottom, lessThanOrEqualTo(note.top));
    });

    testWidgets('고른 칸은 낭독에서 selected, 단계 머리는 고른 답을 값으로 읽는다', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_screen(_judging(), _FakeBattleRepository(), photo: photoOk));
      await tester.pumpAndSettle();

      await _tapChoice(tester, AppStrings.battleJudgmentPassed);
      final tile = find.ancestor(
        of: _choice(AppStrings.battleJudgmentPassed),
        matching: find.byType(JudgmentChoiceTile),
      );
      expect(tester.getSemantics(tile), isSemantics(isSelected: true, isButton: true));
      expect(
        find.bySemanticsLabel(RegExp(AppStrings.battleJudgmentMinQuestion.replaceAll('?', r'\?'))),
        findsOneWidget,
      );
      final heading = tester.getSemantics(
        find.bySemanticsLabel(RegExp(AppStrings.battleJudgmentMinQuestion.replaceAll('?', r'\?'))),
      );
      expect(heading, isSemantics(value: AppStrings.battleJudgmentPassed, isHeader: true));
      handle.dispose();
    });

    for (final scale in [1.0, 1.5]) {
      testWidgets('360dp·$scale배: 넘치지 않고 단계 카드·타일·경고·보내기가 화면 폭 안에 있다', (tester) async {
        tester.view.physicalSize = const Size(720, 1600);
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(_screen(
          _judging(type: 'quality'),
          _FakeBattleRepository(),
          photo: photoOk,
          theme: AppTheme.light,
          textScale: scale,
        ));
        await tester.pumpAndSettle();
        await _tapChoice(tester, AppStrings.battleJudgmentFailed);
        await _tapChoice(tester, AppStrings.battleJudgmentSuperiorMe);
        expect(tester.takeException(), isNull);

        for (final finder in [
          ...List.generate(2, (i) => find.byType(JudgmentStepCard).at(i)),
          ...List.generate(4, (i) => find.byType(JudgmentChoiceTile).at(i)),
          find.byKey(const ValueKey('judgment-once-note')),
          findWidgetWithText(FilledButton, AppStrings.battleJudgmentSend),
        ]) {
          await tester.ensureVisible(finder);
          await tester.pumpAndSettle();
          final rect = tester.getRect(finder);
          expect(rect.left, greaterThanOrEqualTo(20 - 0.5), reason: '$finder');
          expect(rect.right, lessThanOrEqualTo(340 + 0.5), reason: '$finder');
        }
        // 다 골랐으면 보낼 수 있다.
        final send = tester.widget<FilledButton>(
          findWidgetWithText(FilledButton, AppStrings.battleJudgmentSend),
        );
        expect(send.onPressed, isNotNull);
      });
    }
  });
}
