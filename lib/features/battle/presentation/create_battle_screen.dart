import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/navigation/app_tab.dart';
import '../../../core/strings.dart';
import '../../../core/widgets/app_loader.dart';
import '../../../core/widgets/app_panel.dart';
import '../../../core/widgets/keep_words_text.dart';
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

/// 테마 텍스트 버튼의 안쪽 좌우 여백(app_theme.dart textButtonTheme padding). "직접 입력" 글자를 위아래 글과
/// 맞추려고 그만큼 왼쪽으로 옮긴다.
const _textButtonInset = 12.0;

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

  /// 기준 받기. [skipCache]가 true면 `기준 다시 만들기`다 — 서버가 캐시를 건너뛰고 AI에게 새로
  /// 묻는다(한도 1회). 첫 생성과 **같은 로딩 화면**을 쓴다(적중 여부로 갈리는 모습이 없다).
  Future<void> _generate({bool skipCache = false}) async {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;

    setState(() {
      _stage = _Stage.generating;
      _busy = true;
      _error = null;
      // 다시 만들기는 들고 있던 기준을 비우지 않는다 — 실패했을 때 그대로 보여 주기 위해서다.
      if (!skipCache) _result = null;
    });
    try {
      final result = await ref.read(battleCriteriaRepositoryProvider).generate(
            title: title,
            type: _type,
            durationMinutes: _durationMinutes,
            skipCache: skipCache,
          );
      if (!mounted) return;
      setState(() => _busy = false);
      _applyResult(result);
    } catch (error, stackTrace) {
      // 다시 만들기가 실패했는데 들고 있는 기준이 있으면 **그 기준을 잃지 않는다.**
      // 전체 오류 화면(`_handleFailure`)은 "보여 줄 결과가 없을 때"의 것이라 쓰지 않는다
      // (한도를 다 쓴 상태에서 눌렀을 때 기존 한도 문구만 스낵바로 뜨고 기준은 그대로 남는다).
      if (skipCache && _result != null) {
        debugPrint('battle-criteria regenerate failed: $error');
        if (!mounted) return;
        setState(() {
          _busy = false;
          _stage = _Stage.result;
        });
        ref.invalidate(myLimitsProvider);
        _showSnackBar(criteriaErrorMessage(error));
        return;
      }
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
      // true는 "모집을 올렸다"는 신호다. 띄운 쪽(찾기 탭)이 이걸 보고 알림 권한을 묻는다.
      Navigator.of(context).pop(true);
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: KeepWordsText(message)));
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
            ButtonSegment(value: minutes, label: KeepWordsText(battleDurationLabel(minutes))),
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
      // 텍스트 버튼은 안쪽 좌우 여백(12)이 있어 글자가 위아래 글보다 들여 써진다. 버튼을 그 여백만큼 왼쪽으로
      // 옮겨 글자 왼쪽 끝을 세그먼트·입력칸과 맞춘다(누를 때 생기는 면은 화면 여백 20 안에 들어간다).
      Align(
        alignment: Alignment.centerLeft,
        child: Transform.translate(
          offset: const Offset(-_textButtonInset, 0),
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
            child: KeepWordsText(
              _customDuration ? AppStrings.battleDurationQuick : AppStrings.battleDurationCustom,
            ),
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
                  ButtonSegment(value: unit, label: KeepWordsText(unit.label)),
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
        // 기간 범위 오류는 오류 슬롯(bodyMedium), 환산 결과는 보조 문장(bodySmall).
        KeepWordsText(
          error ?? battleDurationLabel(_durationMinutes),
          style: error != null
              ? Theme.of(context).textTheme.bodyMedium
              : Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ];
  }

  /// 뒤로가기를 막아야 하는가. 막는 경우는 둘뿐이다 — AI가 기준을 만드는 중(`_busy`)이거나
  /// 만들어진 기준을 들고 있을 때(`_result != null`). 둘 다 나가면 결과가 버려지고
  /// 이미 차감된 횟수는 돌아오지 않는다.
  ///
  /// **입력 단계에서는 어떤 경우에도 막지 않는다.** `제목 고치기`는 `_stage`만 input으로 되돌리고
  /// `_result`는 들고 있으므로, `_result`만 보면 입력 화면에서 사용자가 갇힌다.
  ///
  /// **오류 화면(`_error != null`)에서도 막지 않는다.** 재검사가 실패하면 `_result`는 남지만
  /// 화면은 "횟수는 차감되지 않았어요"를 보여 주므로, 거기서 "쓴 횟수는 돌아오지 않아요"라고
  /// 묻는 것은 화면과 반대로 말하는 것이다. 게다가 그 자리에서 `_result`로 되돌아갈 길도 없다.
  /// `_error`는 `_generate`/`_recheck` 시작 시 null로 초기화되므로 정상 흐름에는 영향이 없다.
  bool get _blocksLeaving =>
      _stage != _Stage.input && _error == null && (_busy || _result != null);

  @override
  Widget build(BuildContext context) {
    return CriteriaLeaveGuard(
      title: AppStrings.battleCriteriaLeaveTitle,
      blocked: _blocksLeaving,
      child: Scaffold(
        appBar: AppBar(title: const KeepWordsText(AppStrings.battleCreate)),
        body: switch (_stage) {
          _Stage.input => _buildInput(context),
          _Stage.generating => const StatusMessage.loading(
              message: AppStrings.battleCriteriaGenerating,
              detail: AppStrings.battleCriteriaGeneratingDetail,
              fill: true,
            ),
          _Stage.result => _buildResult(context),
        },
      ),
    );
  }

  Widget _buildInput(BuildContext context) {
    final limitsAsync = ref.watch(myLimitsProvider);
    final limits = limitsAsync.value;
    // 사전 차단은 편의일 뿐이다. 같은 검사를 Edge Function과 create_battle이 다시 한다.
    // **한도 소진은 차단이 아니라 안내다**(criteria-cache) — 캐시 적중은 한도를 쓰지 않으므로
    // 다 쓴 날에도 기준이 나올 수 있다. 미적중이면 서버가 거절해 같은 문구가 그대로 뜬다.
    final blockMessage = limits == null ? null : createBattleBlockMessage(limits);
    final exhaustedNotice = limits == null ? null : criteriaCallsExhaustedNotice(limits);
    final canGenerate =
        _titleController.text.trim().isNotEmpty && !_busy && limits != null && blockMessage == null;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        SegmentedButton<String>(
          // 테마가 selectedIcon(체크)을 주므로 끄지 않으면 라벨 폭을 먹어 글자가 잘린다
          // (같은 화면의 기간 세그먼트 둘과 찾기 탭이 쓰는 것과 같은 이유).
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: 'speed', label: KeepWordsText(AppStrings.battleTypeSpeed)),
            ButtonSegment(value: 'quality', label: KeepWordsText(AppStrings.battleTypeQuality)),
          ],
          selected: {_type},
          onSelectionChanged: (selection) => setState(() => _type = selection.first),
        ),
        const SizedBox(height: 8),
        // 두 유형의 차이를 고르는 자리에서 말한다. 모집 상세 시트가 참가자에게 보여 주는 문장과
        // 같은 함수를 써서, 만드는 사람과 참가하는 사람이 같은 설명을 읽게 한다.
        KeepWordsText(battleTypeTagline(_type), style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 24),
        TextField(
          controller: _titleController,
          decoration: const InputDecoration(hintText: AppStrings.battleTitleHint),
          maxLength: battleTitleMaxLength,
          onChanged: (_) => setState(() {}),
        ),
        // 사진으로 증명할 수 없는 제목은 기준 생성에서 차단되고 AI 호출 1회가 이미 차감된다.
        // 그 함정을 제목을 쓰는 동안 말해 준다(차단 자체는 그대로 서버가 한다).
        KeepWordsText(
          AppStrings.battleTitleProvableHint,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 24),
        KeepWordsText(AppStrings.battleDuration, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        ..._buildDurationInput(context),
        const SizedBox(height: 8),
        KeepWordsText(AppStrings.battleDurationNotice, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 8),
        // 기간을 짧게 고를 수 있게 됐으므로 그 위험을 같은 자리에서 알린다(spec D6 — 구조가 아니라 경고로만).
        KeepWordsText(AppStrings.battleDurationShortWarning, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 8),
        // "1분 대결"이 1분 만에 끝나는 것이 아니라는 것을 여기서 한 번 말해 둔다.
        KeepWordsText(AppStrings.battleDurationWindowNotice, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 24),
        if ((blockMessage ?? exhaustedNotice) != null) ...[
          // 동의 전 차단과 한도 소진 안내가 같은 자리를 쓴다(redesign design 5.5 "차단·한도 안내
          // tone danger"). 둘의 차이는 **버튼을 막는지**뿐이다 — 안내는 막지 않는다.
          AppPanel.tone(
            tone: AppTone.danger,
            child: KeepWordsText((blockMessage ?? exhaustedNotice)!),
          ),
          const SizedBox(height: 16),
        ],
        FilledButton(
          onPressed: canGenerate ? () => _generate() : null,
          child: _busy
              ? const AppLoader.small()
              : const KeepWordsText(AppStrings.battleCriteriaGenerate),
        ),
        if (limits != null) ...[
          const SizedBox(height: 8),
          KeepWordsText(
            AppStrings.battleCriteriaCallsLeft(limits.criteriaCallsLeft),
            style: Theme.of(context).textTheme.bodyMedium,
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
          onPressed: _busy ? null : () => _generate(),
          child: const KeepWordsText(AppStrings.retry),
        ),
      );
    }

    final result = _result;
    if (result == null) return const SizedBox.shrink();

    if (!result.provable && !_editing) {
      // 차단. 기준 편집·승인 버튼을 주지 않는다(수정으로 차단을 우회할 수 없다).
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          AppPanel.tone(
            tone: AppTone.danger,
            title: AppStrings.battleCriteriaBlocked,
            child: KeepWordsText(result.blockReason ?? ''),
          ),
          const SizedBox(height: 16),
          // 차단의 탈출구. **주 버튼이다** — `제목 고치기`는 "다른 주제를 쓴다"는 포기에 가깝고,
          // 캐시가 내려 준 차단일 수도 있어 다시 물어볼 길이 없으면 그 제목은 영구히 막힌다.
          // 캐시 적중 여부와 무관하게 늘 같은 자리에 있다(버튼의 존재로 적중이 누설되지 않는다).
          FilledButton(
            onPressed: _busy ? null : () => _generate(skipCache: true),
            child: _busy
                ? const AppLoader.small()
                : const KeepWordsText(AppStrings.battleCriteriaRecheckBlocked),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _busy ? null : () => setState(() => _stage = _Stage.input),
            child: const KeepWordsText(AppStrings.battleCriteriaFixTitle),
          ),
        ],
      );
    }

    final editError = _editing ? _editError : null;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        KeepWordsText(_titleController.text.trim(), style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 16),
        if (!result.provable) ...[
          // 수정 중 차단된 경우. 편집은 계속할 수 있다.
          AppPanel.tone(
            tone: AppTone.danger,
            title: AppStrings.battleCriteriaBlocked,
            child: KeepWordsText(result.blockReason ?? ''),
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
            const SizedBox(height: 24),
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
            const SizedBox(height: 24),
            CriteriaListBlock(
              title: AppStrings.battleCriteriaSuperiorityTitle,
              hint: AppStrings.battleCriteriaSuperiorityHint,
              items: _resultSuperiority,
            ),
          ],
        ],
        if (editError != null) ...[
          const SizedBox(height: 8),
          // 편집 오류는 버튼이 왜 막혔는지 말하는 문장이다 — bodySmall이 아니라 오류 슬롯 bodyMedium.
          KeepWordsText(editError, style: Theme.of(context).textTheme.bodyMedium),
        ],
        const SizedBox(height: 24),
        // 고친 내용이 있으면 먼저 다시 검사해야 올릴 수 있다(수정으로 차단 우회 금지).
        if (_editing && (_changed || !result.provable))
          FilledButton(
            onPressed: _busy || editError != null ? null : _recheck,
            child: _busy
                ? const AppLoader.small()
                : const KeepWordsText(AppStrings.battleCriteriaRecheck),
          )
        else
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy ? const AppLoader.small() : const KeepWordsText(AppStrings.battleCriteriaSubmit),
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
            child: const KeepWordsText(AppStrings.battleCriteriaRevert),
          )
        else ...[
          OutlinedButton(
            onPressed: _busy ? null : () => setState(() => _editing = true),
            child: const KeepWordsText(AppStrings.battleCriteriaEdit),
          ),
          const SizedBox(height: 8),
          // 기준이 마음에 들지 않으면 AI에게 새로 묻는다(한도 1회 — 문구가 그걸 먼저 말한다).
          // **적중 여부와 무관하게 늘 있다**: AI가 방금 만든 기준도 마음에 안 들 수 있고,
          // 버튼의 존재/부재로 적중이 누설되면 안 된다. 편집 중에는 두지 않는다 — 그 자리는
          // `원래 기준으로 되돌리기`가 쓰고, 편집 중에 누르면 쓰던 내용이 사라져 확인창이
          // 하나 더 필요해진다(적중 여부와 무관한 조건이다).
          TextButton(
            onPressed: _busy ? null : () => _generate(skipCache: true),
            child: const KeepWordsText(AppStrings.battleCriteriaRegenerate),
          ),
        ],
      ],
    );
  }
}
