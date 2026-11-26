/// 내 별명 관문 상태(`get_my_nickname_state()`).
///
/// `profiles`가 아니라 본인만 읽는 서버 테이블(`nickname_states`)에서 온다 — 남의 별명 변경 시점이
/// 보이지 않게 하려는 것이다(design 원칙 4). "확정했다"는 사실은 기기가 아니라 서버가 안다.
class NicknameState {
  const NicknameState({
    required this.nickname,
    required this.confirmed,
    required this.wasReset,
  });

  /// 지금 남에게 보이는 이름. 관문 칸에 미리 채운다(새 계정이면 서버가 만든 무작위 별명).
  final String nickname;

  /// 사용자가 `set_nickname`으로 한 번이라도 확정했는가. false면 관문이 뜬다.
  final bool confirmed;

  /// 서버가 사용자 대신 이름을 덮었는가(기존 사용자 일괄 덮기). true면 관문에 이유 안내가 함께 뜬다.
  final bool wasReset;

  /// 키가 빠지거나 타입이 어긋나면 **미확정**으로 읽는다 — 관문을 한 번 더 보여 주는 쪽이
  /// 별명을 정하지 않은 사용자를 조용히 통과시키는 쪽보다 낫다. 이름이 없으면 빈 칸이다.
  factory NicknameState.fromMap(Map<String, dynamic> map) {
    final nickname = map['nickname'];
    final confirmed = map['confirmed'];
    final wasReset = map['was_reset'];
    return NicknameState(
      nickname: nickname is String ? nickname : '',
      confirmed: confirmed is bool && confirmed,
      wasReset: wasReset is bool && wasReset,
    );
  }
}
