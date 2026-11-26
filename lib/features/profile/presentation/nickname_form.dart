import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/strings.dart';
import '../../../core/widgets/app_loader.dart';
import '../../../core/widgets/keep_words_text.dart';
import '../domain/nickname_rules.dart';
import '../domain/profile_providers.dart';

/// 별명 입력 칸 + 오류 줄 + 규칙 안내·글자 수 + 주 버튼(design 7.2·7.3).
///
/// 관문(별명 정하기)과 프로필(별명 바꾸기)이 같은 위젯을 쓴다. 규칙 검사는 하지 않는다 — 오류 줄은 서버가
/// 돌려준 코드를 문장으로 바꾼 것이다(design 원칙 1).
///
/// 칸에 `maxLength`를 걸지 않는다: 앞뒤 공백까지 세는 칸 길이와 서버가 세는 길이가 다르다. 글자 수(P1-2)는
/// 서버처럼 공백을 정리한 뒤 센 값을 보여 주기만 하고 입력을 막지 않는다.
class NicknameForm extends StatelessWidget {
  const NicknameForm({
    super.key,
    required this.controller,
    required this.errorText,
    required this.saving,
    required this.busy,
    required this.submitLabel,
    required this.onChanged,
    required this.onSubmit,
    this.autofocus = false,
    this.between,
  });

  final TextEditingController controller;

  /// 규칙 위반 문구. 있으면 칸이 오류 상태가 되고 안내 줄 대신 이 줄이 보인다.
  final String? errorText;

  /// 저장 중. 주 버튼 자리에 로더를 그린다.
  final bool saving;

  /// 무언가 진행 중(저장·추천받기·로그아웃). 칸과 버튼을 막는다.
  final bool busy;

  final String submitLabel;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmit;
  final bool autofocus;

  /// 칸과 주 버튼 사이에 둘 것(관문의 "다른 별명 추천받기").
  final Widget? between;

  @override
  Widget build(BuildContext context) {
    final error = errorText;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: controller,
          enabled: !busy,
          autofocus: autofocus,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            labelText: AppStrings.nicknameFieldLabel,
            // 오류가 있으면 안내 줄 자리에 오류 줄이 선다(InputDecorator가 helper를 감춘다).
            error: error == null ? null : KeepWordsText(error),
            helper: const KeepWordsText(AppStrings.nicknameRuleHint),
            counter: Text(
              AppStrings.nicknameLength(nicknameDisplayLength(controller.text)),
            ),
          ),
          onChanged: onChanged,
          // 키보드의 완료 = 주 버튼(design 7.2).
          onSubmitted: busy ? null : (_) => onSubmit(),
        ),
        if (between case final between?) ...[
          const SizedBox(height: 8),
          between,
        ],
        const SizedBox(height: 24),
        FilledButton(
          onPressed: busy ? null : onSubmit,
          child: saving ? const AppLoader.small() : KeepWordsText(submitLabel),
        ),
      ],
    );
  }
}

/// 별명 저장 한 번(관문·프로필 공통). 칸·오류 줄·저장 중 상태를 들고, 실패를 두 갈래로 나눈다.
///
/// - **규칙 위반**(`NICKNAME_*`): 사용자가 고칠 수 있는 것이라 칸 아래 오류 줄로 말하고 칸 내용은 그대로 둔다.
/// - **그 밖**(탈퇴 계정·네트워크·알 수 없음): 다시 시도할 일이라 토스트로 알리고 버튼을 다시 살린다.
mixin NicknameSaving<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  late final TextEditingController nicknameController;
  String? nicknameError;
  bool nicknameSaving = false;

  /// `initState`에서 부른다. 칸에 [initial]을 미리 채운다.
  void initNickname(String initial) {
    nicknameController = TextEditingController(text: initial);
  }

  @override
  void dispose() {
    nicknameController.dispose();
    super.dispose();
  }

  /// 입력이 바뀌면 오류 줄을 지운다(design 7.2). 글자 수도 이 setState로 다시 그린다.
  void onNicknameChanged(String _) {
    setState(() => nicknameError = null);
  }

  /// 칸의 원문을 그대로 서버에 보낸다(다듬기도 서버가 한다). 성공하면 저장된 값, 실패하면 null.
  /// 성공해도 [nicknameSaving]을 내리지 않는다 — 부르는 쪽이 화면을 바꾸는 동안 다시 누를 수 없게 한다.
  Future<String?> saveNickname() async {
    if (nicknameSaving) return null;
    setState(() {
      nicknameSaving = true;
      nicknameError = null;
    });
    try {
      return await ref.read(profileRepositoryProvider).setNickname(nicknameController.text);
    } catch (error) {
      debugPrint('setNickname failed: $error');
      if (!mounted) return null;
      final rejection = nicknameRejectionOf(error);
      setState(() {
        nicknameSaving = false;
        nicknameError = rejection == null ? null : nicknameRejectionMessage(rejection);
      });
      if (rejection == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: KeepWordsText(AppStrings.nicknameSaveFailed)),
        );
      }
      return null;
    }
  }
}
