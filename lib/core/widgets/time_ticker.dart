import 'dart:async';

import 'package:flutter/material.dart';

/// 남은 시간처럼 **시간이 흐르는 것만으로 달라지는 화면**을, 글자가 실제로 달라지는 때에 맞춰
/// 다시 그린다.
///
/// 2026-11-12에 생겼다. 그전까지 남은 시간은 "화면을 그릴 때 다시 계산한다"였고, 그 전제가
/// 틀렸다 — `MainShell`의 IndexedStack과 살아 있는 화면 스택 때문에 탭을 오가도, 앱을 뒤로
/// 보냈다 다시 열어도 화면이 다시 그려지지 않는다. 그래서 문구가 첫 build 때 읽은 "지금"에
/// 멈춰 있었다(오너가 실기기에서 신고). 투두 목록과 대결 화면이 같은 증상이었다.
///
/// **고정 주기 타이머를 쓰지 않는다.** [nextChange]가 "다음에 글자가 달라지는 때"를 알고 있으므로
/// 거기에 맞춰 한 번만 깨고, 깨어난 자리에서 다시 계산해 새로 건다. 깨어나는 잦기가 문구의
/// 끝자리를 그대로 따라간다 — 사흘 뒤 마감이면 한 시간에 한 번, 한 시간 뒤면 1분에 한 번,
/// 1분 미만이면 1초에 한 번이다. 고정 주기는 둘 중 하나를 꼭 틀린다: 1분 주기는 마지막 1분을
/// 멈춘 것처럼 보이게 하고, 1초 주기는 하루 종일 똑같은 글자를 다시 그린다.
///
/// 네트워크·DB 호출은 이 경로에 **하나도 없다.** 마감은 이미 받아 둔 고정된 시각이고 바뀌는
/// 것은 글자뿐이다.
///
/// [nextChange]가 null을 주면 타이머를 아예 걸지 않는다 — 말할 마감이 없거나(기한 없는 할 일만
/// 있는 목록) 이미 다 지나 더 바뀔 것이 없다는 뜻이다. 간격을 재는 쪽은 문구 규칙을 아는 순수
/// 함수들이다: `nextDeadlineTick`(대결), `nextDueLabelChange`(투두).
///
/// 앱이 뒤로 가면 타이머를 거두고 **돌아오는 순간 한 번 다시 그린다.** 신고된 증상의 직접적인
/// 해결은 이쪽이다 — 세 시간 뒤에 앱을 열어도 그 자리에서 맞는 값이 뜬다.
class TimeTicker extends StatefulWidget {
  const TimeTicker({
    super.key,
    required this.nextChange,
    required this.builder,
    this.now = DateTime.now,
  });

  /// 다음에 다시 그릴 때까지의 간격. null이면 더 그릴 일이 없다.
  final Duration? Function(DateTime now) nextChange;

  /// 아래 화면. [now]를 함께 받아 **한 화면의 모든 줄이 같은 "지금"을 보게** 한다(경계에서 두
  /// 줄이 어긋나지 않는다).
  final Widget Function(BuildContext context, DateTime now) builder;

  /// 읽는 "지금". 테스트에서 손으로 돌리는 자리다(앱에서는 늘 `DateTime.now`).
  final DateTime Function() now;

  @override
  State<TimeTicker> createState() => _TimeTickerState();
}

class _TimeTickerState extends State<TimeTicker> {
  Timer? _tick;

  /// 앱이 지금 화면에 있는지. 뒤로 보내면 타이머를 끄고, 돌아오면 그 자리에서 다시 읽는다.
  bool _resumed = true;

  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) {
        _resumed = state == AppLifecycleState.resumed;
        if (!_resumed) {
          _tick?.cancel();
          _tick = null;
        } else if (mounted) {
          setState(() {});
        }
      },
    );
  }

  @override
  void dispose() {
    _tick?.cancel();
    _lifecycle.dispose();
    super.dispose();
  }

  void _arm(Duration? delay) {
    _tick?.cancel();
    _tick = null;
    if (delay == null || !_resumed) return;
    _tick = Timer(delay, () {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final now = widget.now();
    // build 안에서 거는 까닭: 다음에 깰 시각은 **지금 그리는 내용**에서만 나온다. 멱등하고
    // (취소하고 다시 건다) setState를 부르지 않으므로 build가 몇 번 불려도 안전하다.
    _arm(widget.nextChange(now));
    return widget.builder(context, now);
  }
}
