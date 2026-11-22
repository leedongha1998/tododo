# bot-battle 구현 계획

## 이 문서의 범위

`docs/specs/bot-battle/spec.md`(합격선·수용 기준)와 `design.md`(16절 전체 + 오너 답변 5건)를 읽고 쓴
작업 순서다. **네 단계 전부 구현했다** — 1·2단계(SQL)는 2026-11-20, 3단계(Dart + Edge 문구)와
4단계(고지 문구·문서)는 2026-11-21이다. 남은 것은 **오너 몫**뿐이다(원격 적용 승인,
`send-notifications` 1회 재배포, 방침 문서, 실기기 확인 — 맨 아래 절).

적용 단위는 design §15의 네 단계를 **그대로** 쓴다. 단계마다 오너가 원격에 직접 적용하고,
developer는 **원격 DB를 한 번도 건드리지 않는다**(로컬 Docker 없음, `db push`/`db reset`/`psql`/
`functions deploy` 전부 실행하지 않았다).

---

## 설계·기획과의 충돌 — 없음 (단, 지시문과 어긋난 한 줄이 있다)

CLAUDE.md 도메인 규칙·코딩 규칙, dev-standards, spec.md, design.md를 조항별로 대조했고 **구현을
멈춰야 할 충돌은 없다.** design이 CLAUDE.md와 어긋나는 7곳(증거 규칙·기준 생성·점수표·한도·동의·
모집·전적)은 spec의 "기존 도메인 규칙과 부딪히는 곳"과 오너 결정 1~6이 **이미 명시적으로 예외로
승인한 것**이고, design §CLAUDE.md 대조표가 조항마다 그 근거를 적어 두었다.

다만 **이번 작업 지시문의 한 줄과 design §6.2가 어긋나서, design을 따랐다.**

| 항목 | 지시문 | design §6.2 / 기존 선례 | 내가 쓴 것 |
|---|---|---|---|
| `settle_due_bot_battles`·`settle_bot_battle`의 권한 | `revoke from public, anon, authenticated` **+ `grant to service_role`** | design: "전부 회수, **service_role에도 주지 않는다**". 선례(`settle_expired_battles`·`close_expired_judging_windows`·`dispatch_notifications`·`dispatch_ai_judgments`)도 전부 **service_role 그랜트가 없다** | **service_role에 주지 않았다**(전부 회수) |

근거: CLAUDE.md의 그 예외 문장은 "**Edge Function**·cron 전용 함수"를 말하고, service_role 그랜트가
필요한 이유는 **Edge Function이 JWT를 검증한 뒤 service_role로 그 함수를 부르기 때문**이다
(`begin_criteria_call`·`accept_submission`이 그 모양이다). 이번 두 함수는 **Edge Function이 부르지
않는다** — `settle_due_bot_battles`는 cron(postgres)이, `settle_bot_battle`은 같은 트랜잭션의
SECURITY DEFINER 함수들만 부른다. 그래서 service_role에 주면 **아무도 쓰지 않는 실행 권한이
하나 늘어난다.** 되돌리는 비용은 한 줄(`grant execute on function ... to service_role;`)이므로,
오너가 지시문 쪽을 원하면 2단계 적용 전에 그 줄만 더하면 된다.

**그 밖의 "설계와 다르게 한 것" 3건**은 아래 "## 설계와 다르게 한 것"에 모았다.

---

## 1단계 — 스키마 (SQL, **구현 완료**)

**파일**: `supabase/migrations/20261120120000_bot_battle_schema.sql` (신규)

내용(순서 그대로):

1. `bot_user_id()` — 봇 uuid가 코드에 나타나는 유일한 자리(`…b07b`). `immutable parallel safe`,
   `revoke from public, anon` + `grant to authenticated, service_role`(design §2.1의 근거: CHECK 식에
   들어간다).
2. 봇 `profiles` seed 1행(`연습 봇`, `deleted_at` null, `player_stats` 행 **없음**).
3. `bot_battle_topics` 테이블 + **RLS 켜고 정책 0개** + `revoke all from anon, authenticated`
   (왜 0개가 정답인지 테이블 주석에 적었다).
4. 주제 **8행 seed**(design §13 표를 글자 그대로, `sort_order` 1~8).
5. `battles`: `is_bot`·`bot_topic_id` 2컬럼, 제약 3개, 조건부 인덱스 2개, 주석.
6. `battle_submissions.captured_at` not null 완화 + `check (captured_at is not null or user_id = bot)`.
7. `bot_outcome_score_delta(text)` + EXECUTE 전부 회수.

**적용 전 확인(오너)**: design §15 그대로.

```sql
select count(*) from public.battles where opponent_id = public.bot_user_id();      -- 0 이어야 한다
select count(*) from public.battle_submissions where captured_at is null;          -- 0 이어야 한다
select count(*) from public.profiles where id = '00000000-0000-0000-0000-00000000b07b'; -- 0
```

> 첫 질의는 **1단계 적용 전에는 `bot_user_id()`가 없어서 그대로는 못 돌린다.** 리터럴로 바꿔
> `where opponent_id = '00000000-0000-0000-0000-00000000b07b'`로 확인한다(마이그레이션 머리 주석에도
> 적어 두었다).

**적용 후 검증**
- `supabase db query --linked -f supabase/tests/bot_battle_rules.sql` → `ok` 전부 `t`
- 회귀: `mutual_judge_rules.sql`, `resolve_battle_smoke.sql`, `settle_expired_battles_smoke.sql`,
  `forfeit_battle_smoke.sql`, `delete_account_smoke.sql`, `ai_consent_smoke.sql`,
  `notification_events_smoke.sql`, `mutual_judge_flow_smoke.sql`
  (`captured_at` 완화가 기존 픽스처를 깨지 않는지 함께 본다 — 전부 `captured_at`에 값을 넣고 있어
  영향이 없을 것으로 읽었다. 읽어서 확인한 결과는 아래 "## 기존 테스트 영향").

**커밋 메시지 초안**
```
feat: 봇전 스키마와 주제 묶음을 넣는다

봇 계정(profiles 1행)과 bot_user_id(), 운영자 주제 테이블(bot_battle_topics,
RLS 켜고 정책 0개) + 주제 8행, battles의 is_bot·bot_topic_id와 제약 3개,
봇 제출만 촬영 시각이 없을 수 있게 하는 CHECK, 봇전 전용 점수표를 만든다.
사람 대결의 점수표(outcome_score_delta)는 한 줄도 건드리지 않는다.

docs/specs/bot-battle/design.md §2·§3.5·§13·§15 1단계
```

---

## 2단계 — RPC·기존 함수 재정의·cron (SQL, **구현 완료**)

**파일**: `supabase/migrations/20261120120100_bot_battle_rpc.sql` (신규)

내용(순서 그대로):

1. `bot_daily_battles_used(uuid)` — `battles` 행을 센다(원장 없음). KST 자정 **경계 시각 이상**으로
   비교해 `(creator_id, started_at) where is_bot` 인덱스를 탄다.
2. `list_bot_battle_topics()` — `{daily_limit, daily_left, topics[]}`.
3. `start_bot_battle(uuid)` — 로그인 가드 → advisory lock(`'bot_battle:'||uid`) → 3회 한도 →
   주제 조회 → `battles` insert → 봇 참가자 행 → **봇 제출 행(`submitted_at = t_bot`)**.
   동의 검사·기준 생성·캐시 조회·알림이 **하나도 없다**.
4. `settle_bot_battle(uuid)` — 두 호출자가 공유하는 유일한 몸통(멱등).
5. `settle_due_bot_battles()` — cron용. 한 행씩 예외 흡수.
6. `settle_my_bot_battles()` — 앱용. `creator_id = auth.uid()`로 좁힌 같은 일.
7. **기존 함수 6개 재정의**(§6.3) — 아래 표.
8. cron `settle-bot-battles` 1분 등록.

**고친 기존 함수 6개 — 무엇을 더했나**

| 함수 | 기준으로 삼은 정의 | 더한 것 |
|---|---|---|
| `enqueue_notification(uuid,text,uuid,text,jsonb)` | `20260920120000` | 첫 가드에 `or p_recipient_id = public.bot_user_id()` 한 조건. 봇 수신 행이 원장에 쌓이지 않는다(N2·N3·N5 호출자를 고칠 필요가 없다) |
| `open_judging_window(uuid)` | `20261103120000` | `if v_battle.is_bot then …` **분기 하나를 기존 N4' 적재 앞에** 넣었다: 사용자의 자동 승인 1행(항상) + 봇의 자동 승인 1행(사용자가 냈을 때만) + `has_judged`/봇 `has_submitted` 갱신 + 제출 행 `meets_criteria=true, verdict_source='auto'` + `perform resolve_battle(...)` + `return`(**N4'를 보내지 않는다**). 사람 대결 경로는 한 글자도 안 바뀌었다 |
| `accept_submission(uuid,uuid,text,timestamptz)` | `20261103120000` (시그니처 유지 → `submit-evidence` 재배포 불필요) | ① 동의 검사를 `if not v_battle.is_bot then …`으로 감쌌다 ② 봇전에서 "상대가 제출했는가"를 `exists`가 아니라 **봇 행 `submitted_at <= now()`**로 계산 ③ 내 행이 있고 그 값이 true면 `SUBMISSION_LOCKED`(교체 잠김) ④ 반환 `battle_status`를 `'judging'` 하드코딩에서 **창을 연 뒤 다시 읽은 실제 상태**로 바꿨다(봇전은 `'finished'`) |
| `finalize_battle(uuid,text,uuid,text,text)` | `20261103120000` | 루프 안에 **봇 참가자 건너뛰기**(outcome만 기록, `score_delta_applied`·`player_stats` 행 없음), 점수 delta를 `is_bot`이면 `bot_outcome_score_delta`로, 승/패/무 카운터 세 줄에 `not v_battle.is_bot and …`, N2 payload에 `is_bot` |
| `get_player_card(uuid)` | `20260917120000` | 인자 null 검사 바로 뒤에 `p_user_id = bot_user_id()` → `BOT_NO_STATS` 거부 한 블록 |
| `withdraw_ai_consent()` / `get_consent_withdrawal_impact()` | `20260916120000` | 진행 중 대결 조회(`status in ('active','judging')`)에 `and not is_bot` 한 조건씩. 철회가 봇전을 포기 처리하지 않고 확인 문구의 개수도 봇전을 세지 않는다 |

**고치지 않은 것**(design §6.3의 목록 그대로, 읽어서 확인함): `resolve_battle`·`judging_gate`·
`mutual_speed_outcome`·`min_verdict_effect`·`outcome_score_delta`·`settle_expired_battles`·
`close_expired_judging_windows`·`submit_judgment`·`forfeit_battle`·`delete_account`·`join_battle`·
`create_battle`·`begin_criteria_call`·`list_open_recruits`·`cancel_battle`·`void_battle`·
`claim_notifications`.

**적용 전 확인(오너)**: 1단계 적용 완료.

**적용 후 검증**
- `supabase db query --linked -f supabase/tests/bot_battle_flow_smoke.sql` → `SMOKE RESULT ok=true`
- 1단계와 같은 회귀 목록 + `join_battle_smoke.sql`, `criteria_smoke.sql`, `custom_duration_smoke.sql`,
  `ai_rejudgment_smoke.sql`, `notification_inbox_smoke.sql`
- `select jobname, schedule from cron.job order by jobname;` → 작업 5개, 전부 `* * * * *`

**커밋 메시지 초안**
```
feat: 봇전 시작·정산 RPC와 자동 승인 분기를 넣는다

주제 목록·시작·정산 RPC 5개와 하루 3회 계수 함수를 만들고, 판정 창을 여는
유일한 지점(open_judging_window)에 "봇전은 열리는 순간 끝난다"를 못박는다.
기존 함수 여섯 개는 전부 분기를 더하는 모양이고 사람 대결 경로는 그대로다.
봇전 정산용 cron 작업(settle-bot-battles, 1분)을 등록한다.

판정 로직은 전부 DB에 있고 클라이언트가 부르는 정산 RPC는 인자 없는 멱등
깨우기다(승패 입력이 없다).

docs/specs/bot-battle/design.md §1·§5·§6·§15 2단계
```

---

## 3단계 — Dart + Edge 문구 (**구현 완료**, 2026-11-21)

| # | 파일 | 한 일 |
|---|---|---|
| 3-1 | `lib/features/battle/data/battle_submission.dart` | `capturedAt`을 `DateTime?`로, `fromMap`에 null 분기. **픽스처는 고치지 않아도 됐다** — 이름 붙인 선택 인자로 바꿔 값을 넘기는 기존 호출 세 곳이 그대로 컴파일된다. 대신 `test/features/battle/data/battle_submission_test.dart`(신규)가 "봇 행(사진·촬영 시각 null)을 읽을 수 있다"를 고정한다 |
| 3-2 | `lib/features/battle/data/battle.dart` | `isBot`(기본 false)·`botTopicId` 추가 + 파싱 |
| 3-3 | `lib/features/battle/data/bot_battle_topic.dart`(신규) | `BotBattleTopic`(id·title·minCriteria·durationMinutes) + `BotBattleTopics`(dailyLimit·dailyLeft·topics·`hasLeft`). 파싱 테스트 신규 |
| 3-4 | `lib/features/battle/data/battle_repository.dart` | `listBotBattleTopics`(jsonb→모델)·`startBotBattle`(uuid→String)·`settleMyBotBattles`(integer→int) |
| 3-5 | `lib/features/battle/domain/battle_providers.dart` | `botBattleTopicsProvider` + `_wakeBotSettlement`(실패를 `debugPrint`만 남기는 공용 헬퍼). `myBattlesProvider`는 목록을 읽기 **전에** 한 번, `battleDetailProvider`는 `isBot && active`일 때만 부르고 0보다 크면 대결을 한 번 다시 읽는다 |
| 3-6 | `lib/features/battle/domain/battle_detail.dart`, `bot_battle_rules.dart`(신규), `submission_rules.dart` | getter 여섯 개(`isBot`·`showsJudgmentQuestions`·`showsOpponentStats`·`botDoneAt`·`wasMySubmissionAutoApproved`·`needsBotSettlePolling`) + 결과 부제·시작 오류 문구 매핑 + `submissionErrorMessage(…, isBot:)`. 유닛 테스트 둘(`bot_battle_detail_test.dart`·`bot_battle_rules_test.dart`) |
| 3-7 | `lib/core/strings.dart` | §12 새 문구 **26개** 그대로 |
| 3-8 | `lib/features/battle/presentation/bot_battle_topics_screen.dart`(신규) | 주제 화면(머리·남은 횟수·0회 안내·주제 0건·실패 `다시 시도`·당겨서 새로고침) + `showBotBattleStartSheet`(기준 전문 + 안내 두 줄 + 시작) |
| 3-9 | `battle_detail_screen.dart`·`evidence_section.dart` | `연습` 배지, 봇 상대 줄(전적 조회 안 함), 판정 섹션 미표시 + 안전망 한 줄, 봇 상대 증거 칸, 종결 뒤 봇 완료 시각·자동 인정 설명, 결과 부제 분기, 교체 잠김 문구, 20초 주기 재조회(`_BotSettlePoll`) |
| 3-10 | `battle_recruits_screen.dart`·`my_battles_screen.dart` | 찾기 탭 목록의 **첫 카드**(모집 0건·실패에서도 그린다) + 내 대결 빈 상태의 보조 `TextButton` |
| 3-11 | `lib/features/profile/presentation/battle_records_screen.dart` | 기록 카드에 `연습` 배지 |
| 3-12 | `supabase/functions/_shared/notification_text.ts` + 테스트 | `softened` 조건에 `payload.is_bot !== true`. 케이스 3개 추가(봇전 완료한 패배/사람 대결/봇전 승). **배포는 하지 않았다 — 오너가 `send-notifications` 1회 재배포** |

**위젯 테스트**: `test/features/battle/bot_battle_test.dart`(신규, 11건) — 주제 카드·기준 표시, 횟수 0에서
시트가 열리지 않음, 시트가 봇·점수·하루 3회를 말하고 **비율·숫자를 적지 않음**, 시작이 주제 id 하나만
보냄, 상세에 **판정 질문이 없음**·전적 조회 0회·판정 마감 줄 없음, 안전망 한 줄, 종결 뒤 세 경우의 부제,
기록 카드 배지.

**커밋 초안**(화면 하나 = 커밋 하나)
```
feat: 봇전 모델·레포지토리·정산 깨우기를 넣는다

battle_submissions.captured_at이 null일 수 있게 하고(봇 제출만 그렇다),
battles의 is_bot·bot_topic_id를 읽고, 주제 모델과 RPC 세 개를 넣는다.
내 대결 목록·봇전 상세는 읽기 전에 정산을 한 번 깨운다 — 인자 없는 멱등
호출이라 결과를 바꾸지 않고 아는 시점만 당긴다.

docs/specs/bot-battle/design.md §2.4·§6.2·§10.9
```
```
feat: 연습 대결 주제 고르기 화면을 넣는다

운영자 주제 묶음을 보여 주고 확인 시트에서 시작한다. 시작 전에 상대가 봇이라는
것·기준 전문·+1점·하루 3회를 말하고, 봇의 목표 시각은 비율도 숫자도 적지 않는다.

docs/specs/bot-battle/design.md §10.2·§10.3
```
```
feat: 봇전 상세·결과 분기를 넣는다

연습 배지, 전적 없는 상대 줄, 판정 섹션 미표시(묻는 것이 없다), 봇 증거 칸의
사실 안내, 종결 뒤 봇 완료 시각과 자동 인정 설명, 결과 부제 세 가지를 넣는다.
봇의 목표 시각이 지난 뒤의 어긋남 구간을 줄이려고 20초 주기로 다시 읽는다.

docs/specs/bot-battle/design.md §10.4·§10.5·§10.6·§10.9
```
```
feat: 봇전 입구 두 자리와 기록 배지를 넣는다

찾기 탭 목록의 첫 카드와 내 대결 빈 상태의 보조 버튼에서 주제 화면으로 간다.
지난 기록 카드에는 연습 배지를 붙여 사람과의 승패와 섞여 보이지 않게 한다.

docs/specs/bot-battle/design.md §10.1·§10.7
```
```
fix: 봇전 종결 알림에서 감면 꼬리를 떼낸다

봇전은 완료한 패배와 미착수가 둘 다 -1이라 "기준을 통과해서 감점이 줄었어요"가
거짓이다. N2 payload의 is_bot으로 그 꼬리만 뺀다(kind는 늘리지 않는다).

docs/specs/bot-battle/design.md §9 · 배포: send-notifications 1회
```

**검증 결과**: `flutter analyze` **No issues found**, `flutter test` **989 passed**,
`deno test supabase/functions/_shared/` **63 passed / 0 failed**.
실기기 체크리스트(design §14 마지막)는 **2단계가 원격에 적용된 뒤 오너 몫**이다.

---

## 4단계 — 고지 문구·문서 (**구현 완료**, 2026-11-21)

| # | 파일 | 한 일 |
|---|---|---|
| 4-1 | `lib/core/strings.dart` | `aiConsentIntro`·`aiConsentRefusal`·`aiConsentRequired`·`aiConsentWithdrawAfter` 네 문장을 §12의 승인된 문장으로 교체(왜 바뀌었는지 주석으로 남겼다) |
| 4-2 | `privacy.html` | **이 저장소에 그 파일이 없다.** 저장소 전체를 찾았고(`find`/`grep`) 방침 본문은 **별도 저장소 `C:\workspaces\todododo-legal`에만** 있다(`DEPLOY.md` 140·147줄이 그 위치를 가리킨다). 즉 4-2와 4-3이 같은 파일이라 **오너 몫**이다 — 아래 "오너가 손수 해야 할 일" 6번 |
| 4-3 | 별도 저장소 | **건드리지 않았다**(지시대로) |
| 4-4 | `TODO_BACKLOG.md` | [배포 전 필수] 동의 문구 줄을 **지웠다**(이 기능이 닫았다) + "사용자 검색이 생기면 연습 봇을 결과에서 빼야 한다" 한 줄 추가(§7-8, `profiles` 백필 주의도 함께) |
| 4-5 | `CLAUDE.md` | 도메인 규칙에 봇전 조항 한 줄(`대결은 2인만` 바로 앞), 에러 토스트 예외 1줄(§10.8). cron 주기 정정은 **이미 되어 있어 다시 하지 않았다** |

**커밋 초안**
```
docs: 동의 고지를 봇전 기준으로 좁힌다

거부 시 불이익이 "대결 전체"에서 "사람과의 대결"로 좁아진다 — 봇전은 나가는
데이터가 없어 동의 없이 할 수 있고, 철회로 포기되지도 않는다. 첫 문장도 현행
판정 구조(1차 상호 판정 + 2차 AI)로 고쳐 백로그의 배포 전 필수 항목을 닫는다.

docs/specs/bot-battle/design.md §12 · 오너 승인 2026-11-20
```
```
docs: 봇전 규칙을 CLAUDE.md에 적는다

도메인 규칙에 봇전 한 조항(새 상태·새 판정 경로·새 kind 없음, 사진 없는 제출은
봇만, 점수 ±1, 하루 3회, 전적 미반영, 동의 불필요)과 에러 토스트 예외 한 줄을
더하고, 사용자 검색이 생길 때 봇을 빼야 한다는 것을 백로그에 남긴다.
```

**4단계 뒤에 `push-notification` 6단계(N6 마감 임박)를 바로 한다**(design 결정 필요 2 → (a)).
봇전 벌점을 일률 -1로 깎은 대가를 메우는 장치가 N6 하나이므로 이 순서를 지킨다.

---

## 스모크 SQL (이번 차례에 구현 완료)

| 파일 | 무엇 |
|---|---|
| `supabase/tests/bot_battle_rules.sql` | 순수 함수 표 테스트. `bot_outcome_score_delta` 전 케이스 + **`outcome_score_delta`가 한 값도 바뀌지 않았는지 함께 고정**(사람 대결 회귀) + `bot_user_id()` 고정값 + `is_criteria_list`로 검사한 seed 8행의 모양·기간·정렬 |
| `supabase/tests/bot_battle_flow_smoke.sql` | design §14의 필수 확인 1~15를 한 `do $$` 블록에서. 마지막에 `raise exception`으로 전체 롤백 |

**합격선을 검사하는 항목**(spec "합격선" 1:1):

| 합격선 | 스모크 키 |
|---|---|
| Gemini 호출 0회 | `calls_delta`·`checks_delta`·`cache_delta`·`jobs_rows` 네 개가 전부 0(= `ai_criteria_calls`·`criteria_checks`·`criteria_cache`·`ai_judgment_jobs`에 행이 생기지 않음). 시작·제출·교체·종결·마감 정산을 **전부 돌린 뒤** 센다 |
| 기준 생성 10회 미소비 | `limits_calls_left` = 10 (`get_my_limits`가 그대로다) |
| 캐시 미접촉 | `cache_delta` = 0 |
| 새 상태 없음 | `status_set` = 끝난 상태들이 `finished`뿐, `draw_voided_count` = 0 |
| 새 kind 없음 | `kinds` = `finished` 하나, `bot_recipient_rows` = 0 |
| 승패는 서버가 정한다 | 사용자가 보내는 값은 주제 id 하나다. `settle_before_tbot`이 0을 돌려주고 상태를 바꾸지 않는 것으로 "클라이언트 호출이 결과를 당기지 못한다"를 고정 |

`now()`가 트랜잭션 내내 고정이라 **시간 경과는 행을 과거로 미는 방식으로 흉내 낸다**
(봇 행 `submitted_at`을 과거로, KST 경계는 `started_at`을 어제로). `pg_sleep`은 쓰지 않는다.

---

## design §16 합격선 대조 — 내 SQL이 각 줄을 지키는지

| spec 합격선 | design이 적은 자리 | **내 SQL에서** | 지켜지나 |
|---|---|---|---|
| 봇전 1판의 Gemini 호출 0회 | §6.2·§3.4 | `start_bot_battle`에 `begin_criteria_call`·`lookup_criteria_cache`·`put_criteria_cache`·`ensure_ai_judgment_job` 호출이 **없다**(기준은 `bot_battle_topics` 행에서 복사). 판정 입력이 `approve`+`auto` 두 행뿐이라 `resolve_battle`의 잡 생성 조건(`min_verdict = 'reject'`)에 **도달할 식이 없다** | ✅ |
| 기준 생성 10회 미소비 | §2.7 | `ai_criteria_calls`에 insert하는 자리는 `begin_criteria_call` 하나이고 봇전 경로가 그 함수를 부르지 않는다 | ✅ |
| `criteria-cache` 읽지도 쓰지도 않음 | §2.7 | 2단계 파일에 `criteria_cache`라는 식별자가 **한 번도 나오지 않는다**(주석의 "쓰지 않는다" 설명 제외) | ✅ |
| 새 대결 상태 없음 | §3.1 | `battles_status_check`를 건드리지 않았다. 봇전이 쓰는 값은 `active`·`judging`·`finished`·`cancelled`뿐 | ✅ |
| 새 알림 `kind` 없음 | §9 | `notification_outbox_kind_check`를 건드리지 않았다. 적재되는 것은 기존 `finished` 하나이고, `open_judging_window` 봇 분기는 `judge_turn`을 **보내지 않는다** | ✅ |
| 승패·점수·상태가 전부 서버 결정 | §3.3 | 결론은 `mutual_speed_outcome`(**한 줄도 안 고쳤다**) → `finalize_battle`. 앱이 보내는 값은 주제 id 하나와 인자 없는 `settle_my_bot_battles()` | ✅ |
| 증거 규칙 예외가 번지지 않음 | §2.4 | 세 겹 그대로: ① `battle_submissions`에 insert/update 정책 0개 ② `accept_submission`의 `p_object_path` 빈 값·`p_captured_at is null` 거부를 **그대로 뒀다** ③ 새 CHECK가 `captured_at is null`을 봇 행으로 제한 | ✅ |
| 판정 창에서 묻지 않음 | §3.2 | 창이 열리는 순간 사용자 판정 행이 PK로 이미 있고 같은 트랜잭션에서 `finished`가 되므로 `submit_judgment`가 `ALREADY_JUDGED`/`JUDGING_NOT_OPEN`에 걸린다(`submit_judgment`를 고치지 않았다) | ✅ |
| `t_bot`을 알 수 없음 | §1.4 | `t_bot`은 `battle_submissions`의 봇 행 한 곳에만 있고 `battles`에 컬럼을 더하지 않았다. 그 행의 select 정책(`judging_opened_at is not null or status in (...)`)을 건드리지 않았다 | ✅ |
| `t_bot`에 끝나고 그보다 일찍·늦게 끝나지 않음 | §1.5 | 일찍: `accept_submission`이 봇전에서 `judging_gate`에 넘기는 "상대 제출"이 `submitted_at <= now()`라 `t_bot` 전에는 `wait`. 늦게: cron 1분 + `settle_my_bot_battles` + `t_bot` 뒤 첫 제출 트랜잭션 | ✅(지연 상한 60초는 design §1.6이 받아들인 비용) |
| 전적이 섞이지 않음 / 점수는 섞임 | §2.6·§3.5 | `finalize_battle`이 봇전에서 `score`만 갱신하고 `wins/losses/draws` 세 줄에 `not v_battle.is_bot`을 걸었다. 봇의 `player_stats` 행은 만들지 않는다 | ✅ |
| 봇이 사람처럼 나타나지 않음 | §7 | 1 구조적(제약) · 2 `BOT_NO_STATS` · 3 `enqueue_notification` 가드 · 4 N4' 미적재 · 5 `player_stats` 행 없음 · 6 `and not is_bot` · 9 `deleted_at` null. 7·8·10·11은 SQL에서 할 일이 없다(화면·백로그·의도된 노출) | ✅ |
| 동의 없이 봇전 가능, 사람 대결은 여전히 막힘 | §8 | `accept_submission` 한 곳만 갈랐다. `begin_criteria_call`·`create_battle`·`join_battle`의 동의 검사를 **읽어서 확인하고 그대로 뒀다** | ✅ |
| 사람끼리의 흐름이 한 줄도 바뀌지 않음 | §6.3 | 고친 6개 전부 `if is_bot`/`not is_bot`/`and not is_bot`을 **더하는** 모양이고, 사람 경로의 조건·점수·문구·payload 키 집합은 그대로다(단 N2 payload에 `is_bot` 키가 **양쪽 모두** 붙는다 — 아래 "다르게 한 것" 2번) | ✅ |
| 개인 투두·홈 위젯·알림함 변경 없음 | — | `todos`·`todo_*`·`notification_seen*`·`dismiss_notification`·`list_notifications`·`has_new_notifications`를 건드리지 않았다 | ✅ |

---

## 설계와 다르게 한 것

1. **`settle_due_bot_battles`·`settle_bot_battle`에 service_role 그랜트를 주지 않았다.**
   위 "## 설계·기획과의 충돌"의 표 — design §6.2와 기존 선례를 따랐고 지시문과 어긋난다.
   되돌리는 비용은 한 줄이다.

2. **N2 payload의 `is_bot`을 "봇전일 때만"이 아니라 `v_battle.is_bot` 값 그대로 담았다.**
   design §6.3은 "`is_bot: true` 추가"라고 적었다. 분기 없이 한 식으로 담으면 **사람 대결 N2에도
   `is_bot: false`가 붙는다.** 그래도 이렇게 쓴 이유: (a) 서버 문구 쪽 조건이
   `payload.is_bot !== true` 한 줄로 끝나 **키가 없는 옛 행과 새 행을 같은 식으로 읽는다**,
   (b) 분기를 더하면 사람 경로에 `if`가 하나 생긴다. 금지 키(`reason`·`object_path`·
   `display_name`·`winner_id`)가 아니고 `notification_events_smoke.sql`이 payload 전체 일치를
   검사하지 않는 것을 **읽어서 확인했다**(키 존재/부재만 본다).

3. **`settle_bot_battle`이 대결 행을 못 찾으면 `null`을 돌려준다.** design은 반환을
   "호출 뒤 상태(text)"로만 적었고 없는 대결을 말하지 않았다. `'missing'`이라는 **없는 상태 이름을
   만들지 않기 위해** null로 뒀다(두 호출자는 `is distinct from 'active'`로만 보므로 동작이 같다).

4. **`settle_my_bot_battles`도 한 행씩 예외를 흡수한다.** design은 cron 쪽만 그렇게 적었다.
   흡수하지 않으면 `myBattlesProvider`가 **목록을 읽기 전에** 이 RPC를 부르므로(§10.9) 한 대결의
   예외가 **내 대결 탭 전체를 오류 화면으로** 만든다. `raise warning`으로 서버 로그는 남긴다.

5. **`withdraw_ai_consent`/`get_consent_withdrawal_impact`의 `pending` 조회에는
   `and not is_bot`을 넣지 않았다.** 넣을 필요가 없다 — `battles_bot_opponent_check`가
   `is_bot ⇒ opponent_id = 봇`을, `battles_bot_topic_pair_check`가 그 역을 보장하므로
   **`status='pending'`인 봇전 행은 구조적으로 존재할 수 없다**(모집 행은 `opponent_id`가 null이다).
   제약이 이미 증명하는 것에 중복 필터를 넣지 않는 것은 design §7-1과 같은 판단이다.
   그 근거를 두 함수 주석에 적었다.

### 3·4단계에서 더 생긴 것 (2026-11-21)

6. **`submissionErrorMessage`에 `isBot` 선택 인자를 더했다.** design §6.4는 "`SUBMISSION_LOCKED`은
   봇전 전용 문구로 갈린다"까지만 적었다. 같은 코드·같은 서버 판단인데 사용자가 읽는 사실이 다르므로
   **문구만** 갈리게 했고, 다른 코드(마감·촬영 시각)는 봇전에서도 같은 문구임을 테스트로 고정했다.
7. **봇 상대 줄을 `PlayerCardView`로 그리지 않고 `_BotOpponentRow`를 새로 만들었다.** 그 위젯은
   전적이 없는 카드를 `playerStatsUnknown`("탈퇴한 사용자")로 설명하는데, **봇은 묘비가 아니다**
   (design §2.1이 `deleted_at`을 null로 두는 이유와 같다). 공용 위젯을 건드리지 않는 쪽을 골랐다.
8. **주제 카드는 `CriteriaChecklistBox`(점 목록), 확인 시트는 `CriteriaListBlock`(번호 + 제목·힌트)을
   쓴다.** design §10.2는 "`criteria_views.dart`의 목록 위젯 재사용"까지만 적었다. 카드에서는 제목이
   이미 주인공이라 번호 목록이 무게를 더 가져가고, 시트에서는 "최소 기준"이라는 제목이 필요하다.
9. **봇전 `judging`(안전망)에서 `RevealedEvidenceSection`을 그리지 않는다.** design §10.5가 "한 줄만
   보여 준다 + 당겨서 새로고침"이라고 적었으므로 그대로 따랐다(사람 대결의 판정 뒤 화면과 다르다).
10. **20초 주기 재조회의 조건 판단을 `BattleDetail.needsBotSettlePolling`으로 올렸다.** 화면 안의
   조각(`_BotSettlePoll`)은 그 getter만 읽고 타이머를 건다 — 상태 전이 조건을 위젯에 쓰지 않는다는
   dev-standards 규칙을 따른 것이고, 덕분에 "언제 도는가"가 유닛 테스트로 고정된다.
11. **`recruit_browse_test.dart`의 두 단정을 `모집 2` → `모집 0`으로 바꿨다.** 입구 카드가 목록의 첫
   칸을 차지해 세 번째 카드가 기본 시험 화면(800x600) 밖으로 밀려 **빌드되지 않는다**. 두 테스트가
   보려는 것은 "걸러졌던 카드가 돌아왔는가"이고 `모집 0`도 걸러졌던 카드라 **의도는 그대로**다.
12. **가짜 레포지토리 7곳에 봇 메서드 3개를 더했다**(`noSuchMethod`가 없어 `implements`가 깨지는
   파일들). 셋 다 아무 일도 하지 않는 구현이다.

---

## 결정 필요 (구현을 멈추지 않고 합리적 기본값으로 채운 것)

1. **`privacy.html`이 이 저장소에 없다.** 4-2가 가리키는 파일이 별도 저장소
   `C:\workspaces\todododo-legal`에만 있어(`DEPLOY.md` 140·147줄) **그 서술은 손대지 못했다.**
   기본값: 이 저장소 쪽(앱 문구)만 고치고, 방침 쪽은 "오너가 손수 해야 할 일" 6번에 **맞춰야 할
   사실 세 가지**로 적어 두었다. 지금 앱과 방침이 **다른 말을 하고 있으므로 배포 전에 닫아야 한다.**
2. **내 대결 탭의 진행 중 카드에는 `연습` 배지를 넣지 않았다.** design §10이 입구·상세·기록
   세 자리만 적었고 그 카드에는 상대 이름(`연습 봇`)이 이미 보인다. 기본값: 범위를 늘리지 않는다.
   오너가 실기기에서 모자라다고 보면 `battle_summary_list.dart`에 한 줄로 더할 수 있다.
3. (1·2단계에서 넘어온 것) **`settle_due_bot_battles`·`settle_bot_battle`의 service_role 그랜트** —
   위 "설계·기획과의 충돌"의 표. 2단계 원격 적용 **전에** 한 번 보기.

---

## 추측으로 쓴 곳 · 적용 후 확인이 필요한 것

SQL을 **한 번도 실행하지 못했다**(로컬 Docker 없음, 원격 금지). 아래는 기존 코드의 선례로 뒷받침되는
것과 그렇지 않은 것을 가른 목록이다.

**선례가 있어 자신 있는 것** (각각 같은 모양이 이미 원격에서 돌고 있다)
- `insert … on conflict (battle_id, judge_id) do nothing` 뒤의 `if found` → `close_expired_judging_windows`
- SECURITY DEFINER가 RLS를 우회해 `battle_submissions`·`battle_participants`에 쓰는 것 → `accept_submission`
- `for update skip locked` 루프 + 행마다 `begin … exception when others then raise warning` → `settle_expired_battles`
- `pg_advisory_xact_lock(hashtext(...))` → `begin_criteria_call`
- `make_interval(mins => …)` → `join_battle`
- `cron.schedule('이름', '* * * * *', $$select …$$)`로 작업 추가·갱신 → `notification_dispatch`
- CHECK 제약이 `public.*` 함수를 부르고 그 함수의 EXECUTE를 `public, anon`에서만 회수하는 것 → `is_criteria_list`

**적용 후 확인이 필요한 것**

| # | 무엇 | 왜 확신이 덜한가 | 확인 방법 |
|---|---|---|---|
| 1 | `make_interval(secs => …)`의 인자 타입 | `secs`는 `double precision`이고 `greatest(int,int)`는 `integer`다. 암묵 캐스팅에 기대지 않고 **`::double precision`을 명시해 두었다**(이 저장소의 선례는 `mins => integer`뿐이다). 남는 불확실성은 `0.35 * random()`의 타입 해석뿐이고 그것도 numeric→float8 암묵 캐스팅이다 | 2단계 적용 직후 `select public.start_bot_battle(<주제 id>)` 한 번 |
| 2 | `t_bot` 분포가 실제로 50~85%에 들어가는가 | `random()`이 걸려 수식만으로는 한 판을 못 본다 | `bot_battle_flow_smoke.sql`의 `tbot_ratio_ok`·`tbot_before_deadline`이 20판을 뽑아 고정한다 |
| 3 | KST 경계 비교식 `started_at >= (((now() at time zone 'Asia/Seoul')::date)::timestamp at time zone 'Asia/Seoul')` | 기존 한도는 `kst_date = date`로 비교해서 **경계 시각으로 비교한 선례가 없다**. 이중 `at time zone`의 방향을 잘못 쓰면 9시간 어긋난다 | 스모크의 `limit_kst_*` 두 항목(어제 3판 → 오늘 3판 가능)이 고정한다. 원격 적용 후 `select public.bot_daily_battles_used(auth.uid())`도 가능 |
| 4 | `select b.id from battles b where … and exists (…) order by b.started_at for update skip locked` | `exists` 서브질의가 있는 질의에 `for update`를 붙인 선례가 없다(기존은 서브질의 없는 `select *`). 문법상 `battles`만 잠그는 것으로 읽었다 | 2단계 적용 직후 `select public.settle_due_bot_battles();` 한 번(0을 돌려주면 성공) |
| 5 | 조건부 인덱스 `(started_at) where is_bot and status = 'active'`를 cron 질의가 실제로 타는가 | 계획을 볼 수 없다 | `explain select …`(기능에는 영향 없음. 활성 봇전이 수십 행일 때는 어느 쪽이든 빠르다) |
| 6 | **봇 행의 `started_at`이 null이면 한도에 세지 않는다** | `battles.started_at`은 여전히 nullable이고 "is_bot이면 not null"이라는 제약을 **design이 적지 않아 넣지 않았다**. 지금은 `start_bot_battle`만 봇전 행을 만들고 거기서 항상 `now()`를 넣으므로 실제 구멍이 아니다 | 원격 적용 후 `select count(*) from battles where is_bot and started_at is null;` → 0. 0이 아니면 제약을 더한다 |
| 7 | `revoke all on table public.bot_battle_topics from anon, authenticated` 뒤 authenticated의 직접 select | Supabase 기본 그랜트(`anon`/`authenticated`)의 정확한 집합을 원격에서 확인하지 못했다. RLS 정책 0개와 revoke가 **둘 다** 막으므로 어느 쪽이든 결과는 0행/권한 오류다 | 스모크의 `topics_rls_rows`(0 또는 권한 오류 → 0으로 접는다) |
| 8 | `battles`에 CHECK 제약 3개를 더할 때 기존 행 검증이 통과하는가 | 원격 `battles`의 실제 내용을 볼 수 없다 | **1단계 적용 전 확인 질의**(위)로 오너가 먼저 본다. 사람 대결 행은 `is_bot=false`·`bot_topic_id=null`이라 세 식 모두 참이다 |

**3·4단계에서 더 생긴 것 — 실제 호출로 확인하지 못했다**(SQL이 아직 원격에 없다)

| # | 무엇 | 추측의 근거 | 확인 방법 |
|---|---|---|---|
| 9 | RPC 세 개의 반환을 Dart가 그대로 읽는다 — `jsonb` → `Map`, `uuid` → `String`, `integer` → `int` | 같은 모양의 선례가 있다: `get_my_limits`(jsonb → `MyLimits.fromMap`), `create_battle`(uuid → `String`), `update_battle_criteria`(integer → `num`). `list_bot_battle_topics`의 `topics`는 jsonb 배열이라 `List`로 와서 원소를 `Map<String, dynamic>.from`으로 받는다(`OpenRecruitPage.fromRows`와 같은 처리) | 2단계 적용 후 주제 화면을 한 번 열어 보기 |
| 10 | `battles` select에 `is_bot`·`bot_topic_id`가 함께 온다 | 앱은 `from('battles').select()`로 **전 컬럼**을 읽으므로 컬럼이 생기면 자동으로 온다(`Battle.fromMap`은 없으면 기본값 false/null로 떨어진다 — 그래서 1단계 적용 전에도 깨지지 않는다) | 같은 확인 |
| 11 | 봇의 완료 시각이 **종결 전에는 오지 않는다** | `battle_submissions`의 기존 select 정책에 기대고 있다(design §1.4). 앱은 받은 행을 그대로 그리므로, 정책이 생각과 다르면 **진행 중 화면에 봇 완료 시각이 뜬다** | 실기기 체크리스트에서 **진행 중 화면에 시각이 보이지 않는지**를 눈으로 본다(스모크 8번이 같은 것을 SQL로 본다) |
| 12 | `settle_my_bot_battles`가 봇전이 하나도 없는 사용자에게도 빠르다 | 내 대결 탭을 열 때마다 왕복 하나가 더 생긴다. 서버 쪽은 조건부 인덱스 스캔 0행이라 싸다고 읽었다 | 실기기에서 내 대결 탭 전환이 느려지지 않는지 |
| 13 | 20초 주기 재조회가 봇전 상세에서만 돈다 | 조건은 유닛 테스트로 고정했지만(`needsBotSettlePolling`) **실제 요청 수는 보지 못했다** | 실기기에서 봇전 상세를 2분 켜 두고 결과가 60초 안에 뜨는지(어긋남 구간 체감) |
| 14 | **내 대결 탭의 진행 중 카드에는 `연습` 배지를 넣지 않았다** | design §10이 입구·상세·기록 세 자리만 적었고, 그 카드에는 상대 이름(`연습 봇`)이 이미 보인다. 범위를 늘리지 않는 쪽을 골랐다 | 오너가 실기기에서 보고 모자라면 한 줄로 더한다 |

---

## 기존 테스트 영향 (읽어서 확인했다)

- **`captured_at` not null 완화가 기존 스모크를 깨지 않는다.** `supabase/tests/*.sql`에서
  `battle_submissions`에 insert하는 자리를 전부 읽었고 **모두 `captured_at`에 값을 넣는다**
  (`settle_expired_battles_smoke.sql:98`, `mutual_judge_flow_smoke.sql`, `resolve_battle_smoke.sql`,
  `ai_rejudgment_smoke.sql`, `notification_events_smoke.sql`). not null을 **푸는** 방향이라
  값이 있는 insert는 그대로 통과한다.
- **`mutual_judge_rules.sql`의 점수 케이스 5개가 그대로 통과한다.** `outcome_score_delta`를
  건드리지 않았고, `bot_battle_rules.sql`이 같은 5개를 **한 번 더** 고정한다(두 파일이 어긋나면
  사람 대결 점수가 바뀐 것이다).
- **`notification_events_smoke.sql`은 payload 전체 일치를 보지 않는다**(키 존재·금지 키 부재만).
  N2에 `is_bot` 키가 붙어도 통과한다.
- **`ai_consent_smoke.sql`·`delete_account_smoke.sql`**: `withdraw_ai_consent`·
  `get_consent_withdrawal_impact`에 `and not is_bot`만 더했고, 그 테스트의 대결은 전부 사람
  대결(`is_bot=false`)이라 조건이 항상 참이다.
- **Dart·Deno**(1·2단계 시점): `lib/`와 `supabase/functions/`를 한 줄도 고치지 않았다.
  **2단계가 원격에 적용되고 3-1(`capturedAt` nullable)이 아직 안 된 구간에는, RPC를 손으로
  불러 만든 봇전의 종결 상세를 앱이 열면 `fetchSubmissions`가 깨진다**(design §2.4의 경고).
  **3단계가 끝난 지금은 그 구멍이 닫혔다** — `capturedAt`이 nullable이고 테스트가 그것을 고정한다.

**3·4단계가 기존 테스트에 준 영향**(2026-11-21, 전부 돌려서 확인했다)
- **가짜 레포지토리 7곳**(`noSuchMethod`가 없는 것들)에 봇 메서드 3개를 더해야 했다.
  `implements BattleRepository`이므로 레포지토리에 메서드가 생기면 컴파일이 깨진다.
- **`recruit_browse_test.dart` 두 건**이 입구 카드 때문에 깨져 단정을 `모집 0`으로 옮겼다
  (위 "다르게 한 것" 11번).
- 그 밖의 위젯 테스트는 **한 건도 손대지 않았다.** `settleMyBotBattles` 실패를 삼키는 설계가
  (design §10.8) 가짜 레포지토리의 `UnimplementedError`까지 함께 흡수하므로, 봇전을 모르는
  테스트들이 그대로 지나간다.
- `flutter analyze` **No issues found** / `flutter test` **989 passed** /
  `deno test supabase/functions/_shared/` **63 passed, 0 failed**.

---

## 작업 순서를 바꾼 기록

없다. design §15의 1 → 2 → 3 → 4를 그대로 따랐다(1·2단계는 2026-11-20, 3·4단계는 2026-11-21).

3단계 안의 순서도 위 표의 3-1 → 3-12 그대로 했다. **3-7(문구)만 3-6과 3-8 사이가 아니라 더 일찍
손댔다** — 3-8·3-9의 화면이 그 문구 없이는 컴파일되지 않아서다. 순서를 바꾼 것이 아니라
같은 묶음 안에서 먼저 쓴 것이고, 커밋은 화면 단위로 갈라 둔다(위 커밋 초안).

(순서를 바꾸게 되면 이 절에 이유를 적는다.)

---

## 오너가 손수 해야 할 일 (design §15 그대로)

1. 1단계 원격 적용 승인 → 스모크 확인 → 2단계 원격 적용 승인(**순서를 지킨다**).
2. 2단계 적용 **전에** 위 "다르게 한 것" 1번(service_role 그랜트)을 어느 쪽으로 할지 한 번 보기.
3. 3단계 뒤 `supabase functions deploy send-notifications` **1회**(문구 변경 때문. 이게 전부다).
4. 4단계에서 `C:\workspaces\todododo-legal`의 방침 문서·게시본 갱신.
5. **새 시크릿·Vault 변경 없음.** Gemini 키·cron 시크릿을 건드리지 않는다.
6. **`privacy.html`의 "거부 시 불이익" 서술을 앱 문구와 맞추기** — 그 파일이 **이 저장소에 없다**
   (별도 저장소 `todododo-legal`에만 있다). 앱의 네 문장이 2026-11-21에 바뀌었으므로 방침이
   지금은 **앱과 다른 말을 하고 있다.** 맞춰야 할 사실 셋: ① 거부 시 불이익은 "사람과의 대결
   (기준 만들기·대결 만들기·참가) 불가"이고 **연습 봇과의 대결과 할 일 기능은 쓸 수 있다**
   ② 판정은 **1차 참가자 상호 판정 + 2차 AI 재판정**이다(옛 "AI 심판" 서술을 고친다)
   ③ **철회해도 진행 중인 연습 대결은 이어진다**(사람 대결만 포기 처리된다).
7. **실기기 체크리스트**(design §14 마지막) — 5분 주제로 한 판, 진행 중 상대 칸 문구,
   `t_bot` 전 교체, 결과가 뜨는 체감 시각(어긋남 구간 ≤60초), 사진을 내지 않고 마감까지 두는 판,
   포기 한 번, **동의하지 않은 계정으로 한 판**. 2단계가 원격에 적용된 뒤에 한다.

---

## 2026-11-22 — 리뷰 지적 수정 (5단계)

reviewer가 1~4단계를 본 뒤 고친 것. **Critical은 없었고** 지적 두 건(W1·W3)과 리뷰어가 놓친 문구
버그 하나를 고쳤다. 커밋 13개(`0b131f8`..`de52690`)로 1~4단계가 이미 푸시된 뒤의 수정이고,
**2단계 마이그레이션은 원격에 적용되지 않았으므로 새 마이그레이션을 만들지 않고 그 파일을 고쳤다.**

| # | 무엇 | 파일 |
|---|---|---|
| W1 | **어긋남 구간의 포기가 확정된 승리(+1)를 포기 패배(-1)로 뒤집었다.** `forfeit_battle`을 **7번째 재정의 함수**로 추가해, 봇전이면 포기 전에 `settle_bot_battle`을 먼저 부르고 상태를 다시 읽어 이미 끝난 판이면 `BOT_ALREADY_SETTLED`로 거부한다 | `20261120120100_bot_battle_rpc.sql` |
| W1 | 그 거부를 "실패"로 말하지 않는다. `isBotAlreadySettled`·`botBattleForfeitErrorMessage`, `_forfeit`에 `isBot` 인자 | `bot_battle_rules.dart`, `battle_detail_screen.dart` |
| 추가 | **리뷰어가 놓친 것**: 포기 확인 대화상자가 봇전에서도 "3점이 깎여요"라고 말했다(봇전은 1점). W2와 달리 **봇전을 포기하는 모든 사용자가 보는** 거짓 문장이었다 | `strings.dart`(`botBattleForfeitConfirm`) |
| W3 | 합격선 바로 위의 공백(벽 두 겹·안전망·증거 규칙)을 음성 테스트로 고정. 키 99개 → 120개 | `bot_battle_flow_smoke.sql` |
| 문서 | design §1.6의 "이것은 버그가 아니다"를 추기로 뒤집고(지우지 않았다), §14에 필수 확인 16~18 추가 | `design.md` |
| 문서 | 사람 대결에도 같은 구간이 있다는 것을 백로그로 넘겼다(봇전만 고친 이유를 함께 적었다) | `TODO_BACKLOG.md` |

**W1을 앱이 아니라 서버에서 고친 이유**: 앱에서 포기 직전에 정산을 깨우면 **두 호출 사이에 cron이
들어온다.** 같은 트랜잭션·같은 행 잠금 안에서만 빈틈이 없다.

**거부가 정산까지 되돌린다 — 그래도 맞다**: 예외가 함수 밖으로 나가면 방금 한 정산도 롤백되므로
거부 직후 대결은 아직 `active`이고 결과는 cron이 1분 안에 쓴다. 지켜야 할 것은 "포기가 커밋되지
않는다"이고 그것은 지켜진다. 그래서 앱 문구도 "이미 결과가 나왔다"가 아니라 **"곧 결과가 나와요"**다.

**스모크를 쓰면서 드러난 사실 하나(브리프가 틀렸다)**: `submit_judgment`의 상대 제출 검사는 평범한
`exists`라 **봇 제출 행이 `t_bot` 전에도 "제출함"으로 읽힌다.** 그래서 `NOTHING_TO_JUDGE`는 벽이
아니고, 봇전이 Gemini를 부르지 못하게 막는 것은 `JUDGING_NOT_OPEN`과 `ALREADY_JUDGED` **두 겹뿐**이다.
`judge_gap_*` 양성 대조가 그 사실을 드러낸다 — 그 두 겹 중 하나가 무너지면 테스트가 먼저 말한다.

**검증**: `flutter analyze` 0건 / `flutter test` 989건 / `deno test` 63건. **스모크 SQL은 여전히
한 번도 실행하지 못했다**(로컬 Docker 없음, 원격 미적용) — 적용 뒤 첫 실행에서 실패 키의 접두사로
원인이 갈린다: `forfeit_*`는 W1 전제, `judge_*`는 벽 두 겹의 순서, `safety_*`는 자동 승인,
`evidence_*`는 마이그레이션 문구, `a_stats`/`safety_stats`는 점수 산술.
