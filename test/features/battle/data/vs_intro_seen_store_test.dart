import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todododo/features/battle/data/vs_intro_seen_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('봤다고 기록하면 같은 사람·같은 대결은 봤음이다', () async {
    const store = VsIntroSeenStore();
    expect(await store.hasSeen('me', 'b1'), isFalse);

    await store.markSeen('me', 'b1');

    expect(await store.hasSeen('me', 'b1'), isTrue);
  });

  test('다른 계정이나 다른 대결에는 기록이 번지지 않는다', () async {
    const store = VsIntroSeenStore();
    await store.markSeen('me', 'b1');

    expect(await store.hasSeen('other', 'b1'), isFalse);
    expect(await store.hasSeen('me', 'b2'), isFalse);
  });

  test('키는 계정별·대결별이다', () {
    expect(VsIntroSeenStore.keyFor('u1', 'b9'), 'vs_intro_seen/u1/b9');
  });
}
