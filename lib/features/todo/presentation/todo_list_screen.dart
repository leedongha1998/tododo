import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/strings.dart';
import '../../auth/domain/auth_providers.dart';
import '../../battle/presentation/battle_recruits_screen.dart';
import '../../battle/presentation/create_battle_screen.dart';
import '../../battle/presentation/my_battles_screen.dart';
import '../../profile/presentation/profile_screen.dart';
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
      appBar: AppBar(
        title: const Text(AppStrings.appName),
        actions: [
          IconButton(
            icon: const Icon(Icons.mail_outline),
            tooltip: AppStrings.battleRecruits,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const BattleRecruitsScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.list_alt),
            tooltip: AppStrings.battleMyBattles,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const MyBattlesScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.sports_kabaddi),
            tooltip: AppStrings.battleCreate,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CreateBattleScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.person_outline),
            tooltip: AppStrings.profileTitle,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ProfileScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: AppStrings.logout,
            onPressed: () => ref.read(authRepositoryProvider).signOut(),
          ),
        ],
      ),
      body: todosAsync.when(
        data: (todos) {
          if (todos.isEmpty) {
            return Center(
              child: Text(AppStrings.emptyTodos, textAlign: TextAlign.center),
            );
          }
          return ListView.builder(
            itemCount: todos.length,
            itemBuilder: (context, index) {
              final todo = todos[index];
              return ListTile(
                leading: Checkbox(
                  value: todo.isDone,
                  onChanged: (_) => _toggleDone(context, ref, todo),
                ),
                title: Text(
                  todo.title,
                  style: todo.isDone
                      ? const TextStyle(decoration: TextDecoration.lineThrough)
                      : null,
                ),
                onTap: () => _openEditDialog(context, ref, todo),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: AppStrings.delete,
                  onPressed: () => _deleteTodo(context, ref, todo),
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) {
          debugPrint('todosProvider error: $error');
          return Center(child: Text(AppStrings.loadTodosFailed));
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openAddDialog(context, ref),
        child: const Icon(Icons.add),
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
