import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/strings.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/widgets/app_panel.dart';
import '../../../core/widgets/keep_words_text.dart';
import '../../auth/domain/auth_providers.dart';
import '../data/nickname_state.dart';
import '../domain/profile_providers.dart';
import 'nickname_form.dart';

/// 별명 정하기(관문, design 7.2). 로그인 직후 본 화면 전에 **한 번** 뜬다 — 확정했다는 사실은 서버가 안다.
///
/// 서버가 만든 무작위 별명이 칸에 **미리 채워져** 있어 그대로 한 번 누르면 지나간다(오너 결정 1).
/// 뒤로 가기 화살표가 없다. 시스템 뒤로 가기는 평소처럼 앱을 닫는다. 다른 계정으로 잘못 들어왔을 때를 위해
/// 로그아웃이 이 화면의 유일한 출구다(spec P0-3).
class NicknameSetupScreen extends ConsumerStatefulWidget {
  const NicknameSetupScreen({super.key, required this.userId, required this.state});

  final String userId;
  final NicknameState state;

  @override
  ConsumerState<NicknameSetupScreen> createState() => _NicknameSetupScreenState();
}

class _NicknameSetupScreenState extends ConsumerState<NicknameSetupScreen> with NicknameSaving {
  bool _suggesting = false;
  bool _loggingOut = false;

  bool get _busy => nicknameSaving || _suggesting || _loggingOut;

  @override
  void initState() {
    super.initState();
    initNickname(widget.state.nickname);
  }

  /// 확정. 성공하면 상태를 다시 읽게 하고, 관문이 `confirmed`를 보고 본 화면으로 바뀐다(토스트 없음).
  Future<void> _confirm() async {
    final saved = await saveNickname();
    if (saved == null || !mounted) return;
    ref.invalidate(myNicknameStateProvider(widget.userId));
    ref.invalidate(myProfileProvider);
    // 관문이 바뀌면 이 화면은 사라진다. 다시 읽은 상태가 어떤 이유로든 "미확정"이면 이 화면이 그대로
    // 남으므로, 버튼이 로더에 갇히지 않게 내려 둔다(다시 눌러도 같은 이름의 재확정이라 무해하다).
    if (mounted) setState(() => nicknameSaving = false);
  }

  /// P1-1. 결과로 칸을 덮고 오류 줄을 지운다. 실패하면 칸은 그대로 두고 토스트만 띄운다.
  Future<void> _suggest() async {
    setState(() => _suggesting = true);
    try {
      final suggestion = await ref.read(profileRepositoryProvider).suggestNickname();
      if (!mounted) return;
      setState(() {
        nicknameController.text = suggestion;
        nicknameError = null;
        _suggesting = false;
      });
    } catch (error) {
      debugPrint('suggestNickname failed: $error');
      if (!mounted) return;
      setState(() => _suggesting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: KeepWordsText(AppStrings.nicknameSuggestFailed)),
      );
    }
  }

  /// 관문에서는 로그아웃이 유일한 출구라 실패를 받는다(프로필의 로그아웃은 받지 않는다).
  /// 성공하면 세션이 사라져 `AuthGate`가 로그인 화면으로 바꾼다.
  Future<void> _logout() async {
    setState(() => _loggingOut = true);
    try {
      await ref.read(authRepositoryProvider).signOut();
    } catch (error) {
      debugPrint('signOut failed: $error');
      if (!mounted) return;
      setState(() => _loggingOut = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: KeepWordsText(AppStrings.logoutFailed)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const KeepWordsText(AppStrings.nicknameSetupTitle),
      ),
      body: ListView(
        // 화면 가장자리 20(redesign design 4.1). AI 동의 화면과 같은 문법이다.
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          KeepWordsText(AppStrings.nicknameSetupIntro, style: textTheme.bodyMedium),
          // 이름이 왜 바뀌었는지 말하지 않으면 낯선 이름이 "해킹당했다"로 읽힌다(spec P0-3).
          // 면은 이 묶음 하나뿐이다(줄마다 면을 두지 않는다).
          if (widget.state.wasReset) ...[
            const SizedBox(height: 16),
            AppPanel.flat(
              title: AppStrings.nicknameResetNoticeTitle,
              child: KeepWordsText(AppStrings.nicknameResetNoticeBody, style: textTheme.bodyMedium),
            ),
          ],
          const SizedBox(height: 24),
          NicknameForm(
            controller: nicknameController,
            errorText: nicknameError,
            saving: nicknameSaving,
            busy: _busy,
            submitLabel: AppStrings.nicknameConfirm,
            onChanged: onNicknameChanged,
            onSubmit: _confirm,
            // 자동 포커스는 하지 않는다 — 대부분 그대로 누르고, 키보드가 안내와 버튼을 가리지 않게 한다.
            between: Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: _busy ? null : _suggest,
                icon: const Icon(AppIcons.retry),
                label: const KeepWordsText(AppStrings.nicknameSuggestAnother),
              ),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : _logout,
            icon: const Icon(AppIcons.logout),
            label: const KeepWordsText(AppStrings.logout),
          ),
        ],
      ),
    );
  }
}
