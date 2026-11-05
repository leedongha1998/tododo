---
name: cross-language-rule-review
description: 같은 규칙이 Dart와 Kotlin(네이티브)에 각각 적어진 코드를 리뷰할 때 — 전수 대조 스크립트 + 플랫폼 JSON의 null 기본값 확인
metadata:
  type: feedback
---

같은 판단 규칙이 두 언어에 각각 옮겨 적힌 변경(예: 위젯의 "몇 줄 그리고 그 외 N개")은 **눈으로 비교하지 말고
양쪽 공식을 스크래치 Dart 파일에 복사해 입력 전 조합을 돌려 대조**한다. 어긋난 조합이 나오면 그것이 **Dart가
만들 수 있는 입력으로 도달 가능한지**까지 함께 표시해야 "실제 버그"와 "잠재적 불일치"를 가를 수 있다.

Dart↔네이티브가 JSON 캐시로 값을 주고받으면 **null 키의 플랫폼 기본값**을 반드시 확인한다. 안드로이드(AOSP)
`org.json`의 `optString(name, fallback)`은 upstream과 달라 **명시적 null에 fallback을 돌려주지 않고 `"null"`
문자열을 돌려준다**(fallback은 키가 아예 없을 때만). Dart가 `null`을 그대로 직렬화하는 선택적 필드가 있으면
네이티브에서 "빈 값" 분기가 통째로 뒤집힌다.

**Why:** 2026-11-05 home-widget 1~3단계 리뷰에서 `visibleRows`는 전수 대조로 "도달 불가 1종"까지 가려낼 수
있었고, 같은 리뷰에서 `optString("centerText","")`가 정상 상태의 위젯을 통째로 깨뜨리는 것을 찾았다. 네이티브는
이 저장소에서 테스트하지 않기로 했으므로(design 12장) 리뷰가 유일한 방어선이다.

**How to apply:** 네이티브/Kotlin/Edge 등 테스트되지 않는 계층이 Dart 규칙을 옮겨 적거나 Dart가 만든 JSON을
읽는 변경이면 적용한다. 스크립트는 작업 트리를 건드리지 않게 스크래치 디렉터리에 두고 `dart run`으로 돌린다
(다른 세션이 같은 체크아웃에서 일할 수 있어 lib/ 임시 수정은 금지). 관련: [[layout-test-vacuity-probe]]
