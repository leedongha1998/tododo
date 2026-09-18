import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/strings.dart';
import '../../../core/widgets/pixel_frame.dart';
import '../../../core/widgets/pixel_loader.dart';
import '../../../core/widgets/pixel_tag.dart';
import '../data/open_recruit.dart';
import '../domain/ai_consent_providers.dart';
import '../domain/ai_consent_rules.dart';
import '../domain/battle_providers.dart';
import '../domain/criteria_rules.dart';
import 'ai_consent_screen.dart';
import 'battle_chips.dart';
import 'criteria_views.dart';
import 'player_card_view.dart';

/// 모집 상세 바텀시트를 띄우고, 참가에 성공하면 참가한 모집을 돌려준다(아니면 null).
///
/// VS 인트로·성공 토스트·탭 이동은 시트가 닫힌 뒤 호출자가 한다 — 시트 context는 그때 이미 없다.
Future<OpenRecruit?> showRecruitSheet(BuildContext context, OpenRecruit recruit) {
  return showModalBottomSheet<OpenRecruit>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _RecruitSheet(recruit: recruit),
  );
}

class _RecruitSheet extends ConsumerStatefulWidget {
  const _RecruitSheet({required this.recruit});

  final OpenRecruit recruit;

  @override
  ConsumerState<_RecruitSheet> createState() => _RecruitSheetState();
}

class _RecruitSheetState extends ConsumerState<_RecruitSheet> {
  late OpenRecruit _recruit = widget.recruit;

  /// 참가하려는 순간 생성자가 기준을 바꿨을 때의 안내.
  bool _criteriaChanged = false;
  bool _busy = false;

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// 바뀐 기준을 다시 읽어 시트 안에서 갱신한다. 그 사이 매칭됐으면 시트를 닫는다.
  Future<void> _refreshCriteria() async {
    try {
      final recruits = await ref.refresh(openRecruitsProvider.future);
      OpenRecruit? fresh;
      for (final candidate in recruits) {
        if (candidate.battle.id == _recruit.battle.id) {
          fresh = candidate;
          break;
        }
      }
      if (!mounted) return;
      if (fresh == null) {
        Navigator.of(context).pop();
        return;
      }
      setState(() {
        _recruit = fresh!;
        _criteriaChanged = true;
      });
    } catch (e) {
      debugPrint('openRecruits refresh failed: $e');
      if (mounted) _showSnackBar(AppStrings.battleLoadRecruitsFailed);
    }
  }

  Future<void> _join({bool retried = false}) async {
    if (!await ensureAiConsent(context, ref)) return;
    if (!mounted) return;

    setState(() => _busy = true);
    try {
      await ref.read(battleRepositoryProvider).joinBattle(
            _recruit.battle.id,
            _recruit.battle.criteriaVersion,
          );
    } catch (error) {
      debugPrint('joinBattle failed: $error');
      if (!mounted) return;
      setState(() => _busy = false);

      // 앱이 알던 동의 상태가 서버와 어긋난 경우(다른 기기에서 철회 등). 다시 읽고 한 번만 재시도한다.
      if (isConsentRequiredError(error) && !retried) {
        ref.invalidate(myAiConsentProvider);
        await _join(retried: true);
        return;
      }
      if (isCriteriaChangedError(error)) {
        await _refreshCriteria();
        return;
      }
      // 이미 매칭된 모집은 목록에서도 사라져야 한다.
      if (errorCodeOf(error) == 'ALREADY_MATCHED') {
        ref.invalidate(openRecruitsProvider);
        if (mounted) {
          Navigator.of(context).pop();
          _showSnackBar(AppStrings.battleErrorAlreadyMatched);
        }
        return;
      }
      _showSnackBar(criteriaErrorMessage(error));
      return;
    }

    if (!mounted) return;
    Navigator.of(context).pop(_recruit);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final battle = _recruit.battle;
    final superiority = battle.superiorityCriteria ?? const [];

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_criteriaChanged) ...[
              PixelFrame.tone(
                tone: PixelTone.info,
                child: const Text(AppStrings.battleCriteriaChanged),
              ),
              const SizedBox(height: 16),
            ],
            Text(battle.title, style: textTheme.titleMedium),
            const SizedBox(height: 12),
            Row(
              children: [
                BattleTypeBadge(type: battle.type),
                const SizedBox(width: 8),
                PixelTag(
                  label: battleDurationLabel(battle.durationMinutes),
                  style: battleStatusTagStyle('draw'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(battleTypeTagline(battle.type), style: textTheme.bodyMedium),
            const SizedBox(height: 16),
            CriteriaListBlock(
              title: AppStrings.battleCriteriaMinTitle,
              hint: AppStrings.battleCriteriaMinHint,
              items: battle.minCriteria,
            ),
            if (superiority.isNotEmpty) ...[
              const SizedBox(height: 16),
              CriteriaListBlock(
                title: AppStrings.battleCriteriaSuperiorityTitle,
                hint: AppStrings.battleCriteriaSuperiorityHint,
                items: superiority,
              ),
            ],
            const SizedBox(height: 16),
            PixelFrame.raised(
              child: PlayerCardView(
                card: _recruit.creator,
                label: AppStrings.battleRecruitCreatorLabel,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _join,
              child: _busy
                  ? const PixelLoader.small()
                  : const Text(AppStrings.battleRecruitJoinWithCriteria),
            ),
          ],
        ),
      ),
    );
  }
}
