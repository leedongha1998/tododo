import 'package:flutter_test/flutter_test.dart';
import 'package:todododo/core/widgets/initial_badge.dart';

void main() {
  group('displayInitial', () {
    test('한글 이름은 첫 글자', () {
      expect(displayInitial('홍길동'), '홍');
    });

    test('앞 공백을 지우고 라틴 소문자는 대문자로', () {
      expect(displayInitial('  alice'), 'A');
    });

    test('비었거나 공백뿐이면 물음표', () {
      expect(displayInitial(''), '?');
      expect(displayInitial('   '), '?');
    });

    test('탈퇴한 사용자 묘비도 특별 취급 없이 첫 글자', () {
      expect(displayInitial('탈퇴한 사용자'), '탈');
    });

    test('한 글자 이름은 그대로', () {
      expect(displayInitial('가'), '가');
    });

    test('이모지로 시작하면 이모지 한 글자 단위로 자른다', () {
      // 피부색 조합 이모지, 가족(ZWJ) 이모지
      expect(displayInitial('\u{1F44D}\u{1F3FD}최고'), '\u{1F44D}\u{1F3FD}');
      expect(
        displayInitial('\u{1F468}‍\u{1F469}‍\u{1F467} 가족'),
        '\u{1F468}‍\u{1F469}‍\u{1F467}',
      );
    });

    test('결합 문자는 앞 글자와 함께 한 글자로 본다', () {
      // e + U+0301(결합 악센트) → 두 코드 포인트가 한 글자 단위로 남는다.
      expect(displayInitial('éclair'), 'É');
      // 미리 합성된 é
      expect(displayInitial('éclair'), 'É');
    });

    test('대문자로 바꾸면 글자 수가 늘어나는 글자는 그대로 둔다', () {
      expect(displayInitial('ßeta'), 'ß');
    });
  });
}
