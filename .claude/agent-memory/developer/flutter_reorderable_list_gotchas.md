---
name: flutter-reorderable-list-gotchas
description: ReorderableListView로 끌어 옮기기를 만들 때 걸린 것들 — onReorder 폐기(3.47), stretch Row의 무한 높이, 빈 칸은 끌리지 않음, maxScrollExtent는 추정값, 꾹 누르기와 탭의 공존·툴팁이 긴 누르기를 가져감, 기본 접근성 액션
metadata:
  type: feedback
---

2026-11-10 `todo-reorder`(개인 투두 손 순서)에서 전부 실제로 걸렸다. 다시 끌기 UI를 만들 때 전제로 깐다.

1. **`ReorderableListView.onReorder`는 Flutter 3.47에서 폐기됐다**(`deprecated_member_use`가 뜨고,
   이 저장소의 끝 조건은 `flutter analyze` 이슈 0이다). 후임은 **`onReorderItem`**이고 **newIndex가
   이미 조정된 좌표**다(`newIndex > oldIndex`면 1을 빼 준다). 옛 예제를 그대로 베껴 또 1을 빼면
   아래로 내릴 때 한 칸 덜 내려간다. 두 좌표계를 섞지 말 것.
2. **`Row(crossAxisAlignment: stretch)`를 목록 줄 안에 그냥 쓰면 죽는다.** 줄의 높이 제약이 무한인데
   `RenderFlex`가 stretch에서 `BoxConstraints.tightFor(height: constraints.maxHeight)`를 자식에게
   주기 때문이다. `IntrinsicHeight`로 감싸면 성립한다(`ConstrainedBox(minHeight:)`는 그 위에 둬도 된다).
3. **`SizedBox` + `Center` + `Icon`으로 만든 48dp 손잡이는 아이콘 자리(24dp)만 잡힌다.**
   `ReorderableDragStartListener`는 `Listener`(기본 `deferToChild`)이고 빈 자리는 히트 테스트를
   통과시킨다. `ColoredBox(color: Colors.transparent)`로 덮으면 칸 전체가 잡힌다
   (`_RenderColoredBox`가 `HitTestBehavior.opaque`다 — 확인함).
4. **게으른 목록의 `maxScrollExtent`는 추정값이다.** 추가 직후 `animateTo(maxScrollExtent)`를 한 번
   하면 모자란 자리에서 멈춘다(20줄 목록에서 1088 vs 실제 1164 — 하필 새로 생긴 그 줄이 안 보인다).
   한 프레임 기다린 뒤 "목표에 못 닿았으면 다시" 몇 번 반복해야 바닥에 닿는다.

**테스트에서 손잡이를 끄는 법**: 20dp 남짓씩 나눠 `moveBy` + `pump(Duration(milliseconds: 40))`.
**한 번에 크게 밀면 목록이 한 칸만 비켜 주고 끝나고**(220dp를 밀어도 한 줄), 걸음마다
`pumpAndSettle`을 하면 **끌기 자체가 인정되지 않는다**(호출은 아예 안 온다). 거리 ÷ 줄 높이(=
minHeight + 줄 간격)가 옮겨지는 줄 수다. 관련: [[flutter-widget-test-gotchas]]

**Why:** 1번은 analyze가 막아 설계(순수 함수가 off-by-one을 보정)를 바꿔야 했고, 2·3번은 설계
코드를 그대로 옮기면 각각 크래시와 "48dp 터치 영역이 거짓"으로 끝났다. 4번은 수용 기준("새 할 일이
어디 생겼는지 알 수 있어야 한다")을 조용히 깨뜨리는 종류였다.

**How to apply:** 끌기 UI·목록 줄 레이아웃을 새로 짤 때 설계 문서가 옛 API를 전제하고 있는지부터
보고, 손잡이는 "칸 전체가 잡히는가"를 위젯 테스트로 재며(칸의 `Key`로 `getRect`), 스크롤 끝으로
보내는 코드는 추정값 때문에 반복이 필요하다는 것을 염두에 둔다.

5. **꾹 눌러 집기(`ReorderableDelayedDragStartListener`)와 "줄 전체 탭"은 분기 없이 공존한다** —
   제스처 경기장이 시간으로 가른다(2026-11-10 오너가 손잡이를 없애고 꾹 누르기로 바꿀 때 확인).
   빨리 떼면 탭이 이기고(수정 열림), 500ms를 넘겨 쥐면 끌기가 이겨 **탭이 취소**되며(놓아도 수정이
   열리지 않는다), 500ms 전에 움직이면 둘 다 지고 `Scrollable`이 이긴다. 안쪽 위젯(체크박스)은
   **짧은 탭에서 먼저 이기고** 그 위에서 꾹 누르면 줄이 집힌다. 다만 **`Tooltip`이 붙은
   `IconButton`(삭제) 위에서 꾹 누르면 툴팁이 긴 누르기를 가져가 끌기도 삭제도 일어나지 않는다**
   (실측). `buildDefaultDragHandles: true`는 쓰지 말 것 — `Theme.of(context).platform`을 보고
   갈라져 **데스크톱에서는 줄 오른쪽에 손잡이 아이콘을 다시 그린다.**
   **테스트 레시피**: `startGesture` → `pump(kLongPressTimeout + 60ms)`(쥐기) → 그다음에야 4번의
   20dp 걸음. 쥐기 전에 움직이면 호출이 아예 안 온다.
6. **`SliverReorderableList`는 줄마다 접근성 액션("맨 앞/위/아래/맨 뒤로 이동")을 기본으로 붙이고,
   그것이 `onReorderItem`으로 들어온다**(`reorderable_list.dart` `_wrapWithSemantics` →
   `_handleReorderItem`). 손잡이 유무와 무관하다 — 손잡이의 `Semantics` 라벨을 지워도 스크린리더
   사용자가 순서를 바꿀 수단은 남고, 그 길도 제품 코드의 저장 경로를 그대로 지난다. 끌기 UI에서
   "접근성 수단이 없어진다"는 걱정을 받으면 이것을 먼저 확인할 것(전용 UI를 만들 이유가 없다).
