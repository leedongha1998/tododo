# redesign 설계

## 참고
- spec.md: `docs/specs/redesign/spec.md` — 2026-11-06 오너 승인. 맨 끝 "## 오너 결정 (2026-11-06)"이 최종 결정이다:
  기준 화면 = 할 일 목록 + 대결 상세 판정 창 / 브랜드 = "현재 파랑을 더 밝게 + 앰버 보조" 기본, 시안 2~3개 중 오너 선택 /
  Pretendard 한 벌 / 갈무리 완전 제거 / 라이트만 / 숫자는 정적 강조만 / 글자 배율 상한 1.5 / 개편 P0 뒤 출시 /
  버튼 촉감 = 시각적 눌림만 / 런처 모티프 "칸을 뚫고 나가는 체크" 유지.
- references.md: `docs/specs/redesign/references.md`(원인 후보 4개, Duolingo 등 레퍼런스).
- 대체 대상: `docs/specs/retro-theme/design.md`. 이 문서가 그 문서의 1장(시각 규칙)·2장(픽셀 아이콘)·3장(구성 요소 모양)·
  4.3~4.4(VS 인트로 레이아웃·타임라인)·5장(화면별 모양)·6장(런처 아이콘)을 **대체**한다. 그 문서의 4.1·4.2·4.5·4.6
  (인트로 표시 여부·"봤음" 기록·실패 구조·붙이는 지점), 상태 칩·결과 라벨의 **의미 구분**, "앱 안 모든 색은 팔레트 한 곳",
  "대비 조합은 테스트로 고정"은 **그대로 이어받는다**(spec 승계표).
- 현재 코드 조사 결과(이 문서가 근거로 쓴 사실):
  - 테마: `lib/core/theme/` — `retro_palette.dart`(15색 + `contrastRatio`), `retro_text.dart`(갈무리 슬롯 8개 + 본문 슬롯),
    `pixel_border.dart`(계단 모서리 + 바닥 두께 `OutlinedBorder`), `pixel_icons.dart`(12×12 비트맵 34종), `app_mark.dart`(16×16 마크),
    `app_theme.dart`(ThemeData, `_DoubleOutlineInputBorder`).
  - 공용 위젯: `lib/core/widgets/` — `pixel_frame.dart`, `pixel_tag.dart`, `pixel_icon.dart`, `pixel_loader.dart`, `status_message.dart`,
    `initial_badge.dart`, `evidence_photo_frame.dart`, `retro_button_styles.dart`. 그 밖에 `lib/features/battle/presentation/battle_chips.dart`
    (유형 배지·상태 칩·결과 라벨 매핑)와 `lib/core/navigation/main_shell.dart`(탭바)가 공용 조각 역할을 한다.
  - 실제로 쓰이는 픽셀 아이콘은 **27종**(아래 4.2 표). `gallery`·`fail`·`edit`·`expand`·`collapse`·`lock`·`openExternal` 7종은
    정의만 있고 어느 화면도 쓰지 않는다.
  - **12dp 픽셀 숫자가 아직 남아 있다**: `RetroText.numeric`(갈무리 12dp)이 상대 카드의 점수·전적(`player_card_view.dart`),
    결과 배너의 점수 변화(`battle_detail_screen.dart`), 제출 시각(`evidence_section.dart`), 프로필 전적(`profile_screen.dart`)에,
    `RetroText.pixel(12)`가 기준 번호(`criteria_views.dart`)와 VS 인트로의 "상대"/"나" 라벨에 쓰인다. 10-29 개정이 라벨만 바꾸고
    숫자 칸은 남겨 둔 자리로, 원인 후보 1의 실제 근거다.
  - `main.dart`: `maxTextScale = 1.3`, 갈무리 OFL 고지를 `LicenseRegistry`로 등록.
  - 런처·알림 아이콘·적응형 배경색·시작 창 배경색: `tool/generate_launcher_icons.dart`(색은 `RetroPalette`, 그림은 `AppMark` 비트맵).
  - 홈 위젯: `tool/generate_widget_resources.dart`가 `widget_resources.xml`(색 7개)을 생성하고, `res/drawable/widget_frame.xml`
    (`PixelFrame.raised` 흉내), `widget_row.xml`, `widget_check.xml`, `res/layout/todo_widget.xml`(글자 10/11/12/13sp)이 그린다.
    Kotlin(`TodoWidgetProvider.kt`)은 `R.color.widget_danger`·`R.color.widget_ink_muted` 두 이름만 직접 참조한다.
  - 테스트: `test/core/theme/`(`retro_palette_test` 대비 24쌍, `retro_text_test`, `pixel_border_test`, `pixel_icons_test`, `app_mark_test`),
    `test/core/widgets/initial_badge_test.dart`, `test/features/battle/presentation/battle_chips_test.dart`, `vs_intro_test.dart` 등.
  - `pubspec.yaml`: `uses-material-design: true`(Material Icons 글꼴이 이미 앱에 들어 있다), 갈무리 TTF 2개 + LICENSE 자산.

---

## 1. 원인 후보 4개와 해결 (수용 기준 "무엇으로 해결했는지")

| 원인 후보 | 이번 해결 |
|---|---|
| 1. 픽셀 글꼴 번짐(24dp 이상 제목·숫자, 그리고 12dp 숫자 칸) | 갈무리를 앱·위젯·아이콘 어디에서도 쓰지 않는다. 모든 글자를 Pretendard 한 벌(400/700/800)로 번들. 숫자 칸은 전용 숫자 슬롯 3개(16/20/32dp, 굵게, 고정폭 숫자)로 옮겨 **12dp 픽셀 숫자를 없앤다**. |
| 2. 전면 2dp 잉크 테두리 + 계단 모서리 → 잡음, 평평한 위계 | 테두리는 **조작 요소 경계**(입력 필드·체크박스·보조 버튼·선택 컨트롤)와 **꼭 구분해야 할 칩**(모집 중 점선, 무효 점선, 판정 중, 미결, 무)에만. 카드는 1dp 연한 선, 안내 블록은 테두리 없음. 남색 두께는 **누르는 버튼에만** 써서 "누를 수 있음"의 신호를 하나로 모은다. 계단 모서리 → 둥근 모서리(8/12/16/20/24). |
| 3. 크림 계열끼리라 층이 안 갈림 | 배경을 차가운 회청색(`background #EEF1F6`), 카드를 흰색(`surface #FFFFFF`)으로 나누고, 떠 있는 카드에 2dp 회색 아래 두께(`edge`)를 붙인다. 가라앉은 면(`sunken #E2E7EF`)은 배경보다 어둡다. 세 층이 "가라앉음 < 배경 < 떠 있음" 순으로 갈린다. |
| 4. 작은 픽셀 아이콘 뭉개짐 | 12×12 비트맵 → **Material Icons Rounded**(벡터, 안티에일리어싱). 최소 크기 16dp(이전 12dp). 이미 앱에 들어 있는 글꼴이라 새 패키지 없음. |

---

## 2. 시각 규칙 — 색 (P0-1)

### 2.1 구조
- 팔레트는 **중립·의미색 공통 + 브랜드 묶음만 시안별로 다름**이다. 그래서 시안을 바꿔도 대비 검증·테스트 표의 공통 부분은 그대로고,
  브랜드 묶음(주 강조·주 강조 진함·주 강조 연함·보조 강조·판정 중 색) 몇 줄만 바뀐다.
- 앱 안의 모든 색은 한 파일의 팔레트에서만 나온다(retro-theme 운영 규칙 승계). 런처 아이콘·홈 위젯 생성기도 이 파일을 읽는다.
- `ColorScheme.fromSeed`를 쓰지 않고 슬롯마다 명시한다(현행 방식 유지 — `scheme.xxx`를 써도 팔레트 밖 색이 안 나오게).
- 대비비는 WCAG 2.x 상대 휘도 공식으로 계산했다(현행 `contrastRatio`와 같은 공식). 소수 둘째 자리 반올림. 테스트는 ±0.05로 고정한다.

### 2.2 공통 토큰 (세 시안 공통)

| 토큰 | hex | 쓰임 |
|---|---|---|
| `background` | `#EEF1F6` | 화면 배경, 앱바 면, 시작 창, 위젯 바탕 |
| `surface` | `#FFFFFF` | 카드·대화상자·시트·입력 필드·탭바 면, 색 면 위 흰 글자 |
| `sunken` | `#E2E7EF` | 가라앉은 면(완료한 할 일, 인용, 모집 조작판), 비활성 버튼 면, 취소 칩, 사진 틀 여백 |
| `line` | `#D3D9E3` | 장식 구분선, 카드 1dp 선, 비활성 컨트롤 경계(예외 허용) |
| `edge` | `#B8C0CF` | 떠 있는 카드의 아래 두께(장식) |
| `outline` | `#6B7289` | **조작 요소 경계**: 입력 필드, 체크박스, 보조 버튼, 세그먼트, 점선·실선 칩 테두리 |
| `ink` | `#1B2033` | 본문 글자, 아이콘, **버튼 아래 두께**, 토스트 면 |
| `inkMuted` | `#4A5168` | 보조 글자, 비선택 탭, 완료한 할 일 글자, 패 라벨 면 |
| `inkDisabled` | `#767D93` | 비활성 글자·아이콘 |
| `success` | `#1D7A4C` | 종료 칩 면, 합격 아이콘, 성공 블록 아이콘 |
| `successPale` | `#DDF3E6` | 성공 블록 면 |
| `danger` | `#CC2F3F` | 위험 버튼 면, 위험 텍스트 버튼 글자, 오류 테두리·글자 |
| `dangerPale` | `#FDE3E4` | 차단·오류 블록 면 |
| `warning` | `#A65A00` | 미결 칩 테두리·아이콘(경고) |
| `warningPale` | `#FFF1D6` | 미결 칩 면 |
| `amber` | `#FFB020` | 속도전 색 칸, 승 라벨 면, 토스트 동작 글자. 시안 A·C에서는 보조 강조(상대)도 겸한다 |
| `mint` | `#4CC9B0` | 품질전 색 칸 |
| `violet` / `violetPale` | `#6247D6` / `#ECE6FF` | 판정 중 칩(시안 A·B) |

- 초록 계열은 **의미색**(`success`·`mint`)으로만 쓰고 둘 다 `#58CC02`(황록, 밝음)와 눈으로 구별되는 청록·짙은 숲색이다. 브랜드·런처 배경·마크에는 쓰지 않는다(IP).
- `warning`은 이번에 새로 생긴 의미색이다. retro-theme 승계 규칙 "`disputed` 경고"를 지키려고 `미결`을 위험색 계열에서 경고색 계열로 옮긴다(`무`는 여전히 중립).

#### 공통 글자/배경 쌍 (기준: 일반 4.5:1)

| 글자 / 배경 | 대비비 | 판정 | 어디에 |
|---|---|---|---|
| ink / surface | 16.14 | 통과 | 카드·대화상자 본문 |
| ink / background | 14.26 | 통과 | 화면 본문, 앱바 제목 |
| ink / sunken | 13.00 | 통과 | 인용, 무 칩 |
| inkMuted / surface | 7.87 | 통과 | 보조 글자, 힌트, 비선택 탭 라벨 |
| inkMuted / background | 6.95 | 통과 | 화면 보조 글자 |
| inkMuted / sunken | 6.34 | 통과 | 완료한 할 일, 취소 칩 |
| surface / ink | 16.14 | 통과 | 토스트·툴팁 글자 |
| amber / ink | 8.83 | 통과 | 토스트 동작 글자 |
| surface / inkMuted | 7.87 | 통과 | 패 라벨 |
| ink / amber | 8.83 | 통과 | 승 라벨, 상대 이니셜, 속도전 칸 아이콘 |
| ink / mint | 7.91 | 통과 | 품질전 칸 아이콘 |
| surface / success | 5.33 | 통과 | 종료 칩 |
| success / surface | 5.33 | 통과 | 합격 문구(있으면) |
| success / background | 4.71 | 통과 | |
| success / successPale | 4.58 | 통과 | 성공 블록 아이콘·강조 |
| ink / successPale | 13.86 | 통과 | 성공 블록 본문 |
| surface / danger | 5.19 | 통과 | 위험 버튼 라벨 |
| danger / surface | 5.19 | 통과 | 오류 글자, 위험 텍스트 버튼(대화상자 안) |
| danger / background | 4.58 | 통과 | 포기 텍스트 버튼(화면 위) |
| ink / dangerPale | 13.29 | 통과 | 차단·오류 블록 본문 |
| danger / dangerPale | 4.27 | **글자 불가**(아이콘만) | 블록 아이콘 — 블록 글자는 ink로만 |
| warning / surface | 5.14 | 통과 | |
| warning / background | 4.54 | 통과 | |
| warning / warningPale | 4.60 | 통과 | 미결 칩 아이콘 |
| ink / warningPale | 14.45 | 통과 | 미결 칩 글자 |
| ink / violetPale | 13.32 | 통과 | 판정 중 칩 글자(A·B) |
| inkDisabled / surface | 4.10 | 비활성(3:1 목표) 통과 | 비활성 텍스트 버튼 |
| inkDisabled / sunken | 3.30 | 비활성(3:1 목표) 통과 | 비활성 버튼 라벨 |
| inkDisabled / background | 3.62 | 비활성(3:1 목표) 통과 | |

#### 공통 비텍스트 쌍 (기준: 3:1, SC 1.4.11)

| 요소 / 인접 색 | 대비비 | 판정 | 어디에 |
|---|---|---|---|
| outline / surface | 4.78 | 통과 | 입력 필드·체크박스·보조 버튼·세그먼트 경계(흰 면 위) |
| outline / background | 4.22 | 통과 | 같은 요소가 화면 배경에 놓일 때 |
| outline / sunken | 3.85 | 통과 | 모집 조작판(sunken) 위 검색 필드 |
| ink / background | 14.26 | 통과 | 버튼 아래 두께, 아이콘 |
| danger / surface · background | 5.19 · 4.58 | 통과 | 오류 입력 테두리 |
| success / surface | 5.33 | 통과 | 합격 아이콘 |
| warning / warningPale | 4.60 | 통과 | 미결 아이콘·테두리 |
| violet / violetPale | 5.11 | 통과 | 판정 중 칩 테두리 |
| inkMuted / surface | 7.87 | 통과 | 비선택 탭 아이콘, 삭제 아이콘 |
| amber / surface | 1.83 | **미달 — 장식으로만** | 속도전 색 칸·승 라벨 면. 뜻은 칸 안의 ink 아이콘(8.83)과 글자가 전달하므로 면 경계에 기대지 않는다 |
| mint / surface | 2.05 | **미달 — 장식으로만** | 품질전 색 칸. 같은 이유 |
| line · edge / background | 1.25 · 1.62 | 장식(기준 대상 아님) | 카드 선·카드 두께. 층 구분은 면 대비 + 두께 + 그림자 위치로 함께 낸다 |

### 2.3 브랜드 시안 3개

세 시안 모두 "나 = 주 강조, 상대 = 보조 강조" 규칙(VS 인트로·이니셜, retro-theme와 같음)을 지킨다.

#### 시안 A — 밝은 파랑 + 앰버 (기본안, **designer 추천**)
> 인상: "지금 앱의 파랑을 한 단계 켠 화사한 경기장" — 기존 아이콘·VS 규칙과 이어지고, 앰버가 승리·속도의 열기를 맡는다.

| 토큰 | hex | 비고 |
|---|---|---|
| `primary` | `#3355FF` | 현 `#2F48B8`보다 밝고 채도 높음. 주 버튼, 진행 중 칩, 선택 상태, 런처 배경, 나 |
| `primaryDeep` | `#2238C8` | 글자로 쓰는 브랜드색(텍스트 버튼, 기준 번호, 선택 탭 아이콘) |
| `primaryPale` | `#E3E9FF` | 안내 블록 면, 선택 탭 표시기 |
| `secondary` | `#FFB020`(= amber) | 상대 |
| 판정 중 | `violet`/`violetPale` | 공통 토큰 |

| 쌍 | 대비비 | 기준 | 판정 |
|---|---|---|---|
| surface / primary (주 버튼 라벨·진행 중 칩·나 이니셜) | 5.41 | 4.5 | 통과 |
| primary / surface (링크형 글자) | 5.41 | 4.5 | 통과 |
| primary / background | 4.78 | 4.5 | 통과 |
| primaryDeep / surface · background · sunken (텍스트 버튼) | 8.51 · 7.52 · 6.85 | 4.5 | 통과 |
| ink / primaryPale (안내 블록 본문) | 13.35 | 4.5 | 통과 |
| primaryDeep / primaryPale (선택 탭 아이콘·라벨) | 7.04 | 4.5 | 통과 |
| primary / primaryPale | 4.47 | 4.5 | **글자 불가**, 아이콘(3:1)만 통과 |
| 주 버튼 면 / background (경계) | 4.78 | 3 | 통과 |
| 주 버튼 면 / surface (카드·대화상자 안) | 5.41 | 3 | 통과 |
| 포커스 링 primary / surface · background | 5.41 · 4.78 | 3 | 통과 |
| 체크박스 선택 면 primary / sunken (완료한 할 일 줄) | 4.35 | 3 | 통과 |
| amber / primary (런처 마크의 체크 / 배경) | 2.96 | 3 | 미달 → 체크에 ink 두께를 둘러 ink/amber 8.83, ink/primary로 윤곽을 세운다 |

#### 시안 B — 주황 + 파랑 (retro 이전 주황 계열로 복귀)
> 인상: "가장 뜨겁고 경쟁적" — 에너지는 가장 강하지만 흰 글자를 못 올려 버튼이 남색 글자가 되고, 위험·경고색과 붙어 보인다.

| 토큰 | hex | 비고 |
|---|---|---|
| `primary` | `#F26B1D` | 밝은 주황. **흰 글자 3.05로 미달** → 주 버튼·진행 중 칩 라벨은 ink |
| `primaryDeep` | `#B5400B` | 글자·작은 조작 요소(체크박스 선택 면, 포커스 링, 선택 탭 아이콘) |
| `primaryPale` | `#FFE6D6` | 안내 블록 면, 선택 탭 표시기 |
| `secondary` | `#3355FF` | 상대(흰 이니셜 5.41) |
| 판정 중 | `violet`/`violetPale` | 공통 토큰 |

| 쌍 | 대비비 | 기준 | 판정 |
|---|---|---|---|
| ink / primary (주 버튼 라벨·진행 중 칩·나 이니셜) | 5.30 | 4.5 | 통과 |
| surface / primary | 3.05 | 4.5 | **미달** — 흰 글자 금지 |
| primaryDeep / surface · background · sunken | 5.67 · 5.01 · 4.57 | 4.5 | 통과(sunken은 여유 적음) |
| ink / primaryPale | 13.48 | 4.5 | 통과 |
| primaryDeep / primaryPale | 4.74 | 4.5 | 통과 |
| primary / primaryPale | 2.54 | 3 | **미달** — 안내 아이콘도 primaryDeep |
| 주 버튼 면 / background (경계) | 2.69 | 3 | **미달** → 주 버튼에 1.5dp ink 테두리를 더해야 한다(테두리를 줄이려는 개편 방향과 어긋남) |
| 체크박스 선택 면 primary / sunken | 2.45 | 3 | **미달** → 선택 면을 primaryDeep으로(흰 체크 5.67) |
| surface / secondary (상대 이니셜) | 5.41 | 4.5 | 통과 |
| 주황 primary vs danger(`#CC2F3F`) 휘도비 | 1.70 | — | 색상 거리도 가까움 — 위험 버튼(흰 글자)과 주 버튼(남색 글자)의 글자색 차이에 기대게 된다 |

#### 시안 C — 보라 + 앰버 (새 색)
> 인상: "가장 차별화된 게임 브랜드" — 투두 앱에서 드문 색이라 기억에 남지만, 근거가 시안뿐이고 기존 파랑 자산과 끊긴다.

| 토큰 | hex | 비고 |
|---|---|---|
| `primary` | `#6C47FF` | 주 버튼, 진행 중 칩, 선택, 런처 배경, 나 |
| `primaryDeep` | `#4B2CC9` | 글자로 쓰는 브랜드색 |
| `primaryPale` | `#ECE6FF` | 안내 블록 면, 선택 탭 표시기 |
| `secondary` | `#FFB020`(= amber) | 상대 |
| 판정 중 | `sky #1F6FC4` / `skyPale #DCEEFF` | 보라가 브랜드라 판정 중을 하늘색으로 옮긴다(진행 중과 같은 계열이 되지 않게) |

| 쌍 | 대비비 | 기준 | 판정 |
|---|---|---|---|
| surface / primary | 5.27 | 4.5 | 통과 |
| primary / background | 4.66 | 4.5 | 통과 |
| primary / sunken | 4.25 | 4.5 | 글자 불가(작은 조작 요소 3:1은 통과) |
| primaryDeep / surface · background · sunken | 8.39 · 7.41 · 6.76 | 4.5 | 통과 |
| ink / primaryPale | 13.32 | 4.5 | 통과 |
| primaryDeep / primaryPale | 6.92 | 4.5 | 통과 |
| primary / primaryPale | 4.35 | 3 | 아이콘만 통과 |
| 주 버튼 면 / background | 4.66 | 3 | 통과 |
| 포커스 링 primary / surface · background | 5.27 · 4.66 | 3 | 통과 |
| ink / skyPale (판정 중 글자) | 13.62 | 4.5 | 통과 |
| sky / skyPale (판정 중 테두리) | 4.29 | 3 | 통과 |
| amber / primary (런처 마크) | 2.88 | 3 | 미달 → A와 같이 ink 두께로 윤곽 |

#### 시안 비교 요약

| | A 밝은 파랑 + 앰버 | B 주황 + 파랑 | C 보라 + 앰버 |
|---|---|---|---|
| 주 버튼 라벨 | 흰색 5.41 | **남색** 5.30(흰색 불가) | 흰색 5.27 |
| 주 버튼 경계 vs 배경 | 4.78 | **2.69 — ink 테두리 추가 필요** | 4.66 |
| 위험색과의 구분 | 쉬움(파랑 vs 빨강) | **어려움**(주황 vs 빨강·경고 갈색) | 쉬움 |
| 기존 자산과 연속성 | 높음(파랑 마크·나=파랑) | 중간(retro 이전 주황) | 낮음 |
| 추가 규칙 | 없음 | 남색 라벨, ink 테두리, 작은 조작 요소는 진한 주황 | 판정 중 색을 하늘색으로 |
| 차별성 | 중간 | 높음 | 가장 높음 |

**designer 추천: 시안 A.** 세 시안 중 유일하게 추가 예외 규칙이 없고(B는 3개, C는 1개), 위험 버튼과의 구분이 가장 쉬워
"되돌릴 수 없는 버튼"(판정 보내기·포기·계정 삭제)을 잘못 누를 위험이 가장 작다. 가독성 1순위라는 spec 목적에 가장 맞는다.

---

## 3. 시각 규칙 — 서체 (P0-1, 결정 3·4)

### 3.1 번들
- **Pretendard 한 벌**(SIL OFL 1.1). 정적 굵기 파일 **3개**: Regular(400), Bold(700), ExtraBold(800). 가변 글꼴 하나로 넣지 않는다 —
  Flutter에서 `fontWeight`가 가변 축으로 자동 연결되는지에 기대지 않고, 정적 파일이 굵기 매칭이 확실하다.
  - 500·600은 넣지 않는다: 역할표가 400(문장)·700(라벨·제목)·800(큰 숫자·표제) 세 단계로 위계를 낸다. 넣는 굵기는 실제로 쓰는 굵기로 제한(spec).
  - 300 이하는 넣지 않는다(가는 굵기 금지 수용 기준).
- 출처: Pretendard 공식 GitHub 릴리스 zip의 정적 파일(OTF 또는 TTF)과 동봉 `LICENSE.txt`. **파일을 서브셋·이름 변경·병합하지 않는다**
  (OFL의 예약 글꼴 이름 규칙 — 파생물이 되면 이름을 바꿔야 한다. 갈무리와 같은 원칙).
- 용량: 굵기당 수 MB 단위로 예상된다(정적 파일 3개). **정확한 값은 developer가 실측해 커밋 메시지에 남긴다**(수용 기준). 갈무리 2개
  제거분과 함께 "AAB 크기 전/후"를 적는다.
- **현대 한글 11,172자 지원 확인**: 번들하는 세 파일 각각의 cmap에 U+AC00–U+D7A3이 빠짐없이 있는지 developer가 1회 확인하고
  (예: fontTools로 개수 세기) 결과를 커밋 메시지에 적는다. 하나라도 빠지면 그 굵기는 쓰지 않고 오너에게 알린다.
- 갈무리: **완전히 제거** — `pubspec.yaml`의 글꼴·자산 항목, `assets/fonts/galmuri/`, `main.dart`의 갈무리 고지 등록, 모든 `RetroText.pixel`/
  `numeric` 사용처. VS 인트로·로그인 앱 이름도 Pretendard.
- 라이선스 고지: Pretendard `LICENSE.txt`를 자산으로 넣고 `LicenseRegistry`에 패키지 이름 `Pretendard`로 등록한다(갈무리 등록을 대체).
  오픈소스 라이선스 화면(`showLicensePage`)에 Pretendard가 보이고 Galmuri는 사라진다.
- 앱 전체 기본 글꼴: `ThemeData(fontFamily: 'Pretendard')`. TextTheme 슬롯에도 같은 패밀리를 적는다(Material이 머지할 때 'Roboto'가 붙는
  현행 동작을 막기 위해 — `retro_text_test`의 런타임 머지 검사를 이어받는다). 이모지 등 Pretendard에 없는 글자는 시스템 폴백에 맡긴다.

### 3.2 글자 역할표 (배율 1.0 기준, 모든 슬롯 `letterSpacing: 0`)

| 슬롯 | 역할(어디에) | 크기 | 굵기 | 행간 |
|---|---|---|---|---|
| `displayLarge` | (예비, 현재 쓰는 곳 없음) | 40 | 800 | 1.25 |
| `displayMedium` | 로그인 앱 이름 | 34 | 800 | 1.25 |
| `displaySmall` | (예비) | 28 | 800 | 1.3 |
| `headlineLarge` | (예비) | 26 | 700 | 1.35 |
| `headlineMedium` | (예비) | 24 | 700 | 1.35 |
| `headlineSmall` | 대화상자 제목 | 22 | 700 | 1.4 |
| `titleLarge` | 앱바 제목 | 20 | 700 | 1.4 |
| `titleMedium` | 결과 배너 헤드라인, VS 명판 이름, 큰 결과 라벨 | 18 | 700 | 1.45 |
| `titleSmall` | 묶음 제목(옛 "창 제목 띠"), 안내 블록 제목, 판정 질문 | 16 | 700 | 1.5 |
| `bodyLarge` | **할 일 내용, 목록 주 텍스트(대결 제목·상대 이름), 입력 글자** | 16 | 400 | 1.6 |
| `bodyMedium` | **문장**: 안내·경고·오류·대화상자 본문·동의 문구·판정 기준·마감 줄·"판정은 한 번만" | 15 | 400 | 1.6 |
| `bodySmall` | 메타데이터만(자리 이름 "상대", 보조 문장, 시각 옆 설명). 놓치면 손해 보는 문장 금지 | 13 | 400 | 1.55 |
| `labelLarge` | 버튼 라벨, 세그먼트 라벨 | 16 | 700 | 1.4 |
| `labelMedium` | 칩·배지·카운터, VS "상대"/"나" | 14 | 700 | 1.4 |
| `labelSmall` | 하단 탭 라벨(선택 700 / 비선택 400) | 12 | 700 | 1.35 |

숫자 슬롯(TextTheme 밖, 같은 파일에 상수로. **고정폭 숫자 `FontFeature.tabularFigures()`**):

| 슬롯 | 어디에 | 크기 | 굵기 | 행간 |
|---|---|---|---|---|
| `numberLarge` | 프로필 점수 | 32 | 800 | 1.2 |
| `numberMedium` | 결과 배너 점수 변화 | 20 | 800 | 1.3 |
| `numberSmall` | 상대 카드 점수·전적, 프로필 전적, 기준 번호, 제출 시각 | 16 | 700 | 1.4 |

- 수용 기준 대조: 최소 12(탭 라벨) ✓, 문장 15 ✓(14 이상), 목록 주 텍스트 16 ✓, 여러 줄 본문 행간 1.55~1.6 ✓, 음수 자간 없음 ✓,
  400 미만 굵기 없음 ✓. 제목·라벨 슬롯은 한두 줄짜리라 1.25~1.5를 쓴다(SC 1.4.12 대상은 본문).
- 마감·남은 시간 줄(`bodyMedium`)에도 고정폭 숫자를 켠다 — 바뀌는 숫자의 폭이 흔들리지 않게(P1-1). Pretendard의 `tnum` 지원 여부를
  developer가 확인한다(없으면 숫자 슬롯만 폭 고정 대상에서 빠진 것으로 보고하고 넘어간다).
- 같은 역할의 글자는 이 표 밖의 크기를 쓰지 않는다. 화면에서 `copyWith(fontSize: …)`로 새 크기를 만들지 않는다(색·굵기 700 강조만 허용).
- 큰 글자 판정(24dp 이상 또는 굵게 18.66dp 이상)에 기대 3:1로 내려가는 조합은 **하나도 쓰지 않는다** — 모든 글자 조합을 4.5:1로 맞췄다.

### 3.3 시스템 글자 크기 (결정 7)
- `maxTextScale = 1.5`(현행 1.3). 시스템 설정을 따르되 1.5에서 멈춘다(`MediaQuery.withClampedTextScaling` 유지).
- 1.5배에서 탭 라벨은 18dp가 된다. 360dp 폭 4칸(칸당 90dp)에서 가장 긴 "대결 찾기"는 약 72dp로 들어간다(Pretendard 한글 너비 ≈ 0.93em 추정) —
  **육안 확인 목록** 1번 항목. 넘치면 탭 라벨만 `labelSmall`을 유지한 채 칸 안쪽 여백을 줄인다(글자 크기는 줄이지 않는다).

---

## 4. 시각 규칙 — 모양·그림자·간격·테두리·움직임 (P0-1)

### 4.1 토큰

| 분류 | 토큰 | 값 | 쓰임 |
|---|---|---|---|
| 모서리 | `radiusS` | 8 | 칩·배지, 유형 색 칸 |
| | `radiusM` | 12 | 버튼, 입력 필드, 안내 블록, 토스트, 이니셜(카드), 사진 틀 |
| | `radiusL` | 16 | 카드·묶음, FAB, 탭 표시기, 이니셜(인트로) |
| | `radiusXL` | 20 | 대화상자, VS 명판 |
| | `radiusSheet` | 24(위 두 모서리) | 바텀시트 |
| | 체크박스 | 6 | |
| 두께(단단한 아래 그림자) | `depthButton` | 3dp, **`ink` 고정** | 주·보조·위험 버튼, FAB, 승 라벨, VS 명판(4dp) |
| | `depthCard` | 2dp, `edge` | 떠 있는 카드(안 한 할 일, 상대 카드, 모집 카드, 승리 배너) |
| 테두리 | `hairline` | 1dp `line` | 카드·묶음 |
| | `control` | 1.5dp `outline` | 입력 필드, 보조 버튼, 세그먼트, 칩 실선·점선 |
| | `strong` | 2dp | 체크박스, 포커스 링(브랜드), 오류 입력(`danger`), 선택 세그먼트 |
| 간격(4dp 단위) | `s1`·`s2`·`s3`·`s4`·`s5`·`s6`·`s8` | 4·8·12·16·20·24·32 | |
| | 화면 가장자리 | 20(현 16) | 목록·상세 좌우 |
| | 묶음 안 | 12(요소 사이) / 카드 안쪽 여백 16 | |
| | 묶음 사이 | 24(현 16) | 상세 화면 섹션 사이 |
| | 목록 항목 사이 | 12(현 8) | 할 일·대결 목록 |
| | 문장 ↔ 문장 | 8, 제목 ↔ 본문 4 | |
| 크기 | 버튼 최소 높이 | 52(두께 포함, 면 49) | 터치 영역 48 이상 |
| | 아이콘 버튼·체크박스 터치 영역 | 48×48 | |
| | 목록 줄 최소 높이 | 60 | 할 일 줄 |
| 장막 | 대화상자·시트 뒤 | `ink` 50% | |

- **흐린 그림자(elevation)는 쓰지 않는다.** 떠 있음 = 아래 단단한 두께, 층 = 면색 차이. Material의 `elevation`·`surfaceTint`는 전부 0/투명(현행 유지).
- 두께는 요소 바깥 크기 **안쪽**에 그린다 — 눌려도 레이아웃이 흔들리지 않는다(현 `PixelBorder` 원리 승계).
- 물결(ripple) 효과는 계속 쓰지 않는다(`NoSplash`). 눌림은 두께로 보인다.

### 4.2 눌리는 버튼 (게임감의 핵심)
- 모양: 둥근 사각(12) 면 + 아래 3dp `ink` 두께. 전체 높이 52 중 면 49.
- **눌림**: 면이 3dp 내려가 두께를 덮는다(두께 0). 글자·아이콘도 함께 내려간다. 바깥 크기는 그대로.
- 손을 떼면 120ms `easeOutCubic`으로 되돌아온다. 누를 때는 즉시(0ms). **애니메이션 줄이기면 되돌아옴도 즉시**(눌림 자체는 상태 표시라 남는다 — spec "버튼 눌림 제외").
- 변형:

| 위계 | 면 | 라벨 | 테두리 | 두께 | 비활성 |
|---|---|---|---|---|---|
| 주(`FilledButton`, FAB) | `primary` | 흰색(A·C) / ink(B) | 없음(B는 1.5dp ink) | 3dp ink | `sunken` 면 + `inkDisabled` 라벨, 두께·테두리 없음(납작) |
| 보조(`OutlinedButton`·`ElevatedButton`) | `surface` | ink | 1.5dp `outline` | 3dp ink | 같음 |
| 낮음(`TextButton`, `IconButton`) | 투명(누르면 `sunken`) | `primaryDeep`(텍스트) / ink(아이콘) | 없음 | 없음 | `inkDisabled` |
| 위험(`AppButtonStyles.danger`) | `danger` | 흰색 | 없음 | 3dp ink | 같음 |
| 위험 낮음(포기) | 투명 | `danger` | 없음 | 없음 | `inkDisabled` |

- 위험 버튼은 주 버튼과 **색(빨강 vs 브랜드) + 아이콘**(깃발·사람 빼기·문서 등 이미 붙은 아이콘)으로 구분된다. 포기는 지금처럼 낮은 위험 버튼(글자 + 깃발).
- 진행 중: `onPressed: null` + 라벨 자리에 `AppLoader.small`(버튼 크기 유지) — 현행 규칙 그대로.
- 포커스: 면 바깥 2dp 브랜드색 링(`primary`, B는 `primaryDeep`) + 2dp 간격.

### 4.3 레퍼런스(Duolingo)와 다른 점 (IP 수용 기준)

레퍼런스 쪽 내용은 references.md와 그 출처(제3자 정리)에 근거한다.

| 항목 | 레퍼런스(Duolingo) | 투두두두 |
|---|---|---|
| 색 | 초록 `#58CC02` 단일 브랜드, 버튼마다 **같은 색의 진한 톤**을 아래 그림자로 | 파랑 `#3355FF`(+ 앰버). 초록은 의미색(짙은 숲색 `#1D7A4C`, 청록 `#4CC9B0`)으로만. **아래 두께는 모든 버튼 공통 남색 `ink` 한 색** — retro-theme의 "남색 바닥 두께"를 이어받은 우리 표현 |
| 서체 | 자체 제작 둥근 디스플레이 서체 + 둥근 본문 서체, 버튼 라벨 대문자·넓은 자간 | Pretendard 한 벌(둥근 디스플레이 서체 없음). 대소문자 변형 없음, 자간 0 고정 |
| 버튼 | 모서리 약 16, 두께 4px, 보조 버튼은 연회색 테두리 + 같은 연회색 두께 | 모서리 12, 두께 3dp, 보조 버튼은 1.5dp 회청색 테두리 + **남색** 두께. 비활성은 두께가 사라진 납작한 면 |
| 카드 | (학습 카드·일러스트 중심) | 흰 면 + 1dp 선 + 2dp **회색** 두께(누르는 버튼의 남색 두께와 위계를 나눔) |
| 아이콘 | 자체 제작 색 채운 두꺼운 아이콘·일러스트 | Material Icons Rounded 단색(Apache 2.0). 일러스트 없음 |
| 마스코트 | 부엉이 등 캐릭터 다수 | **없음**(이니셜 글자만). 얼굴·새 형태 아이콘 금지 |
| 레이아웃·상징 | 학습 경로 지도, 연속 기록 불꽃, 하트·보석, 리그 | 기존 화면 배치 그대로(목록·카드·상세). 불꽃(`local_fire_department` 등)·하트·보석 아이콘을 쓰지 않는다 |
| 앱 아이콘 | 부엉이 얼굴 | 칸을 뚫고 나가는 체크 |

포켓몬 등 기존 IP 제약(캐릭터·로고·폰트·효과음·고유 대사·고유 도형·레이아웃)도 그대로다. VS 인트로의 명판·띠는 특정 게임의 대전 화면 배치를 따라 하지 않고 지금의 위아래 명판 구성을 유지한다.

### 4.4 움직임
- 계단식(50ms 단위) 움직임 규칙을 폐기한다. 곡선은 `easeOutCubic`, 길이는 짧게(120~250ms).
- 새로 생기는 움직임은 둘뿐이다: 버튼이 되돌아오는 120ms, VS 인트로. 로딩 표시기의 점 깜빡임은 부드러운 투명도 변화로 바뀐다.
- **모든 움직임은 `MediaQuery.disableAnimationsOf`를 따른다**: 버튼 되돌아옴 즉시, 로딩 점 전부 켜진 채 정지, VS 인트로 정지 화면.
- FAB 숨김은 지금처럼 애니메이션 없이 즉시(새 움직임을 만들지 않는다). 화면 전환은 Flutter 기본 그대로(이번에 손대지 않음).
- 효과음·진동 없음(`enableFeedback: false` 유지).

---

## 5. 화면

### 5.1 자동 적용(ThemeData) — 공용 Material 위젯

| 대상 | 새 모양 |
|---|---|
| 앱바 | `background` 면, 아래 경계선 없음(스크롤되면 1dp `line`), 제목 `titleLarge` ink, 뒤로 아이콘 `arrow_back_rounded` |
| 하단 탭바 | `surface` 면 + 위 1dp `line`(셸의 2dp ink 선 대체), 높이 72, 표시기 = `primaryPale` 알약(높이 32, 모서리 16). 선택: 채운 아이콘 `primaryDeep` + 라벨 700 ink / 비선택: 윤곽 아이콘 `inkMuted` + 라벨 400 `inkMuted`. 선택은 색 + 표시기 모양 + 아이콘 채움 + 굵기 넷으로 구분 |
| 주·보조·텍스트·아이콘 버튼, FAB | 4.2 |
| 대화상자 | `surface`, 모서리 20, 테두리 없음, 제목 `headlineSmall`, 본문 `bodyMedium`, 버튼 줄은 오른쪽 정렬 그대로 |
| 바텀시트 | `surface`, 위 모서리 24, 손잡이 32×4 `outline` 둥근 막대 |
| 토스트(SnackBar) | 떠 있는 `ink` 면, 모서리 12, 글자 `bodyMedium` 흰색, 동작 글자 amber |
| 입력 필드 | `surface` 면, 모서리 12, 1.5dp `outline` / 포커스 2dp 브랜드 / 오류 2dp `danger` + 오류 문장(글자로도 구분) / 비활성 1.5dp `line`. 힌트 `inkMuted`. 이중선 포커스(`_DoubleOutlineInputBorder`)는 없앤다 |
| 세그먼트(`SegmentedButton`) | 높이 52, 비선택 `surface` + 1.5dp `outline` + ink / 선택 브랜드 면 + 흰 라벨(B는 ink) + **체크 아이콘**(색에만 기대지 않게 — 판정 창의 `showSelectedIcon: false`를 켜는 것으로 바꾼다), 모서리 12 |
| 체크박스 | 24dp, 모서리 6, 2dp `outline` / 선택: 브랜드 면(B는 `primaryDeep`) + 흰 체크 |
| 목록 줄(ListTile) | 제목 `bodyLarge`, 부제 `bodyMedium` `inkMuted` |
| 구분선 | 1dp `line` |
| 진행 표시(선형·원형) | 브랜드색 / 트랙 `primaryPale` |
| 툴팁 | `ink` 면, 모서리 8, 흰 글자 `bodySmall` |
| 펼침 목록(ExpansionTile) | 테두리 없음(현행), 펼침 아이콘은 Material 기본(벡터)이라 그대로 맞는다 |

### 5.2 공용 위젯 교체 매핑 (P0-2)

이름에서 "Pixel/Retro"를 떼고 `App*`로 바꾼다(옛 모양 이름이 남으면 다음 작업자가 오해한다). **생성자 모양·인자는 최대한 유지**해
호출부 변경을 이름 치환 수준으로 줄인다.

| 기존 | 새 이름 | API | 변경점 |
|---|---|---|---|
| `RetroPalette` | `AppPalette` | 정적 `Color` 상수. `contrastRatio()` 함께 이동 | 2장 토큰. `paper`→`background`, `amber` 유지, `primaryDeep`·`outline`·`edge`·`success/Pale`·`warning/Pale`·`violet/Pale`(C는 `judging/Pale`로 이름 통일 권장) 추가, `lavender` 제거 |
| `RetroText` | `AppText` | `textTheme()` + 숫자 슬롯 3개 상수 | `pixel()`·`numeric`·`grid`·`pixelFamily` 제거. 3장 표 |
| `PixelBorder` | `DepthBorder` (`OutlinedBorder`) | `side`, `radius`, `depth`, `depthColor`, `pressed`, `dashed`, `topOnly` | 계단 모서리 → 둥근 모서리. 아래 두께만(오른쪽 두께 없음). 눌림 = 면이 두께만큼 내려옴. `innerColor`(이중선) 제거. 점선은 둥근 사각 경로를 따라 끊는다 |
| `PixelIcon` + `PixelIcons` | 표준 `Icon` + `AppIcons`(`IconData` 상수 모음) | `Icon(AppIcons.todo)` | 위젯 하나가 사라지고 Flutter `Icon`을 쓴다. `IconTheme` 색·크기를 그대로 따른다. 크기 16 / 20 / 24 / 40 |
| `PixelFrame.raised/.flat/.inset/.tone` | `AppPanel.raised/.flat/.inset/.tone` | 같은 생성자·인자(`title`, `onTap`, `padding`, `tone`, `icon`). `icon` 타입만 `IconData?` | raised = surface + 1dp `line` + 2dp `edge` 두께(onTap이면 눌림), flat = surface + 1dp `line`, inset = `sunken` 테두리 없음, 모서리 16. **제목 띠(ink 띠 + 흰 글자) → 묶음 안 첫 줄 `titleSmall` ink 제목**. 기본 안쪽 여백 12 → 16 |
| `PixelTone` | `AppTone` | info / success / danger / neutral | tone 블록: 연한 면(primaryPale / successPale / dangerPale / sunken) + **테두리 없음** + 왼쪽 24dp 아이콘(primary(B는 primaryDeep) / success / danger / inkMuted), 제목 `titleSmall`, 본문 `bodyMedium` ink, 모서리 12 |
| `PixelTag` / `PixelTagStyle` / `PixelTagSize` | `AppTag` / `AppTagStyle` / `AppTagSize` | `fill`, `textColor`, `borderColor`, `dashed`, `raised` 유지 + `icon`(`IconData?`) 추가 | small: 최소 높이 28, 좌우 10, `labelMedium` / large: 최소 높이 40, 좌우 14, `titleMedium`(픽셀 24 대체). 모서리 8. 테두리 1.5dp. raised = 2dp ink 두께. 높이는 최소값만(1.5배에서 늘어남) |
| `neutralPixelTagStyle` | `neutralTagStyle` | | 무 칩과 같은 모양 |
| `RetroButtonStyles.danger` | `AppButtonStyles.danger` | `ButtonStyle` 상수 | 면 `danger`, 라벨 흰색, 두께·눌림은 테마를 따름 |
| `PixelLoader.small/.medium` | `AppLoader.small/.medium` | 같음 | 둥근 점 3개(6 / 8dp, 간격 4/6), `inkMuted` ↔ `line`, 부드러운 투명도 물결(900ms 주기). 줄이기면 셋 다 `inkMuted`로 정지. 시맨틱 라벨 `AppStrings.loading` 유지 |
| `StatusMessage` | 이름 유지 | `icon` 타입만 `IconData?` | 아이콘 40(빈 상태 `inkMuted`, 오류 `danger`), 문장 `bodyMedium` 가운데, 보조 `bodySmall` `inkMuted`, 간격 12 |
| `InitialBadge` | 이름 유지 | 같음 | 둥근 사각(카드 40/모서리 12, 인트로 72/모서리 16). 글자 Pretendard 800(카드 20, 인트로 32). 글자색 규칙(`fill == primary` → 흰색, 그 밖 ink)은 B에서 반대(주황 면 → ink, 파랑 면 → 흰색)라 **면색 → 글자색 매핑을 팔레트 쪽 함수 하나**로 둔다. 두께는 인트로만 3dp ink |
| `EvidencePhotoFrame` | 이름 유지 | 같음 | 바깥 둥근 사각(12) `sunken` 면 + 안쪽 여백 6(현 4) → 사진. **사진에 clip을 걸지 않는다**(둥근 모서리가 사진 픽셀을 깎지 않게 — 여백 6이면 모서리 반지름 12의 곡선 안쪽에 사진 모서리가 들어간다). `BoxFit.contain`, `filterQuality` 기본, `cacheWidth` 없음 그대로. 실패 상태 아이콘 `broken_image_rounded` 40 |
| `BattleTypeBadge` | 이름 유지 | 같음 | 테두리 없음(유지), `surface` 면 모서리 8, 왼쪽 24×24 색 칸(amber / mint, 모서리 6) 안 16dp ink 아이콘(`bolt` / `workspace_premium`) + `labelMedium` 글자 |
| `BattleStatusChip`, `ResultLabel`, `battleStatusTagStyle`, `resultTagStyle`, `battleTypeAccent` | 이름 유지 | 반환 타입만 `AppTagStyle` | 5.3 표 |
| `_DoubleOutlineInputBorder` | 제거 | | 포커스 = 2dp 브랜드 단일선 |
| `AppMark`(16×16 비트맵) | `AppMark`(벡터 그리기) | `paint(Canvas, Size, {monochrome})` 또는 같은 역할의 `CustomPainter` | 9장. 로그인·런처 생성기가 같은 그리기 코드를 쓴다 |

### 5.3 상태 칩 8종·결과 라벨 (의미 구분 승계)

| status | 글자(기존 문자열 그대로) | 면 | 테두리 | 글자 | 색 외 구분 |
|---|---|---|---|---|---|
| `pending` 모집 중 | (현재 칩으로 안 보임 — 문자열 추가 안 함, retro-theme와 같음) | surface | 1.5dp `outline` **점선** | ink | 점선 |
| `active` 진행 중 | 진행중 | primary | 없음 | 흰색(B는 ink) | 꽉 찬 브랜드 면 + 글자 |
| `judging` 판정 중 | 판정중 | violetPale(C는 skyPale) | 1.5dp violet(C는 sky) 실선 | ink | 연한 면 + 실선 + 글자 |
| `finished` 종료 | 종료 | success | 없음 | 흰색 | 글자 |
| `draw` 무 | 무승부 | surface | 1.5dp `outline` 실선 | ink | 실선(점선인 모집 중과 다름). **위험색 아님** |
| `disputed` 미결 | 미결 | warningPale | 1.5dp warning | ink | **경고 아이콘(`warning_amber_rounded` 16)** + 글자 — 무와 면·테두리·아이콘이 모두 다름 |
| `cancelled` 취소 | (현재 칩으로 안 보임) | sunken | 없음 | inkMuted | 흐린 글자 |
| `voided` 무효 | 무효 | 투명 | 1.5dp inkMuted **점선** | inkMuted | 면 없음 + 점선 + 흐린 글자 = 가장 약함 |

| 결과 | 면 | 테두리·두께 | 글자 | 강도 |
|---|---|---|---|---|
| 승 | amber | 2dp ink 두께(유일하게 떠 있음) | ink | 가장 강함 |
| 패 | inkMuted | 없음 | 흰색 | 보통 |
| 무 | `draw` 칩과 같음 | | | 중립 |
| 무효 | `voided` 칩과 같음 | | | **가장 약함** |

- 알 수 없는 status → `draw`와 같은 중립(현행 동작 유지).
- `battle_chips_test`의 의미 검사(무 ≠ 미결, 무에 위험색 없음, 무효가 가장 약함)를 새 값으로 갱신한다.

### 5.4 앱 안 아이콘 교체 (P0-3)

- **출처: Flutter SDK에 들어 있는 Material Icons의 Rounded 변형**(`Icons.*_rounded`). `uses-material-design: true`로 이미 앱에 번들돼 있고
  릴리스 빌드는 쓰는 글리프만 남기는 아이콘 트리 셰이킹을 한다 → **새 패키지 없음**. Material Symbols는 별도 패키지(pub)가 필요해 쓰지 않는다.
- 라이선스: Material Icons는 Apache 2.0. developer가 앱의 오픈소스 라이선스 화면에 이미 이 고지가 Flutter 엔진 라이선스와 함께 나오는지
  확인하고, 없으면 Apache 2.0 고지를 Pretendard와 같은 방식으로 추가한다.
- 한 벌 규칙: 전부 Rounded 변형, 한 색(현재 `IconTheme` 색), 크기 16/20/24/40. 탭바만 선택=채움·비선택=윤곽 변형을 쓴다.
- 얼굴·캐릭터·마스코트·새 형태, 불꽃·하트·보석 금지. 패배 = 얼굴 금지 규칙 유지(아래로 꺾인 화살표).
- 아래 상수 이름은 **developer가 Flutter `Icons` 클래스에 실제로 있는지 확인**한다. 없으면 같은 줄의 대안을 쓴다.

| 픽셀 아이콘 | 쓰는 곳 | 새 아이콘(`Icons.`) | 대안 |
|---|---|---|---|
| `battle` 교차한 칼 | 내 대결 탭, 대결 만들기 FAB | `sports_mma_rounded`(글러브) / 비선택 `sports_mma_outlined` | **결정 필요 2** |
| `search` | 대결 찾기 탭, 검색 필드 | `search_rounded` | |
| `todo` | 할 일 탭, 빈 할 일 | `check_box_rounded` / 비선택 `check_box_outlined` | |
| `profile` | 프로필 탭 | `person_rounded` / 비선택 `person_outline_rounded` | |
| `add` | FAB, 기준 항목 추가 | `add_rounded` | |
| `back` | 앱바 뒤로 | `arrow_back_rounded` | |
| `logout` | 로그아웃 | `logout_rounded` | |
| `accountDelete` | 계정 삭제 | `person_remove_rounded` | `person_off_rounded` |
| `delete` | 할 일 삭제 | `delete_outline_rounded` | `delete_rounded` |
| `check` | 세그먼트 선택 표시 | `check_rounded` | |
| `speed` | 속도전 배지 | `bolt_rounded` | `flash_on_rounded` |
| `quality` | 품질전 배지 | `workspace_premium_rounded`(인장 리본) | `verified_rounded` |
| `flag` | 포기 | `flag_rounded` | `outlined_flag_rounded` |
| `camera` | 촬영·다시 찍기 | `photo_camera_rounded` | |
| `brokenImage` | 사진 불러오기 실패 | `broken_image_rounded` | |
| `trophy` | 승리 배너 | `emoji_events_rounded` | |
| `lose` | 패배 배너 | `trending_down_rounded` | `south_east_rounded` |
| `hourglass` | 무 배너, 판정 대기 블록 | `hourglass_bottom_rounded` | `hourglass_empty_rounded` |
| `warning` | 미결, 오류, 위험 블록, 무효 배너 | `warning_amber_rounded` | `error_outline_rounded` |
| `pass` | 성공 블록 기본 아이콘 | `check_circle_rounded` | |
| `info` | 안내 블록 | `info_outline_rounded` | `info_rounded` |
| `retry` | 다시 시도·다시 찍기 | `refresh_rounded` | |
| `remove` | 기준 항목 삭제 | `remove_circle_outline_rounded` | `remove_rounded` |
| `clock` | 남은 시간·제출 시각·판정 기한 경과 | `schedule_rounded` | |
| `document` | 동의 문구, 오픈소스 라이선스 | `description_outlined` | `article_rounded` |
| `close` | 시트 닫기, 검색어 지우기 | `close_rounded` | |
| `cursor` | 로그인 ▶ 깜빡임 | **없앤다** (9.4 로그인 참고) | |

정의만 있고 안 쓰는 7종(`gallery`, `fail`, `edit`, `expand`, `collapse`, `lock`, `openExternal`)은 옮기지 않는다(미래 대비 금지). 필요해지면 그때 같은 규칙으로 추가한다.

### 5.5 화면별 적용 메모 (P0-4 — 배치·흐름·문구 유지, 간격·줄바꿈·묶음 경계·글자 역할만 조정)

공통: 화면 가장자리 20, 상세 화면 섹션 사이 24, 목록 항목 사이 12, 모든 "창 제목 띠"는 묶음 안 `titleSmall` 제목으로. 12dp 픽셀 숫자는 전부 숫자 슬롯으로.

#### 기준 화면 1 — 할 일 목록 (전/후)

| | 전(retro) | 후 |
|---|---|---|
| 배경 / 카드 | 크림 `paper` 위 크림 `surface` 카드(대비 약함) | 회청 `background` 위 흰 카드 |
| 안 한 할 일 | 2dp ink 테두리 + 2dp 바닥 두께 + 계단 모서리 | `AppPanel.raised`: 흰 면 + 1dp 선 + 2dp 회색 두께, 모서리 16. 누르면(수정 대화상자) 두께가 꺼진다 |
| 완료한 할 일 | `sunken` 면(크림), 취소선 + `inkMuted` | `sunken` 면, 테두리·두께 없음(가라앉음), 체크박스 채움(브랜드), 글자 `inkMuted` + 취소선(선 색도 `inkMuted`). **면색·높낮이·체크·취소선 네 가지로 구분**(현행 원칙) |
| 할 일 내용 | 기기 기본 글꼴 16 | Pretendard `bodyLarge` 16/400/1.6, 줄바꿈 허용(말줄임 없음 — 현행과 같음) |
| 체크박스 | 직각 2dp ink | 24dp 모서리 6, 2dp `outline` / 선택 브랜드 면 + 흰 체크, 터치 48 |
| 삭제 | 픽셀 휴지통 ink | `delete_outline_rounded` 24 `inkMuted`, 터치 48, 툴팁 그대로 |
| 간격 | 목록 여백 16, 항목 사이 8 | 좌우 20·위 16·아래 96(FAB가 마지막 줄을 가리지 않게), 항목 사이 12, 줄 최소 높이 60 |
| 빈 상태 | 픽셀 todo 36 | `check_box_outlined` 40 `inkMuted` + 문장 |
| FAB | 계단 사각 primary | 56dp 모서리 16 브랜드 면 + 3dp ink 두께 + `add_rounded` |
| 앱바 | 픽셀 24 제목 + 아래 4dp ink 선 | Pretendard `titleLarge` 20/700, 경계선 없음 |
| 추가·수정 대화상자 | 픽셀 24 제목, 이중선 포커스 | `headlineSmall` 22 제목, 입력 필드 모서리 12, 포커스 2dp 브랜드, [취소](텍스트) [저장](주) |

#### 기준 화면 2 — 대결 상세 판정 창 (전/후)

| | 전(retro) | 후 |
|---|---|---|
| 머리(유형·상태·마감) | 배지·칩 2dp ink, 마감 두 줄 `bodyMedium` 14 | 배지·칩 5.3 표. 마감 두 줄 `bodyMedium` 15 + 고정폭 숫자. 두 줄 사이 4 → 8(제출 창 / 판정 창이 다른 시계임이 더 잘 갈리게) |
| 상대 카드 | raised 2dp ink, 점수·전적 **12dp 픽셀** | `AppPanel.raised`, 이니셜 40(상대 = 보조 강조), 이름 `bodyLarge`, 점수·전적 `numberSmall` 16/700 |
| "상대의 증거" 묶음 | ink 띠 + 흰 14 라벨 + 2dp ink 틀 | `AppPanel.flat` + 첫 줄 `titleSmall` 제목, 사진 틀 5.2(원본 그대로, clip 없음) |
| 최소 기준 / 우열 기준 | flat 2dp ink, 번호 12dp 픽셀, 기준 14 | `AppPanel.flat`, 번호 `numberSmall` `primaryDeep`, 기준 `bodyMedium` 15/1.6, 항목 사이 8, 힌트 `bodyMedium` |
| 판정 묶음 | flat 2dp ink + 제목 띠 | `AppPanel.flat` + `titleSmall` 제목. 안내 `bodyMedium` → 질문 `titleSmall`(16/700, 현 `bodyLarge` 16/400에서 역할 재배정 — 질문이 문장 속에 묻히지 않게) → 세그먼트(높이 52, 선택 시 체크 아이콘) → 불복 힌트 `bodyMedium` |
| 우열 세그먼트 | 두 칸 한 줄 | 같은 배치. 1.5배에서 "상대가 더 잘했다"가 칸을 넘으면 **라벨 두 줄 허용**(높이가 늘어남). 그래도 잘리면 두 칸을 위아래로 쌓는다(배치 조정 허용 범위) — 육안 확인 목록 |
| 판정 보내기 | 주 버튼(계단, 2dp 테두리) | 가로 꽉 찬 주 버튼 52, 3dp ink 두께, 진행 중 `AppLoader.small`. 비활성은 납작한 `sunken` — "아직 못 보냄"이 눈에 보인다 |
| "판정은 한 번만" / 사진 못 봄 | 버튼 아래 `bodyMedium` 14 | 같은 자리, `bodyMedium` 15 + 왼쪽 `info_outline_rounded` 20 `inkMuted`(놓치면 손해 보는 문장이라 메타 크기에 두지 않음) |
| 확인 대화상자 | 픽셀 제목 | `headlineSmall` 제목, 본문 `bodyMedium`, [취소] [판정 보내기](주) |
| 판정 단계 블록(대기·기한 경과·보냄·AI 재판정) | tone 2dp 테두리 | `AppPanel.tone` 테두리 없음 + 아이콘(5.4) |

#### 나머지 화면

| 화면 | 메모 |
|---|---|
| 시작·인증 대기(`auth_gate`) | `background` + `AppLoader.medium` 가운데 |
| 로그인 | 9.4 |
| 하단 탭 셸 | 5.1 탭바. 4탭 구성·순서·이름 그대로 |
| 내 대결 목록 | 모집 구역·진행 구역 묶음 `AppPanel.flat`, 각 대결 카드 `AppPanel.raised`(누르면 두께 꺼짐). 대결 제목 `bodyLarge`, 칩 줄은 `Wrap`(넘치면 줄바꿈, 지금과 같음) |
| 대결 찾기 | 고정 조작판 `sunken` 유지(세 겹 층: 조작판 sunken → 목록 background → 카드 surface가 그대로 성립). 조작판과 목록 사이 4dp ink 선 → 1dp `line`. 모집 카드 왼쪽 유형 색 띠는 모서리 16 카드 안 왼쪽 4dp 띠로(`battleTypeAccent` 규칙 그대로). 기간 칩 `neutralTagStyle` |
| 모집 상세 시트 | 바텀시트 5.1, 생성자 카드 `AppPanel.raised`, 참가 버튼 주 버튼 |
| 대결 만들기 / 모집 기준 수정 | 입력 필드·세그먼트 5.1, 기준 생성 중 `StatusMessage.loading` + 문장, 차단·한도 안내 `AppPanel.tone(danger)`, 기준 항목 추가·삭제 아이콘 5.4 |
| 대결 상세(그 밖) | 내 증거 제출·교체: 촬영 버튼 주 버튼 + `photo_camera_rounded`, 다시 찍기 보조 버튼 + `refresh_rounded`, 잠금 안내 tone(neutral) + `schedule_rounded`. 제출 시각 `numberSmall`. 결과 배너: 승 = `AppPanel.raised` + 왼쪽 48dp amber 둥근 칸 안 `emoji_events_rounded` ink, 패·무·무효 = `AppPanel.tone(neutral)`, 헤드라인 `titleMedium`, 점수 변화 `numberMedium`. 포기 = 위험 낮은 버튼(왼쪽 정렬 유지) |
| AI 데이터 제공 동의 | 동의 문구 묶음 `AppPanel.flat`, 문구 `bodyMedium` 15/1.6, 동의 버튼 주 버튼 |
| 프로필 | 점수 `numberLarge` 32/800 + 전적 `numberSmall`, 기록 목록 줄 오른쪽 `ResultLabel.small`, 동의·알림·계정 섹션 `AppPanel.flat`, 동의 철회·계정 삭제 = 위험 버튼, 로그아웃·라이선스 = 보조/낮은 버튼 + 아이콘 5.4 |
| 오픈소스 라이선스 | Flutter `showLicensePage` — 테마가 자동 적용. Pretendard(·필요 시 Material Icons) 고지 확인 |
| 대화상자·시트·토스트 전부 | 5.1 자동 적용 |

- 문구가 1.5배에서 잘리거나 줄바꿈이 어색해도 **문구는 고치지 않는다**. 발견하면 developer가 보고하고 메인 세션이 오너에게 묻는다(spec).

---

## 6. VS 인트로 새 스타일 (P0-5, 결정 D·E 그대로)

### 6.1 바뀌지 않는 것
뜨는 시점 2곳, 대결당 한 사람에게 한 번, 모집 중·종결 대결에서 안 뜸, 약 1.5초, 누르면·뒤로 가기면 즉시 닫힘, 애니메이션 줄이기 시 정지 화면,
실패해도 진입을 막지 않음(로그만, 토스트 없음), "봤음"은 표시 시작 시 기록, 3초 안전 타이머, 성공·오류 안내를 가리지 않음, 효과음·진동 없음,
시맨틱 라벨(`vsIntroSemantics`), 긴 이름·한 글자·"탈퇴한 사용자"에서 안 깨짐. `maybeShowVsIntro`/`showVsIntro`/`vs_intro_rules`/`vs_intro_seen_store` 그대로.

### 6.2 겉모습 (세로 기준, 위에서 아래로 — 구성 순서는 현행과 같다)
1. "상대" 라벨: `labelMedium` 14/700 `inkMuted`, 오른쪽 정렬(현 12dp 픽셀).
2. 상대 명판: 흰 면, 모서리 20, 1dp `line`, **4dp ink 두께**, 안쪽 16. [이름(오른쪽 정렬) | 이니셜 72(보조 강조 면)]. 이름 `titleMedium` 18/700, 최대 2줄 말줄임.
3. 가운데 띠: 높이 96, 가로 꽉 참, `ink` 면. "VS" = Pretendard 800, 64dp, 흰색(16.14), 아래로 4dp 오프셋 amber 단단한 글자 그림자(흐림 0).
4. 내 명판: 같은 모양, [이니셜 72(브랜드 면) | 이름(왼쪽 정렬)].
5. "나" 라벨: 왼쪽 정렬.
- 배경 `background`. 사진·캐릭터·마스코트 없음.
- 작은 화면(높이 < 520): 이니셜 48, 띠 64, "VS" 44(현 compact 규칙 승계).
- 글자 1.5배: 이름 2줄 + 말줄임, "VS"는 띠 높이 안에서 `FittedBox` 축소, 전체 `SingleChildScrollView`(스크롤 불가) 유지.

### 6.3 움직임 (총 1500ms, 연속 곡선)

| 구간 | ms | 내용 | 곡선 |
|---|---|---|---|
| 띠 열림 | 0–200 | 띠 높이 0 → 96 | easeOutCubic |
| 명판 들어옴 | 150–550 | 상대는 오른쪽 밖에서, 나는 왼쪽 밖에서 제자리로 | easeOutCubic |
| VS 등장 | 550–750 | 배율 1.6 → 1.0 + 투명도 0 → 1 | easeOutBack(넘침 작게) |
| 부딪힘 | 750–850 | 띠가 amber로 **한 번** 바뀌었다 돌아옴(100ms, 1회 — 초당 3회 미만) | 즉시 전환 |
| 읽는 시간 | 850–1300 | 정지 | — |
| 사라짐 | 1300–1500 | 전체 투명도 1 → 0(배경색으로 덮임) | easeOutCubic |

- **애니메이션 줄이기**: 1300ms 시점의 완성 화면을 처음부터 정지 상태로 보여 주고 1500ms에 닫는다(현행 `stillFrameMs` 규칙 그대로). 번쩍임 없음.
- 프레임 계산은 지금처럼 **시각(ms) → 연출 상태**의 순수 함수로 둔다(계단 `stepsSince` → 곡선 보간). `vs_intro_test`의 기대값을 새 곡선 값으로 고친다
  (구간 경계, 정지 화면 시각, 번쩍임 1회·100ms, 총 1500ms는 그대로 검사).

### 6.4 숫자 연출 (결정 6 = 정적 강조만)
움직임 없음. 3.2의 숫자 슬롯(굵게·크게·고정폭)과 결과 배너의 점수 변화 배치만으로 끝난다. 카운트업 등은 만들지 않는다(확정 3 유지).

---

## 7. 앱 밖 정체성 (P0-6)

### 7.1 앱 마크 — "칸을 뚫고 나가는 체크"(모티프 유지, 벡터로 다시 그림)
24×24 단위 격자(u) 위의 벡터 그림. 한 그리기 코드를 로그인·런처·스토어·알림·테마 아이콘이 함께 쓴다.

| 부품 | 모양 | 색(시안 A) |
|---|---|---|
| 칸 | 둥근 사각 (2,6)–(18,22), 모서리 3.5u, 선 굵기 2.5u | `surface` 흰색 |
| 체크 | 꺾은선 (5.5,13.5) → (10,18) → (21.5,4), 굵기 4u, 둥근 끝·둥근 꺾임 | `amber` |
| 뚫린 자리 | 체크가 칸 선을 지나는 곳에서 칸 선을 체크 둘레 1.5u만큼 지운다 — 체크가 칸을 "뚫고" 오른쪽 위로 나간다 | — |
| 두께 | 칸·체크를 아래로 1.5u 옮긴 같은 모양을 `ink`로 먼저 깐다(버튼 두께와 같은 언어) | `ink` |
| 배경 | 브랜드 `primary` | |

- 시안 B: 배경 주황, 칸 흰색, **체크 ink**(주황 위 앰버·파랑이 안 보여서). 시안 C: 배경 보라, 칸 흰색, 체크 amber.
- 단색(테마 아이콘·알림): 두께 없이 칸 + 체크만, 뚫린 자리 간격은 남긴다(한 덩어리로 뭉개지지 않게 — 현행 규칙 승계).
- 안전 영역: 적응형 아이콘(108dp 캔버스)에서 마크 상자 44dp를 가운데 둔다 → 가장 먼 점(체크 끝 + 굵기 절반)이 중심에서 약 26.5dp,
  안전 원 반지름 33dp 안. `app_mark_test`를 "그림의 모든 경로 경계가 중심에서 33dp 안"으로 바꾼다.
- 얼굴·캐릭터·특정 게임 도형 없음(체크와 네모뿐).

### 7.2 생성물 (한 명령 `flutter test tool/generate_launcher_icons.dart` 유지)

| 생성물 | 새 내용 |
|---|---|
| `mipmap-*/ic_launcher_foreground.png` | 투명 바탕 108dp 캔버스, 마크 상자 44dp, 색 마크 + 두께 |
| `mipmap-*/ic_launcher_monochrome.png` | 같은 크기, 단색 실루엣(두께 없음) |
| `mipmap-*/ic_launcher.png`(API 25 이하) | 48dp 캔버스, 브랜드 둥근 사각 배경(모서리 10dp — 계단 모서리 대체), 마크 상자 34dp |
| `drawable-*/ic_notification.png` | 24dp 캔버스, 흰 실루엣, 마크 상자 20dp, 두께 없음. 벡터라 **밀도마다 정확히 24dp**로 그린다(현 정수 셀 제약 해소) |
| `store/icon-512.png` | 512px 꽉 찬 브랜드 정사각(모서리는 Play가 깎음), 마크 상자 300px |
| `values/colors.xml` | `ic_launcher_background` = `primary`, `launch_background` = `background` |

- 안티에일리어싱을 켠다(도트가 아니므로 현 `isAntiAlias = false` 폐기).
- 옛 도트 PNG는 같은 경로를 덮어써 남지 않는다. 경로·파일 이름이 같으므로 CLAUDE.md의 명령 줄과 DEPLOY.md 16~17·114~115행 문장은 그대로 맞는다
  (DEPLOY.md에 "도트"·"16×16" 같은 그림 설명이 있으면 함께 고친다).

### 7.3 시작 창
- 배경색 = `background #EEF1F6`(생성된 `launch_background`), `values-night`도 같은 라이트 시작 창(현행 구조 유지).
- Android 12 이상 시스템 시작 화면은 적응형 아이콘(새 마크) + 이 배경색으로 보인다 — 첫 프레임 `background`와 이어진다.

### 7.4 홈 화면 투두 위젯 (기능·표시 정보 그대로)

| 부품 | 전 | 후 |
|---|---|---|
| 색 리소스(`tool/generate_widget_resources.dart` → `widget_resources.xml`) | paper·surface·sunken·line·ink·inkMuted·danger | `widget_background`(=background), `widget_surface`, `widget_sunken`, `widget_line`, `widget_outline`, `widget_ink`, `widget_ink_muted`, `widget_danger`. **Kotlin이 쓰는 `widget_danger`·`widget_ink_muted` 이름은 유지** |
| 전체 틀(`widget_frame.xml`) | paper + 2dp ink 선 + 2dp 바닥 두께(직각) | `widget_background` 면, 모서리 16dp, 테두리·두께 없음(홈 화면 위에서 앱 배경과 같은 인상) |
| 할 일 줄(`widget_row.xml`) | surface + 1dp line(직각) | `widget_surface` + 1dp `widget_line`, 모서리 10dp |
| 체크 칸(`widget_check.xml`) | sunken + 2dp ink(직각) | `widget_surface` + 2dp `widget_outline`, 모서리 4dp(앱 체크박스와 같은 인상) |
| 글자 | 제목 13sp, 보조 10~12sp | **결정 필요 3** |

- 위젯은 RemoteViews라 Pretendard를 쓸 수 없다(기기 기본 글꼴). "같은 앱으로 보인다"는 색·면·모서리로 낸다(spec이 허용한 범위).

---

## 8. 라이선스 (P0-7)
- 추가: Pretendard OFL 1.1(`LICENSE.txt` 원문, 이름 그대로). 필요 시 Material Icons Apache 2.0(5.4).
- 제거: 갈무리 고지·자산·글꼴.
- 서체 파일 이름·글꼴 패밀리 이름을 바꾸지 않는다.

---

## 데이터 흐름
- **기능 데이터 흐름은 바뀌지 않는다.** 사용자 액션 → provider/repository → RPC/RLS → 화면 반영 경로, 서버가 기록한 `status`/`winner_id`/`outcome`/
  `score_delta_applied`를 표시만 하는 규칙, 매핑 함수(`battleStatusTagStyle` 등)가 승패를 계산하지 않고 모양만 고르는 규칙 모두 그대로다.
- 시각 규칙의 흐름:
  - `AppPalette`(색의 유일한 출처) → `AppTheme.light`(ThemeData, Material 위젯 자동 적용) → 공용 위젯(`AppPanel`·`AppTag`·…) → 화면.
  - `AppPalette` + `AppMark` → `tool/generate_launcher_icons.dart` → 런처·스토어·알림 PNG, `colors.xml`(적응형 배경·시작 창).
  - `AppPalette` + `AppStrings` → `tool/generate_widget_resources.dart` → `widget_resources.xml` → 위젯 drawable·layout·Kotlin.
- VS 인트로 흐름(표시 판단 → 기록 → 표시, 실패 시 건너뜀)은 그대로.

## API 계약
- **RPC·테이블·RLS·Edge Function 변경 없음.** 스키마 마이그레이션 없음.
- CLAUDE.md 도메인 규칙 대조: 대결 상태 전이·판정 로직 위치(서버)·speed/quality 구분·`draw`/`voided`/`disputed` 구분 모두 손대지 않는다.
  화면은 서버 값의 모양만 바꾼다. 클라이언트 승패 계산 없음. 상태 칩·결과 라벨의 의미 구분(무 중립, 미결 경고, 무효 가장 약함)을 유지한다.
- 클라이언트 내부 계약(바뀌는 공용 API)은 5.2 표가 전부다. 사용자에게 보이는 문자열(`AppStrings`)은 하나도 추가·변경하지 않는다.
- 새 패키지: **없음**(Pretendard는 자산 파일, 아이콘은 Flutter 내장 Material Icons). 네이티브 변경은 위젯 drawable·리소스 XML과 생성된 PNG뿐이지만
  릴리스 빌드 검증은 한다(CLAUDE.md).

---

## 9. 단계별 작업 단위와 검증 (spec "단계" 순서. 파일 목록·커밋 계획은 plan.md 몫)

| 단계 | 작업 단위 | 검증 |
|---|---|---|
| 0. 시안 승인 지점 | 시안 A/B/C × (주·보조·위험 버튼 기본/눌림/비활성, 카드 raised/flat/inset, 상태 칩 8종, 할 일 줄 안 함/완료, 런처 아이콘 원형·사각·단색)을 **한 장씩 PNG로 렌더**(런처 생성기와 같은 방식의 일회성 도구, 앱에 화면을 추가하지 않는다). 오너가 시안 하나를 고르고 서체·버튼·카드·런처를 승인 | 오너 승인. 고른 시안의 토큰만 팔레트에 넣는다(나머지 시안은 코드에 남기지 않는다 — 테마 두 벌 금지) |
| 1. 기반 | `AppPalette`, `AppText`(Pretendard 번들·갈무리 제거·고지 교체), `DepthBorder`, `AppTheme` 재작성, `maxTextScale` 1.5 | **대비 테스트**: 2장 표의 글자 쌍(4.5)·비활성 쌍(3)·비텍스트 쌍(3)을 `app_palette_test`로 고정(현 `retro_palette_test` 대체, 설계값 ±0.05 + 기준 이상). **글자 테스트**: 모든 TextTheme 슬롯·숫자 슬롯이 Pretendard, 12 이상, 문장 슬롯 14 이상, 본문 행간 1.5 이상, 자간 ≥ 0, 굵기 ≥ 400, 런타임 머지 뒤에도 유지(현 `retro_text_test` 대체). `DepthBorder` 테스트: 눌림 전후 바깥 크기 동일, 두께 위치(현 `pixel_border_test` 대체). `maxTextScale == 1.5` 테스트. 11,172자 cmap 확인 기록 |
| 2. 공용 위젯·아이콘 | 5.2 매핑 전부, `AppIcons`, 탭바, 5.3 칩·라벨 매핑 | `battle_chips_test` 갱신(무≠미결, 무에 danger 계열 없음, 무효 가장 약함, 미결에 아이콘), `initial_badge_test` 갱신(면 → 글자색 매핑), `pixel_icons_test` 삭제(비트맵 규칙 소멸) 후 `AppIcons` 상수가 서로 다른지 정도만, 코드 전체에 `PixelIcon`·`PixelBorder`·`RetroText`·`Galmuri` 참조 0 |
| 3. 화면별 정리 | 5.5 순서: **할 일 목록 → 대결 상세(판정 창)** → 내 대결 → 대결 찾기·모집 시트 → 만들기·기준 수정 → 동의 → 프로필 → 로그인·시작 → 라이선스 (화면 하나 = 커밋 하나) | 화면마다 기존 조작 끝까지 수행(spec 기능 목록), 문구 diff 0(`strings.dart` 변경 없음) |
| 4. 순간 연출 | VS 인트로(6장), 숫자 슬롯 적용 확인, 로그인(9.4) | `vs_intro_test` 갱신(구간·정지 화면·번쩍임 1회·닫힘 규칙), `battle_join_vs_intro_test` 통과 |
| 5. 앱 밖 정체성 | `AppMark` 벡터, 런처 생성기, 위젯 리소스 생성기·drawable, 시작 창 색, DEPLOY.md 문장 점검 | `app_mark_test`(안전 원 33dp), 두 생성 명령 재실행 후 산출물 커밋, 에뮬레이터에서 원형·사각·테마 아이콘·알림·위젯·다크 모드 시작 창 확인 |
| 6. 가독성 검증 | 아래 육안 목록 + 전/후 스크린샷 | `flutter analyze` 0, `flutter test` 전부, `flutter build appbundle --release --dart-define-from-file=env.json` 성공을 **종료 코드로** 확인, AAB 크기 전/후 기록, 오너 "읽힌다" 확인 |

릴리스 규칙(spec): 1~6단계 P0는 한 릴리스로 함께 공개한다. 중간 상태는 내부 테스트 트랙까지만.

### 9.1 전/후 비교 (오너 확인)
- 같은 계정·같은 데이터로 **할 일 목록**(안 한 일 3 + 완료 2 + 긴 제목 1)과 **판정 창**(품질전, 최소 기준 3 + 우열 기준 2, 아무것도 고르지 않은 상태와
  둘 다 고른 상태)을 배율 1.0·1.5에서 개편 전(현 main)과 후로 찍어 나란히 둔다. `tool/screenshot_seed.sql`이 쓸 수 있으면 그것으로 데이터를 맞춘다.

### 9.2 육안 확인 목록 (자동 테스트로 안 잡히는 곳, 배율 1.0 / 1.5, 360dp 폭 에뮬레이터)
1. 하단 탭 라벨 4개가 한 줄(특히 "대결 찾기").
2. 판정 창 세그먼트 두 개(승인/불복, 우열) — 잘림 없음, 선택 체크 아이콘이 라벨을 밀어내지 않음.
3. 대결 만들기 유형·기간 세그먼트·빠른 선택.
4. 대결 상세 머리의 배지 + 칩 한 줄(넘치면 줄바꿈).
5. 모집 카드·내 대결 카드의 칩 줄과 기간 칩.
6. VS 인트로: 긴 이름(20자), 한 글자 이름, "탈퇴한 사용자", 가로 모드(compact).
7. 대화상자 버튼 줄(취소/저장, 취소/판정 보내기, 계정 삭제 확인).
8. 토스트 두 줄 문장.
9. 프로필 점수(32 × 1.5) + 전적 한 줄.
10. 결과 배너 4종(승·패·무·무효)과 점수 하한 안내.
11. 버튼 눌림이 보이는지, 비활성 버튼이 "못 누름"으로 읽히는지.
12. 홈 위젯 최소 크기에서 줄 수·말줄임.
13. 기기 다크 모드에서 앱·시작 창·위젯이 라이트 그대로.
14. 가장 작은 아이콘(16dp 유형 아이콘, 20dp 안내 아이콘)과 알림 아이콘 형태.

### 9.3 retro-theme에서 사라지는 것 확인 목록
픽셀 글꼴(앱·위젯), 계단 모서리, 2dp 전면 잉크 테두리, 창 제목 띠, 12×12 아이콘 34종, 16×16 도트 마크(로그인·런처·스토어·알림), 50ms 계단식 움직임,
깜빡이는 ▶ 커서, 이중선 포커스, 크림 팔레트. 하나라도 남으면 9단계 6을 통과하지 않는다.

### 9.4 로그인 (P0-4 + P1-2)
- 구성(마크 + 앱 이름 + 구글 로그인 버튼)·문구·기능 그대로. 배경 `background`.
- 마크: 112dp 브랜드 둥근 사각(모서리 28) + 4dp ink 두께, 안에 7.1 마크(마크 상자 72dp). 런처 아이콘과 같은 그림·색.
- 앱 이름 `displayMedium` 34/800 ink. 현재의 amber 4dp 글자 그림자는 뺀다(큰 제목도 번짐 없이 읽히는 쪽 — 게임감은 마크의 두께와 버튼이 낸다).
- 로그인 버튼: 주 버튼 최소 240×56.
- ▶ 깜빡이는 커서는 **없앤다**(레트로 게임기 "PRESS START" 상징이고 깜빡임 움직임이다). 정보가 아니라 장식이라 spec "정보를 빼지 않는다"에 걸리지 않는다고 판단했다 — 결정 필요 4로 오너 확인.
- P1-2(마크 등장 움직임 등)는 시간이 남을 때만, 애니메이션 줄이기면 정지.

---

## 결정 필요

1. **브랜드 시안 선택 (A / B / C)** — 2.3 비교표.
   - A 밝은 파랑 `#3355FF` + 앰버: 예외 규칙 없음, 위험색과 구분 쉬움, 기존 파랑 자산과 연속.
   - B 주황 `#F26B1D` + 파랑: 가장 뜨겁지만 흰 글자 불가(버튼 라벨 남색), 주 버튼에 ink 테두리 추가 필요(경계 2.69), 위험·경고색과 가깝다.
   - C 보라 `#6C47FF` + 앰버: 가장 차별화, 판정 중 색을 하늘색으로 옮겨야 하고 기존 자산과 끊긴다.
   - **designer 추천: A.** 0단계에서 세 시안을 같은 화면 조각으로 렌더해 보여 드린 뒤 확정한다.

2. **"대결" 아이콘(지금의 교차한 칼)을 무엇으로?** Material Icons에 칼(swords)이 없다(Material Symbols에는 있으나 별도 패키지 필요).
   - (a) 권투 글러브 `sports_mma` — "겨룬다"가 바로 읽히고 얼굴이 없다.
   - (b) 마주 보는 화살표 `compare_arrows` — 순하지만 "대결"로 덜 읽힌다(탭 라벨이 함께 있어 뜻은 전달됨).
   - (c) 교차한 칼 하나만 같은 둥근 선 굵기로 직접 벡터로 그린다 — 현 의미를 그대로 잇지만 한 벌 아이콘 세트에 손그림이 하나 섞인다.
   - **추천: (a).** 새 패키지·손그림 없이 의미가 가장 가깝다.

3. **홈 위젯 글자 크기를 올릴까?** 현재 할 일 제목 13sp, 보조 줄 10~12sp로 앱 안 기준(12 미만 금지, 목록 주 텍스트 16)보다 작다. spec은 위젯에 "색과 면·경계 인상"만 요구했다.
   - (a) 그대로 둔다 — 위젯 작업은 색·모양만, 줄 수 변화 없음.
   - (b) 보조 줄 12sp, 제목 14sp로 올린다 — 앱과 같은 "12 미만 없음" 원칙. 최소 크기 위젯에서 보이는 줄 수가 줄 수 있다(표시 정보 자체는 같고 "그 외 N개"가 대신 받는다).
   - **추천: (b).** 이번 개편의 1순위가 가독성이고 위젯은 앱 다음으로 자주 보는 화면이다. 단 홈 위젯 기능 범위(`home-widget` spec)에 "줄 수"에 관한 확정이 있으면 그쪽을 따른다.

4. **로그인 화면의 ▶ 깜빡이는 커서를 없애도 될까?** (9.4)
   - (a) 없앤다 — 레트로 상징·깜빡임 움직임 제거, 마크·이름·버튼만으로 타이틀 구성.
   - (b) 정지한 ▶(`play_arrow_rounded`)로 남긴다 — "게임 타이틀" 흔적 유지, 움직임 없음.
   - **추천: (a).**

5. **Pretendard 서체 확인 결과에 따른 예외** — 다음 중 하나라도 실측에서 어긋나면 developer가 멈추고 보고한다: 세 굵기 중 하나가 11,172자를 다 갖지 않음 / 고정폭 숫자(`tnum`) 미지원 / AAB 증가가 오너가 받아들이기 어려운 수준.
   기본 대응 추천: 11,172자 미지원 굵기는 빼고 가까운 굵기로 대신, `tnum` 미지원이면 숫자 칸 폭 고정만 포기(P1-1 일부), 용량은 그대로 진행(굵기 3개가 이미 최소).
