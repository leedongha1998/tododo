# mutual-judge 설계

## 참고
- spec.md: `docs/specs/mutual-judge/spec.md` (오너 승인 2026-09-18, 결정 사항 D1~D9 확정, 미결 없음). **이 설계의 유일한 요구사항이다.**
- 대체 대상: `docs/specs/ai-judge/design.md`의 **판정 시점·판정 주체·마감 기간**에 해당하는 부분. 그 문서의 기준 생성, 증거 규칙, 동의, 점수·outcome, 한도 원장, 모집 매칭, 포기, 탈퇴, 서버 전용 함수 권한 구조, pg_net·Vault 배선은 그대로 유효하며 이 설계가 재사용한다.
- 선례로 읽은 것: `docs/specs/ai-judge/design.md`(상태 전이표, 순수 함수 분리, service 전용 권한, cron, Edge 계약, 단계 분할), `docs/specs/ai-judge/plan.md` 진행 기록(실제 구현 결과와 함정 — 특히 6단계의 "`create or replace`로 인자 시그니처를 유지해야 배포된 Edge Function이 옛 오버로드를 부르지 않는다"), `docs/specs/push-notification/{spec,design}.md`(알림 사건 정의와 cron 트랜잭션 분리 선례).
- 근거로 읽은 현재 구현: `supabase/migrations/20260910140000_battle_deadline`(`duration_hours` 제약·cron 5분), `20260915120100_ai_judge_schema`, `20260915120200_ai_judge_outcome_rules`, `20260915120300_ai_judge_transitions`, `20260916120000_ai_consent`, `20260916130000_ai_criteria`(`create_battle`), `20260917120000_join_and_player_cards`(`join_battle`), `20260918120000_speed_submissions`(`accept_submission`·`record_speed_verdict`·Storage 정책·cron 1분), `20260919120000_quality_judgments`(판정 잡·재시도·`dispatch`), `20260920120000_push_tokens_and_outbox`(현재 `delete_account` 정의), `supabase/functions/{submit-evidence,judge-quality,battle-criteria,_shared/*}`, `supabase/tests/*.sql`, `lib/features/battle/**`, `lib/core/strings.dart`.
- 전제: ai-judge 1~7단계는 **원격 적용·Edge Function 3개 배포까지 끝나 지금 돌고 있다.** push-notification은 1단계(토큰·원장 스키마)만 적용·커밋됐고 아무도 그 테이블을 읽지 않는다. 로컬 Docker가 없어 마이그레이션은 원격에 적용하며 **단계마다 오너 확인**을 받는다.

## 설계 원칙 (전체를 관통하는 5가지)

1. **사람도 AI도 "사실"만 말하고, 승패는 DB가 정한다.** 참가자의 판정은 `battle_judgments`에 승인/불복·우열 선택이라는 *사실*로만 들어가고, AI 재판정도 `battle_submissions.meets_criteria`·우열 승자라는 사실로만 들어간다. 그 사실들로 상태·승자·점수를 계산하는 규칙은 전부 Postgres 순수 함수와 `finalize_battle` 안에 있다. 사용자 판정을 받는다고 해서 클라이언트가 승패를 계산하는 일은 없다(CLAUDE.md "클라이언트에서 승패 계산 금지").
2. **판정 창은 상태로 표현한다.** "지금 판정할 수 있는가"를 화면이 시각 계산으로 짐작하지 않는다. `battles.status = 'judging'` + `judging_opened_at` + `judge_deadline_at` 세 값이 서버의 답이고, 제출 수락·판정 수락·증거 공개·자동 승인이 모두 이 세 값을 본다.
3. **비공개는 서버가 막는다.** 마감(또는 양쪽 제출) 전에는 상대의 제출 시각·사진·통과 여부·교체 여부를 **어떤 쿼리로도** 얻을 수 없다. "제출했다"는 사실만 양쪽이 읽는 요약 컬럼(`battle_participants.has_submitted`)으로 분리하고, 시각을 담은 값은 그 테이블에서 없앤다. 사진은 Storage select 정책이 같은 규칙으로 막으므로 서명 URL 발급 자체가 실패한다.
4. **잠수는 언제나 잠수한 쪽에 불리하게 끝난다.** 미판정은 승인으로 간주되고, 판정 창은 cron이 닫는다. 대결이 영영 `active`/`judging`으로 남는 경로를 만들지 않는다.
5. **AI 호출은 "결론이 나지 않은 건"에만 붙는다.** 사람 판정으로 결론이 나면 AI 호출은 0회다. 호출을 만드는 유일한 지점은 (a) 불복 기록, (b) 우열 답 불일치이고, 실패 처리(자동 재시도 2·5·10분 → `voided`)는 ai-judge에서 검증된 구조를 그대로 옮겨 쓴다.

## CLAUDE.md 도메인 규칙 조항 대조

지금 CLAUDE.md "도메인 규칙"은 ai-judge 기준이다. 조항 단위로 이 설계가 무엇을 바꾸는지 적는다. **문구 갱신은 마지막 단계(5단계)에서 한다.**

| # | CLAUDE.md 조항 | 판단 | 이 설계에서 |
|---|---|---|---|
| 1 | 유형 두 가지, 둘 다 승자가 있다 | 유지 | 그대로 |
| 2 | 판정은 AI 심판이 한다. 참가자 승인/이의제기 절차는 없다 | **대체** | 1차 참가자 상호 판정, 2차 AI 재판정. 용어는 `승인`/`불복`이고 AI 판정은 여전히 최종 |
| 3 | 증거는 앱 카메라 사진만, 촬영 시각 대조, 승부 기준은 서버 시각 | 유지 + 추가 | 전부 유지. **속도전 교체**를 더하고, 교체 시 `submitted_at`을 서버 시각으로 다시 찍는다 |
| 4 | 기준은 AI가 만들고 생성자가 확정, 증명 불가 차단, 품질전 우열 기준, `criteria_version` | 유지 | 그대로. 사람이 판정하므로 "참가 전 공개"가 더 중요해진다 |
| 5 | 속도전 판정: 제출 즉시 AI, 5회 상한, 통과 시 잠금, 실패는 미산입 | **대체** | 제출 즉시 판정 없음. 5회 상한·`error` 미산입·불합격 재제출 개념 소멸. 잠금 기준은 "상대가 제출함" |
| 6 | 품질전 판정: 제출 1회, 두 사진 모이면 AI가 2단계 판정 | **부분 대체** | 두 사진이 모이면 **사람의 판정 창**이 열린다. 제출 1회·교체 없음은 유지. 한쪽만 제출 시 규칙(판정 없이 제출자 승리)도 유지 |
| 7 | AI 판정은 최종, `disputed` 미도달 | 유지 | 그대로. 참가자 "불복"은 사람 판정에 대한 것이고 AI 판정에는 불복 수단이 없다 |
| 8 | 상대 증거·사유는 종결 후에만. 진행 중에는 제출 사실과 속도전 합격/불합격 | **대체** | 마감 전에는 **제출 사실만**(합격/불합격 표시 폐지, 제출 시각도 숨김). **판정 창이 열리는 순간 양쪽 증거가 동시에 공개**된다 |
| 9 | 상태 전이: 품질전만 `judging`(AI 판정 대기), 속도전은 건너뜀 | **대체** | 두 유형 공통으로 `judging`을 거치고, 뜻이 **상호 판정 창**으로 바뀐다 |
| 10 | 마감: `duration_hours` 1일/3일/7일, cron 5분, 마감은 판정을 대신하지 않는다 | **부분 대체** | 기간이 **분 단위 커스텀**(1~10080분)으로 바뀌고 정산 cron이 **1분**이 된다. "마감은 판정을 대신하지 않는다"는 더 강해진다 — 마감은 판정 창을 여는 사건일 뿐이다 |
| 11 | `draw`/`voided`/`disputed`를 합치지 않는다 | 유지 | 그대로. `voided` 도달 경로만 "불복·불일치 재판정이 끝내 실패" 로 바뀐다 |
| 12 | 점수표·하한 0·랭킹 없음 | 유지 | 그대로. "완료한 패배"의 판정 주체만 바뀐다(자동 승인 포함) |
| 13 | 하루 1대결·기준 10회·모집 1개 한도 | 유지 | 그대로(D7 — 짧은 대결도 1개를 소진한다) |
| 14 | AI 데이터 제공 동의와 철회 | 유지 | 그대로. **문구만** 고친다(D9) |
| 15 | 주제 모집 자동 매칭 | 유지 | 그대로 |
| 16 | 포기만이 탈출구, 포기한 쪽 패배 | 유지 | 그대로. `judging`(판정 창)에서도 포기할 수 있다 |
| 17 | 2인만 | 유지 | 판정자 N명 구조를 만들지 않는다. `battle_judgments`에 `target_id`를 두지 않는 이유도 이것이다(대상은 항상 상대 한 명) |
| 18 | 판정 로직은 DB/Edge, 화면은 표시만 | 유지 | 판정 **입력**은 사용자가 하지만 결론은 서버가 낸다. 화면은 버튼을 보내고 서버 값을 읽는다 |
| 19 | 계정 삭제 묘비, 사용자 FK는 `profiles` | 유지 | 신규 두 테이블도 `public.profiles`를 참조한다 |

---

## 상태 전이

### 상태 값 (새 상태 없음)

| status | 뜻 (변경분 굵게) | 사용자 표시 | 종결 |
|---|---|---|---|
| `pending` | 모집 중, 상대 없음 | 모집 중 | 아님 |
| `active` | 매칭됨. **제출 창**(사진을 내고 교체하는 구간) | 진행 중 | 아님 |
| `judging` | **상호 판정 창. 두 유형 공통.** 양쪽 증거가 공개되고 참가자가 판정한다. AI 재판정은 이 안의 갈래다 | 판정 중 | 아님 |
| `finished` | 승자 있음(`winner_id` 항상 not null) | 승/패 | 종결 |
| `draw` | 가를 근거가 없음 | 무 | 종결 |
| `voided` | **불복·불일치 AI 재판정이 끝내 실패** | 무효 | 종결 |
| `cancelled` | 모집 취소, 동의 철회로 인한 모집 취소, 탈퇴 정리 | 취소 | 종결 |
| `disputed` | 유료 재심용 개념. **어떤 함수도 이 값을 쓰지 않는다** | 미결 | 종결 |

`judging`의 뜻이 바뀌므로 `battles.status` 주석과 `battle_participants` 관련 주석을 함께 고친다(옛 주석이 사실과 달라진다 — ai-judge 1단계에서 같은 정리를 했다).

**용어 충돌 방지**: 참가자의 불복을 `battle_judgments.min_verdict = 'reject'`로 적는다. `'dispute'`를 쓰면 유료 재심용으로 남겨 둔 `disputed` 상태와 화면·코드에서 뒤섞인다(spec 범위 밖: "두 용어를 화면에서도 섞지 않는다").

### 판정 창의 세 시점

| 시점 | 어디에 기록하나 | 누가 전이시키나 |
|---|---|---|
| **창이 열린다** | `battles.status = 'judging'`, `judging_opened_at = now()`, `judge_deadline_at = now() + interval '24 hours'` | (a) **양쪽 제출**: `accept_submission`이 같은 트랜잭션에서 — 마감을 기다리지 않는다. (b) **마감**: cron `settle-expired-battles`(1분) → `settle_expired_battles()` |
| **창이 닫힌다(기한)** | `judge_deadline_at <= now()` | cron `close-judging-windows`(1분) → `close_expired_judging_windows()`가 미판정을 승인으로 채운다 |
| **즉시 종결** | `finalize_battle`이 `status`·`winner_id`·`finished_at`·`outcome` 기록 | `submit_judgment`(마지막 필요 판정), `record_min_criteria_verdict`/`record_superiority_verdict`(마지막 AI 결과) — 셋 다 `resolve_battle`을 거친다 |

- `judge_deadline_at`은 **창이 열린 시각 + 24시간**이다(오너 확정, 결정 사항 1). `timestamptz + interval`은 STABLE이라 generated column으로 둘 수 없어 창을 열 때 같은 문장에서 함께 기록한다. 제약 `check ((judging_opened_at is null) = (judge_deadline_at is null))`로 두 값이 따로 놀지 않게 한다.
- 창이 마감에 열리는 보통의 경우 이 값은 spec의 "마감 후 24시간"과 정확히 같다. 양쪽 제출로 일찍 열린 경우에만 그보다 이르고, 그때도 창의 길이는 24시간이다.
- **기산점이 갈라지지 않게 계산을 한 곳에 둔다.** `judging_opened_at`·`judge_deadline_at`을 쓰는 지점은 아래 세 곳뿐이고, 셋 다 **`open_judging_window(p_battle_id)` 내부 함수를 통과한다.** 이 함수만 두 컬럼에 값을 넣으므로 `now() + interval '24 hours'` 표현식이 코드에 한 번만 있다.

| 창을 여는 경로 | 호출 사슬 | 기산점 |
|---|---|---|
| 양쪽 제출(마감 전·후 무관) | Edge `submit-evidence` → `accept_submission` → `open_judging_window` | 마지막 제출이 수락된 서버 시각 |
| 마감, 속도전 한쪽만 제출 | cron → `settle_expired_battles` → `open_judging_window` | cron이 그 대결을 집은 서버 시각(= 마감 직후, 최대 1분 뒤) |
| 그 밖 | **없다.** 다른 함수는 두 컬럼을 쓰지 않는다 | - |

  마감 경로에서 기산점이 `deadline_at`이 아니라 "cron이 집은 시각"인 것은 의도된 것이다. 사용자에게 판정 기한을 `judge_deadline_at`으로 보여 주므로 화면과 서버가 같은 값을 보고, cron 지연(최대 1분)만큼 기한이 늘어나는 쪽으로만 어긋난다(사용자에게 불리해지지 않는다).
- **아무도 제출하지 않았으면 창을 열지 않는다.** 판정할 것이 없으므로 마감에서 곧바로 `draw`다.
- **품질전 한쪽만 제출도 창을 열지 않는다.** 판정할 상대 증거가 없어 제출자가 바로 승리한다(기존 Q8 규칙 유지).
- **속도전 한쪽만 제출은 창을 연다.** 낸 사람의 사진이 최소 기준을 통과했는지는 아직 아무도 판정하지 않았고, 그 판정을 할 사람은 제출하지 않은 상대다. 판정하지 않으면 자동 승인되어 제출자가 이긴다.

### 판정 창을 여는 규칙 (순수 함수 `judging_gate`)

| 유형 | a 제출 | b 제출 | 마감 | 결과 |
|---|---|---|---|---|
| 공통 | O | O | 무관 | `open` (마감을 기다리지 않는다) |
| 공통 | 아무 조합 | | 전 | `wait` |
| speed | O | X | 후 | `open` |
| speed | X | X | 후 | `draw` |
| quality | O | X | 후 | `finish_a` (제출자 승리, 상호 판정·AI 없음) |
| quality | X | X | 후 | `draw` |

### 전이표 (두 유형 공통 + 유형별 차이)

| # | 현재 | 사건 | 트리거(호출자) | 다음 | 결과 |
|---|---|---|---|---|---|
| T1 | `pending` | 참가 | 참가자 → `join_battle(battle, version)` | `active` | 양쪽 오늘 슬롯 소진, `deadline_at = now() + duration_minutes` |
| T2 | `active` | 첫 제출 수락 | Edge `submit-evidence` → `accept_submission` | `active` 또는 `judging` | 제출 행 생성, `has_submitted = true`. 상대도 제출했으면 `judging_gate = open` → 창 열림 |
| T3 | `active` | **교체 제출 수락(속도전, 상대 미제출)** | 동일 | `active` | 제출 행을 덮어쓰고 `submitted_at = now()`. 옛 사진은 Edge가 지운다 |
| T4 | `active` | 교체 시도(상대가 이미 제출) / 품질전 두 번째 제출 | 동일 | `active` | 거부 `SUBMISSION_LOCKED`(행 변화 없음) |
| T5 | `active` | 마감 경과 | cron `settle_expired_battles()` | `judging` \| `finished` \| `draw` | `judging_gate` 규칙 |
| T6 | `judging` | 참가자 판정 수락 | 참가자 → `submit_judgment` | `judging` 또는 종결 | 판정 행 기록, `has_judged = true`, 불복이면 AI 잡 생성, `resolve_battle` |
| T7 | `judging` | 판정 기한 경과 | cron `close_expired_judging_windows()` | `judging` 또는 종결 | 필요한 미판정을 `approve`(auto)로 채우고 `resolve_battle` |
| T8 | `judging` | AI 최소 기준 재판정 성공 | Edge `judge-dispute` → `record_min_criteria_verdict` | `judging` 또는 종결 | 제출 행에 `meets_criteria`·사유 기록, `resolve_battle` |
| T9 | `judging` | AI 우열 재판정 성공 | Edge `judge-dispute` → `record_superiority_verdict` | `finished` | `battles.verdict_reason` 기록 후 `finalize_battle` |
| T10 | `judging` | AI 재판정 실패, 시도 남음 | 동일 / cron의 임대 만료 처리 | `judging` | 다음 시도 예약(2·5·10분) |
| T11 | `judging` | AI 재판정 실패, 4회 소진 | 동일 | `voided` | 점수 0, 매칭일이 오늘인 슬롯 반환 |
| T12 | `active`/`judging` | 포기 / 동의 철회 | `forfeit_battle` / `withdraw_ai_consent` | `finished` | 상대 `win`(+3), 본인 `forfeit`(-3). 남은 AI 잡 삭제 |
| T13 | `active`/`judging` | 상대 탈퇴 | `delete_account` | `cancelled` | 점수 0, 매칭일이 오늘이면 남은 사람 슬롯 반환, AI 잡 삭제 |

`judging`에서 마감(`deadline_at`)이 지나도 아무 일도 일어나지 않는다. 마감은 제출 창의 끝이고, 판정 창은 `judge_deadline_at`이 지배한다. `settle_expired_battles`는 `status = 'active'`만 본다.

### 결론 규칙

**(1) 제출별 최소 기준 결론** — 순수 함수 `min_verdict_effect(p_submitted, p_opponent_verdict, p_ai_meets)`

| 제출 | 상대 판정 | AI `meets` | 결론 |
|---|---|---|---|
| X | - | - | `none` (제출 없음) |
| O | null(아직 판정 안 함) | - | `pending` |
| O | `approve` (사람 또는 자동) | - | `pass` |
| O | `reject` | null | `pending` (AI 대기) |
| O | `reject` | true | `pass` — **AI가 사람 판정을 대체한다**(거짓 불복이 이득이 되지 않는 지점) |
| O | `reject` | false | `fail` |

**(2) 속도전** — 순수 함수 `mutual_speed_outcome(a_effect, a_at, a_seq, b_effect, b_at, b_seq)`

| a | b | 결과 |
|---|---|---|
| `pass` | `pass` | 이른 `submitted_at`이 승리(동률이면 `battle_submissions.id`가 작은 쪽). 패자 `completed_loss`(-1) |
| `pass` | `fail`/`none` | a `win`, b `loss`(-3) |
| `fail`/`none` | `pass` | b `win`, a `loss`(-3) |
| `fail`/`none` | `fail`/`none` | `draw`(양쪽 -1) |

`pending`이 하나라도 있으면 이 함수를 부르지 않는다(`resolve_battle`이 대기한다). 승부 시각은 여전히 서버 `submitted_at`이고, 교체하면 이 값이 갱신되므로 "빨리 눌러 선점하고 나중에 바꾸기"가 성립하지 않는다.

**(3) 품질전** — 순수 함수 `mutual_quality_outcome(a_effect, b_effect, a_pick, b_pick)`. `*_pick`은 그 사람이 고른 승자를 `'a'|'b'|null` 슬롯으로 넘긴 값이다(미판정은 null).

| a | b | a_pick | b_pick | `next` | 결과 |
|---|---|---|---|---|---|
| `pass` | `fail` | 무관 | 무관 | `finish` | a `win`, b `loss`. 우열은 묻지 않는다 |
| `fail` | `pass` | 무관 | 무관 | `finish` | b `win`, a `loss` |
| `fail` | `fail` | 무관 | 무관 | `draw` | 양쪽 -1 |
| `pass` | `pass` | `a` | `a` | `finish` | a `win` — **합의, AI 호출 없음** |
| `pass` | `pass` | `b` | `b` | `finish` | b `win` — 합의 |
| `pass` | `pass` | `a` | null | `finish` | a `win` — 한쪽만 답함 |
| `pass` | `pass` | null | `b` | `finish` | b `win` — 한쪽만 답함 |
| `pass` | `pass` | `a` | `b` | **`ai`** | 우열 AI 재판정 1회 |
| `pass` | `pass` | `b` | `a` | **`ai`** | 우열 AI 재판정 1회 |
| `pass` | `pass` | null | null | `draw` | 양쪽 -1, **AI 호출 없음**(무임승차 방지) |

`a_pick = a, b_pick = b`는 "둘 다 내가 더 잘했다", `a_pick = b, b_pick = a`는 "둘 다 상대가 더 잘했다"에 해당한다. 두 경우 모두 "아무도 승복하지 않았다"이므로 AI가 가른다(spec 원문의 세 번째 줄). 품질전 패배는 항상 `loss`(-3)이고 감면이 없다.

**(4) 점수와 outcome** — ai-judge 설계의 표를 **한 줄도 바꾸지 않는다.** `win +3 / completed_loss -1 / loss -3 / forfeit -3 / draw -1`, 하한 0, `voided`·`cancelled`는 0. 반영은 `finalize_battle` 한 곳, 무효는 `void_battle` 한 곳. `outcome_score_delta`는 그대로 쓴다.

발생 지점만 바뀐다: `completed_loss`는 이제 "상대의 승인 또는 자동 승인 또는 불복 후 AI 통과로 유효한 완료를 인정받은 속도전 패자"다.

**(5) 규칙에서 따라오는 결과 하나** — 속도전에서 제출하지 않은 사람이 상대를 불복하면, AI가 상대의 사진을 불합격으로 보면 결과가 `loss`(-3)에서 `draw`(-1)로 바뀐다. spec이 정한 규칙의 직접적 귀결이고, 거짓 불복은 AI가 그 자리에서 뒤집으므로 이득이 되지 않는다(spec "거짓 불복에 점수 벌칙을 두지 않는다"와 같은 선). 규칙을 바꾸지 않는다.

---

## 데이터 모델

### `battles` (변경)

| 항목 | 조치 |
|---|---|
| `duration_hours integer` + `check in (24,72,168)` | **`duration_minutes integer not null check (duration_minutes between 1 and 10080)`로 교체.** 아래 "커스텀 마감" 참고 |
| `judging_opened_at timestamptz` | **추가.** 판정 창이 열린 서버 시각. null이면 아직 제출 창이다 |
| `judge_deadline_at timestamptz` | **추가.** 판정 기한(창 열림 + 24시간) |
| 제약 | `check ((judging_opened_at is null) = (judge_deadline_at is null))`, `check (status <> 'judging' or judging_opened_at is not null)` |
| 인덱스 | `(judge_deadline_at) where status = 'judging'`, `(deadline_at) where status = 'active'` — 1분 주기 cron이 두 테이블 스캔을 하지 않게 |
| `verdict_reason text` | 유지. **우열 AI 재판정이 확정될 때만** 쓴다(그 함수가 곧바로 종결시키므로 판정 창 중에 새지 않는다). 최소 기준 재판정 사유는 제출 행에 남는다 |
| `status` 체크 제약 | 변경 없음(새 상태 없음). 주석만 갱신 |
| select 정책 2개 | 변경 없음(참가자 전체 + `pending`은 누구나) |

### `battle_participants` (변경 — 진행 중 상대에게 보여도 되는 것만 남긴다)

| 항목 | 조치 | 이유 |
|---|---|---|
| `first_submitted_at timestamptz` | **삭제**, `has_submitted boolean not null default false`로 교체 | 이 테이블은 참가자 둘 다 읽는다(정책 `participants can view their battle progress` — 아래 "공개 범위와 RLS"에서 조건까지 확인했다). **시각**을 담으면 spec이 숨기라고 한 "상대의 제출 시각"이 그대로 새고, 교체할 때마다 값이 바뀌면 "몇 번 교체했는지"까지 드러난다. 불린은 두 정보를 동시에 없앤다 |
| `attempts_used smallint` | **삭제** | 판정 5회 상한 폐기 |
| `last_verdict text` | **삭제** | 진행 중 상대 합격/불합격 표시 폐기 |
| `passed_at timestamptz` | **삭제** | 속도전 승부 시각은 유효한 완료로 확정된 제출의 `submitted_at`이다. 요약 컬럼에 두면 "상대가 통과했다"가 새는 경로가 된다 |
| `has_judged boolean not null default false` | **추가** | 화면이 "내 판정 차례 / 상대 판정 대기 / AI 재판정 중"을 구분해야 한다. 대안은 `battle_judgments` 행을 상대에게 여는 것인데 그건 판정 **내용**까지 노출한다. 불린은 "판정했다"만 말한다. 자동 승인으로 채워진 경우에도 true다 |
| `outcome`, `score_delta_applied` | 유지 | 종결 시 `finalize_battle`이 기록 |

### `battle_submissions` (변경 — 참가자당 한 행, 교체는 덮어쓰기)

```
id bigserial primary key
battle_id uuid not null references battles(id) on delete cascade
user_id  uuid not null references profiles(id) on delete cascade
object_path text                  -- battle_evidence 경로. 탈퇴 시 null
captured_at  timestamptz not null -- 앱이 보낸 촬영 시각(대조용)
submitted_at timestamptz not null default now()  -- 서버 수신 시각 = 속도전 승부 기준. 교체하면 갱신
meets_criteria boolean            -- 최소 기준 결론(승인/자동 승인/AI). 미결이면 null
verdict_source text check (verdict_source in ('opponent','auto','ai'))  -- 누가 정했나
reason text                       -- AI 재판정의 한 줄 사유(사람 판정에는 사유가 없다)
ai_model text
unique (battle_id, user_id)       -- 참가자당 한 행
index (battle_id, user_id)
```

| 항목 | 조치 | 이유 |
|---|---|---|
| `status text` | **삭제** | 값이 `submitted` 하나만 남는다. `judging/passed/failed/error`는 제출 즉시 AI 판정이 있던 시절의 개념이다 |
| `judging_started_at` | **삭제** | 동기 판정이 없다. 끊긴 판정 청소(`sweep_stale_submissions`)도 없어진다 |
| 부분 유니크 3개(`one_judging`/`one_passed`/`one_quality`) | **삭제**, `unique (battle_id, user_id)` 하나로 교체 | 두 유형 모두 참가자당 제출 1건이다. 교체는 새 행이 아니라 이 행의 덮어쓰기다 |
| `meets_criteria` | 유지(뜻 확장) | 속도전 1단계 결과도 여기에 들어온다 |
| `verdict_source` | 추가 | 결과 화면이 "상대가 인정 / 판정 기한이 지나 자동 인정 / AI가 다시 보고 인정"을 구분해 말해야 한다. 파생 가능한 값이지만 판정 사실의 기록이므로 남긴다 |

**교체는 행을 덮어쓴다.** spec 수용 기준 "내 제출 이력은 마감 전에도 내가 볼 수 있다"는 *현재 내 제출*을 내가 볼 수 있다는 뜻으로 읽는다. 옛 사진을 행으로 남기면 (a) 버킷에 쓰레기가 쌓이고, (b) 행 수가 곧 교체 횟수라 공개 범위가 열릴 때 상대에게 그대로 드러난다. 두 문제를 동시에 없애려면 덮어쓰기가 맞다. 덮어쓰기 전 경로는 `accept_submission`이 반환하고 Edge가 service 롤로 지운다.

### `battle_judgments` (신규 — 참가자 상호 판정 기록)

```
battle_id uuid not null references public.battles (id) on delete cascade
judge_id  uuid not null references public.profiles (id) on delete cascade
min_verdict text not null check (min_verdict in ('approve','reject'))
superior_id uuid references public.profiles (id)   -- 품질전만. 더 잘했다고 고른 사람
auto boolean not null default false                 -- 판정 기한 경과로 서버가 채운 행
decided_at timestamptz not null default now()
primary key (battle_id, judge_id)
```

- **판정 대상 컬럼을 두지 않는다.** 2인 대결이므로 대상은 항상 `judge_id`의 상대다(CLAUDE.md "3인 이상 구조를 미리 만들지 말 것").
- `superior_id`를 상대적 값(`'me'|'opponent'`)이 아니라 **절대적 사용자 id**로 적는다. 두 사람의 답이 같은 사람을 가리키는지(합의) 어긋나는지(AI)를 비교할 때 뒤집기 실수가 생기지 않는다.
- 미답은 `superior_id is null`이다. 자동 승인 행(`auto = true`)은 `min_verdict = 'approve'`, `superior_id = null`로 넣는다. 우열을 "승복" 쪽으로 억지로 채우지 않는다 — 채우면 spec의 "한쪽만 답함 → 답한 쪽 답대로 확정"이 성립하지 않고 불필요한 AI 호출이 생긴다.
- **표로 강제할 수 없는 두 가지는 RPC가 본다**(유형과 참가자가 다른 테이블에 있어 CHECK로 쓸 수 없다): 속도전이면 `superior_id is null`, 품질전이면 `superior_id`가 두 참가자 중 하나.
- 한 사람의 판정은 **한 번뿐**이다(PK). 두 번째 호출은 `ALREADY_JUDGED`. 되돌리기·수정 수단은 spec에 없으므로 만들지 않는다.
- RLS: 켠다. select는 `judge_id = auth.uid()` **또는** (참가자이고 대결이 종결 상태). 판정 창 중에 상대의 판정 내용이 보이면 상대 답을 보고 내 답을 고르는 경로가 생긴다. insert/update/delete 정책은 두지 않는다(쓰기는 `submit_judgment`와 서버 전용 함수만).

### `ai_judgment_jobs` (신규 — `quality_judgments`를 대체)

```
id bigserial primary key
battle_id uuid not null references public.battles (id) on delete cascade
kind text not null check (kind in ('min_criteria','superiority'))
target_id uuid references public.profiles (id) on delete cascade  -- min_criteria: 판정할 사진의 주인
attempts smallint not null default 0 check (attempts between 0 and 4)
next_attempt_at timestamptz not null default now()
lease_token uuid
lease_until timestamptz
last_error text
created_at timestamptz not null default now()
check ((kind = 'min_criteria') = (target_id is not null))
unique (battle_id, target_id) where kind = 'min_criteria'
unique (battle_id)             where kind = 'superiority'
index (next_attempt_at)
```

- `quality_judgments`(대결당 잡 1개)를 **버리고 새로 만든다.** 이제 한 대결에 최대 3건(최소 기준 불복 2 + 우열 1)의 AI 호출이 따로 생기고, 각자 4회 시도·임대·백오프를 따로 세야 한다. 배틀 단위 PK로는 표현할 수 없다.
- **순서는 잡 생성 시점이 만든다.** 최소 기준 잡은 불복이 기록되는 즉시(`submit_judgment`) 생기고, 우열 잡은 두 최소 기준 결론이 모두 `pass`가 된 뒤(`resolve_battle`)에만 생긴다. 디스패처에 순서 로직을 두지 않는다.
- 어느 잡이든 4회를 다 쓰면 그 대결은 `voided`다(D5). 남은 다른 잡은 함께 지운다.
- RLS: 켜고 **정책을 하나도 두지 않는다**(`quality_judgments` 선례). 클라이언트는 이 테이블을 알 필요가 없다.

### 공개 범위와 RLS

| 무엇 | 마감/양쪽 제출 전 | 판정 창 | 종결 후 |
|---|---|---|---|
| 상대가 제출했는지 | **보인다**(`battle_participants.has_submitted`) | 보인다 | 보인다 |
| 상대의 제출 시각 | 안 보인다 | 보인다(제출 행이 열린다) | 보인다 |
| 상대의 증거 사진 | 안 보인다(서명 URL 발급 실패) | **보인다** | 보인다 |
| 상대 제출의 통과 여부 | 존재하지 않는다 | 확정되는 대로 보인다 | 보인다 |
| 상대가 몇 번 교체했는지 | 안 보인다(행을 덮어쓰고 요약은 불린이다) | 안 보인다 | 안 보인다 |
| 상대가 판정했는지 | - | 보인다(`has_judged`) | 보인다 |
| 상대가 무엇으로 판정했는지 | - | **안 보인다** | 보인다 |
| AI 재판정 사유 | - | 내 사진에 대한 것만 | 보인다 |

#### `battle_participants`의 노출은 확인된 사실이다

메인 세션이 **원격 스키마에서 직접 확인했다**(추측이 아니다). 정책은 `20260818220100_battles.sql`의

```
create policy "participants can view their battle progress"
  on public.battle_participants for select
  to authenticated
  using (
    exists (
      select 1 from public.battles b
      where b.id = battle_id and auth.uid() in (b.creator_id, b.opponent_id)
    )
  );
```

이고, 조건이 **행의 `user_id`를 보지 않는다.** 그래서 참가자는 자기 행뿐 아니라 **상대 행까지 전부 읽는다** — 지금 이 테이블에 있는 `first_submitted_at`(상대의 제출 시각), `last_verdict`(상대의 합격/불합격), `passed_at`(상대의 통과 시각)이 상대에게 그대로 노출되는 것이 맞다. spec이 숨기라고 한 세 가지가 이 정책 하나로 새고 있다.

**결론: 정책은 고치지 않고 노출 컬럼을 교체하는 것으로 충분하다.** 판단 근거:

| 남는 컬럼 | 상대에게 보여도 되는가 | 시점 분기가 필요한가 |
|---|---|---|
| `has_submitted` | **된다.** spec D2가 "마감 전에 공개하는 것은 제출 사실 하나"라고 명시했다 | 아니다 — 처음부터 보여야 한다 |
| `has_judged` | **된다.** 판정 *내용*이 아니라 "판정했다"는 사실이다 | **아니다 — 구조적으로 필요가 없다.** `submit_judgment`가 `status = 'judging'`을 요구하므로(`JUDGING_NOT_OPEN`) 판정 창 전에는 이 값이 언제나 false다. 정책에 시점 조건을 넣어도 결과가 같다 |
| `outcome` | 된다 | 아니다 — `finalize_battle`이 **종결 시에만** 채우므로 그전에는 null이다. 공개 허용 시점과 값이 생기는 시점이 일치한다 |
| `score_delta_applied` | 된다 | 같은 이유로 아니다. 상대의 총점·전적은 이미 `get_player_card`로 공개되는 범위이고, 이 값은 그 사람의 `outcome`에서 거의 파생된다 |

정책을 "본인 행만"으로 좁히지 않는 이유는 두 가지다.
1. **RLS는 행 단위라 "내 행은 전부, 상대 행은 일부 컬럼"을 표현할 수 없다.** 컬럼 권한(`grant select (col)`)은 롤 단위여서 본인/상대를 가르지 못한다. 좁히려면 상대 요약을 RPC나 뷰로 따로 내야 한다.
2. 그러면 **목록 화면이 깨진다.** 내 대결 목록의 상태 줄은 대결마다 상대의 `has_submitted`·`has_judged`를 쓰고, 지금은 `fetchParticipantsOf`가 한 번의 질의로 전부 읽는다(ai-judge 7단계에서 이 목적으로 만든 일괄 조회다). 정책을 좁히면 대결 수만큼 RPC를 부르거나 집계 RPC를 새로 만들어야 하는데, 얻는 것은 위 표에서 이미 "보여도 된다"로 판정된 네 컬럼을 한 번 더 가리는 것뿐이다.

대신 **정책이 남는다는 사실 자체를 규칙으로 못박는다**: 이 테이블에 새 컬럼을 더하면 **상대에게 자동으로 공개된다.** 그래서 (a) 2단계 마이그레이션에서 정책과 테이블에 이 불변식을 주석으로 적고(`"이 테이블의 모든 컬럼은 상대 참가자도 읽는다. 진행 중 상대에게 보여도 되는 요약만 둔다."`), (b) 시점에 따라 가려야 하는 값은 **전부 `battle_submissions`와 Storage에 둔다**(그 두 곳이 `judging_opened_at`으로 시점을 가른다). 지금 새는 세 컬럼이 생긴 원인이 정확히 이 규칙의 부재였다 — ai-judge 설계는 같은 말을 본문에만 적었고 DB에는 남기지 않았다.

정책 조건의 `auth.uid() in (b.creator_id, b.opponent_id)`는 **그대로 둔다.** CLAUDE.md가 금지한 것은 `not in`이고, `in`은 비로그인일 때 NULL → 정책 불통과로 닫히는 안전한 방향이다.

`battle_submissions` select 정책(교체):

```
using (
  user_id = auth.uid()
  or exists (
    select 1 from public.battles b
    where b.id = battle_id
      and (auth.uid() = b.creator_id or auth.uid() = b.opponent_id)
      and (b.judging_opened_at is not null
           or b.status in ('finished','draw','voided','cancelled','disputed'))
  )
)
```

`judging_opened_at is not null`이 판정 창과 종결 후를 함께 덮고, 종결 상태 목록은 **창 없이 끝난 대결**(제출 0건 `draw`, 품질전 한쪽 제출 승리, 포기, 취소)의 사후 공개를 덮는다. 참가자 비교는 등호 두 개로 쓴다(`not in`의 null 함정 반대 방향, 기존 정책과 같은 형태).

Storage(`battle_evidence`) 정책:

| 동작 | 조치 |
|---|---|
| select | **교체.** 위와 같은 조건(`본인 폴더` 또는 `참가자 and (판정 창 열림 or 종결)`). `createSignedUrl`이 이 정책을 거치므로 마감 전 상대 사진은 URL 발급 자체가 실패한다 |
| insert | **교체.** 기존 조건에 `b.judging_opened_at is null`을 더한다. `status = 'active'`가 이미 함의하지만, 교체 업로드가 창이 열린 뒤에 끼어들지 못하게 두 번 본다 |
| update | 정책 없음(덮어쓰기 금지, 기존 유지). 교체는 **새 파일 업로드 + 옛 파일 삭제**다 |
| delete | 본인 폴더(기존 유지). 거부·교체된 사진은 Edge가 service 롤로 지운다 |

---

## 제출 교체와 경합

**규칙(D3)**: 속도전은 상대가 아직 제출하지 않은 동안 몇 번이든 교체할 수 있고, 교체하면 `submitted_at`이 갱신된다. 상대가 제출하는 순간 내 사진도 잠긴다. 품질전에는 교체가 없다.

`accept_submission`이 `battles` 행을 `for update`로 잠근 뒤 판단한다:

| 내 제출 행 | 상대 제출 행 | 유형 | 동작 |
|---|---|---|---|
| 없음 | 없음 | 공통 | insert. `has_submitted = true`. 창은 열지 않는다 |
| 없음 | 있음 | 공통 | insert. `has_submitted = true`. **양쪽 제출 → 같은 트랜잭션에서 판정 창 열림** |
| 있음 | 없음 | speed | **update**(경로·`captured_at`·`submitted_at` 갱신). 옛 경로를 반환 |
| 있음 | 없음 | quality | 거부 `SUBMISSION_LOCKED` |
| 있음 | 있음 | 공통 | 거부 `SUBMISSION_LOCKED`(이미 창이 열려 `status <> 'active'` 검사에서 먼저 걸린다) |

**DB 제약으로 강제할 수 있는 것은 "참가자당 제출 1행"까지다.** "상대가 안 낸 동안만 교체"는 두 행의 관계에 대한 조건이라 CHECK로 쓸 수 없고, `battles` 행 잠금 안의 검사가 유일한 강제 수단이다. 대신 그 잠금이 **직렬화 지점**이 되어 경합이 정의된 대로 끝난다:

- 내 교체와 상대의 첫 제출이 동시에 오면 둘 다 같은 `battles` 행을 기다린다.
- 상대가 먼저 커밋 → 내 교체 트랜잭션은 `status = 'judging'`(창 열림)을 보고 거부된다. 내 옛 사진이 그대로 판정 대상이 된다.
- 내가 먼저 커밋 → 상대의 제출이 이어서 들어오고 그 트랜잭션에서 창이 열린다. 내 새 사진이 판정 대상이 되고 `submitted_at`은 교체 시각이다.
- 어느 쪽이든 "교체된 사진과 잠긴 사진이 섞인 상태"는 생기지 않는다.

업로드는 잠금 밖에서 일어나므로(클라이언트가 Storage에 먼저 올린다) **거부된 업로드와 교체로 밀려난 옛 사진을 지우는 책임은 Edge에 있다.** `submit-evidence`가 거부 시 방금 올린 경로를, 교체 성공 시 반환된 옛 경로를 지운다.

---

## 커스텀 마감 (분 단위)

### 컬럼 이전

`duration_hours integer not null default 72 check (duration_hours in (24,72,168))` → **`duration_minutes`로 교체**한다. 컬럼을 하나 더 두고 둘을 유지하는 방식은 쓰지 않는다(진실이 두 곳에 생긴다).

```
alter table public.battles add column duration_minutes integer;
update public.battles set duration_minutes = duration_hours * 60;
alter table public.battles
  alter column duration_minutes set not null,
  alter column duration_minutes set default 1440,
  add constraint battles_duration_minutes_check check (duration_minutes between 1 and 10080),
  drop constraint battles_duration_hours_check,
  drop column duration_hours;
```

- 상한 10080분(7일)은 지금의 최대값과 같다. 하한만 24시간 → 1분으로 내린다(범위를 넓히지 않는다).
- 기본값은 1440분(1일)으로 둔다. `create_battle`이 항상 값을 넘기므로 기본값은 스모크 테스트의 편의용이다.

### 따라 고쳐야 하는 곳

| 대상 | 조치 | 함정 |
|---|---|---|
| `join_battle(uuid, integer)` | `deadline_at = now() + make_interval(mins => v_battle.duration_minutes)` | 시그니처 유지(`create or replace`) |
| `create_battle(p_check_id uuid, p_duration_hours integer)` | **`drop function` 후 `create_battle(p_check_id uuid, p_duration_minutes integer)`** | 인자 **타입**이 `(uuid, integer)`로 같아서 `create or replace`로는 인자 **이름**을 바꿀 수 없다(Postgres가 거부). 드롭이 필수다. PostgREST는 인자 이름으로 RPC를 찾으므로 **Dart를 같은 단계에서 함께 바꿔야** 한다. 앱이 아직 배포되지 않았으므로 구버전 호환은 필요 없다 |
| `list_open_recruits()` | 반환 jsonb 키 `duration_hours` → `duration_minutes` | 시그니처 유지 |
| Edge `battle-criteria` | `schemas.ts`의 `DURATION_HOURS = [24,72,168]` → 분 범위 검증(1~10080 정수), `prompts.ts`의 `<duration_hours>` 태그 → `<duration_minutes>` | 프롬프트 태그 이름이 바뀌면 `prompts_test.ts`가 깨진다(의도된 것) |
| `criteria_checks` | 변경 없음 | 기간을 증서에 담지 않으므로 기간과 기준이 묶이지 않는다(지금도 그렇다) |
| Dart | `Battle.durationHours` → `durationMinutes`, `battleDurationLabel(int minutes)` | `battle_chips.dart`, 모집 카드·상세 시트, 생성 화면 |

### cron 주기

`settle-expired-battles`를 **`*/5 * * * *` → `* * * * *`**로 바꾼다. 같은 이름으로 `cron.schedule`을 다시 부르면 기존 작업이 갱신된다(6단계 선례). 5분 주기로는 1분 대결의 마감 정산이 대결 길이의 다섯 배 늦게 일어나 spec 수용 기준("짧은 대결에서도 마감 정산·판정 처리가 반드시 일어난다")을 체감상 어긴다.

### 하한 1분이 실제로 성립하는가

| 단계 | 지연 |
|---|---|
| 매칭 → 마감 | **정확히 1분**(`deadline_at`은 초 단위로 계산되고 제출 수락은 `now() < deadline_at`으로 본다) |
| 양쪽 제출 → 판정 창 열림 | **0초**(같은 트랜잭션) |
| 한쪽만/아무도 제출 안 함 → 마감 정산 | 최대 1분(cron) |
| 양쪽 판정 → 종결 | **0초**(같은 트랜잭션) |
| 불복·불일치 → AI 호출 발송 | 최대 1분(cron `ai-judge-tick`) |
| AI 호출 | 최소 기준 30초 / 우열 60초 타임아웃 |
| 미판정 → 자동 승인 | 판정 기한 24시간 + 최대 1분 |

**성립한다 — 단, "1분"은 제출 창의 길이다.** 협조하는 두 사람의 1분 대결은 제출 1분 + 판정 수 초로 끝난다. 늦어지는 것은 (a) 한쪽이 제출하지 않을 때의 정산 1분, (b) 불복이 생겼을 때의 발송 1분 + AI 호출, (c) 한쪽이 판정하지 않을 때의 24시간이다. 화면에서 **제출 창과 판정 창을 다른 줄로 보여 주는 것**(아래 화면 4)이 이 간극을 설명하는 유일한 장치다.

AI 재판정을 즉시 실행(`waitUntil`)으로 당기지 않는 이유: 판정 제출은 Edge Function이 아니라 RPC(`submit_judgment`)이므로 응답 뒤에 일을 이어 줄 프로세스가 없다. 판정만을 위해 Edge Function을 하나 더 만들면 얻는 것은 수십 초이고 잃는 것은 진입점 하나다 — cron 1분을 받아들인다.

---

## AI 재판정 재배선

### 무엇을 남기고 무엇을 새로 만드는가

| 조각 | 판단 | 내용 |
|---|---|---|
| `_shared/gemini.ts`(모델명 한 곳, REST 직접 호출, `temperature: 0`, 타임아웃, inline_data) | **그대로** | 손대지 않는다 |
| `_shared/auth.ts`, `errors.ts`, `secret.ts`(상수 시간 비교) | **그대로** | 같은 관문 구조 |
| 자동 재시도 2·5·10분 / 최대 4회 / 임대 3분 / 끝내 실패 시 `voided` | **그대로 옮긴다** | `quality_judgment_backoff` → `ai_judgment_backoff`(내용 동일), `fail_quality_judgment` → `fail_ai_judgment`(잡 단위). spec "버려지는 것은 시점이고 남는 것은 실패 처리 방식이다" |
| pg_net + Vault(`judge_function_url`, `judge_cron_secret`) + `verify_jwt = false` + `x-judge-secret` | **그대로** | Vault **값**만 새 함수 URL로 바꾼다(오너 작업) |
| 품질전 **최소 기준** 판정 질문 | **속도전 프롬프트를 재사용** | 지금의 `SPEED_JUDGE_*`가 이미 "사진 1장 + 최소 기준 → {passed, reason}"이다. 두 유형의 불복 재판정이 똑같은 질문을 하므로 이름만 `MIN_CRITERIA_JUDGE_*`로 바꿔 공용으로 쓴다 |
| 품질전 **2단계 통합 프롬프트**(`QUALITY_JUDGE_*`) | **쪼갠다** | 문구는 옮기되 1단계 부분은 위 `MIN_CRITERIA_JUDGE_*`가 이미 하고, 2단계 부분만 **우열 전용 프롬프트** `SUPERIORITY_JUDGE_*`(사진 2장 + 우열 기준 → `{winner, winner_reason}`)로 남긴다. 통합 프롬프트를 그대로 쓰면 이미 사람이 통과시킨 사진을 AI가 미달로 보고 `winner`를 비워 **매번 실패 → `voided`** 가 된다 |
| A/B 순서 섞기와 역매핑 | **그대로** | 우열 호출에만 적용(위치 편향 완화) |
| `quality_judgments` 테이블, `claim_quality_judgment`, `record_quality_verdict`, `record_quality_failure`, `dispatch_quality_judgments` | **폐기** | 시작 조건·대상·단위가 모두 달라졌다. 아래 새 함수로 대체 |
| `speed_outcome`, `quality_outcome`, `quality_deadline_outcome` | **폐기** | 5회 상한·"두 사진 모이면 AI" 규칙이 박혀 있다. 새 순수 함수 4개로 대체 |
| `record_speed_verdict`, `sweep_stale_submissions` | **폐기** | 제출 즉시 판정과 끊긴 동기 판정이 사라진다. 후자의 `ai_criteria_calls` 정리 몫만 `sweep_stale_criteria_calls()`로 옮긴다 |
| Edge `judge-quality` | **`judge-dispute`로 대체** | 이제 두 유형·두 질문을 처리한다. 이름이 사실과 다르면 나중에 더 비싸다. 옛 함수는 `supabase functions delete judge-quality` |
| Edge `submit-evidence` | **유지, Gemini 호출 제거** | 진입점·계약은 그대로. 속도전 분기의 판정 호출과 품질전 분기의 즉시 판정 실행(`waitUntil`)을 지우고, 교체된 사진 삭제를 더한다 |
| `_shared/quality_judge.ts` | **`dispute_judge.ts`로 대체** | "임대 → 판정 → 기록" 골격을 재사용하되 `kind`로 갈라진다 |

### 새 서버 전용 함수

| 함수 | 호출자 | 역할 |
|---|---|---|
| `ensure_ai_judgment_job(p_battle_id uuid, p_kind text, p_target_id uuid)` | `submit_judgment`, `resolve_battle` | `insert ... on conflict do nothing`. 잡 생성이 한 곳에만 있게 한다 |
| `claim_ai_judgment(p_job_id bigint)` → jsonb 또는 null | Edge `judge-dispute` | `for update skip locked` + 임대. `kind`, 제목, 필요한 기준 목록, 사진 경로(최소 기준은 1장, 우열은 2장), 두 참가자 id, 토큰, 시도 수를 돌려준다. 대결이 `judging`이 아니면 잡을 지우고 null |
| `record_min_criteria_verdict(p_job_id, p_token, p_meets boolean, p_reason text, p_model text)` | 같음 | 대상 제출 행에 `meets_criteria`·`reason`·`verdict_source='ai'`·`ai_model` 기록 → 잡 삭제 → `resolve_battle` |
| `record_superiority_verdict(p_job_id, p_token, p_winner_user_id uuid, p_reason text, p_model text)` | 같음 | 승자가 두 참가자 중 하나가 아니면 **성공으로 치지 않고** `fail_ai_judgment`(동점 없음을 서버가 강제 — 기존 `quality_outcome`의 `valid=false` 처리와 같은 선). 맞으면 `battles.verdict_reason` 기록 → 잡 삭제 → `resolve_battle` |
| `record_ai_judgment_failure(p_job_id, p_token, p_error text)` | 같음 | 토큰이 맞을 때만 실패 1회 |
| `fail_ai_judgment(p_job_id, p_error text)` (내부) | 위 셋 + `dispatch` | `attempts < 4` → `next_attempt_at = now() + ai_judgment_backoff(attempts)`, 임대 해제. `attempts = 4` → 그 대결의 잡 전부 삭제 + `void_battle` |
| `dispatch_ai_judgments()` | cron `ai-judge-tick` | (a) 임대 만료 잡을 실패 1회로 정리 → (b) Vault 값이 있으면 기한이 된 잡마다 `net.http_post('{job_id}')`. 값이 없으면 발송만 건너뛰고 0 반환(선례 그대로) |
| `sweep_stale_criteria_calls()` | cron `ai-judge-tick` | 2분 넘은 `in_progress` 기준 생성 호출을 `failed`로 정리(`sweep_stale_submissions`에서 이 몫만 옮긴 것) |

### AI 호출별 입력/출력

보내지 않는 것은 그대로다: 사용자 id·이름, 상대 정보, 촬영 시각, 점수, 사람의 판정 결과. **AI에게 "상대가 불복했다"를 알리지 않는다** — 알리면 판정이 사람의 주장에 끌린다.

**① 최소 기준 재판정** (`kind = 'min_criteria'`)
- 입력: `title`, `min_criteria`, 사진 1장(불복당한 제출)
- 출력: `{ "passed": boolean, "reason": string }` (한국어 한 줄 60자 이내) — 지금의 속도전 판정 스키마 그대로

**② 우열 재판정** (`kind = 'superiority'`)
- 입력: `title`, `superiority_criteria`, 사진 2장(순서 무작위)
- 출력: `{ "winner": "a" | "b", "winner_reason": string }`
- 시스템 지시는 지금 2단계 프롬프트의 후반부를 옮긴다: 공개된 우열 기준 항목만으로 비교하고, 기준에 없는 요소(구도·조명·배경)로 가르지 않고, 두 사진이 거의 같아도 **반드시 하나를 고른다**(동점 없음). 최소 기준 충족 여부는 묻지도 답하지도 않는다(서버가 이미 확정했다).

프롬프트 인젝션 방어 원칙 7가지(태그 감싸기, 사진 속 글자는 지시가 아니다, 관찰 가능한 사실만, 스키마 재검증, 판정 기준 고정, 정책 차단은 실패, `PROMPT_VERSION` 기록)는 **한 줄도 바꾸지 않고 그대로 적용한다.**

---

## 주기 작업(cron) 구성

| 작업 | 주기 | 명령 | 변경 |
|---|---|---|---|
| `settle-expired-battles` | **1분**(5분→) | `select public.settle_expired_battles();` | 주기 변경 + 함수 재작성 |
| `close-judging-windows` | 1분 | `select public.close_expired_judging_windows();` | **신규** |
| `ai-judge-tick` | 1분 | `select public.sweep_stale_criteria_calls(); select public.dispatch_ai_judgments();` | 명령 교체(`sweep_stale_submissions`·`dispatch_quality_judgments` 폐기) |
| `notify-tick` | (push-notification 4단계) | - | 이 설계에서 만들지 않는다 |

**세 작업을 합치지 않는 이유**는 push-notification design이 `notify-tick`을 따로 둔 것과 같다. 한 작업의 명령 문자열은 한 트랜잭션이라, 판정 창 닫기에서 예외가 나면 같은 tick의 마감 정산까지 되돌아간다. 셋은 서로를 기다릴 이유가 없고 각자 다음 분에 다시 시도하는 안전망이다.

**한 대결의 실패가 다른 대결을 막지 않게** 두 정리 함수는 루프 한 바퀴를 `begin ... exception when others then raise warning ...; end;`로 감싼다. 지금 `settle_expired_battles`는 그렇지 않아 한 대결에서 예외가 나면 그 tick 전체가 죽는다. 판정 창까지 얹히면 실패 지점이 늘어나므로 이번에 고친다(spec "대결이 영영 `active`로 남지 않는다").

---

## 버리는 것의 실제 제거 계획

| 버리는 것 | 어디에 있나 | 조치 |
|---|---|---|
| 제출 즉시 AI 판정 | `supabase/functions/submit-evidence/index.ts`(속도전 분기 전체), `_shared/prompts.ts`·`schemas.ts`의 speed 판정 부분 | Gemini 호출·다운로드·`record_speed_verdict` 호출 삭제. 프롬프트·스키마는 `MIN_CRITERIA_*`로 이름을 바꿔 불복 재판정에서 재사용 |
| `record_speed_verdict(bigint,text,text,text)` | `20260918120000` | `drop function`. **배포된 `submit-evidence`가 이 함수를 부르므로 마이그레이션 적용과 재배포 사이(수십 초) 속도전 제출이 실패한다.** 실사용자가 없어 감수하고, 단계 체크리스트에 "적용 직후 배포"를 명시한다 |
| 판정 5회 상한과 딸린 규칙 | `accept_submission`(`ATTEMPTS_EXHAUSTED`·`JUDGING_IN_PROGRESS`·`passed` 잠금), `speed_outcome`의 `c_max_attempts`, `battle_participants.attempts_used`, `battle_submissions.status`의 `passed/failed/error`, Dart `speedJudgeMaxAttempts`·`submissionStatusLabel`, 문자열 `battleEvidenceAttemptsLeft`·`battleEvidenceExhausted`·`battleEvidenceError*` | 전부 삭제. `accept_submission`은 **인자 시그니처를 유지한 `create or replace`**(6단계 함정 그대로) |
| 불합격 후 재제출 학습 고리 | `evidence_section.dart`의 결과 표시·재촬영 흐름 | 교체 흐름으로 교체(사유가 없으므로 "다시 찍기"만 남는다) |
| 진행 중 상대 합격/불합격 표시 | `battle_participants.last_verdict`·`passed_at`, `battle_summary.dart`의 상태 줄 분기, `battle_detail_screen.dart` 상대 영역, 문자열 `battleListOpponentPassed/Failed`·`battleEvidenceOpponentVerdict` | 컬럼 삭제 + 화면·문자열 삭제. 상대 영역은 "아직 제출 전 / 제출했어요"(**시각 없이**)만 남는다 → `battleEvidenceOpponentSubmitted(time)`도 시각 없는 문구로 교체 |
| 품질전 "두 사진 모이면 곧바로 AI" | `accept_submission`의 `quality_judgments` insert, `submit-evidence`의 `waitUntil` 즉시 실행, `judge-quality`, `dispatch_quality_judgments`, cron 명령 | 두 사진이 모이면 `judging`으로 가는 것은 **유지**하되 잡을 만들지 않고 판정 창을 연다. Edge·잡·디스패처는 위 "재배선" 표대로 교체 |
| 기간 1일/3일/7일 고정 | `battles_duration_hours_check`, `create_battle`의 `not in (24,72,168)`, `schemas.ts`의 `DURATION_HOURS`, `create_battle_screen.dart`의 SegmentedButton, 문자열 `battleDuration1Day/3Days/7Days` | 분 단위로 교체. 문자열은 빠른 선택 칩 라벨로 재사용 |
| 알림 N4, N3의 "품질전 전용" | `docs/specs/push-notification/{spec,design}.md`(아직 구현 안 됨) | 문서 인계만(아래) |

**`create or replace` 시 인자 시그니처를 유지해야 하는 함수**(배포된 Edge Function이 부른다): `accept_submission(uuid, uuid, text, timestamptz)`. **반드시 드롭하고 다시 만들어야 하는 함수**: `create_battle(uuid, integer)`(인자 이름 변경), 위 폐기 목록 전부.

---

## 화면

기존 패턴(`FutureProvider.autoDispose` + `AsyncValue.when`, 실패 시 `debugPrint` + 스낵바, 당겨서 새로고침)을 따른다. 사용자에게 보이는 문자열은 전부 `lib/core/strings.dart`. 서버 오류는 오류 코드로 분기해 문구를 고른다.

### 1. 대결 만들기 (`create_battle_screen.dart` 단계 A 변경)

- 기간 입력: **빠른 선택 칩**(30분 · 1시간 · 1일 · 3일 · 7일) + **"직접 입력"**(정수 입력 + 단위 선택 `분`/`시간`/`일`, 서버에는 항상 분으로 보낸다). 범위 밖이면 입력 즉시 "1분에서 7일 사이로 정해 주세요".
- 안내 두 줄(spec 수용 기준): (a) "마감은 상대가 매칭되는 순간부터 시작돼요."(기존 문구 유지) (b) **"짧은 기간을 고르면 매칭 알림을 놓쳤을 때 손도 못 대고 질 수 있어요."**
- 제출 창/판정 창 구분 안내 한 줄: "기간은 사진을 내는 시간이고, 마감 뒤 24시간 동안 서로 판정해요."
- 상태: 기존과 같음(사전 차단 안내·로딩·AI 실패·한도 초과 분기 모두 유지).

### 2. 모집 목록·모집 상세 시트 (표시만 변경)

- 기간 칩이 분 단위 라벨을 쓴다(`battleDurationLabel`: 1분/30분/1시간/1일/3일/7일/"N분"). 유형 한 줄 설명·기준 목록·생성자 카드·오류 분기는 그대로.

### 3. 내 대결 목록 상태 줄 (`battle_summary.dart` 재작성)

서버 값(`status`, `deadline_at`, `judge_deadline_at`, 내/상대 `has_submitted`·`has_judged`)만으로 한 줄을 고른다. 판정하지 않는다.

| 상황 | 문구 |
|---|---|
| `active`, 상대가 제출했고 나는 아직 | 상대가 제출했어요 |
| `active`, 상대가 제출했고 나도 제출(속도전에서 교체가 잠긴 순간) | 양쪽 다 제출했어요 |
| `active`, 마감 경과 | 마감됨 · 정리 중 |
| `judging`, 내가 아직 판정 안 함 | **판정할 차례예요 · N시간 남음** |
| `judging`, 나는 판정했고 상대는 아직 | 상대 판정을 기다리는 중 |
| `judging`, 양쪽 판정 끝 | AI가 다시 보고 있어요 |
| `judging`, 판정할 상대 증거가 없음(속도전 한쪽만 제출, 내가 제출자) | 상대 판정을 기다리는 중 |

"양쪽 판정이 끝났는데 아직 `judging`"은 AI 잡이 있다는 뜻이다(`resolve_battle`이 마지막 판정과 같은 트랜잭션에서 돌므로 다른 경우가 없다). 그래서 이 줄은 추측이 아니다.

### 4. 대결 상세 (`battle_detail_screen.dart` 대폭 변경)

**공통 헤더**: 유형 배지, 상태 칩(`active`→"진행 중", `judging`→"판정 중"), 상대 카드, 최소 기준 + 품질전 우열 기준(접이식), **시간 두 줄**:
- "사진 마감 · {남은 시간}" (`deadline_at`, 지나면 "마감됨")
- "판정 마감 · {남은 시간}" (`judge_deadline_at`, 창이 열린 뒤에만 보인다)

**제출 창(`active`)**
- 미제출: "사진 찍기" → 미리보기 → "제출". 품질전은 기존 확인 다이얼로그 유지("한 번만 낼 수 있어요").
- 속도전 제출 후, 상대 미제출: 내 사진 + **"사진 바꾸기"** 버튼 + 안내 "상대가 제출하기 전까지 바꿀 수 있어요. 바꾸면 제출 시각이 다시 기록돼요."
- 속도전 제출 후, 상대 제출: 교체 버튼 없음 + 안내 "상대가 제출해서 사진이 잠겼어요."
- 품질전 제출 후: 내 사진 + "제출 완료. 상대가 제출하면 판정이 시작돼요."
- 상대 영역: "아직 제출 전" / **"제출했어요"**(시각·사진·통과 여부 없음).
- 제출 거부 문구: 기존 3종(`CAPTURED_BEFORE_START`, `CAPTURE_TIME_MISMATCH`, `DEADLINE_PASSED`) 유지 + `SUBMISSION_LOCKED`를 "상대가 이미 제출해서 바꿀 수 없어요"로 고친다.

**판정 창(`judging`)** — 아래 화면 5.

**종결 후**
- 결과 배너: 승/패/무/무효/취소. 부제는 서버 기록에서 고른다: 포기(`forfeited_by`), 속도전 완료한 패배, 품질전 한쪽 제출 승리, 무효, 우열 AI 사유(`verdict_reason`). 점수 변화(`score_delta_applied`)는 별도 줄(7단계 선례 유지).
- **양쪽 증거와 판정 내역 공개**: 사진, 최소 기준 결론과 **누가 정했는지**(`verdict_source`: "상대가 인정" / "판정 기한이 지나 자동 인정" / "AI가 다시 보고 판정"), AI 사유(`reason`), 품질전이면 두 사람의 우열 선택.
- 포기 버튼: `active`/`judging`에서만. 문구 통일 유지.

**상태**: 로딩(스켈레톤), 사진 로드 실패(자리 문구), 제출/판정 전송 중(버튼 비활성+스피너), 실패(스낵바·화면 유지).

### 5. 판정 화면 (신규 위젯 `judgment_section.dart`, 상세 안에 표시)

판정 창이 열려 있고 **판정할 상대 증거가 있고** 내가 아직 판정하지 않았을 때만 나온다.

- 공통: 상대 사진(크게), 최소 기준 목록, 안내 "판정은 한 번만 할 수 있어요. 보낸 뒤에는 바꿀 수 없어요."
- **속도전**: 질문 하나 — "이 사진이 최소 기준을 통과했나요?" → [통과했어요] / [통과하지 못했어요]. 불복 버튼 아래 한 줄: "통과하지 못했다고 하면 AI가 다시 봐요."
- **품질전**: 질문 둘을 한 화면에서 답한다 —
  1. "상대 사진이 최소 기준을 통과했나요?" [통과] / [미달]
  2. "우열 기준으로 볼 때 누가 더 잘했나요?" [내가 더 잘했어요] / [상대가 더 잘했어요] (우열 기준 목록을 함께 보여 준다)
  두 답을 모두 고르기 전에는 "판정 보내기"가 비활성이다(서버도 `SUPERIORITY_REQUIRED`로 거부한다).
- 보내기 전 확인 다이얼로그(되돌릴 수 없음), 성공 시 상세·목록 invalidate.
- 자유 텍스트 입력은 **어디에도 두지 않는다**(spec 범위 밖).
- 판정 후: "판정을 보냈어요" + 상대 판정 대기 안내.
- 판정할 것이 없는 사람(속도전 한쪽만 제출의 제출자): "상대가 사진을 내지 않아 판정할 것이 없어요."
- 상태: 사진 로딩/로드 실패(판정 버튼 비활성 — 못 본 사진을 판정하게 하지 않는다), 전송 중, 실패(스낵바), 기한 경과(`JUDGE_WINDOW_CLOSED` → "판정 기한이 지나 자동으로 처리됐어요" + 새로고침).

### 6. 프로필

변경 없음. 점수 + 승/패/무, 기록 목록 라벨(승/패/무/무효), 동의 섹션 그대로.

---

## 데이터 흐름

### 흐름 1. 제출과 교체
1. 카메라(`image_picker`, `ImageSource.camera`) → bytes + `capturedAt`(UTC).
2. Storage 업로드 `battle_evidence/{battle_id}/{user_id}/{uuid}.jpg`(insert 정책: 본인 폴더·참가자·`active`·마감 전·`judging_opened_at is null`).
3. `functions.invoke('submit-evidence', {battle_id, object_path, captured_at})`.
4. Edge → `accept_submission(user, battle, path, captured_at)`. 이 함수가 `battles` 행을 잠그고 `submitted_at = now()`를 찍으며 참가자·동의·`active`·마감 전·경로·촬영 시각(매칭 전/10분)·교체 가능 여부를 본다.
5. 거부 → Edge가 방금 올린 오브젝트 삭제 → `{error: 코드}`.
6. 수락 → `{submission_id, type, replaced_object_path, judging_opened}`. `replaced_object_path`가 있으면 Edge가 그 파일을 지운다.
7. `judging_opened = true`면 클라이언트가 상세를 다시 읽어 판정 창을 그린다. 승패 계산은 하지 않는다.

### 흐름 2. 판정 창 열림
- (a) 양쪽 제출: `accept_submission` 안에서 `judging_gate = open` → `open_judging_window(battle)`(내부 함수)이 `status='judging'`, `judging_opened_at`, `judge_deadline_at`을 한 문장으로 기록.
- (b) 마감: cron → `settle_expired_battles()` → `status='active' and deadline_at <= now()`인 대결마다 `judging_gate`를 보고 `open_judging_window` 또는 `finalize_battle`(품질전 한쪽 제출 승리) 또는 `finalize_battle`(제출 0건 `draw`).

### 흐름 3. 참가자 판정
1. 판정 버튼 → `BattleRepository.submitJudgment(battleId, minVerdict, superiorId)` → RPC `submit_judgment`.
2. 서버: 로그인 가드 → `battles` 잠금 → 참가자 확인(`is distinct from`) → `status='judging'` → `judge_deadline_at > now()` → 상대가 제출했는지(없으면 `NOTHING_TO_JUDGE`) → 이미 판정했는지(`ALREADY_JUDGED`) → 유형별 `superior_id` 검증 → `battle_judgments` insert → `battle_participants.has_judged = true` → `min_verdict='reject'`면 `ensure_ai_judgment_job(battle,'min_criteria',상대)` → `resolve_battle`.
3. 반환: `resolve_battle`이 돌려준 대결 상태. 클라이언트는 그 값을 쓰지 않고 상세를 다시 읽는다(표시 일관성).

### 흐름 4. 판정 기한 경과(자동 승인)
cron `close-judging-windows` → `close_expired_judging_windows()`:
1. `status='judging' and judge_deadline_at <= now()`인 대결을 `for update skip locked`로 돈다.
2. **필요한 판정**(= 상대가 제출한 쪽의 판정)만 `insert ... on conflict do nothing`으로 `{min_verdict:'approve', superior_id:null, auto:true}` 채우고 `has_judged = true`.
3. `resolve_battle`.
4. 아직 `judging`이면 AI 잡이 남아 있다는 뜻이므로 그대로 둔다. **판정 기한이 진행 중인 AI 재판정을 죽이지 않는다**(마감이 판정을 대신하지 않는 것과 같은 원칙). 다음 tick에서 2·3이 멱등하게 다시 돈다.

### 흐름 5. AI 재판정
1. cron `ai-judge-tick` → `dispatch_ai_judgments()` → (a) 임대 만료 정리 → (b) 기한이 된 잡마다 `net.http_post(judge_function_url, {job_id}, header x-judge-secret)`.
2. Edge `judge-dispute` → 시크릿 상수 시간 비교 → `claim_ai_judgment(job_id)`(임대 못 하면 `skipped`).
3. `kind`로 갈라 사진을 내려받고 Gemini 호출(최소 기준 30초 / 우열 60초, 우열은 A/B 섞기).
4. 성공 → `record_min_criteria_verdict` 또는 `record_superiority_verdict` → 그 안에서 `resolve_battle`.
5. 실패(호출·타임아웃·안전 차단·형식 오류·사진 없음) → `record_ai_judgment_failure` → `fail_ai_judgment` → 2·5·10분 뒤 재시도 또는 4회 소진 시 `voided`.

### 흐름 6. 결론(`resolve_battle` 재작성, 시그니처 `uuid → text` 유지)
1. `battles` 잠금. `status not in ('active','judging')`이거나 상대가 없으면 현재 상태 반환(늦게 온 판정이 종결된 대결을 건드리지 않는다).
2. 제출 두 행과 판정 두 행을 읽는다.
3. `min_verdict_effect`로 제출별 최소 기준 결론을 낸다(상대의 판정이 내 제출의 결론이다).
4. `pending`이 있으면 — 불복인데 AI 결과가 없으면 `ensure_ai_judgment_job`으로 보정하고 — `judging`을 반환한다.
5. 속도전 → `mutual_speed_outcome` → `finalize_battle`.
6. 품질전 → `mutual_quality_outcome` → `next='ai'`면 `ensure_ai_judgment_job(battle,'superiority',null)` 후 `judging` 반환, 아니면 `finalize_battle`.
7. `status='active'`로 불렸을 때는 판정이 있을 수 없으므로 아무것도 하지 않고 반환한다(cron이 `judging_gate`로 따로 본다).

### 흐름 7. 포기 / 동의 철회 / 탈퇴
- `forfeit_battle`: 유형·상태(`active`/`judging`) 무관 포기한 쪽 패배. `forfeited_by` 기록, **그 대결의 `ai_judgment_jobs` 삭제**, `finalize_battle`. 늦게 도착한 AI 결과는 `claim`/`record`가 종결 상태를 보고 버린다(기존과 같은 방식).
- `withdraw_ai_consent`: 변경 없음(`forfeit` 경로를 그대로 쓴다).
- `delete_account`: 기존 정의(push 1단계 버전)를 `create or replace`로 이어받아 취소된 대결의 `ai_judgment_jobs`를 지우는 줄만 `quality_judgments` 줄과 교체한다. `battle_judgments`의 내 행은 **남긴다** — 상대의 전적을 설명하는 판정 기록이고 사진·식별 정보가 아니다(제출 행을 남기는 것과 같은 이유).

### 흐름 8. 조회
- 상세: `battles`(id eq) + `battle_participants`(battle_id eq) + `battle_submissions`(battle_id eq) + `battle_judgments`(battle_id eq) — 공개 범위는 RLS가 자른다. 사진은 `createSignedUrl`(Storage 정책이 자른다).
- 목록: `myBattlesProvider`가 참가자 행을 일괄 조회(7단계 `fetchParticipantsOf` 선례) — 상태 줄이 `has_submitted`·`has_judged`를 쓴다.
- 점수·전적·상대 카드: 변경 없음.

---

## API 계약

### 공통 규칙 (CLAUDE.md 코딩 규칙 그대로)
- 앱이 부르는 RPC: `security definer set search_path = public`, 첫 줄 `if auth.uid() is null then raise exception '로그인이 필요합니다.'`, 참가자 검사는 `auth.uid() is distinct from a and auth.uid() is distinct from b`, `revoke execute ... from public, anon` + `grant execute ... to authenticated`.
- Edge/cron 전용 함수: `auth.uid()` 가드를 두지 않고(서비스 롤·cron에 uid가 없어 항상 실패) `revoke execute ... from public, anon, authenticated` + Edge가 부르는 것만 `grant execute ... to service_role`. cron만 부르는 것은 service_role에도 주지 않는다. **각 함수 주석에 이 예외의 이유를 적는다.**
- 내부 전용 함수(`open_judging_window`, `resolve_battle`, `finalize_battle`, `void_battle`, `fail_ai_judgment`, `ensure_ai_judgment_job`, 순수 함수)는 `security invoker` + EXECUTE 전부 회수.
- 새 테이블은 만들 때 RLS를 켜고 정책을 같이 쓴다. 사용자 FK는 전부 `public.profiles(id)`.
- 오류는 `raise exception using message = '<한국어>', hint = '<CODE>'`.

### 오류 코드

| 코드 | 상태 | 발생 위치 | 의미 |
|---|---|---|---|
| `CONSENT_REQUIRED` | 유지 | criteria, create/join, submit | 동의 없음 |
| `PENDING_EXISTS` / `MY_DAILY_LIMIT` / `CREATOR_DAILY_LIMIT` / `CRITERIA_CALL_LIMIT` / `CRITERIA_CHANGED` / `CHECK_INVALID` / `NOT_PENDING` / `ALREADY_MATCHED` | 유지 | 그대로 | 그대로 |
| `CAPTURED_BEFORE_START` / `CAPTURE_TIME_MISMATCH` / `DEADLINE_PASSED` | 유지 | submit | 그대로 |
| `SUBMISSION_LOCKED` | 뜻 변경 | submit | 상대가 제출해 교체 불가 / 품질전 이미 제출 / 판정 창 열림 |
| `JUDGING_IN_PROGRESS` | **삭제** | - | 동기 판정이 없다 |
| `ATTEMPTS_EXHAUSTED` | **삭제** | - | 5회 상한이 없다 |
| `AI_FAILED` | 유지(범위 축소) | criteria | 기준 생성 호출 실패. 재판정 실패는 사용자에게 보이지 않는다(서버가 재시도한다) |
| `JUDGING_NOT_OPEN` | **신규** | judge | 아직 판정 창이 아니다 |
| `JUDGE_WINDOW_CLOSED` | **신규** | judge | 판정 기한이 지났다(자동 승인됨) |
| `ALREADY_JUDGED` | **신규** | judge | 이미 판정했다 |
| `NOTHING_TO_JUDGE` | **신규** | judge | 상대가 제출하지 않아 판정할 증거가 없다 |
| `SUPERIORITY_REQUIRED` | **신규** | judge | 품질전인데 우열 답이 없다 |

### RPC — 앱이 호출 (authenticated)

| 함수 | 파라미터 | 반환 | 조치 |
|---|---|---|---|
| `submit_judgment` | `p_battle_id uuid, p_min_verdict text, p_superior_id uuid` | `text`(호출 뒤 대결 상태) | **신규.** 흐름 3 |
| `create_battle` | `p_check_id uuid, p_duration_minutes integer` | `uuid` | **드롭 후 재생성**(인자 이름 변경) |
| `join_battle` | `p_battle_id uuid, p_criteria_version integer` | void | `create or replace`(분 단위 마감) |
| `list_open_recruits` | - | `setof jsonb` | `create or replace`(`duration_minutes`) |
| `forfeit_battle` | `p_battle_id uuid` | void | `create or replace`(AI 잡 삭제) |
| `delete_account` | - | void | `create or replace`(AI 잡 삭제) |
| `get_my_limits` / `update_battle_criteria` / `cancel_battle` / `get_player_card` / `give_ai_consent` / `withdraw_ai_consent` / `get_consent_withdrawal_impact` | - | - | **변경 없음** |

클라이언트 조회는 기존처럼 테이블 select(`battles`, `battle_participants`, `battle_submissions`, `battle_judgments`, `player_stats`, `ai_consents`).

### RPC — 서버 전용

| 함수 | 호출자 | 권한 | 조치 |
|---|---|---|---|
| `accept_submission(uuid,uuid,text,timestamptz)` | Edge `submit-evidence` | service_role | `create or replace`, **시그니처 유지**. 교체·창 열기 반영, 반환에 `replaced_object_path`·`judging_opened` 추가 |
| `open_judging_window(uuid)` | `accept_submission`, `settle_expired_battles` | 내부 | 신규 |
| `resolve_battle(uuid) → text` | `submit_judgment`, `close_*`, `record_*_verdict`, `settle_*` | 내부 | `create or replace`, 본문 전면 재작성 |
| `settle_expired_battles()` | cron | 회수 | `create or replace`, 재작성(`active`만, `judging_gate`) |
| `close_expired_judging_windows()` | cron | 회수 | 신규 |
| `ensure_ai_judgment_job` / `fail_ai_judgment` / `ai_judgment_backoff` | 내부 | 회수 | 신규(뒤 둘은 `quality_*`에서 옮김) |
| `claim_ai_judgment` / `record_min_criteria_verdict` / `record_superiority_verdict` / `record_ai_judgment_failure` | Edge `judge-dispute` | service_role | 신규 |
| `dispatch_ai_judgments()` / `sweep_stale_criteria_calls()` | cron | 회수 | 신규 |
| `finalize_battle` / `void_battle` | 내부 | 회수 | `void_battle`만 `create or replace`(잡 테이블 이름 교체). `finalize_battle`은 **변경 없음** |
| `record_speed_verdict` / `sweep_stale_submissions` / `claim_quality_judgment` / `record_quality_verdict` / `record_quality_failure` / `fail_quality_judgment` / `quality_judgment_backoff` / `dispatch_quality_judgments` / `speed_outcome` / `quality_outcome` / `quality_deadline_outcome` | - | - | **전부 drop** |

### 판정 규칙 순수 함수 (DB, 테스트 대상)

| 함수 | 반환 |
|---|---|
| `judging_gate(p_type text, p_a_submitted boolean, p_b_submitted boolean, p_deadline_passed boolean)` | `action text` in (`wait`,`open`,`finish_a`,`finish_b`,`draw`) |
| `min_verdict_effect(p_submitted boolean, p_opponent_verdict text, p_ai_meets boolean)` | `text` in (`none`,`pending`,`pass`,`fail`) |
| `mutual_speed_outcome(...)` | `(status, winner, a_outcome, b_outcome)` |
| `mutual_quality_outcome(...)` | `(next, status, winner, a_outcome, b_outcome)` |
| `outcome_score_delta(text)` | **변경 없음** |

참가자 a/b는 호출부에서 `creator/opponent`로 고정 매핑한다(기존 방식 유지).

### Edge Functions

| 함수 | verify_jwt | 입력 | 출력 | 조치 |
|---|---|---|---|---|
| `battle-criteria` | on | `duration_minutes`로 교체 | 그대로 | 검증·프롬프트 태그 수정 |
| `submit-evidence` | on | `{battle_id, object_path, captured_at}` | 200 `{submission_id, replaced, judging_opened, battle_status}` / 422 `{error}` | Gemini 호출 제거, 교체 사진 삭제 추가 |
| `judge-dispute` | **off**(cron 전용, `x-judge-secret` 상수 시간 비교) | `{job_id}` | 200 `{result: 'finished'\|'draw'\|'judging'\|'retry_scheduled'\|'voided'\|'skipped'}` | **신규** |
| `judge-quality` | - | - | - | **삭제**(`supabase functions delete`) |

`supabase/config.toml`: `[functions.judge-quality]` 블록을 `[functions.judge-dispute] verify_jwt = false`로 교체.

시크릿·Vault: `GEMINI_API_KEY`, `GEMINI_MODEL`, `JUDGE_CRON_SECRET`은 그대로 쓴다. Vault `judge_function_url` **값만** 새 함수 URL로 바꾼다(오너). `judge_cron_secret`은 그대로.

---

## 알림 정의 갱신과 인계 (D8)

**이 설계에서 정하는 것은 사건의 정의와 서버에서 확정되는 지점까지다.** 문구, payload, 중복 방지 키, 발송 경로, cron, Edge, 수신 처리는 전부 `push-notification` spec·design 갱신으로 넘긴다. **그 feature의 spec과 design 두 문서를 모두 고쳐야 한다**(spec의 N1~N6 표와 수용 기준, design의 발송 지점 표·문구 표·N6 절·단계 분할).

| 사건 | 조치 | 서버에서 확정되는 지점 | 받는 사람 | 넣지 않는 조건 |
|---|---|---|---|---|
| **N4 속도전 상대 판정 결과** | **폐지** | (사라짐 — `record_speed_verdict`가 없다) | - | - |
| **N3 상대가 사진을 제출** | **두 유형 공통으로 확대** | `accept_submission`에서 `has_submitted`가 false→true로 바뀌는 순간 | 상대 | **교체 제출에는 보내지 않는다**(보내면 교체 횟수·시각이 알림으로 새어 spec의 비공개 규칙을 깬다). 받는 사람이 이미 제출했으면 보내지 않는다(기존 결정 1과 같은 근거 — 그 순간이 곧 판정 창 열림이고 판정 요청 알림이 바로 뒤따른다) |
| **N7 판정 요청** | **신설(두 유형 공통)** | `open_judging_window` 한 곳 — 양쪽 제출·마감 두 경로가 모두 이 함수를 지난다 | 양쪽. 단 **판정할 상대 증거가 있는 사람만**(속도전 한쪽 제출이면 비제출자 1명) | 종결로 직행한 경우(품질전 한쪽 제출 승리, 제출 0건 `draw`)는 창이 열리지 않으므로 애초에 없다 |
| **N6 마감 임박** | **재설계 필요** | cron | 아직 제출하지 않은 참가자 | 전제("기간 최소 24시간")가 깨졌다. 문턱을 기간에 비례시키는 규칙이 필요하고(예: `least(duration_minutes * 비율, 6시간)`), 대상 조건도 바뀐다 — "속도전 미통과"가 아니라 **"미제출"**, "5회 소진 제외"는 삭제, `status='active'`만(이제 `judging`은 제출 창이 끝난 상태다) |
| **N2 종결 결과** | 유지 | `finalize_battle` / `void_battle` | 양쪽 | 그대로. 체감 시점만 늦어진다 |
| **N1 매칭** | 유지(중요도 상승) | `join_battle` | 생성자 | 짧은 대결에서는 이 알림을 놓치면 그대로 진다 |
| **N5 상대 탈퇴 취소** | 유지 | `delete_account` | 남은 사람 | 그대로 |
| 판정 기한 임박 | **만들지 않음** | - | - | spec 범위 밖(D8) |

`notification_outbox.kind` 체크 제약에 `judge_request`를 더하고 `speed_verdict`를 빼는 일도 `push-notification`의 몫이다(그 테이블은 아직 아무도 쓰지 않아 지금 고칠 이유가 없다). 이 설계는 `notification_outbox`·`device_push_tokens`를 **읽지도 쓰지도 않는다.**

---

## 동의·방침 문구 (D9)

### 앱 안 문구

| 문자열 | 현재 | 바꿀 것 |
|---|---|---|
| `aiConsentIntro` | "대결 결과는 AI 심판이 판정해요. 이를 위해 아래 정보를…" | "대결 결과는 먼저 참가자끼리 판정하고, **결론이 나지 않으면 AI가 판정해요.** 이를 위해 아래 정보를 해외 AI 사업자에게 제공해요." |
| `aiConsentItems` | 대결 제목, 판정 기준(품질전은 우열 기준 포함), 증거 사진 | **그대로** |
| `aiConsentRecipient` / `aiConsentPurpose` / `aiConsentRetention` / `aiConsentRefusal` | - | **그대로** |
| (신규) `aiConsentTiming` | 없음 | "제공 시점: 판정 기준을 만들 때(제목·기준), 그리고 **참가자 판정으로 결론이 나지 않았을 때**(증거 사진)" |

동의 자체는 계속 필수다 — 기준 생성에서 제목·기준이 이미 전송되므로 사진이 안 나가는 대결에서도 제공이 일어난다.

### 재동의는 받지 않는다 (오너 확정, 결정 사항 4)

| 판단 근거 | 내용 |
|---|---|
| 제공 항목·받는 자·이용 목적·보유 기간 | **변하지 않는다.** 바뀌는 것은 사진이 전송되는 **조건이 좁아진다**는 사실뿐이다 |
| 정보주체에게 불리한 변경인가 | 아니다. 제공 범위가 줄어드는 방향이다. 재동의를 요구하는 통상의 기준(항목 추가·목적 확대·수령자 추가)에 해당하지 않는다 |
| 지금 구조가 재동의를 강제할 수 있는가 | **못 한다.** 모든 게이트(`join_battle`, `create_battle`, `accept_submission`, `begin_criteria_call`)는 `ai_consents` 행의 **존재**만 본다. 버전 비교 로직이 없다. 강제하려면 버전 검사를 새로 넣어야 하는데 spec에 그런 요구가 없다 |
| 실사용자 | 배포 전이고 동의 이력은 오너·더미 계정뿐이다 |

**조치**: `AiConsentRepository.currentVersion`을 `'2026-09-18'`로 올린다(이후 동의가 새 문구로 기록되게 하는 **기록 목적**). 기존 행을 무효화하거나 버전 검사를 넣지 않는다. 버전 검사를 도입하는 것은 범위 밖이므로 만들지 않는다.

### 저장소 밖 문서 (이 설계의 산출물이 아니다 — 인계 항목)
- 개인정보처리방침의 제3자 제공(국외 이전) 고지에서 "모든 판정 시 증거 사진 제공" → "참가자 판정으로 결론이 나지 않았을 때 제공"으로. **별도 저장소 `C:\workspaces\todododo-legal`과 앱이 링크로 가리키는 게시본을 함께 맞춘다.**
- `DEPLOY.md`의 방침·데이터 보안 항목 확인.
- 이 설계 작업에서는 `docs/specs/mutual-judge/design.md` 밖의 파일을 고치지 않는다. 위 두 항목은 마지막 단계(5단계)의 체크리스트로 남긴다.

---

## 구현 단계 분할

각 단계 끝에 `flutter analyze` 이슈 0 + `flutter test` 통과 + 해당 SQL 테스트(원격, 롤백) 통과 후 커밋한다. **스키마 변경이 있는 단계는 원격 적용 전에 오너 확인을 받는다**(로컬 Docker 없음). 세부 파일 목록·커밋 순서의 최종 확정은 plan.md 영역이다.

| 단계 | 스키마 변경 | 내용 | Edge 재배포 |
|---|---|---|---|
| 1 | **있음(오너 확인)** | 커스텀 마감(분 단위) | `battle-criteria` |
| 2 | **있음(오너 확인)** | 판정 창·제출 교체·상호 판정 기록·자동 승인·결론 규칙 (즉시 AI 판정 제거) | `submit-evidence` |
| 3 | **있음(오너 확인)** | AI 재판정 재배선 | `judge-dispute` 신규 / `judge-quality` 삭제 |
| 4 | 없음 | 판정 화면과 제출 교체 화면 | - |
| 5 | 없음 | 결과·공개·상태 줄·문서·문구 | - |

**1단계 — 기존 데이터 정리 + 커스텀 마감 (스키마 변경 있음)**

*1-a. 기존 대결 삭제* (`..._mutual_judge_reset.sql`, 이 단계의 **첫 파일**) — **오너가 승인했다(2026-09-18, 결정 사항 3).**
- `delete from public.battles;` (cascade로 `battle_participants`·`battle_submissions`·`quality_judgments`·`daily_battle_slots` 관련 행이 함께 사라진다).
- **사라지는 것**(메인 세션이 원격에서 확인한 현재 상태): **진행 중 대결 1건**과 **모집 9건** — 버그 탐색용 더미 모집 8개 + 오너가 만든 "셀카 찍기" 1개.
- **남는 것**: 더미 계정 8개(`%@dummy.invalid`)와 그 `profiles`·`player_stats` 행. `battles` 삭제와 별개이며 지우거나 남기는 것은 오너 판단이고 설계에 영향이 없다. `criteria_checks`·`ai_criteria_calls`·`ai_consents`도 남긴다(대결에 묶이지 않은 기록이고 옛 규칙과 어긋나지 않는다).
- Storage 사진은 SQL로 지울 수 없다(`storage.protect_delete()`). 마이그레이션 적용 직후 `supabase storage rm -r ss:///battle_evidence/ --linked --experimental`로 비운다 — plan에 체크리스트로 남긴다(ai-judge 1단계와 같은 절차).
- 선별 삭제를 하지 않는 이유: 옛 행에는 제출 즉시 판정 시절의 `battle_submissions.status`(`passed`/`failed`/`error`)와 5회 이력이 있어 새 스키마에서 뜻이 없고, 진행 중이던 1건은 2단계에서 추가되는 판정 창 컬럼이 비어 있어 어느 cron도 정리하지 못한다.

*1-b. 커스텀 마감*
- 파일: `supabase/migrations/..._custom_duration.sql`(`duration_minutes` 이전, `battles_duration_minutes_check`, `create_battle` drop+재생성, `join_battle`·`list_open_recruits` 재정의, cron `settle-expired-battles` 1분으로 갱신), `supabase/functions/_shared/{schemas.ts,prompts.ts}` + 두 테스트, `lib/features/battle/data/battle.dart`·`battle_repository.dart`·`battle_criteria_repository.dart`, `presentation/{create_battle_screen.dart,battle_chips.dart,recruit_detail_sheet.dart,battle_recruits_screen.dart,edit_recruit_criteria_screen.dart}`, `lib/core/strings.dart`, `test/**`.
- 커밋: `chore: 옛 판정 규칙 대결 데이터 정리` / `feat: 대결 기간을 분 단위 커스텀으로` / `feat: 짧은 기간 경고와 기간 입력 화면`(화면은 따로).
- 검증: 스모크 `ok=t`(1분·30분·10080분 생성, 0분·10081분 거부, 매칭 시 `deadline_at`이 분 단위로 정확), `deno test`(분 범위 검증·프롬프트 태그), 실기기에서 1분 대결을 만들어 매칭 → 1분 뒤 cron이 정산하는 것 확인.
- 1-a가 `battles`를 비우므로 `duration_hours → duration_minutes` 이전 `update`는 실제로 0행을 고친다. 그래도 문장을 남긴다 — 마이그레이션은 행이 있는 환경에서도 같은 결과를 내야 하고, 1-a를 빼고 되돌릴 수 있어야 한다.
- 이 단계는 판정 구조를 건드리지 않는다. 적용 후에도 옛 판정(즉시 AI·5회)이 그대로 돌아가야 한다.

**2단계 — 판정 창·교체·상호 판정 (스키마 변경 있음)**
- 파일: `supabase/migrations/..._judging_window.sql`(`battles` 3컬럼·제약·인덱스, `battle_participants` 컬럼 교체, `battle_submissions` 재편, `battle_participants` 정책 `participants can view their battle progress`는 **유지하고 불변식 주석만 추가**, `battle_judgments` + RLS, 순수 함수 4개 생성 + 옛 3개 drop, `open_judging_window`·`resolve_battle`·`settle_expired_battles`·`close_expired_judging_windows`·`submit_judgment`, `accept_submission` 재정의(시그니처 유지), `record_speed_verdict`·`sweep_stale_submissions` drop + `sweep_stale_criteria_calls` 신설, Storage 정책 교체, cron `close-judging-windows` 등록·`ai-judge-tick` 명령 갱신), `supabase/functions/submit-evidence/index.ts`, `supabase/tests/{mutual_judge_rules.sql,mutual_judge_flow_smoke.sql}` + 기존 스모크 4개 교체, Dart 모델·도메인(`battle_submission.dart`, `battle_participant.dart`, `battle_detail.dart`, `battle_summary.dart`, `submission_rules.dart`)과 관련 테스트.
- 커밋: `feat: 판정 창과 상호 판정 기록 스키마` / `feat: 속도전 제출 교체` / `refactor: 제출 즉시 AI 판정 제거`.
- **이 단계만 적용해도 규칙이 성립한다**: 판정 화면이 없으므로 모든 대결이 24시간 뒤 자동 승인으로 종결된다(속도전은 제출 시각으로, 품질전은 우열 미답 `draw`). 중간에 멈춘 상태가 아니라 "아무도 판정하지 않는 경우"와 같은 경로다. 화면은 판정 창을 안내만 한다("판정 기능은 준비 중" — 5단계 선례와 같은 방식).
- 검증: 규칙 테스트 전 케이스 통과, 흐름 스모크 `ok=t`(아래 테스트 전략), 진행 중 상대 사진 서명 URL 발급 실패·상대 제출 행 0행(두 번째 계정), 판정 창에서는 같은 쿼리가 1행.
- **적용 직후 `submit-evidence` 재배포**(옛 함수가 `record_speed_verdict`를 부른다).

**3단계 — AI 재판정 (스키마 변경 있음)**
- 파일: `supabase/migrations/..._ai_rejudgment.sql`(`ai_judgment_jobs` + RLS, `ai_judgment_backoff`·`fail_ai_judgment`·`ensure_ai_judgment_job`·`claim_ai_judgment`·`record_min_criteria_verdict`·`record_superiority_verdict`·`record_ai_judgment_failure`·`dispatch_ai_judgments`, `submit_judgment`·`resolve_battle`에 잡 배선, `void_battle`·`forfeit_battle`·`delete_account` 재정의, `quality_judgments` 관련 전부 drop, `ai-judge-tick` 명령 갱신), `supabase/functions/judge-dispute/index.ts`, `_shared/{dispute_judge.ts,prompts.ts,schemas.ts}` + 테스트, `supabase/config.toml`.
- 커밋: `feat: 불복·우열 불일치 AI 재판정`.
- 검증: `deno test`(우열 응답 검증·승자 누락=실패·A/B 역매핑·최소 기준 응답 검증·프롬프트에 최소 기준과 우열 기준이 섞이지 않음), 스모크(불복 1건 → 잡 1개, 양쪽 불복 → 잡 2개, 우열 불일치 → 잡 1개, 4회 실패 → `voided` + 오늘 슬롯만 반환, 임대 만료 = 실패 1회, 포기·탈퇴 시 잡 삭제), 오너가 Vault URL 교체 후 `functions deploy judge-dispute` → 두 계정으로 불복 1건 실호출 확인 → `functions delete judge-quality`.

**4단계 — 판정 화면과 교체 화면 (스키마 변경 없음)**
- 파일: `lib/features/battle/presentation/{judgment_section.dart,evidence_section.dart,battle_detail_screen.dart}`, `domain/{judgment_rules.dart,battle_detail.dart}`, `data/battle_repository.dart`, `lib/core/strings.dart`, 위젯·유닛 테스트.
- 커밋: `feat: 상호 판정 화면` / `feat: 제출 교체 화면`(화면 하나 = 커밋 하나).
- 검증: 위젯 테스트(속도전 2버튼, 품질전 4버튼과 둘 다 고르기 전 비활성, 사진 로드 실패 시 판정 비활성, 판정 후 대기 안내, 판정할 것이 없는 사람 안내, 교체 버튼이 상대 제출 여부로 나타나고 사라짐), 실기기에서 두 계정으로 승인/불복 각각 한 번.

**5단계 — 결과·공개·문서 (스키마 변경 없음)**
- 파일: `battle_detail_screen.dart`(종결 후 양쪽 증거·판정 내역·`verdict_source` 표시), `battle_summary.dart`(상태 줄 표), `lib/core/strings.dart`(미사용 문자열 삭제 — 5회·합격/불합격·기간 3종), `CLAUDE.md`(위 조항 대조표의 **대체** 행만), `docs/specs/push-notification/{spec,design}.md` 갱신 인계 메모, `DEPLOY.md`·`TODO_BACKLOG.md`.
- 커밋: `feat: 종결 후 판정 내역 공개` / `docs: 상호 판정 기준으로 도메인 규칙 갱신`.
- 검증: spec 수용 기준 전 항목 수동 체크리스트, `grep`으로 앱·서버에 5회·합격표시·`duration_hours` 참조 0건, 미사용 `AppStrings` 0건.
- 오너 몫: 개인정보처리방침(`todododo-legal`)과 게시본 문구, Play Console 데이터 보안 확인.

---

## 테스트 전략

| 무엇 | 어디서 | 수단 |
|---|---|---|
| 판정 창 열림 규칙, 최소 기준 결론, 속도전·품질전 결론, 점수 변화 | DB 순수 함수 | `supabase/tests/mutual_judge_rules.sql` — 테이블 구동 케이스(원격 `supabase db query --linked -f`, 마지막에 예외로 롤백). 로컬 Docker가 없어 이 방식이 유일한 실행 수단 |
| 전이 적용(창 열기·자동 승인·즉시 종결·교체·경합·잡 생성·무효·슬롯 반환·포기·탈퇴) | DB 전이 함수 | `supabase/tests/mutual_judge_flow_smoke.sql`(가짜 사용자 2명, 서버 전용 함수 직접 호출, 롤백) |
| 기존 스모크 | DB | `settle_expired_battles_smoke.sql`·`resolve_battle_smoke.sql`·`ai_judge_flow_smoke.sql`을 새 규칙으로 **교체**. `forfeit_battle_smoke.sql`·`delete_account_smoke.sql`·`criteria_smoke.sql`·`join_battle_smoke.sql`·`ai_consent_smoke.sql`·`push_token_smoke.sql`은 `duration_minutes`와 새 컬럼에 맞춰 최소 수정 |
| AI 응답 검증·프롬프트 조립·A/B 역매핑·분 단위 입력 검증·상수 시간 비교 | Edge 순수 함수 | `deno test supabase/functions/_shared/` — Gemini를 부르지 않는다(기존 선) |
| 기간 라벨·분 변환, 제출/교체/판정 가능 판단, 상태 줄, 결과 라벨 | Dart 순수 함수 | `flutter test` 유닛 |
| 판정 화면·교체 화면·종결 후 공개 | Dart 위젯 | `flutter test`(가짜 `BattleRepository`·`evidenceCameraProvider`) |
| 실제 카메라·서명 URL·실호출·짧은 대결 체감 | 실기기 | 오너 수동 체크리스트 |

**규칙을 Dart에 복제해 테스트하지 않는다.** CLAUDE.md "판정 로직은 반드시 유닛 테스트"는 위 SQL 규칙 테스트로 충족하고, `flutter test`는 표시·활성화 판단만 덮는다.

### 규칙 테스트 필수 케이스

`judging_gate`: 위 표 6행 그대로 + 양쪽 제출인데 마감 전(→`open`).

`min_verdict_effect`: 위 표 6행 그대로.

`mutual_speed_outcome`:
| # | a | b | 기대 |
|---|---|---|---|
| 1 | pass t1 | pass t2 (t1<t2) | a win / b completed_loss |
| 2 | pass t2 | pass t1 | b win / a completed_loss |
| 3 | pass t1 | pass t1(동률, seq a<b) | a win |
| 4 | pass | fail | a win / b loss |
| 5 | pass | none | a win / b loss |
| 6 | fail | fail | draw / draw |
| 7 | fail | none | draw / draw |
| 8 | none | none | draw / draw (창이 열리지 않는 경우의 방어적 처리) |

`mutual_quality_outcome`: 위 표 10행 그대로 + `pass/pass`에 픽이 참가자가 아닌 값(방어적으로 `ai`가 아니라 예외가 나야 함은 호출부 검증 몫).

### 흐름 스모크 필수 확인
양쪽 제출 시 마감 전 `judging` 전이와 `judge_deadline_at` 계산 / 마감 시 속도전 1건 제출은 창 열림·품질전 1건 제출은 즉시 제출자 승리·0건은 `draw` / 속도전 교체가 `submitted_at`을 갱신하고 상대 제출 후에는 `SUBMISSION_LOCKED` / 품질전 두 번째 제출 거부 / 판정 1회 제한(`ALREADY_JUDGED`) / 속도전에 `superior_id`를 넣으면 거부, 품질전에 빼면 `SUPERIORITY_REQUIRED` / 양쪽 판정 즉시 종결(24시간 대기 없음) / 기한 경과 자동 승인이 **필요한 판정만** 채움 / 자동 승인으로 인정된 완료가 `completed_loss` 감면을 받음 / 불복 → 잡 생성 → AI `pass`가 사람의 불복을 뒤집음 / 우열 불일치 → 잡 1개 → 승자 확정 / 4회 실패 → `voided` + 오늘 슬롯만 반환(어제 매칭은 유지) / 점수 하한 0(`score_delta_applied = 0`) / 포기·동의 철회·탈퇴가 잡을 지우고 규칙대로 끝냄 / 어떤 경로도 `disputed`를 만들지 않음.
권한·공개 범위: anon으로 `submit_judgment` 권한 오류, authenticated로 서버 전용 함수 권한 오류, 창 열리기 전 상대 `battle_submissions` 0행·`battle_judgments` 0행, 창 열린 뒤 제출 1행·판정 0행, 종결 후 판정 1행.

---

## 오너가 손수 해야 할 일 (순서대로)

1. 각 스키마 단계(1·2·3)의 원격 적용 승인. 적용은 단계 순서를 지킨다.
2. 2단계 적용 **직후** `supabase functions deploy submit-evidence`.
3. 3단계 적용 후 Supabase 대시보드 Vault에서 `judge_function_url` 값을 `https://<project-ref>.supabase.co/functions/v1/judge-dispute`로 교체(`judge_cron_secret`은 그대로).
4. `supabase functions deploy judge-dispute` → 실호출 확인 후 `supabase functions delete judge-quality`.
5. (선택) 더미 계정 8개(`%@dummy.invalid`) 정리. 1단계가 `battles`를 비우지만 계정 자체는 남는다 — 지우거나 남기는 것은 오너 판단이고 설계에 영향이 없다.
6. 5단계: 개인정보처리방침(`C:\workspaces\todododo-legal`과 게시본) 문구 갱신.

새 시크릿은 없다. Gemini 키·모델·cron 시크릿은 지금 값을 그대로 쓴다.

---

## 결정 사항

2026-09-18 오너가 초안의 "결정 필요" 4건에 모두 답했다(초안의 추천안 전부 채택). **미결 항목은 없다.**

1. **판정 기한은 "창이 열린 시각 + 24시간"이다.** 양쪽이 마감보다 일찍 제출해 창이 먼저 열려도 창의 길이는 24시간이다.
   - 근거: spec 본문이 "판정 창은 24시간이다"라고 못박았고, "원래 마감 + 24시간"으로 두면 7일 대결에서 3분 만에 양쪽이 제출했을 때 창이 8일 가까이 열려 "24시간"이라는 설명이 사실과 어긋난다. 보통의 경로(마감에 창이 열림)에서는 두 값이 같다. 반영: "판정 창의 세 시점" 절의 계산 경로 표 — 두 컬럼에 값을 넣는 곳은 `open_judging_window` 하나뿐이다.
2. **품질전 판정은 최소 기준과 우열 두 질문을 모두 답해야 한다.** 우열 건너뛰기 버튼은 없고, 서버가 `SUPERIORITY_REQUIRED`로 거부한다. spec 결론표의 "한쪽만 답함"·"양쪽 다 미답"은 **판정 자체를 하지 않은 사람**을 뜻한다(우열만 건너뛴 경우는 존재하지 않는다).
   - 근거: spec이 "두 질문을 한 번에 답한다(왕복을 늘리지 않는다)"고 적었고, 건너뛰기를 허용하면 "최소 기준만 불복하고 우열은 안 답하기"가 무비용 전략이 되어 `draw`를 유도하는 경로가 생긴다. 반영: 화면 5, 오류 코드 표, `submit_judgment` 계약, 흐름 스모크 필수 확인.
3. **1단계 첫 마이그레이션에서 기존 `battles`를 전부 삭제한다**(`delete from public.battles`, cascade) + Storage `battle_evidence`를 비운다(ai-judge 1단계 선례).
   - 근거: 옛 행에는 제출 즉시 판정 시절의 `battle_submissions.status`(`passed`/`failed`/`error`)와 5회 이력이 있어 새 스키마에서 뜻이 없고, 진행 중이던 대결은 판정 창 컬럼이 비어 있어 어느 cron도 정리하지 못한다. 사라지는 것과 남는 것의 실제 숫자는 "1단계" 절에 적었다.
4. **AI 데이터 제공 동의는 버전 문자열만 올리고 재동의를 받지 않는다.** `AiConsentRepository.currentVersion`을 `'2026-09-18'`로 올려 이후 동의가 새 문구로 기록되게 하고, 기존 행을 무효화하거나 버전 비교 게이트를 넣지 않는다.
   - 근거: 제공 항목·받는 자·이용 목적·보유 기간이 변하지 않고 사진이 전송되는 조건만 좁아지므로 정보주체에게 불리한 변경이 아니다. 버전 비교 게이트는 spec 범위 밖이다. 반영: "동의·방침 문구(D9)" 절.
