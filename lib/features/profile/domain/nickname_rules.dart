import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/strings.dart';
import '../data/nickname_state.dart';

/// 별명 관문이 무엇을 그릴지.
enum NicknameGateView {
  /// 첫 조회 중. 전체 화면 로더.
  loading,

  /// 아직 확정하지 않았다. 별명 정하기 화면.
  setup,

  /// 확정했거나 조회가 실패했다. 본 화면(탭바).
  shell,
}

/// 관문 판단(design 7.1). **오류를 값보다 먼저 본다** — riverpod의 `AsyncError`는 직전 값을 들고 있어서,
/// 값부터 보면 재조회 실패가 "미확정"으로 읽혀 관문으로 되돌아간다.
///
/// 조회 실패는 통과다(오너 결정 1의 (a)): 관문은 보안 장치가 아니다 — 실명 노출은 서버의 기본 별명과
/// 일괄 덮기가 이미 끊었다. 확정한 사용자가 오프라인으로 켰을 때 "별명 오류 화면"에 막히지 않게 하고,
/// RPC가 깨져도 아무도 못 들어오는 일이 없게 한다. 미확정 사용자는 다음 실행에 다시 본다.
NicknameGateView nicknameGateView(AsyncValue<NicknameState> state) {
  if (state.hasError) return NicknameGateView.shell;
  final value = state.value;
  if (value == null) return NicknameGateView.loading;
  return value.confirmed ? NicknameGateView.shell : NicknameGateView.setup;
}

/// 서버가 거부한 별명 규칙(`check_nickname`의 코드). 사용자가 입력을 고쳐 풀 수 있는 것만 여기에 든다.
enum NicknameRejectionKind { length, chars, reserved, banned }

/// 규칙 위반 하나. [term]은 예약어에 걸렸을 때 서버가 알려 준 말(보이는 모양)이다. 금칙어는 서버가
/// 걸린 말을 돌려주지 않는다(욕설을 화면에 되돌려 보여 주지 않는다, design 2.6).
class NicknameRejection {
  const NicknameRejection(this.kind, {this.term});

  final NicknameRejectionKind kind;
  final String? term;
}

/// 저장 실패를 규칙 위반으로 읽는다. 규칙 위반이 아니면(탈퇴 계정·네트워크·알 수 없는 오류) null —
/// 그때 화면은 칸 옆이 아니라 토스트로 "저장하지 못했다"를 말한다(design 6.4).
NicknameRejection? nicknameRejectionOf(Object error) {
  if (error is! PostgrestException) return null;
  final kind = switch (error.hint) {
    'NICKNAME_LENGTH' => NicknameRejectionKind.length,
    'NICKNAME_CHARS' => NicknameRejectionKind.chars,
    'NICKNAME_RESERVED' => NicknameRejectionKind.reserved,
    'NICKNAME_BANNED' => NicknameRejectionKind.banned,
    _ => null,
  };
  if (kind == null) return null;
  if (kind != NicknameRejectionKind.reserved) return NicknameRejection(kind);
  final details = error.details;
  final term = details is String && details.trim().isNotEmpty ? details.trim() : null;
  return NicknameRejection(kind, term: term);
}

/// 규칙 위반 → 칸 아래 오류 줄 문구. 규칙 자체는 서버에 있고 여기서는 코드에 문장만 붙인다.
String nicknameRejectionMessage(NicknameRejection rejection) {
  return switch (rejection.kind) {
    NicknameRejectionKind.length => AppStrings.nicknameErrorLength,
    NicknameRejectionKind.chars => AppStrings.nicknameErrorChars,
    NicknameRejectionKind.reserved => switch (rejection.term) {
        final term? => AppStrings.nicknameErrorReserved(term),
        null => AppStrings.nicknameErrorReservedGeneric,
      },
    NicknameRejectionKind.banned => AppStrings.nicknameErrorBanned,
  };
}

/// 서버가 공백으로 다루는 글자(공백·탭·줄바꿈·CR·NBSP·전각 공백). `normalize_nickname`과 같은 목록이다.
final _nicknameSpaces = RegExp('[ \t\n\r\u00A0\u3000]+');

/// 글자 수 안내(P1-2)에 쓰는 길이 — 앞뒤 공백을 지우고 연속 공백을 한 칸으로 줄인 뒤 센 값이다.
///
/// **표시에만 쓴다.** 판정은 서버가 하고, 앱은 허용 문자·예약어 검사를 복제하지 않는다(design 원칙 1).
/// 서버(`char_length`)처럼 코드 포인트로 센다(NFC 합치기는 하지 않는다 — 키보드는 완성형을 친다).
int nicknameDisplayLength(String raw) {
  return raw.replaceAll(_nicknameSpaces, ' ').trim().runes.length;
}

/// 별명 길이 상한. 안내 줄의 `n/10`에만 쓴다(입력을 막지 않는다).
const nicknameMaxLength = 10;
