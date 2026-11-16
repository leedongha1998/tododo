import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/strings.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/app_loader.dart';
import '../../../core/widgets/app_panel.dart';
import '../../../core/widgets/keep_words_text.dart';
import '../../../core/widgets/status_message.dart';
import '../../battle/domain/battle_providers.dart';
import '../../battle/presentation/battle_detail_screen.dart';
import '../data/notification_inbox.dart';
import '../data/notification_item.dart';
import '../domain/notification_line.dart';
import '../domain/notification_providers.dart';

/// 앱 안 알림함. 서버 원장에 남은 **내 몫의 대결 알림 사건**을 최신순으로 모아 보여 준다.
///
/// 이 화면은 **읽기 전용 거울**이다. 할 수 있는 일은 "읽는다"와 "그 대결로 간다" 둘뿐이고,
/// 판정·제출·포기·삭제로 가는 길이 없다(spec 범위 밖). 알림함을 보지 않아도 대결 진행·판정·결과는
/// 완전히 똑같다 — 관문이 아니다.
///
/// **지금 상태의 정답은 언제나 대결 상세다.** 그래서 줄은 "그때 일어난 일"만 적고 지금 기준으로
/// 계산되는 값(남은 시간)이나 촉구 문장을 말하지 않는다(design 원칙 4).
class NotificationInboxScreen extends ConsumerStatefulWidget {
  const NotificationInboxScreen({super.key});

  @override
  ConsumerState<NotificationInboxScreen> createState() => _NotificationInboxScreenState();
}

class _NotificationInboxScreenState extends ConsumerState<NotificationInboxScreen> {
  /// 화면을 **처음 열었을 때** 서버가 준 "마지막으로 본 시각" 스냅샷. 목록이 다시 읽혀도 이
  /// 기준을 바꾸지 않는다 — 그래야 알림함을 보고 있는 동안 새 알림 표시가 눈앞에서 사라지지
  /// 않는다(design 5.2). null이면 한 번도 열지 않은 사용자이고 전부 새 알림이다.
  DateTime? _seenAtAtOpen;

  /// 읽음을 찍었는가. **한 번만 찍는다**(목록이 다시 읽혀도 다시 찍지 않는다). 그래서 알림함을
  /// 보고 있는 동안 도착한 알림은 다음에 다시 새 알림으로 보인다 — 조금 어색하지만
  /// "보여 준 적 없는 것을 읽음으로 만들지 않는다"가 더 중요하다.
  bool _marked = false;

  /// **첫 성공 로드에서만** 기준 시각을 붙잡고 읽음을 찍는다.
  ///
  /// 조회가 실패했을 때 찍지 않는 이유: 그 상태에서 사용자는 아무것도 보지 못했는데 읽음을
  /// 찍으면 **보지 못한 알림이 읽은 것이 된다.** 화면 진입만으로 찍지 않는 까닭이다.
  ///
  /// `setState`를 쓰지 않고 build 안에서 부른다. 같은 provider를 `watch`하고 있으므로 값이
  /// 바뀌면 Riverpod이 다시 그리고, 그 build가 여기서 붙잡은 값을 바로 읽는다.
  /// (`ref.listen(fireImmediately:)`를 쓰지 않는 이유: riverpod 3의 `WidgetRef.listen`에는 그
  /// 인자가 없어 **이미 data인 provider에 붙이면 콜백이 한 번도 불리지 않는다** — 화면을 닫았다
  /// 바로 다시 열면 캐시가 살아 있을 수 있어 그 경로에서 읽음이 찍히지 않게 된다.)
  void _captureSeenAt(AsyncValue<NotificationInbox> value) {
    if (_marked) return;
    // AsyncError는 직전 값을 그대로 들고 있으므로 value만 보면 실패한 상태에서도 찍게 된다.
    if (value.isLoading || value.hasError) return;
    final inbox = value.value;
    if (inbox == null) return;

    _marked = true;
    _seenAtAtOpen = inbox.seenAt;
    unawaited(_markSeen());
  }

  /// 읽음 찍기 실패는 `debugPrint`만 남긴다(CLAUDE.md "에러는 삼키지 않는다"의 예외).
  /// 사용자가 할 수 있는 일이 없고(다시 누를 버튼이 없다), 다음에 알림함을 열면 저절로 맞고,
  /// 실패해도 목록은 이미 보이고 있어 기능이 막히지 않는다.
  Future<void> _markSeen() async {
    try {
      await ref.read(notificationRepositoryProvider).markSeen();
    } catch (error) {
      debugPrint('mark_notifications_seen failed: $error');
      return;
    }
    if (!mounted) return;
    // 점이 사라지는 순간이다.
    ref.invalidate(hasNewNotificationsProvider);
  }

  /// 푸시를 탭했을 때와 **같은 곳·같은 관문**이다 — 열 수 있는지 서버에 먼저 묻고, 안 되면
  /// 오류 화면을 띄우지 않는다.
  ///
  /// 푸시 경로(`MainShell._openPendingBattle`)와 **다른 것 하나**: 거기서는 조용히 넘어가지만
  /// (알림을 탭한 순간 사용자가 앱 안에 있다고 보장할 수 없어 토스트를 띄울 맥락이 없다)
  /// 알림함은 토스트 한 줄을 띄운다. 아무 반응이 없으면 앱이 고장 난 것으로 읽힌다(spec).
  /// 처리가 갈리므로 두 코드를 한 함수로 합치지 않는다 — 공유하는 것은 관문의 규칙이다.
  Future<void> _openBattle(String battleId) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await ref.read(battleRepositoryProvider).fetchBattle(battleId);
    } catch (error) {
      debugPrint('알림함에서 연 대결을 읽지 못했다($battleId): $error');
      // 조회가 느린 동안 사용자가 알림함을 닫았으면 띄우지 않는다(2026-11-13 리뷰).
      // `messenger`를 미리 잡아 두어 터지지는 않지만, 그대로 두면 **다른 화면 위에** 알림함의
      // 토스트가 뜬다 — 저장소의 다른 자리도 `mounted`를 보고 스낵바를 띄운다.
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: KeepWordsText(AppStrings.notificationBattleGone)),
      );
      return;
    }
    if (!mounted) return;
    await navigator.push(
      MaterialPageRoute(builder: (_) => BattleDetailScreen(battleId: battleId)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final inboxAsync = ref.watch(notificationInboxProvider);
    _captureSeenAt(inboxAsync);

    return Scaffold(
      // 이 화면에는 종 아이콘을 두지 않는다 — 이미 알림함 안이다.
      appBar: AppBar(title: const KeepWordsText(AppStrings.notificationInboxTitle)),
      body: inboxAsync.when(
        data: (inbox) {
          // 뜻을 모르는 kind는 줄을 그리지 않는다(체크 제약이 7종을 보장하므로 실제로는 없다).
          final rows = <(NotificationItem, NotificationLine)>[];
          for (final item in inbox.items) {
            final line = notificationLine(item.kind, item.payload);
            if (line != null) rows.add((item, line));
          }

          if (rows.isEmpty) {
            // 대결을 재촉하는 문구·버튼을 두지 않는다(spec).
            return const StatusMessage.empty(
              icon: AppIcons.bellOutlined,
              message: AppStrings.notificationInboxEmpty,
              fill: true,
            );
          }

          // 당겨서 새로고침을 두지 않는다 — provider가 autoDispose라 화면을 닫고 열면 새로 읽고,
          // 열어 둔 채 푸시를 받으면 포그라운드 처리가 목록을 다시 읽어 준다(design 5.2).
          return ListView.separated(
            // 화면 가장자리 20 / 항목 사이 12(redesign design 4.1).
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            itemCount: rows.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final (item, line) = rows[index];
              return NotificationTile(
                line: line,
                time: notificationTimeLabel(item.createdAt),
                isNew: item.isNewSince(_seenAtAtOpen),
                onTap: () => _openBattle(item.battleId),
              );
            },
          );
        },
        loading: () => const Center(child: AppLoader.medium()),
        error: (error, stackTrace) {
          debugPrint('notificationInboxProvider error: $error');
          // 토스트를 띄우지 않는다 — 화면이 이미 사실을 말하고 `다시 시도`로 할 일을 준다.
          return StatusMessage.error(
            message: AppStrings.notificationInboxLoadFailed,
            fill: true,
            action: TextButton(
              onPressed: () => ref.invalidate(notificationInboxProvider),
              child: const KeepWordsText(AppStrings.retry),
            ),
          );
        },
      ),
    );
  }
}

/// 알림 한 줄(카드 한 장).
///
/// **새 알림과 읽은 알림의 구분은 왼쪽 점 하나뿐이다.** 글자 굵기·배경색을 바꾸지 않는다 —
/// 앱바 배지와 **같은 기호(8dp primary 점)**를 쓰면 "그 점이 이 줄들 때문이었다"가 설명 없이
/// 이어진다. 읽은 줄에도 같은 크기의 빈 자리를 남겨 글자 왼쪽 선이 흔들리지 않게 한다.
class NotificationTile extends StatelessWidget {
  const NotificationTile({
    super.key,
    required this.line,
    required this.time,
    required this.isNew,
    required this.onTap,
  });

  static const dotSize = 8.0;

  final NotificationLine line;
  final String time;
  final bool isNew;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final mutedColor = Theme.of(context).colorScheme.onSurfaceVariant;

    return AppPanel.raised(
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: dotSize,
            height: dotSize,
            child: isNew
                ? Semantics(
                    label: AppStrings.notificationNewSemantics,
                    child: const DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppPalette.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 8),
          Icon(line.icon, size: 20, color: mutedColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                KeepWordsText(
                  line.text,
                  style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                // 대결 제목은 사용자가 입력한 문장이라 본문 글꼴로 두고 한 줄로 자른다.
                KeepWordsText(
                  line.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodyMedium?.copyWith(color: mutedColor),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          KeepWordsText(time, style: textTheme.bodySmall?.copyWith(color: mutedColor)),
        ],
      ),
    );
  }
}
