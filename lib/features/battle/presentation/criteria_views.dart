import 'package:flutter/material.dart';

import '../../../core/strings.dart';
import '../../../core/theme/pixel_icons.dart';
import '../../../core/widgets/pixel_frame.dart';
import '../../../core/widgets/pixel_icon.dart';
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

    return PixelFrame.flat(
      title: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hint != null) ...[
            Text(hint!, style: textTheme.bodySmall),
            const SizedBox(height: 8),
          ],
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 번호는 숫자라 픽셀 글꼴, 기준 본문은 문장이라 본문 글꼴.
                Text('${i + 1}', style: textTheme.labelLarge),
                const SizedBox(width: 8),
                Expanded(child: Text(items[i], style: textTheme.bodyMedium)),
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

    return PixelFrame.flat(
      title: widget.title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.hint != null) ...[
            Text(widget.hint!, style: textTheme.bodySmall),
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
                  icon: const PixelIcon(PixelIcons.remove),
                ),
              ],
            ),
          ],
          if (_controllers.length < criteriaMaxCount)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: widget.enabled ? _add : null,
                icon: const PixelIcon(PixelIcons.add),
                label: const Text(AppStrings.battleCriteriaAdd),
              ),
            ),
        ],
      ),
    );
  }
}
