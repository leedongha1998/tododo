import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/strings.dart';
import '../../../core/theme/pixel_icons.dart';
import '../../../core/theme/retro_palette.dart';
import '../../../core/widgets/pixel_frame.dart';
import '../../../core/widgets/pixel_icon.dart';
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final todosAsync = ref.watch(todosProvider);

    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.todoTitle)),
      body: todosAsync.when(
        data: (todos) {
          if (todos.isEmpty) {
            return const StatusMessage.empty(
              icon: PixelIcons.todo,
              message: AppStrings.emptyTodos,
              fill: true,
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: todos.length,
            itemBuilder: (context, index) {
              final todo = todos[index];
              final tile = ListTile(
                leading: Checkbox(
                  value: todo.isDone,
                  onChanged: (_) => _toggleDone(context, ref, todo),
                ),
                title: Text(
                  todo.title,
                  style: todo.isDone
                      ? const TextStyle(
                          decoration: TextDecoration.lineThrough,
                          color: RetroPalette.inkMuted,
                        )
                      : null,
                ),
                onTap: () => _openEditDialog(context, ref, todo),
                trailing: IconButton(
                  icon: const PixelIcon(PixelIcons.delete),
                  tooltip: AppStrings.delete,
                  onPressed: () => _deleteTodo(context, ref, todo),
                ),
              );
              // 안 한 일은 떠 있고, 끝낸 일은 가라앉는다. 면색·높낮이·체크·취소선으로 한눈에 갈린다.
              return Padding(
                padding: EdgeInsets.only(bottom: index == todos.length - 1 ? 0 : 8),
                child: todo.isDone
                    ? PixelFrame.inset(padding: EdgeInsets.zero, child: tile)
                    : PixelFrame.raised(padding: EdgeInsets.zero, child: tile),
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
        onPressed: () => _openAddDialog(context, ref),
        child: const PixelIcon(PixelIcons.add),
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
        title: Text(dialogTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: AppStrings.todoInputHint),
          onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(AppStrings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text(AppStrings.save),
          ),
        ],
      );
    },
  );
}
