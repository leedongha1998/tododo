---
name: flutter-widget-test-gotchas
description: 이 저장소 위젯 테스트에서 반복해서 걸리는 것들 — NetworkImage 400, 화면 밖 버튼 탭, DateTime.now() getter, Riverpod 자동 재시도 타이머, Scrollable/텍스트 찾기 모호성
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

**Why:** 1~3번은 mutual-judge 판정 화면(4단계), 4~5번은 recruit-browse의 찾기 탭(검색·필터·무한 스크롤)
작업에서 실제로 테스트를 깨뜨렸다. 1·3번은 설계를 되돌려야 할 수도 있는 판단(활성화 조건을 무엇에
걸 것인가)에 영향을 줬다.

**How to apply:** 위젯 테스트를 쓰기 전에 적용하고, 리뷰에서 "사진 로드 실패 시 비활성" 같은 요구사항을 만나면
1번을 근거로 조건의 범위를 분명히 적어 둔다. SQL 쪽의 같은 성격 함정은 [[sql-smoke-test-now-frozen]] 참고.
