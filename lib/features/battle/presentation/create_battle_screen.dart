import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/strings.dart';
import '../data/profile.dart';
import '../domain/battle_providers.dart';

class CreateBattleScreen extends ConsumerStatefulWidget {
  const CreateBattleScreen({super.key});

  @override
  ConsumerState<CreateBattleScreen> createState() => _CreateBattleScreenState();
}

class _CreateBattleScreenState extends ConsumerState<CreateBattleScreen> {
  final _searchController = TextEditingController();
  final _titleController = TextEditingController();

  List<Profile> _searchResults = const [];
  bool _isSearching = false;
  Profile? _selectedOpponent;
  String _type = 'speed';
  bool _isSubmitting = false;

  @override
  void dispose() {
    _searchController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) {
      setState(() => _searchResults = const []);
      return;
    }

    setState(() => _isSearching = true);
    try {
      final results = await ref.read(battleRepositoryProvider).searchProfiles(query.trim());
      if (!mounted || _searchController.text.trim() != query.trim()) return;
      setState(() => _searchResults = results);
    } catch (e) {
      debugPrint('searchProfiles failed: $e');
      if (mounted) _showSnackBar(AppStrings.battleSearchFailed);
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  void _selectOpponent(Profile profile) {
    setState(() {
      _selectedOpponent = profile;
      _searchResults = const [];
      _searchController.clear();
    });
  }

  Future<void> _submit() async {
    final opponent = _selectedOpponent;
    final title = _titleController.text.trim();
    if (opponent == null || title.isEmpty) return;

    setState(() => _isSubmitting = true);
    try {
      await ref.read(battleRepositoryProvider).createBattle(
            opponentId: opponent.id,
            type: _type,
            title: title,
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      _showSnackBar(AppStrings.battleInviteSent);
    } catch (e) {
      debugPrint('createBattle failed: $e');
      if (mounted) _showSnackBar(AppStrings.battleInviteFailed);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit =
        _selectedOpponent != null && _titleController.text.trim().isNotEmpty && !_isSubmitting;

    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.battleCreate)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_selectedOpponent == null) ...[
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(hintText: AppStrings.battleOpponentSearchHint),
              onChanged: _search,
            ),
            const SizedBox(height: 8),
            if (_isSearching) const Center(child: CircularProgressIndicator())
            else if (_searchController.text.trim().isNotEmpty && _searchResults.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(AppStrings.battleOpponentEmpty),
              )
            else
              ..._searchResults.map(
                (profile) => ListTile(
                  title: Text(profile.displayName),
                  onTap: () => _selectOpponent(profile),
                ),
              ),
          ] else ...[
            Row(
              children: [
                Expanded(
                  child: Chip(label: Text(_selectedOpponent!.displayName)),
                ),
                TextButton(
                  onPressed: () => setState(() => _selectedOpponent = null),
                  child: const Text(AppStrings.battleChangeOpponent),
                ),
              ],
            ),
            const SizedBox(height: 24),
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
            FilledButton(
              onPressed: canSubmit ? _submit : null,
              child: _isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(AppStrings.battleInviteSend),
            ),
          ],
        ],
      ),
    );
  }
}
