import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/navigation/app_tab.dart';
import '../../../core/strings.dart';
import '../../../core/widgets/pixel_frame.dart';
import '../../../core/widgets/pixel_loader.dart';
import '../../../core/widgets/status_message.dart';
import '../data/criteria_check_result.dart';
import '../domain/battle_providers.dart';
import '../domain/criteria_rules.dart';
import '../domain/duration_rules.dart';
import 'battle_chips.dart';
import 'criteria_views.dart';

/// 대결 만들기. 세 단계다.
///   A 입력  — 유형·제목·기간을 정하고 "AI 기준 만들기"
///   B 생성  — AI가 기준을 만드는 동안 기다린다
///   C 결과  — 기준을 확인하고 올리거나, 고쳐서 다시 검사하거나, 차단이면 제목을 고친다
///
/// 승인 전에는 대결이 만들어지지 않는다(모집 목록에도 없다).
class CreateBattleScreen extends ConsumerStatefulWidget {
  const CreateBattleScreen({super.key});

  @override
  ConsumerState<CreateBattleScreen> createState() => _CreateBattleScreenState();
}

enum _Stage { input, generating, result }

class _CreateBattleScreenState extends ConsumerState<CreateBattleScreen> {
  final _titleController = TextEditingController();

  String _type = 'speed';
  // 기본 3일. 하루는 촉박하고 일주일은 늘어진다.
  int _durationMinutes = 4320;
  // 직접 입력 모드. 빠른 선택과 동시에 켜지지 않는다.
  bool _customDuration = false;
  final _customDurationController = TextEditingController();
  DurationUnit _customUnit = DurationUnit.hours;
  String? _customDurationError;
  _Stage _stage = _Stage.input;

  CriteriaCheckResult? _result;
  bool _editing = false;
  List<String> _editedMin = [];
  List<String> _editedSuperiority = [];
  bool _busy = false;
  Object? _error;

  @override
  void dispose() {
    _titleController.dispose();
    _customDurationController.dispose();
    super.dispose();
  }

  bool get _isQuality => _type == 'quality';

  List<String> get _resultSuperiority => _result?.superiorityCriteria ?? const [];

  bool get _changed =>
      !criteriaListsEqual(_editedMin, _result?.minCriteria ?? const []) ||
      (_isQuality && !criteriaListsEqual(_editedSuperiority, _resultSuperiority));

  String? get _editError {
    final minError = validateCriteriaList(_editedMin);
    if (minError != null) return minError;
    if (_isQuality) return validateCriteriaList(_editedSuperiority);
    return null;
  }

  void _applyResult(CriteriaCheckResult result) {
    setState(() {
      _result = result;
      _error = null;
      _stage = _Stage.result;
      _editing = false;
      _editedMin = [...result.minCriteria];
      _editedSuperiority = [...(result.superiorityCriteria ?? const [])];
    });
    // 남은 횟수 표시를 갱신한다.
    ref.invalidate(myLimitsProvider);
  }

  void _handleFailure(Object error, StackTrace stackTrace) {
    debugPrint('battle-criteria failed: $error');
    if (!mounted) return;
    setState(() {
      _error = error;
      _stage = _Stage.result;
      _busy = false;
    });
    ref.invalidate(myLimitsProvider);
  }

  Future<void> _generate() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;

    setState(() {
      _stage = _Stage.generating;
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      final result = await ref.read(battleCriteriaRepositoryProvider).generate(
            title: title,
            type: _type,
            durationMinutes: _durationMinutes,
          );
      if (!mounted) return;
      setState(() => _busy = false);
      _applyResult(result);
    } catch (error, stackTrace) {
      _handleFailure(error, stackTrace);
    }
  }

  Future<void> _recheck() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await ref.read(battleCriteriaRepositoryProvider).check(
            title: _titleController.text.trim(),
            type: _type,
            durationMinutes: _durationMinutes,
            minCriteria: _editedMin.map((item) => item.trim()).toList(),
            superiorityCriteria:
                _isQuality ? _editedSuperiority.map((item) => item.trim()).toList() : null,
          );
      if (!mounted) return;
      setState(() => _busy = false);
      // 검사에 통과하면 읽기 모드로 돌아가고, 차단이면 사유를 보여 주되 편집은 계속할 수 있다.
      if (result.provable) {
        _applyResult(result);
      } else {
        setState(() {
          _result = result;
          _editing = true;
        });
        ref.invalidate(myLimitsProvider);
      }
    } catch (error, stackTrace) {
      _handleFailure(error, stackTrace);
    }
  }

  Future<void> _submit() async {
    final result = _result;
    if (result == null) return;

    setState(() => _busy = true);
    try {
      await ref.read(battleRepositoryProvider).createBattle(
            checkId: result.checkId,
            durationMinutes: _durationMinutes,
          );
      // 모집을 만드는 것은 남의 모집 목록을 바꾸지 않으므로 피드는 무효화하지 않는다
      // (찾기 탭의 검색어·필터·스크롤 위치도 그대로 남는다).
      ref.invalidate(myRecruitsProvider);
      ref.invalidate(myLimitsProvider);
      if (!mounted) return;
      // 올린 모집이 어느 화면에도 보이지 않는 구간을 만들지 않는다. 결과가 있는 자리로 보낸다.
      // 순서가 중요하다 — pop 뒤에 탭을 바꿔야 push된 화면이 남지 않는다.
      Navigator.of(context).pop();
      ref.read(selectedTabProvider.notifier).select(AppTab.myBattles);
      _showSnackBar(AppStrings.battleRecruitSubmitted);
    } catch (error) {
      debugPrint('createBattle failed: $error');
      if (!mounted) return;
      setState(() => _busy = false);
      _showSnackBar(criteriaErrorMessage(error));
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// 직접 입력 값을 읽어 `_durationMinutes`에 반영한다. 범위 밖이면 반영하지 않고 오류만 보여 준다
  /// (서버로 보내는 값은 항상 유효한 분이다).
  void _applyCustomDuration() {
    final minutes = durationMinutesOf(_customDurationController.text, _customUnit);
    setState(() {
      _customDurationError = validateDurationMinutes(minutes);
      if (_customDurationError == null) _durationMinutes = minutes!;
    });
  }

  /// 기간 입력: 자주 쓰는 값 빠른 선택 + 직접 입력(정수 + 단위). 서버에는 항상 분으로 보낸다.
  List<Widget> _buildDurationInput(BuildContext context) {
    final error = _customDurationError;

    return [
      SegmentedButton<int>(
        showSelectedIcon: false,
        // 직접 입력 중에는 빠른 선택이 아무것도 고르지 않은 상태가 된다.
        emptySelectionAllowed: true,
        segments: [
          for (final minutes in battleDurationQuickPicks)
            ButtonSegment(value: minutes, label: Text(battleDurationLabel(minutes))),
        ],
        selected: _customDuration ? const <int>{} : {_durationMinutes},
        onSelectionChanged: (selection) {
          if (selection.isEmpty) return;
          setState(() {
            _customDuration = false;
            _customDurationError = null;
            _durationMinutes = selection.first;
          });
        },
      ),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: _busy
              ? null
              : () {
                  setState(() {
                    _customDuration = !_customDuration;
                    _customDurationError = null;
                  });
                  if (_customDuration) _applyCustomDuration();
                },
          child: Text(
            _customDuration ? AppStrings.battleDurationQuick : AppStrings.battleDurationCustom,
          ),
        ),
      ),
      if (_customDuration) ...[
        Row(
          children: [
            SizedBox(
              width: 96,
              child: TextField(
                controller: _customDurationController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  hintText: AppStrings.battleDurationHint,
                  // 테두리만 오류 상태로 바꾸고 문구는 아래 한 줄에서 한 번만 말한다
                  // (errorText를 쓰면 같은 문구가 두 번 나온다).
                  error: error == null ? null : const SizedBox.shrink(),
                ),
                onChanged: (_) => _applyCustomDuration(),
              ),
            ),
            const SizedBox(width: 8),
            SegmentedButton<DurationUnit>(
              showSelectedIcon: false,
              segments: [
                for (final unit in DurationUnit.values)
                  ButtonSegment(value: unit, label: Text(unit.label)),
              ],
              selected: {_customUnit},
              onSelectionChanged: (selection) {
                _customUnit = selection.first;
                _applyCustomDuration();
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          error ?? battleDurationLabel(_durationMinutes),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.battleCreate)),
      body: switch (_stage) {
        _Stage.input => _buildInput(context),
        _Stage.generating => const StatusMessage.loading(
            message: AppStrings.battleCriteriaGenerating,
            detail: AppStrings.battleCriteriaGeneratingDetail,
            fill: true,
          ),
        _Stage.result => _buildResult(context),
      },
    );
  }

  Widget _buildInput(BuildContext context) {
    final limitsAsync = ref.watch(myLimitsProvider);
    final limits = limitsAsync.value;
    // 사전 차단은 편의일 뿐이다. 같은 검사를 Edge Function과 create_battle이 다시 한다.
    final blockMessage = limits == null ? null : createBattleBlockMessage(limits);
    final canGenerate =
        _titleController.text.trim().isNotEmpty && !_busy && limits != null && blockMessage == null;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'speed', label: Text(AppStrings.battleTypeSpeed)),
            ButtonSegment(value: 'quality', label: Text(AppStrings.battleTypeQuality)),
          ],
          selected: {_type},
          onSelectionChanged: (selection) => setState(() => _type = selection.first),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _titleController,
          decoration: const InputDecoration(hintText: AppStrings.battleTitleHint),
          maxLength: battleTitleMaxLength,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 16),
        Text(AppStrings.battleDuration, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        ..._buildDurationInput(context),
        const SizedBox(height: 8),
        Text(AppStrings.battleDurationNotice, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 4),
        // 기간을 짧게 고를 수 있게 됐으므로 그 위험을 같은 자리에서 알린다(spec D6 — 구조가 아니라 경고로만).
        Text(AppStrings.battleDurationShortWarning, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 4),
        // "1분 대결"이 1분 만에 끝나는 것이 아니라는 것을 여기서 한 번 말해 둔다.
        Text(AppStrings.battleDurationWindowNotice, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 24),
        if (blockMessage != null) ...[
          PixelFrame.tone(tone: PixelTone.neutral, child: Text(blockMessage)),
          const SizedBox(height: 16),
        ],
        FilledButton(
          onPressed: canGenerate ? _generate : null,
          child: _busy
              ? const PixelLoader.small()
              : const Text(AppStrings.battleCriteriaGenerate),
        ),
        if (limits != null) ...[
          const SizedBox(height: 8),
          Text(
            AppStrings.battleCriteriaCallsLeft(limits.criteriaCallsLeft),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }

  Widget _buildResult(BuildContext context) {
    final error = _error;
    if (error != null) {
      return StatusMessage.error(
        message: criteriaErrorMessage(error),
        fill: true,
        action: FilledButton(
          onPressed: _busy ? null : _generate,
          child: const Text(AppStrings.retry),
        ),
      );
    }

    final result = _result;
    if (result == null) return const SizedBox.shrink();

    if (!result.provable && !_editing) {
      // 차단. 기준 편집·승인 버튼을 주지 않는다(수정으로 차단을 우회할 수 없다).
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          PixelFrame.tone(
            tone: PixelTone.danger,
            title: AppStrings.battleCriteriaBlocked,
            child: Text(result.blockReason ?? ''),
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: () => setState(() => _stage = _Stage.input),
            child: const Text(AppStrings.battleCriteriaFixTitle),
          ),
        ],
      );
    }

    final editError = _editing ? _editError : null;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(_titleController.text.trim(), style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 16),
        if (!result.provable) ...[
          // 수정 중 차단된 경우. 편집은 계속할 수 있다.
          PixelFrame.tone(
            tone: PixelTone.danger,
            title: AppStrings.battleCriteriaBlocked,
            child: Text(result.blockReason ?? ''),
          ),
          const SizedBox(height: 16),
        ],
        if (_editing) ...[
          CriteriaEditor(
            title: AppStrings.battleCriteriaMinTitle,
            hint: AppStrings.battleCriteriaMinHint,
            items: _editedMin,
            enabled: !_busy,
            onChanged: (items) => setState(() => _editedMin = items),
          ),
          if (_isQuality) ...[
            const SizedBox(height: 16),
            CriteriaEditor(
              title: AppStrings.battleCriteriaSuperiorityTitle,
              hint: AppStrings.battleCriteriaSuperiorityHint,
              items: _editedSuperiority,
              enabled: !_busy,
              onChanged: (items) => setState(() => _editedSuperiority = items),
            ),
          ],
        ] else ...[
          CriteriaListBlock(
            title: AppStrings.battleCriteriaMinTitle,
            hint: AppStrings.battleCriteriaMinHint,
            items: result.minCriteria,
          ),
          if (_isQuality && _resultSuperiority.isNotEmpty) ...[
            const SizedBox(height: 16),
            CriteriaListBlock(
              title: AppStrings.battleCriteriaSuperiorityTitle,
              hint: AppStrings.battleCriteriaSuperiorityHint,
              items: _resultSuperiority,
            ),
          ],
        ],
        if (editError != null) ...[
          const SizedBox(height: 8),
          Text(editError, style: Theme.of(context).textTheme.bodySmall),
        ],
        const SizedBox(height: 24),
        // 고친 내용이 있으면 먼저 다시 검사해야 올릴 수 있다(수정으로 차단 우회 금지).
        if (_editing && (_changed || !result.provable))
          FilledButton(
            onPressed: _busy || editError != null ? null : _recheck,
            child: _busy
                ? const PixelLoader.small()
                : const Text(AppStrings.battleCriteriaRecheck),
          )
        else
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy ? const PixelLoader.small() : const Text(AppStrings.battleCriteriaSubmit),
          ),
        const SizedBox(height: 8),
        if (_editing)
          TextButton(
            onPressed: _busy
                ? null
                : () => setState(() {
                      _editing = false;
                      _editedMin = [...result.minCriteria];
                      _editedSuperiority = [...(result.superiorityCriteria ?? const [])];
                    }),
            child: const Text(AppStrings.battleCriteriaRevert),
          )
        else
          OutlinedButton(
            onPressed: _busy ? null : () => setState(() => _editing = true),
            child: const Text(AppStrings.battleCriteriaEdit),
          ),
      ],
    );
  }
}
