import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/strings.dart';
import '../../../core/widgets/keep_words_text.dart';
import 'nickname_form.dart';

/// 프로필에서 별명 바꾸기(design 7.3, spec P0-6). 관문과 **같은 RPC·같은 규칙**이다.
///
/// 대화상자가 아니라 화면인 이유: 저장 실패 토스트가 대화상자 장벽 밑에 깔리지 않게 하려는 것이다.
/// 성공하면 `true`로 닫히고, 토스트와 프로필 다시 읽기는 부른 쪽(프로필)이 한다.
/// 횟수 제한·안내가 없다(오너 결정 7). "다른 별명 추천받기"는 두지 않는다(spec P1-1은 첫 화면만).
class NicknameEditScreen extends ConsumerStatefulWidget {
  const NicknameEditScreen({super.key, required this.currentNickname});

  final String currentNickname;

  @override
  ConsumerState<NicknameEditScreen> createState() => _NicknameEditScreenState();
}

class _NicknameEditScreenState extends ConsumerState<NicknameEditScreen> with NicknameSaving {
  @override
  void initState() {
    super.initState();
    initNickname(widget.currentNickname);
  }

  Future<void> _save() async {
    final saved = await saveNickname();
    if (saved == null || !mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const KeepWordsText(AppStrings.nicknameEditTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          KeepWordsText(
            AppStrings.nicknameEditIntro,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          NicknameForm(
            controller: nicknameController,
            errorText: nicknameError,
            saving: nicknameSaving,
            busy: nicknameSaving,
            submitLabel: AppStrings.save,
            onChanged: onNicknameChanged,
            onSubmit: _save,
            // 바꾸러 들어온 화면이라 바로 칠 수 있게 한다(관문은 하지 않는다).
            autofocus: true,
          ),
        ],
      ),
    );
  }
}
