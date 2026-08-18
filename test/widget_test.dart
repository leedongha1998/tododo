import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:todododo/core/strings.dart';
import 'package:todododo/features/auth/presentation/login_screen.dart';
import 'package:todododo/main.dart';

void main() {
  testWidgets('Supabase 미설정 시 설정 안내를 보여준다', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: TododuduApp()));

    expect(find.textContaining('Supabase 설정이 필요합니다'), findsOneWidget);
  });

  testWidgets('로그인 화면에 구글 로그인 버튼이 보인다', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: LoginScreen()),
      ),
    );

    expect(find.text(AppStrings.googleSignIn), findsOneWidget);
  });
}
