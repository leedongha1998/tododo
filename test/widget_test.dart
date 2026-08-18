import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:todododo/core/strings.dart';
import 'package:todododo/main.dart';

void main() {
  testWidgets('App shows home placeholder', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: TododuduApp()));

    expect(find.text(AppStrings.appName), findsWidgets);
  });
}
