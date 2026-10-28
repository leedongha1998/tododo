---
name: feedback_riverpod_async_review_probe
description: Riverpod AsyncNotifier(피드·페이징) 리뷰는 ProviderContainer 일회용 probe로 경합을 재현해 확인하고, AsyncValue가 실패·재빌드에도 이전 value를 유지한다는 사실을 에러 분기 검토에 쓴다
metadata:
  type: feedback
---

Riverpod `AsyncNotifier` 기반 목록/페이징 코드를 리뷰할 때 두 가지를 반드시 손으로 확인한다.

**1) 경합은 말로 따지지 말고 일회용 probe로 재현한다.** `test/`에 임시 테스트 파일을 하나 만들어
`ProviderContainer` + 게이트(`Completer`)로 "응답이 늦게 오는 상황"을 만들고, 끝나면 파일을 지운다
(`git status`로 작업 트리가 원래대로인지 확인). 리뷰는 코드를 고치지 않지만 **검증용 임시 파일은
만들어도 된다** — 추측으로 Critical을 쓰는 것보다 훨씬 낫다. 주의: `autoDispose` provider는 listener가
없으면 read 사이에 버려져 state가 초기화되므로 probe 안에서 `container.listen(provider, (_, _) {})`을
먼저 걸어야 한다.

**2) `AsyncValue`는 재빌드·실패에도 이전 value를 들고 있다.** riverpod 3.4.2
`lib/src/core/async_value.dart`의 `copyWithPrevious`를 보면 `AsyncLoading`·`AsyncError` 모두
`value: previous._value`를 유지한다. 그래서
- 화면이 `async.value == null && async.hasError`로 오류 화면을 가르면, **첫 로딩에서만** 오류가 보이고
  당겨서 새로고침·조건 변경 실패는 낡은 목록만 남긴 채 조용히 묻힌다(CLAUDE.md "에러는 삼키지 않는다" 위반).
- `build()` 재실행 중에도 `state.value`가 살아 있어 `loadMore()` 같은 메서드가 "이전 커서"로 요청을
  더 날릴 수 있다. `build()` 첫 줄에서 세대 번호를 올리는 가드는 **그 뒤에 시작된** 호출을 막지 못한다
  (호출이 새 세대 번호를 잡는다). `state.isLoading` 확인이나 조건을 상태에 함께 담아 비교하는 쪽이 맞다.

**Why**: recruit-browse 리뷰(2026-10-29)에서 이 두 가지로 Critical 2건을 찾았다. 하나는 조건 변경
중의 `loadMore`가 목록 중간 20건을 영구히 빠뜨리는 경합(probe로 `b0~b19 + b40~b59` 재현), 다른 하나는
피드 새로고침 실패가 화면·토스트 어디에도 나타나지 않는 경로였다. 둘 다 코드만 읽고는 "가드가 있으니
괜찮다"로 넘어가기 쉬웠다.

**How to apply**: Riverpod 상태·페이징·무한 스크롤·재시도 로직이 들어간 diff를 볼 때. SQL 쪽 검산은
[[feedback_sql_trigger_check_verification]]와 같은 태도로 하고, Dart 비동기 쪽은 이 memo를 쓴다.
