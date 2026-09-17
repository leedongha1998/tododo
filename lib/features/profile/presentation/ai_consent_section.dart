import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/strings.dart';
import '../../../core/widgets/pixel_frame.dart';
import '../../../core/widgets/pixel_loader.dart';
import '../../../core/widgets/retro_button_styles.dart';
import '../../battle/data/ai_consent.dart';
import '../../battle/domain/ai_consent_providers.dart';
import '../../battle/domain/ai_consent_rules.dart';
import '../../battle/domain/battle_providers.dart';
import '../../battle/presentation/ai_consent_screen.dart';
import '../domain/profile_providers.dart';

/// 프로필의 AI 데이터 제공 동의 섹션(design.md 화면 2). 상태 확인, 동의하기, 동의 철회.
class AiConsentSection extends ConsumerStatefulWidget {
  const AiConsentSection({super.key});

  @override
  ConsumerState<AiConsentSection> createState() => _AiConsentSectionState();
}

class _AiConsentSectionState extends ConsumerState<AiConsentSection> {
  bool _withdrawing = false;

  Future<void> _give() async {
    // 동의 화면이 저장과 상태 갱신까지 하고 닫힌다.
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const AiConsentScreen()),
    );
  }

  Future<void> _withdraw() async {
    final repo = ref.read(aiConsentRepositoryProvider);
    // 대화상자가 다시 그려져도 조회를 한 번만 하도록 열기 전에 만든다.
    final impactFuture = repo.fetchWithdrawalImpact();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _WithdrawConsentDialog(impact: impactFuture),
    );
    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _withdrawing = true);
    try {
      await repo.withdrawConsent();
      // 진행 중 대결은 포기로, 모집은 취소로 끝났으므로 대결 목록과 전적도 다시 읽는다.
      ref.invalidate(myAiConsentProvider);
      ref.invalidate(myBattlesProvider);
      ref.invalidate(myRecruitsProvider);
      ref.invalidate(openRecruitsProvider);
      ref.invalidate(battleRecordsProvider);
      // 철회는 진행 중 대결을 포기(-3)로 끝내므로 점수도 함께 바뀐다.
      ref.invalidate(myPlayerStatsProvider);
      messenger.showSnackBar(const SnackBar(content: Text(AppStrings.aiConsentWithdrawDone)));
    } catch (e) {
      debugPrint('withdrawConsent failed: $e');
      messenger.showSnackBar(const SnackBar(content: Text(AppStrings.aiConsentWithdrawFailed)));
    } finally {
      if (mounted) setState(() => _withdrawing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final consentAsync = ref.watch(myAiConsentProvider);

    return PixelFrame.flat(
      title: AppStrings.aiConsentSection,
      child: consentAsync.when(
        data: (consent) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              consent == null
                  ? AppStrings.aiConsentStatusNotGiven
                  : AppStrings.aiConsentStatusGiven(_formatDate(consent)),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            if (consent == null)
              FilledButton(onPressed: _give, child: const Text(AppStrings.aiConsentGive))
            else
              FilledButton(
                style: RetroButtonStyles.danger,
                onPressed: _withdrawing ? null : _withdraw,
                child: _withdrawing
                    ? const PixelLoader.small()
                    : const Text(AppStrings.aiConsentWithdraw),
              ),
          ],
        ),
        loading: () => const Center(child: PixelLoader.medium()),
        error: (error, stackTrace) {
          debugPrint('myAiConsentProvider error: $error');
          return const Text(AppStrings.aiConsentLoadFailed);
        },
      ),
    );
  }
}

String _formatDate(AiConsent consent) {
  final local = consent.consentedAt.toLocal();
  return '${local.year}년 ${local.month}월 ${local.day}일';
}

/// 철회 확인. 서버에서 처리될 대결 수를 받아 온 뒤에야 확인 버튼을 누를 수 있다.
class _WithdrawConsentDialog extends StatelessWidget {
  const _WithdrawConsentDialog({required this.impact});

  final Future<ConsentWithdrawalImpact> impact;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ConsentWithdrawalImpact>(
      future: impact,
      builder: (context, snapshot) {
        final Widget content;
        if (snapshot.hasError) {
          debugPrint('fetchWithdrawalImpact failed: ${snapshot.error}');
          content = const Text(AppStrings.aiConsentWithdrawImpactFailed);
        } else if (!snapshot.hasData) {
          content = const Align(alignment: Alignment.centerLeft, child: PixelLoader.small());
        } else {
          content = Text(consentWithdrawalMessage(snapshot.data!));
        }

        return AlertDialog(
          title: const Text(AppStrings.aiConsentWithdrawConfirmTitle),
          content: content,
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text(AppStrings.cancel),
            ),
            FilledButton(
              style: RetroButtonStyles.danger,
              onPressed: snapshot.hasData ? () => Navigator.of(context).pop(true) : null,
              child: const Text(AppStrings.aiConsentWithdrawConfirm),
            ),
          ],
        );
      },
    );
  }
}
