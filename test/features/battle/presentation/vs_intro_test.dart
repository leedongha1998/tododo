import 'package:flutter_test/flutter_test.dart';
import 'package:todododo/features/battle/presentation/vs_intro.dart';

void main() {
  group('VsIntroTimeline', () {
    test('구간이 겹치지 않고 이어지며 합이 1500ms다', () {
      var cursor = 0;
      for (final segment in VsIntroTimeline.segments) {
        expect(segment.start, cursor);
        expect(segment.end, greaterThan(segment.start));
        cursor = segment.end;
      }
      expect(cursor, VsIntroTimeline.totalMs);
      expect(VsIntroTimeline.totalMs, 1500);
    });

    test('모든 구간 경계가 50ms 계단 위에 있다', () {
      for (final segment in VsIntroTimeline.segments) {
        expect(segment.start % VsIntroTimeline.stepMs, 0);
        expect(segment.end % VsIntroTimeline.stepMs, 0);
      }
    });
  });

  group('VsIntroFrame', () {
    test('시작하면 띠가 없고 명판은 화면 밖, VS는 안 보인다', () {
      final frame = VsIntroFrame.at(0);
      expect(frame.band, 0);
      expect(frame.slide, 0);
      expect(frame.versusScale, isNull);
      expect(frame.cover, 0);
    });

    test('띠는 150ms에 다 펼쳐지고 명판은 550ms에 제자리다', () {
      expect(VsIntroFrame.at(150).band, 1);
      expect(VsIntroFrame.at(550).slide, 1);
      expect(VsIntroFrame.at(349).slide, VsIntroFrame.at(300).slide);
    });

    test('VS는 3배로 나타나 750ms에 1배가 된다', () {
      expect(VsIntroFrame.at(550).versusScale, 3);
      expect(VsIntroFrame.at(750).versusScale, 1);
    });

    test('번쩍임은 한 번, 짧게', () {
      final flashing = [for (var ms = 0; ms <= 1500; ms += 10) VsIntroFrame.at(ms).flash];
      expect(flashing.where((f) => f).length, 5);
      expect(VsIntroFrame.at(760).flash, isTrue);
      expect(VsIntroFrame.at(810).flash, isFalse);
    });

    test('1300ms부터 paper로 덮여 1500ms에 다 덮인다', () {
      expect(VsIntroFrame.at(1299).cover, 0);
      expect(VsIntroFrame.at(1500).cover, 1);
    });

    test('정지 화면은 완성 상태(띠·명판·VS 1배, 번쩍임·덮기 없음)다', () {
      final still = VsIntroFrame.at(VsIntroTimeline.stillFrameMs);
      expect(still.band, 1);
      expect(still.slide, 1);
      expect(still.versusScale, 1);
      expect(still.flash, isFalse);
      expect(still.cover, 0);
    });
  });
}
