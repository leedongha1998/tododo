---
name: riverpod-async-pitfalls
description: riverpod 3의 AsyncValue가 실패해도 직전 값을 들고 있고, AsyncNotifier.build()는 같은 인스턴스에서 다시 돌아 "세대 번호" 가드가 한 방향만 막는다
metadata:
  type: feedback
---

이 프로젝트의 riverpod 3(`flutter_riverpod 3.4.x`)에서 목록·페이징 provider를 만들 때 세 가지를 전제로 깐다.

1. **`AsyncError`는 직전 값을 그대로 들고 있다**(`copyWithPrevious`). 그래서 `value != null`은 "성공"이
   아니다. 화면 분기를 `value == null && hasError`로 쓰면 **한 번이라도 성공한 뒤의 실패가 어디에도
   보이지 않고**, 조건(검색어·필터)이 바뀐 뒤 실패하면 "새 조건 + 옛 결과"가 한 화면에 남아 사용자가
   그걸 결과로 읽는다. 실패를 숨기는 것보다 나쁘다. 분기는 `hasError`를 **먼저** 보고, 사용자 통지는
   `ref.listen`에서 `next.hasError && previous?.hasError != true`로 한 번 띄운다.
2. **`AsyncNotifier`는 무효화돼도 같은 인스턴스에서 `build()`만 다시 돈다.** `build()` 시작 시점에 올리는
   "세대 번호" 가드는 **build가 나중에 시작된 경우만** 막는다. build가 먼저 시작된 뒤 걸린 `loadMore()`는
   새 세대를 잡아 가드를 통과하고, 옛 커서로 받은 묶음이 새 첫 묶음 뒤에 붙어 **목록 중간이 통째로
   사라진다**(recruit-browse에서 실제로 리뷰에 걸렸다). 상태 객체에 **그 상태를 만든 조건**을 담아
   "적용된 조건 == 상태의 조건"을 비교하고, 다시 받는 중이면(`state.isLoading`) 끼어들지 않게 한다.
3. **실패한 provider는 스스로 다시 부른다**(기본 재시도, 지수 백오프). 테스트에서는 그 타이머가 남아
   `A Timer is still pending`으로 터지므로 `ProviderContainer(retry: (count, error) => null)`로 끈다.
   실패 로그가 두 번 찍히면 이 재시도를 의심한다.

**Why:** 1·2번은 recruit-browse 리뷰에서 "반드시 고칠 것"으로 지적된 결함 두 건의 원인이고, 둘 다
기능이 조용히 틀린 결과를 보여 주는 쪽(스펙의 "조용히 빠지지 않는다" 위반)이었다.

**How to apply:** 묶음·커서 페이징을 쓰는 provider를 새로 만들거나 고칠 때 2번의 두 가드를 처음부터 넣고,
그 가드를 **테스트로 박는다**(가드를 지우면 실패하는지까지 확인). 화면을 쓸 때는 1번대로 `hasError`를
먼저 보고, 위젯 테스트에서는 3번을 적용한다. 위젯 테스트의 다른 함정은 [[flutter-widget-test-gotchas]] 참고.
