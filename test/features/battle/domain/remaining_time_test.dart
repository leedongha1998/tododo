import 'package:flutter_test/flutter_test.dart';
import 'package:todododo/features/battle/domain/remaining_time.dart';

/// 대결 상세 헤더와 내 대결 목록 카드가 같은 서식을 쓴다(mobile-ux M1).
/// 한쪽만 바뀌면 같은 시각이 화면마다 다르게 읽힌다.
void main() {
  group('formatRemaining', () {
    test('떨어지는 가장 큰 단위 하나로만 말한다', () {
      expect(formatRemaining(const Duration(days: 3, hours: 5)), '3일');
      expect(formatRemaining(const Duration(hours: 5, minutes: 30)), '5시간');
      expect(formatRemaining(const Duration(minutes: 30, seconds: 30)), '30분');
      expect(formatRemaining(const Duration(seconds: 30)), '30초');
    });

    test('단위 경계에서 한 단계 아래로 내려간다', () {
      expect(formatRemaining(const Duration(hours: 24)), '1일');
      expect(formatRemaining(const Duration(hours: 23, minutes: 59)), '23시간');
      expect(formatRemaining(const Duration(minutes: 60)), '1시간');
      expect(formatRemaining(const Duration(minutes: 59)), '59분');
      expect(formatRemaining(const Duration(seconds: 60)), '1분');
      expect(formatRemaining(const Duration(seconds: 59)), '59초');
    });

    // 호출부가 "지나지 않았다"를 먼저 확인하므로 0은 사실상 오지 않지만,
    // 와도 빈 문자열이나 음수가 보이지 않아야 한다.
    test('0이면 0초로 말한다', () {
      expect(formatRemaining(Duration.zero), '0초');
    });
  });
}
