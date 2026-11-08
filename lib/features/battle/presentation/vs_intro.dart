import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/strings.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/theme/depth_border.dart';
import '../../../core/widgets/initial_badge.dart';
import '../../../core/widgets/keep_words_text.dart';
import '../data/vs_intro_seen_store.dart';
import '../domain/vs_intro_rules.dart';

/// VS 인트로 연출 구간(redesign design 6.3). 총 1500ms, 구간마다 연속 곡선으로 보간한다.
/// 띠와 명판 구간은 150–200ms에서 겹친다(띠가 거의 다 열렸을 때 명판이 들어오기 시작한다).
class VsIntroTimeline {
  VsIntroTimeline._();

  static const totalMs = 1500;

  /// 가운데 ink 띠가 높이 0 → 최대(easeOutCubic).
  static const bandOpen = (start: 0, end: 200);

  /// 상대 명판은 오른쪽 밖에서, 내 명판은 왼쪽 밖에서 제자리로(easeOutCubic).
  static const slide = (start: 150, end: 550);

  /// "VS"가 1.6배 → 1배 + 투명도 0 → 1(easeOutBack — 넘침 작게).
  static const versus = (start: 550, end: 750);

  /// 띠가 앰버로 한 번(100ms, 1회) 바뀌었다 돌아옴 — 부딪히는 순간. 광과민 기준 초당 3회 미만. 즉시 전환.
  static const flash = (start: 750, end: 850);

  /// 이름을 읽는 시간(정지).
  static const hold = (start: 850, end: 1300);

  /// 전체가 배경색으로 덮이며 사라짐(easeOutCubic).
  static const fade = (start: 1300, end: 1500);

  static const segments = [bandOpen, slide, versus, flash, hold, fade];

  /// "VS"가 나타날 때의 배율.
  static const versusStartScale = 1.6;

  /// 애니메이션 줄이기일 때 처음부터 보여 주는 완성 화면 시각.
  static const stillFrameMs = 1300;

  /// 컨트롤러가 멈춰도 인트로가 화면을 붙잡지 않도록 강제로 닫는 시간.
  static const safetyTimeout = Duration(seconds: 3);
}

/// 어떤 시각의 연출 상태. 위젯은 이 값만 그린다.
@immutable
class VsIntroFrame {
  const VsIntroFrame({
    required this.band,
    required this.slide,
    required this.versusScale,
    required this.versusOpacity,
    required this.flash,
    required this.cover,
  });

  factory VsIntroFrame.at(int ms) {
    final t = ms.clamp(0, VsIntroTimeline.totalMs);
    // 구간 안 진행률(0~1)에 곡선을 입힌 값.
    double progress(({int start, int end}) segment, Curve curve) {
      final linear = ((t - segment.start) / (segment.end - segment.start)).clamp(0.0, 1.0);
      return curve.transform(linear);
    }

    final versusShown = t >= VsIntroTimeline.versus.start;
    final versus = progress(VsIntroTimeline.versus, Curves.easeOutBack);
    return VsIntroFrame(
      band: progress(VsIntroTimeline.bandOpen, Curves.easeOutCubic),
      slide: progress(VsIntroTimeline.slide, Curves.easeOutCubic),
      versusScale: versusShown
          ? VsIntroTimeline.versusStartScale - (VsIntroTimeline.versusStartScale - 1) * versus
          : null,
      versusOpacity: versusShown ? versus.clamp(0.0, 1.0) : 0,
      flash: t >= VsIntroTimeline.flash.start && t < VsIntroTimeline.flash.end,
      cover: progress(VsIntroTimeline.fade, Curves.easeOutCubic),
    );
  }

  /// 띠 높이 비율(0~1).
  final double band;

  /// 명판이 제자리에 온 정도(0 = 화면 밖, 1 = 제자리).
  final double slide;

  /// "VS" 배율. null이면 아직 안 보인다. easeOutBack이라 끝나기 직전 1보다 조금 작아졌다 돌아온다.
  final double? versusScale;

  /// "VS" 투명도(0~1).
  final double versusOpacity;

  /// 띠가 앰버로 바뀐 순간.
  final bool flash;

  /// 배경색으로 덮인 정도(0~1).
  final double cover;
}

/// 표시 여부 판단 → 기록 → 인트로 순서(design.md 4.5). 어느 단계에서 실패해도 인트로만 건너뛴다.
///
/// "봤음"은 표시를 시작하는 순간 기록한다. 인트로 도중 앱이 죽거나 건너뛰어도 다시 뜨지 않게 하기 위함이다.
Future<void> maybeShowVsIntro(
  BuildContext context, {
  required VsIntroSeenStore store,
  required String userId,
  required String battleId,
  required String status,
  required String myName,
  required String opponentName,
}) async {
  if (!shouldShowVsIntro(status: status, alreadySeen: false)) return;
  try {
    final seen = await store.hasSeen(userId, battleId);
    if (!shouldShowVsIntro(status: status, alreadySeen: seen)) return;
    await store.markSeen(userId, battleId);
  } catch (e) {
    // 장식 연출의 실패는 로그만 남긴다(토스트 없음, design.md 4.2). 대결 진입은 막지 않는다.
    debugPrint('vsIntroSeenStore failed: $e');
    return;
  }
  if (!context.mounted) return;
  await showVsIntro(context, myName: myName, opponentName: opponentName);
}

/// 전체 화면 불투명 route로 인트로를 띄우고 닫힐 때까지 기다린다. 예외는 모두 삼키고 로그만 남긴다.
/// Scaffold를 쓰지 않으므로 토스트가 인트로 위에 붙지 않는다.
Future<void> showVsIntro(
  BuildContext context, {
  required String myName,
  required String opponentName,
}) async {
  try {
    await Navigator.of(context).push<void>(
      PageRouteBuilder<void>(
        opaque: true,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (context, _, _) => VsIntro(myName: myName, opponentName: opponentName),
      ),
    );
  } catch (e) {
    // 장식 연출의 실패는 로그만 남긴다(토스트 없음, design.md 4.5). 호출자는 다음 동작을 이어 간다.
    debugPrint('showVsIntro failed: $e');
  }
}

/// 양쪽 이름·이니셜이 맞붙으며 "VS"가 뜨는 1.5초 연출. 캐릭터·사진·효과음·진동 없음.
/// 어디를 눌러도, 뒤로 가기를 해도 즉시 닫힌다. 애니메이션 줄이기면 완성 화면이 정지 상태로 보인다.
class VsIntro extends StatefulWidget {
  const VsIntro({super.key, required this.myName, required this.opponentName});

  final String myName;
  final String opponentName;

  @override
  State<VsIntro> createState() => _VsIntroState();
}

class _VsIntroState extends State<VsIntro> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: VsIntroTimeline.totalMs),
  );
  Timer? _closeTimer;
  Timer? _safetyTimer;
  bool _started = false;
  bool _still = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _still = MediaQuery.disableAnimationsOf(context);
    if (_still) {
      _closeTimer = Timer(const Duration(milliseconds: VsIntroTimeline.totalMs), _close);
    } else {
      _controller.forward().then((_) => _close());
    }
    _safetyTimer = Timer(VsIntroTimeline.safetyTimeout, _close);
  }

  @override
  void dispose() {
    _closeTimer?.cancel();
    _safetyTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// 이미 사용자가 닫았으면(최상단이 아니면) 아무것도 하지 않는다.
  void _close() {
    if (!mounted) return;
    final route = ModalRoute.of(context);
    if (route == null || !route.isCurrent) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppPalette.background,
      child: Semantics(
        container: true,
        liveRegion: true,
        label: AppStrings.vsIntroSemantics(widget.myName, widget.opponentName),
        child: ExcludeSemantics(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _close,
            child: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) => AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) => _buildFrame(context, constraints),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFrame(BuildContext context, BoxConstraints constraints) {
    final frame = _still
        ? VsIntroFrame.at(VsIntroTimeline.stillFrameMs)
        : VsIntroFrame.at((_controller.value * VsIntroTimeline.totalMs).round());
    // 가로 모드·작은 화면에서는 칸을 줄여 명판이 넘치지 않게 한다(design 6.2).
    final compact = constraints.maxHeight < 520;
    final badge = compact ? 48.0 : 72.0;
    final bandHeight = compact ? 64.0 : 96.0;
    final versusSize = compact ? 44.0 : 64.0;
    final offscreen = (1 - frame.slide) * constraints.maxWidth;
    final label = Theme.of(context).textTheme.labelMedium?.copyWith(color: AppPalette.inkMuted);
    // 자리 이름("상대"/"나")은 명판 이름이 그 말과 같으면 숨긴다. 내 이름 조회가 실패하면 이름 자리에 "나"를 대신 쓰는데
    // (CLAUDE.md 예외), 그때 이니셜·이름·자리 이름이 모두 "나"로 세 번 나왔다(redesign 후속 결정 7).
    final showOpponentLabel = widget.opponentName != AppStrings.battleOpponent;
    final showMeLabel = widget.myName != AppStrings.battleMe;

    return Stack(
      children: [
        Center(
          child: SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showOpponentLabel) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: KeepWordsText(AppStrings.battleOpponent, style: label),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                Transform.translate(
                  offset: Offset(offscreen, 0),
                  child: _Nameplate(
                    name: widget.opponentName,
                    fill: AppPalette.secondary,
                    badgeFirst: false,
                    badge: badge,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: bandHeight,
                  width: double.infinity,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        height: bandHeight * frame.band,
                        width: double.infinity,
                        child: ColoredBox(
                          color: frame.flash ? AppPalette.amber : AppPalette.ink,
                        ),
                      ),
                      if (frame.versusScale != null)
                        Opacity(
                          opacity: frame.versusOpacity,
                          child: Transform.scale(
                            scale: frame.versusScale!,
                            child: SizedBox(
                              height: bandHeight,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: KeepWordsText(
                                  AppStrings.vsIntroVersus,
                                  style: TextStyle(
                                    fontFamily: AppText.family,
                                    fontSize: versusSize,
                                    fontWeight: FontWeight.w800,
                                    height: 1.2,
                                    letterSpacing: 0,
                                    color: AppPalette.surface,
                                    // 흐림 0의 단단한 아래 그림자(design 6.2) — 버튼 두께와 같은 언어.
                                    shadows: const [
                                      Shadow(color: AppPalette.amber, offset: Offset(0, 4)),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Transform.translate(
                  offset: Offset(-offscreen, 0),
                  child: _Nameplate(
                    name: widget.myName,
                    fill: AppPalette.primary,
                    badgeFirst: true,
                    badge: badge,
                  ),
                ),
                if (showMeLabel) ...[
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: KeepWordsText(AppStrings.battleMe, style: label),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (frame.cover > 0)
          Positioned.fill(
            child: IgnorePointer(
              child: ColoredBox(color: AppPalette.background.withValues(alpha: frame.cover)),
            ),
          ),
      ],
    );
  }
}

/// 이름 명판(design 6.2). 흰 면·모서리 20·1dp line·4dp ink 두께 + 이니셜 칸 + 이름(titleMedium, 최대 2줄 말줄임).
class _Nameplate extends StatelessWidget {
  const _Nameplate({
    required this.name,
    required this.fill,
    required this.badgeFirst,
    required this.badge,
  });

  final String name;
  final Color fill;
  final bool badgeFirst;
  final double badge;

  @override
  Widget build(BuildContext context) {
    final initial = InitialBadge(
      name: name,
      fill: fill,
      size: InitialBadgeSize.intro,
      dimension: badge,
    );
    final text = Expanded(
      child: KeepWordsText(
        name,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: badgeFirst ? TextAlign.left : TextAlign.right,
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: const ShapeDecoration(
          color: AppPalette.surface,
          shape: DepthBorder(
            side: BorderSide(color: AppPalette.line),
            radius: 20,
            depth: 4,
            depthColor: AppPalette.ink,
          ),
        ),
        child: Row(
          children: badgeFirst
              ? [initial, const SizedBox(width: 12), text]
              : [text, const SizedBox(width: 12), initial],
        ),
      ),
    );
  }
}
