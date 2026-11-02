---
name: feedback_popscope_guard_review
description: 뒤로가기 가드(PopScope) 리뷰는 blocked 식을 상태 열거로 검산하고 maybePop probe로 "탈출 가능한가"를 직접 확인한다 — Navigator.pop·pumpAndSettle은 이 검증에서 쓸 수 없다
metadata:
  type: feedback
---

`PopScope`로 화면을 떠나는 길을 막는 변경을 리뷰할 때 쓰는 절차.

**1) `blocked` 식을 상태 열거로 검산한다.** 화면의 플래그(`_busy`, `_result`, `_checked`, `_stage`)
조합을 표로 적고 세 가지를 따로 묻는다.
- `_busy`가 **영영 풀리지 않는 경로**가 있는가(모든 `catch`에 `setState(_busy=false)`가 있는가, `!mounted`
  조기 반환 뒤에 남는 것은 없는가).
- 막아야 하는데 **안 막히는** 상태: "결과를 들고 있음"을 가리키는 플래그가 **편집 중 null로 초기화**되면
  (예: `onChanged`에서 `_checked = null`) 이미 쓴 AI 호출 1회가 경고 없이 사라진다.
- 막아서는 안 되는데 **막히는** 상태: 실패해서 오류 화면을 보여 주는 중인데 결과 플래그가 남아 있는 경로.
  이때 다이얼로그 문구("사용한 횟수는 돌아오지 않아요")가 화면 문구("횟수는 차감되지 않았어요")와 충돌하기 쉽다.

**2) 탈출 가능성은 임시 probe 테스트로 직접 확인한다.** 세 가지 함정이 있다.
- `Navigator.pop`은 `PopScope`를 거치지 않아 아무것도 검증하지 못한다. 시스템 뒤로가기 제스처·앱바
  `BackButton`과 같은 길은 `tester.state<NavigatorState>(find.byType(Navigator)).maybePop()`이다.
- 검증 대상 화면은 host 화면에서 `push`해 띄워야 "나갔다"를 볼 수 있다.
- **전면 로더(`StatusMessage.loading`)가 떠 있는 상태에서는 `pumpAndSettle`이 타임아웃한다**(점 애니메이션이
  끝나지 않는다). `_busy` 상태를 검사할 때는 `pump(Duration(milliseconds: 50))`을 고정 횟수로 돌린다.
- 다이얼로그가 떠 있는 동안의 뒤로가기, 같은 프레임의 뒤로가기 2회도 같이 눌러 본다(갇히는지만 본다).

**Why**: mobile-ux M7 리뷰(2026-11-02)에서 오너가 "이것이 유일하게 사람을 다치게 할 수 있는 지점"이라고
못 박은 항목이었다. probe 5건으로 "생성 중에도 나가기로 탈출된다 / 생성 실패 뒤에는 묻지 않는다 /
재검사 실패 때는 막힌다"를 사실로 확인했고, 코드만 읽고는 단정할 수 없던 것이 그 셋이었다.

**How to apply**: `PopScope`·`WillPopScope`·확인 다이얼로그가 들어간 diff를 볼 때. probe 파일을 만들고
지우는 태도는 [[feedback_riverpod_async_review_probe]]와 같다(끝나면 `git status`로 작업 트리 확인).
