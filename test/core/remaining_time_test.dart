import 'package:flutter_test/flutter_test.dart';
import 'package:todododo/core/remaining_time.dart';

/// 대결 상세 헤더·내 대결 목록 카드·개인 투두 목록이 **같은 서식**을 쓴다
/// (todo-due-date spec "남은 시간 문구 — 전체 규칙"). 한쪽만 바뀌면 같은 시각이 화면마다
/// 다르게 읽힌다.
void main() {
  group('formatRemaining', () {
    test('단위 두 개까지 병기한다', () {
      expect(formatRemaining(const Duration(days: 3, hours: 5)), '3일 5시간');
      expect(
        formatRemaining(const Duration(days: 3, hours: 12, minutes: 30)),
        '3일 12시간',
      );
      expect(formatRemaining(const Duration(hours: 5, minutes: 30)), '5시간 30분');
      expect(formatRemaining(const Duration(hours: 1, minutes: 42)), '1시간 42분');
    });

    test('아래 단위가 0이면 생략한다', () {
      expect(formatRemaining(const Duration(days: 2, minutes: 40)), '2일');
      expect(formatRemaining(const Duration(hours: 5, seconds: 30)), '5시간');
      expect(formatRemaining(const Duration(days: 3)), '3일');
    });

    test('세 번째 단위는 버린다', () {
      expect(
        formatRemaining(const Duration(days: 1, hours: 3, minutes: 59)),
        '1일 3시간',
      );
      expect(
        formatRemaining(const Duration(hours: 2, minutes: 20, seconds: 59)),
        '2시간 20분',
      );
    });

    test('초는 1분 미만 구간에서만 쓴다', () {
      expect(formatRemaining(const Duration(minutes: 43, seconds: 12)), '43분');
      expect(formatRemaining(const Duration(minutes: 1, seconds: 30)), '1분');
      expect(formatRemaining(const Duration(seconds: 30)), '30초');
      expect(formatRemaining(const Duration(seconds: 12)), '12초');
    });

    test('단위 경계에서 한 단계 아래로 내려간다', () {
      expect(formatRemaining(const Duration(hours: 24)), '1일');
      expect(
        formatRemaining(const Duration(hours: 23, minutes: 59)),
        '23시간 59분',
      );
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
