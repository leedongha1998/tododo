---
name: feedback_gesture_arena_review
description: 길게 누르기/탭이 같은 자리를 쓰는 제스처 변경을 리뷰할 때 — 경계값 타이밍 probe, 옛 구조 재현으로 느린 탭 회귀 확인, SemanticsOwner.performAction으로 접근성 액션이 저장까지 되는지 확인
metadata:
  type: feedback
---

제스처 경기장(`DelayedMultiDragGestureRecognizer` 500ms vs `TapGestureRecognizer` vs `Tooltip`의
long press)에 맡긴 변경은 **코드를 읽어 단정하지 말고 세 종류 probe로 사실을 만든다.**

**1) 경계값 타이밍 probe.** `tester.startGesture` → `tester.pump(kLongPressTimeout ± n)` → `up()`.
`kLongPressTimeout`(500ms)을 상수로 쓰고 리터럴 500을 쓰지 않는다. 400ms는 탭이 이기고(= 수정 열림),
560ms는 끌기가 이겨 탭이 `onTapCancel`로 취소된다. **"움직이지 않고 떼는" 갈래를 따로 본다** —
구현·테스트가 보통 "집어서 움직인" 갈래만 덮는다.

**2) 느린 탭 회귀는 옛 구조를 20줄로 재현해 확인한다.** 끌기 인식기를 더하면, 그 전까지 탭
인식기만 있던 경기장에서 **600ms 눌렀다 떼도 안쪽 위젯(체크박스)이 이겨 토글됐던** 동작이
사라진다(실측: 전 toggled=1 → 후 toggled=0, 토글도 끌기도 아닌 무반응). 옛 코드를 체크아웃하지
않고 `GestureDetector(opaque, onTap:) > Checkbox`만 가진 스탠드얼론 probe로 재현할 수 있다
(`Scaffold`로 감싸야 Material 단정을 통과한다).

**3) 접근성 커스텀 액션은 실제로 실행해 저장까지 본다.** `tester.ensureSemantics()` →
`tester.binding.pipelineOwner.semanticsOwner`의 루트를 재귀로 돌며
`getSemanticsData().customSemanticsActionIds`가 있는 노드를 모으고,
`CustomSemanticsAction.getAction(id)!.label`로 고른 뒤
`owner.performAction(node.id, SemanticsAction.customAction, id)`. `SliverReorderableList`는
`_wrapWithSemantics`에서 줄마다 액션을 붙이고 **그것이 `onReorderItem`으로 들어가 화면의 저장
경로를 그대로 탄다**(= 손잡이를 지워도 공백이 없다). 단 **양 끝 줄은 액션이 2개**다(첫 줄에
"위로 이동"이 없다) — "모든 줄에 넷"은 틀린 서술이다. 라벨의 한국어는
`flutter_localizations`의 ko 번역(`reorderItemDown = '아래로 이동'`)에서 오므로
`GlobalWidgetsLocalizations.delegate`가 앱에 걸려 있는지도 같이 본다.

**Why**: todo-reorder 제스처 변경 리뷰(2026-11-10). 구현 보고의 "체크박스 위에서 꾹 누르면 줄이
집힌다 / 삭제 위에서는 툴팁이 가져간다"는 probe로 전부 사실로 확인됐지만, **아무도 보지 않은
갈래**(꾹 눌렀다 안 움직이고 떼기 = 가장 자주 쓰는 완료 토글이 조용히 안 된다)가 거기서 나왔다.

**How to apply**: 길게 누르기·끌기·탭이 같은 픽셀을 쓰는 diff. 레이아웃 하한 단정은
[[feedback_layout_test_vacuity_probe]]처럼 1dp 올려 실패를 확인해 공허하지 않음을 본다.
