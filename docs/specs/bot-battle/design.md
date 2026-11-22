# bot-battle 설계

## 참고

- spec.md: `docs/specs/bot-battle/spec.md` — **이 설계의 유일한 요구사항이다.** 오너 결정 1~6은 전제이고 선택지로 다시 열지 않는다. 합격선(호출 0회·새 상태 없음·새 kind 없음·캐시 미접촉·서버가 승패 결정)은 §16에서 조항별로 어디서 지켜지는지 대조했다.
- 가장 중요한 선행 설계: `docs/specs/mutual-judge/design.md`(판정 창·`judging_gate`·`resolve_battle`·`finalize_battle`·`open_judging_window`·cron 구성). **봇전은 그 기계에 얹히는 것이고 새 판정 기계를 만들지 않는다.** 결론 규칙(`mutual_speed_outcome`)도 한 줄 고치지 않는다.
- `docs/specs/criteria-cache/design.md` — 봇전이 **읽지도 쓰지도 않는** 캐시. 그 테이블의 보안 성질("AI 원본만 들어온다")이 적재 호출의 **위치**(Edge `battle-criteria`의 generate 성공 경로 한 자리)로 지켜지므로, 봇전이 그 경로를 지나가지 않는다는 사실만으로 접촉이 0이다(§2.7).
- `docs/specs/push-notification/{spec,design}.md`, `docs/specs/notification-inbox/design.md` — 알림 7종과 두 자리 문구 규칙. **N6(마감 임박) 적재 지점은 아직 없다**(push 6단계 미구현, §9·결정 필요 2).
- 읽어서 확인한 현재 구현(추측이 아니다):
  - `supabase/migrations/20260818220100_battles.sql`(battles·battle_participants DDL과 두 select 정책, `battles_create_participants` 트리거는 `20260818220200`·`20260820160000`), `20260902213000_delete_account.sql:18`(`profiles.id`의 `auth.users` FK 해제 — 봇 profiles 행이 구조적으로 가능한 근거), `20260915120100_ai_judge_schema.sql`(`battle_submissions`·`player_stats`), `20260915120200`(`outcome_score_delta`), `20260915120300`(`finalize_battle`·`void_battle`), `20260916120000_ai_consent.sql`(동의 게이트·`withdraw_ai_consent`), `20260916130000_ai_criteria.sql`(`is_criteria_list`·`begin_criteria_call`의 KST 한도 처리·`create_battle`), `20260917120000`(`get_player_card`), `20260922120000_judging_window.sql`(판정 창·`judging_gate`·`accept_submission`·`close_expired_judging_windows`), `20261028120000_recruit_browse.sql`(`list_open_recruits`), `20261029120000_ai_rejudgment.sql`(최신 `resolve_battle`), `20261103120000_notification_events.sql`(최신 `open_judging_window`·`finalize_battle`·`accept_submission`·`delete_account`·`enqueue_notification` 호출 지점), `20261106120000_remove_battle_limits.sql`(**`daily_battle_slots` 테이블은 드롭됐다**), `20261111120000_criteria_cache.sql`.
  - `supabase/functions/submit-evidence/index.ts`(accept_submission만 중계한다 — 봇전 때문에 바뀌지 않는다), `_shared/notification_text.ts`, `_shared/prompts.ts`(기준 문장의 말투·길이 규칙).
  - `lib/features/battle/**`(`battle_repository.dart`·`battle_providers.dart`·`battle_detail.dart`·`battle_summary.dart`·`judgment_rules.dart`·`evidence_section.dart`·`battle_detail_screen.dart`·`battle_chips.dart`·`my_battles_screen.dart`·`battle_recruits_screen.dart`), `lib/features/profile/**`(`profile_repository.dart`·`battle_records_screen.dart`), `lib/core/strings.dart`.
- 전제: mutual-judge 1~5단계, ai-rejudgment, push-notification 1~5단계, notification-inbox, criteria-cache가 **원격에 적용돼 돌고 있다.** cron 작업 네 개(`settle-expired-battles`·`close-judging-windows`·`ai-judge-tick`·`notify-tick`)가 전부 **1분** 주기다(CLAUDE.md의 "5분"은 옛 값이다 — `20260921120100_custom_duration.sql:271`에서 1분으로 갱신됐다). 로컬 Docker가 없어 마이그레이션은 원격에 적용하며 **단계마다 오너 확인**을 받는다(§15).

---

## 설계 원칙 (전체를 관통하는 6가지)

1. **새 판정 기계를 만들지 않는다.** 봇전의 네 결과(승 / 완료한 패배 / 완료 못 한 패배 / 포기)는 전부 기존 `judging_gate` → `min_verdict_effect` → `mutual_speed_outcome` → `finalize_battle` 사슬이 그대로 낸다. 봇전이 더하는 것은 **입력 두 개**뿐이다 — (a) 제출 시각이 `t_bot`인 사진 없는 봇 제출 행, (b) 판정 창이 열리는 순간 채워지는 자동 승인 두 행.
2. **결과는 `t_bot`에 정해지고, 기록은 그보다 늦게 쓰일 수 있다.** 승자는 `submitted_at` 비교로 정해지므로 **정산이 언제 돌든 결과가 바뀌지 않는다**(§1.7). 그래서 "사용자가 화면을 봐야 결과가 나온다"가 아니고, 화면을 보면 **더 빨리 보인다**가 전부다.
3. **`t_bot`은 클라이언트가 어떤 쿼리로도 얻을 수 없다.** `battles` 행은 참가자가 전 컬럼을 읽으므로(`participants can view their battles`) 거기에 둘 수 없다. `battle_submissions`의 기존 select 정책이 "판정 창이 열리거나 종결된 뒤에만 상대 행"이라는 **정확히 필요한 시점 분기**를 이미 갖고 있어 그 행에 둔다(§1.4).
4. **봇은 등장인물이 아니라 시계다.** 성격·말투·전적·점수가 없고, 사람처럼 보이는 자리에 나타나지 않는다. RLS로는 막을 수 없으므로 **걸러야 하는 자리를 전수로 적고 각각을 막는다**(§7).
5. **AI와 닿는 경로를 지나가지 않는다.** 기준은 seed 테이블에서 복사하고(증서·캐시·임베딩 없음), 사진은 아무도 보지 않으며, 재판정 잡이 생기는 조건(`min_verdict = 'reject'`)에 도달하는 경로가 없다(§3.4).
6. **봇전 때문에 사람 대결이 한 줄도 달라지지 않는다.** 고치는 기존 함수는 여섯 개뿐이고(§6.3) 전부 `if is_bot then ... end if` 분기를 **더하는** 모양이다. 사람 대결 경로의 조건·점수·문구는 그대로다.

---

## CLAUDE.md 도메인 규칙 대조

| # | 조항 | 판단 | 봇전에서 |
|---|---|---|---|
| 1 | 유형은 `speed`/`quality` 둘, 둘 다 승자가 있다 | 유지 | 봇전은 **`speed` 전용**(spec 2번). 품질전 봇전과 그 추상화를 만들지 않는다 |
| 2 | 판정은 1차 상호 판정 + 2차 AI 재판정 | 유지(+예외) | 1차가 **양쪽 자동 승인**으로 즉시 채워지고 2차는 도달하지 않는다. "미판정은 승인으로 간주"라는 확정 조항을 그대로 쓴 것이고 새 규칙이 아니다 |
| 3 | 증거는 앱 카메라 사진만, 촬영 시각 서버 대조 | 유지 + **예외 1건** | 사용자 쪽은 한 글자도 안 바뀐다. **봇의 제출만** 사진·촬영 시각이 없다(spec이 허용한 유일한 예외). 사람이 그 경로를 쓸 수 없다는 보증은 §2.4 |
| 4 | 기준은 AI가 만들고 생성자가 확정, `criteria_version` | **대체(봇전만)** | 봇전 기준은 **운영자 seed**다. `criteria_version`은 1로 고정되고 바뀌지 않는다(`update_battle_criteria`는 `status='pending'`을 요구해 봇전에 도달하지 않는다) |
| 5 | 판정 창은 제출이 더 못 바뀐 뒤 열린다 | 유지 | "양쪽 제출 또는 마감 중 먼저"가 봇전에서 "`t_bot`(사용자가 이미 냈으면) 또는 마감"이 된다 |
| 6 | 판정 기한 24시간, 미판정은 승인 | 유지 | 창이 열리는 순간 자동 승인이 채워지고 같은 트랜잭션에서 종결되므로 **24시간이 한 번도 걸리지 않는다**(`close_expired_judging_windows`는 안전망으로만 남는다) |
| 7 | 상태 전이 `pending→active→judging→finished…`, 새 상태 금지 | 유지 | `pending`을 거치지 않고 `active`로 시작한다. `judging`은 거치지만 머물지 않는다. **새 상태 없음** |
| 8 | 공개 범위: 마감 전에 보이는 것은 "제출했다"는 사실뿐 | 유지 | `t_bot` 전에는 봇의 제출 행도 `has_submitted`도 보이지 않는다(§1.4·§2.5) |
| 9 | 마감은 판정을 대신하지 않는다 / 바뀔 수 없으면 즉시 종결 | 유지 | 후자가 "사용자가 `t_bot` 뒤에 처음 제출하면 그 자리에서 끝난다"로 나타난다(결정 필요 1) |
| 10 | 점수표(승 +3 …), 하한 0, 랭킹 없음 | **봇전 전용 표 추가** | `outcome_score_delta`를 **한 줄도 고치지 않고** `bot_outcome_score_delta`를 따로 둔다(§3.5). 하한 0은 그대로 |
| 11 | `draw`/`voided`/`disputed`를 합치지 않는다 | 유지 | 셋 다 봇전에서 **도달 불가**다(증명 §3.4) |
| 12 | 한도는 기준 생성 10회 하나뿐 | **한도 1종 추가** | 봇전 하루 3회. 기준 생성 10회와 **완전히 별개**이고 1회도 소비하지 않는다(§5) |
| 13 | 동의 전에는 기준 생성·대결 생성·참가를 막는다 | **대체(봇전만)** | 봇전은 동의 없이 가능. 막는 자리는 그대로 두고 `accept_submission`에만 분기를 넣는다(§8) |
| 14 | 대결은 주제 모집·자동 매칭 | **대체(봇전만)** | 봇전은 모집을 거치지 않는다(spec 5번). 봇은 모집을 만들지도 참가하지도 않는다 |
| 15 | 빠져나가는 길은 포기뿐 | 유지 | `forfeit_battle` 그대로(유형·상대와 무관). `cancel_battle`은 도달 경로가 없다 |
| 16 | 2인만 | 유지 | 봇은 한 마리, 2인 구조 그대로 |
| 17 | 판정 로직은 DB/Edge, 화면은 표시만 | 유지 | 클라이언트가 더하는 것은 "지금 다시 봐 달라"는 멱등 RPC 한 번뿐이고 판단 입력이 없다(§1.3) |
| 18 | 사용자 FK는 `public.profiles` | 유지 | 새 테이블(`bot_battle_topics`)은 사용자 FK가 없다. 봇은 `profiles` 행 하나를 갖는다 |
| 19 | 탈퇴는 묘비, 끝나지 않은 대결은 `cancelled` | 유지 | 봇전도 `cancelled`가 된다. 봇에게는 알릴 것이 없다(§7-3) |

---

## 1. 핵심 난점 — 봇의 제출을 누가 언제 기록하는가

### 1.1 문제

`t_bot`은 시각일 뿐이고 **봇에게는 제출이라는 행위를 하는 주체가 없다.** 사람 대결에서 "판정 창을 열어라"의 트리거는 제출 행위(`accept_submission`)인데 봇전에는 그 호출자가 없다. 그런데 spec은 다음을 동시에 요구한다.

> 봇전은 판정 창이 열리는 시점(= `t_bot` 또는 마감)에 끝난다. 그보다 일찍 끝나지 않고, 그보다 늦게도 끝나지 않는다.

`settle_expired_battles()`는 **마감**만 본다. 마감까지 기다리면 "15분 봇전인데 `t_bot`이 10분이었다"에서 5분 늦게 끝난다. cron 주기(1분)도 그 자체로는 `t_bot`을 모른다.

### 1.2 후보와 판단

| 후보 | 내용 | 판단 |
|---|---|---|
| **(a) 시작 때 봇 제출 행을 미리 넣는다** | 매칭(=시작) 순간 `battle_submissions`에 봇 행을 넣고 `submitted_at = t_bot`으로 박는다 | **채택.** 공개 범위가 깨질 위험은 **기존 select 정책이 이미 막는다**(§1.4에서 증명). 다만 "양쪽 제출"을 `exists`로 세는 자리가 봇전에서 거짓이 되지 않게 `accept_submission` 한 곳만 시각을 보게 고친다(§1.5의 표) |
| **(b) `t_bot`에 lazy 실체화** | 사용자가 화면을 열거나 제출할 때 "이제 지났으니 기록하고 정산" | **부분 채택(보조 수단).** 단독으로는 "아무도 안 열면 결과가 안 난다"가 되는데, (a)와 함께 쓰면 **결과는 이미 데이터로 정해져 있고** 실체화는 기록 시점만 당긴다. 그래서 "승패를 클라이언트가 정한다"가 되지 않는다(§1.7) |
| **(c) `t_bot`에 맞춘 일회성 예약** | pg_net 지연 호출 / cron 주기 상향 | **cron 1분만 채택.** pg_net은 즉시 발송만 되고 지연 수단이 없다. `pg_sleep`으로 기다리는 작업은 커넥션을 붙잡는다. pg_cron 1.5+의 초 단위 주기(`'15 seconds'`)는 **지연을 15초로 줄일 수 있는 나중의 손잡이**로만 적어 둔다 — 지금은 다른 네 작업과 같은 1분으로 맞춰 운영 그림을 하나로 둔다(확인 질의: `select extversion from pg_extension where extname = 'pg_cron'`) |
| (d) 봇도 Edge Function이 "제출"한다 | cron이 Edge를 깨워 봇 제출을 올린다 | **버린다.** 사진이 없어 업로드할 것이 없고, 진입점과 시크릿이 늘어난다. DB 안에서 끝나는 일에 HTTP를 넣을 이유가 없다 |
| (e) `t_bot`을 `battles`에 둔다 | 컬럼 하나로 끝난다 | **불가.** 참가자가 `battles` 전 컬럼을 읽으므로 `t_bot`이 그대로 새고, "미리 보여 주지 않는다"가 깨진다(§1.4) |

### 1.3 고른 설계 — 한 줄 요약

> **봇 제출 행은 시작할 때 미리 넣고(제출 시각 = `t_bot`), 종결은 "판정 창이 열리는 순간"에 한다. 판정 창을 여는 유일한 지점(`open_judging_window`)이 봇전이면 자동 승인 두 행을 채우고 같은 트랜잭션에서 `resolve_battle`을 부른다.**

그래서 "판정 창이 열린다 = 봇전이 끝난다"가 **한 함수 안의 사실**이 되고, 창을 여는 세 경로가 전부 그 효과를 얻는다.

| 창을 여는 경로 | 언제 | 봇전에서 열리는 조건 | 결과 |
|---|---|---|---|
| `accept_submission`(사용자 제출) | 사용자가 `t_bot` **뒤**에 처음 제출 | 양쪽 제출 성립 | 그 자리에서 종결(완료한 패배) |
| `settle_due_bot_battles()` cron(신규, 1분) + `settle_my_bot_battles()`(화면이 부른다) | `t_bot`이 지났고 사용자가 **이미** 제출함 | 양쪽 제출 성립 | 그 자리에서 종결(사용자 승리) |
| `settle_expired_battles()` cron(기존, 1분) | 마감 | 한쪽만 제출(봇) | 그 자리에서 종결(완료 못 한 패배) |

세 경로 중 **어느 것도 승패를 계산하지 않는다.** 전부 `resolve_battle`을 부르고, 거기서 `mutual_speed_outcome`이 `submitted_at` 비교로 답을 낸다.

### 1.4 `t_bot`을 어디에 둘 수 있는가 — RLS 수준의 확인

| 자리 | 참가자(사용자)가 읽는가 | 판단 |
|---|---|---|
| `battles`의 새 컬럼 | **읽는다.** 정책 `participants can view their battles` = `using (auth.uid() in (creator_id, opponent_id))`로 **행 전체**를 내준다. 컬럼 단위로 가릴 수단이 RLS에 없다 | **쓸 수 없다** |
| `battle_participants`의 새 컬럼 | **읽는다.** 정책이 `user_id`로 좁히지 않아 상대 행까지 전부 보인다(그 테이블 주석이 못박은 불변식) | **쓸 수 없다** |
| **`battle_submissions`의 봇 행** | **판정 창이 열리거나 종결된 뒤에만** 읽는다(정책 `users can view own submissions or judging or finished battle submissions`: `user_id = auth.uid() or (참가자 and (judging_opened_at is not null or status in (finished,draw,voided,cancelled,disputed)))`) | **여기에 둔다** |
| 정책 0개인 새 테이블 | 안 읽는다 | 가능하지만 **진실이 두 곳에 생긴다**(그 값을 다시 제출 행으로 복사해야 한다). 테이블 하나와 복사 단계를 아끼고 위를 쓴다 |

**누출이 없다는 증명**: 봇전에서 `judging_opened_at`이 찍히는 순간은 §1.3의 세 경로뿐이고 셋 다 `t_bot`이 지난 뒤다(마감 경로도 `t_bot < deadline_at`이 불변식이라 그렇다, §4). 즉 **봇 제출 행이 보이기 시작하는 시점은 언제나 `t_bot` 이후**다. 그전에는 사용자 세션의 `select * from battle_submissions where battle_id = …`가 자기 행만(0 또는 1행) 돌려준다 — 행 수로도 `t_bot`을 추정할 수 없다. Storage는 봇 사진이 없어 발급할 서명 URL 자체가 없다.

### 1.5 두 개의 "즉시"를 어디서 구현하는가

spec 본문 6번의 인용 상자를 조항 단위로 구현 위치에 매핑한다.

| spec이 요구하는 것 | 구현 지점 | 어떻게 |
|---|---|---|
| **판정 창이 열린 뒤에는 즉시 끝난다**(24시간을 쓰지 않는다) | `open_judging_window`의 봇전 분기 | 자동 승인 두 행을 채워 "양쪽 판정 끝"을 그 자리에서 참으로 만들고 `resolve_battle`을 같은 트랜잭션에서 부른다 |
| **판정 창이 열리기 전에는 즉시 끝내지 않는다**(사용자가 `t_bot` 전에 내도 교체를 살린다) | `accept_submission`의 게이트 입력 | 봇전에서 "상대가 제출했는가"를 `exists(봇 행)`이 아니라 **`봇 행.submitted_at <= now()`**로 본다. `t_bot` 전에는 false → 게이트 `wait` → 창이 열리지 않고 교체가 열려 있다 |
| **`t_bot`이 지나면 내 사진이 잠긴다** | 같은 자리 | 위 값이 true가 되는 순간 "내 행이 있는데 상대도 제출함" → `SUBMISSION_LOCKED` |
| **`t_bot`이 지난 뒤에도 첫 제출은 된다** | 같은 자리 | 내 행이 없으면 insert 경로를 그대로 타고, 그 뒤 게이트가 `open`이 되어 바로 종결된다(완료한 패배) |
| **`t_bot`을 미리 보여 주지 않는다** | 위 §1.4 | 서버가 내주지 않는다 |

`exists`로 "제출했는가"를 세는 **다른** 자리들은 고치지 않아도 안전하다 — 전부 `t_bot`이 지난 뒤에만 실행되기 때문이다.

| 자리 | 왜 안전한가 |
|---|---|
| `settle_expired_battles()` | `deadline_at <= now()`에서만 돈다. `t_bot < deadline_at`이므로 그때 봇은 이미 "제출함"이 맞다 |
| `open_judging_window()`(누가 판정할 수 있나) | 창이 열리는 시점은 언제나 `t_bot` 이후다 |
| `close_expired_judging_windows()` | 판정 기한은 창이 열린 뒤 24시간이다 |
| `submit_judgment()` | 봇전에서 호출 자체가 성립하지 않는다(§3.2 마지막 줄) |

### 1.6 사용자가 보는 시각과 DB가 가진 시각이 어긋나는 구간

**어긋나는 구간은 하나뿐이고, 그 안에서 결과는 이미 결정돼 있다.**

```
시작 ────────── 사용자 제출 ──────── t_bot ─────[어긋남 구간]───── 기록됨 ───── 마감
                 (교체 가능)        (DB: 승부 확정)  (최대 60초)   (finished)
```

| 무엇 | 구간 안의 사실 |
|---|---|
| DB | `t_bot`이 지난 순간 승자는 이미 정해져 있다(두 `submitted_at`의 비교). 아직 `status='active'`이고 점수는 반영되지 않았다 |
| 화면 | 여전히 `진행 중`이고 `사진 마감 N분 남음`이 보인다. **봇이 완료했다는 사실은 보이지 않는다** — 서버가 아직 쓰지 않았으므로 화면이 꾸밀 수 없다 |
| 구간을 끝내는 것 | ① cron(≤60초) ② 사용자가 내 대결 탭·대결 상세를 열거나 당겨서 새로고침 ③ 그 화면을 보고 있으면 20초 주기 재조회(§10.9) ④ 사용자가 그 사이 처음 제출(그 트랜잭션에서 직접 종결) |
| 구간 안에 사용자가 할 수 있는 일 | 교체 시도 → `SUBMISSION_LOCKED`(문구: "봇이 완료해서 사진을 바꿀 수 없어요") + 그 실패를 받은 화면이 정산 RPC를 부르고 다시 읽어 결과를 보여 준다. 포기 시도 → **거부된다**(아래 추기. 초고는 "성립한다"였다) |
| 포기가 끼어들면 | ~~`forfeit_battle`이 먼저 커밋되면 포기 패배(-1)로 끝난다. **이것은 버그가 아니다** — 사람 대결에서도 마감 뒤 cron이 집기 전에 포기하면 포기로 끝난다. 봇전에서 손해가 같아(-1) 어느 쪽이든 점수가 같고, 전적에서도 둘 다 `패`다~~ → **아래 추기로 뒤집혔다** |

> **2026-11-22 추기 — 위 표 마지막 줄의 근거가 틀렸다(reviewer W1).** "손해가 같아 어느 쪽이든
> 점수가 같다"가 성립하지 않는다. **이 어긋남 구간에 들어올 수 있는 봇전은 사용자가 `t_bot` 전에
> 제출한 판뿐이다** — `t_bot` 뒤의 첫 제출은 §1.5대로 그 트랜잭션에서 바로 종결되므로 구간에
> 머물지 않고, 아직 제출하지 않은 판은 `judging_gate`가 `wait`를 주어 정산이 일어나지 않는다.
> 즉 **그 구간의 결과는 언제나 승리**이고, 비교 대상은 `-1 대 -1`이 아니라 **`+1 대 -1`**이다.
> 포기가 먼저 커밋되면 확정된 승리가 포기 패배로 뒤집히고 전적 라벨도 승 → 패로 바뀐다.
>
> 고쳤다: `forfeit_battle`이 봇전이면 **포기 전에 `settle_bot_battle`을 먼저 부르고 상태를 다시
> 읽어**, 이미 끝난 판이면 `BOT_ALREADY_SETTLED`로 거부한다(`20261120120100_bot_battle_rpc.sql`의
> "고치는 기존 함수 7/7"). 같은 트랜잭션·같은 잠금이라 두 호출 사이에 cron이 끼어들 수 없다 —
> 앱에서 포기 직전에 깨우는 방식으로는 막을 수 없다. 거부 예외가 그 정산까지 되돌리므로 거부
> 직후 대결은 아직 `active`이고 결과는 cron이 1분 안에 쓴다(앱 문구가 "곧 결과가 나와요"인 이유).
> 회귀는 `bot_battle_flow_smoke.sql`의 `forfeit_refused`·`forfeit_outcome`이 고정한다.
>
> **사람 대결에 대한 위 서술("마감 뒤 cron이 집기 전 포기")은 그대로 유효하다** — 거기서는 상대가
> 제출하지 않은 판에서만 그 구간이 생겨 비교가 실제로 `-3 대 -3`이 아니라 `+3 대 -3`이 될 수 있다.
> 이 변경은 **봇전만** 손댔다. 사람 대결 쪽은 이 기능의 범위가 아니므로 `TODO_BACKLOG.md`로 넘긴다.

이 구간이 **최대 60초**인 것이 이 설계가 지불하는 유일한 비용이다. 지불하지 않는 길은 §1.2의 (c) 셋뿐이고 전부 더 비싸다.

### 1.7 실체화 시점이 결과를 바꾸지 않는다는 증명

| 실체화가 언제 돌든 | `mutual_speed_outcome`의 입력 | 결과 |
|---|---|---|
| `t_bot` + 1초 | 사용자 `submitted_at`(과거), 봇 `submitted_at = t_bot` | 이른 쪽 승리 |
| `t_bot` + 59초 | **같은 두 값** | 같다 |
| 마감(cron 하나가 몇 분 죽어 있었다) | **같은 두 값** | 같다 |
| 판정 기한(두 cron이 다 죽어 `close_expired_judging_windows`가 치웠다) | **같은 두 값** | 같다 |

`submitted_at`은 과거에 서버가 찍은 값이고 실체화가 그 값을 만지지 않으므로, 지연은 **결과가 아니라 결과를 아는 시점**만 바꾼다. 그래서 "승패는 서버가 정한다"가 유지되고, 클라이언트가 부르는 정산 RPC도 판단 입력이 없는 **멱등한 깨우기**일 뿐이다.

---

## 2. 데이터 모델

### 2.1 봇 계정 — `profiles` 행 하나 + `bot_user_id()`

```
-- 봇의 id는 seed 상수다. 이 함수가 그 값이 코드에 나타나는 유일한 자리다.
create function public.bot_user_id() returns uuid
language sql immutable parallel safe
as $$ select '00000000-0000-0000-0000-00000000b07b'::uuid $$;

insert into public.profiles (id, display_name)
values (public.bot_user_id(), '연습 봇')
on conflict (id) do nothing;
```

| 항목 | 내용 |
|---|---|
| 왜 가능한가 | `profiles.id`의 `auth.users` FK가 2026-09-02에 끊겼다(`20260902213000_delete_account.sql:18`). 평소 행 생성은 `on_auth_user_created` 트리거가 하지만 **seed가 직접 넣어도 제약이 없다** |
| 로그인 | `auth.users` 행이 없으므로 **로그인 경로가 존재하지 않는다**(토큰을 발급받을 계정이 없다) |
| `deleted_at` | **null로 둔다.** 묘비로 보이면 안 된다(spec 4번). 그래서 `get_player_card`의 `deleted` 분기에도 걸리지 않는다 |
| `player_stats` | **행을 만들지 않는다.** `handle_new_user` 트리거는 봇에 대해 돌지 않고, `finalize_battle`은 봇전에서 봇 참가자를 건너뛴다(§3.5). **앞으로 `profiles`를 훑어 행을 만드는 마이그레이션을 쓸 때 `id <> public.bot_user_id()`를 넣는다**(`20260915120100`의 백필이 그런 모양이었다) |
| 이름 | `연습 봇`. 사람 닉네임으로 읽히지 않고(앞 두 글자가 역할을 말한다), 화면에서는 `연습` 배지가 한 번 더 말한다. 성격·말투·프로필 사진은 없다(범위 밖) |
| 권한 | `revoke execute on function public.bot_user_id() from public, anon;` + `grant execute to authenticated, service_role`. **authenticated에 주는 이유**: 이 함수가 CHECK 제약 식에 들어가므로, 훗날 `battles`에 사용자 롤로 쓰는 경로가 생겼을 때 제약 평가가 권한 오류로 깨지지 않게 한다. 봇 id는 비밀이 아니다(사용자는 이미 자기 봇전의 `opponent_id`를 읽는다) |

### 2.2 `bot_battle_topics` (신규)

```
create table public.bot_battle_topics (
  id uuid primary key default gen_random_uuid(),
  title text not null
    constraint bot_battle_topics_title_check check (length(btrim(title)) between 1 and 60),
  min_criteria jsonb not null
    constraint bot_battle_topics_min_shape check (public.is_criteria_list(min_criteria)),
  duration_minutes integer not null
    constraint bot_battle_topics_duration_check check (duration_minutes between 1 and 10080),
  active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);

alter table public.bot_battle_topics enable row level security;
revoke all on table public.bot_battle_topics from anon, authenticated;
```

| 결정 | 근거 |
|---|---|
| `type`·`superiority_criteria` 칸을 **두지 않는다** | 전부 `speed`이고 품질전 봇전은 성립하지 않는다(spec 2번). 칸을 두면 그것이 곧 "나중을 위한 추상화"다 |
| 기간이 주제에 붙는다 | 기간 선택은 난이도 선택의 뒷문이다(spec P0-1) |
| `min_criteria` 모양 검사는 **기존 `is_criteria_list`를 재사용** | 사람 대결 기준과 같은 모양(1~5개, 각 1~100자)이어야 화면이 같은 위젯으로 그린다 |
| **RLS를 켜고 정책을 0개 둔다** | 읽는 경로를 `list_bot_battle_topics()` 하나로 못박는다(그 RPC가 남은 횟수도 함께 내준다). `criteria_cache`의 선례와 같은 모양이고, "나중에 정책을 붙인다"가 아니라 **정답이 정책 없음**이다 |
| `active` + `sort_order` | 주제를 **고치지 않고 교체하는** 운영 규칙을 위한 것이다 — 기준 문장을 바꾸려면 옛 행을 `active=false`로 내리고 새 행을 넣는다. 그러면 "사용자가 본 기준"과 "대결에 복사된 기준"이 어긋날 수 없어 `criteria_version` 같은 장치가 필요 없다. `sort_order`는 새 사용자가 가장 먼저 보는 카드를 운영자가 정하는 수단이다 |
| 인덱스 없음 | 10여 행이다. 전체 스캔이 더 싸다 |

### 2.3 `battles` 변경

| 항목 | 조치 |
|---|---|
| `is_bot boolean not null default false` | **추가.** 봇전임을 나타내는 표시. 클라이언트가 이 값 하나로 배지·분기를 고르므로 **봇 uuid가 Dart에 들어가지 않는다** |
| `bot_topic_id uuid references public.bot_battle_topics (id)` | **추가.** 어느 주제로 시작했는지. 제목만으로는 교체된 옛 주제와 구분되지 않는다. FK는 기본값(no action)이라 쓰인 주제를 실수로 지울 수 없다 |
| 제약 | `check ((bot_topic_id is not null) = is_bot)`, `check (not is_bot or type = 'speed')`, `check (is_bot = (opponent_id is not null and opponent_id = public.bot_user_id()))` |
| 인덱스 | `(started_at) where is_bot and status = 'active'`(cron이 훑는 자리), `(creator_id, started_at) where is_bot`(하루 3회 계수) |
| 주석 | `status`·`is_bot`에 "봇전은 `pending`을 거치지 않고 `active`로 시작하며 `judging`에 머물지 않는다"를 적는다 |

세 번째 제약이 **두 방향을 동시에** 막는다 — 봇이 상대인데 `is_bot`이 false일 수 없고(사람 대결로 위장), `is_bot`인데 상대가 사람일 수도 없다(봇전 점수표로 사람 대결을 치르기). `opponent_id is null`인 모집 행은 왼쪽이 false, 오른쪽이 false로 통과한다.

**적용 전 확인**: `select count(*) from public.battles where opponent_id = public.bot_user_id()` → 0이어야 한다(봇 seed가 이 마이그레이션에서 처음 들어가므로 당연히 0이다).

### 2.4 `battle_submissions` 변경 — 사진 없는 봇 제출

| 항목 | 조치 | 이유 |
|---|---|---|
| `captured_at timestamptz not null` | **`drop not null`** + `check (captured_at is not null or user_id = public.bot_user_id())` | 봇은 사진을 찍지 않으므로 **촬영 시각이 없다.** 아무 값이나 채워 넣는 것은 spec이 사진 자리에 대해 금지한 것("없는 것을 있는 것처럼 꾸미지 않는다")을 데이터에서 하는 것이다. 제약이 "null은 봇 행뿐"을 DB 수준에서 못박는다 |
| `object_path` | **변경 없음**(이미 nullable — 탈퇴 시 null이 된다) | 봇 행은 null이다. 이 컬럼만으로는 봇 행을 식별할 수 없다(탈퇴한 사람 행도 null이다) — 식별은 `user_id = bot_user_id()`로 한다 |
| 봇 행의 모양 | `object_path = null`, `captured_at = null`, `submitted_at = t_bot`, `meets_criteria`·`verdict_source`는 창이 열릴 때 `true`/`'auto'`가 된다 | |
| 쓰기 경로 | insert/update/delete **정책이 하나도 없다**(서버 함수만 쓴다). 봇 행을 넣는 것은 `start_bot_battle` 하나다 | |

**"사람이 사진 없이 제출할 수 없다"의 보증 세 겹**: ① 사용자는 이 테이블에 쓸 수 없다(정책 0개) ② 유일한 사용자 경로 `accept_submission`이 `p_object_path` 빈 값과 `p_captured_at is null`을 각각 예외로 막는다 ③ 위 CHECK가 `captured_at is null`을 봇 행으로 제한한다.

> **딸려 오는 클라이언트 변경(이게 없으면 종결 직후 상세가 깨진다)**: `lib/features/battle/data/battle_submission.dart`의 `capturedAt`이 `DateTime.parse(map['captured_at'] as String)`이라 **null에서 예외가 난다.** 봇 행은 종결 뒤 공개되므로 그 순간 `fetchSubmissions`가 깨져 상세가 오류 화면이 된다. `DateTime? capturedAt`으로 바꾼다 — 이 값은 화면에서 읽는 곳이 한 곳도 없어(grep 확인) 모델 한 줄과 테스트 픽스처만 바뀐다.

### 2.5 `battle_participants` — 봇 행과 `has_submitted` 불변식

- `start_bot_battle`이 봇의 참가자 행을 **명시적으로** 넣는다. `battles_create_participants` 트리거는 현재 본문이 `creator_id` 한 행만 넣기 때문이고, `join_battle`도 같은 방식으로 자기 행을 넣는다. 봇 행이 없으면 `battleDetailProvider`의 `participants.firstWhere((p) => p.userId != myId)`가 터진다.
- **봇의 `has_submitted`는 판정 창이 열릴 때 true가 된다.** 제출 행은 시작부터 있지만 이 컬럼은 **상대(사용자)가 읽는 요약**이라, `t_bot` 전에 true가 되면 "봇이 제출했어요"가 보여 공개 범위가 깨진다. 즉 **봇전에서 이 컬럼의 뜻은 "제출 행이 있는가"가 아니라 "그 제출이 공개됐는가"다.** 이 함정을 컬럼 주석에 적는다.
- `outcome`은 **양쪽 다** 기록한다(행이 스스로를 설명하게). `score_delta_applied`는 **사람 참가자만** 기록한다 — 봇에게는 점수 개념이 없으므로 0을 적어 "변화 없음"이라고 말하지 않고 null로 둔다.

### 2.6 `player_stats` — 칸을 더하지 않는다

| 요구 | 어떻게 지키나 |
|---|---|
| 점수는 섞는다 | `finalize_battle`이 봇전에서도 `score`를 갱신한다(하한 0 그대로) |
| 전적(승/패/무)은 섞지 않는다 | **봇전에서는 `wins`/`losses`/`draws`를 건드리지 않는다.** 칸 추가도 별도 집계 테이블도 만들지 않는다 |
| 모집 목록·상대 전적에 섞이지 않는다 | 그 두 자리는 `player_stats`(와 `list_open_recruits`의 조인)를 읽으므로 **위 한 줄로 자동 충족**된다 |
| 내 봇전 기록을 볼 자리 | 내 기록 목록(`battles` 직접 조회 + `battle_participants.outcome`). `is_bot`으로 구분해 그린다 |
| 프로필의 "봇전 N승 M패" | **P1-2이고 배포 후다.** 그때 집계는 `battles.is_bot` + `battle_participants.outcome` 카운트로 가능하므로 지금 칸을 만들 이유가 없다 |

### 2.7 건드리지 않는 것 (합격선)

| 대상 | 봇전과의 관계 |
|---|---|
| `criteria_checks` | **행이 생기지 않는다.** `start_bot_battle`은 증서를 쓰지 않고 주제 행에서 직접 복사한다 |
| `ai_criteria_calls` | **행이 생기지 않는다.** 그래서 하루 10회가 1회도 줄지 않는다 |
| `criteria_cache` | **읽지도 쓰지도 않는다.** 적재는 Edge `battle-criteria`의 generate 성공 경로 한 자리뿐이고 봇전은 그 함수를 부르지 않는다. 운영자가 쓴 문장이 캐시에 들어가면 "AI 원본만 담는다"는 인젝션 전파 차단이 깨지므로, **봇전 기준을 캐시에 넣는 코드를 쓰지 않는다**(seed는 `bot_battle_topics`에만 들어간다) |
| `ai_judgment_jobs` | **행이 생기지 않는다**(§3.4) |
| `daily_battle_slots` | **존재하지 않는다**(2026-11-06에 드롭됐다). 봇전 한도는 원장 없이 센다(§5) |
| `battle_judgments` 스키마 | 변경 없음. 자동 승인 행 두 개가 `auto = true`로 들어갈 뿐이다 |
| Edge Function | `submit-evidence`·`battle-criteria`·`judge-dispute` **코드 변경 없음.** `_shared/notification_text.ts` 한 곳만 고친다(§9) |

---

## 3. 상태 전이와 판정

### 3.1 전이표 (새 상태 없음)

| # | 현재 | 사건 | 트리거 | 다음 | 결과 |
|---|---|---|---|---|---|
| B1 | — | 봇전 시작 | 사용자 → `start_bot_battle(topic)` | `active` | 봇전 행 + 참가자 2행 + **봇 제출 행(`submitted_at = t_bot`)**, `deadline_at = now() + duration` |
| B2 | `active` | 사용자 첫 제출(`t_bot` 전) | Edge `submit-evidence` → `accept_submission` | `active` | 제출 행, `has_submitted = true`. 게이트 `wait`(봇은 아직 공개 전) |
| B3 | `active` | 교체(`t_bot` 전) | 동일 | `active` | 덮어쓰고 `submitted_at` 갱신. 옛 사진은 Edge가 지운다 |
| B4 | `active` | 교체 시도(`t_bot` 뒤) | 동일 | `active` | 거부 `SUBMISSION_LOCKED` |
| B5 | `active` | **`t_bot` 경과 + 사용자 제출 있음** | cron `settle_due_bot_battles()` / 화면 `settle_my_bot_battles()` | `finished` | 창 열림 → 자동 승인 2행 → `resolve_battle` → 사용자 `win`(+1), 봇 `completed_loss` |
| B6 | `active` | 사용자 첫 제출(`t_bot` 뒤) | `accept_submission` | `finished` | 같은 트랜잭션에서 창 열림 → 종결. 사용자 `completed_loss`(-1) |
| B7 | `active` | 마감(사용자 미제출) | cron `settle_expired_battles()` | `finished` | 게이트 `open`(한쪽만 제출) → 자동 승인 1행 → 사용자 `loss`(-1) |
| B8 | `active` | 포기 | 사용자 → `forfeit_battle` | `finished` | 봇이 `winner_id`, 사용자 `forfeit`(-1), `forfeited_by` 기록. 하루 3회는 돌려주지 않는다 |
| B9 | `active` | 탈퇴 | `delete_account` | `cancelled` | 점수 0. 봇에게 보낼 N5는 수신자 가드가 막는다 |
| B10 | `judging` | (안전망) 판정 기한 경과 | cron `close_expired_judging_windows()` | `finished` | B5~B7의 `resolve_battle`이 예외로 실패해 창이 남은 경우에만 돈다. 자동 승인을 채우고 같은 결론을 낸다 |
| — | `active`/`judging` | 동의 철회 | `withdraw_ai_consent` | **변화 없음** | 봇전은 철회로 포기되지 않는다(§8) |

`judging`이 **관측되는 유일한 경우가 B10 직전**이고, 그것도 트랜잭션 실패라는 사고 뒤다. 정상 경로에서 `judging`은 같은 트랜잭션 안에서 생겼다 사라진다.

### 3.2 자동 승인 두 행 — 누가 무엇을 승인하나

`open_judging_window`의 봇전 분기가 하는 일(순서대로, 창을 여는 `update` 직후):

| 행 | 조건 | 뜻 |
|---|---|---|
| `battle_judgments(judge_id = 사용자, 'approve', auto = true)` | 항상(봇은 창이 열릴 때 늘 제출해 있다) | **봇의 제출을 사용자가 자동 승인.** 사용자에게는 판정할 증거가 없으므로 묻지 않는다 |
| `battle_judgments(judge_id = 봇, 'approve', auto = true)` | **사용자가 제출했을 때만** | **사용자의 제출을 봇이 자동 승인.** "미판정은 승인으로 간주"의 적용이다. 사용자가 내지 않았으면 판정할 것이 없어 행을 만들지 않는다(`close_expired_judging_windows`가 "필요한 판정만" 채우는 것과 같은 규칙) |
| `battle_participants.has_judged = true`, 봇의 `has_submitted = true` | 위 행을 넣은 쪽 | 요약이 사실과 어긋나지 않게 |
| 존재하는 제출 행들의 `meets_criteria = true, verdict_source = 'auto'` | 각각 | 결과 화면이 "누가 인정했는지"를 말할 수 있게. **새 `verdict_source` 값을 만들지 않는다** — 봇전에서 `auto`를 "봇은 판정하지 않아 그대로 인정됐어요"로 **문구만** 달리 읽는다(§12) |
| `perform public.resolve_battle(p_battle_id)` | 마지막 | 같은 트랜잭션에서 종결 |

- **판정 요청 알림(N4')은 이 분기에서 보내지 않는다**(§9).
- `insert ... on conflict (battle_id, judge_id) do nothing`으로 멱등하게 쓴다. B10의 안전망이 같은 행을 다시 넣으려 해도 조용히 지나간다.
- **사용자가 `submit_judgment`를 부를 수 없다**: 창이 열리는 순간 그의 판정 행이 이미 있으므로 PK 충돌 → `ALREADY_JUDGED`. 게다가 종결되어 `status <> 'judging'` → `JUDGING_NOT_OPEN`. 화면에도 판정 버튼이 없다(§10.5). **불복이라는 입력이 서버 어디에도 들어올 수 없다** = AI 재판정 경로가 닫힌다.

### 3.3 결론은 기존 순수 함수가 낸다

`resolve_battle`은 **한 줄도 고치지 않는다.** a = creator = 사용자, b = opponent = 봇으로 고정 매핑되고(§2.3의 제약이 보장) 다음이 그대로 성립한다.

| 경우 | a(사용자) effect | b(봇) effect | `mutual_speed_outcome` | outcome | 점수 |
|---|---|---|---|---|---|
| `t_bot` 전에 제출 | `pass`(봇의 auto 승인) | `pass`(사용자의 auto 승인) | `a.submitted_at < t_bot` → a 승 | `win` / `completed_loss` | **+1** / — |
| `t_bot` 뒤에 처음 제출 | `pass` | `pass` | `t_bot < a.submitted_at` → b 승 | `completed_loss` / `win` | **-1** / — |
| 마감까지 미제출 | `none` | `pass` | b 승 | `loss` / `win` | **-1** / — |
| 포기 | — | — | (`forfeit_battle`이 직접 `finalize_battle`) | `forfeit` / `win` | **-1** / — |

봇 쪽 outcome(`completed_loss`/`win`)은 기록만 되고 점수·전적에 쓰이지 않는다.

### 3.4 `draw`·`voided`·`disputed`가 도달 불가인 증명

| 상태 | 도달 조건 | 봇전에서 왜 불가능한가 |
|---|---|---|
| `draw` | `judging_gate = 'draw'`(아무도 제출 안 함) 또는 `mutual_speed_outcome`의 양쪽 비-`pass` | 봇 제출 행이 **시작부터 존재**하고 `t_bot < deadline_at`이 불변식이라(§4) 마감 시점에 봇은 언제나 "제출함"이다 → 게이트는 `open`. 결론 단계에서도 봇의 effect는 항상 `pass`(사용자의 auto 승인은 `reject`가 될 수 없다) |
| `voided` | `ai_judgment_jobs`의 4회 소진 | 잡이 생기는 유일한 조건은 `min_verdict = 'reject'`(또는 품질전 우열 불일치)다. 봇전에 들어가는 판정은 `auto` + `approve` 두 행뿐이고 사용자가 `reject`를 넣을 경로가 §3.2대로 없다. 품질전 봇전은 존재하지 않는다 |
| `disputed` | 어떤 함수도 쓰지 않는다 | 그대로 |

### 3.5 점수 — `bot_outcome_score_delta`

```
create function public.bot_outcome_score_delta(p_outcome text) returns integer
language sql immutable
as $$ select case p_outcome
                 when 'win' then 1
                 when 'completed_loss' then -1
                 when 'loss' then -1
                 when 'forfeit' then -1
                 when 'draw' then -1   -- 도달하지 않는다(§3.4). null을 돌려주지 않는 이유는 아래
                 else null end $$;
```

- **`outcome_score_delta`는 손대지 않는다**(사람 대결 점수는 한 줄도 바뀌지 않는다).
- `draw`에 `-1`을 주는 이유: `finalize_battle`이 `greatest(v_old_score + v_delta, 0)`를 쓰므로 **delta가 null이면 점수가 0으로 날아간다.** 도달하지 않는 값이라도 null을 돌려주지 않는다. 이 함수가 null을 돌려주는 경우는 outcome 자체가 잘못된 값일 때뿐이고, 그때는 `finalize_battle`의 모양 검사가 먼저 막는다.
- `finalize_battle`의 봇전 분기: **사람 참가자만** 루프를 돌아 `score`를 갱신하고(하한 0 그대로), `wins`/`losses`/`draws`는 **건드리지 않으며**, `player_stats` 행을 봇에게 만들지 않는다. `battle_participants.outcome`은 양쪽, `score_delta_applied`는 사람만.
- 하루 수확의 상한: 3회 × (+1) = **+3**, 손실 상한 3회 × (-1) = **-3**(spec 수용 기준).

---

## 4. `t_bot` 분포 — 정확한 수치

```
v_bot_at := v_started_at
          + make_interval(secs => greatest(30, floor(v_duration_minutes * 60 * (0.50 + 0.35 * random()))::int));
v_bot_at := least(v_bot_at, v_deadline_at - interval '1 second');   -- 불변식을 못박는다
```

| 결정 | 값 | 근거 |
|---|---|---|
| 비율 구간 | **기간의 50% ~ 85%**, 균등 분포 | spec 권고 그대로다. 좁히거나 넓힐 근거가 설계에 없다(앞쪽은 "시작하자마자 졌다", 뒤쪽은 "늘 이긴다") |
| 해상도 | **초 단위 내림** | 분 단위로 뽑으면 5분 주제에서 가능한 값이 3개뿐(2·3·4분)이라 금방 외워진다 |
| 짧은 기간에서 말이 되는가 | 5분(300초) → **150~255초**, 10분 → 300~510초, 15분 → 450~765초. 하한인 5분 주제에서도 2분 30초 이상이 주어진다(§13의 5분 주제는 쓰레기통 비우기·물 한 컵처럼 1분 안에 되는 일이다) | 1분 주제는 §13에 없다. 혹시 들어와도 `greatest(30, …)` 때문에 30초 이상이 보장된다 |
| `t_bot < deadline_at` | `least(..., deadline - 1s)`로 **계산이 아니라 코드가** 보장한다 | 이 불변식이 깨지면 `draw`가 생길 수 있고, "봇전에 `draw`가 없다"는 §3.4의 증명이 여기에 기대 있다. 증명에만 맡기지 않는다 |
| 사용자 행동에 반응하지 않는다 | 시작 때 한 번 뽑고 그 뒤 어떤 함수도 이 값을 쓰지 않는다(`update battle_submissions ... submitted_at`은 봇 행을 건드리지 않는다) | spec P0-3 |
| 난이도 손잡이 | 이 식 한 줄이 전부다. 테이블·설정·사용자 선택을 만들지 않는다 | 범위 밖 |

---

## 5. 하루 3회 상한

기존 한도(기준 생성 10회)의 구현을 읽고 **방식은 따르되 원장은 공유하지 않는다.**

| 항목 | 기준 생성 10회 | 봇전 3회 | 판단 |
|---|---|---|---|
| 하루 경계 | `(now() at time zone 'Asia/Seoul')::date` | **같다** | 같은 식을 쓴다(사용자에게 자정이 두 개면 안 된다) |
| 세는 대상 | `ai_criteria_calls` 원장(성공 + 2분 이내 진행 중) | **`battles` 행 그 자체** | 기준 생성은 "호출"이 행을 남기지 않아 원장이 필요했다. 봇전은 **시작 = `battles` 행 1개**라 원장이 사본일 뿐이다. 사본은 어긋날 수 있고(이중 집계·누락) 드롭된 `daily_battle_slots`를 되살리는 모양이 된다 |
| 동시 호출 | `pg_advisory_xact_lock(hashtext(user::text))` | `pg_advisory_xact_lock(hashtext('bot_battle:' || user::text))` | **키를 다르게 둔다.** 같은 키를 쓰면 무관한 두 한도가 서로를 기다린다 |
| 돌려주기 | 실패한 호출은 세지 않는다 | **포기·무효·취소로 돌려주지 않는다** | 돌려주면 "주제가 마음에 안 들면 포기하고 다시 고르기"가 무한이 된다(spec) |
| 공유 함수 | `criteria_calls_used(user, date)` | `bot_daily_battles_used(user)` **신규** | 복사가 아니라 각자 한 개. 세는 대상이 다르므로 공유할 몸통이 없다 |

```
create function public.bot_daily_battles_used(p_user_id uuid) returns integer
language sql stable set search_path = public
as $$
  select count(*)::integer from public.battles
  where is_bot and creator_id = p_user_id
    and started_at >= (((now() at time zone 'Asia/Seoul')::date)::timestamp at time zone 'Asia/Seoul')
$$;
```

- 비교를 `(started_at at time zone 'Asia/Seoul')::date = today`가 아니라 **경계 시각 이상**으로 쓴다 — 함수 호출을 컬럼에 씌우지 않아 `(creator_id, started_at) where is_bot` 인덱스를 그대로 탄다.
- **클라이언트 시계로 우회할 수 없다**: 이 계산이 전부 서버에서 일어나고, 클라이언트가 보내는 값은 주제 id 하나다.
- `get_my_limits`는 **고치지 않는다.** 그 RPC는 동의 여부와 기준 생성 한도를 말하는 자리이고, 봇전 남은 횟수는 그것을 쓰는 화면(주제 고르기)이 `list_bot_battle_topics`로 함께 받는다. 두 한도를 한 응답에 섞으면 화면이 "오늘 남은 횟수"를 두 개 들고 있게 된다.

---

## 6. API 계약

### 6.1 공통 규칙 (CLAUDE.md 코딩 규칙 그대로)

- 앱이 부르는 RPC: `security definer set search_path = public`, 첫 줄 `if auth.uid() is null then raise exception '로그인이 필요합니다.'`, `revoke execute … from public, anon` + `grant execute … to authenticated`.
- cron 전용 함수: `auth.uid()` 가드를 **두지 않는다**(cron에 uid가 없어 항상 실패한다). `revoke execute … from public, anon, authenticated`만 쓰고 service_role에도 주지 않으며, **함수 주석에 이 예외의 이유를 적는다**(`settle_expired_battles` 선례).
- 내부 전용 함수: `security invoker` + EXECUTE 전부 회수.
- 참가자 검사는 `is distinct from` 두 개(`not in` 금지).
- 오류는 `raise exception using message = '<한국어>', hint = '<CODE>'`.
- 새 테이블은 만들 때 RLS를 켜고 정책을 같이 쓴다(정책 0개가 정답인 근거는 §2.2).

### 6.2 새 함수

| 함수 | 파라미터 | 반환 | 호출자 | 권한 |
|---|---|---|---|---|
| `bot_user_id()` | — | `uuid` | 제약·내부 함수·필터 | public·anon 회수, authenticated·service_role 허용(§2.1) |
| `bot_daily_battles_used(p_user_id uuid)` | — | `integer` | 아래 두 RPC | 전부 회수 |
| `bot_outcome_score_delta(p_outcome text)` | — | `integer` | `finalize_battle` | 전부 회수 |
| `list_bot_battle_topics()` | — | `jsonb` `{daily_limit:3, daily_left:int, topics:[{id,title,min_criteria,duration_minutes}]}`(`active`만, `sort_order, created_at` 순) | 앱(주제 고르기 화면) | authenticated |
| `start_bot_battle(p_topic_id uuid)` | — | `uuid`(battle id) | 앱 | authenticated |
| `settle_my_bot_battles()` | — | `integer`(종결된 수) | 앱(목록·상세 화면) | authenticated |
| `settle_bot_battle(p_battle_id uuid)` | — | `text`(호출 뒤 상태) | 위 RPC와 cron | 전부 회수(내부 전용) |
| `settle_due_bot_battles()` | — | `integer` | cron `settle-bot-battles` | 전부 회수, **service_role에도 주지 않는다** |

**`start_bot_battle` 본문 순서**
1. 로그인 가드. 2. `pg_advisory_xact_lock(hashtext('bot_battle:' || auth.uid()::text))`.
3. `bot_daily_battles_used(auth.uid()) >= 3` → `BOT_DAILY_LIMIT`.
4. 주제 조회(`id = p_topic_id and active`) → 없으면 `BOT_TOPIC_INVALID`.
5. `insert into battles (type, status, title, creator_id, opponent_id, started_at, deadline_at, duration_minutes, min_criteria, superiority_criteria, is_bot, bot_topic_id) values ('speed','active', 주제.title, auth.uid(), bot_user_id(), now(), now() + make_interval(mins => 주제.duration_minutes), 주제.duration_minutes, 주제.min_criteria, null, true, 주제.id)` → 트리거가 생성자 참가자 행을 만든다.
6. `insert into battle_participants (battle_id, user_id) values (…, bot_user_id())`.
7. `t_bot` 계산(§4) → `insert into battle_submissions (battle_id, user_id, object_path, captured_at, submitted_at) values (…, bot_user_id(), null, null, v_bot_at)`.
8. **동의 검사도, 기준 생성 호출도, 캐시 조회도 없다.** 알림도 적재하지 않는다(N1 없음).
9. battle id 반환.

**`settle_bot_battle(p_battle_id)` 본문**(두 호출자가 공유하는 유일한 몸통)
1. `select * from battles where id = … for update` → `is_bot`이 아니거나 `status <> 'active'`면 현재 상태 반환(멱등).
2. 사용자 제출 여부(`exists`)와 **봇 공개 여부**(`봇 행.submitted_at <= now()`)를 읽는다.
3. `judging_gate('speed', v_user_submitted, v_bot_revealed, false)`가 `'open'`이면 `open_judging_window(id)`(그 안에서 자동 승인 + `resolve_battle`). 아니면 아무것도 하지 않는다.
4. 종결 뒤 상태 반환.

`settle_due_bot_battles()`는 `battles b where b.is_bot and b.status='active'`를 인덱스로 훑어 봇 제출 행의 `submitted_at <= now()`인 것만 골라 **한 행씩 예외를 흡수하며**(`begin … exception when others then raise warning …; end;` — `settle_expired_battles` 선례) `settle_bot_battle`을 부른다. `settle_my_bot_battles()`는 같은 일을 `creator_id = auth.uid()`로 좁혀서 한다.

> **왜 클라이언트가 부르는 정산 RPC가 "클라이언트가 승패를 정한다"가 아닌가**: 인자가 없고(어느 대결인지도 서버가 고른다), 시각 판단을 전부 `now()`로 서버가 하며, 호출해도 `t_bot` 전에는 아무 일도 일어나지 않는다. 클라이언트가 보내는 것은 "지금 다시 봐 달라"는 신호 하나이고, cron이 같은 일을 1분마다 한다. 호출 결과도 §1.7대로 **결과를 바꾸지 않는다.**

### 6.3 고치는 기존 함수 (여섯 개)

| 함수 | 시그니처 | 변경 | 왜 |
|---|---|---|---|
| `open_judging_window(uuid)` | 유지 | **봇전 분기 추가**: 자동 승인 2행 + 요약 갱신 + 제출 행 `verdict_source='auto'` + `resolve_battle` 호출. **N4'(judge_turn) 적재를 건너뛴다** | "봇전은 판정 창이 열리는 순간 끝난다"를 한 곳에 못박는다. 창을 여는 세 경로가 전부 이 효과를 얻는다 |
| `accept_submission(uuid,uuid,text,timestamptz)` | **반드시 유지**(배포된 `submit-evidence`가 이 시그니처로 부른다 → `create or replace`) | ① 봇전이면 **동의 검사 건너뛰기** ② "상대가 제출했는가"를 봇전에서 `봇 행.submitted_at <= now()`로 계산 ③ 내 행이 있고 그 값이 true면 `SUBMISSION_LOCKED` ④ 반환 `battle_status`를 하드코딩(`'judging'`)하지 않고 **창을 연 뒤 실제 상태를 다시 읽어** 담는다(봇전은 `'finished'`가 된다) | ②·③이 "교체를 살리고 `t_bot`에 잠근다"의 전부다. ④ 없이는 끝난 대결에 `judging`을 돌려준다 |
| `finalize_battle(uuid,text,uuid,text,text)` | 유지 | **봇전 분기**: 사람 참가자만 점수 반영(`bot_outcome_score_delta`), 승/패/무 카운터 미변경, 봇의 `player_stats` 행 미생성, `outcome`은 양쪽 기록. N2 payload에 **`is_bot: true`** 추가 | 점수는 섞고 전적은 가른다(§2.6). payload 키는 §9 |
| `enqueue_notification(uuid,text,uuid,text,jsonb)` | 유지 | 기존 null 가드에 **`or p_recipient_id = public.bot_user_id()` → 조용히 반환** | N2·N3·N5가 봇을 수신자로 부른다. 한 곳에서 막으면 호출자를 고칠 필요가 없고 원장에 쓰레기가 쌓이지 않는다 |
| `get_player_card(uuid)` | 유지 | **`p_user_id = bot_user_id()`면 거부**(`BOT_NO_STATS`) | 봇은 "내 대결 상대"라서 기존 공개 조건을 **통과한다.** 거부하지 않으면 봇의 누적 전적이 상대 카드에 뜬다 |
| `withdraw_ai_consent()` / `get_consent_withdrawal_impact()` | 유지 | 두 함수의 대결 조회에 **`and not is_bot`** | 철회가 봇전을 포기 처리하지 않고(§8), 확인 문구의 개수도 봇전을 세지 않는다 |

**고치지 않는 것**: `resolve_battle`, `judging_gate`, `mutual_speed_outcome`, `min_verdict_effect`, `outcome_score_delta`, `settle_expired_battles`, `close_expired_judging_windows`, `submit_judgment`, `forfeit_battle`, `delete_account`, `join_battle`, `create_battle`, `begin_criteria_call`, `list_open_recruits`, `cancel_battle`, `void_battle`, `claim_notifications`. 각각 왜 그대로 되는지는 §1.5·§3.3·§7에 적었다.

### 6.4 오류 코드

| 코드 | 발생 | 사용자 문구(§12) |
|---|---|---|
| `BOT_DAILY_LIMIT` | `start_bot_battle` | 오늘 연습 대결 3번을 다 썼어요 |
| `BOT_TOPIC_INVALID` | `start_bot_battle` | 지금은 쓸 수 없는 주제예요 |
| `BOT_NO_STATS` | `get_player_card` | (화면이 부르지 않는다. 호출되면 로그만) |
| `SUBMISSION_LOCKED` | `accept_submission` | **봇전 전용 문구로 갈린다**(봇이 완료해서 바꿀 수 없어요) |
| `DEADLINE_PASSED` / `CAPTURED_BEFORE_START` / `CAPTURE_TIME_MISMATCH` | 동일 | 기존 그대로(봇전에서도 촬영 시각 대조가 그대로 동작한다) |
| `CONSENT_REQUIRED` | 봇전에서는 **발생하지 않는다** | — |

### 6.5 cron

| 작업 | 주기 | 명령 | 조치 |
|---|---|---|---|
| `settle-bot-battles` | `* * * * *` | `select public.settle_due_bot_battles();` | **신규** |
| `settle-expired-battles` / `close-judging-windows` / `ai-judge-tick` / `notify-tick` | 1분 | — | **변경 없음** |

**다섯 번째 작업을 따로 두는 이유**는 mutual-judge가 셋을 쪼갠 것과 같다 — 한 작업의 명령 문자열은 한 트랜잭션이라, 봇전 정산에서 예외가 나면 같은 tick의 마감 정산까지 되돌아간다. 비용은 1분에 한 번 작은 조건부 인덱스 스캔(활성 봇전은 사용자당 최대 3행)이다.

### 6.6 Edge Function

| 함수 | 조치 |
|---|---|
| `submit-evidence` | **코드 변경 없음**(accept_submission을 중계할 뿐이다). 재배포도 필요 없다 — `accept_submission`을 `create or replace`로 시그니처를 유지하기 때문이다 |
| `battle-criteria` / `judge-dispute` | **변경 없음.** 봇전은 부르지 않는다 |
| `send-notifications` | `_shared/notification_text.ts`를 고치므로 **재배포 1회**(§9·§15) |

---

## 7. 봇을 걸러야 하는 자리 (전수)

`profiles`의 select 정책이 `using (true)`("profiles are viewable by any authenticated user", `20260818220000_profiles_and_todos.sql:10-13`)라 **봇 행은 모든 로그인 사용자에게 보인다. RLS로는 못 막으므로 쿼리·함수에서 막는다.**

| # | 자리 | 봇이 새는가 | 조치 |
|---|---|---|---|
| 1 | `list_open_recruits()`(모집 목록) | **구조적으로 안 샌다** | 조건이 `status='pending' and opponent_id is null`인데, §2.3의 제약이 `is_bot ⇒ opponent_id = 봇`을 보장하므로 봇전 행은 두 조건에 모두 걸린다. 봇은 모집을 만들지 않으므로 생성자 조인에도 나타나지 않는다. **중복 필터를 넣지 않는다**(DB 제약이 이미 증명한다) |
| 2 | `get_player_card(bot)`(상대 전적 카드) | **샌다** — 봇은 내 대결 상대라 첫 번째 `exists`를 통과한다 | **서버에서 거부**(`BOT_NO_STATS`) + 화면이 애초에 부르지 않는다(§10.4) |
| 3 | `enqueue_notification(recipient = bot)` | **샌다** — `finalize_battle`(N2), `accept_submission`(N3), `delete_account`(N5)가 봇을 수신자로 부른다 | 함수 첫 가드에서 **조용히 반환** |
| 4 | `open_judging_window`의 N4'(judge_turn) | **샌다** — 봇전에서도 "판정할 차례" 알림이 사용자에게 간다 | 봇전 분기에서 **적재하지 않는다**(사용자가 판정할 것이 없다) |
| 5 | `player_stats`(점수·전적 집계) | 봇 행이 생기면 샌다 | **봇 행을 만들지 않는다**(§2.1·§3.5) + 앞으로 `profiles` 전수 백필에 `id <> bot_user_id()`를 넣는 규칙 |
| 6 | `withdraw_ai_consent` / `get_consent_withdrawal_impact` | 봇전을 사람 대결처럼 포기·집계한다 | `and not is_bot` |
| 7 | 표시 이름 조회(`fetchDisplayNames`, battle·profile 양쪽) | id를 지정해 읽으므로 **걸러낼 것이 없다** | 대신 **이름 자체가 역할을 말한다**(`연습 봇`) + 화면에 `연습` 배지 |
| 8 | 사용자 검색 | **지금 앱에 없다**(`friends`는 배포 후) | 생길 때 봇을 제외해야 한다 → `TODO_BACKLOG.md`에 한 줄(메인 세션 몫) |
| 9 | 탈퇴 묘비 목록·"탈퇴한 사용자" 표시 | 봇은 `deleted_at`이 null이라 묘비로 읽히지 않는다 | 유지(봇에게 `deleted_at`을 쓰는 코드를 만들지 않는다) |
| 10 | 내 대결 목록·내 기록 목록 | 봇전은 **보여야 한다** | 거르지 않고 `is_bot` 배지로 구분(§10.7) |
| 11 | `settle_expired_battles` / `close_expired_judging_windows` | 봇전도 **지나가야 한다** | 거르지 않는다(안전망) |

---

## 8. 동의 게이트 — 어디를 가르나

현재 게이트는 네 곳이고 **셋은 그대로 둔다.**

| 게이트 | 지금 | 봇전 |
|---|---|---|
| `begin_criteria_call`(기준 생성) | 동의 필수 | **그대로**(봇전은 부르지 않는다) |
| `create_battle`(모집 등록) | 동의 필수 | **그대로** |
| `join_battle`(참가) | 동의 필수 | **그대로** |
| `accept_submission`(제출) | 동의 필수 | **봇전이면 건너뛴다** ← 유일한 변경 |
| `start_bot_battle`(신규) | — | 동의를 **보지 않는다** |

- 근거: 봇전에서 Google로 나가는 것이 하나도 없다. 기준은 운영자가 쓴 고정 문구, 사진은 아무도 보지 않고, 제목은 임베딩으로도 나가지 않는다(§2.7).
- **철회가 봇전을 건드리지 않는다**: `withdraw_ai_consent`가 `and not is_bot`으로 좁힌다. 진행 중 봇전은 그대로 남고, 사람 대결에 대한 처리(포기·모집 취소)는 한 줄도 바뀌지 않는다.
- **고지 문구 세 자리**(spec P0-6): 앱의 `aiConsentRefusal`·`aiConsentWithdrawAfter`·`aiConsentRequired`(§12), `privacy.html`, 별도 저장소 `C:\workspaces\todododo-legal`. 그리고 `TODO_BACKLOG.md`의 **[배포 전 필수]** 항목(`aiConsentIntro`의 첫 문장이 옛 판정 구조를 말한다)이 **같은 화면의 같은 단락**이므로 함께 고친다. 법적 고지라 문구는 오너 승인 사항이다(결정 필요 3).

---

## 9. 알림

**새 `kind`를 만들지 않는다.** 봇전에서 실제로 적재되는 것은 `finished` 하나다.

| 사건 | 봇전에서 | 어디서 막히나 / 생기나 |
|---|---|---|
| N1 `matched` | **없다** | `start_bot_battle`이 적재하지 않는다(사용자가 그 화면에 있다) |
| N2 `finished` | **있다**(사용자에게만) | `finalize_battle`의 기존 적재. 봇 수신 행은 §7-3 가드가 막는다. cron으로 조용히 끝나는 경우가 있어 이 알림이 필요하다 |
| N2' `voided` | **없다** | `void_battle`에 도달하지 않는다(§3.4) |
| N3 `submitted` | **없다** | 수신자가 봇뿐이라 가드가 막는다("봇이 냈어요"는 사실상 "너 졌어"다) |
| N4' `judge_turn` | **없다** | `open_judging_window`의 봇전 분기가 적재하지 않는다 |
| N5 `cancelled` | **없다** | 봇은 탈퇴하지 않고, 사용자 탈퇴 시 수신자가 봇이라 가드가 막는다 |
| N6 `deadline_soon` | **적재 지점이 아직 없다**(push 6단계 미구현) | 아래 인계 |

**문구 두 자리 규칙**: `kind`를 늘리지 않으므로 두 자리에 줄을 더하지 않는다. 다만 **서버 문구 한 곳을 고친다** — `notification_text.ts`의 `finishedText`가 `outcome='completed_loss'`일 때 붙이는 `· 기준을 통과해서 감점이 줄었어요.`는 **봇전에서 거짓이다**(봇전은 완료한 패배와 미착수가 둘 다 -1이라 줄어든 것이 없다). N2 payload에 `is_bot`을 담고 그 꼬리를 **봇전에서는 붙이지 않는다**. 앱 안 알림함(`notification_line.dart`)은 **그 감면 설명을 이미 붙이지 않으므로 변경이 없다**(현재 주석이 그렇게 적혀 있다).

> **N6 인계**(spec의 "이 연결을 끊지 말 것"): 봇전의 벌점이 일률 -1로 약해진 대가를 메우는 장치가 N6 하나다. 그런데 `enqueue_deadline_reminders`는 아직 존재하지 않는다(`push-notification` 6단계). 그 단계가 만들 때 **봇전이 대상에 포함되어야 한다** — 조건은 `status = 'active'` + **내 제출이 없음** + 마감 문턱(짧은 대결용 비례 문턱 재설계가 그 단계의 과제이고 **봇전은 짧은 대결의 또 한 종류다**), 수신자는 **사람 참가자 한 명**(봇 수신은 §7-3 가드가 막는다). 봇전 쪽에서 추가로 필요한 작업은 없다. 배포 시점 문제는 결정 필요 2.

---

## 10. 화면

기존 패턴을 따른다 — `FutureProvider.autoDispose` + `AsyncValue.when`, 실패 시 `debugPrint` + 스낵바, 당겨서 새로고침, 문구는 전부 `lib/core/strings.dart`, 서버 오류는 코드로 분기.

### 10.1 입구 (두 자리)

| 자리 | 모양 | 근거 |
|---|---|---|
| `찾기` 탭 목록의 **첫 카드** | `AppPanel.flat` 한 장: `연습 봇과 대결` + `상대를 기다리지 않고 바로 시작해요. 하루 3번까지.` + 오른쪽 화살표. 목록과 함께 스크롤되고 **빈 상태(모집 0건)에서도 그린다** | 봇전은 "상대를 찾다 막혔을 때"의 선택지다. 고정 조작 영역(검색·필터 2단, 이미 174dp)을 더 늘리지 않고, 실제 모집이 있으면 스크롤로 밀려난다 |
| `내 대결` 탭 **빈 상태** | 기존 `찾기` 버튼 아래 보조 `TextButton`: `연습 봇과 대결` | 로그인 직후 첫 탭이고 이 기능이 겨냥한 사용자가 있는 자리다. 소개 블록 세 줄 바로 아래에서 "지금 해 볼 수 있는 것"을 가리킨다 |

둘 다 `BotBattleTopicsScreen`을 push한다. 주제 고르기·시작은 **대결 만들기(`create_battle_screen`)와 섞지 않는다** — 그 화면은 기준 생성·동의·기간 선택이 있는 다른 흐름이다.

### 10.2 주제 고르기 (`bot_battle_topics_screen.dart`, 신규)

- 머리: `연습 대결 주제` / 한 줄 안내 `운영자가 미리 준비한 주제예요. 기간과 기준은 주제마다 정해져 있어요.` / `오늘 N번 남았어요 (하루 3번)`.
- 본문: 주제 카드 N장(`AppPanel.raised`, onTap). 카드 = 제목 + 기간 칩(`battleDurationLabel`) + **최소 기준 목록**(기존 `criteria_views.dart`의 목록 위젯 재사용, 2~3줄이라 접지 않고 그대로 보여 준다). 유형 배지는 **두지 않는다** — 전부 속도전이라 구분에 쓸모가 없다.
- 상태: 로딩(`StatusMessage.loading`) / 실패(`연습 대결 주제를 불러오지 못했어요.` + `다시 시도`) / **남은 횟수 0**(카드는 그대로 보이되 탭이 비활성 + 위에 `오늘 연습 대결을 다 썼어요. 자정이 지나면 다시 할 수 있어요.`) / 주제 0건(운영자가 전부 비활성화한 경우 — `지금은 준비된 주제가 없어요.`).
- 빈 횟수에서도 **카드를 숨기지 않는다**: 무엇을 할 수 있는 기능인지는 보여 주고 "오늘은 끝"만 말한다.

### 10.3 시작 확인 (바텀 시트)

- 제목 `바로 시작할까요?` + 주제 제목·기간.
- **최소 기준 전문**(spec: 시작 전에 기준이 보인다).
- **한 줄 안내 두 줄**(spec P0-2의 네 가지를 담는다): `상대는 사람이 아니라 연습 봇이에요. 봇은 기간 안 어느 시각에 완료하고, 그보다 먼저 사진을 내면 이겨요.` / `이기면 +1점이에요(사람과의 대결은 +3점). 하루 3번까지 할 수 있어요.`
- 버튼 `이 주제로 시작` → `startBotBattle(topicId)` → 성공 시 `BattleDetailScreen`으로 **교체 push**(시트 닫고 상세로). 실패 시 코드별 문구(§6.4) + 목록 invalidate.
- `t_bot`을 **어디에도 적지 않는다**(비율도 숫자도).

### 10.4 봇전 진행 (`battle_detail_screen` 분기)

| 자리 | 사람 대결 | 봇전 |
|---|---|---|
| 헤더 칩 | 유형 배지 + 상태 칩 | **+ `연습` 배지**(`AppTag` + 기존 `neutralTagStyle`. 새 팔레트 값을 만들지 않는다) |
| 상대 카드 | `playerCardProvider` 전적 카드 | **부르지 않는다.** `연습 봇` + `연습 상대` 한 줄만. 점수·승패 숫자가 한 자도 없다 |
| 시간 두 줄 | 사진 마감 / 판정 마감 | **사진 마감만.** 봇전은 판정 창에 머물지 않아 판정 마감 줄이 뜨는 순간이 없다(값이 null이라 기존 코드가 이미 숨긴다) |
| 내 증거 영역 | 그대로 | **그대로**(촬영·미리보기·제출·교체·10분 안내 전부 동일) |
| 상대 증거 영역 | `아직 제출 전` / `제출했어요` | `봇은 증거 사진을 내지 않아요.` + `봇은 기간 안 어느 시각에 완료해요.` — **빈 칸도 가짜 이미지도 아니다**. `t_bot`은 적지 않는다 |
| 포기 버튼 | 있다 | **있다**(빠져나가는 유일한 길) |
| VS 인트로 | 첫 진입 1회 | **그대로**(상대 이름이 `연습 봇`으로 나온다). 장식이고 관문이 아니다 |

### 10.5 판정 창 — 사용자에게 묻는 것이 없다

- `JudgmentSection`을 **그리지 않는다**(`is_bot`이면 통째로 건너뛴다). 통과/불복 버튼, 우열 버튼, 확인 다이얼로그가 전부 없다.
- 정상 경로에서는 `judging`이 **관측되지 않는다**(같은 트랜잭션에서 끝난다). 안전망 B10으로 `judging`이 보일 극히 드문 경우에는 한 줄만 보여 준다: `연습 대결에는 판정이 없어요. 봇은 사진을 내지 않고, 내 사진은 그대로 인정돼요.` + 당겨서 새로고침.
- `judgment_rules.dart`의 `judgmentStageOf`는 **고치지 않는다** — 호출 자체를 하지 않는다(규칙 함수에 봇 분기를 심으면 사람 대결 판정 경로에 if가 늘어난다).

### 10.6 결과

- 결과 배너는 서버 값(`status`·`winner_id`·`outcome`·`score_delta_applied`) 그대로. 부제만 봇전 문구로 갈린다.

| `outcome` | 부제 |
|---|---|
| `win` | `봇보다 먼저 완료했어요.` |
| `completed_loss` | `기준은 통과했지만 봇이 먼저 완료했어요.` |
| `loss` | `사진을 내지 않아 봇이 이겼어요.` |
| `forfeit` | 기존 `battleLostByForfeit` 그대로 |

- 점수 줄(`+1점` / `-1점`)과 하한 안내(`점수는 0점 아래로 내려가지 않아요.`)는 기존 위젯 그대로.
- 공개된 양쪽 증거(`RevealedEvidenceSection`): 내 사진 + 시각, 봇 칸은 **`봇 완료 시각 hh:mm` + `봇은 증거 사진을 내지 않아요.`**(사진 자리를 비우지 않는다). 내 제출의 인정 경로 설명은 `verdict_source='auto'`를 **봇전 문구**로 읽는다: `봇은 판정하지 않아 내 사진이 그대로 인정됐어요.`
- "왜 +1인가"를 결과 화면에서 다시 설명하지 않는다(P1-3, 배포 후).

### 10.7 내 기록 목록·프로필

- `battle_records_screen`의 카드에 유형 배지 옆 **`연습` 배지**를 더한다(상대 이름 `연습 봇`과 함께 두 번 말한다). 결과 라벨(승/패)은 기존 그대로.
- 프로필의 점수·승/패/무는 **그대로**. 봇전은 점수에만 더해지고 승/패/무에는 들어가지 않는다(§2.6). 프로필의 봇전 전용 줄은 **배포 후**(P1-2).

### 10.8 상태·오류 표 (새 화면)

| 화면 | 로딩 | 빈 상태 | 오류 |
|---|---|---|---|
| 주제 고르기 | `StatusMessage.loading` | 주제 0건 안내 / 남은 횟수 0 안내 | `다시 시도` 버튼(목록 조회는 사용자가 볼 것이 아무것도 없는 실패라 화면에 사실을 적는다) |
| 시작 확인 시트 | 버튼 비활성 + 스피너 | — | 스낵바(코드별 문구) + 목록 invalidate |
| 봇전 상세 | 기존 그대로 | — | 기존 그대로 |
| 정산 RPC(`settleMyBotBattles`) | **표시하지 않는다** | — | **`debugPrint`만.** 토스트를 띄우지 않는다 — 관문이 아니고(cron이 1분 안에 같은 일을 한다), 사용자가 할 수 있는 일이 없고, 다음 새로고침에서 저절로 맞춰진다. CLAUDE.md "에러는 삼키지 않는다"의 기존 예외들(위젯 캐시 발행, 기한 알림 배선, 알림함 읽음 표시)과 같은 성격이다 → **CLAUDE.md 코딩 규칙의 예외 목록에 한 줄 추가**(결정 필요 4) |

### 10.9 어긋남 구간을 줄이는 재조회

| 지점 | 무엇 |
|---|---|
| `myBattlesProvider` | 목록을 읽기 **전에** `settleMyBotBattles()` 한 번. 내 대결 탭을 열면 밀린 봇전이 정산된다. 비용은 작은 RPC 한 번(봇전이 없으면 0행 루프) |
| `battleDetailProvider` | 대결을 읽고 **`is_bot && status == 'active'`일 때만** `settleMyBotBattles()` → 반환이 0보다 크면 한 번 다시 읽는다. 사람 대결에는 호출이 생기지 않는다 |
| 봇전 상세를 보고 있는 동안 | `is_bot && status == 'active' && me.hasSubmitted`인 동안 **20초 주기로 상세를 invalidate.** 그 상태에서만 돈다 |
| 정확한 시각에 한 번만 깨우지 않는 이유 | **클라이언트는 `t_bot`을 모른다**(그게 규칙이다). 그래서 "그 시각에 한 번"이 불가능하고 주기 재조회가 유일한 수단이다. 조건을 좁혀 비용을 20초에 요청 하나로 묶는다 |

---

## 11. 데이터 흐름

**흐름 1. 시작** — 주제 카드 탭 → 확인 시트 → `BattleRepository.startBotBattle(topicId)` → RPC(§6.2) → battle id → `BattleDetailScreen` push + `myBattlesProvider`·`botBattleTopicsProvider` invalidate. 서버가 그 트랜잭션에서 봇 제출 행(`submitted_at = t_bot`)까지 만든다. **AI 호출 0, 증서 0, 캐시 접촉 0, 알림 0.**

**흐름 2. 제출·교체** — 기존 흐름과 **같다**(카메라 → Storage 업로드 → Edge `submit-evidence` → `accept_submission`). 봇전에서 달라지는 판단은 서버 안의 세 가지뿐: 동의 검사 건너뛰기, "상대 제출"을 `t_bot <= now()`로 보기, 창이 열리면 같은 트랜잭션에서 종결.

**흐름 3. `t_bot` 경과(사용자가 이미 제출함)** — cron `settle-bot-battles`(≤60초) 또는 화면의 `settleMyBotBattles()` → `settle_bot_battle` → 게이트 `open` → `open_judging_window`(자동 승인 2행) → `resolve_battle` → `mutual_speed_outcome` → `finalize_battle`(점수 +1, 전적 미변경, N2 적재) → `finished`.

**흐름 4. 마감(사용자 미제출)** — cron `settle-expired-battles` → `judging_gate('speed', false, true, true) = 'open'` → `open_judging_window`(사용자의 자동 승인 1행만) → `resolve_battle` → 사용자 `loss`(-1) → N2.

**흐름 5. 포기** — `forfeit_battle` 그대로. 봇이 `winner_id`, `forfeited_by = 사용자`, `forfeit`(-1). 포기한 본인에게 N2를 보내지 않는 기존 규칙이 그대로 적용되어 **봇전 포기에는 알림이 하나도 생기지 않는다**(상대는 봇이고 가드가 막는다).

**흐름 6. 탈퇴·동의 철회** — 탈퇴: 기존 `delete_account`가 봇전도 `cancelled`로 바꾼다(점수 0). 철회: 봇전을 건드리지 않는다.

**흐름 7. 조회** — 상세는 기존 4개 질의 그대로(`battles`/`battle_participants`/`battle_submissions`/`battle_judgments`). 공개 범위는 전부 RLS가 자른다 — 봇 제출 행은 `judging_opened_at`이 찍힌 뒤에만 온다. 주제 목록은 `list_bot_battle_topics()` 하나.

---

## 12. 문구 (전부 한국어, `lib/core/strings.dart`)

**새로 추가**

| 키 | 값 | 자리 |
|---|---|---|
| `botBattleEntryTitle` | 연습 봇과 대결 | 입구 두 자리 |
| `botBattleEntryHint` | 상대를 기다리지 않고 바로 시작해요. 하루 3번까지. | 찾기 탭 입구 카드 |
| `botBattleTopicsTitle` | 연습 대결 주제 | 주제 화면 제목 |
| `botBattleTopicsIntro` | 운영자가 미리 준비한 주제예요. 기간과 기준은 주제마다 정해져 있어요. | 주제 화면 머리 |
| `botBattleDailyLeft(int left, int limit)` | 오늘 {left}번 남았어요 (하루 {limit}번) | 주제 화면 |
| `botBattleDailyNone` | 오늘 연습 대결을 다 썼어요. 자정이 지나면 다시 할 수 있어요. | 주제 화면(횟수 0) |
| `botBattleTopicsEmpty` | 지금은 준비된 주제가 없어요. | 주제 0건 |
| `botBattleLoadTopicsFailed` | 연습 대결 주제를 불러오지 못했어요. | 주제 조회 실패 |
| `botBattleStart` | 이 주제로 시작 | 확인 시트 버튼 |
| `botBattleStartConfirmTitle` | 바로 시작할까요? | 확인 시트 제목 |
| `botBattleStartNoticeBot` | 상대는 사람이 아니라 연습 봇이에요. 봇은 기간 안 어느 시각에 완료하고, 그보다 먼저 사진을 내면 이겨요. | 확인 시트 |
| `botBattleStartNoticeScore` | 이기면 +1점이에요(사람과의 대결은 +3점). 하루 3번까지 할 수 있어요. | 확인 시트 |
| `botBattleStartFailed` | 연습 대결을 시작하지 못했어요. 다시 시도해주세요. | 스낵바 |
| `botBattleErrorDailyLimit` | 오늘 연습 대결 3번을 다 썼어요. | `BOT_DAILY_LIMIT` |
| `botBattleErrorTopicInvalid` | 지금은 쓸 수 없는 주제예요. 목록을 새로 불러왔어요. | `BOT_TOPIC_INVALID` |
| `botBattleBadge` | 연습 | 상세 헤더·기록 카드 배지 |
| `botBattleOpponentLabel` | 연습 상대 | 상대 카드(전적 대신) |
| `botBattleNoEvidence` | 봇은 증거 사진을 내지 않아요. | 상대 증거 자리(진행 중·종결 후) |
| `botBattleOpponentWaiting` | 봇은 기간 안 어느 시각에 완료해요. | 진행 중 상대 영역 |
| `botBattleDoneAtLabel` | 봇 완료 시각 | 종결 후 봇 칸 |
| `botBattleAutoApproved` | 봇은 판정하지 않아 내 사진이 그대로 인정됐어요. | 종결 후 내 제출 설명(`verdict_source='auto'`) |
| `botBattleNoJudgment` | 연습 대결에는 판정이 없어요. 봇은 사진을 내지 않고, 내 사진은 그대로 인정돼요. | 안전망 `judging` 한 줄 |
| `botBattleWon` | 봇보다 먼저 완료했어요. | 결과 부제 |
| `botBattleCompletedLoss` | 기준은 통과했지만 봇이 먼저 완료했어요. | 결과 부제 |
| `botBattleLossNoSubmission` | 사진을 내지 않아 봇이 이겼어요. | 결과 부제 |
| `botBattleErrorSubmissionLocked` | 봇이 완료해서 사진을 바꿀 수 없어요. | 봇전 `SUBMISSION_LOCKED` |

**고치는 기존 문구**(동의·고지 — 오너 승인 사항, 결정 필요 3)

| 키 | 현재 | 바꿀 것 |
|---|---|---|
| `aiConsentRefusal` | 동의하지 않을 수 있어요. 동의하지 않으면 **대결을 만들거나 참가할 수 없고**, 할 일 기능은 그대로 쓸 수 있어요. | 동의하지 않을 수 있어요. 동의하지 않으면 **사람과의 대결(기준 만들기·대결 만들기·참가)을 할 수 없고, 연습 봇과의 대결과** 할 일 기능은 그대로 쓸 수 있어요. |
| `aiConsentRequired` | 동의해야 대결에 참여할 수 있어요. | **사람과 대결하려면 동의가 필요해요. 연습 봇과의 대결은 동의 없이 할 수 있어요.** |
| `aiConsentWithdrawAfter` | 다시 동의하기 전까지 대결을 만들거나 참가할 수 없어요. | 다시 동의하기 전까지 **사람과 대결할 수 없어요. 진행 중인 연습 대결은 그대로 이어져요.** |
| `aiConsentIntro` | 대결 결과는 **AI 심판이 판정해요.** 이를 위해 아래 정보를 해외 AI 사업자에게 제공해요. | 대결 결과는 **먼저 참가자끼리 판정하고, 결론이 나지 않으면 AI가 판정해요.** 이를 위해 아래 정보를 해외 AI 사업자에게 제공해요. ← `TODO_BACKLOG.md`의 [배포 전 필수] 항목이고 같은 단락이라 함께 고친다 |
| `aiConsentWithdrawImpact(active, pending)` | 진행 중인 대결 {active}개는 모두 포기(패배, -3점) 처리되고… | **문구는 그대로.** 숫자가 봇전을 세지 않게 **서버**(`get_consent_withdrawal_impact`)를 고친다 |

**서버 문구 한 곳**: `supabase/functions/_shared/notification_text.ts`의 `finishedText` — payload `is_bot`이 참이면 `completed_loss` 감면 꼬리를 붙이지 않는다(§9).

---

## 13. 초기 주제 8개 (오너 승인용)

선정 기준 다섯을 전부 적용했다 — ① 사진 한 장으로 완료가 보인다 ② 집이나 바로 근처에서 몇 분 안에 ③ 도구·돈·타인 불필요 ④ 얼굴·타인·주소·차량 번호가 찍히기 쉬운 주제 제외 ⑤ 사진으로 증명 불가한 종류(독서·명상·공부 시간) 제외. 기준 문장은 기존 AI 생성 기준의 말투·길이를 따랐다(`"책상 위 물건이 모두 치워져 상판이 드러나 있다"`, `_shared/prompts.ts`: "사진 한 장에서 눈으로 확인할 수 있는 최종 상태로만", 각 100자 이내).

| # | 제목 | 최소 기준 | 기간 |
|---|---|---|---|
| 1 | 설거지하기 | ① 싱크대 안에 씻지 않은 그릇이나 컵이 보이지 않는다<br>② 싱크대 바닥에 음식물 찌꺼기가 남아 있지 않다 | 10분 |
| 2 | 책상 정리하기 | ① 책상 위 물건이 치워져 상판이 드러나 있다<br>② 컵·그릇·포장지 같은 쓰레기가 책상 위에 보이지 않는다 | 10분 |
| 3 | 쓰레기통 비우기 | ① 쓰레기통 안이 비어 있거나 새 봉투가 끼워져 있다<br>② 쓰레기통 주변 바닥에 쓰레기가 떨어져 있지 않다 | 5분 |
| 4 | 이불 정리하기 | ① 이불이 펼쳐진 채 자리 위에 네모지게 정돈돼 있다<br>② 베개가 이불 위쪽 제자리에 놓여 있다 | 5분 |
| 5 | 신발 정리하기 | ① 신발이 코를 같은 방향으로 두고 나란히 놓여 있다<br>② 뒤집히거나 겹쳐 놓인 신발이 보이지 않는다 | 5분 |
| 6 | 물 한 컵 마시기 | ① 다 마신 빈 컵이나 빈 물병이 사진 한가운데에 보인다<br>② 컵 안에 물이 남아 있지 않다 | 5분 |
| 7 | 빨래 개기 | ① 갠 옷가지가 세 벌 이상 쌓여 있다<br>② 옷이 각각 반듯하게 접혀 모양이 흐트러지지 않았다 | 15분 |
| 8 | 방 바닥 치우기 | ① 바닥에 있던 물건이 치워져 바닥면이 드러나 있다<br>② 옷·가방·쓰레기가 바닥에 보이지 않는다 | 15분 |

- **전부 `speed`이고 우열 기준이 없다.** 기준은 2개씩으로 맞췄다(1개는 "아무거나 한 장"에 가깝고, 4~5개는 짧은 기간에 과하다).
- 기간은 **5·10·15분 세 종류**다. 5분은 §4의 하한 계산이 성립하는 가장 짧은 값이고, 15분은 "몇 분 안에 할 수 있다"의 끝이다. 1일·3일·7일 같은 긴 기간은 두지 않았다(기간이 길면 `t_bot`이 멀어져 사실상 무조건 승리다 — spec P0-1).
- **집 안 정리가 여섯 개로 치우쳐 있다**는 점을 적어 둔다. 선정 기준 ①④⑤를 동시에 만족하는 집안일이 사실상 정리·치우기 계열이다. 창문 열기(창밖에 간판·건물이 찍혀 위치가 드러날 수 있다), 산책·외출(얼굴·타인·차량 번호), 독서·스트레칭(사진으로 증명 불가)은 기준에 걸려 제외했다.
- 운영 규칙: **주제 행을 고치지 않는다.** 문장을 바꾸려면 옛 행을 `active = false`로 내리고 새 행을 넣는다(§2.2).

---

## 14. 테스트 계획

| 무엇 | 어디서 | 수단 |
|---|---|---|
| 봇전 점수 매핑(+1 / -1 / -1 / -1, 하한 0) | DB 순수 함수 | **신규** `supabase/tests/bot_battle_rules.sql` — `bot_outcome_score_delta` 전 케이스 + `outcome_score_delta`가 **한 값도 바뀌지 않았는지** 함께 고정(사람 대결 회귀) |
| 승부 판정·전이·점수 반영·한도·공개 범위 | DB 전이 함수 | **신규** `supabase/tests/bot_battle_flow_smoke.sql`(가짜 사용자 1명 + 봇, 마지막에 롤백, 원격 `supabase db query --linked -f`) |
| 기존 규칙 회귀 | DB | `mutual_judge_rules.sql`·`mutual_judge_flow_smoke.sql`·`settle_expired_battles_smoke.sql`·`resolve_battle_smoke.sql`·`forfeit_battle_smoke.sql`·`delete_account_smoke.sql`·`ai_consent_smoke.sql`·`notification_events_smoke.sql`을 **그대로 다시 돌린다**(고친 함수 여섯 개가 전부 이 스모크들의 사정권이다). `battle_submissions.captured_at`의 not null 완화 때문에 픽스처가 깨지지 않는지 함께 본다 |
| N2 문구(봇전 감면 꼬리 없음) | Edge 순수 함수 | `deno test supabase/functions/_shared/` — `notification_text_test.ts`에 `is_bot` 케이스 추가 |
| 화면 분기·문구 선택 | Dart 유닛 | `BattleDetail`의 봇 분기(판정 섹션 미표시·상대 카드 미조회·교체 가능 판단), 결과 부제 선택, 오류 코드→문구, 주제 목록 모델 파싱, 남은 횟수 표시 |
| 주제 고르기·상세·결과 | Dart 위젯 | 주제 카드 N장과 기준 표시, 횟수 0에서 시작 비활성 + 안내, 상세에 **불복 버튼이 없음**, 상대 증거 자리에 안내 문구와 봇 완료 시각, 기록 카드의 `연습` 배지 |
| 실제 카메라·서명 URL·60초 어긋남 구간 체감 | 실기기 | 오너 수동 체크리스트(아래) |

**`bot_battle_flow_smoke.sql` 필수 확인**(spec "빌드·테스트" 체크리스트와 1:1)

1. `start_bot_battle`: `battles` 1행(`is_bot`·`speed`·`active`·`deadline_at = started_at + duration`·기준이 주제와 **같은 값**), 참가자 2행, 봇 제출 행 1행(`object_path is null`·`captured_at is null`·`started + 50% <= submitted_at <= started + 85%`·`submitted_at < deadline_at`), 그리고 **`criteria_checks`·`ai_criteria_calls`·`criteria_cache`·`ai_judgment_jobs`·`notification_outbox`의 행 수가 변하지 않음**(합격선).
2. 하루 3회: 4번째 호출 `BOT_DAILY_LIMIT`. `started_at`을 어제 KST로 밀어 둔 3행 + 오늘 0행 → 다시 3회 가능(**KST 경계**). 포기한 뒤에도 횟수가 돌아오지 않음.
3. 승리: 봇 행 `submitted_at`을 과거로 당겨 `t_bot` 경과를 흉내 → `settle_due_bot_battles()` → `finished`, `winner_id = 사용자`, 사용자 `outcome='win'`·`score_delta_applied = 1`, **`wins`가 0 그대로**, 봇의 `player_stats` 0행.
4. 완료한 패배: `t_bot` 경과 뒤 첫 제출 → **그 트랜잭션에서** `finished`, 사용자 `completed_loss`, 점수 -1.
5. 완료 못 한 패배: 미제출 + 마감 경과 → `settle_expired_battles()` → `loss`, -1.
6. 교체: `t_bot` 전 두 번 교체 → `submitted_at` 갱신 확인. `t_bot` 뒤 교체 → `SUBMISSION_LOCKED`.
7. `settle_my_bot_battles()`가 `t_bot` **전**에는 0을 돌려주고 상태를 바꾸지 않음(즉시 종결하지 않는다는 결정 6).
8. 공개 범위: 사용자 세션으로 `battle_submissions` 조회 — `t_bot` 전 1행(내 것만), 종결 후 2행. `battles`를 아무 컬럼으로 읽어도 `t_bot`이 없다.
9. 알림: 종결 시 사용자 수신 `finished` 1행, **봇 수신 0행**, `judge_turn`·`submitted`·`matched` 0행.
10. `draw`·`voided` 미도달: 위 모든 경로에서 두 상태가 한 번도 나오지 않고 `ai_judgment_jobs`가 0행.
11. 동의: `ai_consents` 행이 없는 사용자가 `start_bot_battle`·제출·종결을 전부 통과. 같은 사용자의 `create_battle`·`join_battle`은 여전히 `CONSENT_REQUIRED`. `withdraw_ai_consent`가 봇전을 **건드리지 않고** 사람 대결만 포기 처리. `get_consent_withdrawal_impact`의 `active_count`가 봇전을 세지 않음.
12. 탈퇴: 진행 중 봇전이 `cancelled`, 점수 변동 0.
13. 봇 노출: `get_player_card(봇)` 예외, `list_open_recruits()`에 봇전·봇 생성자 0건.
14. 권한: anon·authenticated로 `settle_due_bot_battles`·`settle_bot_battle`·`bot_daily_battles_used`·`bot_outcome_score_delta` 실행 거부. authenticated로 `start_bot_battle`·`list_bot_battle_topics`·`settle_my_bot_battles` 실행 허용. `bot_battle_topics`를 authenticated로 직접 select 시 0행 또는 권한 오류.
15. 사람 대결 회귀: 사람끼리 속도전 한 판(양쪽 제출 → 상호 판정 → 종결)에서 점수가 +3/-1, 전적 카운터가 증가.
16. **어긋남 구간의 포기(2026-11-22 추가, §1.6 추기)**: `t_bot` 전에 낸 제출을 봇보다 앞으로 밀고 `t_bot` 경과를 흉내 낸 뒤 `forfeit_battle` → **`BOT_ALREADY_SETTLED`로 거부**되고 그 판은 `win`·`+1`로 끝난다(`forfeited_by`는 null). 따로 **어긋남 구간이 아닌 포기**(`t_bot` 전·미제출)도 한 건 — 그대로 `forfeit/-1`이고 봇이 승자, 알림 0행.
17. **합격선 바로 위의 벽 두 겹**: 정상 종결된 봇전에 `submit_judgment` → `JUDGING_NOT_OPEN`, 억지로 `judging`에 세운 판(자동 승인 행 그대로) → `ALREADY_JUDGED`. 그 두 행을 지우면 **거부되지 않고** `reject`가 들어가며 `ai_judgment_jobs`에 잡이 **생긴다**(양성 대조) — 즉 "`min_verdict='reject'`에 도달할 식이 없다"를 지키는 것이 그 두 겹뿐임을 테스트가 드러낸다. `submit_judgment`의 상대 제출 검사는 평범한 `exists`라 `NOTHING_TO_JUDGE`는 벽이 아니다.
18. **안전망(B10)과 증거 규칙**: 판정 행 없이 `judging`에 세우고 기한을 지난 뒤 `close_expired_judging_windows()` → 3번과 **같은 결론**(자동 승인 2행·`verdict_source='auto'`·`win`·`+1`·잡 0행). 봇전에서도 `accept_submission`의 사진 경로 빈 값·촬영 시각 null·`CAPTURED_BEFORE_START`·`CAPTURE_TIME_MISMATCH` 네 가드가 그대로 작동하고, 네 번의 거부가 상태·내 제출 행을 바꾸지 않는다.

**실기기 체크리스트(오너)**: 5분 주제로 한 판 — 시작 안내가 보이는지, 진행 중 상대 칸 문구, `t_bot` 전 교체, 결과가 뜨는 체감 시각(어긋남 구간), 사진을 내지 않고 마감까지 두는 판 한 번, 포기 한 번, 동의하지 않은 계정으로 한 판.

---

## 15. 적용 순서와 오너 몫

마이그레이션은 **원격에 적용하고 단계마다 오너 확인을 받는다**(로컬 Docker 없음). 세부 파일 목록·커밋 순서는 plan.md 몫이고, 여기서는 **적용 단위와 멈추는 지점**만 정한다.

| 단계 | 스키마 변경 | 내용 | 적용 전 확인 | 적용 후 검증 |
|---|---|---|---|---|
| **1** | **있음(오너 확인)** | `bot_user_id()` + 봇 `profiles` seed + `bot_battle_topics`(+RLS 정책 0개) + **주제 8행** + `battles` 2컬럼·3제약·2인덱스 + `battle_submissions.captured_at` 완화·제약 + `bot_outcome_score_delta` | `select count(*) from battles where opponent_id = public.bot_user_id()` → 0, `select count(*) from battle_submissions where captured_at is null` → 0 | `bot_battle_rules.sql` + 기존 스모크 회귀 |
| **2** | **있음(오너 확인)** | 새 RPC 5개(`list_bot_battle_topics`·`start_bot_battle`·`settle_my_bot_battles`·`settle_bot_battle`·`settle_due_bot_battles`) + `bot_daily_battles_used` + 기존 함수 6개 재정의(§6.3) + cron `settle-bot-battles` 등록 | 1단계 적용 완료 | `bot_battle_flow_smoke.sql` 전 항목 `ok=t`, 기존 스모크 회귀 |
| **3** | 없음 | Dart: 모델(`is_bot`·`capturedAt` nullable)·repository·providers·주제 화면·상세/결과/기록 분기·문구, `notification_text.ts` + `deno test` | — | `flutter analyze` 0, `flutter test` 통과, 실기기 체크리스트 |
| **4** | 없음 | 고지 문구(§12) + `privacy.html` + `TODO_BACKLOG.md`의 [배포 전 필수] 항목 정리 + CLAUDE.md 갱신(도메인 규칙에 봇전 조항, 에러 처리 예외 1줄, cron 주기 1분 정정) | 오너의 문구 승인(결정 필요 3) | 세 자리 문구가 같은 사실을 말하는지 눈으로 대조 |

**1·2단계를 쪼개도 안전한 이유**: 1단계만 적용된 상태에서는 봇전을 시작할 RPC도 화면도 없어 `is_bot = true`인 행이 생길 수 없다. 2단계 적용 **직후** 화면이 없어도(3단계 전) 봇전은 완결 동작한다 — RPC를 직접 불러 끝까지 돌 수 있으므로 스모크가 그 상태에서 전부 통과한다.

**오너가 손수 해야 할 일**
1. 1단계 원격 적용 승인 → 2단계 원격 적용 승인(순서를 지킨다).
2. **주제 8개 표 승인**(§13). 제목·기준 문장·기간을 그대로 쓸지 고칠지.
3. `supabase functions deploy send-notifications`(§9의 문구 변경 때문이고, **이 한 번이 전부다**).
4. 고지 문구 승인 후 `C:\workspaces\todododo-legal`의 방침 문서와 게시본 갱신.
5. 새 시크릿·Vault 변경 **없음**. Gemini 키·cron 시크릿은 건드리지 않는다.

---

## 16. 합격선·수용 기준 대조

| spec 합격선 | 어디서 지켜지나 |
|---|---|
| 봇전 1판의 Gemini 호출 0회 | `start_bot_battle`이 기준을 seed에서 복사(§6.2), 판정 입력이 `auto`+`approve`뿐이라 잡 생성 조건에 도달하지 않음(§3.4), 사진을 아무도 내려받지 않음. 스모크 1·10번이 고정 |
| 기준 생성 10회를 소비하지 않음 | `ai_criteria_calls`에 행이 생기지 않는다(§2.7). 스모크 1번 |
| `criteria-cache`를 읽지도 쓰지도 않음 | 적재 호출이 Edge `battle-criteria` 한 자리에만 있고 봇전이 그 함수를 부르지 않는다(§2.7). 스모크 1번 |
| 새 대결 상태 없음 | §3.1 전이표가 기존 7개 안에서 끝난다 |
| 새 알림 `kind` 없음 | §9. 적재되는 것은 `finished` 하나이고 `notification_outbox.kind` 제약을 건드리지 않는다 |
| 승패·점수·상태가 전부 서버 결정 | 결론은 `resolve_battle`·`mutual_speed_outcome`·`finalize_battle`(§3.3). 클라이언트가 더하는 호출은 인자 없는 멱등 깨우기 하나(§6.2 인용 상자) |
| 증거 규칙 예외가 번지지 않음 | §2.4의 세 겹 보증 |
| 봇전 판정 창에서 묻지 않음(불복 버튼 없음) | §3.2 마지막 줄(서버) + §10.5(화면) |
| `t_bot`을 알 수 없음 | §1.4의 RLS 증명 + 화면·안내 문구에 비율도 숫자도 적지 않음(§10.3) |
| `t_bot`에 끝나고 그보다 일찍·늦게 끝나지 않음 | §1.5의 조항별 매핑, §1.6의 어긋남 구간 명시, §1.7의 결과 불변 증명 |
| 전적이 섞이지 않음 / 점수는 섞임 | §2.6·§3.5 |
| 봇이 사람처럼 나타나지 않음 | §7의 전수 목록 |
| 동의 없이 봇전 가능, 사람 대결은 여전히 막힘 | §8 |
| 사람끼리의 흐름이 한 줄도 바뀌지 않음 | §6.3의 "고치지 않는 것" 목록 + §14의 회귀 스모크 |
| 개인 투두·홈 위젯·알림함 변경 없음 | 이 설계는 그 세 기능의 테이블·함수·화면을 건드리지 않는다 |

---

## 결정 필요 → **2026-11-20 오너 답변 완료**

> 다섯 건 중 **네 건(1·2·3·5)에 답을 받았고 전부 설계 추천대로** 정해졌다. 남은 한 건(4번 — CLAUDE.md
> 에러 토스트 예외 한 줄)은 **기존 예외 다섯 개와 같은 모양이라 따로 묻지 않고 그대로 진행한다.**
> 아래 각 항목의 `→ 결정`을 볼 것. **1번은 spec 본문과 글자가 달라지므로 spec에도 추기가 필요하다**(§아래 1번).

1. **`t_bot`이 지난 뒤 사용자가 처음 제출하면, 그 자리에서 끝낼까 마감까지 기다릴까?**
   spec 본문 6번은 이 경우도 "마감에 판정 창이 열려 종결(냈으면 완료한 패배)"이라고 적었다. 그런데 그 시점에는 **양쪽 제출이 성립**하고 교체도 이미 잠겨 있어 결과가 더 바뀔 수 없다.
   - (a) **그 제출 트랜잭션에서 바로 끝낸다**(설계가 고른 쪽) — 기존 규칙("판정 창은 양쪽 제출 또는 마감 중 먼저 오는 쪽")과 CLAUDE.md("더 이상 결과가 바뀔 수 없으면 마감을 기다리지 않고 즉시 종결")를 그대로 따른다. 사용자가 사진을 낸 직후 결과를 본다. 대가: spec 문장과 글자가 다르다(결과값 -1은 같고 **아는 시점만** 다르다).
   - (b) 마감까지 기다린다 — spec 문장 그대로. 대가: 이미 정해진 결과를 10분 넘게 숨기고, "결과가 바뀔 수 없으면 즉시 종결"이라는 도메인 규칙에 봇전만 예외가 하나 더 생긴다.
   - **추천: (a).** spec의 수용 기준("사용자가 `t_bot`까지 제출하지 않으면 판정 창이 `t_bot`에 열리지 않고 마감에 열린다 — 한쪽만 냈으므로")은 (a)에서도 그대로 참이다(미제출인 동안은 창이 열리지 않는다).
   - **→ 결정: (a)** (설계 추천대로). 낸 자리에서 바로 종결한다. **spec 본문 6번의 "마감에 판정 창이 열려 종결" 문장은 이 결정으로 좁아진다** — `t_bot` 뒤 **첫 제출이 들어오면 그 순간** 창이 열려 종결되고, **끝까지 안 내면** 마감에 열린다. 두 경우 모두 결과값(-1 / -1)은 같고 **아는 시점만** 다르다. developer가 spec에 이 추기를 넣을 것.

2. **N6(마감 임박)가 아직 없는데 봇전을 먼저 배포할까?**
   오너 결정 5가 봇전 벌점을 일률 -1로 깎으면서 "끝까지 하게 만드는 일"이 N6 하나에 걸렸는데, **`enqueue_deadline_reminders`는 아직 구현되지 않았다**(`push-notification` 6단계. 알림함이 그보다 먼저 들어가면서 순서가 바뀌었다). 즉 봇전을 지금 배포하면 그 장치가 사람 대결에도 봇전에도 **아직 없다.**
   - (a) **push-notification 6단계를 봇전 다음(배포 전)에 바로 한다** — 두 기능 모두 배포 전 범위이고, 6단계의 과제가 원래 "짧은 대결에서 문턱을 비례로 재설계"다. 봇전(5~15분)이 그 설계의 가장 짧은 사례라 **함께 보는 것이 오히려 싸다.**
   - (b) 봇전 안에 마감 임박 알림을 따로 만든다 — 합격선("새 kind 없음")에는 걸리지 않지만 적재 지점이 두 곳으로 갈라져 push 6단계가 그것을 다시 합쳐야 한다. **추천하지 않는다.**
   - (c) N6 없이 배포한다 — 사용자는 걸어 놓고 잊고, -1만 쌓인다.
   - **추천: (a).** 봇전 4단계 뒤에 push 6단계를 붙이고, 그 단계의 대상 조건에 봇전을 포함시킨다(§9의 인계 문단이 그 조건을 적어 두었다).
   - **→ 결정: (a)** (설계 추천대로). **봇전 다음에 `push-notification` 6단계를 바로 한다**(둘 다 배포 전). 그 단계의 대상 조건에 봇전(5~15분)을 포함시키고, 문턱을 기간 비례로 재설계하는 원래 과제를 봇전의 짧은 기간과 함께 본다. **즉 봇전만 배포되고 N6가 없는 상태로 끝나지 않는다** — 벌점을 -1로 깎은 대가를 메우는 장치가 그것이므로 이 순서를 지킬 것.

3. **동의 고지·방침 문구(§12)를 이 문장들로 고치는 것을 승인하는가?**
   spec 결정 4가 "좁히는 것"까지는 승인했지만 **실제 문장**은 오너 승인이 필요하다(법적 고지). 네 문구가 함께 바뀌고(`aiConsentRefusal`·`aiConsentRequired`·`aiConsentWithdrawAfter`·`aiConsentIntro`), 그중 `aiConsentIntro`는 `TODO_BACKLOG.md`의 [배포 전 필수] 항목과 **같은 단락**이라 한 번에 처리하는 것이 맞다. 앱 밖 두 자리(`privacy.html`, `todododo-legal`)도 같은 뜻으로 맞춰야 한다.
   - **→ 결정: 승인** (2026-11-20 오너). §12의 네 문장 그대로 간다. `aiConsentIntro`를 함께 고치므로 `TODO_BACKLOG.md`의 **[배포 전 필수] 동의 문구 항목이 이 기능으로 닫힌다** — 닫을 때 그 줄을 백로그에서 지울 것. 앱 밖 두 자리도 같은 뜻으로 맞춘다.

4. **CLAUDE.md 코딩 규칙의 "에러 토스트 예외" 목록에 한 줄을 더하는 것을 승인하는가?**
   봇전 정산 RPC(`settle_my_bot_battles`) 실패를 `debugPrint`만 남기고 토스트를 띄우지 않는다(§10.8). 근거는 기존 예외들과 같다 — 관문이 아니고(cron이 1분마다 같은 일을 한다), 사용자가 할 수 있는 일이 없고, 다음 새로고침에서 저절로 맞는다. **반대로 봇전 시작·제출 실패는 그대로 토스트를 띄운다.** 승인하면 4단계에서 CLAUDE.md에 한 줄을 추가한다.
   - **→ 진행: 추가한다** (오너에게 따로 묻지 않았다). 기존 예외 다섯 개(위젯 캐시 발행, 투두 기한 알림, 위젯 안내 "봤음" 기록, 알림함 읽음 표시·배지·치우기)와 **근거의 모양이 같다** — 관문이 아니고, 사용자가 할 수 있는 일이 없고, 다음 보정에서 저절로 맞는다. **반대로 봇전 시작·제출 실패는 그대로 토스트를 띄운다**는 문장을 함께 적을 것. 오너가 아니라고 하면 되돌린다.

5. **주제 8개 표(§13)를 승인하는가?**
   spec "결정 필요" 4번이 "designer·developer가 만들어 오고 오너는 표만 보고 승인"으로 정해졌다. 제목·기준 문장·기간이 전부 그 표에 있다. 집 안 정리 계열로 치우친 이유도 적었다 — 더 넣고 싶은 주제나 빼고 싶은 주제가 있으면 그것만 알려 주면 된다(주제는 `active` 플래그로 교체하는 구조라 나중에 늘리는 비용이 작다).
   - **→ 결정: 승인** (2026-11-20 오너). §13의 여덟 주제·기준 문장·기간을 그대로 seed에 넣는다. 집 안 정리로 치우친 것도 그대로 받아들였다.
