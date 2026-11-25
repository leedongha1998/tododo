/// 이 계정의 로그인 수단(kakao-login spec P0-4). 본인 프로필에만 보인다.
///
/// 지금 있는 두 값뿐이다 — 계정 연결·공급자 목록 같은 추상화를 미리 만들지 않는다(design §5.4).
enum LoginMethod { google, kakao }

/// 세션의 `User.appMetadata`에서 로그인 수단을 읽는다(design 흐름 3).
///
/// `app_metadata`는 서버(GoTrue)가 쓰고 사용자가 바꿀 수 없으며, 계정 연결이 없으므로(결정 29) 한
/// 계정의 공급자는 평생 하나다. 규칙:
/// - `provider`가 `google`/`kakao`면 그 값. `provider`가 다른 값(`email` 등)이면 null.
/// - `provider`가 없으면 `providers` 목록이 **정확히 하나**이고 그것이 둘 중 하나일 때만 그 값.
/// - 그 밖은 null — 화면은 줄을 그리지 않는다(잘못된 안내보다 없는 편이 낫다).
LoginMethod? loginMethodFrom(Map<String, dynamic>? appMetadata) {
  if (appMetadata == null) return null;
  final provider = appMetadata['provider'];
  if (provider != null) return _methodOf(provider);
  final providers = appMetadata['providers'];
  if (providers is List && providers.length == 1) return _methodOf(providers.single);
  return null;
}

LoginMethod? _methodOf(Object? value) => switch (value) {
  'google' => LoginMethod.google,
  'kakao' => LoginMethod.kakao,
  _ => null,
};
