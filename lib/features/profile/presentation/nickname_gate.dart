import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_loader.dart';
import '../domain/nickname_rules.dart';
import '../domain/profile_providers.dart';
import 'nickname_setup_screen.dart';

/// 로그인 직후, 본 화면 앞의 별명 관문(design 7.1).
///
/// - 확정하지 않았으면 별명 정하기 화면, 확정했으면 [child](본 화면).
/// - **조회가 실패하면 [child]로 통과시킨다**(오너 결정 1의 (a)). 관문은 보안 장치가 아니다 — 실명 노출은
///   서버의 기본 별명과 일괄 덮기가 이미 끊었다. 미확정 사용자는 다음 실행에 다시 본다.
/// - **한 번 [child]로 보냈으면 이 위젯이 사는 동안 되돌리지 않는다(래치).** 그 뒤로는 상태를 watch하지
///   않으므로, 나중에 상태가 "미확정"으로 읽혀도 본 화면에서 관문으로 끌려 나가지 않는다.
///   로그아웃하면 `AuthGate`가 이 위젯을 걷어 내고, 다른 계정은 다른 키로 새로 만든다.
///
/// [child]를 받는 이유는 테스트가 `MainShell` 없이 관문만 돌릴 수 있게 하려는 것이다.
class NicknameGate extends ConsumerStatefulWidget {
  const NicknameGate({super.key, required this.userId, required this.child});

  final String userId;
  final Widget child;

  @override
  ConsumerState<NicknameGate> createState() => _NicknameGateState();
}

class _NicknameGateState extends ConsumerState<NicknameGate> {
  bool _passed = false;

  @override
  void didUpdateWidget(covariant NicknameGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 같은 자리에 다른 계정이 들어오면 래치를 푼다(AuthGate가 키로 나누지만 한 겹 더).
    if (oldWidget.userId != widget.userId) _passed = false;
  }

  @override
  Widget build(BuildContext context) {
    if (_passed) return widget.child;

    final state = ref.watch(myNicknameStateProvider(widget.userId));
    switch (nicknameGateView(state)) {
      case NicknameGateView.loading:
        // AuthGate의 세션 복구 로더와 같은 모양이라 두 단계가 한 화면처럼 이어진다.
        return const Scaffold(body: Center(child: AppLoader.medium()));
      case NicknameGateView.setup:
        return NicknameSetupScreen(userId: widget.userId, state: state.requireValue);
      case NicknameGateView.shell:
        // 조회 실패는 통과다. 관문이 아니므로 토스트를 띄우지 않고 로그만 남긴다(CLAUDE.md 예외 —
        // 사용자가 할 수 있는 일이 없고, 다음 실행에서 저절로 다시 묻는다).
        if (state.hasError) debugPrint('getMyNicknameState failed: ${state.error}');
        // build 안에서 값을 바꾸지만 다시 그릴 필요가 없다 — 이번 build가 이미 child를 돌려준다.
        _passed = true;
        return widget.child;
    }
  }
}
