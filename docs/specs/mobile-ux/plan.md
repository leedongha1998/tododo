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
