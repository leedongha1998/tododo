---
name: flutter-widget-test-gotchas
description: 이 저장소 위젯 테스트에서 반복해서 걸리는 것들 — NetworkImage 400, 화면 밖 버튼 탭, DateTime.now() getter, Riverpod 자동 재시도 타이머, finder 모호성, 정사각 테스트 글꼴, 런타임 fontFamily/행간 머지, 끌기 제스처·FAB 제거의 추가 pump
metadata:
  type: feedback
---

위젯 테스트를 새로 쓸 때 아래를 먼저 전제로 깔고 설계한다.

1. **`NetworkImage`는 테스트에서 항상 실패한다**(테스트용 HTTP 클라이언트가 400을 돌려준다).
   그래서 "사진을 봤는가"를 조건으로 삼는 활성화 판단은 **서명 URL 발급 결과**(`evidencePhotoUrlProvider`)에
   걸어야 테스트로 활성/비활성 두 경로를 모두 볼 수 있다. 이미지 디코딩 성공까지 조건에 넣으면 테스트에서
   활성 경로를 아예 만들 수 없다.
2. **기본 테스트 화면은 800x600이라 상세 화면의 버튼은 대개 화면 밖이다.** `ensureVisible` + `pumpAndSettle`
   없이 `tap`하면 "would not hit test" 경고와 함께 실패한다. `ListView` 아래쪽 위젯은 아예 빌드되지 않아
   `find.text`가 0을 돌려주기도 한다 — 그 단언은 다른 테스트에 맡기는 쪽이 낫다.
3. **`DateTime.now()`를 내부에서 쓰는 getter는 고정 날짜 픽스처로 검증할 수 없다.** 도메인 모델에 시각 비교가
   들어가면 `...At(DateTime now)` 형태를 유닛 테스트가 쓰고, 인자 없는 getter 경로는 `DateTime.now()` 기준으로
   픽스처를 만드는 위젯 테스트가 덮는다.
4. **Riverpod 3은 실패한 provider를 스스로 다시 부른다.** 그 백오프 타이머가 테스트 끝까지 남아
   `A Timer is still pending even after the widget tree was disposed`로 터진다. "불러오기 실패" 화면을
   보는 테스트는 `ProviderContainer(retry: (count, error) => null)`로 재시도를 끄고 띄운다
   (제품 코드의 재시도는 그대로 둔다). 실패 로그가 두 번 찍히면 이 재시도를 의심한다.
5. **찾기(finder)가 조용히 모호해지는 두 자리.** ① `find.byType(Scrollable)`은 `TextField` 내부
   (`EditableText`)의 Scrollable까지 잡아 `scrollUntilVisible`이 "Too many elements"로 죽는다 —
   `scrollable: find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable))`로 집어 준다.
   ② 입력창에 넣은 글자가 목록 카드 제목과 같으면 `find.text`가 2개를 잡는다. 검색 테스트에서는
   제목의 **일부만** 입력한다. 같은 라벨이 조작 영역과 빈 상태 버튼에 동시에 있으면
   `find.widgetWithText(TextButton/FilledButton, ...)`로 가른다.
6. **테스트 글꼴은 글자마다 정사각형(1em)이다.** 한글 라벨의 실제 글리프 폭보다 훨씬 넓게 잡혀,
   "라벨이 칸을 넘지 않는다"를 글리프 폭으로 단정하면 실기기에서는 멀쩡한데 테스트만 실패한다
   (14dp·배율 1.3에서 "대결 찾기"가 테스트에서는 91dp = 한 칸 90dp 초과, 실제 한글은 ≈77dp).
   그런데 **상자 기준으로도 못 잡는 위젯이 있다.** `NavigationBar`·`SegmentedButton`·`Wrap`은
   자식 폭을 부모 폭 이하로 clamp하므로 "라벨 상자 <= 칸 폭"이 **어떤 배율에서도 참**이고,
   커스텀 레이아웃 델리게이트라 넘쳐도 `RenderFlex` 예외를 내지 않는다. 넘침은 예외가 아니라
   2줄 줄바꿈으로 나타난다. 그런 위젯의 넘침 단정은 쓰지 말고 육안 확인으로 넘긴다.
   **새로 쓴 레이아웃 테스트는 배율을 3.0처럼 터무니없이 올린 복사본으로 한 번 돌려 보라 —
   그래도 통과하면 그 테스트는 아무것도 보장하지 않는다**(2026-10-29에 탭 라벨 테스트가 그랬다).
   `Row`/`Column`(RenderFlex)은 넘치면 예외를 내므로 `tester.takeException()` 단정이 유효하다.
7. **테마 글꼴을 단정할 때 `fontFamily`는 런타임에 null이 아니다.** `RetroText.textTheme()`은
   `fontFamily` 미지정(null)이지만, `ThemeData` + `MaterialApp`을 타면 Material Typography가
   머지돼 `'Roboto'`가 붙는다. "본문 글꼴이다"는 `isNull`이 아니라
   `isNot(RetroText.pixelFamily)`로 쓴다. 같은 머지로 **`height`를 비워 두면 englishLike 기하
   (bodyLarge 1.50 / bodyMedium 1.43 / bodySmall 1.33)가 들어온다** — 행간을 보장해야 하면
   테마에서 직접 적어야 한다.

8. **한 `testWidgets` 안에서 `pumpWidget`을 두 번 하면 타이머가 남는다.** 픽스처만 바꿔 같은 화면을
   다시 세우면 첫 트리가 띄운 타이머(스낵바·provider 재시도 등)가 정리되지 않아
   `A Timer is still pending even after the widget tree was disposed`로 실패한다. 픽스처가 다른 두 상황은
   **테스트를 둘로 쪼갠다**(2026-10-30 mobile-ux M1의 내 대결 카드 테스트).

9. **스크롤 제스처와 FAB 사라짐은 둘 다 "한 번 더 pump"가 필요하다.**
   ① `startGesture` 뒤 `moveBy`를 **한 번에 크게** 주면 카드의 `GestureDetector`(PixelFrame의
   onTapDown)와 겨루다 끌기로 인정받지 못해 **리스트가 1픽셀도 안 움직인다**(`position.pixels == 0`).
   touch slop을 넘기는 작은 걸음(예: -40) → `pump()` → 본 걸음(-200) 순으로 나눠 준다.
   ② `Scaffold.floatingActionButton`을 null로 바꿔도 **그 프레임에 트리에서 빠지지 않는다.**
   내부 수명 타이머(200ms) 때문에 `pump()`(교체 반영) → `pump(250ms)`(타이머 소진) →
   `pump()`(제거 반영) 세 번이 필요하다. `FloatingActionButtonAnimator.noAnimation`을 줘도
   이 지연은 남는다(크기·회전 연출만 사라진다).

**Why:** 1~3번은 mutual-judge 판정 화면(4단계), 4~5번은 recruit-browse의 찾기 탭(검색·필터·무한 스크롤),
6~7번은 retro-theme 가독성 개정(2026-10-29, 글꼴 표를 바꾸고 배율 1.3 넘침 테스트를 쓸 때),
9번은 recruit-list-scan(2026-11-02, 찾기 탭의 "내리면 FAB이 비킨다" 테스트)
작업에서 실제로 테스트를 깨뜨렸다. 1·3번은 설계를 되돌려야 할 수도 있는 판단(활성화 조건을 무엇에
걸 것인가)에 영향을 줬다.

**How to apply:** 위젯 테스트를 쓰기 전에 적용하고, 리뷰에서 "사진 로드 실패 시 비활성" 같은 요구사항을 만나면
1번을 근거로 조건의 범위를 분명히 적어 둔다. 글꼴·배율·레이아웃 넘침을 테스트로 보장해 달라는 요구를
받으면 6번을 근거로 "무엇을 측정한 것인지"를 테스트 주석과 보고에 분명히 적는다.
SQL 쪽의 같은 성격 함정은 [[sql-smoke-test-now-frozen]] 참고.
