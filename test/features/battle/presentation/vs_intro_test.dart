import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todododo/core/strings.dart';
import 'package:todododo/core/theme/app_theme.dart';
import 'package:todododo/features/battle/presentation/vs_intro.dart';

/// 정지 화면(애니메이션 줄이기)으로 인트로를 그린다. 스스로 닫히는 타이머가 돌기 전에 트리에서 내린다.
Future<void> _pumpStill(WidgetTester tester, {required String myName, required String opponentName}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: VsIntro(myName: myName, opponentName: opponentName),
    ),
  );
  await tester.pump();
}

void main() {
  group('VsIntroTimeline', () {
    test('모든 구간이 0~1500ms 안에 있고 시작 < 끝, 사라짐이 1500ms에 끝난다', () {
      // 띠(0–200)와 명판(150–550)은 일부러 겹친다(redesign design 6.3). 그래서 "이어진다"가 아니라
      // "범위 안"을 본다.
      for (final segment in VsIntroTimeline.segments) {
        expect(segment.start, greaterThanOrEqualTo(0));
        expect(segment.end, lessThanOrEqualTo(VsIntroTimeline.totalMs));
        expect(segment.end, greaterThan(segment.start));
      }
      expect(VsIntroTimeline.fade.end, VsIntroTimeline.totalMs);
      expect(VsIntroTimeline.totalMs, 1500);
    });

    test('번쩍임은 100ms 한 번이고 정지 화면 시각은 사라짐 시작과 같다', () {
      expect(VsIntroTimeline.flash.end - VsIntroTimeline.flash.start, 100);
      expect(VsIntroTimeline.stillFrameMs, VsIntroTimeline.fade.start);
    });
  });

  group('VsIntroFrame', () {
    test('시작하면 띠가 없고 명판은 화면 밖, VS는 안 보인다', () {
      final frame = VsIntroFrame.at(0);
      expect(frame.band, 0);
      expect(frame.slide, 0);
      expect(frame.versusScale, isNull);
      expect(frame.versusOpacity, 0);
      expect(frame.cover, 0);
    });

    test('띠는 200ms에 다 펼쳐지고 명판은 550ms에 제자리다', () {
      expect(VsIntroFrame.at(200).band, 1);
      expect(VsIntroFrame.at(550).slide, 1);
      // 띠가 다 열리기 전에 명판이 들어오기 시작한다(150–200 겹침).
      expect(VsIntroFrame.at(180).band, lessThan(1));
      expect(VsIntroFrame.at(180).slide, greaterThan(0));
    });

    test('VS는 1.6배·투명으로 나타나 750ms에 1배·불투명이 된다', () {
      expect(VsIntroFrame.at(549).versusScale, isNull);
      expect(VsIntroFrame.at(550).versusScale, closeTo(1.6, 1e-9));
      expect(VsIntroFrame.at(550).versusOpacity, 0);
      expect(VsIntroFrame.at(750).versusScale, closeTo(1.0, 1e-9));
      expect(VsIntroFrame.at(750).versusOpacity, 1);
    });

    test('VS의 넘침(easeOutBack)은 작고 투명도는 0~1을 벗어나지 않는다', () {
      for (var ms = 550; ms <= 750; ms += 5) {
        final frame = VsIntroFrame.at(ms);
        expect(frame.versusScale, inInclusiveRange(0.9, 1.6));
        expect(frame.versusOpacity, inInclusiveRange(0, 1));
      }
    });

    test('번쩍임은 연속된 한 덩어리(750 이상 850 미만)', () {
      final flashingMs = [
        for (var ms = 0; ms <= 1500; ms += 10)
          if (VsIntroFrame.at(ms).flash) ms,
      ];
      expect(flashingMs, hasLength(10));
      expect(flashingMs.first, 750);
      expect(flashingMs.last, 840);
      for (var i = 1; i < flashingMs.length; i++) {
        expect(flashingMs[i] - flashingMs[i - 1], 10);
      }
      expect(VsIntroFrame.at(850).flash, isFalse);
    });

    test('1300ms부터 배경색으로 덮여 1500ms에 다 덮인다', () {
      expect(VsIntroFrame.at(1299).cover, 0);
      expect(VsIntroFrame.at(1400).cover, inExclusiveRange(0, 1));
      expect(VsIntroFrame.at(1500).cover, 1);
    });

    test('띠·명판·덮기 진행률은 각 구간 안에서 줄어들지 않는다', () {
      var previous = VsIntroFrame.at(0);
      for (var ms = 1; ms <= 1500; ms++) {
        final frame = VsIntroFrame.at(ms);
        expect(frame.band, greaterThanOrEqualTo(previous.band), reason: 'band @ $ms');
        expect(frame.slide, greaterThanOrEqualTo(previous.slide), reason: 'slide @ $ms');
        expect(frame.cover, greaterThanOrEqualTo(previous.cover), reason: 'cover @ $ms');
        expect(frame.versusOpacity, greaterThanOrEqualTo(previous.versusOpacity),
            reason: 'opacity @ $ms');
        previous = frame;
      }
    });

    test('정지 화면은 완성 상태(띠·명판·VS 1배 불투명, 번쩍임·덮기 없음)다', () {
      final still = VsIntroFrame.at(VsIntroTimeline.stillFrameMs);
      expect(still.band, 1);
      expect(still.slide, 1);
      expect(still.versusScale, closeTo(1.0, 1e-9));
      expect(still.versusOpacity, 1);
      expect(still.flash, isFalse);
      expect(still.cover, 0);
    });
  });

  // redesign 후속 결정 7: 내 이름 조회가 실패해 "나"로 대신 보일 때 이니셜·이름·자리 이름이 "나"로 세 번 나왔다.
  group('VS 인트로 자리 이름 중복', () {
    testWidgets('이름이 있으면 아래 "나"·위 "상대" 자리 이름이 보인다', (tester) async {
      await _pumpStill(tester, myName: '민지', opponentName: '도윤');
      expect(find.text(AppStrings.battleMe), findsOneWidget);
      expect(find.text(AppStrings.battleOpponent), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('내 이름이 "나"(조회 실패 대체)면 아래 "나" 자리 이름을 숨긴다 — 이니셜·이름 두 번만', (tester) async {
      await _pumpStill(tester, myName: AppStrings.battleMe, opponentName: '도윤');
      // 이니셜 칸 "나" + 명판 이름 "나". 자리 이름은 없다.
      expect(find.text(AppStrings.battleMe), findsNWidgets(2));
      expect(find.text(AppStrings.battleOpponent), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
