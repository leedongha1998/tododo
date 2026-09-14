import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/strings.dart';
import '../../../core/widgets/pixel_loader.dart';
import '../domain/battle_providers.dart';

class CreateBattleScreen extends ConsumerStatefulWidget {
  const CreateBattleScreen({super.key});

  @override
  ConsumerState<CreateBattleScreen> createState() => _CreateBattleScreenState();
}

class _CreateBattleScreenState extends ConsumerState<CreateBattleScreen> {
  final _titleController = TextEditingController();

  String _type = 'speed';
  // 기본 3일. 하루는 촉박하고 일주일은 늘어진다.
  int _durationHours = 72;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;

    setState(() => _isSubmitting = true);
    try {
      await ref.read(battleRepositoryProvider).createBattle(
            type: _type,
            title: title,
            durationHours: _durationHours,
          );
      ref.invalidate(openRecruitsProvider);
      ref.invalidate(myRecruitsProvider);
      if (!mounted) return;
      Navigator.of(context).pop();
      _showSnackBar(AppStrings.battleRecruitSubmitted);
    } catch (e) {
      debugPrint('createBattle failed: $e');
      if (mounted) _showSnackBar(AppStrings.battleRecruitSubmitFailed);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit = _titleController.text.trim().isNotEmpty && !_isSubmitting;

    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.battleCreate)),
      body: ListView(
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
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 24),
          Text(AppStrings.battleDuration, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 24, label: Text(AppStrings.battleDuration1Day)),
              ButtonSegment(value: 72, label: Text(AppStrings.battleDuration3Days)),
              ButtonSegment(value: 168, label: Text(AppStrings.battleDuration7Days)),
            ],
            selected: {_durationHours},
            onSelectionChanged: (selection) => setState(() => _durationHours = selection.first),
          ),
          const SizedBox(height: 8),
          Text(
            AppStrings.battleDurationNotice,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: canSubmit ? _submit : null,
            child: _isSubmitting
                ? const PixelLoader.small()
                : const Text(AppStrings.battleRecruitSubmit),
          ),
        ],
      ),
    );
  }
}
