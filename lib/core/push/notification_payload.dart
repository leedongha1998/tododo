/// 알림 payload 해석. 서버가 넣는 키는 `battle_id`와 `kind` 둘뿐이다(design `_shared/fcm.ts`).
///
/// 알림을 탭해 대결 상세를 여는 길은 5단계에서 붙는다. 이 파일은 그때 쓸 순수 함수만 둔다 —
/// 플랫폼 타입이 섞이지 않아 유닛 테스트로 고정할 수 있는 유일한 지점이다.
library;

final _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

/// payload에서 열어야 할 대결 id. 키가 없거나 uuid 모양이 아니면 null이다.
///
/// 모양을 검사하는 이유: 틀린 값을 그대로 조회에 넘기면 서버 오류로만 드러나고, 사용자에게는
/// 알림을 눌렀는데 오류가 뜨는 것으로 보인다. 열 수 없는 알림은 조용히 무시하는 쪽이 맞다.
String? battleIdOf(Map<String, dynamic> data) {
  final value = data['battle_id'];
  if (value is! String) return null;
  final id = value.trim();
  return _uuid.hasMatch(id) ? id : null;
}
