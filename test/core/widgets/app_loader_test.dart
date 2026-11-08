import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todododo/core/strings.dart';
import 'package:todododo/core/theme/app_palette.dart';
import 'package:todododo/core/widgets/app_loader.dart';
import 'package:todododo/core/widgets/evidence_photo_frame.dart';

/// AppLoader(design 5.2·4.4): 애니메이션 줄이기면 멈추고 셋 다 inkMuted, 시맨틱 라벨은 그대로.
void main() {
  Widget host(Widget child, {bool disableAnimations = false}) {
    return MaterialApp(
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(disableAnimations: disableAnimations),
          child: Scaffold(body: Center(child: child)),
        ),
      ),
    );
  }

  List<Color?> dotColors(WidgetTester tester) {
    return tester
        .widgetList<Container>(
          find.descendant(
            of: find.byType(AppLoader),
            matching: find.byType(Container),
          ),
        )
        .map((c) => (c.decoration as BoxDecoration?)?.color)
        .toList();
  }

  testWidgets('애니메이션 줄이기에서는 멈춰 있고 세 점이 모두 inkMuted다', (tester) async {
    await tester.pumpWidget(
      host(const AppLoader.medium(), disableAnimations: true),
    );
    // 티커가 돌고 있으면 pumpAndSettle이 시간 초과로 실패한다.
    await tester.pumpAndSettle();
    final colors = dotColors(tester);
    expect(colors, hasLength(3));
    expect(colors, everyElement(AppPalette.inkMuted));
  });

  testWidgets('평소에는 점 색이 inkMuted와 line 사이에서 바뀐다', (tester) async {
    await tester.pumpWidget(host(const AppLoader.small()));
    final first = dotColors(tester);
    await tester.pump(AppLoader.period ~/ 3);
    final later = dotColors(tester);
    expect(first, hasLength(3));
    expect(later, isNot(first));
    for (final color in [...first, ...later]) {
      final c = color!;
      // 두 색 사이의 보간 값이다(팔레트 밖으로 나가지 않는다).
      expect(c.r, inInclusiveRange(AppPalette.inkMuted.r, AppPalette.line.r));
    }
  });

  testWidgets('크기: small 점 6, medium 점 8', (tester) async {
    await tester.pumpWidget(
      host(const AppLoader.small(), disableAnimations: true),
    );
    final small = find.descendant(
      of: find.byType(AppLoader),
      matching: find.byType(Container),
    );
    expect(tester.getSize(small.first), const Size(6, 6));

    await tester.pumpWidget(
      host(const AppLoader.medium(), disableAnimations: true),
    );
    final medium = find.descendant(
      of: find.byType(AppLoader),
      matching: find.byType(Container),
    );
    expect(tester.getSize(medium.first), const Size(8, 8));
  });

  testWidgets('시맨틱 라벨은 로딩 문구다', (tester) async {
    await tester.pumpWidget(
      host(const AppLoader.medium(), disableAnimations: true),
    );
    expect(find.bySemanticsLabel(AppStrings.loading), findsOneWidget);
  });

  testWidgets('증거 사진은 clip 없이 BoxFit.contain으로 그린다', (tester) async {
    await tester.pumpWidget(
      host(
        EvidencePhotoFrame.thumbnail(image: MemoryImage(Uint8List(0))),
        disableAnimations: true,
      ),
    );
    final image = find.byType(Image);
    expect(image, findsOneWidget);
    expect(tester.widget<Image>(image).fit, BoxFit.contain);
    expect(
      tester.widget<Image>(image).filterQuality,
      Image(image: MemoryImage(Uint8List(0))).filterQuality,
    );
    expect(
      find.ancestor(of: image, matching: find.byType(ClipRRect)),
      findsNothing,
    );
    expect(
      find.ancestor(of: image, matching: find.byType(ClipPath)),
      findsNothing,
    );
  });
}
