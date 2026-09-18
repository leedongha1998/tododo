import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/strings.dart';
import '../../../core/widgets/pixel_frame.dart';
import '../../../core/widgets/pixel_loader.dart';
import '../data/battle.dart';
import '../data/criteria_check_result.dart';
import '../domain/battle_providers.dart';
import '../domain/criteria_rules.dart';
import 'criteria_views.dart';

/// 모집 중(상대 없음)인 내 대결의 기준 수정(결정 46).
/// 고친 기준도 증명 가능성 재검사를 거쳐야 하고, 재검사는 하루 10회에 포함된다.
/// 매칭된 뒤에는 서버가 거부한다.
class EditRecruitCriteriaScreen extends ConsumerStatefulWidget {
  const EditRecruitCriteriaScreen({super.key, required this.battle});

  final Battle battle;

  @override
  ConsumerState<EditRecruitCriteriaScreen> createState() => _EditRecruitCriteriaScreenState();
}

class _EditRecruitCriteriaScreenState extends ConsumerState<EditRecruitCriteriaScreen> {
  late List<String> _editedMin = [...widget.battle.minCriteria];
  late List<String> _editedSuperiority = [...(widget.battle.superiorityCriteria ?? const [])];

  /// 재검사를 통과한 증서. 있어야 "기준 바꾸기"를 누를 수 있다.
  CriteriaCheckResult? _checked;
  bool _busy = false;

  bool get _isQuality => widget.battle.type == 'quality';

  bool get _changed =>
      !criteriaListsEqual(_editedMin, widget.battle.minCriteria) ||
      (_isQuality && !criteriaListsEqual(_editedSuperiority, widget.battle.superiorityCriteria ?? const []));

  String? get _editError {
    final minError = validateCriteriaList(_editedMin);
    if (minError != null) return minError;
    if (_isQuality) return validateCriteriaList(_editedSuperiority);
    return null;
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _recheck() async {
    setState(() => _busy = true);
    try {
      final result = await ref.read(battleCriteriaRepositoryProvider).check(
            title: widget.battle.title,
            type: widget.battle.type,
            durationMinutes: widget.battle.durationMinutes,
            minCriteria: _editedMin.map((item) => item.trim()).toList(),
            superiorityCriteria:
                _isQuality ? _editedSuperiority.map((item) => item.trim()).toList() : null,
            battleId: widget.battle.id,
          );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _checked = result;
      });
      ref.invalidate(myLimitsProvider);
    } catch (error) {
      debugPrint('criteria check failed: $error');
      if (!mounted) return;
      setState(() => _busy = false);
      ref.invalidate(myLimitsProvider);
      _showSnackBar(criteriaErrorMessage(error));
    }
  }

  Future<void> _apply() async {
    final checked = _checked;
    if (checked == null) return;

    setState(() => _busy = true);
    try {
      await ref.read(battleRepositoryProvider).updateBattleCriteria(
            battleId: widget.battle.id,
            checkId: checked.checkId,
          );
      ref.invalidate(myRecruitsProvider);
      ref.invalidate(openRecruitsProvider);
      if (!mounted) return;
      Navigator.of(context).pop();
      _showSnackBar(AppStrings.battleCriteriaApplied);
    } catch (error) {
      debugPrint('updateBattleCriteria failed: $error');
      if (!mounted) return;
      setState(() => _busy = false);
      _showSnackBar(criteriaErrorMessage(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final checked = _checked;
    final editError = _editError;
    // 고친 뒤에는 반드시 재검사를 통과해야 바꿀 수 있다.
    final canApply = checked != null && checked.provable && !_busy;

    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.battleCriteriaEditRecruit)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(widget.battle.title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          if (checked != null && !checked.provable) ...[
            PixelFrame.tone(
              tone: PixelTone.danger,
              title: AppStrings.battleCriteriaBlocked,
              child: Text(checked.blockReason ?? ''),
            ),
            const SizedBox(height: 16),
          ],
          CriteriaEditor(
            title: AppStrings.battleCriteriaMinTitle,
            hint: AppStrings.battleCriteriaMinHint,
            items: _editedMin,
            enabled: !_busy,
            onChanged: (items) => setState(() {
              _editedMin = items;
              _checked = null;
            }),
          ),
          if (_isQuality) ...[
            const SizedBox(height: 16),
            CriteriaEditor(
              title: AppStrings.battleCriteriaSuperiorityTitle,
              hint: AppStrings.battleCriteriaSuperiorityHint,
              items: _editedSuperiority,
              enabled: !_busy,
              onChanged: (items) => setState(() {
                _editedSuperiority = items;
                _checked = null;
              }),
            ),
          ],
          if (editError != null) ...[
            const SizedBox(height: 8),
            Text(editError, style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: 24),
          if (canApply)
            FilledButton(
              onPressed: _apply,
              child: _busy
                  ? const PixelLoader.small()
                  : const Text(AppStrings.battleCriteriaApply),
            )
          else
            FilledButton(
              onPressed: _busy || editError != null || !_changed ? null : _recheck,
              child: _busy
                  ? const PixelLoader.small()
                  : const Text(AppStrings.battleCriteriaRecheck),
            ),
        ],
      ),
    );
  }
}
