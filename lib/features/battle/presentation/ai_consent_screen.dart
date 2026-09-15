import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/app_links.dart';
import '../../../core/strings.dart';
import '../../../core/theme/pixel_icons.dart';
import '../../../core/widgets/pixel_frame.dart';
import '../../../core/widgets/pixel_icon.dart';
import '../../../core/widgets/pixel_loader.dart';
import '../data/ai_consent.dart';
import '../domain/ai_consent_providers.dart';

/// 대결을 만들거나 참가하기 전에 부른다. 이미 동의했으면 곧바로 true.
/// 아니면 동의 화면을 띄우고, 동의하지 않으면 안내 토스트 후 false.
/// 서버(`join_battle`, battles insert 정책)도 같은 검사를 다시 한다 — 이 확인은 안내용이다.
Future<bool> ensureAiConsent(BuildContext context, WidgetRef ref) async {
  final AiConsent? consent;
  try {
    consent = await ref.read(myAiConsentProvider.future);
  } catch (e) {
    debugPrint('myAiConsentProvider failed: $e');
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text(AppStrings.aiConsentLoadFailed)));
    }
    return false;
  }
  if (consent != null) return true;
  if (!context.mounted) return false;

  final agreed = await Navigator.of(context).push<bool>(
    MaterialPageRoute(builder: (_) => const AiConsentScreen()),
  );
  if (agreed == true) return true;

  if (context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text(AppStrings.aiConsentRequired)));
  }
  return false;
}

/// AI 데이터 제공 동의 화면(design.md 화면 1). 동의하면 true, 아니면 false를 돌려주며 닫힌다.
class AiConsentScreen extends ConsumerStatefulWidget {
  const AiConsentScreen({super.key});

  @override
  ConsumerState<AiConsentScreen> createState() => _AiConsentScreenState();
}

class _AiConsentScreenState extends ConsumerState<AiConsentScreen> {
  bool _submitting = false;

  Future<void> _agree() async {
    setState(() => _submitting = true);
    try {
      await ref.read(aiConsentRepositoryProvider).giveConsent();
      ref.invalidate(myAiConsentProvider);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      debugPrint('giveConsent failed: $e');
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text(AppStrings.aiConsentGiveFailed)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.aiConsentTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(AppStrings.aiConsentIntro, style: textTheme.bodyMedium),
          const SizedBox(height: 16),
          const PixelFrame.flat(
            title: AppStrings.aiConsentDetailsTitle,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ConsentItem(
                  label: AppStrings.aiConsentRecipientLabel,
                  value: AppStrings.aiConsentRecipient,
                ),
                _ConsentItem(label: AppStrings.aiConsentItemsLabel, value: AppStrings.aiConsentItems),
                _ConsentItem(
                  label: AppStrings.aiConsentPurposeLabel,
                  value: AppStrings.aiConsentPurpose,
                ),
                _ConsentItem(
                  label: AppStrings.aiConsentRetentionLabel,
                  value: AppStrings.aiConsentRetention,
                ),
                _ConsentItem(
                  label: AppStrings.aiConsentRefusalLabel,
                  value: AppStrings.aiConsentRefusal,
                  last: true,
                ),
              ],
            ),
          ),
          // 정책 문서 주소가 정해지기 전에는 링크를 보이지 않는다. 브라우저 열기 패키지가 없어
          // 주소를 복사할 수 있는 글자로 보여 준다.
          if (AppLinks.privacyPolicyUrl.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const PixelIcon(PixelIcons.document),
                const SizedBox(width: 8),
                Text(AppStrings.aiConsentPrivacyPolicy, style: textTheme.labelLarge),
              ],
            ),
            const SizedBox(height: 4),
            SelectableText(AppLinks.privacyPolicyUrl, style: textTheme.bodySmall),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _submitting ? null : _agree,
            child: _submitting ? const PixelLoader.small() : const Text(AppStrings.aiConsentAgree),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _submitting ? null : () => Navigator.of(context).pop(false),
            child: const Text(AppStrings.aiConsentDisagree),
          ),
        ],
      ),
    );
  }
}

/// 동의 내용 한 항목. 이름은 짧은 표제라 픽셀 글꼴, 내용은 문장이라 본문 글꼴.
class _ConsentItem extends StatelessWidget {
  const _ConsentItem({required this.label, required this.value, this.last = false});

  final String label;
  final String value;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(value, style: textTheme.bodyMedium),
        ],
      ),
    );
  }
}
