---
name: android-json-optstring-null
description: 안드로이드(AOSP) org.json의 optString은 값이 명시적 null이면 fallback이 아니라 "null" 네 글자를 돌려준다 — Dart가 만든 JSON을 네이티브가 읽는 모든 경계에서 걸린다
metadata:
  type: reference
---

Dart가 만든 JSON을 Kotlin(`org.json`)이 읽는 경계에서 걸리는 함정이다. `home-widget` 2단계
리뷰(2026-11-05)에서 실제 버그로 잡혔다.

AOSP의 `JSONObject.optString(name, fallback)`은 upstream org.json과 **다르게** 동작한다:
`opt(name)`이 `JSONObject.NULL`을 주면 `JSON.toString`이 `"null"`이라는 **네 글자 문자열**을
돌려주고, `fallback`은 **키가 아예 없을 때만** 쓰인다. 그래서 `{"centerText": null}`을 읽으면
빈 문자열이 아니라 `null`이 UI에 그려진다(위젯 가운데에 `null`이 떴다).

- `optInt`/`optLong`/`optJSONArray`/`optJSONObject`는 명시적 null에 fallback·null을 제대로 준다.
  **문자열만 다르다.**
- 막는 방법은 둘 다 쓴다: ① Dart `toJson()`에서 **null인 키를 아예 싣지 않는다**
  (`if (x != null) 'x': x` — `fromJson`은 없는 키를 null로 읽으므로 왕복이 그대로다),
  ② Kotlin에 `fun JSONObject.text(name, fallback="") = if (isNull(name)) fallback else optString(name, fallback)`
  헬퍼를 두고 모든 문자열을 그것으로 읽는다.
- **네이티브는 이 저장소에서 테스트하지 않으므로**, Dart 쪽 "null 키가 들어가지 않는다" 유닛
  테스트가 유일한 자동 방어선이다. 그 테스트를 함께 박아 둘 것.

**Why:** 증상이 "정상 상태에서만 화면이 깨진다"로 나타나 실기기에 올려야 보이고, 원인이 언어
경계의 표준 구현 차이라 코드만 읽어서는 찾기 어렵다.

**How to apply:** Dart↔네이티브로 JSON을 넘기는 새 경계(위젯 캐시, 네이티브 콜백 payload 등)를
만들 때 선제적으로 적용한다. 관련: [[supabase-background-isolate-session]]
