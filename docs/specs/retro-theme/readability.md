# retro-theme 개정 — 도트 느낌 유지 + 가독성 (설계)

작성: 2026-10-29. 오너 피드백에서 출발한 **기존 retro-theme의 개정**이다. 새 기능이 아니다.
`spec.md`/`design.md`/`plan.md`가 정한 콘셉트는 유지하고, 그 중 **글꼴 역할 분담 표만** 고친다.

오너 말: "도트 느낌으로 게임처럼 하는 것은 좋은데 뭔가 가독성이 떨어지는 것 같다.
게임 같은 느낌은 유지하면서 가독성을 좋게 해 달라."

## 1. 진단 (designer, 2026-10-29)

**색 대비는 원인이 아니다.** `test/core/theme/retro_palette_test.dart`가 24쌍을 고정하고 있고
전부 WCAG SC 1.4.3 AA(4.5:1) 이상이다. 팔레트는 건드리지 않는다.

원인은 두 개다.

1. **12dp 픽셀 글꼴이 짧은 라벨 전부를 덮는다.** `retro_text.dart:50-57`의
   `titleSmall`·`labelLarge`·`labelMedium`·`labelSmall`이 **넷 다 `pixel(grid)` = 12dp**다.
   이 네 슬롯이 버튼(`app_theme.dart:375`), 탭(`:117-121`), 세그먼트(`:295`), 칩(`pixel_tag.dart:84`),
   유형 배지(`battle_chips.dart:173`), 창 제목 띠·톤 블록 제목(`pixel_frame.dart:145,207`)을 통째로 끌고 간다.
   갈무리11은 12px 격자라 한 음절이 11x11 dot이다. 초·중·종성을 넣으면 받침 획 간격이 1 dot이 되고,
   Flutter는 **텍스트 안티에일리어싱을 끌 수 없다**(테두리·픽셀 아이콘은 `isAntiAlias = false`로
   칼같이 그린다 — `pixel_border.dart:110,129`, `pixel_icon.dart:49`). 그래서 테두리는 또렷한데
   글자만 회색으로 번진다. DPR 2.625(Pixel 6)에서 12dp 글자의 1 dot 획은 물리 2.6px로 3픽셀에 퍼지고,
   같은 화면의 2dp 테두리는 물리 5.25px로 선명하다. 오너가 느낀 증상과 정확히 일치한다.
2. **본문 3슬롯에 행간·자간이 비어 있다.** `retro_text.dart:59-61`은 `height`/`letterSpacing`을
   지정하지 않아 `ThemeData.localize`가 `englishLike2021` 기하를 머지한다 → 실제 행간이
   bodyLarge 1.50 / bodyMedium 1.43 / bodySmall 1.33이 된다. 한글 본문 권장은 1.6~1.75이고
   **WCAG SC 1.4.12는 1.5em 이상 지원을 요구한다 → bodyMedium·bodySmall 미달.**
   하필 `bodySmall`(12dp/1.33)에 "놓치면 손해 보는 문장"이 들어 있다(제출·판정 마감, "판정은 한 번만",
   기간 경고, 기준 힌트).

## 2. 채택안 — 방안 1 + 2 + 3 (designer 추천 묶음)

### 방안 1. 본문 3슬롯에 한글용 행간·자간 명시
`lib/core/theme/retro_text.dart:59-61`만 고친다.

| 슬롯 | 지금 | 바꿀 값 |
|---|---|---|
| bodyLarge | 16, height 미지정 | 16, `height: 1.6`, `letterSpacing: 0` |
| bodyMedium | 14, height 미지정 | 14, `height: 1.6`, `letterSpacing: 0` |
| bodySmall | 12, height 미지정 | **13**, `height: 1.55`, `letterSpacing: 0` |

### 방안 2. 12dp 픽셀 역할을 본문 글꼴로 넘기고, 픽셀은 24dp 이상에만 남긴다
**이것이 이번 개정의 핵심이다.** 픽셀 글꼴을 버리는 게 아니라 **경계를 12dp에서 24dp로 올린다.**

`retro_text.dart:50-57`의 네 슬롯을 **본문 글꼴(= `fontFamily` 지정하지 않음) 14dp / w700 /
height 1.4 / letterSpacing 0.2**로 바꾼다. 이 한 군데를 고치면 버튼·탭·세그먼트·카운터가 따라온다.

직접 `RetroText.pixel(RetroText.grid, ...)`를 쓰는 곳은 같이 고친다:
- `lib/core/widgets/pixel_frame.dart:145` (창 제목 띠), `:207` (톤 블록 제목) → 테마의 `labelLarge` 계열
- `lib/core/widgets/pixel_tag.dart:84` → **`isLarge`가 false인 쪽(grid=12)만** 본문 글꼴로.
  `isLarge`(grid*2=24)는 픽셀 그대로 둔다.

**픽셀로 남기는 것(건드리지 말 것)** — 도트 인상은 여기서 나온다:
- `display*`/`headline*`/`titleLarge`/`titleMedium` = 24dp 이상 픽셀
- `RetroText.numeric` 계열(점수, 남은 시간, n/5 카운터, 전적)
- `lib/features/battle/presentation/vs_intro.dart:226,277` (VS 인트로 연출 전체)
- `lib/core/widgets/initial_badge.dart:61` (이니셜 한 글자)
- `lib/features/profile/presentation/profile_screen.dart:202` (20dp 점수)
- 2dp ink 각진 테두리·계단 모서리·눌림 변형·픽셀 아이콘·제한 팔레트 — **전부 그대로**

왜 게임 느낌이 안 깨지는가: 이 앱의 도트감은 글꼴이 아니라 테두리·모서리·아이콘·팔레트·VS 연출이
만든다. 화면 면적의 대부분이 그대로 남는다. 지금은 **도트를 가장 안 보이는 크기에만** 써서 비용은
다 치르고 멋은 못 받는 상태다. 경계를 올리면 앱바 제목 24·점수 20·VS 72가 픽셀로 남아 도트 인상이
오히려 또렷해진다.

> 단일 글꼴로 크기만 조정하는 안은 쓸 수 없다. `design.md:107`이 격자 정수배(12/24/36/48/72)만
> 허용하고 1.5배(18dp)를 금지했다 — 버튼·칩에 쓸 중간 크기가 존재하지 않는다.

### 방안 3. 경고·설명 문장 등급 올리기 (bodySmall → bodyMedium)
"놓치면 손해 보는 문장"만 승격한다. `bodySmall`은 진짜 메타데이터(날짜, "vs 이름")에만 남긴다.

- `battle_detail_screen.dart:153,157` (제출 마감·판정 마감)
- `judgment_section.dart:195,235` ("판정은 한 번만", 거부 힌트)
- `evidence_section.dart:189,280`
- `create_battle_screen.dart:323,326,329,345` (기간 경고)
- `criteria_views.dart:32,113` (기준 블록 힌트)
- `battle_detail_screen.dart:258,275` (판정 사유 라벨, 점수 하한 설명)

행 번호는 designer가 읽은 시점 기준이다. **줄 번호를 믿지 말고 문장 내용으로 찾아라.**

## 3. 오너 결정 — 메인 세션 판단 (2026-10-29)

designer가 오너에게 물어 달라고 남긴 3건에 대한 답이다. 이대로 하면 된다.

1. **라벨이 12→14로 커져 한 줄 3칩이 넘칠 수 있다** (`my_battles_screen.dart:199-213`,
   `battle_summary_list.dart:55-83`) → **`Wrap`으로 내린다. 칩을 빼지 않는다.**
   정보를 지우는 쪽은 사용자가 잃는 게 생기고, 줄바꿈은 아무것도 잃지 않는다.
   `spacing`/`runSpacing`은 기존 `Row`의 간격을 그대로 쓴다.
2. **텍스트 배율 상한 1.3**(`main.dart:13`) → **이번에는 건드리지 않는다.** 배포 후 과제.
   라벨이 본문 글꼴이 되어 줄바꿈이 가능해지므로 올릴 여지는 생기지만, MVP 직전에 전 화면
   레이아웃을 1.5배로 재검증할 시간이 없다.
3. **문서 개정** → **이번 작업에 포함한다.** `spec.md` 결정 A, `design.md:113-136` 글꼴 표,
   `decisions.md:5`가 "짧은 라벨은 통째로 픽셀 12"로 적혀 있어 코드와 어긋나게 된다.
   같은 커밋에서 고친다.

## 4. 범위 밖 (이번에 하지 않는다)

- 방안 4(칩 테두리 2dp→1dp), 방안 5(구분선 `line`→`inkMuted`, 프레임 중첩 평면화) — 레이아웃
  변동이 커서 배포 후로 미룬다. 필요하면 `TODO_BACKLOG.md`에 한 줄.
- 방안 6(Galmuri14 추가) — 레이아웃 비용은 방안 2와 같은데 앱 크기만 5~8MB 늘고 번짐은 그대로다.
- 팔레트 색 변경, 새 패키지·새 에셋 추가. **에셋 변경 0바이트여야 한다.**

## 5. 검증

- `flutter analyze` 이슈 0, `flutter test` 전부 통과. 테마를 바꾸므로 깨지는 위젯 테스트가 있다
  (`test/core/theme/`, `test/features/battle/battle_chips_test.dart`,
  `my_battles_sections_test.dart` 등) — **테스트를 지우지 말고 새 기대값으로 고친다.**
  `retro_palette_test.dart`의 대비 24쌍은 손대지 않는다(색은 안 바뀐다).
- 배율 1.3에서 탭 라벨·칩이 칸을 넘지 않는지 위젯 테스트로 확인한다.
- 숫자 근거를 남길 것: 바꾼 뒤 본문 행간이 1.5em 이상인지.

## 설계와 달라진 점 (developer, 2026-10-29 구현)

채택안(방안 1+2+3)과 오너 결정 3건은 그대로 구현했다. 아래 넷만 다르다.

1. **비선택 탭 라벨만 w400으로 남겼다.** 방안 2는 네 슬롯을 모두 `w700`으로 정했는데,
   `app_theme.dart`의 `navigationBarTheme`은 선택/비선택 탭을 **굵기로만** 구분하고 있었다
   (색은 둘 다 ink). 네 슬롯이 전부 w700이 되면 그 구분이 사라져 선택된 탭이 표시기 색 외에는
   드러나지 않는다. 그래서 비선택 라벨에 `copyWith(fontWeight: w400)`을 둬 **개정 전과 같은 대비**를
   유지했다(개정 전에도 비선택은 Regular였다). 테마 표 자체는 방안 2대로 w700이다.
2. **기준 목록의 항목 번호는 픽셀 12를 유지했다.** `criteria_views.dart`의 `Text('${i + 1}')`은
   `labelLarge`를 타고 있어 그대로 두면 본문 글꼴이 된다. 그 줄의 기존 주석이 "번호는 숫자라 픽셀 글꼴"
   이고, 방안 2의 "픽셀로 남기는 것"에 숫자 칸이 들어 있어 `RetroText.pixel(grid, bold: true)`로
   명시했다(한 자리 숫자는 받침이 없어 12dp에서도 번지지 않는다).
3. **"점수 변동" 라벨도 bodyMedium으로 올렸다.** 방안 3 목록은 `battle_detail_screen`의 판정 사유 라벨과
   점수 하한 설명만 지목했지만, 그 둘과 같은 결과 블록 안에 있는 `battleScoreChangeLabel` 한 줄만
   13dp로 남으면 같은 묶음에서 크기가 들쭉날쭉해진다. 한 줄 추가로 올렸다.
4. **`battle_summary_list`의 줄은 3칩이 아니라 "배지 + vs 이름"이었다.** 오너 결정 1대로 `Wrap`으로
   바꿨고, `Wrap`은 `Flexible`(Flex 전용 parent data)을 받을 수 없어 그 래퍼를 떼고 `Text`를 직접 넣었다.
   간격은 기존 `SizedBox(width: 8)`을 `spacing: 8` / `runSpacing: 8`로 옮겼다. 이름이 길면 이제 줄여
   보여 주는 대신 아래 줄로 내려간다.

5. **새 위젯 테스트를 `test/core/theme/text_scale_layout_test.dart` 대신 `test/widget_test.dart`에 넣었다.**
   `plan.md` 개정 2의 6단계는 새 파일을 만들겠다고 적었지만, dev-standards가 "위젯 테스트는
   `test/widget_test.dart` 하나에 몰려 있다"고 정하고 있어 그쪽을 따랐다. 구현이 맞고 문서가 틀렸다.

### 숫자 근거 (측정값)

| 슬롯 | 개정 전 행간 | 개정 후 행간 | 한 줄 실제 높이(배율 1.0) |
|---|---|---|---|
| bodyLarge | 16dp × **1.50** | 16dp × **1.60** | 26.0dp |
| bodyMedium | 14dp × **1.43** | 14dp × **1.60** | 22.0dp |
| bodySmall | 12dp × **1.33** | **13dp** × **1.55** | 20.0dp |

개정 전 값은 "행간 미지정 + `ThemeData.localize`의 englishLike 기하"를 그대로 재현해 측정한 것이다
(bodyMedium·bodySmall이 WCAG SC 1.4.12의 1.5em에 미달했다는 진단이 맞았다). 개정 후는 세 슬롯 모두
1.5em 이상이다(26/16 = 1.63, 22/14 = 1.57, 20/13 = 1.54).

### 확인한 것 / 확인 못 한 것

- `flutter analyze` 이슈 0, `flutter test` 362개 통과(기준선 351 + 새 테스트 11개, 지운 테스트 없음).
- **탭 라벨이 칸을 넘지 않는지는 확인하지 못했다.** 처음 쓴 위젯 테스트는 아무것도 보장하지
  못했다(reviewer 지적 W1, 메인 세션이 배율 3.0 복사본으로 재현해 확인했다 — 그대로 통과한다).
  `NavigationBar`는 자체 레이아웃 델리게이트라 넘쳐도 예외를 내지 않고 라벨 상자 폭을 칸 폭으로
  clamp한다. 테스트는 "1.3배에서 예외 없이 그려지고 네 라벨이 다 있고 바 높이 72가 유지된다"는
  스모크로 낮췄다. 탭 라벨 넘침(2줄 줄바꿈)은 **오너 육안 확인 대상**이다.
- 같은 이유로 `SegmentedButton`(대결 만들기의 기간 빠른 선택 5칸, 대결 찾기의 기간대 필터 4칸)도
  배율 1.3에서 라벨이 두 줄로 내려앉을 수 있다(reviewer W4, 계산상 라벨 ≈46dp vs 남는 폭 ≈44dp).
  어떤 테스트도 못 잡는다 — **오너 육안 확인 대상**이다. 실제로 깨져 보이면 그 두 곳만
  `Wrap` + 토글로 바꾸면 된다(오너 결정 1과 같은 방향).
- 배율 1.3·폭 360dp에서 모집 카드 칩 3개가 모두 남고 화면 밖으로 나가지 않는다(위젯 테스트).
- **실기기·에뮬레이터 육안 확인은 하지 않았다**(developer 에이전트가 할 수 없음). "번짐이 실제로
  줄었는지", "도트 인상이 유지되는지"는 오너가 1.0·1.3 배율로 직접 봐야 한다.
