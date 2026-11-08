import 'package:flutter/material.dart';

import '../../../core/strings.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_panel.dart';
import '../../../core/widgets/keep_words_text.dart';
import '../domain/criteria_rules.dart';

/// 읽기 모드의 기준 목록 한 블록. 최소 기준과 우열 기준을 같은 모양으로 구분해 보여 준다.
class CriteriaListBlock extends StatelessWidget {
  const CriteriaListBlock({
    super.key,
    required this.title,
    required this.items,
    this.hint,
  });

  final String title;
  final List<String> items;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return AppPanel.flat(
      title: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hint != null) ...[
            KeepWordsText(hint!, style: textTheme.bodyMedium),
            const SizedBox(height: 8),
          ],
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            Row(
              // 번호(숫자 16)와 기준 첫 줄(문장 15)의 글자 기준선을 맞춘다.
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                // 번호는 숫자 슬롯(고정폭) + 글자용 브랜드색, 기준 본문은 문장 슬롯.
                KeepWordsText(
                  '${i + 1}',
                  style: AppText.numberSmall.copyWith(color: AppPalette.primaryDeep),
                ),
                const SizedBox(width: 8),
                Expanded(child: KeepWordsText(items[i], style: textTheme.bodyMedium)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// 판정 단계 카드 안의 기준 상자(design-judging-buttons 공통 토큰 "기준 상자"). 읽기 전용.
///
/// sunken 면·모서리 12·안쪽 12·테두리 없음. 첫 줄 힌트 bodyMedium inkMuted, 항목 bodyMedium ink, 항목 앞 6dp 원점
/// inkMuted — 번호를 쓰지 않는다(단계 번호 1·2와 겹치지 않게). 다른 화면(대결 만들기·모집 상세)은 [CriteriaListBlock]을 쓴다.
class CriteriaChecklistBox extends StatelessWidget {
  const CriteriaChecklistBox({super.key, required this.items, this.hint});

  final List<String> items;
  final String? hint;

  static const dotSize = 6.0;

  @override
  Widget build(BuildContext context) {
    final body = Theme.of(context).textTheme.bodyMedium!;
    // 점을 첫 줄 높이(15 × 글자 배율 × 행간) 가운데에 둔다 — 큰 배율에서도 첫 줄 옆에 온다.
    final firstLine = MediaQuery.textScalerOf(context).scale(body.fontSize!) * body.height!;

    return Container(
      key: const ValueKey('criteria-checklist-box'),
      padding: const EdgeInsets.all(12),
      decoration: const ShapeDecoration(
        color: AppPalette.sunken,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hint != null) ...[
            KeepWordsText(hint!, style: body.copyWith(color: AppPalette.inkMuted)),
            const SizedBox(height: 8),
          ],
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: firstLine,
                  child: const Center(
                    child: DecoratedBox(
                      decoration: ShapeDecoration(color: AppPalette.inkMuted, shape: CircleBorder()),
                      child: SizedBox.square(dimension: dotSize),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: KeepWordsText(items[i], style: body.copyWith(color: AppPalette.ink))),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// 수정 모드의 기준 목록 한 블록. 항목 편집·추가(최대 5개)·삭제(최소 1개).
class CriteriaEditor extends StatefulWidget {
  const CriteriaEditor({
    super.key,
    required this.title,
    required this.items,
    required this.onChanged,
    this.hint,
    this.enabled = true,
  });

  final String title;
  final List<String> items;
  final ValueChanged<List<String>> onChanged;
  final String? hint;
  final bool enabled;

  @override
  State<CriteriaEditor> createState() => _CriteriaEditorState();
}

class _CriteriaEditorState extends State<CriteriaEditor> {
  late List<TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    _controllers = widget.items.map((item) => TextEditingController(text: item)).toList();
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _emit() => widget.onChanged(_controllers.map((c) => c.text).toList());

  void _add() {
    setState(() => _controllers.add(TextEditingController()));
    _emit();
  }

  void _removeAt(int index) {
    setState(() => _controllers.removeAt(index).dispose());
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return AppPanel.flat(
      title: widget.title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.hint != null) ...[
            KeepWordsText(widget.hint!, style: textTheme.bodyMedium),
            const SizedBox(height: 8),
          ],
          for (var i = 0; i < _controllers.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _controllers[i],
                    enabled: widget.enabled,
                    maxLength: criterionMaxLength,
                    maxLines: null,
                    onChanged: (_) => _emit(),
                  ),
                ),
                // 마지막 하나는 지울 수 없다(기준이 0개가 되면 판정할 수 없다).
                IconButton(
                  onPressed:
                      widget.enabled && _controllers.length > criteriaMinCount ? () => _removeAt(i) : null,
                  tooltip: AppStrings.battleCriteriaRemove,
                  icon: const Icon(AppIcons.remove),
                ),
              ],
            ),
          ],
          if (_controllers.length < criteriaMaxCount)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: widget.enabled ? _add : null,
                icon: const Icon(AppIcons.add),
                label: const KeepWordsText(AppStrings.battleCriteriaAdd),
              ),
            ),
        ],
      ),
    );
  }
}

/// 기준을 만드는 중이거나 만들어 둔 기준을 들고 있을 때만 뒤로가기를 막고 한 번 확인한다.
///
/// [blocked]가 false면 평소와 똑같이 즉시 나가진다. 입력만 해 둔 단계에서 확인창을 띄우면
/// **잃는 것이 없는데 길을 막는 것**이라 더 나쁘다(audit.md M7). 그래서 이 위젯은 무엇을
/// 막을지 판단하지 않고, 화면이 넘겨준 [blocked]만 따른다.
///
/// [title]도 같은 이유로 화면이 넘긴다 — 만들기 화면과 수정 화면은 사용자가 하던 일이 다르다.
/// 본문은 양쪽이 같아서(`만든 기준이 사라지고 쓴 횟수는 돌아오지 않는다`) 여기에 둔다.
///
/// `Navigator.pop()`(코드가 직접 닫는 길)은 `PopScope`를 거치지 않으므로 제출 성공 뒤 화면을
/// 닫는 흐름은 그대로 동작한다. 막히는 것은 시스템 뒤로가기 제스처와 앱바 뒤로가기뿐이다.
class CriteriaLeaveGuard extends StatelessWidget {
  const CriteriaLeaveGuard({
    super.key,
    required this.title,
    required this.blocked,
    required this.child,
  });

  final String title;
  final bool blocked;
  final Widget child;

  Future<void> _confirmLeave(BuildContext context) async {
    // await 뒤에 context를 다시 쓰지 않으려고 navigator를 미리 잡아 둔다.
    final navigator = Navigator.of(context);
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: KeepWordsText(title),
        content: const KeepWordsText(AppStrings.battleCriteriaLeaveBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const KeepWordsText(AppStrings.stay),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const KeepWordsText(AppStrings.leave),
          ),
        ],
      ),
    );
    if (leave == true) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !blocked,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _confirmLeave(context);
      },
      child: child,
    );
  }
}
