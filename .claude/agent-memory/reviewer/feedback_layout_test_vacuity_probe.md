---
name: feedback-layout-test-vacuity-probe
description: 레이아웃/넘침 위젯 테스트가 공허한(절대 실패할 수 없는) 단정인지 판단할 때는 입력을 과장한 일회용 probe로 확인한다 — textScaler를 1.3→3.0/5.0으로 올려 보고 그래도 통과하면 공허한 테스트다
metadata:
  type: feedback
---

"배율 1.3·폭 360dp에서 라벨이 칸을 넘지 않는다" 같은 위젯 테스트를 리뷰할 때, 통과했다는 사실만으로
보호받고 있다고 보지 말 것. **입력을 과장한 일회용 probe로 테스트가 실패할 수 있는지부터 확인한다.**

방법: 테스트 파일을 `test/zz_probe_test.dart`로 복사 → `TextScaler.linear(1.3)`을 `3.0`/`5.0`으로
바꿔 `flutter test <probe> --plain-name "<테스트 이름 일부>"` 실행 → 끝나면 파일 삭제하고
`git status`로 작업 트리 원복 확인. (리뷰는 코드를 고치지 않지만 검증용 임시 파일은 만들어도 된다.)

**왜 공허해지는가 — Flutter 레이아웃이 자식을 가둬 버린다.**
- `NavigationBar`는 커스텀 레이아웃이라 라벨이 칸을 넘어도 `RenderFlex` 예외를 내지 않고,
  라벨 상자 폭 자체가 칸(`bar.width / n`) 이하로 **강제 clamp**된다. 그래서
  `expect(tester.getSize(label).width, lessThanOrEqualTo(slotWidth))`는 **절대 실패할 수 없다**.
  `expect(bar.height, 72)`도 테마가 고정한 값이라 같다.
- `SegmentedButton`도 `_RenderSegmentedButton._calculateHorizontalChildSize`에서
  `childWidth = min(childWidth, constraints.maxWidth / childCount)`로 clamp하고 세로로 자라므로
  글자가 넘쳐도 예외가 없다(줄바꿈/잘림으로만 나타난다).
- `Wrap`도 자식에게 `maxWidth = Wrap의 maxWidth`를 주므로 "자식 rect가 부모 안에 있다"는 단정은
  거의 항상 참이다. 다만 `Wrap` 안의 `Row`(예: 배지 내부)는 여전히 예외를 내므로
  `expect(tester.takeException(), isNull)`은 의미가 남는다 — 실제로 5.0배에서 깨졌다.

**실패할 수 있는 단정은 이런 것이다**: 구조 단정(`find.ancestor(of: chip, matching: find.byType(Wrap))`
— `Row`로 되돌리면 깨진다), 존재 단정(칩 3개가 다 보인다), 테마 값 단정(`retro_text_test.dart`처럼
슬롯의 `fontFamily`/`fontSize`/`height`를 직접 본다).

**한글 글리프 폭은 위젯 테스트로 보장할 수 없다.** 테스트 글꼴은 글자마다 정사각형(1em)이어서
실제 한글·숫자보다 넓고(본문 글꼴은 시스템 글꼴이라 테스트에 아예 없다), 그래서 "넘치는지"를
글리프 폭으로 단정하면 실기기와 무관한 결과가 나온다. 이 경우 테스트를 억지로 만들지 말고
**"오너가 1.0·1.3 배율로 육안 확인할 목록"으로 돌리라고 보고하는 쪽이 정직하다.**

**Why**: retro-theme 가독성 개정 리뷰(2026-10-29)에서 "배율 1.3 탭 라벨 넘침" 테스트가 배율 3.0에서도
그대로 통과하는 것을 probe로 확인했다. 설계 문서(`readability.md` 5장)가 "위젯 테스트로 확인한다"를
합격 기준으로 걸어 뒀는데, 그 테스트는 화면이 빌드된다는 것만 증명하고 있었다.

**How to apply**: 위젯 테스트가 레이아웃 넘침·배율·크기를 "보장한다"고 주장하면 반드시 probe로
되돌림·과장 실험을 하고, 공허하면 심각도를 매겨 보고한다. 관련: [[feedback-riverpod-async-review-probe]]
(같은 일회용 probe 방식), [[feedback-sql-trigger-check-verification]](실행 불가 영역의 경계값 검산).
