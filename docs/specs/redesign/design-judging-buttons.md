# redesign 후속 설계 — 판정 묶음 훑어보기 · 보조 버튼 위계

## 참고
- 오너 피드백(2026-11-08, 메인 세션 전달): ① "판정 글이 구분이 잘 안 되어 있어서 글을 다 읽어야 하는 게 불편해. 안 봐도 느낌적으로
  사용자들이 알아야 해." ② "기준 수정, 취소 버튼 UI가 올드해."
- 상위 문서: `docs/specs/redesign/spec.md`(가독성 1순위·게임감·IP), `design.md`(2장 색, 3.2 글자 역할표, 4.1 토큰, **4.2 버튼 위계**,
  5.5 기준 화면 2 "대결 상세 판정 창"), `plan.md`(후속 결정 F1–F8, 후속 2 W1–W4 진행 기록).
- 도메인: `CLAUDE.md` "도메인 규칙" 판정 조항(mutual-judge 기준).
- 현재 코드(2026-11-08 HEAD 기준으로 읽음): `lib/features/battle/presentation/judgment_section.dart`(`_ChoicePair` 세그먼트),
  `criteria_views.dart`(`CriteriaListBlock`), `battle_detail_screen.dart`, `evidence_section.dart`, `my_battles_screen.dart`(`_MyRecruitBody`),
  `lib/core/theme/{app_palette,app_theme,app_text,app_icons,depth_border}.dart`, `lib/core/widgets/{app_panel,app_button_styles,initial_badge,keep_words_text}.dart`,
  `lib/core/strings.dart`.

이 문서는 redesign design.md를 **대체하지 않는다**. 오너가 안을 고르면 design.md 4.2 표의 "보조"·"위험 윤곽" 줄과 5.5 기준 화면 2의
"판정 묶음"·"우열 세그먼트"·"'판정은 한 번만'" 줄이 이 문서의 선택된 안으로 바뀐다(design.md에 한 줄로 가리킨다 — developer 몫).

### 바꾸지 않는 것 (도메인 가드)
- 선택지는 **정해진 버튼뿐**: 최소 기준 `통과했어요`/`통과하지 못했어요`, 우열 `내가 더 잘했어요`/`상대가 더 잘했어요`. 점수·별점·
  슬라이더·부분 승인·"잘 모르겠어요"·자유 텍스트 입력을 만들지 않는다. 기본 선택값을 두지 않는다(아무것도 안 고른 상태로 시작).
- 품질전은 두 질문을 **한 번에** 보낸다(한 RPC, 한 확인 대화상자). 질문 순서를 강제하지 않는다(어느 쪽부터 골라도 된다).
- 판정은 한 번. 확인 대화상자(`battleJudgmentConfirmTitle`/`battleJudgmentConfirm`)는 그대로 둔다.
- 화면은 단계([JudgmentStage])·결과를 **표시만** 한다. 단계 판단은 `judgmentStageOf`, 결론은 서버. 새 상태 없음, RPC·스키마 변경 없음.
- 미판정 = 승인 간주 안내는 지금처럼 기한 경과 단계(`battleJudgmentWindowClosed`)에서만 말한다.
- 아이콘은 Material Icons Rounded만. 얼굴·캐릭터·로봇 얼굴(`smart_toy` 등)·불꽃·하트·보석 금지 — AI는 돋보기(`manage_search_rounded`)로 나타낸다.

---

## 화면

### 0. 진단 — 지금 왜 "다 읽어야" 하는가
현재 `_form`의 판정 묶음(흰 `AppPanel.flat` 한 장) 안 세로 순서와 무게:

| # | 요소 | 슬롯 | 문제 |
|---|---|---|---|
| 1 | 제목 "판정" | titleSmall 16/700 | 질문과 같은 슬롯 — 제목인지 질문인지 구분 안 됨 |
| 2 | 안내 "상대 증거를 확정된 기준으로 판정해 주세요." | bodyMedium 15 | 행동을 담지 않은 문장이 맨 앞에서 시선을 먹는다 |
| 3 | 질문1 | titleSmall 16/700 | 1과 같은 무게 |
| 4 | 세그먼트(52, 흰 면 + 회색 테두리) | labelLarge 16/700 | 선택지가 주인공이 아니다 — 아이콘 없음, 통과/미달이 글자로만 갈린다 |
| 5 | 불복 힌트 | bodyMedium 15 | 2와 같은 무게 |
| 6 | 질문2 + 세그먼트 | 3·4와 같음 | 질문1과 2 사이에 경계가 없다 — 질문이 몇 개인지 세려면 읽어야 한다 |
| 7 | 판정 보내기 / "판정은 한 번만…" | 주 버튼 / bodyMedium | 경고가 버튼 **아래**라 누른 뒤에 읽힌다 |

그리고 기준(최소·우열)은 판정 묶음 **위에 따로 떨어진 두 블록**이라 "질문1 ↔ 최소 기준", "질문2 ↔ 우열 기준"의 짝이 위치로 드러나지 않는다.

해결 원칙(두 안 공통):
1. **질문 하나 = 경계가 있는 구획 하나.** 구획 머리에 짧은 꼬리표(`최소 기준`/`우열 기준` — 이미 있는 문자열)를 붙여, 질문 문장을 읽지 않아도 무엇을 묻는지 안다.
2. **기준은 그 질문 구획 안에.** 질문1 구획 안에 최소 기준, 질문2 구획 안에 우열 기준. 따로 떨어진 `CriteriaListBlock` 두 개는 판정 차례 화면에서 빠진다.
3. **선택지가 주인공.** 아이콘(통과 ✓ 초록 / 미달 ✕ 빨강) 또는 이니셜 배지(나 파랑 / 상대 앰버)가 글자보다 먼저 눈에 들어온다.
4. **선택은 색만이 아니라 모양으로.** 고른 칸 = 연파랑 면 + 2dp 파랑 테두리 + 오른쪽 위 체크 배지. 질문을 다 답한 구획은 머리 번호가 초록 체크로 바뀐다.
5. **보조 설명은 한 줄, 보조색.** 불복 힌트는 선택지 바로 아래 한 줄(아이콘 + inkMuted), `통과하지 못했어요`를 고르면 그 자리에서 안내 블록으로 강조.
6. **경고는 누르기 전에.** "판정은 한 번만"은 보내기 버튼 **바로 위**.
7. **누를 것은 하나만 두껍다.** 화면에서 3dp 두께가 있는 것은 `판정 보내기` 하나(버튼 안 A와 함께 고르면 더 분명해진다 — 2장).

### 공통 토큰 (두 안이 같이 쓴다)

| 이름(설계용) | 값 | 쓰임 |
|---|---|---|
| 단계 배지 | 지름 28 원. 미답: `primary` `#3355FF` 면 + 흰 숫자(`AppText.numberSmall` 16/700) / 답함: `success` `#1D7A4C` 면 + 흰 `check_rounded` 20 | 질문 구획 머리 |
| 꼬리표 | `labelMedium` 14/700 `primaryDeep` `#2238C8` | `최소 기준` / `우열 기준`(기존 `battleCriteriaMinTitle`/`battleCriteriaSuperiorityTitle`) |
| 질문 | `titleSmall` 16/700 `ink` `#1B2033` | 기존 질문 문자열 |
| 기준 상자 | `sunken` `#E2E7EF` 면, 모서리 12, 안쪽 12, 테두리 없음 | 구획 안 기준 목록. 첫 줄 힌트 `bodyMedium` 15 `inkMuted` `#4A5168`, 항목 `bodyMedium` 15 `ink`, 항목 앞 6dp 원점 `inkMuted`(번호 대신 — 단계 번호 1·2와 겹치지 않게), 항목 사이 8 |
| 불복 힌트 줄 | 왼쪽 `manage_search_rounded` 20 `inkMuted` + 8 + `bodyMedium` 15 `inkMuted` | 기존 `battleJudgmentRejectHint` |
| 불복 힌트 강조 | `AppPanel.tone(info)` 축소형: `primaryPale` `#E3E9FF` 면, 모서리 12, 안쪽 12, 아이콘 `manage_search_rounded` 20 `primary`, 글자 `bodyMedium` `ink` | `통과하지 못했어요`를 골랐을 때 같은 자리 |
| 한 번만 경고 줄 | 왼쪽 `lock_rounded` 20 `inkMuted` + 8 + `bodyMedium` 15 `ink` | 기존 `battleJudgmentOnce`. 보내기 버튼 바로 위 8 |
| 사진 실패 | `AppPanel.tone(danger)`(`dangerPale` `#FDE3E4` + `warning_amber_rounded` 24 `danger` + `bodyMedium` ink) | 기존 `battleJudgmentPhotoUnavailable` — 경고 줄 자리를 대신 |
| 보내기 | 주 버튼 가로 꽉 참, 높이 52(면 49 + 3dp `ink` 두께), `primary` 면 + 흰 `labelLarge`. 비활성 = `sunken` 면 + `inkDisabled` `#767D93` 라벨, 납작 | 기존 `battleJudgmentSend` |

새 아이콘(`AppIcons`에 추가, 쓰는 곳이 생기므로 미래 대비가 아니다): `fail = Icons.cancel_rounded`(미달 ✕), `aiReview = Icons.manage_search_rounded`(AI가 다시 봄),
`lock = Icons.lock_rounded`(한 번만), `edit = Icons.edit_rounded`(기준 수정 — 2장). 통과 ✓는 기존 `AppIcons.pass`(`check_circle_rounded`), 선택 체크는 기존
`AppIcons.check`. developer가 `Icons`에 실제로 있는지 확인한다(대안: `highlight_off_rounded` / `search_rounded` / `lock_outline_rounded` / `mode_edit_rounded`).

---

### 1. 판정 묶음 — 안 1A "단계 카드 + 큰 선택 타일" (**designer 추천**)

> 인상: 두 질문이 두 장의 번호 붙은 카드로 나란히 쌓이고, 카드마다 "기준 → 큰 타일 두 개". 훑으면 "카드 2장, 각각 둘 중 하나, 초록 체크 = 끝"이 보인다.

#### 1A.1 구성 (위 → 아래, 판정 차례 `myTurn`)

```
[화면 가장자리 20 · ListView]
대결 머리 / 상대 카드 (그대로)
24
┌ AppPanel.flat  "상대 제출" ───────────────┐   ← 지금과 같다
│ EvidencePhotoFrame.large                  │
└───────────────────────────────────────────┘
24
판정                                          ← titleSmall 16/700 ink, 배경 위 맨글자(묶음 제목 역할). 아래 12
┌ 단계 카드 1 (AppPanel.flat, 안쪽 16) ──────┐
│ (1)  최소 기준                             │  ← 배지 28 + 12 + [꼬리표 / 4 / 질문]
│      상대 사진이 최소 기준을 통과했나요?    │
│ 12                                         │
│ ┌ 기준 상자(sunken) ────────────────────┐ │
│ │ 이걸 모두 만족하면 통과예요            │ │
│ │ • 상판이 보인다                        │ │
│ │ • …                                    │ │
│ └────────────────────────────────────────┘ │
│ 16                                         │
│ ┌──────────────┐ 8 ┌──────────────┐        │  ← 선택 타일 두 칸(같은 높이)
│ │      ✓       │   │      ✕       │        │
│ │  통과했어요  │   │ 통과하지     │        │
│ │              │   │ 못했어요     │        │
│ └──────────────┘   └──────────────┘        │
│ 12                                         │
│ 🔍 통과하지 못했다고 하면 AI가 다시 봐요.   │  ← 불복 힌트 줄
└───────────────────────────────────────────┘
12
┌ 단계 카드 2 (품질전만) ───────────────────┐
│ (2)  우열 기준                             │
│      우열 기준으로 볼 때 누가 더 잘했나요?  │
│ 12                                         │
│ ┌ 기준 상자 ─ 둘 다 통과하면 이걸로 … ──┐ │
│ └────────────────────────────────────────┘ │
│ 16                                         │
│ ┌──────────────┐ 8 ┌──────────────┐        │
│ │   [나 배지]  │   │ [상대 배지]  │        │
│ │ 내가 더      │   │ 상대가 더    │        │
│ │ 잘했어요     │   │ 잘했어요     │        │
│ └──────────────┘   └──────────────┘        │
└───────────────────────────────────────────┘
24
🔒 판정은 한 번만 할 수 있어요. 보낸 뒤에는 바꿀 수 없어요.   ← 한 번만 경고 줄
8
[████████████ 판정 보내기 ████████████]    ← 주 버튼 52
```

- **안내문 `battleJudgmentIntro`는 판정 차례 화면에서 뺀다.** 꼬리표 + 질문 + 기준 상자가 같은 말을 구조로 한다(결정 필요 6 — 문자열 처리).
- 따로 떨어져 있던 `CriteriaListBlock` 두 개(최소·우열)는 판정 차례 화면에서 빠지고 단계 카드 안 기준 상자가 된다. 우열 기준이 비어 있으면(옛 데이터) 2단계 카드의 기준 상자만 생략.
- **속도전**은 단계 카드 1장. 질문이 하나뿐이라 **번호 배지를 그리지 않는다**(1/1은 소음). 머리는 꼬리표 + 질문만, 나머지 같음.
- 구획 사이 12, 판정 제목 ↔ 첫 카드 12, 마지막 카드 ↔ 경고 줄 24(묶음 사이 규칙 design 4.1).
- 단계 카드는 `AppPanel.flat`(흰 면 + 1dp `line` `#D3D9E3`, 모서리 16) 그대로. 카드 자체는 누를 수 없다.
- 낭독: 단계 머리는 `Semantics(header: true)`, 배지는 `ExcludeSemantics`(꼬리표·질문이 대신 읽힌다). 답한 구획은 머리 라벨 끝에 시맨틱 값으로 고른 답을 붙인다(문자열 추가 없이 선택지 원문 사용).

#### 1A.2 선택 타일 (새 위젯 — 두 질문 공통)

| 속성 | 값 |
|---|---|
| 크기 | 두 칸 가로 1:1, 사이 8. 최소 높이 104, 두 칸 높이를 같게(긴 라벨 쪽에 맞춤). 안쪽 위 16 / 좌우 12 / 아래 14 |
| 모서리 | 16 |
| 내용(세로 가운데) | 위: 아이콘 40 또는 이니셜 배지 40 → 8 → 라벨 `labelLarge` 16/700 가운데 정렬, `KeepWordsText`(어절 줄바꿈, 기본 balanced) |
| 아이콘 | 통과 `check_circle_rounded` 40 `success` `#1D7A4C` / 미달 `cancel_rounded` 40 `danger` `#CC2F3F` |
| 이니셜 배지 | 나 = `InitialBadge(name: myName, fill: primary)`(흰 글자) / 상대 = `InitialBadge(name: opponentName, fill: secondary)`(앰버 `#FFB020` + ink 글자). 카드 크기 40, 모서리 12 |
| 미선택 | `surface` `#FFFFFF` 면 + 1.5dp `outline` `#6B7289` 테두리, 라벨 `ink` |
| 누르는 동안 | 면 `sunken` `#E2E7EF`(즉시, 뗄 때 120ms — 애니메이션 줄이기면 즉시). 두께 없음 |
| 선택 | `primaryPale` `#E3E9FF` 면 + 2dp `primary` `#3355FF` 테두리 + 오른쪽 위(위·오른쪽 6 안쪽) **체크 배지**: 지름 24 `primary` 원 + 흰 `check_rounded` 16. 라벨 `ink`. 아이콘·이니셜 색은 그대로 |
| 고르지 않은 쪽(다른 칸이 선택됨) | 미선택 모양 그대로 — **흐리게 하지 않는다**(흐리면 비활성으로 읽혀 바꿀 수 없다고 오해한다) |
| 보내는 중 | 선택 칸: 선택 모양 유지(보내는 내용이므로). 미선택 칸: `sunken` 면 + 1.5dp `line` 테두리 + 아이콘·라벨 `inkDisabled` `#767D93`, 이니셜 배지는 그대로 두되 탭 불가 |
| 터치 | 칸 전체(최소 104 × 140 이상). 물결 없음 |
| 낭독 | `Semantics(button: true, inMutuallyExclusiveGroup: true, selected: …, label: 라벨 원문)` |
| 좁을 때 | 한 칸 안쪽 폭(칸 폭 − 좌우 12×2 − 테두리 2×2)에 가장 긴 **어절**이 안 들어가면 두 칸을 위아래로(사이 8) 쌓는다. 지금 `_ChoicePair`의 `widestWordWidth` 판단을 그대로 옮긴다 |

360dp·1.5배 계산: 화면 360 − 가장자리 40 − 카드 안쪽 32 = 288 → 칸 140. 칸 안쪽 폭 140 − 28 = 112. 가장 긴 어절 "통과하지"·"못했어요"·"잘했어요"·"상대가"는
4글자 × 16 × 1.5 ≈ 96(Pretendard 실폭은 더 좁다) → 112 안에 들어가 **가로 두 칸 유지**, 라벨은 두 줄. 테스트 글꼴(정사각형)에서 넘치면 쌓기로 떨어진다(무너지지 않음).
체크 배지(오른쪽 위 24)는 가운데 아이콘(140 칸에서 50–90 구간)과 겹치지 않는다.

#### 1A.3 상태별 모습

| 상태 | 단계 배지 | 타일 | 불복 힌트 | 경고 줄 / 보내기 |
|---|---|---|---|---|
| 미선택 | 1·2 모두 파랑 숫자 | 모두 미선택 | 회색 한 줄 | 🔒 경고 / 보내기 비활성(납작 sunken) |
| 일부 선택(품질전, 1만 답) | 1 = 초록 체크, 2 = 파랑 숫자 | 1의 고른 칸 선택 모양 | (통과를 골랐으면) 회색 한 줄 | 보내기 비활성 |
| 불복 선택 | 1 = 초록 체크 | "통과하지 못했어요" 선택 | **같은 자리에서 연파랑 안내 블록으로 바뀜**(문구 같음) | — |
| 완료(모두 답함) | 모두 초록 체크 | 각 카드 한 칸씩 선택 | 고른 값에 따름 | 보내기 활성: `#3355FF` 면 + 3dp `#1B2033` 두께 — 화면에서 유일한 두께 |
| 사진 불러오기 실패 | 그대로 | 그대로(고를 수는 있다 — 현행 동작) | 그대로 | 경고 줄 자리에 `AppPanel.tone(danger)` + `battleJudgmentPhotoUnavailable`, 보내기 비활성 |
| 보내는 중 | 그대로 | 1A.2 "보내는 중" | 그대로 | 보내기 비활성 + 라벨 자리 `AppLoader.small` |
| 보냄 이후(대기·AI·기한·없음) | — | — | — | 1C "판정 진행 카드"로 바뀐다 |

(선택) 진행 한 줄 — 품질전만, 경고 줄 위 8: `2개 중 1개 골랐어요` / `다 골랐어요` (`labelMedium` 14/700, 미완 `inkMuted`, 완료 `success`). **새 문자열이라 결정 필요 3.**
채택하지 않아도 단계 배지 체크가 같은 정보를 준다.

---

### 1B. 판정 묶음 — 안 1B "한 질문씩 펼침 + 세로 선택 줄"

> 인상: 한 번에 질문 하나만 펼쳐져 있다. 답하면 그 질문은 "✓ 최소 기준 · 통과했어요 [바꾸기]" 한 줄로 접히고 다음 질문이 열린다. 다 답하면 두 줄 요약 + 보내기 — 보내기 전에 내 답을 한눈에 다시 본다.

#### 1B.1 구성

```
상대 제출(사진) — 그대로
24
┌ AppPanel.flat "판정" (안쪽 16) ───────────────────┐
│ [펼친 단계]                                        │
│ (1)  최소 기준                                     │
│      상대 사진이 최소 기준을 통과했나요?            │
│ 12  기준 상자(1A와 같음)                           │
│ 16                                                  │
│ ┌ ✓  통과했어요                          ○ ┐       │  ← 세로 선택 줄, 가로 꽉 참
│ └──────────────────────────────────────────┘       │
│ 8                                                   │
│ ┌ ✕  통과하지 못했어요                   ○ ┐       │
│ │    AI가 다시 봐요                          │       │  ← 줄 안 보조 문장(bodyMedium inkMuted)
│ └──────────────────────────────────────────┘       │
│ ─ 1dp line, 위아래 16 ─                            │
│ [잠긴 단계]  (2) 우열 기준                         │  ← 숫자 배지 윤곽형, 꼬리표·질문 inkMuted, 내용 없음
│              우열 기준으로 볼 때 누가 더 잘했나요?  │
└────────────────────────────────────────────────────┘
```
- 1을 답하면: 1은 **요약 줄**로 접힌다 — `[초록 체크 배지 28] 최소 기준 / [고른 답 칩: ✓ 통과했어요] ……… [바꾸기](텍스트 버튼 작은 크기)`.
  2가 펼쳐지고 화면이 2의 머리로 스크롤된다(`ensureVisible`, 애니메이션 줄이기면 즉시). 낭독은 "우열 기준, 펼쳐짐"을 알린다.
- 다 답하면: 두 요약 줄 + 묶음 안 아래에 경고 줄 + 보내기(1A와 같은 모양).
- 요약 줄의 `바꾸기`를 누르면 그 단계가 다시 펼쳐지고 다른 단계는 접힌다(값은 유지).
- 속도전: 단계 하나. 답하면 요약 줄로 접히고 바로 아래 경고 + 보내기 — "검토하고 보낸다"는 순간이 생긴다.
- 잠긴 단계도 **누르면 펼쳐진다**(순서를 강제하지 않는다는 가드 — 앞 질문을 건너뛰고 답해도 된다). "잠김"은 모양일 뿐이다.

#### 1B.2 세로 선택 줄

| 속성 | 값 |
|---|---|
| 크기 | 가로 꽉 참, 최소 높이 64, 안쪽 좌 12 / 우 16 / 위아래 12, 모서리 12, 줄 사이 8 |
| 내용(가로) | 아이콘 24(`check_circle_rounded` success / `cancel_rounded` danger) 또는 이니셜 배지 40 → 12 → 라벨 `labelLarge` 16/700(남은 폭, 어절 줄바꿈) [+ 아래 4, 보조 문장 `bodyMedium` 15 `inkMuted`] → 12 → 라디오 표시 24 |
| 라디오 표시 | 미선택: 지름 24 원, 2dp `outline` 테두리, 속 빔 / 선택: `primary` 원 + 흰 `check_rounded` 16 |
| 미선택 / 누름 / 선택 / 보내는 중 | 1A.2 타일과 같은 색 규칙(흰 면 1.5dp outline → 누름 sunken → 선택 primaryPale + 2dp primary → 미선택 비활성 sunken + line + inkDisabled) |
| 보조 문장 | 미달 줄에만 `AI가 다시 봐요`(**새 짧은 문자열 — 결정 필요 3**). 채택하지 않으면 줄 안 보조 문장 없이 줄 묶음 아래에 1A의 불복 힌트 줄 |
| 360dp·1.5배 | 줄이 가로로 길어 어절 쌓기 판단이 필요 없다. 라벨 칸 = 288 − 12 − 24 − 12 − 12 − 24 − 16 = 188 ≥ 가장 긴 어절 96 |

#### 1B.3 상태별 모습

| 상태 | 단계 1 | 단계 2(품질전) | 아래 |
|---|---|---|---|
| 미선택 | 펼침 | 잠김(윤곽 배지: 흰 면 + 1.5dp `outline` 원 + `inkMuted` 숫자, 꼬리표·질문 `inkMuted`) | 없음 |
| 일부 선택 | 요약 줄(초록 체크 + 답 칩 + 바꾸기) | 펼침 | 없음 |
| 완료 | 요약 줄 | 요약 줄 | 경고 줄 + 보내기 활성 |
| 사진 실패 | 1A와 같음(경고 줄 자리에 danger 블록, 보내기 비활성) | | |
| 보내는 중 | 요약 줄의 `바꾸기` 비활성(`inkDisabled`) | 같음 | 보내기 로더 |
| 보냄 이후 | 1C | | |

답 칩: `primaryPale` 면, 모서리 8, 높이 최소 28, 좌우 10, 왼쪽 16dp 아이콘(✓ success / ✕ danger / 이니셜 대신 `person_rounded` 16 — 배지 40은 칩에 크다) + `labelMedium` 14/700 `ink`(13.35).

---

### 1C. 보낸 뒤·대기 상태 — "판정 진행 카드" (두 안 공통)

지금은 단계마다 `AppPanel.tone` 한 장(아이콘 24 + 제목 + 문장)이다. 같은 시각 언어(28 원형 배지 + 짧은 상태 낱말)로 맞춘다.

**기본형(새 문자열 0) — 결정 필요 4에서 진행 줄을 거절해도 이것은 한다:** `AppPanel.tone`을 유지하되 왼쪽 아이콘 24를 **28 원형 배지**로 바꾼다.

| 단계 | 패널 성격 | 배지 | 제목 / 본문(기존 문자열) |
|---|---|---|---|
| `waitingOpponent` | success(`successPale` `#DDF3E6`) | `success` 원 + 흰 `check_rounded` 20 | `battleJudgmentSentTitle` / `battleJudgmentWaitingOpponent` |
| `waitingAi` | info(`primaryPale`) | `surface` 원 + `manage_search_rounded` 20 `primary`(흰 원 위 5.41) | `battleJudgmentAiTitle` / `battleJudgmentAi` |
| `nothingToJudge` | info | `surface` 원 + `hourglass_bottom_rounded` 20 `primary` | `battleJudgmentNothingTitle` / `battleJudgmentNothing` |
| `windowClosed` | neutral(`sunken`) | `surface` 원 + `schedule_rounded` 20 `inkMuted` | `battleJudgmentWindowClosedTitle` / `battleJudgmentWindowClosed` |

**확장형(진행 줄 — 결정 필요 4, designer 추천):** 제목 아래 4, 본문 위에 진행 줄 2–3개를 넣는다. 줄 하나 = 최소 높이 40, `[배지 24] 8 [이름 bodyMedium ink, 남은 폭] 8 [상태 labelMedium 14/700]`.

| 단계 | 내 판정 | 상대 판정 | AI 재판정 |
|---|---|---|---|
| `waitingOpponent` | ✓ 초록 배지 · `보냈어요`(success) | ⏳ sunken 배지 · `기다리는 중`(inkMuted) | (줄 없음) |
| `waitingAi` | ✓ `보냈어요` | ✓ `보냈어요` | 🔍 primaryPale 배지 · `보고 있어요`(primaryDeep) |
| `nothingToJudge` | — sunken 배지 · `판정할 사진 없음`(inkMuted) | ⏳ `기다리는 중` | (줄 없음) |
| `windowClosed` | 🕒 sunken 배지 · `기한 지남`(inkMuted) | 서버 값대로 ✓ / ⏳ | (줄 없음) |

- 상대 판정 줄이 드러내는 것은 "판정을 보냈는가"뿐이다(지금도 `waitingOpponent`/`waitingAi` 갈림으로 이미 드러난다). **무엇을 골랐는지는 보여 주지 않는다** — 서버가 주지 않는다.
- 내가 보낸 답을 다시 보여 주지 않는다(서버가 내 판정 값을 화면에 내주지 않는다 — 결정 필요 9).
- 이 카드 아래에는 지금처럼 `RevealedEvidenceSection`(두 사진)이 이어진다.

### 1D. 두 안 비교

| | 1A 단계 카드 + 큰 타일 (추천) | 1B 한 질문씩 펼침 + 세로 줄 |
|---|---|---|
| 훑어보기 | 카드 수 = 질문 수, 초록 체크 = 끝. 한 화면에 전부 보인다 | 한 번에 하나만 → 읽을 양이 가장 적다. 전체 질문 수는 잠긴 머리로만 보인다 |
| 도메인 "두 질문을 한 번에" | 그대로 드러난다 | 순차처럼 보인다(잠김은 모양뿐이라 규칙 위반은 아님) |
| 보내기 전 검토 | 위 카드들의 선택 모양이 곧 검토 | 요약 줄 두 개로 가장 분명 |
| 360dp·1.5배 | 가로 두 칸 유지(계산상), 넘치면 쌓기 | 가로 꽉 찬 줄이라 가장 안전 |
| 새 문자열 | 0(진행 한 줄은 선택) | `바꾸기`, (선택) `AI가 다시 봐요` |
| 상태 복잡도 | 지금과 같다(`_passed`, `_superiorId`) | + 펼친 단계 인덱스, 자동 스크롤·포커스 이동 |
| 낭독 | 순서대로 읽힌다 | 펼침·접힘 알림 필요, 포커스가 움직인다 |
| 기존 테스트 | 세그먼트 방향 단정만 바뀜 | + "처음부터 우열 선택지가 보인다" 단정이 깨짐(2단계가 접혀 있음) |

추천 이유: 오너가 원한 "안 읽어도 몇 개·뭘·어디까지·다음"을 1A는 **한 화면의 모양**으로 다 준다. 1B의 장점(검토)은 1A에서도 선택 모양이 그대로 남아 있어 대부분 얻는다.
1B는 상태·스크롤·낭독 비용이 크고 품질전의 "한 번에 묻는다"를 순차 흐름처럼 보이게 한다.

---

### 2. 보조·3차 버튼 위계

#### 2.0 진단
지금 보조 버튼(`OutlinedButton`)은 `surface` 흰 면 + 1.5dp `outline` 회청 테두리 + **3dp `ink` 남색 두께** — 주 버튼과 같은 두께에 테두리까지 더해져, 흰 카드 위에서는
"두꺼운 상자" 두 개가 나란히 선다. 두께가 주 행동의 신호가 되지 못하고, 테두리 + 두께 조합이 2010년대 "스큐어모픽 버튼"처럼 읽힌다. 모집 카드 두 버튼이 같은 모양이라
"고치기"와 "없애기"의 무게 차도 없다.

#### 2.1 안 2A "두께는 주 행동만, 보조는 토널" (**designer 추천**)

| 등급 | 위젯(역할) | 면 | 라벨·아이콘 | 테두리 | 두께 | 누름 | 비활성 |
|---|---|---|---|---|---|---|---|
| 주 | `FilledButton`, FAB | `primary` `#3355FF` | 흰색 | 없음 | 3dp `ink` | 면이 내려옴(현행) | `sunken` + `inkDisabled`, 납작 |
| 보조(토널) | `OutlinedButton`(테마를 토널로 바꾼다 — 2.4) | **`primaryTonal` `#D9E1FF`(새 토큰)** | `primaryDeep` `#2238C8` | 없음 | **없음** | 면 `primaryTonalPressed` `#C2CEFF`(새 토큰) | `sunken` `#E2E7EF` + `inkDisabled` |
| 3차(텍스트) | `TextButton` | 투명 | `primaryDeep` | 없음 | 없음 | 면 `sunken`(현행) | `inkDisabled` |
| 위험 | `FilledButton` + `AppButtonStyles.danger` | `danger` `#CC2F3F` | 흰색 | 없음 | 3dp `ink` | 현행 | 현행 |
| 위험 토널(옛 위험 윤곽) | `OutlinedButton` + `AppButtonStyles.dangerTonal`(새) | `dangerPale` `#FDE3E4` | **`dangerDeep` `#A3202E`(새 토큰)** | 없음 | 없음 | 면 `dangerTonalPressed` `#F9CDD0`(새) | `sunken` + `inkDisabled` |
| 위험 텍스트 | `TextButton` + `AppButtonStyles.dangerText`(새 — 포기 버튼의 인라인 스타일을 옮김) | 투명 | `danger` | 없음 | 없음 | 면 `dangerPale` + 라벨 `dangerDeep`(누르는 순간 danger/dangerPale 4.27 미달을 피한다) | `inkDisabled` |

크기:

| 크기 | 쓰는 곳 | 면 높이 | 터치 영역 | 모서리 | 좌우 안쪽 | 아이콘 | 라벨 |
|---|---|---|---|---|---|---|---|
| 보통 | 화면 폭 버튼(세로로 쌓이는 행동) | 주 52(면 49 + 두께 3) / 토널·텍스트 48 | 48 이상 | 12 | 16(텍스트 12) | 24 | `labelLarge` 16/700 |
| **작은(compact)** | 카드 안 작은 행동(모집 카드) | **40** | **48**(`MaterialTapTargetSize.padded`가 바깥을 48로 채운다) | **20(알약)** | 16(텍스트 12) | 20 | `labelLarge` 16/700(1.5배에서 면 높이가 늘어난다 — 최소값만) |

- 포커스: 모든 등급 2dp `primary` 링(주 버튼만 `ink` 링 — 현행).
- 화면 하나에 두께 있는 버튼은 원칙상 **하나**(주 행동). 대화상자의 [취소](텍스트) [확인](주)도 그대로 맞는다.
- 토널은 `primaryPale` 면(안내 블록) 위에 두지 않는다(1.07로 면이 사라진다). 지금 그런 자리는 없다.

#### 2.2 안 2B "모든 버튼이 눌린다 — 보조는 같은 색 계열의 얕은 두께"

게임감(design 4.2 "눌리는 버튼")을 모든 등급에 남기고, 낡아 보이는 원인(흰 면·회색 테두리·남색 두께)만 없앤다.

| 등급 | 면 | 라벨 | 테두리 | 두께 | 누름 |
|---|---|---|---|---|---|
| 주 | 2A와 같음 | | | 3dp `ink` | 현행 |
| 보조(토널) | `primaryTonal` `#D9E1FF` | `primaryDeep` | 없음 | **3dp `primaryTonalEdge` `#9DAEF2`(새 장식 토큰)** (작은 크기는 2dp) | 면이 두께만큼 내려옴(현행 메커니즘) |
| 3차 | 2A와 같음(두께 없음) | | | | |
| 위험 | 2A와 같음 | | | | |
| 위험 토널 | `dangerPale` | `dangerDeep` | 없음 | 3dp `dangerTonalEdge` `#EBA6AC`(새 장식 토큰) | 면이 내려옴 |
| 위험 텍스트 | 2A와 같음 | | | | |

크기는 2A 표와 같되 보통 토널 높이 52(면 49 + 두께 3), 작은 토널 40(면 38 + 두께 2).

#### 2.3 두 안 비교

| | 2A 두께는 주 행동만 (추천) | 2B 얕은 같은 색 두께 |
|---|---|---|
| "올드함" 해소 | 테두리·두께 모두 없어 가장 현대적(토널 버튼은 Material 3·최근 앱의 표준 보조 모양) | 테두리·남색이 사라져 해소되지만 두께가 남아 장난감 느낌은 유지 |
| 위계 | 두께 = 주 행동이라는 신호가 생긴다 → 판정 화면 "다음에 뭘 누르면 되는지"와 같은 규칙 | 두께 색(남색 vs 연파랑)으로만 위계를 갈라 차이가 약하다 |
| 게임감 | 주 버튼·FAB·승 라벨에 집중 | 모든 버튼에 남는다 |
| IP(Duolingo와 다름) | 더 멀어진다(레퍼런스는 모든 버튼에 같은 색 진한 톤 두께) | **레퍼런스의 "같은 색 계열 진한 톤 아래 그림자"에 가까워진다** — design 4.3이 "두께는 모든 버튼 공통 남색 ink 한 색"을 차이로 들었는데 그 근거가 약해진다 |
| 구현 | 토널은 `DepthBorder(depth: 0)` 하나 — 단순 | 등급별 두께 색 인자, 눌림 여백 계산 그대로 |

추천 이유: 오너가 문제 삼은 것이 바로 "흰 면 + 테두리 + 두께"이고, 2B는 IP 근거(4.3)를 약하게 만든다. 2A는 1A의 "누를 것은 하나만 두껍다"와 같은 규칙이라 두 피드백이 한 원칙으로 풀린다.

#### 2.4 위젯 이름과 역할
`OutlinedButton`을 앱 안에서 계속 "보조 역할 위젯"으로 쓰고 **테마(`outlinedButtonTheme`)를 토널 모양으로 바꾼다**(design 5.1 "화면이 모양을 지정하지 않아도 저절로" 원칙, 호출부·테스트 finder 유지).
이름이 모양과 어긋나므로 `app_theme.dart`에 "이 앱에서 OutlinedButton = 보조(토널), 테두리 없음" 주석을 남긴다. `ElevatedButton` 테마도 같은 모양으로(쓰는 곳 없음 — 기본값 유지용).
작은 크기는 `AppButtonStyles.compact`(높이 40·알약·아이콘 20·좌우 16, `merge`로 등급 스타일 위에 얹는다). `AppButtonStyles.dangerOutlined`는 `dangerTonal`로 이름을 바꾼다(옛 이름이 남으면 모양을 오해한다 — design 5.2 선례).

#### 2.5 대비 (WCAG 2.x, `contrastRatio`와 같은 공식으로 계산 — `app_palette_test`에 ±0.05로 고정)

| 쌍 | 대비비 | 기준 | 판정 |
|---|---|---|---|
| `primaryDeep` / `primaryTonal` (토널 라벨) | 6.55 | 4.5 | 통과 |
| `primaryDeep` / `primaryTonalPressed` (누름) | 5.50 | 4.5 | 통과 |
| `ink` / `primaryTonal` | 12.42 | 4.5 | 통과 |
| `primary` 포커스 링 / `primaryTonal` | 4.16 | 3 | 통과 |
| `dangerDeep` / `dangerPale` (위험 토널 라벨, 위험 텍스트 누름) | 6.17 | 4.5 | 통과 |
| `dangerDeep` / `dangerTonalPressed` | 5.23 | 4.5 | 통과 |
| `dangerDeep` / `surface` | 7.49 | 4.5 | 통과 |
| `danger` / `surface` · `background` (위험 텍스트) | 5.19 · 4.58 | 4.5 | 통과(현행 값) |
| `inkDisabled` / `sunken` (모든 비활성) | 3.30 | 3(비활성 목표) | 통과(현행 값) |
| `primaryTonal` 면 / `surface` · `background` (버튼 경계) | 1.30 · 1.15 | — | **경계는 장식.** 토널·텍스트 버튼은 라벨(6.55)이 버튼을 식별하므로 SC 1.4.11의 경계 대비 대상이 아니다(현행 텍스트 버튼과 같은 근거) |
| `primaryTonal` / `primaryPale` | 1.07 | — | 이 면 위에 토널을 두지 않는다 |
| `primaryTonalEdge` · `dangerTonalEdge` (2B만) | — | — | 장식 |

판정 화면(1A·1B) 쌍:

| 쌍 | 대비비 | 기준 | 판정 |
|---|---|---|---|
| 흰 숫자·체크 / `primary` 배지 | 5.41 | 4.5 | 통과 |
| 흰 체크 / `success` 배지 | 5.33 | 3(아이콘) | 통과 |
| `primaryDeep` 꼬리표 / `surface` | 8.51 | 4.5 | 통과 |
| `ink` · `inkMuted` / `sunken` (기준 상자) | 13.00 · 6.34 | 4.5 | 통과 |
| `outline` 미선택 테두리 / `surface` | 4.78 | 3 | 통과 |
| `primary` 선택 테두리 / `primaryPale` 선택 면 · `surface` 바깥 | 4.47 · 5.41 | 3 | 통과 |
| `ink` 라벨 / `primaryPale` | 13.35 | 4.5 | 통과 |
| `success` ✓ 아이콘 / `surface` · `primaryPale` | 5.33 · 4.41 | 3 | 통과 |
| `danger` ✕ 아이콘 / `surface` · `primaryPale` | 5.19 · 4.29 | 3 | 통과 |
| `primary` 🔍 아이콘 / `primaryPale` (불복 강조·AI 배지) | 4.47 | 3 | 통과(글자는 ink) |
| 상대 이니셜 `ink` / `amber`, 나 이니셜 흰색 / `primary` | 8.83 · 5.41 | 4.5 | 통과 |
| 선택 표시가 색에만 기대지 않음 | — | SC 1.4.1 | 테두리 굵기 1.5 → 2 + 체크 배지(타일) / 라디오 채움(줄) + 단계 배지 숫자 → 체크 |

#### 2.6 사용처 매핑 (앱 전체 보조·3차 버튼)

| # | 화면 / 파일 | 버튼(문구) | 지금 | 2A 등급 · 크기 | 아이콘 |
|---|---|---|---|---|---|
| 1 | 내 대결 모집 카드 `my_battles_screen.dart` | `기준 수정` | 보조 윤곽 | **보조(토널) · 작은** | `edit_rounded` 20(새) |
| 2 | 같은 곳 | `취소`(모집 취소) | 보조 윤곽 | **위험 텍스트 · 작은** | `close_rounded` 20 |
| 3 | 대결 상세 증거 `evidence_section.dart`(속도전·품질전 촬영 미리보기) | `다시 찍기` | 보조 윤곽 + 아이콘 | 보조(토널) · 보통, 가로 꽉 참 | `refresh_rounded` 24(현행) |
| 4 | 같은 곳(속도전 교체) | `사진 바꾸기` | 보조 윤곽 + 아이콘 | 보조(토널) · 보통, 가로 꽉 참 | `refresh_rounded` 24(현행) |
| 5 | AI 데이터 제공 동의 `ai_consent_screen.dart` | `동의하지 않음` | 보조 윤곽 | **3차(텍스트) · 보통, 가로 꽉 참** — 거절은 정당한 선택이지만 "동의하고 계속"(주)과 같은 상자로 경쟁시키지 않는다(결정 필요 7) | 없음 |
| 6 | 대결 만들기 차단 `create_battle_screen.dart` | `제목 고치기` | 보조 윤곽 | 보조(토널) · 보통 | 없음 |
| 7 | 대결 만들기 기준 결과 | `수정` | 보조 윤곽 | 보조(토널) · 보통 | 없음 |
| 8 | 같은 곳(수정 중) | `원래 기준으로 되돌리기` | 텍스트 | 3차 · 보통(변화 없음) | 없음 |
| 9 | 프로필 계정 `profile_screen.dart` | `로그아웃` | 보조 윤곽 + 아이콘 | 보조(토널) · 보통 | `logout_rounded` 24 |
| 10 | 같은 곳 | `오픈소스 라이선스` | 텍스트 + 아이콘 | 3차(변화 없음) | `description_outlined` |
| 11 | 같은 곳 | `계정 삭제` | 위험 | 위험(변화 없음) | `person_remove_rounded` |
| 12 | 프로필 동의 `ai_consent_section.dart` | `동의 철회` | 위험 윤곽 | **위험 토널 · 보통** | 없음 |
| 13 | 대결 상세 `battle_detail_screen.dart` | `대결 포기` | 인라인 위험 텍스트 | 위험 텍스트(`AppButtonStyles.dangerText`로 옮김, 누름 색만 바뀜) | `flag_rounded` |
| 14 | 각 화면 오류 상태(`StatusMessage` action), 사진 틀 | `다시 시도` | 텍스트 | 3차(변화 없음) | 없음 |
| 15 | 대결 찾기 `battle_recruits_screen.dart` | `조건 초기화`(조작판) | 텍스트 + 아이콘 16 | 3차(변화 없음) | `close_rounded` 16 |
| 16 | 기준 편집기 `criteria_views.dart` | `기준 추가` | 텍스트 + 아이콘 | 3차(변화 없음) | `add_rounded` |
| 17 | 모든 대화상자 | `취소`·`머무르기` / 확인 | 텍스트 / 주·위험 | 변화 없음 | — |
| 18 | 판정 묶음 1B만 | `바꾸기` | (새) | 3차 · 작은 | 없음 |

`FilledButton`(주) 사용처는 바꾸지 않는다.

#### 2.7 모집 카드 배치 (2A, `_MyRecruitBody`)

```
┌ AppPanel.flat "내 모집" (안쪽 16, 흰 면 #FFFFFF, 1dp #D3D9E3, 모서리 16) ─┐
│ 거실 바닥 걸레질                    ← bodyLarge 16/700 ink, 2줄, balanced    │
│ 8                                                                            │
│ [⚡ 속도전] [모집중(점선)] [1일]      ← 칩 줄(Wrap, 그대로)                  │
│ 8                                                                            │
│ 아직 아무도 참가하지 않았어요        ← bodySmall 13 inkMuted (그대로)         │
│ 16  (지금 12 → 16: 버튼 줄을 정보 줄과 떼어 놓는다)                          │
│                         [✕ 취소]  8  (✎ 기준 수정)                          │
│                          ↑ 위험 텍스트 · 작은      ↑ 토널 · 작은(알약 40)      │
└──────────────────────────────────────────────────────────────────────────────┘
```

- 배치: `OverflowBar(spacing: 8, alignment: end, overflowAlignment: end, overflowSpacing: 8, overflowDirection: up)`, 자식 순서 `[취소, 기준 수정]`.
  넘치면 세로로 쌓이고 **`기준 수정`이 위**(overflowDirection up — 대화상자 버튼 줄과 같은 규칙), 둘 다 오른쪽 정렬.
- `기준 수정`: 면 `#D9E1FF`, 라벨·아이콘 `#2238C8`, 높이 40, 모서리 20, 좌우 16, 아이콘 `edit_rounded` 20 + 8 + "기준 수정" 16/700. 누름 면 `#C2CEFF`.
- `취소`: 투명 면, 라벨·아이콘 `#CC2F3F`, 높이 40, 모서리 20, 좌우 12, `close_rounded` 20 + 8 + "취소" 16/700. 누름 면 `#FDE3E4` + 라벨 `#A3202E`.
- 폭 계산(360dp, 카드 안 폭 288): 1.0배 = 기준 수정 ≈ 126 + 8 + 취소 ≈ 83 = 217 → 한 줄. 1.5배 = 159 + 8 + 99 = 266 → 한 줄.
  라벨이 `모집 취소`(결정 필요 5)면 1.5배에서 159 + 8 + 151 = 318 > 288 → **두 줄(기준 수정 위, 모집 취소 아래), 둘 다 오른쪽**.
- 2B를 고르면 `기준 수정`에 2dp `#9DAEF2` 두께가 붙고(면 38) 나머지는 같다.

---

## 데이터 흐름

바뀌지 않는다.
- 판정: 타일/줄 탭 → `_JudgmentSectionState`의 `_passed`(bool?)·`_superiorId`(String? — **고른 사람의 user id 그대로**, 상대적 값 아님) → 둘 다 찼고(속도전은 `_passed`만)
  사진 URL이 준비됐으면 보내기 활성 → 확인 대화상자 → `battleRepository.submitJudgment(battleId, passed, superiorId)` → `battleDetailProvider`·`myBattlesProvider` 무효화 →
  서버 값으로 단계(`judgmentStage`)가 바뀌어 1C 카드가 그려진다. 실패 → `judgmentErrorMessage` 토스트 + 상세 다시 읽기(현행).
- 1B만: 펼친 단계 인덱스(int)를 화면 상태로 더 든다. 서버로 가지 않는다.
- 진행 줄(1C 확장형): `me.hasJudged`·`opponent.hasJudged`·`judgmentStage`만 읽는다(이미 상세에 있다). 승패를 계산하지 않는다.
- (결정 필요 8을 채택하면) 품질전 2단계 타일에 내 사진 썸네일: `mySubmission.objectPath` → 기존 `evidencePhotoUrlProvider`. 판정 창이 열린 뒤라 서버가 이미 내준다.
- 버튼: 동작·콜백 변화 없음(모양만).

## API 계약

변경 없음. `submit_judgment(battle_id, passed, superior_id)` RPC, `battle_participants.has_submitted`·`has_judged`, `battles.status`·`judge_deadline_at` 읽기 그대로.
새 RPC·테이블·컬럼·마이그레이션 없음. CLAUDE.md 도메인 규칙과의 충돌 점검:
- 판정 로직 위치: 화면은 단계 표시와 입력만 — 충돌 없음.
- 선택지: 정해진 두 개씩, 점수·부분 승인·자유 텍스트 없음 — 충돌 없음.
- 품질전 두 질문 한 번에: 1A·1B 모두 한 번의 보내기 — 충돌 없음(1B의 "잠김"은 모양뿐, 순서 강제 없음).
- 상대 판정 내용 비공개: 진행 줄은 "보냈는가"만 — 충돌 없음.
- 상태 전이·새 상태: 없음.

## 구현 범위 (파일 단위 — 순서·커밋 계획은 plan.md 몫)

| 파일 | 1A | 1B | 2A | 2B |
|---|---|---|---|---|
| `lib/features/battle/presentation/judgment_section.dart` | `_form` 재구성(단계 카드·기준 상자·타일·경고 줄 위치), `_ChoicePair` → 선택 타일 위젯, 대기 단계 1C | `_form` 재구성(펼침 상태·요약 줄·세로 줄), 1C | — | — |
| `lib/features/battle/presentation/criteria_views.dart` | 기준 상자(sunken, 점 머리표) 읽기용 변형 추가 — 기존 `CriteriaListBlock`은 다른 화면용으로 그대로 | 같음 | — | — |
| `lib/core/theme/app_palette.dart` | — | — | `primaryTonal`·`primaryTonalPressed`·`dangerDeep`·`dangerTonalPressed` | 2A 넷 + `primaryTonalEdge`·`dangerTonalEdge` |
| `lib/core/theme/app_theme.dart` | — | — | `outlinedButtonTheme`·`elevatedButtonTheme` → 토널(두께 0) | → 토널 + 연파랑 두께 |
| `lib/core/widgets/app_button_styles.dart` | — | — | `compact`, `dangerTonal`(← `dangerOutlined`), `dangerText` | 같음(두께 인자 포함) |
| `lib/core/theme/app_icons.dart` | `fail`, `aiReview`, `lock` | 같음 | `edit` | `edit` |
| `lib/features/battle/presentation/my_battles_screen.dart` | — | — | 모집 카드 `OverflowBar`, 작은 토널 + 위험 텍스트 | 같음 |
| `lib/features/battle/presentation/battle_detail_screen.dart` | — | — | 포기 버튼 인라인 스타일 → `dangerText` | 같음 |
| `lib/features/profile/presentation/ai_consent_section.dart` | — | — | `dangerOutlined` → `dangerTonal` | 같음 |
| `lib/features/battle/presentation/ai_consent_screen.dart` | — | — | `동의하지 않음` OutlinedButton → TextButton(결정 필요 7) | 같음 |
| `evidence_section.dart`, `create_battle_screen.dart`, `profile_screen.dart` | — | — | 코드 변경 없음(테마가 바꾼다) | 같음 |
| `lib/core/strings.dart` | 결정 필요 3·4·5에서 고른 것만 추가, 6에 따라 `battleJudgmentIntro` 처리 | + `바꾸기` 등 | 결정 필요 5 | 같음 |
| `docs/specs/redesign/design.md` | 5.5 기준 화면 2 줄을 이 문서로 가리킴 | 같음 | 4.2 표 "보조"·"위험 윤곽" 줄 갱신, 4.3 "두께는 모든 버튼 공통 ink" 문장을 "두께는 주·위험 버튼만"으로 | 4.2 갱신, 4.3 IP 근거 다시 씀 |

새 패키지 없음. iOS·i18n 무관.

## 테스트 영향

| 테스트 파일 | 영향 |
|---|---|
| `test/features/battle/battle_judgment_test.dart` | 선택지 finder `_choice`(KeepWordsText 원문)는 그대로 동작하게 라벨을 `KeepWordsText`로 둔다. `directionOf`(SegmentedButton 방향) 단정 2곳 → 새 타일 묶음의 가로/세로 배치 단정으로 교체. 안내문 루프의 `battleJudgmentIntro`는 결정 6에 따라 목록에서 뺀다. **1B만**: "처음부터 우열 선택지가 보인다" 단정(314–315행)을 "1을 답하면 2가 펼쳐진다"로 바꾸고, 불복 힌트 단정은 보조 문장 채택 여부에 따름 |
| 같은 파일(추가) | 단계 배지: 답하기 전 숫자 / 답한 뒤 체크(품질전 1·2 각각). 타일 `Semantics.selected`. 불복 선택 시 힌트가 안내 블록으로 바뀜. 경고 줄이 보내기 버튼 **위**에 있음(y 좌표). 속도전에 번호 배지 없음. 360dp·1.0/1.5배 넘침 없음 + 어절 경계(기존 그룹 확장). 1C 각 단계의 배지·(채택 시) 진행 줄 |
| `test/core/theme/app_palette_test.dart` | 새 토큰 대비 2.5 표 줄 추가(±0.05) |
| `test/core/theme/app_theme_test.dart` | 74행 "보조 버튼은 surface 면 + 1.5dp outline + 같은 두께" → 2A: "토널 면 + 테두리 없음 + 두께 없음(누름 = 면색)" / 2B: "토널 면 + 연파랑 두께" |
| `test/core/widgets/app_button_styles_test.dart` | `dangerOutlined` → `dangerTonal`, `compact`(높이 40·알약·터치 48), `dangerText`(누름 라벨 `dangerDeep`) |
| `test/core/theme/app_icons_test.dart` | "29개 상수" → 추가 수만큼(1A+2A = 33). 서로 다른 글리프·금지 도형 검사는 그대로 통과해야 한다 |
| `test/features/battle/my_battles_sections_test.dart` | 135행 `OutlinedButton` 기준 수정은 그대로, 139·203행 취소 finder `OutlinedButton` → `TextButton`. 추가: 360dp·1.5배에서 두 버튼 넘침 없음, 터치 영역 ≥ 48, (모집 취소 채택 시) 세로로 쌓이고 기준 수정이 위 |
| `test/features/battle/ai_consent_test.dart` | 423행 동의 철회 스타일 단정 → `dangerTonal`. `동의하지 않음` finder가 `OutlinedButton`이면 `TextButton`으로 |
| 도메인 테스트(`judgment_rules` 등) | 영향 없음 — 판정 로직 변경 없음 |

## 결정 필요

1. **판정 묶음 안**: 1A(단계 카드 + 큰 타일, 추천) / 1B(한 질문씩 펼침 + 세로 줄).
2. **보조 버튼 안**: 2A(두께는 주 행동만, 보조는 토널, 추천) / 2B(보조도 연파랑 얕은 두께). 2A를 고르면 design.md 4.3(IP 차이표)의 "두께는 모든 버튼 공통 남색"을 "두께는 주·위험 버튼만"으로 바꿔 적는다.
3. **새 짧은 문자열** — 고르지 않으면 괄호 안 대안으로 간다.

   | 후보 키 | 문구 | 쓰는 곳 | 고르지 않으면 |
   |---|---|---|---|
   | `battleJudgmentProgress(n, total)` | `{total}개 중 {n}개 골랐어요` | 1A 품질전 진행 한 줄 | 단계 배지 체크만 |
   | `battleJudgmentReady` | `다 골랐어요` | 1A 진행 한 줄 완료 | 같음 |
   | `battleJudgmentOnceShort` | `보내면 바꿀 수 없어요` | 보내기 위 경고 줄(현 두 문장을 대신) | 기존 `battleJudgmentOnce` 두 문장 |
   | `battleJudgmentAiRecheckShort` | `AI가 다시 봐요` | 1B 미달 줄 보조 문장 | 줄 묶음 아래 기존 `battleJudgmentRejectHint` |
   | `battleJudgmentChange` | `바꾸기` | 1B 요약 줄 | (1B는 이 문자열 없이는 성립하지 않는다 — 기존 `battleCriteriaEdit` "수정" 재사용 가능) |

4. **판정 진행 카드 확장형(진행 줄) 채택 여부**(추천: 채택). 필요한 새 문자열: `내 판정`, `상대 판정`, `AI 재판정`, `보냈어요`, `기다리는 중`, `보고 있어요`, `판정할 사진 없음`, `기한 지남`. 거절하면 1C 기본형(배지만 교체, 문자열 0).
5. **모집 카드 `취소` 라벨을 `모집 취소`로**(새 문자열 `battleRecruitCancelAction`)? 위험 텍스트로 바뀌면서 `기준 수정` 옆의 맨 `취소`는 "수정을 취소"로도 읽힌다. 기존 키 `battleRecruitCancel`('취소')을 바꾸면 그 키를 쓰는 다른 곳이 없는지 developer가 확인. 1.5배에서는 두 줄로 쌓인다(2.7).
6. **`battleJudgmentIntro`("상대 증거를 확정된 기준으로 판정해 주세요.") 처리**: 1A·1B 모두 판정 차례 화면에서 뺀다. 쓰는 곳이 없어지면 `strings.dart`에서 지울까, 남길까(추천: 지운다 — 안 쓰는 문자열은 다음 작업자를 헷갈리게 한다).
7. **`동의하지 않음`을 3차(텍스트)로 낮춰도 되는가?** 동의 화면은 법적 고지라 거절 경로가 덜 눈에 띄면 "거절을 숨긴다"로 읽힐 수 있다. 대안: 보조(토널)로 유지. designer는 텍스트(가로 꽉 참, `primaryDeep` 8.51)로도 충분히 보인다고 보지만 오너 판단에 맡긴다.
8. **품질전 2단계 타일에 사진 썸네일(나/상대)을 넣을까?** 지금 판정 차례 화면은 상대 사진만 크게 보여 줘서 "누가 더 잘했나"를 비교하려면 내 사진을 기억에 의존한다. 판정 창이 열린 뒤라 도메인상 둘 다 볼 수 있고 데이터도 있다(`mySubmission`). 넣으면 타일 위쪽에 높이 96 썸네일(`EvidencePhotoFrame` 작은 변형), 이니셜 배지는 썸네일 왼쪽 위 겹침. spec(redesign)에 없는 표시 추가라 질문으로 남긴다(추천: 넣는다).
9. **보낸 판정 내용을 다시 보여 줄까?** 지금 서버는 내 판정 값(승인/불복·우열)을 화면에 내주지 않아 1C에서 "무엇을 보냈는지"를 보여 줄 수 없다. 보여 주려면 읽기 경로(RLS·뷰) 변경이 필요해 이 후속(디자인)의 범위 밖이다. 이대로 둘지 확인.
10. **모집 취소에 확인 대화상자가 없다**(지금도 누르면 바로 취소). 이번 설계는 모양만 바꾸고 동작은 그대로 둔다. 확인 단계를 더할지는 별도 판단(더하면 새 동작이라 기획이 필요하다).
11. **`제목 고치기`(대결 만들기 차단 화면의 유일한 행동) 등급**: 매핑은 보조(토널). 유일한 복구 경로라 주 버튼으로 올리는 대안도 있다 — 사소한 UI 결정이라 오너 의견이 없으면 토널로 간다.
