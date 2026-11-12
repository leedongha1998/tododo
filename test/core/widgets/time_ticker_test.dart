import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todododo/core/widgets/time_ticker.dart';

/// 시간이 흐르는 것만으로 달라지는 화면을 **스스로 다시 그리게** 하는 장치
/// (2026-11-12. 투두 목록과 대결 화면이 함께 쓴다).
///
/// 두 시계를 함께 돌린다 — `now`(화면이 읽는 "지금")와 `tester.pump`의 가짜 시계(타이머가 깨는
/// 시각)다. 실제 앱에서는 둘이 같은 시계이고, 여기서만 손으로 맞춰 돌린다.
void main() {
  testWidgets('말해 준 간격이 지나면 다시 그린다', (tester) async {
    final clock = _FakeClock(DateTime(2026, 11, 12, 12, 0, 0));
    var builds = 0;

    await tester.pumpWidget(
      _host(
        clock: clock,
        nextChange: (now) => const Duration(seconds: 30),
        builder: (context, now) {
          builds++;
          return Text('$now', textDirection: TextDirection.ltr);
        },
      ),
    );
    expect(builds, 1);
    expect(find.text('2026-11-12 12:00:00.000'), findsOneWidget);

    // 아직 안 됐으면 그대로다.
    clock.advance(const Duration(seconds: 29));
    await tester.pump(const Duration(seconds: 29));
    expect(builds, 1);

    clock.advance(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(builds, 2);
    expect(find.text('2026-11-12 12:00:30.000'), findsOneWidget);
  });

  testWidgets('깨어난 자리에서 다음 간격을 다시 묻는다(고정 주기가 아니다)', (tester) async {
    final clock = _FakeClock(DateTime(2026, 11, 12, 12, 0, 0));
    final asked = <DateTime>[];

    await tester.pumpWidget(
      _host(
        clock: clock,
        nextChange: (now) {
          asked.add(now);
          // 한 번은 10초, 그다음은 1시간 — 잦기가 그때그때 달라진다.
          return asked.length == 1
              ? const Duration(seconds: 10)
              : const Duration(hours: 1);
        },
        builder: (context, now) => const SizedBox.shrink(),
      ),
    );
    expect(asked, [DateTime(2026, 11, 12, 12, 0, 0)]);

    clock.advance(const Duration(seconds: 10));
    await tester.pump(const Duration(seconds: 10));
    expect(asked, [
      DateTime(2026, 11, 12, 12, 0, 0),
      DateTime(2026, 11, 12, 12, 0, 10),
    ]);

    // 두 번째 답은 1시간이므로 10초를 더 보내도 아무 일이 없다.
    clock.advance(const Duration(seconds: 10));
    await tester.pump(const Duration(seconds: 10));
    expect(asked, hasLength(2));
  });

  testWidgets('null이면 타이머를 아예 두지 않는다', (tester) async {
    final clock = _FakeClock(DateTime(2026, 11, 12, 12, 0, 0));
    var builds = 0;

    // 타이머가 걸렸다면 테스트가 끝날 때 "A Timer is still pending"으로 깨진다.
    await tester.pumpWidget(
      _host(
        clock: clock,
        nextChange: (now) => null,
        builder: (context, now) {
          builds++;
          return const SizedBox.shrink();
        },
      ),
    );

    clock.advance(const Duration(days: 1));
    await tester.pump(const Duration(days: 1));
    expect(builds, 1);
  });

  testWidgets('뒤로 가면 깨지 않고, 돌아오는 순간 다시 그린다', (tester) async {
    final clock = _FakeClock(DateTime(2026, 11, 12, 12, 0, 0));
    var builds = 0;

    await tester.pumpWidget(
      _host(
        clock: clock,
        nextChange: (now) => const Duration(seconds: 30),
        builder: (context, now) {
          builds++;
          return Text('$now', textDirection: TextDirection.ltr);
        },
      ),
    );
    expect(builds, 1);

    await _lifecycle(tester, [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]);

    // 뒤로 간 동안은 시간이 한참 흘러도 깨지 않는다.
    clock.advance(const Duration(hours: 3));
    await tester.pump(const Duration(hours: 3));
    expect(builds, 1);

    // 돌아오는 순간 한 번 다시 그린다 — **신고된 증상의 직접적인 해결이 이것이다.**
    await _lifecycle(tester, [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]);
    expect(builds, 2);
    expect(find.text('2026-11-12 15:00:00.000'), findsOneWidget);
  });

  testWidgets('화면이 사라질 때 타이머를 거둔다', (tester) async {
    final clock = _FakeClock(DateTime(2026, 11, 12, 12, 0, 0));

    await tester.pumpWidget(
      _host(
        clock: clock,
        nextChange: (now) => const Duration(hours: 1),
        builder: (context, now) => const SizedBox.shrink(),
      ),
    );

    // 치운다. dispose가 거두지 않으면 "A Timer is still pending"으로 깨진다.
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pumpAndSettle();
  });
}

Future<void> _lifecycle(WidgetTester tester, List<AppLifecycleState> states) async {
  for (final state in states) {
    tester.binding.handleAppLifecycleStateChanged(state);
    await tester.pump();
  }
}

Widget _host({
  required _FakeClock clock,
  required Duration? Function(DateTime now) nextChange,
  required Widget Function(BuildContext context, DateTime now) builder,
}) {
  return MaterialApp(
    home: TimeTicker(now: clock.now, nextChange: nextChange, builder: builder),
  );
}

class _FakeClock {
  _FakeClock(this._now);

  DateTime _now;

  DateTime now() => _now;

  void advance(Duration by) => _now = _now.add(by);
}
