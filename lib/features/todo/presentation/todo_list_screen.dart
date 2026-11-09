import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/strings.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_panel.dart';
import '../../../core/widgets/keep_words_text.dart';
import '../../../core/widgets/status_message.dart';
import '../../auth/domain/auth_providers.dart';
import '../data/todo.dart';
import '../domain/due_date_rules.dart';
import '../domain/todo_providers.dart';

class TodoListScreen extends ConsumerWidget {
  const TodoListScreen({super.key});

  Future<void> _openAddDialog(BuildContext context, WidgetRef ref) async {
    final draft = await _showTodoInputDialog(context, dialogTitle: AppStrings.addTodo);
    if (draft == null || draft.title.isEmpty) return;

    try {
      final userId = ref.read(authRepositoryProvider).currentUser!.id;
      await ref
          .read(todoRepositoryProvider)
          .addTodo(userId, draft.title, dueAt: draft.dueAt);
      ref.invalidate(todosProvider);
    } catch (e) {
      debugPrint('addTodo failed: $e');
      if (context.mounted) _showErrorSnackBar(context, AppStrings.saveTodoFailed);
    }
  }

  Future<void> _openEditDialog(BuildContext context, WidgetRef ref, Todo todo) async {
    final draft = await _showTodoInputDialog(
      context,
      dialogTitle: AppStrings.editTodo,
      initialTitle: todo.title,
      initialDueAt: todo.dueAt?.toLocal(),
    );
    if (draft == null || draft.title.isEmpty) return;
    // 제목이 그대로여도 기한이 바뀌면 저장한다. **둘 다** 그대로일 때만 건너뛴다 —
    // 기한만 고친 경우가 조용히 버려지면 안 된다(spec).
    final sameTitle = draft.title == todo.title;
    final sameDue = _sameInstant(draft.dueAt, todo.dueAt);
    if (sameTitle && sameDue) return;

    try {
      await ref
          .read(todoRepositoryProvider)
          .updateTodo(todo.id, title: draft.title, dueAt: draft.dueAt);
      ref.invalidate(todosProvider);
    } catch (e) {
      debugPrint('updateTodo failed: $e');
      if (context.mounted) _showErrorSnackBar(context, AppStrings.saveTodoFailed);
    }
  }

  Future<void> _toggleDone(BuildContext context, WidgetRef ref, Todo todo) async {
    try {
      await ref.read(todoRepositoryProvider).setDone(todo.id, !todo.isDone);
      ref.invalidate(todosProvider);
    } catch (e) {
      debugPrint('setDone failed: $e');
      if (context.mounted) _showErrorSnackBar(context, AppStrings.saveTodoFailed);
    }
  }

  Future<void> _deleteTodo(BuildContext context, WidgetRef ref, Todo todo) async {
    try {
      await ref.read(todoRepositoryProvider).deleteTodo(todo.id);
      ref.invalidate(todosProvider);
    } catch (e) {
      debugPrint('deleteTodo failed: $e');
      if (context.mounted) _showErrorSnackBar(context, AppStrings.deleteTodoFailed);
    }
  }

  /// 기한이 그대로인지. 둘 다 null도 "같다"다. 저장된 값은 UTC, 대화상자의 값은 local이라
  /// 절대 시각으로 비교한다.
  bool _sameInstant(DateTime? a, DateTime? b) {
    if (a == null || b == null) return a == null && b == null;
    return a.toUtc().isAtSameMomentAs(b.toUtc());
  }

  void _showErrorSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: KeepWordsText(message)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final todosAsync = ref.watch(todosProvider);

    return Scaffold(
      appBar: AppBar(title: const KeepWordsText(AppStrings.todoTitle)),
      body: todosAsync.when(
        data: (todos) {
          if (todos.isEmpty) {
            return const StatusMessage.empty(
              icon: AppIcons.todoOutlined,
              message: AppStrings.emptyTodos,
              fill: true,
            );
          }
          // 모든 줄이 같은 "지금"을 쓰도록 한 번만 읽는다. 분 단위 타이머로 다시 그리지 않으므로
          // 화면을 켜 둔 채 두면 낡지만, 다시 들어오면 맞는다(spec "표시 갱신").
          final now = DateTime.now();
          return ListView.builder(
            // 좌우 20·위 16, 아래는 FAB가 마지막 줄을 가리지 않게(redesign design 5.5 기준 화면 1, 후속 결정 4).
            padding: const EdgeInsets.fromLTRB(20, 16, 20, AppTheme.fabClearance),
            itemCount: todos.length,
            itemBuilder: (context, index) {
              final todo = todos[index];
              // 완료한 할 일에는 남은 시간을 표시하지 않는다(기한이 있어도, 넘겼어도) —
              // 끝낸 일에 붙는 빨간 "지남"은 아무 행동도 유도하지 않는다(spec).
              // 문구와 색은 formatDueLabel이 **함께** 판정한다. 여기서 "지났는지"를 다시 따지면
              // 경계(기한까지 1초 미만)에서 둘이 어긋난다.
              final dueAt = todo.isDone ? null : todo.dueAt?.toLocal();
              final due = dueAt == null ? null : formatDueLabel(dueAt, now);
              final tile = ListTile(
                minTileHeight: 60,
                // 1.5배에서 글자 칸을 넓히려고 좌우 여백·간격을 줄였다(redesign 후속 2 W3, 글자 칸 150 → 198dp).
                // 체크박스·삭제 버튼은 48dp 터치 상자를 그대로 갖고, 그 상자 안 여백(12)이 카드 가장자리와의 시각 간격 16을 만든다.
                // 체크박스는 24/18배로 그려 터치 상자도 64dp로 커지므로 간격 8이면 글자가 그 상자에 맞닿고 겹치지 않는다
                // (글자 앞을 눌러도 체크되지 않는다 — 테스트 고정).
                contentPadding: const EdgeInsetsDirectional.symmetric(horizontal: 4),
                horizontalTitleGap: 8,
                minLeadingWidth: 0,
                // Flutter Checkbox는 18dp 고정이라 이 자리에서만 24dp로 키운다(redesign plan "설계와 다른 점" 3).
                // 터치 영역 48은 materialTapTargetSize.padded가 유지한다.
                leading: Transform.scale(
                  scale: 24 / 18,
                  child: Checkbox(
                    value: todo.isDone,
                    onChanged: (_) => _toggleDone(context, ref, todo),
                  ),
                ),
                title: KeepWordsText(
                  todo.title,
                  style: todo.isDone
                      ? const TextStyle(
                          decoration: TextDecoration.lineThrough,
                          color: AppPalette.inkMuted,
                          decorationColor: AppPalette.inkMuted,
                        )
                      : null,
                ),
                // 남은 시간은 제목 아래 둘째 줄이다 — 제목 칸(198dp)을 1dp도 깎지 않는다.
                // 기한이 없거나 완료한 줄은 subtitle이 null이라 지금과 똑같은 한 줄 타일이 된다
                // (minTileHeight를 올리지 않는 이유: 올리면 기한 없는 줄까지 같이 커진다).
                subtitle: due == null
                    ? null
                    : KeepWordsText(
                        due.label,
                        style: Theme.of(context).textTheme.bodySmall!
                            .merge(AppText.tabular)
                            .copyWith(
                              color: due.overdue
                                  ? AppPalette.danger
                                  : AppPalette.inkMuted,
                            ),
                      ),
                trailing: IconButton(
                  icon: const Icon(AppIcons.delete, color: AppPalette.inkMuted),
                  tooltip: AppStrings.delete,
                  onPressed: () => _deleteTodo(context, ref, todo),
                ),
              );
              void openEdit() => _openEditDialog(context, ref, todo);
              // 안 한 일은 떠 있고, 끝낸 일은 가라앉는다. 면색·높낮이·체크·취소선으로 한눈에 갈린다.
              // 누르기(수정)는 묶음이 받아 떠 있는 카드는 누르는 동안 두께가 꺼진다. 체크박스·삭제 버튼은 안쪽이라
              // 제스처 경쟁에서 먼저 이긴다.
              return Padding(
                padding: EdgeInsets.only(bottom: index == todos.length - 1 ? 0 : 12),
                child: todo.isDone
                    ? AppPanel.inset(padding: EdgeInsets.zero, onTap: openEdit, child: tile)
                    : AppPanel.raised(padding: EdgeInsets.zero, onTap: openEdit, child: tile),
              );
            },
          );
        },
        loading: () => const StatusMessage.loading(fill: true),
        error: (error, stackTrace) {
          debugPrint('todosProvider error: $error');
          return const StatusMessage.error(message: AppStrings.loadTodosFailed, fill: true);
        },
      ),
      floatingActionButton: FloatingActionButton(
        // 찾기 탭 FAB와 같은 이유로 고유 태그를 준다(기본값이면 Hero 태그가 겹친다).
        heroTag: 'addTodoFab',
        onPressed: () => _openAddDialog(context, ref),
        child: const Icon(AppIcons.add),
      ),
    );
  }
}

/// 추가·수정 대화상자가 돌려주는 값. null은 취소다.
class TodoDraft {
  const TodoDraft({required this.title, required this.dueAt});

  final String title;

  /// **기기 시간대의 local DateTime**(분 단위, 초·밀리초는 0). null이면 기한 없음.
  /// UTC 변환은 레포지토리가 저장 직전에 한다.
  final DateTime? dueAt;
}

Future<TodoDraft?> _showTodoInputDialog(
  BuildContext context, {
  required String dialogTitle,
  String initialTitle = '',
  DateTime? initialDueAt,
}) {
  return showDialog<TodoDraft>(
    context: context,
    builder: (context) => _TodoInputDialog(
      dialogTitle: dialogTitle,
      initialTitle: initialTitle,
      initialDueAt: initialDueAt,
    ),
  );
}

/// 추가와 수정이 공유하는 대화상자. 기한은 사용자가 고르는 동안 화면에 남아야 하므로
/// 상태가 필요하다(지금까지는 무상태 `AlertDialog`였다).
///
/// **기한을 쓰지 않는 사용자의 타수가 늘지 않는다**(design 원칙 5): 입력 칸이 여전히
/// `autofocus`이고 `onSubmitted`가 그대로 저장으로 간다 — 제목 적고 엔터면 끝이다. 기한 줄은
/// 입력 칸 아래에 있고 날짜를 고르라고 막는 단계가 없다.
class _TodoInputDialog extends StatefulWidget {
  const _TodoInputDialog({
    required this.dialogTitle,
    required this.initialTitle,
    this.initialDueAt,
  });

  final String dialogTitle;
  final String initialTitle;
  final DateTime? initialDueAt;

  @override
  State<_TodoInputDialog> createState() => _TodoInputDialogState();
}

class _TodoInputDialogState extends State<_TodoInputDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialTitle);
  DateTime? _dueAt;

  @override
  void initState() {
    super.initState();
    _dueAt = widget.initialDueAt;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.of(context).pop(
      TodoDraft(title: _controller.text.trim(), dueAt: _dueAt),
    );
  }

  Future<void> _pickDue() async {
    final now = DateTime.now();
    final base = _dueAt ?? now;
    // 규칙상의 한도가 아니라 달력 위젯이 요구하는 범위다(spec "기한의 하한·상한을 두지 않는다").
    // 지난 시각도 기한으로 넣을 수 있어야 하므로 firstDate를 오늘로 두지 않고, 이미 가진 기한이
    // 범위를 벗어나면 그쪽으로 넓혀 수정이 막히지 않게 한다.
    var firstDate = DateTime(now.year - 1);
    var lastDate = DateTime(now.year + 5, 12, 31);
    final baseDay = DateTime(base.year, base.month, base.day);
    if (baseDay.isBefore(firstDate)) firstDate = baseDay;
    if (baseDay.isAfter(lastDate)) lastDate = baseDay;

    final date = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: firstDate,
      lastDate: lastDate,
    );
    // 날짜를 취소하면 아무것도 바뀌지 않는다(취소는 취소다).
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      // 날짜만 생각하고 들어온 사용자를 위해 23:59. 확인만 눌러도 "그 날 안에"가 된다(spec).
      initialTime: _dueAt == null
          ? const TimeOfDay(hour: 23, minute: 59)
          : TimeOfDay.fromDateTime(_dueAt!),
    );
    if (time == null || !mounted) return;

    // 초·밀리초는 0이다(분 단위). 수정 시 "안 바뀌었는지" 비교가 흔들리지 않는다.
    setState(() {
      _dueAt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  @override
  Widget build(BuildContext context) {
    final dueAt = _dueAt;
    return AlertDialog(
      title: KeepWordsText(widget.dialogTitle),
      // 1.5배 글자 + 키보드에서 내용이 잘리지 않게 감싼다(기한 줄만큼 높이가 늘었다).
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: const InputDecoration(hintText: AppStrings.todoInputHint),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 8),
            if (dueAt == null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _pickDue,
                  icon: const Icon(AppIcons.clock),
                  label: const KeepWordsText(AppStrings.todoDueAdd),
                ),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: _pickDue,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: KeepWordsText(
                          '${AppStrings.todoDueLabel} · ${formatDueValue(dueAt)}',
                        ),
                      ),
                    ),
                  ),
                  // 기한 없음으로 되돌리는 길. 없으면 잘못 고른 기한을 지우는 유일한 방법이
                  // "할 일을 삭제하고 다시 적기"가 된다(spec).
                  IconButton(
                    icon: const Icon(AppIcons.close, color: AppPalette.inkMuted),
                    tooltip: AppStrings.todoDueClear,
                    onPressed: () => setState(() => _dueAt = null),
                  ),
                ],
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const KeepWordsText(AppStrings.cancel),
        ),
        FilledButton(
          onPressed: _submit,
          child: const KeepWordsText(AppStrings.save),
        ),
      ],
    );
  }
}
