import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/push/push_messaging.dart';
import '../../../core/push/push_providers.dart';
import '../../../core/strings.dart';
import '../../../core/widgets/pixel_frame.dart';

/// 알림이 꺼져 있을 때만 보이는 안내 한 칸.
///
/// 앱 안에 알림 on/off 스위치를 두지 않는다 — 켜고 끄는 주인은 OS이고, 두 곳에 상태를 두면
/// 어긋난다(design 결정 4). 기기 설정으로 바로 보내는 버튼도 두지 않는다(새 패키지가 필요해지고
/// 안내 문구만으로 목적이 달성된다).
///
/// 조회 중·켜져 있음·조회 실패에는 아무것도 그리지 않는다. 틀린 안내를 띄우지 않는 쪽을 택했다.
class NotificationSection extends ConsumerWidget {
  const NotificationSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permissionAsync = ref.watch(notificationPermissionProvider);

    return permissionAsync.when(
      data: (permission) {
        if (permission != NotificationPermission.denied) return const SizedBox.shrink();
        // 보일 때만 아래 여백을 갖는다 — 숨은 상태에서 빈 칸이 남지 않게 섹션이 직접 들고 있다.
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: PixelFrame.flat(
            title: AppStrings.notificationSection,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppStrings.notificationDisabled,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  AppStrings.notificationDisabledGuide,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (error, stackTrace) {
        debugPrint('notificationPermissionProvider error: $error');
        return const SizedBox.shrink();
      },
    );
  }
}
