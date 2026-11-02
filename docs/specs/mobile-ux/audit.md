# mobile-ux — 폰 사용성 점검과 개선안

작성: 2026-10-30, designer. 오너 요청("앱이다 보니까 핸드폰으로 쓸 텐데 사용자 친화적인 UI/UX였으면 좋겠다")에
대한 **진단 문서**다. 새 기능 기획이 아니고 구현도 아니다. 다음 단계(developer)가 이 문서만 읽고 일할 수 있게 적었다.

## 참고 / 입력

- `CLAUDE.md` (범위·도메인 규칙·하지 말 것)
- `docs/specs/ui-restructure/design.md` (4탭 구조와 그 근거), `docs/specs/retro-theme/readability.md` (글꼴 개정 — **이미 끝난 얘기**)
- 읽은 코드: `lib/core/**`, `lib/features/*/presentation/**`, `lib/features/battle/domain/**`, `lib/core/strings.dart`, `pubspec.yaml`
- 기준 화면 크기: Galaxy S20(SM-G981N) = 논리 **360×800dp**(1440×3200, DPR 4), Pixel 6 = 411×914dp. 세로 전용.

### 전제와 한계

- **앱을 실행하지 못했다.** 모든 근거는 코드다. 치수·잘림처럼 실측이 필요한 것은 산수 과정을 적고 `추정`이라고 표시했다.
- `pubspec.yaml` 기준 쓸 수 있는 것은 `flutter_riverpod`, `supabase_flutter`, `image_picker`, `shared_preferences`뿐이다.
  **이 문서의 모든 개선안은 새 패키지가 필요 없다**(`PopScope`, `Timer`, `RefreshIndicator`, `ImagePicker.retrieveLostData`는 전부 SDK·기존 패키지).
- 다루지 않은 것: 글꼴 크기·행간·픽셀 경계(readability.md에서 종결), 텍스트 배율 상한 1.3(readability.md 3장 결정 2에서 **이미 배포 후로 결정**),
  푸시 알림(별도 feature `push-notification`), 친구·랭킹·결제·그룹·다국어·iOS·테마 설정(범위 밖).
- **API 계약 변경: 없음.** 신규 RPC·마이그레이션·RLS 변경을 요구하는 항목이 하나도 없다. 서버가 이미 내주는 값
  (`battle_participants.has_submitted`/`has_judged`, `battles.deadline_at`, `get_my_limits.daily_battle_used`)을 **표시만** 더 한다.
  판정·승패 계산은 어느 항목도 클라이언트로 끌어오지 않는다.

---

## 요약 표 (최소 변경 · 큰 효과 순)

| # | 무엇 | 심각도 | 비용 |
|---|---|---|---|
| M1 | 내 대결 카드가 "지금 내가 할 일"과 남은 시간을 말하지 않는다 | 배포 전 | 작음 |
| M2 | 대결 상세 로딩 실패에 재시도가 없고, 로딩 표시가 거의 안 보인다 | 배포 전 | 아주 작음 |
| M3 | 대결 제목 입력에 "사진으로 증명 가능해야 한다"는 안내가 없다 | 배포 전 | 아주 작음 |
| M4 | 속도전/품질전을 고르는 자리에 설명이 없다 (+ `showSelectedIcon` 누락) | 배포 전 | 아주 작음 |
| M5 | "찍은 지 10분 안에 제출" 규칙이 화면에 없다 | 배포 전 | 아주 작음 |
| M6 | 첫 화면(내 대결 빈 상태)이 이 앱이 무엇인지 말하지 않는다 | 배포 전 | 작음 |
| M7 | 기준 생성 중·생성 후 뒤로 가면 결과와 횟수가 조용히 사라진다 | 배포 전 | 작음 |
| M8 | 오늘 대결 한도를 다 쓴 사용자가 "참가 실패"로만 그 사실을 안다 | 배포 전 | 작음 |
| M9 | 할 일 삭제에 확인이 없고, 체크는 눌러도 반응이 없다 | 좋아짐 | 중간 |
| M10 | 전면 로딩 표시가 16dp 점 세 개뿐이다 (빈 화면으로 읽힌다) | 좋아짐 | 아주 작음 |
| M11 | 프로필에 당겨서 새로고침이 없고 실패에 재시도가 없다 | 좋아짐 | 작음 |
| M12 | 모집 취소가 확인 없이 즉시 실행되고 바로 옆 8dp에 `기준 수정`이 있다 | 좋아짐 | 작음 |
| M13 | 포기·로그인·로그아웃에 진행 표시가 없다(중복 요청 가능, 실패 무음) | 좋아짐 | 작음 |
| M14 | 찾기 탭 상단 고정 조작 영역이 화면의 1/3을 먹고, 전부 엄지 밖이다 | 좋아짐 | 중간 |
| M15 | 기간 빠른 선택 5칸 세그먼트가 좁은 폭·큰 글자에서 잘릴 수 있다 | 좋아짐 | 작음 |
| M16 | 모집 상세 시트의 `참가` 버튼이 긴 스크롤 맨 끝에 있다 | 좋아짐 | 작음 |
| M17 | "AI가 다시 보고 있어요"에서 결과를 다시 확인하는 방법을 말하지 않는다 | 좋아짐 | 아주 작음 |
| M18 | 프로필의 `계정` 섹션이 전적 전체 아래에 묻힌다 | 좋아짐 | 아주 작음 |
| M19 | 남은 시간이 갱신되지 않는다(30분·1시간 대결에서 틀린 값이 머문다) | 좋아짐 | 작음 |
| M20 | 카메라에서 돌아오는 중 앱이 죽으면 사진이 사라진다 | 배포 후 | 중간 |
| M21 | 미제출 사진을 들고 화면을 떠나는 길이 조용하다 | 배포 후 | 작음 |
| M22 | 할 일 목록에 당겨서 새로고침이 없다 | 배포 후 | 아주 작음 |

**지금 하나만 고른다면 → M1.** 이 앱에는 MVP에서 알림이 없다. 상대가 제출했는지, 내가 판정해야 하는지,
마감이 몇 시간 남았는지를 알 수 있는 유일한 자리가 `내 대결` 목록 카드인데, 지금 그 카드는
`서로 판정하는 중이에요` 한 문장만 보여 주고 "그래서 내가 눌러야 하는지"를 말하지 않는다.
필요한 데이터는 **이미 같은 요청으로 받아 와 버리고 있다**(아래 근거). 추가 네트워크 0.

---

## 배포 전에 고쳐야 함

### M1. 내 대결 카드가 "지금 내가 할 일"과 남은 시간을 말하지 않는다

**무엇이 불편한가**
`판정중` 칩과 `서로 판정하는 중이에요` 한 줄은 두 상황을 합쳐 버린다 — ① 내가 상대 증거를 아직 판정하지 않았다(들어가서 눌러야 한다)
② 내 판정은 보냈고 상대를 기다린다(할 일 없음). 제출 창(`active`)에서도 ① 내가 사진을 안 냈다 ② 냈다가 구분되지 않는다.
마감까지 남은 시간도 목록에 없다. 기간이 30분·1시간까지 짧아졌는데(`duration_rules.dart:12`) 목록만 보고는 급한지 알 수 없다.
푸시가 없는 MVP에서 이 카드가 유일한 "할 일 신호"다.

**어디**
- `lib/features/battle/domain/battle_summary.dart:24-41` — `statusLineAt`이 `judging`이면 문장 하나로 끝낸다. 보유 필드는 `opponent`뿐(`:17`).
- `lib/features/battle/domain/battle_providers.dart:41-65` — `fetchParticipantsOf`로 **양쪽 참가자 행을 이미 전부 받아 놓고** `participantOf(b.id, otherId)`로 상대만 쓰고 내 행을 버린다.
- `lib/features/battle/data/battle_repository.dart:148-154` — `fetchParticipantsOf`는 `battle_id in (...)` 전체 행을 돌려준다(필터 없음).
- `lib/features/battle/domain/judgment_rules.dart:35-59` — `judgmentStageOf(...)` 순수 함수가 이미 있고, 필요한 입력이 `status`/양쪽 `has_submitted`/`has_judged`/`judge_deadline_at`뿐이다.
- `lib/features/battle/presentation/battle_summary_list.dart:70-80` — 상태 줄을 그리는 자리.
- `lib/core/strings.dart:99-102` — 지금 있는 상태 줄 문구 3종.

**어떻게 고치는가**
1. `BattleSummary`에 `me` 참가자 행을 더한다(`battle_providers.dart`에서 `participantOf(b.id, myId)` 한 줄 — **추가 네트워크 없음**).
2. `statusLineAt`에서 `judging`이면 문장을 고정하지 말고 `judgmentStageOf(...)`를 그대로 불러 단계별로 고른다.
   - `myTurn` → `내가 판정할 차례예요`(강조)
   - `waitingOpponent` → `상대 판정을 기다려요`
   - `waitingAi` → `AI가 다시 보고 있어요`
   - `nothingToJudge`/`windowClosed` → 기존 중립 문구
3. `active`이고 `me.hasSubmitted == false`면 `아직 사진을 내지 않았어요`(강조). 이미 냈으면 기존 `상대가 제출했어요` 규칙 유지.
4. 카드 하단에 남은 시간 한 줄: `battle.deadlineAt`이 있고 미래면 `battleDeadlineLeft(...)` 재사용(`strings.dart:96`).
   서식 함수 `_formatRemaining`은 `battle_detail_screen.dart:398-403`에 이미 있으므로 **공용 위치로 꺼내 두 곳이 같이 쓴다**(새 규칙을 만들지 않는다).
5. 강조는 이미 있는 수단으로만: `statusLine`은 `colorScheme.primary` + `w600`로 그려지고 있으니(`battle_summary_list.dart:75-78`)
   "내 차례"에만 `PixelTag`(`battle_chips.dart`) 하나를 더하는 선택도 가능하다 — 사소한 UI 결정이라 developer 재량.

**비용** 작음. 파일 4개, 순수 함수 재사용, 문자열 3~4개 추가. `judgmentStageOf` 테스트 패턴이 이미 있어 유닛 테스트도 싸다.
**위험** 낮음. 서버가 기록한 불린만 읽어 문장을 고르는 표시 로직이고 승패를 계산하지 않는다(CLAUDE.md "화면은 표시만" 준수).
단, 상태 줄 우선순위가 바뀌므로 `test/features/battle/` 아래 기존 기대값이 깨질 수 있다 — **지우지 말고 새 기대값으로 고친다.**

---

### M2. 대결 상세 로딩 실패에 재시도가 없고, 로딩 표시가 거의 안 보인다

**무엇이 불편한가** 상세를 읽다 실패하면 화면에 `대결 정보를 불러오지 못했습니다.` 한 줄만 남는다.
`RefreshIndicator`가 `data` 갈래 **안쪽**에만 있어서 당겨서 새로고침도 안 된다 — 복구 방법이 "뒤로 갔다가 다시 들어오기"뿐이다.
지하철에서 한 번 실패하면 막다른 길처럼 보인다. 로딩도 16dp 점 세 개(M10 참고)뿐이라 흰 화면으로 읽힌다.
`battleDetailProvider`는 `firstWhere`를 쓰므로(`battle_providers.dart:72-73`) 데이터 모양이 어긋날 때도 같은 갈래로 떨어진다.

**어디** `lib/features/battle/presentation/battle_detail_screen.dart:74-123` (특히 `:118` loading, `:119-122` error, `:75-76` RefreshIndicator 위치)

**어떻게 고치는가**
- error → `StatusMessage.error(message: AppStrings.battleLoadDetailFailed, fill: true, action: TextButton(다시 시도 → ref.invalidate(battleDetailProvider(battleId))))`.
  같은 패턴이 `my_battles_screen.dart:163-172`에 이미 있다.
- loading → `StatusMessage.loading(message: AppStrings.loading, fill: true)`.

**비용** 아주 작음(한 화면, 두 갈래). **위험** 없음.

---

### M3. 대결 제목 입력에 "사진으로 증명 가능해야 한다"는 안내가 없다

**무엇이 불편한가** 제목 힌트는 `무엇을 걸고 대결할까요?`뿐이다. 사용자가 "책 30분 읽기", "명상하기"를 쓰면
AI 기준 생성이 **차단**되고(도메인 규칙) 하루 10회 중 1회가 차감된 뒤 최대 30초를 기다린 끝에
`사진으로 증명할 수 없는 미션이라 대결로 만들 수 없어요`를 본다. 첫 사용자가 가장 쉽게 밟는 함정이고, 되돌릴 수 없는 소모다.

**어디**
- `lib/features/battle/presentation/create_battle_screen.dart:312-317` (제목 TextField, hint만)
- `lib/core/strings.dart:27` (`battleTitleHint`), `:242` (차단 문구), `:246` (남은 횟수), `:232-233` (최대 30초)

**어떻게 고치는가** 제목 필드 **아래** 한 줄을 추가한다(`bodyMedium`):
`사진 한 장으로 증명할 수 있는 일이어야 해요. 예: 아침 7시 기상, 책상 정리 완료` — 예시를 포함해야 뜻이 전달된다.
문구는 도메인 사실이라 오너 확인 대상(결정 5).

**비용** 아주 작음(문자열 1개 + `Text` 1개). **위험** 없음. 서버 차단 규칙은 그대로다.

---

### M4. 속도전/품질전을 고르는 자리에 설명이 없다 (+ `showSelectedIcon` 누락)

**무엇이 불편한가** 대결 만들기의 첫 선택이 유형인데 화면에는 `속도전`/`품질전` 두 단어뿐이다.
처음 쓰는 사람은 "먼저 통과한 사람이 이긴다 / 더 잘한 사람이 이긴다"는 차이를 모른 채 고른다.
그 설명 문장은 **이미 코드에 있고**(`battleTypeTagline`) 모집 상세 시트에서만 쓰인다 — 즉 참가자는 보는데 만드는 사람은 못 본다.
속도전은 재제출 5회, 품질전은 단 한 번이라 결과가 크게 다르다.

**어디**
- `lib/features/battle/presentation/create_battle_screen.dart:303-310` (유형 SegmentedButton)
- `lib/features/battle/presentation/battle_chips.dart:29-31` (`battleTypeTagline`), `lib/core/strings.dart:257-258`
- `lib/features/battle/presentation/recruit_detail_sheet.dart:151` (지금 유일한 사용처)

**어떻게 고치는가**
1. 세그먼트 바로 아래에 `Text(battleTypeTagline(_type), style: bodyMedium)` 한 줄. **문자열 추가 0개.**
2. 같은 `SegmentedButton`에 `showSelectedIcon: false`가 빠져 있다. 같은 파일 `:200`과 `:254`에는 들어 있고
   `battle_recruits_screen.dart:233-234`에는 "테마가 selectedIcon(체크)을 주므로 끄지 않으면 라벨 폭을 먹어 글자가 잘린다"는
   주석까지 달려 있다. 즉 이 한 곳만 빠진 것이다(`app_theme.dart:272`가 테마에서 체크 아이콘을 준다). 한 줄 추가.

**비용** 아주 작음. **위험** 없음.

---

### M5. "찍은 지 10분 안에 제출" 규칙이 화면에 없다

**무엇이 불편한가** 서버는 촬영 시각과 수신 시각이 10분 이상 벌어진 사진을 거부한다(도메인 규칙, 오류 문구 `strings.dart:278`).
그런데 미리보기 화면에는 제한 시간이 한 글자도 없다. 사진을 찍어 두고 다른 일을 하다 돌아와 제출하면
**업로드를 다 마친 뒤** `찍은 지 10분이 지난 사진이에요. 다시 찍어 주세요.`를 본다. 데이터·시간을 다 쓰고 처음으로 돌아간다.

**어디**
- `lib/features/battle/data/evidence_camera.dart:23-34` (`capturedAt` 기록)
- `lib/features/battle/presentation/evidence_section.dart:147-163` (속도전 미리보기 → 제출/다시 찍기), `:242-257` (품질전 미리보기)
- `lib/core/strings.dart:277-278` (거부 문구 2종)

**어떻게 고치는가** 미리보기 상태의 제출 버튼 아래 한 줄: `찍은 지 10분 안에 제출해야 해요.`
카운트다운까지 만들 필요 없다(타이머·생명주기 비용 대비 효과 낮음). 품질전에는 기존 `battleEvidenceQualityOnce` 줄 옆에 붙인다.

**비용** 아주 작음(문자열 1개, 두 자리). **위험** 없음.

---

### M6. 첫 화면(내 대결 빈 상태)이 이 앱이 무엇인지 말하지 않는다

**무엇이 불편한가** 로그인 직후 첫 탭은 `내 대결`이고(`app_tab.dart:12`), 새 계정이 보는 것은
`진행 중인 대결이 없어요.` + `지난 대결은 프로필에서 볼 수 있어요.` + `대결 찾기` 버튼뿐이다.
"친구와 같은 투두를 걸고 겨룬다", "증거는 앱 카메라 사진", "서로 판정하고 갈리면 AI가 확정", "무료는 하루 1대결"을
어디서도 먼저 알려 주지 않는다. AI 판정 설명은 동의 화면에만 있고, 그 화면은 만들기/참가를 누른 **뒤에야** 뜬다.
게다가 `대결 찾기`를 누르면 초기에는 그쪽도 비어 있어(모집 0건) 빈 화면이 연속으로 두 번 나온다.

**어디**
- `lib/features/battle/presentation/my_battles_screen.dart:151-160` (빈 상태), `lib/core/strings.dart:57,60`
- `lib/features/battle/presentation/battle_recruits_screen.dart:302-315` (찾기 탭의 두 번째 빈 화면)

**어떻게 고치는가** 빈 상태 위에 `PixelFrame.tone(tone: PixelTone.info)` 한 장을 두고 **세 줄**만 적는다.
- `같은 할 일을 걸고 둘이 겨뤄요. 먼저 올린 사람과 자동으로 매칭돼요.`
- `증거는 앱에서 찍은 사진 한 장이에요.`
- `서로 판정하고 의견이 갈리면 AI가 기준으로 확정해요.`

기존 CTA(`대결 찾기`)는 그대로 둔다. **온보딩 화면·캐러셀·툴팁 투어를 만들지 않는다**(범위 밖, 뒤로가기 경로만 늘어난다).
문구는 도메인 사실이라 오너 확인 대상(결정 5).

**비용** 작음(문자열 3개 + 블록 1개, 빈 상태에서만 보임). **위험** 없음.

---

### M7. 기준 생성 중·생성 후 뒤로 가면 결과와 횟수가 조용히 사라진다

**무엇이 불편한가** `AI 기준 만들기`를 누르면 화면이 생성 대기로 바뀌지만 앱바 뒤로가기와 시스템 뒤로가기 제스처는 그대로 열려 있다.
빠져나가면 `if (!mounted) return`으로 결과가 버려지고, 하루 10회 중 1회는 차감된 상태로 남는다(서버에서 이미 셌다).
기준을 손으로 고친 뒤 뒤로 가는 경우도 같다 — 확인도 경고도 없다. 세로 폰에서 가장 흔한 오조작이 바로 뒤로가기 제스처다.

**어디**
- `lib/features/battle/presentation/create_battle_screen.dart:97-119` (`_generate`, `_Stage.generating`), `:280-289` (단계별 body — 앱바는 공통), `:403-470` (편집 상태)
- `lib/features/battle/presentation/edit_recruit_criteria_screen.dart:50-75` (`_recheck`도 횟수를 쓴다)

**어떻게 고치는가** 두 화면을 `PopScope`로 감싼다(Flutter SDK, 패키지 추가 없음).
- `canPop`: 생성 중(`_busy`)이거나 결과를 들고 있을 때(`_result != null`)만 false.
- 막았을 때 확인 다이얼로그: `지금 나가면 만든 기준이 사라져요. 사용한 횟수는 돌아오지 않아요.` → `나가기`/`계속하기`.
- **입력 단계에서는 반드시 그냥 나가지게 둔다**(아무것도 잃지 않는데 확인창을 띄우면 그게 더 나쁘다 — 점검 기준 8의 반대 방향).

**비용** 작음(두 화면). **위험** 중간-낮음. `PopScope`를 잘못 걸면 뒤로가기가 먹지 않아 사용자가 갇힌다 →
"입력 단계는 항상 pop 가능"을 위젯 테스트로 고정할 것.

---

### M8. 오늘 대결 한도를 다 쓴 사용자가 "참가 실패"로만 그 사실을 안다

**무엇이 불편한가** 무료 사용자는 하루(KST) 매칭 대결 1개다. 그 한도를 쓴 사람이 `대결 찾기`에 들어오면
목록이 평소처럼 보이고, 카드를 눌러 시트를 열고 `이 기준으로 참가`까지 누른 뒤에야
`오늘은 이미 대결을 했어요...`를 받는다. 모집 중 중복(`hasPending`)에 대해서는 이미 상단 배너로 **미리** 알려 주고 있어서
(같은 화면, 같은 데이터) 한도만 빠진 상태다.

**어디**
- `lib/features/battle/presentation/battle_recruits_screen.dart:162` (`hasPending`만 읽는다), `:329-330` (배너 조건), `:377-398` (`_buildPendingBanner`)
- `lib/features/battle/data/criteria_check_result.dart:59-60` — `dailyBattleUsed`가 **같은 `get_my_limits` 응답에 이미 들어 있다**
- `lib/core/strings.dart:270-271` (사후 오류 문구), `lib/features/battle/domain/criteria_rules.dart:63-69` (만들기 쪽 사전 안내 선례)

**어떻게 고치는가** 배너 조건을 `hasPending || dailyBattleUsed`로 넓히고 문구를 분기한다
(`dailyBattleUsed`면 "오늘 대결은 이미 했어요. 내일 다시 참가할 수 있어요." + 액션은 `내 대결 보기`가 아니라 없음).
**카드 탭·시트 열기는 막지 않는다** — 기준을 구경하는 것은 한도와 무관하고, 막으면 둘러보는 재미가 사라진다.
참가 버튼은 서버가 어차피 거부하므로 그대로 둬도 되고, 시트 안에서 비활성화하는 것은 developer 재량.

**비용** 작음(한 화면, 추가 조회 0). **위험** 낮음. 사전 안내는 편의일 뿐이고 **차단은 서버가 한다**는 기존 원칙을 그대로 둔다.

---

## 고치면 확실히 좋아짐

### M9. 할 일 삭제에 확인이 없고, 체크는 눌러도 반응이 없다

**무엇이 불편한가**
- 행 오른쪽 끝 휴지통 아이콘을 누르면 **즉시 삭제**된다. 확인도, 되돌리기도 없다. 행 전체 탭은 수정 다이얼로그라서
  "제목을 고치려고 오른쪽을 눌렀다가 삭제"가 일어난다. 되돌릴 수 없는 동작 중 유일하게 확인이 없는 곳이다
  (포기·계정 삭제·동의 철회·품질전 제출·판정 보내기에는 모두 확인창이 있다).
- 체크박스를 누르면 왕복이 끝날 때까지 **아무 변화가 없다**. 느린 망에서는 무시당한 것처럼 보여 또 누르고, 요청이 두 번 나간다.

**어디** `lib/features/todo/presentation/todo_list_screen.dart:48-56`(`_toggleDone`), `:58-66`(`_deleteTodo`), `:92-112`(ListTile 구성: leading 체크박스, onTap 수정, trailing 삭제)

**어떻게 고치는가**
1. 삭제 전 확인 다이얼로그(이 앱의 다른 위험 동작과 같은 형식: 제목 + 내용 + `취소`/`삭제`).
2. 처리 중인 todo id 집합을 들고 그 행의 추가 입력을 무시한다. 체크 모양은 왕복을 기다리지 말고 즉시 바꿔 보여 준다
   (서버 응답이 오면 `invalidate`로 정답에 맞춰진다. 실패하면 기존 토스트 + 원래 모양으로 복구).

**비용** 중간. `TodoListScreen`이 `ConsumerWidget`이라 `ConsumerStatefulWidget`으로 바꿔야 한다.
**위험** 낮음. 서버가 정답이고 낙관적 표시가 어긋나도 invalidate로 교정된다.
**대안 검토** 되돌리기 스낵바는 지운 행을 **다시 만드는 것**이어서 id·생성 시각·완료 상태가 달라지고 목록 위치가 바뀐다 → 결정 4.

---

### M10. 전면 로딩 표시가 16dp 점 세 개뿐이다

**무엇이 불편한가** `PixelLoader.medium`은 8dp 사각형 3개, 전체 높이 16dp·폭 32dp다.
이게 360×800dp 화면 가운데에 혼자 놓이면 사실상 빈 화면으로 읽힌다 — 특히 로그인 직후(세션 확인)와 대결 상세 진입처럼
**사용자가 처음 기다리는 자리**가 그렇다. 문구 없이 쓰는 호출이 여럿이다.

**어디** `lib/core/widgets/pixel_loader.dart:48-51`(치수), 문구 없는 사용처:
`lib/features/auth/presentation/auth_gate.dart:21`, `lib/features/battle/presentation/battle_detail_screen.dart:118`,
`lib/features/profile/presentation/profile_screen.dart:40,70,217`, `lib/features/todo/presentation/todo_list_screen.dart:123`

**어떻게 고치는가** 전면 대기에는 전부 `StatusMessage.loading(message: AppStrings.loading, fill: true)`를 쓴다.
선례가 이미 있다: `create_battle_screen.dart:282-286`(문구 + 보조 문구 + `fill`).
점 3개는 버튼 안·카드 안 같은 **작은 자리에만** 남긴다. 로더 자체의 크기나 모양은 바꾸지 않는다(retro-theme 결정 영역).

**비용** 아주 작음(호출부 교체). **위험** 없음.

---

### M11. 프로필에 당겨서 새로고침이 없고 실패에 재시도가 없다

**무엇이 불편한가** 프로필의 세 영역(이름·점수·전적)이 각각 실패할 수 있는데, 실패하면 전부 맨 텍스트 한 줄이다.
`RefreshIndicator`도 없어서 복구 방법이 "다른 탭으로 갔다가 돌아오기"뿐이다(그때 `main_shell.dart:39-42`가 invalidate한다).
이건 사용자가 알 수 없는 복구 방법이다. 다른 탭에는 당겨서 새로고침이 다 있다.

**어디** `lib/features/profile/presentation/profile_screen.dart:34-36`(ListView 직접), `:41-44`, `:71-74`, `:218-221`(에러 갈래 3곳)

**어떻게 고치는가** ListView를 `RefreshIndicator`로 감싸고 `myProfileProvider`·`myPlayerStatsProvider`·`battleRecordsProvider`·`myAiConsentProvider`를 invalidate한다
(`my_battles_screen.dart:58-68`과 같은 모양, 실패해도 다시 던지지 않는 처리까지 포함). 에러 갈래 3곳에 `다시 시도` 버튼.

**비용** 작음. **위험** 없음.

---

### M12. 모집 취소가 확인 없이 즉시 실행되고 바로 옆 8dp에 `기준 수정`이 있다

**무엇이 불편한가** `내 대결` 탭 모집 구역의 버튼 두 개가 오른쪽 끝에 8dp 간격으로 붙어 있다 —
`기준 수정`(OutlinedButton)과 `취소`(TextButton). 오른손 엄지가 가장 자연스럽게 닿는 자리에 되돌릴 수 없는 쪽이 있다.
취소하면 AI가 만들어 준 기준도 함께 사라져 다시 만들려면 하루 10회 중 1회를 또 쓴다. 확인창이 없고,
요청 중에도 버튼이 계속 눌려 중복 호출이 가능하다. 라벨도 그냥 `취소`라서 "무엇을 취소하는지"가 약하다.

**어디** `lib/features/battle/presentation/my_battles_screen.dart:223-240`(버튼 Row, 간격 `:234`), `:25-47`(`_cancel` — 확인·진행 표시·중복 방지 없음), `lib/core/strings.dart:36`

**어떻게 고치는가** 확인 다이얼로그를 둔다: `모집을 취소할까요?` / `만들어 둔 판정 기준도 함께 사라져요. 다시 만들면 기준 생성 횟수가 1회 들어요.`
확인 뒤에는 버튼을 비활성 + `PixelLoader.small()`로 바꾼다(`_DeleteAccountButton`이 선례 — `profile_screen.dart:165-174`).
버튼 재배치는 하지 않는다(확인창이 오조작을 이미 막는다).

**비용** 작음. **위험** 없음.

---

### M13. 포기·로그인·로그아웃에 진행 표시가 없다

**무엇이 불편한가**
- **포기**: 확인창까지는 좋다. 그런데 확인한 뒤 RPC가 도는 동안 버튼이 그대로 눌리는 상태로 남는다. 한 번 더 누르면
  두 번째 호출이 실패해 `포기에 실패했습니다`가 뜬다 — 실제로는 포기가 성공했는데 실패로 읽는다.
- **로그인**: `구글로 로그인`을 누르면 외부 인증이 뜰 때까지 화면에 아무 변화가 없다. 두 번 눌리면 흐름이 두 개 열린다.
- **로그아웃**: `signOut()`을 `await`도 `catch`도 없이 던진다. 실패하면 아무 일도 일어나지 않고 아무 말도 없다
  — CLAUDE.md "에러는 삼키지 않는다" 위반이다(장식 연출 예외에 해당하지 않는다).

**어디** `lib/features/battle/presentation/battle_detail_screen.dart:27-59,101-113`,
`lib/features/auth/presentation/login_screen.dart:16-27,59-64`,
`lib/features/profile/presentation/profile_screen.dart:86-90`

**어떻게 고치는가** 세 곳 모두 `_busy` 플래그 + 라벨 자리 `PixelLoader.small()` + 실패 토스트.
`login_screen`·`profile_screen`의 해당 조각은 `ConsumerStatefulWidget`으로 바꿔야 한다(`_DeleteAccountButton`처럼 **버튼만** 떼어내면 화면 전체를 바꾸지 않아도 된다).

**비용** 작음. **위험** 낮음.

---

### M14. 찾기 탭 상단 고정 조작 영역이 화면의 1/3을 먹고, 전부 엄지 밖이다

**무엇이 불편한가** 검색창 + 유형 세그먼트 + 기간대 세그먼트가 스크롤되지 않는 고정 영역에 쌓여 있다.
산수(추정): 세로 패딩 12+12 + 검색 48 + 8 + 세그먼트 48 + 8 + 세그먼트 48 ≈ **184dp**. 여기에 앱바 56dp와 상태바를 더하면
360×800dp 기기에서 첫 모집 카드가 화면 **270dp 아래**에서 시작하고, 하단 탭바(72dp+2dp)까지 빼면 목록에 남는 높이는 약 450dp —
카드 두 장 남짓이다. 조건을 안 걸고 둘러보는 대다수 사용자가 늘 이 비용을 낸다.
게다가 조작 요소가 전부 상단 1/3(엄지가 가장 안 닿는 영역)에 있고, `조건 지우기`도 그 안이다.

**어디** `lib/features/battle/presentation/battle_recruits_screen.dart:188-199`(Column 고정 + Expanded), `:203-269`(`_buildControls`)

**어떻게 고치는가(택 1 — 결정 1)**
- **안 A(작음)**: 유형 세그먼트만 남기고 기간대는 `필터` 토글 아래로 접는다(조건이 걸려 있으면 펼친 상태로 유지). 약 56dp 회수.
- **안 B(중간)**: 두 축을 하단 시트(`showModalBottomSheet`)로 옮기고 상단에는 검색창 + 적용된 조건 칩만 남긴다.
  조작이 화면 **아래쪽**에서 일어나 한 손 조작에 맞고, 약 112dp를 회수한다. 조건 표시는 칩으로 계속 보인다.

**비용** A 작음 / B 중간. **위험** recruit-browse 설계가 "고정 조작 영역"을 **의도적으로** 택했다
(`battle_recruits_screen.dart:203` 주석: "스크롤되지 않으므로 지금 어떤 조건이 걸려 있는지가 계속 보인다").
그 의도를 깨는 변경이므로 오너 결정이 필요하다.

---

### M15. 기간 빠른 선택 5칸 세그먼트가 좁은 폭·큰 글자에서 잘릴 수 있다

**무엇이 불편한가** 빠른 선택은 `[30분, 1시간, 1일, 3일, 7일]` **5칸**이 한 줄에 들어간다.
산수(추정): 360dp - 좌우 패딩 32dp = 328dp → 칸당 **65.6dp**. 라벨은 본문 글꼴 14dp w700이라
`1시간`(3글자) 글리프만 약 42dp이고 여기에 세그먼트 좌우 패딩이 붙는다. 배율 1.3이면 글리프만 **약 55dp**가 되어
칸을 넘길 가능성이 크다. readability.md 5장이 배율 1.3에서 검증한 것은 **탭 라벨과 모집 카드 칩 두 가지**이고 이 5칸 줄은 아니다.
잘리면 "30분"과 "3일"이 구분되지 않아 기간을 잘못 고를 수 있고, 기간은 승패에 직접 영향을 준다.

**어디** `lib/features/battle/presentation/create_battle_screen.dart:199-216`, `lib/features/battle/domain/duration_rules.dart:12`

**어떻게 고치는가(택 1 — 결정 2)**
- **안 A**: 빠른 선택을 `[1일, 3일, 7일]` 3칸으로 줄인다. 30분·1시간은 이미 있는 `직접 입력`(분/시간/일 단위)으로 충분히 고를 수 있다.
- **안 B**: 세그먼트를 버리고 `Wrap` + 선택형 태그 5개로 바꿔 두 줄로 흐르게 한다(readability.md가 칩에 쓴 것과 같은 해법).

**비용** 작음~중간. **위험** 기간 값은 도메인 입력이다. 안 A는 "자주 쓰는 기간" 목록을 바꾸는 것이라 오너 확인이 필요하다
(서버 허용 범위 1분~7일은 건드리지 않는다).
**선행 작업** 어느 안이든 **배율 1.0/1.3 × 폭 360dp에서 잘림 여부를 위젯 테스트로 먼저 측정**할 것. 추정만으로 고치지 말 것.

---

### M16. 모집 상세 시트의 `참가` 버튼이 긴 스크롤 맨 끝에 있다

**무엇이 불편한가** 시트는 `isScrollControlled: true` + `SingleChildScrollView`이고, 내용은
(기준 변경 안내) + 제목 + 배지 + 유형 설명 + 최소 기준(최대 5개) + 우열 기준(최대 5개) + 만든 사람 카드 + 참가 버튼이다.
품질전 모집이면 시트가 화면을 가득 채우고 `이 기준으로 참가`는 스크롤 끝에 있어 **버튼이 보이지 않는 상태로 시작**한다.

**어디** `lib/features/battle/presentation/recruit_detail_sheet.dart:22-28`(시트 설정), `:124-183`(본문), `:174-179`(참가 버튼)

**어떻게 고치는가** 시트 본문을 `Column(children: [Expanded(스크롤 영역), 고정 하단 버튼])`으로 바꾼다
(`SafeArea`는 유지). 버튼이 늘 엄지 근처에 있고 기준은 그 위에서 스크롤된다.
**단서**: 지금 배치가 "기준을 끝까지 읽어야 참가 버튼에 닿는다"는 의도였을 수 있다(참가는 `criteria_version`을 확인했다는 뜻이다) → 결정 3.

**비용** 작음(한 위젯). **위험** 낮음.

---

### M17. "AI가 다시 보고 있어요"에서 결과를 다시 확인하는 방법을 말하지 않는다

**무엇이 불편한가** 문구가 `결과가 나오면 여기에 보여요.`인데 MVP에는 푸시가 없고 자동 갱신(polling)도 없다.
`battleDetailProvider`는 화면에 들어올 때 한 번 읽고 그대로다. 실제로 결과를 보려면 사용자가 당겨서 새로고침하거나
화면을 다시 열어야 하는데, 문구는 가만히 기다리면 바뀐다고 약속한다. 같은 문제가 `상대가 판정하면 결과가 나와요.`에도 있다.

**어디** `lib/features/battle/presentation/judgment_section.dart:118-129`, `lib/core/strings.dart:178,182`,
`lib/features/battle/domain/battle_providers.dart:67-85`(polling 없음), `battle_detail_screen.dart:75-76`(당겨서 새로고침은 있다)

**어떻게 고치는가** 두 문구 뒤에 한 줄을 붙인다: `화면을 아래로 당기면 다시 확인해요.`
**자동 폴링을 만들지 않는다** — 배터리·요청 비용이 들고, 알림은 별도 feature(`push-notification`) 영역이다.

**비용** 아주 작음(문자열 1개). **위험** 없음.

---

### M18. 프로필의 `계정` 섹션이 전적 전체 아래에 묻힌다

**무엇이 불편한가** 프로필은 (이름 → 점수 → **지난 대결 전체** → AI 동의 → 계정)이다.
지난 대결은 서버에서 **개수 제한 없이** 받아 와 `Column` + `for`로 **전부 한꺼번에** 그린다(lazy 아님).
하루 1대결이라 석 달이면 90장쯤 되고, 그 아래에 로그아웃·오픈소스 라이선스·계정 삭제가 있다.
스크롤이 길어질수록 계정 관리가 사실상 숨는다(계정 삭제는 Play 정책상 찾을 수 있어야 한다).
전부 즉시 빌드하므로 첫 그리기도 같이 무거워진다.

**어디** `lib/features/profile/presentation/profile_screen.dart:34-111`(섹션 순서), `:56-75`(Column+for), `lib/features/profile/data/profile_repository.dart:18-28`(limit 없음)

**어떻게 고치는가** 섹션 순서를 **(이름 → 점수·전적 집계 → AI 동의 → 계정 → 지난 대결)**로 바꾼다. 두 줄 이동이고 잃는 것이 없다.
지난 대결의 lazy 렌더링(Sliver 전환)이나 서버 페이징은 이번에 하지 않는다 — 하루 1대결 한도에서 당장 급하지 않고 비용이 다르다.
필요하면 `TODO_BACKLOG.md`에 "프로필 전적 목록 페이징" 한 줄.

**비용** 아주 작음. **위험** 없음.

---

### M19. 남은 시간이 갱신되지 않는다

**무엇이 불편한가** `남음` 표시는 빌드 시점에 한 번 계산된다. 화면을 열어 둔 채로는 `28분 남음`이 그대로 머문다.
기간이 30분·1시간까지 짧아졌으니 틀린 값이 꽤 오래 보일 수 있다. `0초 남음`에서 멈추는 경우도 생긴다.
(완화 요인: 상세 헤더는 절대 시각도 함께 보여 준다 — `사진 마감 10월 30일 14:00 · 28분 남음`. 그래서 치명적이지는 않다.)

**어디** `lib/features/battle/presentation/battle_detail_screen.dart:371-403`, `lib/features/battle/domain/battle_summary.dart:24-43`(`statusLineAt`도 `DateTime.now()` 1회)

**어떻게 고치는가** 상세 헤더만 주기적으로 다시 그린다. 남은 시간이 1시간 미만이면 1분 주기, 그 이상이면 다시 그리지 않는다
(`StatefulWidget` + `Timer.periodic`, `dispose`에서 취소). 목록 카드는 탭 재선택·당겨서 새로고침이 이미 다시 그리므로 손대지 않는다.

**비용** 작음. **위험** 낮음(타이머 누수 주의 — `dispose` 테스트).

---

## 배포 후

### M20. 카메라에서 돌아오는 중 앱이 죽으면 사진이 사라진다

**무엇** `ImagePicker().pickImage`만 쓰고 `retrieveLostData()`를 쓰지 않는다. Android가 카메라 앱 동작 중
메모리 압박으로 이 앱을 죽이면, 돌아왔을 때 찍은 사진이 사라지고 아무 안내도 없다. 사용자는 "찍었는데 없어졌다"로 겪는다.
**추정**이다 — 알려진 `image_picker` 동작이지만 이 앱에서 재현해 보지 않았고, S20(8GB)에서는 드물 것이다.
**어디** `lib/features/battle/data/evidence_camera.dart:23-34`
**고침** 대결 상세 진입·복귀 시 `retrieveLostData()`를 확인해 `_shot`을 복구한다. 패키지 추가 없음.
**비용** 중간(앱 생명주기 처리 + 복구 경로 테스트). **위험** 중간. 배포 전 시간으로는 비싸다.

### M21. 미제출 사진을 들고 화면을 떠나는 길이 조용하다

**무엇** 찍은 사진은 위젯 상태(`_shot`)에만 있다. 뒤로 가면 경고 없이 사라진다(10분 제약 때문에 다시 찍어야 한다).
**어디** `lib/features/battle/presentation/evidence_section.dart:39-58`
**고침** 미리보기 상태에 `아직 제출하지 않았어요.` 한 줄(싸다) — 또는 상세 화면에 `PopScope` 확인(비싸다, M7과 달리 상태가 자식 위젯에 있어 끌어올려야 한다).
**비용** 작음/중간. **위험** 낮음.

### M22. 할 일 목록에 당겨서 새로고침이 없다

**무엇** 다른 기기에서 바꾼 할 일이 반영되지 않고, 탭 재선택 invalidate 대상도 아니다(`main_shell.dart:26-43`).
**어디** `lib/features/todo/presentation/todo_list_screen.dart:76-134` — `ui-restructure/design.md:81`의 의도적 결정이었다.
**고침** `RefreshIndicator` + `todosProvider` invalidate.
**비용** 아주 작음. **위험** 없음. 급하지 않아 배포 후.

---

## 점검했고 문제 없다고 본 것 (중복 작업 방지)

- **터치 타깃**: 테마가 `FilledButton`/`OutlinedButton` 최소 64×48, `TextButton`·`IconButton`·`SegmentedButton` 최소 48×48을 보장한다
  (`app_theme.dart:150,176,298,375`) + `materialTapTargetSize: padded`(`:79`). 48dp 미만인 탭 가능 요소를 찾지 못했다.
  `BattleTypeBadge`·`PixelTag`는 탭 대상이 아니다. 모집 카드·전적 카드는 카드 전체가 탭 영역이다(`PixelFrame.onTap`).
- **빈 상태**: 목록 화면 네 곳 모두 성격별 빈 상태가 있고 다음 행동 버튼까지 붙어 있다(`status_message.dart`, `recruit_query.dart:86-105`). 좋다.
- **키보드 가림**: 입력이 있는 화면은 전부 `ListView`/`AlertDialog`라 `viewInsets`에 맞춰 줄어들고 포커스된 필드가 스크롤되어 올라온다.
  찾기 탭은 `keyboardDismissBehavior: onDrag`까지 넣어 두었다(`battle_recruits_screen.dart:353`). 문제를 찾지 못했다.
- **중복 요청 방지**: 참가(`recruit_detail_sheet.dart:80`), 판정 보내기(`judgment_section.dart:74`), 증거 제출(`evidence_section.dart:67`),
  기준 생성·올리기(`create_battle_screen.dart:102,156`), 동의(`ai_consent_screen.dart:55`), 계정 삭제·동의 철회는 모두 busy 플래그가 있다.
  빠진 곳만 M13·M12에 적었다.
- **카메라 탭 수**: `사진 찍기` → 시스템 카메라(촬영 + 확인) → 앱 복귀 미리보기 → `제출`. 앱 쪽 탭은 2회이고
  `다시 찍기`로 되돌아가는 길이 두 유형 모두 있다(`evidence_section.dart:158-162,252-256`). 구조는 적절하다. 남은 문제는 M5·M20·M21뿐.
- **되돌릴 수 없는 동작의 확인창**: 포기·계정 삭제·동의 철회(영향 건수까지 조회해 보여 준다)·품질전 제출·판정 보내기 모두 확인창이 있고
  문구가 결과를 정확히 말한다. 과한 확인창도 발견하지 못했다. 빠진 둘은 M9(할 일 삭제)·M12(모집 취소)다.
- **내비게이션 깊이**: 탭 → 상세 2단계가 최대이고(대결 만들기는 한 화면 안 3단계), 같은 곳으로 가는 길이 중복되지 않는다.
  끝난 대결은 프로필 전적 → 상세로 도달한다. 구조 자체는 바꿀 이유가 없다.

---

## 결정 필요

1. **찾기 탭 상단 조작 영역(M14)** — 지금의 "항상 보이는 고정 영역"을 유지할지, 안 A(기간대 접기) 또는 안 B(하단 시트)로 갈지.
   고정 유지는 recruit-browse 설계의 의도이고, 바꾸면 목록에 100~110dp를 돌려받는다. 설계 의도를 뒤집는 결정이라 오너 판단이 필요하다.
2. **기간 빠른 선택 목록(M15)** — `[30분, 1시간, 1일, 3일, 7일]` 5칸을 `[1일, 3일, 7일]` 3칸으로 줄여도 되는가
   (30분·1시간은 `직접 입력`으로 계속 선택 가능). 줄이지 않으려면 두 줄 태그로 바꾼다. 기간은 도메인 입력이라 디자이너가 정하지 않았다.
3. **모집 시트의 참가 버튼(M16)** — 하단 고정으로 올려도 되는가. 지금처럼 스크롤 끝에 둔 것이
   "기준을 끝까지 보게 한다"는 의도였다면 그대로 두고 스크롤 신호만 더한다.
4. **할 일 삭제(M9)** — 확인 다이얼로그로 갈지, 되돌리기 스낵바로 갈지. 되돌리기는 지운 행을 **새로 만드는 것**이어서
   목록 위치와 완료 상태가 달라진다(현재 스키마로는 같은 행을 되살릴 수 없다). 디자이너 추천은 확인 다이얼로그.
5. **문구 승인(M3·M6)** — 제목 입력 안내 한 줄과 첫 화면 3줄은 도메인 사실을 사용자 말로 옮기는 것이라 오너가 읽어야 한다.
   초안은 각 항목에 적어 두었다. 틀린 설명이 들어가면 분쟁을 만든다.

## 제안하지 않은 것 (요청대로 범위 밖)

온보딩 화면·투어, 푸시 알림(별도 feature), 자동 폴링, 테마/글꼴 설정 화면, 다국어, iOS, 다크 모드,
친구·랭킹·그룹 대결·결제, 전적 서버 페이징(백로그 한 줄로만), 새 패키지 도입, 상대 사진·판정 사유의 조기 공개(서버가 막는 영역).

---

## 문구 승인 (2026-11-02, 오너 확인 — 결정 5)

M3·M6의 문구를 오너가 읽고 승인했다("이대로 가"). M4는 기존 문구(`battleTypeSpeedTagline`/
`battleTypeQualityTagline`)를 옮겨 쓰는 것이라 승인 대상이 아니었다.

**M3 — 제목 입력 아래 한 줄 (확정)**
> 사진 한 장으로 증명할 수 있는 일이어야 해요. 예: 아침 7시 기상, 책상 정리 완료

**M6 — 첫 화면 빈 상태 세 줄 (확정)**
> 같은 할 일을 걸고 둘이 겨뤄요. 먼저 참가한 사람과 자동으로 매칭돼요.
> 증거는 앱에서 찍은 사진 한 장이에요.
> 서로 판정하고 의견이 갈리면 AI가 기준으로 확정해요.

**첫 줄은 초안에서 고쳤다.** 초안은 "먼저 **올린** 사람과 자동으로 매칭돼요"였는데 사실과 다르다 —
매칭되는 쪽은 모집을 올린 사람이 아니라 **먼저 참가하는 사람**이다(CLAUDE.md 도메인 규칙:
"유형/제목만 정해 올리면 누구든 먼저 참가하는 사람과 자동 매칭된다"). 구현은 **이 확정본**을 쓴다.
