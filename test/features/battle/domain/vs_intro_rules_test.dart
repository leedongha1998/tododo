import 'package:flutter_test/flutter_test.dart';
import 'package:todododo/features/battle/domain/vs_intro_rules.dart';

void main() {
  group('shouldShowVsIntro', () {
    test('매칭된 진행 중 대결을 아직 안 봤으면 띄운다', () {
      expect(shouldShowVsIntro(status: 'active', alreadySeen: false), isTrue);
      expect(shouldShowVsIntro(status: 'judging', alreadySeen: false), isTrue);
    });

    test('이미 봤으면 다시 띄우지 않는다', () {
      expect(shouldShowVsIntro(status: 'active', alreadySeen: true), isFalse);
      expect(shouldShowVsIntro(status: 'judging', alreadySeen: true), isFalse);
    });

    test('모집 중(상대 없음)이거나 종결된 대결에는 띄우지 않는다', () {
      for (final status in ['pending', 'finished', 'disputed', 'draw', 'cancelled', 'voided']) {
        expect(shouldShowVsIntro(status: status, alreadySeen: false), isFalse, reason: status);
      }
    });
  });
}
