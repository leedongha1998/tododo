import 'package:flutter_test/flutter_test.dart';
import 'package:todododo/core/push/notification_payload.dart';

void main() {
  const id = '3f2504e0-4f89-11d3-9a0c-0305e82c3301';

  test('payload의 battle_id를 그대로 돌려준다', () {
    expect(battleIdOf({'battle_id': id, 'kind': 'finished'}), id);
  });

  test('앞뒤 공백은 떼고 본다', () {
    expect(battleIdOf({'battle_id': '  $id  '}), id);
  });

  test('키가 없거나 uuid 모양이 아니면 null이다', () {
    expect(battleIdOf(const {}), isNull);
    expect(battleIdOf(const {'kind': 'finished'}), isNull);
    expect(battleIdOf(const {'battle_id': ''}), isNull);
    expect(battleIdOf(const {'battle_id': 'b1'}), isNull);
    // 서버는 문자열만 넣지만, 플랫폼을 거쳐 온 값이라 타입을 믿지 않는다.
    expect(battleIdOf(const {'battle_id': 42}), isNull);
    expect(battleIdOf(const {'battle_id': null}), isNull);
  });
}
