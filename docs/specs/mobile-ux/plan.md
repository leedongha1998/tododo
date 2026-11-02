# mobile-ux 구현 계획 — M1만

작성: 2026-10-30, developer. 입력은 `docs/specs/mobile-ux/audit.md`의 **M1 절만**이다(오너가 M1만 승인).
M2~M22는 이번 작업 범위가 아니다 — 자동 폴링(M17)·프로필 섹션 순서(M18)·타이머 갱신(M19)을 포함해 손대지 않는다.
서버(마이그레이션·RPC·RLS·Edge Function)도 건드리지 않는다. 커밋도 하지 않는다(작업 트리에만 남긴다).

## 목표 한 줄

내 대결 카드가 ① 지금 내가 할 일이 있는지 ② 어느 시계가 몇 남았는지를 말하게 한다.
서버가 이미 기록한 값(`battle_participants.has_submitted`/`has_judged`, `battles.deadline_at`/`judge_deadline_at`)을
**문장으로 옮기기만** 한다. 승패·판정은 계산하지 않는다(CLAUDE.md "화면은 표시만").

## 선행 확인 — CLAUDE.md와의 어긋남 (구현을 막는 충돌은 아니다)

CLAUDE.md "도메인 규칙"은 `ai-judge` 기준으로 쓰여 있어 **"판정은 참가자가 아니라 AI 심판이 한다.
사용자끼리 서로의 증거를 승인/이의제기하는 절차는 없다"**고 적혀 있다. 그러나

- 2026-09-18 오너 확정 문서 `docs/specs/mutual-judge/spec.md`가 **판정 주체 조항을 상호 판정으로 대체**했고,
- 그 구현이 이미 서버·클라이언트에 들어가 동작 중이다(`judgment_rules.dart`, `judgment_section.dart`,
  `battleJudgment*` 문구 전부 오너 승인본, 커밋 `eb5ce4e` "mutual-judge 3단계 원격 적용 완료 기록").

즉 **CLAUDE.md 쪽이 낡았다**. M1은 새 판정 개념을 도입하지 않고 이미 돌아가는 상호 판정 단계를
목록 카드에 비칠 뿐이므로, 임의 판단으로 한쪽을 고르는 상황이 아니라고 보고 진행한다.
CLAUDE.md 도메인 규칙 문단 갱신은 이번 범위가 아니므로 **고치지 않고 보고에만 적는다**.

## 작업 순서

1. **plan.md 작성**(이 문서).
2. `lib/core/strings.dart` — 상태 줄 문구 3개 추가. 나머지는 기존 문구 재사용
   (`battleJudgmentAiTitle`, `battleListJudging`, `battleListOpponentSubmitted`, `battleListSettling`,
   `battleSubmitDeadlineLabel`, `battleJudgeDeadlineLabel`, `battleDeadlineLeft`).
3. `lib/features/battle/domain/remaining_time.dart`(신규) — `battle_detail_screen.dart`의 `_formatRemaining`을
   그대로 옮겨 `formatRemaining(Duration)`로 공개한다. 서식 규칙을 새로 만들지 않는다.
4. `lib/features/battle/domain/battle_summary.dart`
   - 필드 `me`(내 참가자 행, nullable) 추가.
   - `statusAt(now)` → `({String? line, bool needsMyAction})`. 우선순위:
     1. `judging`이면 `judgmentStageOf(...)` 결과로 문장을 고른다
        (`myTurn`→내 차례(강조) / `waitingOpponent`→상대 판정 대기 / `waitingAi`→AI 재판정 /
        `nothingToJudge`·`windowClosed`→기존 중립 문구).
        **마감 경과보다 앞에 둔다** — 속도전 판정 창은 대개 마감 뒤에 열리므로 뒤에 두면 영원히 가려진다.
     2. 마감 경과(판정 창도 아님) → 기존 `battleListSettling`.
     3. `active`이고 내 행이 있고 `hasSubmitted == false` → "아직 사진을 내지 않았어요"(강조).
     4. 상대가 제출했으면 기존 문구.
     5. 그 외 null.
   - `statusLineAt(now)`은 `statusAt(now).line`으로 유지(기존 호출·테스트 호환).
   - `deadlineLineAt(now)` 추가 — `judging`이면 판정 기한, 그 외에는 사진 마감. 지났거나 없으면 null.
5. `lib/features/battle/domain/battle_providers.dart` — `myBattlesProvider`에서 이미 받아 둔 참가자 행으로
   `me: participantOf(b.id, myId)` 한 줄. **추가 네트워크 없음.**
6. `lib/features/battle/presentation/battle_summary_list.dart` — `now`를 한 번만 구해 상태 줄·남은 시간 줄에
   같이 쓴다. 강조는 색·굵기로만 가른다(아래 "UI 결정").
7. `lib/features/battle/presentation/battle_detail_screen.dart` — 지역 `_formatRemaining` 삭제하고 공용 함수 사용.
8. 테스트
   - `test/features/battle/domain/battle_summary_test.dart` — 기존 `judging` 기대값을 단계별 새 기대값으로 **고친다**(지우지 않는다).
     새 분기(판정 단계 4종, 내 미제출, 우선순위, 남은 시간 줄) 유닛 테스트 추가.
   - `test/features/battle/domain/remaining_time_test.dart`(신규) — 단위 경계.
   - `test/features/battle/my_battles_sections_test.dart` — `DateTime.now()` 기준 상대 픽스처로
     카드가 "내 차례"와 남은 시간을 그리는지 위젯 테스트 1건 추가(메모 `flutter-widget-test-gotchas` 3번:
     인자 없는 now 경로는 위젯 테스트가 덮는다).
9. `flutter analyze`(이슈 0) + `flutter test`(기준선 362개 이상) 확인.

## UI 결정 (audit.md가 developer 재량으로 남긴 것)

- **강조 수단**: `PixelTag`를 새로 붙이지 않고, 이미 있는 수단만 쓴다. 지금은 모든 상태 줄이
  `colorScheme.primary` + `w600`으로 똑같이 강조돼 있어 "할 일"과 "그냥 소식"이 구분되지 않는다.
  → **할 일이 있는 줄만** `primary` + `w600`을 유지하고, 소식 줄(상대 제출/판정 대기/정리 중)은
  `onSurfaceVariant`(= `RetroPalette.inkMuted`, 테마에 이미 있는 색) 기본 굵기로 낮춘다.
  카드 수 자체가 적고(하루 1대결) 칩 하나를 더하면 좁은 폭에서 줄바꿈 위험이 커지므로 태그를 늘리지 않는다.
- **줄 수**: 상태 줄은 **한 줄만** 고른다(내 미제출 + 상대 제출을 둘 다 띄우지 않는다). audit.md의
  우선순위를 그대로 따른다 — 내가 할 일이 상대 소식보다 먼저다.
- **어느 시계를 보여 주는가**: audit.md 4단계는 `deadlineAt`만 적었으나, `judging`에서는 사진 마감이 이미
  지났거나 의미가 없고 실제로 흐르는 시계는 판정 기한이다. 그래서 `judging`이면 `judgeDeadlineAt`을 쓰고
  라벨(`사진 마감`/`판정 마감`)을 함께 붙인다. 라벨 없이 "1일 남음"만 두면 무엇의 1일인지 알 수 없다.
  문구는 전부 기존 상수 재사용이고 상세 헤더와 같은 ` · ` 형식이다. → audit.md와 다른 유일한 지점.

## 하지 않는 것

- 남은 시간 자동 갱신(M19), 자동 폴링(M17), 상태 줄의 상대 제출 "합격/불합격" 노출(서버가 가린다),
  새 패키지, 테마·팔레트·글꼴 변경, 커밋.

## 순서 변경 기록

(구현 중 순서를 바꾸면 여기에 이유를 남긴다.)

- 2026-10-30: 8단계에서 `remaining_time_test.dart`를 새로 만드는 대신 `battle_summary_test.dart`에
  `formatRemaining` 단위 경계 테스트를 함께 두는 쪽을 검토했으나, 공용 함수는 두 화면이 쓰므로
  소속을 분명히 하려고 계획대로 별도 파일로 두었다(변경 없음).
- 2026-10-30: 4단계에서 `statusLineAt`에 "강조 여부" 불린을 따로 더하는 대신, 레코드를 돌려주는
  `noticeAt(now)`를 두고 `statusLineAt`을 그 위의 얇은 래퍼로 바꿨다. 이유: 문구와 강조를 두 메서드로
  나누면 각자 `DateTime.now()`를 읽어 경계에서 어긋나고, 강조 판단이 문구 비교로 흘러 중복된다.
  기존 호출부·테스트가 쓰는 `statusLineAt(now)` 서명은 그대로 남겼다.
- 2026-10-30: 위젯 테스트 하나에서 두 픽스처를 연달아 pump했더니
  `A Timer is still pending even after the widget tree was disposed`로 죽었다(한 테스트 안에서
  위젯 트리를 두 번 세우면 첫 트리의 타이머가 남는다). 그래서 "상대 제출 소식" 단정을
  **별도 testWidgets로 분리**했다. 검증 내용은 그대로다.
- 2026-10-30: 편집 훅(`dart format --set-exit-if-changed`)이 손댄 파일마다 실패를 보고했는데,
  **이 저장소는 HEAD 상태에서도 기본 폭(80칸) 기준 `dart format`을 통과하지 않는다**(`strings.dart`,
  `battle_providers.dart` 등을 stash 후 확인). 기존 파일을 통째로 재포맷하면 M1과 무관한 거대한 diff가
  생기므로 **재포맷하지 않았다.** 새로 만든 파일(`remaining_time.dart`, 두 테스트 파일)과 새로 쓴
  코드 줄만 80칸 기준을 지켜 포맷을 맞췄고, 판정 기준은 `dart analyze`(이슈 0)로 삼았다.

---

# mobile-ux 2차 구현 계획 — recruit-list-scan (P1·P2·S1·S2·S3·S4-1·S4-2)

작성: 2026-11-02, developer. 입력은 `docs/specs/mobile-ux/recruit-list-scan.md` 전체이고,
특히 그 문서 끝의 **"## 오너 결정 (2026-11-02)"과 "### 이번 범위 (전부)"**가 유일한 결정 근거다.
위의 1차(M1) 계획은 이미 끝난 작업이므로 건드리지 않는다.

## 범위 (그대로 옮김)

- **P1** FAB 아이콘 전용(56x56 + tooltip) + 스크롤 내릴 때 숨김
- **P2** 조작 영역↔목록 경계선 2dp → 4dp, 조작 영역 면 `sunken`
- **S1** 모집 카드 사이 간격 8 → 16dp
- **S2** 카드 왼쪽 유형 색 띠 8dp(속도전 `amber` / 품질전 `mint`)
- **S3** 카드 안 2dp ink 상자 3 → 2 (유형 배지 테두리 제거 = **전 화면 공용**, 기간 칩에 `clock` leading,
  `battleStatusTagStyle('draw')` → `neutralPixelTagStyle`)
- **S4-1** 제목 `maxLines: 2` + 말줄임 / **S4-2** 기준 미리보기 `inkMuted`

## 하지 않는 것

- **M14/S5**(상단 조작 영역 축소·하단 시트) — 배포 후. `TODO_BACKLOG.md`에 한 줄만.
- **S4-3**(미리보기 1줄) — 2줄 유지가 오너 결정 1.
- 새 색·새 패키지·새 에셋, 글꼴 크기·행간·픽셀 경계 변경, 서버(마이그레이션·RPC·RLS·Edge Function),
  팔레트 테스트 수정, 범위 밖 화면의 "겸사겸사" 수정, 커밋(`git add`/`commit`/`push`).

## 선행 확인 — 문서 간 어긋남 (구현을 막는 충돌은 아니다)

`docs/specs/retro-theme/design.md:279`는 `BattleTypeBadge`를 **"surface 면 + 2dp ink 테두리"**로 정했다.
S3-1은 그 테두리를 없앤다. 즉 **retro-theme design.md와 recruit-list-scan.md가 어긋난다.**
다만 이는 CLAUDE.md 도메인 규칙이나 dev-standards와의 충돌이 아니고, **더 나중에 오너가 직접 승인한 결정**
(recruit-list-scan.md 오너 결정 2: "전 화면에 적용한다. 화면별 변형은 만들지 않는다")이 앞선 설계 문서의
한 줄을 덮는 경우다. 그래서 멈추지 않고 진행하되, retro-theme/design.md는 이번 범위가 아니므로
**고치지 않고 보고에만 적는다**(1차 계획에서 CLAUDE.md 판정 조항을 다룬 것과 같은 방식).

같은 성격의 작은 어긋남 둘:
- `retro-theme/design.md:344`는 모집 카드의 기준 미리보기를 "bodySmall inkMuted, **한 줄** 말줄임"으로 정했다.
  줄 수는 뒤에 나온 `recruit-browse/design.md:173`(2줄)과 오너 결정 1이 2줄로 확정했고, 색만 이 문서가 되돌린다.
- `retro-theme/design.md:158`의 "목록 항목 사이 8"은 전역 기본값이다. S1은 **이 카드 한 곳**만 16으로 올린다
  (recruit-list-scan.md가 명시). 내 대결 카드·전적 카드는 손대지 않는다.

## 작업 순서

1. **plan.md 작성**(이 절).
2. `lib/features/battle/presentation/battle_chips.dart`
   - `Color battleTypeAccent(String type)` 공개 함수 추가 — 앰버/민트 매핑을 **한 곳**에만 둔다
     (배지와 색 띠가 같이 쓴다. recruit-list-scan.md S2가 "두 번 적지 말 것"으로 지정).
   - `BattleTypeBadge`의 `PixelBorder()` → `PixelBorder(side: BorderSide.none)`. 면색(`surface`)은 유지한다
     — 배지가 `surface`가 아닌 면 위에 놓이는 화면이 생겨도 칩 모양을 잃지 않는다.
3. `lib/features/battle/presentation/battle_recruits_screen.dart`
   - P1-a: `FloatingActionButton.extended` → `FloatingActionButton`(아이콘 전용 + `tooltip: AppStrings.battleCreate`).
   - P1-b: 목록을 `NotificationListener<ScrollNotification>`으로 감싸고 `UserScrollNotification.direction`이
     `reverse`면 FAB을 `null`로, `forward`/`idle`이면 되돌린다. **애니메이션 없음**(design.md 1.4 움직임 규칙).
     `ScrollController` 대신 알림을 쓰는 이유는 순서 변경 기록에 적는다.
   - P2: 경계선 `height: 2` → `4`, `_buildControls`의 `Padding`을 `ColoredBox(color: RetroPalette.sunken)`로 감싼다.
   - S1: 카드 바깥 `EdgeInsets.only(bottom: 8)` → `16`.
   - S2: `_OpenRecruitCard`를 `PixelFrame.raised(padding: EdgeInsets.zero)` + `IntrinsicHeight(Row(stretch))`로 바꾸고
     왼쪽에 폭 8dp `ColoredBox(battleTypeAccent(type))`, 오른쪽은 `Expanded(Padding(all: 12, 기존 Column))`.
     색 띠는 **보조 신호**라는 점(아이콘+글자 배지가 같은 뜻을 말한다)을 주석에 적는다.
   - S3-2·3: 기간 칩에 `leading: PixelIcon(PixelIcons.clock, size: 12)`, `style: neutralPixelTagStyle`.
   - S4-1: 제목 `maxLines: 2, overflow: ellipsis`. S4-2: 미리보기 `color: RetroPalette.inkMuted`.
4. `TODO_BACKLOG.md` — M14 한 줄 추가.
5. 테스트(지우지 않고 고치거나 더한다)
   - `test/widget_test.dart:390`, `test/features/battle/recruit_browse_test.dart:471` —
     `find.widgetWithText(FloatingActionButton, …)`이 라벨을 잃어 깨진다 → `find.byTooltip(...)`/`byType`으로 **고친다**.
   - `test/features/battle/recruit_browse_test.dart`에 추가: ① 아이콘 전용 FAB + tooltip,
     ② 목록을 내리면 FAB이 사라지고 위로 올리면 돌아온다, ③ 속도전/품질전 카드에 유형 색 띠가 있다,
     ④ 기간 칩이 `neutralPixelTagStyle`이고 시계 아이콘을 단다.
   - **치수(간격 16dp·FAB 폭)를 재는 테스트는 쓰지 않는다** — 메모 `flutter-widget-test-gotchas` 6번
     (배율만 올려도 통과하는 공허한 레이아웃 테스트). 대신 "무엇이 보이는가/사라지는가"를 단정한다.
     긴 제목·배율 1.3에서 카드가 넘치지 않는지는 `takeException()`으로 본다(Row/Column은 넘치면 예외).
6. `flutter analyze`(이슈 0) + `flutter test`(기준선 384개) 확인.

## 순서 변경 기록

- 2026-11-02: P1-b를 recruit-list-scan.md가 적은 `ScrollController` + `position.userScrollDirection` 대신
  `NotificationListener<UserScrollNotification>`으로 구현했다. 이유: `ScrollController`의 리스너는
  **오프셋이 변할 때만** 불리므로 "스크롤이 멈췄다(`idle`)"를 놓친다 — 오너 결정 3의 "멈추거나 위로 올리면
  즉시 되돌린다"를 지킬 수 없다. `UserScrollNotification`은 방향이 바뀌는 순간(`idle` 포함) 그대로 온다.
  읽는 신호(`ScrollDirection`)와 동작은 문서와 같고, `RefreshIndicator`가 보내는 알림은 `false`를 돌려
  그대로 통과시킨다(당겨서 새로고침 동작 유지).
- 2026-11-02: S2의 `Row(crossAxisAlignment: stretch)`를 **`IntrinsicHeight`로 감쌌다.**
  recruit-list-scan.md는 "stretch를 쓰면 `IntrinsicHeight`가 필요 없다"고 적었지만, 이 카드는
  `ListView` 항목이라 **세로 제약이 무한**이고 `RenderFlex`는 stretch에서 비-flex 자식에게
  `BoxConstraints.tightFor(height: constraints.maxHeight)`를 준다(`flex.dart` `_constraintsForNonFlexChild`).
  즉 띠가 무한 높이를 받아 레이아웃이 터진다. `IntrinsicHeight`가 높이를 먼저 확정하면
  flex 자식 폭 계산도 정상(`_getIntrinsicSize`의 INTRINSIC CROSS SIZE가 실제 남는 폭으로 재측정)이다.
- 2026-11-02: 5단계의 "배율 1.3 칩 한 줄 넘침 테스트"를 **썼다가 버렸다.** 배율만 3.0으로 올린
  복사본도 통과해(두 칩이 x≈325에서 끝난다, 화면 360dp) 아무것도 보장하지 못하는 테스트였다.
  대신 그 사실을 테스트 파일 끝 주석으로 남겼다. 나머지 새 테스트 둘(색 띠·FAB 숨김)은
  기대값을 일부러 틀리게 바꿨을 때 실제로 깨지는지 확인했다(stretch→center, hide 상수화).
- 2026-11-02: P1-b에 `floatingActionButtonAnimator: noAnimation`이 추가로 필요했다(계획에 없던 줄).
  Scaffold 기본값이 FAB을 돌리며 키우는 200ms 연출을 넣어 design.md 1.4 "움직임"과 어긋나기 때문이다.

---

# mobile-ux 3차 구현 계획 — M2 · M5 · M7 · M8

작성: 2026-11-02, developer. 입력은 `docs/specs/mobile-ux/audit.md`의 **`### M2.` `### M5.` `### M7.` `### M8.`
네 절만**이다(오너가 이 넷만 승인). 위의 1차(M1)·2차(recruit-list-scan) 계획은 끝난 작업이므로 건드리지 않는다.

## 범위 (네 항목)

- **M2** 대결 상세의 `error` 갈래에 `다시 시도`(= `ref.invalidate(battleDetailProvider(battleId))`),
  `loading` 갈래에 문구 있는 전면 로더.
- **M5** 증거 미리보기(속도전·품질전 **두 자리**)에 "찍은 지 10분 안에 제출해야 해요." 한 줄.
  **카운트다운 타이머는 만들지 않는다.**
- **M7** 기준 생성 화면·모집 기준 수정 화면을 `PopScope`(SDK)로 감싸고, **생성 중이거나 결과를 들고 있을 때만**
  막고 확인 다이얼로그를 띄운다. **입력 단계는 반드시 그냥 나가진다.**
- **M8** `대결 찾기` 상단 배너 조건을 `hasPending || dailyBattleUsed`로 넓히고 문구를 분기.
  `dailyBattleUsed`는 **이미 받아 둔 `get_my_limits` 응답에 들어 있다**(`MyLimits.dailyBattleUsed`) — 추가 조회 없음.

## 하지 않는 것

- M1·M3·M4·M6·M9~M22 전부. 특히 **M10(전면 로더 전 화면 교체)은 범위 밖** — M2가 가리키는
  대결 상세의 두 갈래만 바꾼다(`auth_gate`·`profile_screen`·`todo_list_screen`의 `PixelLoader.medium`은 그대로).
- 서버(마이그레이션·RPC·RLS·Edge Function). **한도 판단은 서버가 한다** — 화면은 서버가 내준
  `dailyBattleUsed`를 미리 보여 줄 뿐이고 차단은 서버 몫이다(CLAUDE.md "클라이언트에서 승패·한도 계산 금지").
- 새 패키지, 테마·팔레트·글꼴, 2차에서 끝난 목록 개편(`_OpenRecruitCard`·FAB·조작 영역), 커밋.

## 선행 확인 — 문서·규칙 충돌

**구현을 막는 충돌은 없다.** CLAUDE.md·dev-standards와 audit.md의 네 절이 어긋나는 지점을 찾지 못했다.
- 네 항목 모두 API 계약을 바꾸지 않고 서버가 이미 내준 값을 표시만 더한다(audit.md "전제와 한계"와 일치).
- 1차 계획에 적은 "CLAUDE.md 판정 주체 조항이 낡았다(상호 판정이 오너 확정본)"는 그대로 유효하지만,
  이번 네 항목은 판정 로직을 건드리지 않아 영향이 없다. CLAUDE.md는 이번에도 고치지 않는다.

## 작업 순서

1. **plan.md 작성**(이 절).
2. `lib/core/strings.dart` — 문구 추가 5개.
   - `leave` / `stay`(M7 다이얼로그 버튼, 일반 동작이라 `cancel`·`retry` 옆에 둔다)
   - `battleCriteriaLeaveTitle` / `battleCriteriaLeaveBody`(M7)
   - `battleEvidenceCaptureWindow`(M5)
   - `battleDailyLimitBanner`(M8)
3. **M2** `lib/features/battle/presentation/battle_detail_screen.dart`
   - `loading` → `StatusMessage.loading(message: AppStrings.loading, fill: true)`
   - `error` → `StatusMessage.error(..., fill: true, action: TextButton(다시 시도))`.
     `debugPrint` 로그는 그대로 남긴다(에러를 삼키지 않는다).
   - `RefreshIndicator` 위치는 **바꾸지 않는다** — audit.md M2의 고침 항목이 두 갈래뿐이고,
     `data` 갈래 밖으로 끌어내는 것은 적혀 있지 않다(그 자리에 당겨서 새로고침이 필요한 이유도
     "복구 수단이 없다"였고 그건 `다시 시도` 버튼이 해결한다).
4. **M5** `lib/features/battle/presentation/evidence_section.dart` — 속도전 미리보기(`_speedBody`)와
   품질전 미리보기(`_qualityBody`) 두 자리의 제출 버튼 바로 아래에 한 줄. 타이머·생명주기 처리 없음.
5. **M7-a** `create_battle_screen.dart` — `Scaffold`를 `PopScope`로 감싼다.
   - `canPop`: `_stage == _Stage.input`이면 **항상 true**. 그 외에는 `!(_busy || _result != null)`.
     (입력 단계를 먼저 가르는 이유: `제목 고치기`는 `_stage`만 input으로 되돌리고 `_result`는 들고 있어서
     `_result != null`만 보면 입력 화면에서 갇힌다.)
   - `onPopInvokedWithResult`에서 확인 다이얼로그 → `나가기`면 `Navigator.pop()`.
6. **M7-b** `edit_recruit_criteria_screen.dart` — 같은 모양. `canPop`은 `!(_busy || _checked != null)`.
   이 화면은 단계가 없고 `_checked`(재검사 통과 증서)가 "결과를 들고 있다"에 해당한다.
   **고치는 중(`_changed`)만으로는 막지 않는다** — 횟수를 쓰지 않았고, 입력만 있는 상태에서 확인창을 띄우면
   audit.md M7이 금지한 쪽("아무것도 잃지 않는데 확인창")이 된다.
7. **M8** `battle_recruits_screen.dart` — `myLimitsProvider`에서 `dailyBattleUsed`도 읽어 `_buildFeed`로 넘긴다.
   배너 조건 `hasPending || dailyBattleUsed`, 문구 분기. 카드 탭·시트 열기는 그대로 둔다.
8. 테스트(지우지 않고 고치거나 더한다)
   - `test/features/battle/battle_detail_load_test.dart`(신규) — M2 두 갈래.
     실패 provider를 띄우므로 `ProviderContainer(retry: ...null)`로 재시도를 끈다(메모 4번).
   - `test/features/battle/battle_evidence_test.dart` — M5 두 자리 단언 추가.
   - `test/features/battle/create_battle_test.dart` — **M7 필수 고정 2건**:
     ① 입력 단계에서는 시스템 뒤로가기가 그냥 나간다, ② 결과를 들고 있으면 확인창이 뜨고
     `계속하기`면 남고 `나가기`면 나간다. `제목 고치기`로 입력에 돌아온 경우도 ①에 포함한다.
   - `test/features/battle/edit_recruit_criteria_test.dart`(신규) — 같은 두 가지를 이 화면에서도 고정.
   - `test/features/battle/recruit_browse_test.dart` — M8 배너 세 경우(한도만/모집만/둘 다).
   - **치수를 재는 레이아웃 테스트는 쓰지 않는다**(메모 `flutter-widget-test-gotchas` 6번).
9. `flutter analyze`(이슈 0) + `flutter test`(기준선 **390개** 이상) 확인.

## 재량으로 정한 것 (audit.md가 developer에게 넘긴 것)

- **M8 참가 버튼**: 모집 상세 시트의 `이 기준으로 참가`는 **비활성화하지 않는다.**
  이유 ① 차단은 서버가 하고(CLAUDE.md), 시트에 한도 분기를 또 두면 같은 판단이 두 곳에 생긴다.
  ② 거부 문구(`battleErrorDailyLimit`)가 이미 "오늘은 이미 대결을 했어요"로 정확히 말한다.
  ③ 상단 배너가 **시트를 열기 전에** 이미 알려 주므로 사전 안내 목적은 달성된다.
  ④ `myLimitsProvider`는 캐시된 값이라 비활성화하면 "서버는 허용하는데 버튼이 죽은" 오차가 생길 수 있다.
- **M8 두 조건이 동시에 참일 때**: 배너를 둘로 나누지 않고 한 장 안에 두 줄로 적는다.
  한도 줄(이 화면에서 하려는 일 = 참가를 막는 것)을 먼저, 모집 줄과 `내 모집 보기`를 뒤에 둔다.
- **M5 품질전 자리**: audit.md는 "기존 `battleEvidenceQualityOnce` 줄 옆에 붙인다"고 적었는데,
  그 줄은 미리보기가 아니라 **촬영 전** 단계에 있다. 10분 제약은 찍은 **뒤에** 뜻이 생기므로
  품질전도 속도전과 같이 **미리보기의 제출 버튼 아래**에 둔다(= 지시받은 "두 자리").
- **M7 다이얼로그 제목**: audit.md는 본문과 버튼만 줬다. 이 저장소의 확인창은 모두 제목+본문이라
  제목 한 줄(`기준 만들기를 그만둘까요?`)을 더했다.

## 순서 변경 기록

(구현 중 순서를 바꾸면 여기에 이유를 남긴다.)

- 2026-11-02: 5·6단계에서 두 화면에 `PopScope`를 각각 쓰는 대신, 확인창까지 포함한
  **`CriteriaLeaveGuard`**를 `criteria_views.dart`(두 화면이 이미 함께 쓰는 파일)에 하나 두고 둘이 감쌌다.
  이유: 다이얼로그 문구·버튼·`onPopInvokedWithResult` 처리가 완전히 같아서 두 번 적으면
  한쪽만 고쳐지는 길이 생긴다. **무엇을 막을지는 위젯이 판단하지 않고** 화면이 넘겨주는
  `blocked` 한 개만 따르게 해서, "입력 단계는 항상 나가진다" 판단이 화면에 남아 있게 했다.
- 2026-11-02: M7 테스트는 `Navigator.pop`이 아니라
  **`tester.state<NavigatorState>(...).maybePop()`**으로 나가 본다. `Navigator.pop`은 `PopScope`를
  거치지 않아(그래서 제출 성공 뒤 `pop`이 막히지 않는다) 그걸로 테스트하면 아무것도 검증하지 못한다.
  두 테스트 모두 **기대값을 일부러 틀리게 바꿨을 때 깨지는지 확인했다**:
  `_blocksLeaving`을 `_result != null || _busy`로(단계 검사 제거) 바꾸면 "제목 고치기로 돌아온 입력 단계"가 깨지고,
  `false`로(항상 통과) 바꾸면 "결과를 들고 있으면 확인창" 쪽이 깨진다.
- 2026-11-02: 8단계에 적지 않았던 단언 하나를 더했다 — `한도를 안 썼고 모집도 없으면 배너가 없다`.
  배너 조건을 넓히는 변경이라 "안 떠야 할 때 뜨지 않는다"를 같이 묶어 두지 않으면
  조건을 잘못 넓혀도(`||`를 빼먹어도) 테스트가 통과한다.
- 2026-11-02: 레이아웃·치수 테스트는 한 건도 쓰지 않았으므로 배율 3.0 복사본 검증은 해당 사항이 없다.
  새로 쓴 10건은 전부 "무엇이 보이는가 / 어디로 갔는가 / 몇 번 불렸는가"만 단언한다.

## 리뷰 반영 (2026-11-02, reviewer W1·W2·W3 + 덤 3건)

리뷰어가 임시 probe 테스트로 실제 눌러 보고 찾은 3건을 고친다. 막아야 할 문제는 없었고
사용자가 갇히는 경로도 없었다 — 셋 다 "잃는데 묻지 않는다 / 묻는 말이 화면과 다르다" 쪽이다.

### W1 — 재검사를 쓴 뒤 한 글자 고치면 가드가 풀린다 (edit_recruit_criteria_screen)

**내가 6단계에 적은 근거가 틀렸다.** 나는 `blocked: _busy || _checked != null`을 두고
"고치기만 한 상태(`_changed`)로는 막지 않는다 — 아직 쓴 것이 없다"고 적었는데, 그 말은
**첫 재검사 전에만** 참이다. 재검사로 1회를 쓴 뒤 기준을 한 글자 더 고치면
`CriteriaEditor.onChanged`가 `_checked = null`로 증서를 버리므로 `blocked`가 false로 돌아가고,
뒤로가기 한 번에 확인창 없이 나가면서 **고친 기준과 쓴 1회가 같이 사라진다.**
`_checked`(증서 보유)는 "잃을 것이 있는가"의 대리 지표로 부족하다.

→ 기준을 **"이 화면에서 호출을 썼는가"**로 바꾼다. `_usedCheck` 플래그를 `_recheck` 시작 시
true로 세우고(성공·실패 모두 호출은 떠났다) `blocked: _busy || _usedCheck`로 쓴다.
한 번 true가 되면 화면이 살아 있는 동안 되돌리지 않는다 — 쓴 호출은 되돌아오지 않으니까.
create 화면에는 이 구멍이 없다(`_result`는 편집해도 유지된다).

### W2 — 확인창 제목이 수정 화면에서도 "기준 만들기를 그만둘까요?"

공통 위젯(`CriteriaLeaveGuard`)으로 묶은 것은 유지하고 **제목만 화면이 넘긴다**
(`CriteriaLeaveGuard({required this.title, ...})`).
`battleCriteriaLeaveEditTitle = '기준 수정을 그만둘까요?'`를 더하고 수정 화면이 그것을 넘긴다.
본문(`battleCriteriaLeaveBody`)은 양쪽 모두 맞으므로 그대로 둔다.

### W3 — create 화면: 재검사 실패 화면에서 뒤로가기가 막히고 다이얼로그가 화면과 반대로 말한다

`_recheck`의 catch(`_handleFailure`)는 `_error`만 세우고 `_result`는 들고 있으므로
`_blocksLeaving`이 참이 된다. 그런데 그 화면은 `AI가 응답하지 않았어요 …(횟수는 차감되지 않았어요)`를
보여 주고, 뒤로가기 확인창은 `사용한 횟수는 돌아오지 않아요`라고 **정반대로** 말한다.
게다가 지키려고 막은 `_result`로 되돌아갈 길이 없다(오류 화면의 `다시 시도`는 `_recheck`가 아니라
`_generate`라 `_result`를 지우고 새 호출을 쓴다).

→ `_blocksLeaving`에 `_error == null`을 더해 **오류 상태에서는 막지 않는다.**
`_error`는 `_generate`/`_recheck` 시작 시 null로 초기화되므로 정상 흐름에 부작용이 없다.
오류 화면의 `다시 시도`를 `_recheck`로 바꾸는 쪽은 범위 밖으로 보고 하지 않는다(리뷰 지시도 아니다).

### 덤 3건

- `strings.dart`의 `battleEvidenceCaptureWindow`를 품질전 전용 주석 블록에서 **공용 증거 문구** 쪽으로 옮긴다
  (속도전·품질전 두 자리가 함께 쓴다).
- `battle_evidence_test.dart` 속도전 쪽에 "찍기 전에는 10분 줄이 뜨지 않는다" 음성 단언 한 줄.
- `recruit_browse_test.dart` 참가 버튼 테스트에 `onPressed != null` 단언 —
  "한도여도 참가 버튼을 죽이지 않는다"(3차 재량 결정 M8)를 문구가 아니라 동작으로 고정한다.

### 작업 순서

1. 이 절 작성.
2. `lib/core/strings.dart` — `battleCriteriaLeaveEditTitle` 추가, `battleEvidenceCaptureWindow` 자리 이동.
3. `criteria_views.dart` — `CriteriaLeaveGuard.title` 필수 인자화(문서 주석도 갱신).
4. `create_battle_screen.dart` — `title:` 전달 + `_blocksLeaving`에 `_error == null`.
5. `edit_recruit_criteria_screen.dart` — `_usedCheck` 도입 + `title:` 전달.
6. `TODO_BACKLOG.md` — 리뷰어 N5(`RefreshIndicator.onRefresh`의 예외 처리) 한 줄. **고치지 않는다** —
   이번 변경이 만든 문제가 아니다.
7. 회귀 테스트(지우지 않고 더한다)
   - W1: `edit_recruit_criteria_test.dart` — 재검사 뒤 기준을 또 고쳐도 확인창이 뜬다.
   - W2: 같은 파일 — 확인창 제목이 `기준 수정을 그만둘까요?`이고 만들기 제목이 아니다.
   - W3: `create_battle_test.dart` — 재검사 실패 화면에서는 확인창 없이 그냥 나간다.
     `_Stage.generating`의 전면 로더는 `pumpAndSettle`이 타임아웃하므로 고정 횟수 `pump`를 쓴다(리뷰어 N7).
   - 덤 둘.
   - W1·W3은 **되돌리면 깨지는지** 확인한다.
8. `flutter analyze`(이슈 0) + `flutter test`(400개 + 새 회귀 테스트) 확인. 커밋하지 않는다.

### 순서 변경 기록 (리뷰 반영)

- 2026-11-02: 7단계에 적지 않은 수정 둘이 필요했다. ① 기존 테스트
  `재검사를 통과한 기준을 들고 있으면…`·`고치는 중(재검사 전)에는…`의 제목 단언을
  `battleCriteriaLeaveTitle` → `battleCriteriaLeaveEditTitle`로 **고쳤다**(W2가 제목을 바꿨으니
  같이 따라가야 한다. 지우지 않았다). ② `create_battle_test.dart`의 가짜 레포지토리에 `checkError`
  필드를 더했다 — W3은 `generate`는 성공하고 `check`만 실패하는 상태가 필요한데 기존 가짜는
  `generateError`만 가지고 있었다.
- 2026-11-02: W1·W3 회귀 테스트는 **되돌리면 깨지는지 확인했다.**
  `blocked: _busy || _usedCheck` → `_busy || _checked != null`로 되돌리면 W1 테스트가,
  `_blocksLeaving`에서 `_error == null`을 빼면 W3 테스트가 각각 실패한다(확인 후 원복).
  W2는 "수정 제목이 뜨고 만들기 제목이 뜨지 않는다"를 한 테스트에서 양쪽으로 단정한다.
