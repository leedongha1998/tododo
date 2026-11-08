import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/strings.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_panel.dart';
import '../../../core/widgets/keep_words_text.dart';
import '../../../core/widgets/status_message.dart';
import '../../auth/domain/auth_providers.dart';
import '../data/todo.dart';
import '../domain/todo_providers.dart';

class TodoListScreen extends ConsumerWidget {
  const TodoListScreen({super.key});

  Future<void> _openAddDialog(BuildContext context, WidgetRef ref) async {
    final title = await _showTodoInputDialog(context, dialogTitle: AppStrings.addTodo);
    if (title == null || title.isEmpty) return;

    try {
      final userId = ref.read(authRepositoryProvider).currentUser!.id;
      await ref.read(todoRepositoryProvider).addTodo(userId, title);
      ref.invalidate(todosProvider);
    } catch (e) {
      debugPrint('addTodo failed: $e');
      if (context.mounted) _showErrorSnackBar(context, AppStrings.saveTodoFailed);
    }
  }

  Future<void> _openEditDialog(BuildContext context, WidgetRef ref, Todo todo) async {
    final title = await _showTodoInputDialog(
      context,
      dialogTitle: AppStrings.editTodo,
      initialValue: todo.title,
    );
    if (title == null || title.isEmpty || title == todo.title) return;

    try {
      await ref.read(todoRepositoryProvider).updateTitle(todo.id, title);
      ref.invalidate(todosProvider);
    } catch (e) {
      debugPrint('updateTitle failed: $e');
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
          return ListView.builder(
            // 좌우 20·위 16, 아래는 FAB가 마지막 줄을 가리지 않게(redesign design 5.5 기준 화면 1, 후속 결정 4).
            padding: const EdgeInsets.fromLTRB(20, 16, 20, AppTheme.fabClearance),
            itemCount: todos.length,
            itemBuilder: (context, index) {
              final todo = todos[index];
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

Future<String?> _showTodoInputDialog(
  BuildContext context, {
  required String dialogTitle,
  String initialValue = '',
}) {
  final controller = TextEditingController(text: initialValue);
  return showDialog<String>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: KeepWordsText(dialogTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: AppStrings.todoInputHint),
          onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const KeepWordsText(AppStrings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const KeepWordsText(AppStrings.save),
          ),
        ],
      );
    },
  );
}
