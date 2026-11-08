import 'package:flutter_test/flutter_test.dart';
import 'package:todododo/main.dart';

/// 시스템 글자 크기 상한(redesign design 3.3, 오너 결정 7). 이 값을 바꾸면 탭 라벨·판정 세그먼트·VS 명판의
/// 넘침 육안 확인(design 9.2)을 다시 해야 한다.
void main() {
  test('시스템 글자 크기는 1.5배에서 멈춘다', () {
    expect(maxTextScale, 1.5);
  });
}
