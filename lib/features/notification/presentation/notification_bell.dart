import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/strings.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_palette.dart';
import '../domain/notification_providers.dart';
import 'notification_inbox_screen.dart';

/// 알림함 입구. **네 탭 앱바가 모두 이 위젯 하나를 쓴다**(`actions: const [NotificationBell()]`).
///
/// 오너가 "네 탭 앱바 전부"를 골랐으므로(spec 결정 4) 같은 것을 네 벌 관리하지 않으려고 위젯을
/// 하나로 둔다. 값도 provider 하나를 보기 때문에 네 자리의 배지가 어긋날 수 없다.
///
/// 할 일 탭·프로필 탭에 대결 배지가 뜨는 어긋남은 이렇게 받아들인다: 종 아이콘은 **탭의 내용과
/// 무관한 "앱 전체의 알림함 입구"**이고, 그 입구는 네 탭에서 같은 자리·같은 모양이다. 어떤 탭에서는
/// 숨는 쪽이 오히려 "이 배지가 무엇에 대한 것인지"를 흔든다.
class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key});

  /// 점 하나의 지름. 알림함 줄의 "새 알림 점"과 **같은 크기·같은 색**이어야 같은 뜻으로 읽힌다.
  static const dotSize = 8.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 배지 조회 실패는 `debugPrint`만 남긴다(CLAUDE.md "에러는 삼키지 않는다"의 예외) —
    // 관문이 아니고, 탭을 오가거나 앱을 다시 열면 저절로 맞는다.
    //
    // **`build` 안에서 찍지 않는다**(2026-11-13 리뷰). 실패 상태가 유지되는 동안 리빌드마다
    // 같은 줄이 찍히고, 종이 네 탭에 있어 한 번의 실패가 최소 네 줄이 된다 — 로그 노이즈가
    // 진짜 실패를 덮는다. `listen`은 값이 **바뀔 때만** 부른다.
    ref.listen(hasNewNotificationsProvider, (previous, next) {
      final error = next.error;
      if (error != null) debugPrint('hasNewNotificationsProvider error: $error');
    });

    final hasNewAsync = ref.watch(hasNewNotificationsProvider);
    // 실패에서는 점을 그리지 않는다. 잘못된 안내를 띄우지 않는 쪽을 택한 선례와 같고
    // (프로필의 "알림이 꺼져 있어요"가 조회 실패 시 표시하지 않는다) 사용자가 할 수 있는 일이 없다.
    //
    // **다시 읽는 중(`isLoading`)에는 점을 끄지 않는다**(2026-11-13 리뷰). 탭 전환·앱 재개마다
    // 이 provider를 `invalidate`하는데, 재조회 상태는 **이전 값을 든 `AsyncLoading`**이라
    // `isLoading`으로 끄면 탭을 옮길 때마다 점이 깜빡이고 느린 망에서는 "사라졌다"로 읽힌다.
    // 첫 로딩에서 점이 없어야 한다는 요구는 `value`가 아직 null인 것으로 이미 충족된다.
    final hasNew = !hasNewAsync.hasError && (hasNewAsync.value ?? false);

    final icon = Badge(
      // 라벨 없음 = 점 하나. 숫자 배지를 만들지 않는다(spec 결정 3).
      // danger를 쓰지 않는 이유: 이 앱의 danger는 포기·삭제처럼 되돌릴 수 없는 동작의 색이고
      // 새 알림은 위험이 아니다.
      backgroundColor: AppPalette.primary,
      smallSize: dotSize,
      isLabelVisible: hasNew,
      child: const Icon(AppIcons.bell, size: 24),
    );

    return IconButton(
      tooltip: AppStrings.notificationInboxTitle,
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const NotificationInboxScreen()),
      ),
      // 점은 색만으로 전달되면 안 된다. 새 알림이 있을 때만 라벨을 덧붙인다.
      icon: hasNew
          ? Semantics(label: AppStrings.notificationNewSemantics, child: icon)
          : icon,
    );
  }
}
