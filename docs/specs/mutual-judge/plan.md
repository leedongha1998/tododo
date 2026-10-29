# mutual-judge 구현 계획

입력: `spec.md`(오너 승인 2026-09-18, D1~D9 확정), `design.md`(오너 승인 2026-09-18, 결정 사항 1~4 확정).
순서는 design.md "구현 단계 분할" 5단계를 그대로 따른다. 이 문서는 그 표의 **파일 목록·커밋·검증 방법을 확정**한 것이다.
화면 규칙은 `docs/specs/retro-theme/design.md` 3장을 그대로 쓴다(같은 역할의 요소를 새로 모양 짓지 않는다).

## 공통 규칙 (ai-judge/plan.md 선례 그대로)
- 각 커밋 전: `flutter analyze` 이슈 0 + `flutter test` 전부 통과. TypeScript를 건드린 단계는 `deno test supabase/functions/_shared/`도 통과.
- **원격 DB 적용은 단계마다 오너 확인 후.** 에이전트는 `supabase db push`, `supabase migration up`, 쓰기·DDL이 섞인 `supabase db query --linked`, `supabase storage rm`, `supabase functions deploy`, `supabase functions delete`, `supabase secrets set`, Vault 접근을 실행하지 않는다. 읽기 전용(`migration list --linked`, 파일 읽기)만 한다.
- 단계 순서: 로컬 구현 → analyze/test → **오너 승인 → 오너가 원격 적용 → 오너가 SQL 테스트 실행 → 통과하면 커밋.** SQL 테스트가 실패하면 고치는 마이그레이션을 **새 파일로** 추가한다(적용된 파일은 수정하지 않는다).
- SQL 테스트는 로컬 Docker가 없어 원격에서만 돈다. 쓰기가 있는 스모크는 마지막에 `raise exception`으로 전체를 롤백하고 결과를 예외 메시지로 돌려준다. 규칙 테스트는 SELECT만 한다.
- 스모크에서 **파괴적 호출(탈퇴·취소·삭제·정산) 뒤에 상태를 읽지 않는다.** 읽을 값은 호출 전에 변수로 잡아 둔다(ai-judge 4단계에서 실제로 났던 버그).
- `RAISE`의 `%%`는 리터럴 퍼센트다. 결과 줄은 `raise exception 'SMOKE RESULT ok=% %', v_ok, v_detail;` 형태로 쓴다.
- 커밋: `<type>: <한국어 설명>` + 이유 본문 + `Co-Authored-By` 줄. 새 화면 하나 = 커밋 하나. push 없음.
- 시크릿 값은 파일·로그·커밋·보고에 쓰지 않는다. 새 시크릿은 없다(Gemini 키·모델·cron 시크릿은 현재 값 그대로).

## 착수 전 확인 (2026-09-18)
- `supabase/migrations/` 로컬 22개(마지막 `20260920120000_push_tokens_and_outbox.sql`). 설계 전제대로 ai-judge 1~7단계 + push-notification 1단계가 원격에 적용돼 있다고 본다(원격 목록 확인은 오너 몫 — 에이전트는 원격을 읽지 않았다).
- `supabase/tests/` 10개, Edge Function 3개(`battle-criteria`, `submit-evidence`, `judge-quality`)가 배포된 상태.
- 기준선: `flutter analyze` 이슈 0, `flutter test` 273개 통과, `deno test supabase/functions/_shared/` 26개 통과(ai-judge 7단계 종료 시점 수치).

## CLAUDE.md·dev-standards 충돌 점검 결과

**구현을 멈춰야 하는 충돌은 없다.** 아래는 전부 오너가 이미 해소한 것이고, 근거를 각 항목에 적었다.

| CLAUDE.md 조항 | 어긋나는 내용 | 해소 근거 |
|---|---|---|
| 도메인 규칙 "기간(`battles.duration_hours`, 1일/3일/7일)" | 1단계가 컬럼과 허용값을 분 단위(1~10080)로 바꾼다 | spec.md "P0. 커스텀 마감"(오너 승인) + design.md 조항 대조표 10행이 **부분 대체**로 판정. **CLAUDE.md 문구 갱신은 5단계**(design "구현 단계 분할") |
| 도메인 규칙 "`settle_expired_battles()` … pg_cron이 5분마다" | 1단계가 1분으로 바꾼다 | 같음(design "cron 주기") |
| 도메인 규칙의 판정 주체·속도전 5회·품질전 단일 AI 판정·진행 중 합격/불합격 공개·`judging`의 뜻 | 2·3단계가 대체한다 | spec.md "판정 주체" 조항 대체(오너 승인) + design 조항 대조표 2·5·6·8·9행. 문구 갱신은 5단계 |

**1~4단계 동안 CLAUDE.md 문구와 코드가 어긋나는 것은 의도된 과도기다**(ai-judge/plan.md와 같은 방식). 5단계에서 design 조항 대조표의 **대체·부분 대체 행만** 근거로 고치고 범위를 넓히지 않는다.

지킨 규칙(1단계에 해당하는 것만):
- 스키마 변경은 마이그레이션 파일로만. 새 컬럼 제약·주석을 같은 파일에서 붙였다.
- 사용자용 RPC(`create_battle`)는 재생성 후 `revoke execute ... from public, anon` + `grant execute ... to authenticated` + 첫 줄 로그인 가드를 다시 붙였다(드롭하면 권한이 함께 사라진다).
- cron 전용 `settle_expired_battles`는 1단계에서 **본문을 건드리지 않고** `cron.schedule` 주기만 갱신했다(권한·가드 예외 구조 그대로).
- 판정 로직을 클라이언트로 내리지 않았다. 1단계가 만지는 것은 기간 입력·표시뿐이다.
- 사용자에게 보이는 문자열은 전부 `lib/core/strings.dart`.
- "테스트 없이 판정 로직 수정 금지": 1단계는 판정 로직을 수정하지 않는다(`resolve_battle`·`speed_outcome`·`quality_outcome`·`accept_submission`·`record_speed_verdict` 미변경). 2·3단계에서 규칙 테스트와 함께 바꾼다.

---

## 5단계 분할 (확정)

| 단계 | 스키마 | 내용 | Edge 재배포 | 상태 |
|---|---|---|---|---|
| 1 | 있음 | 기존 대결 데이터 정리 + 커스텀 마감(분 단위) | `battle-criteria` | **원격 적용·스모크 통과(2026-09-18)** |
| 2 | 있음 | 판정 창·제출 교체·상호 판정 기록·자동 승인·결론 규칙(즉시 AI 판정 제거) | `submit-evidence`(적용 직후) | **원격 적용·SQL 테스트 12개 통과(2026-10-28)** |
| 3 | 있음 | AI 재판정 재배선 | `judge-dispute` 신규 / `judge-quality` 삭제 | **원격 적용·SQL 테스트 14개 통과·`judge-quality` 삭제 완료(2026-10-29)** |
| 4 | 없음 | 판정 화면·제출 교체 화면 | - | **구현 완료(미커밋) — 3단계보다 먼저 했다** |
| 5 | 없음 | 결과·공개·상태 줄·문서·문구 | - | 미착수 |

---

## 1단계 — 기존 데이터 정리 + 커스텀 마감

### 1-a. 기존 대결 삭제

파일: `supabase/migrations/20260921120000_mutual_judge_reset.sql`
- `delete from public.battles;` 한 문장. cascade로 `battle_participants`·`battle_submissions`·`quality_judgments`·`daily_battle_slots`·`criteria_checks.battle_id` 관련 행이 함께 정리된다.
- **오너 승인 2026-09-18**(design 결정 사항 3). 사라지는 것: 진행 중 1건 + 모집 9건(더미 8 + "셀카 찍기" 1).
- 남는 것: 더미 계정 8개(`%@dummy.invalid`)와 그 `profiles`·`player_stats`, `criteria_checks`·`ai_criteria_calls`·`ai_consents`, `notification_outbox`·`device_tokens`.
- **Storage 사진은 이 마이그레이션에 넣지 않는다.** `storage.protect_delete()` 트리거 때문에 SQL로 지울 수 없다. 적용 직후 오너가 아래 "원격 적용 체크리스트"의 `storage rm`을 실행한다(ai-judge 1단계와 같은 절차).
- **되돌릴 수 없다.**

### 1-b. 커스텀 마감 (`duration_hours` → `duration_minutes`)

파일: `supabase/migrations/20260921120100_custom_duration.sql`
1. `battles.duration_minutes integer` 추가 → `update ... = duration_hours * 60` → `not null` + `default 1440` + `battles_duration_minutes_check check (between 1 and 10080)` → `battles_duration_hours_check` 드롭 → `duration_hours` 드롭. 컬럼 주석 갱신.
   - 1-a가 `battles`를 비우므로 `update`는 실제로 0행을 고친다. **그래도 문장을 남긴다** — 마이그레이션은 행이 있는 환경에서도 같은 결과를 내야 하고, 1-a 없이도 되돌릴 수 있어야 한다(design 지시).
2. `drop function public.create_battle(uuid, integer);` → `create function public.create_battle(p_check_id uuid, p_duration_minutes integer)`로 재생성.
   - **`create or replace`로는 못 고친다.** 인자 타입이 `(uuid, integer)`로 같고 이름만 바뀌므로 PostgreSQL이 `cannot change name of input parameter`로 거부한다.
   - 본문은 `20260916130000_ai_criteria.sql`의 정의를 그대로 옮기고 검증만 `not in (24,72,168)` → `is null or < 1 or > 10080`으로 바꾼다. 로그인 가드·동의 검사·증서 검사·모집 1개·하루 한도·`unique_violation` 처리는 한 줄도 바꾸지 않는다.
   - **드롭하면 GRANT도 사라진다.** 재생성 뒤 `revoke execute ... from public, anon` + `grant execute ... to authenticated`를 다시 쓴다.
3. `create or replace function public.join_battle(uuid, integer)` — `20260917120000`의 최신 정의를 그대로 옮기고 `make_interval(hours => v_battle.duration_hours)` → `make_interval(mins => v_battle.duration_minutes)` 한 줄만 바꾼다. **시그니처 유지**이므로 GRANT는 그대로 남는다.
4. `create or replace function public.list_open_recruits()` — 반환 jsonb 키 `duration_hours` → `duration_minutes`. 시그니처 유지.
5. cron `settle-expired-battles` 주기 `*/5 * * * *` → `* * * * *`. 같은 이름으로 `cron.schedule`을 다시 부르면 기존 작업이 갱신된다(ai-judge 6단계 선례). **`settle_expired_battles()` 본문과 권한은 건드리지 않는다.**

**1단계에서 건드리지 않는 것(명시)**: `accept_submission(uuid,uuid,text,timestamptz)`, `record_speed_verdict(bigint,text,text,text)`, `resolve_battle`, `finalize_battle`, `void_battle`, `speed_outcome`, `quality_outcome`, `quality_deadline_outcome`, `settle_expired_battles` 본문, `forfeit_battle`, `delete_account`, `quality_judgments`, Storage 정책, `battle_participants`·`battle_submissions` 스키마.
→ 이유: 배포된 `submit-evidence`가 `accept_submission`과 `record_speed_verdict`를 부른다. 시그니처를 건드리면 적용 직후 앱이 깨지고 재배포 순서가 필요해진다. **그것은 2단계 몫이다.** 적용 후에도 옛 판정(즉시 AI·5회)이 그대로 돌아가야 한다.

### Edge Function (`battle-criteria`만)
- `supabase/functions/_shared/schemas.ts`: `DURATION_HOURS = [24,72,168]` 삭제 → `DURATION_MINUTES_MIN = 1` / `DURATION_MINUTES_MAX = 10080`. `CriteriaRequest.durationHours` → `durationMinutes`, 입력 키 `duration_hours` → `duration_minutes`, 검증은 "1~10080 정수"(`Number.isInteger`로 소수 거부).
- `supabase/functions/_shared/prompts.ts`: `TAG_NAMES`와 `COMMON_RULES`의 `duration_hours` → `duration_minutes`, `CriteriaPromptInput.durationMinutes`, `buildGenerateUserText`·`buildCheckUserText`의 `<duration_hours>` 태그 → `<duration_minutes>`.
- `supabase/functions/battle-criteria/index.ts`: **변경 없음**(`request` 객체를 그대로 프롬프트 빌더에 넘긴다).
- 테스트: `schemas_test.ts`(경계값 1·10080 통과, 0·10081·소수·문자열 거부), `prompts_test.ts`(`<duration_minutes>` 태그, 판정 본문에 기간이 새지 않음).

### Dart
- `lib/features/battle/data/battle.dart`: `durationHours` → `durationMinutes`(기본 1440), `fromMap`의 `duration_minutes`.
- `lib/features/battle/data/battle_repository.dart`: `createBattle({checkId, durationMinutes})` → RPC 인자 `p_duration_minutes`. **PostgREST가 인자 이름으로 RPC를 찾으므로 마이그레이션과 같은 단계에서 함께 바꿔야 한다**(안 바꾸면 `create_battle`을 못 찾아 즉시 깨진다).
- `lib/features/battle/data/battle_criteria_repository.dart`: `durationHours` → `durationMinutes`, 본문 키 `duration_minutes`.
- `lib/features/battle/domain/duration_rules.dart`(신규, 순수 함수): 범위 상수, `DurationUnit`(분/시간/일), `durationMinutesOf(text, unit)`, `validateDurationMinutes(minutes)`.
- `lib/features/battle/presentation/battle_chips.dart`: `battleDurationLabel(int minutes)`(일→시간→분 순으로 떨어지는 단위를 고른다).
- `lib/features/battle/presentation/create_battle_screen.dart`: 빠른 선택 5개(30분·1시간·1일·3일·7일) + "직접 입력"(정수 + 단위) + 안내 3줄.
- `lib/features/battle/presentation/{recruit_detail_sheet.dart,battle_recruits_screen.dart,edit_recruit_criteria_screen.dart}`: `durationMinutes` 전달.
- `lib/core/strings.dart`: 기간 라벨을 포맷 함수 3개로 교체, 빠른 선택·직접 입력·범위 오류·경고 2줄 추가.
- 테스트: `test/features/battle/domain/duration_rules_test.dart`(신규), `test/features/battle/create_battle_test.dart`(기본값·직접 입력·범위 오류), 가짜 저장소 6곳과 `Battle` 픽스처의 인자 이름 갱신.

### 기존 스모크 영향 (검토 결과 — 실행은 오너·메인 세션)

`duration_hours`를 참조하는 스모크 **8개**를 1단계에서 함께 고쳐야 한다. 안 고치면 컬럼이 없어 전부 `column "duration_hours" of relation "battles" does not exist`로 죽는다.

| 파일 | 조치 |
|---|---|
| `ai_consent_smoke.sql` | insert 컬럼명 5곳 + 값 7곳 |
| `ai_judge_flow_smoke.sql` | 컬럼명 2곳 + 값 2곳 |
| `criteria_smoke.sql` | 컬럼명 3곳 + 값 3곳 + `create_battle(check, 72/24/168)` 호출 5곳의 값 |
| `delete_account_smoke.sql` | 컬럼명 3곳 + 값 3곳 |
| `forfeit_battle_smoke.sql` | 컬럼명 3곳 + 값 3곳 |
| `push_token_smoke.sql` | 컬럼명 3곳 + 값 3곳 |
| `resolve_battle_smoke.sql` | 컬럼명 3곳 + 값 3곳 |
| `settle_expired_battles_smoke.sql` | 컬럼명 8곳 + 값 8곳 |
| `join_battle_smoke.sql` | 컬럼 참조 없음. `create_battle` **위치 인자** 호출 3곳의 값만(인자 이름이 바뀌어도 위치 호출은 깨지지 않는다) |
| `battle_outcome_rules.sql` | **영향 없음**(순수 함수 SELECT만) |

- 값은 시간→분으로 환산한다(24→1440, 72→4320, 168→10080). 이 픽스처들은 `deadline_at`을 직접 넣으므로 `duration_minutes`가 계산에 쓰이지 않지만, 숫자가 "24분"으로 읽히면 다음 사람이 오해한다.
- 기간 검증 문구(`기간이 올바르지 않습니다.`)를 확인하는 스모크는 없다. 새 경계값(0분·10081분) 검증은 신규 `custom_duration_smoke.sql`이 덮는다.

### 신규 SQL 테스트
`supabase/tests/custom_duration_smoke.sql`(쓰기 있음 → 마지막에 예외로 롤백)
- 1분·30분·10080분 대결 생성 성공, 0분·10081분·null 거부.
- 직접 insert의 `battles_duration_minutes_check`가 0·10081을 막는다.
- `join_battle`이 `deadline_at = started_at + 분`을 **초 단위로 정확히** 계산한다(1분·30분).
- `list_open_recruits()`가 `duration_minutes` 키를 돌려주고 `duration_hours` 키가 없다.
- anon으로 `create_battle` 권한 오류, `authenticated`로 `settle_expired_battles` 권한 오류(드롭·재생성으로 권한이 새지 않았는지).
- 주의: `public.battles` 직접 insert에는 `min_criteria`가 필수고 속도전은 `superiority_criteria`가 null이어야 한다. 한 사람당 `pending` 모집은 1개다. `join_battle`은 2인자다.

### 커밋 단위 (원격 적용·SQL 테스트 통과 후 — **이번 세션에서는 커밋하지 않는다**)
1. `chore: 옛 판정 규칙 대결 데이터 정리` — `20260921120000_mutual_judge_reset.sql`만.
2. `feat: 대결 기간을 분 단위 커스텀으로` — `20260921120100_custom_duration.sql`, 스모크 9개 수정 + 신규 1개, Edge `_shared/{schemas,prompts}.ts` + 두 테스트, Dart 모델·저장소·도메인·라벨, 관련 테스트.
3. `feat: 짧은 기간 경고와 기간 입력 화면` — `create_battle_screen.dart` + `strings.dart`의 화면 문자열 + 화면 테스트(화면 하나 = 커밋 하나).
   - 2와 3은 같은 원격 상태를 전제로 하므로 연달아 커밋한다.

### 로컬 검증
- `flutter analyze` 이슈 0, `flutter test` 전부 통과.
- `deno test supabase/functions/_shared/` 통과(에이전트 실행 가능 — Gemini를 부르지 않는다).
- grep: `lib/`·`supabase/`·`test/`에 `duration_hours`·`durationHours`·`DURATION_HOURS` 참조 0건.

### 원격 적용 체크리스트 (오너 — 순서 그대로)
1. `supabase db push --dry-run` — 새 파일 2개(`20260921120000_mutual_judge_reset.sql`, `20260921120100_custom_duration.sql`)만 나오는지 확인.
2. `supabase db push`
3. `supabase migration list --linked` — 로컬 24개 = 원격 24개.
4. **Storage 비우기**(1-a의 나머지 절반): `supabase storage rm -r ss:///battle_evidence/ --linked --experimental`
   - 버킷 자체는 남긴다(2단계에서 새 정책으로 재사용).
5. `supabase functions deploy battle-criteria` — 앱이 `duration_minutes`를 보내므로 옛 함수는 `duration_hours는 24, 72, 168 중 하나여야 합니다.`로 전부 거부한다. **적용 직후 배포.**
6. SQL 테스트:
   - `supabase db query --linked -f supabase/tests/custom_duration_smoke.sql` → `SMOKE RESULT ok=t`
   - `supabase db query --linked -f supabase/tests/criteria_smoke.sql` → `ok=t`
   - `supabase db query --linked -f supabase/tests/join_battle_smoke.sql` → `ok=t`
   - `supabase db query --linked -f supabase/tests/settle_expired_battles_smoke.sql` → `ok=t`
   - `supabase db query --linked -f supabase/tests/resolve_battle_smoke.sql` → `ok=t`
   - `supabase db query --linked -f supabase/tests/forfeit_battle_smoke.sql` → `ok=t`
   - `supabase db query --linked -f supabase/tests/delete_account_smoke.sql` → `ok=t`
   - `supabase db query --linked -f supabase/tests/ai_consent_smoke.sql` → `ok=t`
   - `supabase db query --linked -f supabase/tests/ai_judge_flow_smoke.sql` → `ok=t`
   - `supabase db query --linked -f supabase/tests/push_token_smoke.sql` → `ok=t`
   - `supabase db query --linked -f supabase/tests/battle_outcome_rules.sql` → 23행 모두 `ok = true`
7. cron 확인: `select schedule from cron.job where jobname = 'settle-expired-battles';` → `* * * * *`

### 에뮬레이터 수동 확인 (원격 적용 후)
- 내 대결·대결 찾기·프로필이 오류 없이 열림(기존 대결이 모두 사라져 빈 상태).
- 대결 만들기: 빠른 선택 5개가 보이고, "직접 입력"에서 `0`·`10081`분이 즉시 오류 문구, `1`분이 통과.
- 두 계정으로 1분 대결 생성 → 참가 → 마감 1분 뒤 cron이 정산(최대 2분 대기).
- 모집 목록·모집 상세의 기간 칩이 새 라벨로 보임.

### 되돌리기 어려운 지점
- **1-a의 `delete from public.battles`와 Storage 비우기**: 되돌릴 수 없다. 오너 승인 근거는 design 결정 사항 3.
- **`duration_hours` 드롭**: 컬럼과 값이 사라진다. 1-a로 행이 0이라 실제 잃는 데이터는 없지만, 컬럼을 되살리려면 역방향 마이그레이션을 새로 써야 한다.
- **`create_battle` 드롭·재생성**: 드롭과 재생성 사이(같은 트랜잭션)에는 함수가 없다. `db push`는 파일 단위 트랜잭션이므로 실패하면 통째로 롤백된다. 다만 **적용이 성공한 뒤 옛 앱 빌드는 `p_duration_hours`로 호출해 실패한다** — 실사용자가 없어 감수한다(설계 판단).
- **cron 주기 변경**: `cron.schedule` 재호출로 되돌릴 수 있다(파괴적이지 않다).

---

## 2단계 — 판정 창·제출 교체·상호 판정 (착수 메모)

- 마이그레이션 `..._judging_window.sql`: `battles` 3컬럼(`judging_opened_at`·`judge_deadline_at`)·제약 2개·인덱스 2개, `battle_participants` 컬럼 교체(`first_submitted_at`·`attempts_used`·`last_verdict`·`passed_at` 드롭 / `has_submitted`·`has_judged` 추가) + **정책 `participants can view their battle progress`는 유지하고 "이 테이블의 모든 컬럼은 상대 참가자도 읽는다" 불변식 주석만 추가**, `battle_submissions` 재편(`status`·`judging_started_at` 드롭, 부분 유니크 3개 → `unique (battle_id, user_id)`, `verdict_source` 추가), `battle_judgments` 신규 + RLS, 순수 함수 4개(`judging_gate`·`min_verdict_effect`·`mutual_speed_outcome`·`mutual_quality_outcome`) 생성 + 옛 3개 드롭, `open_judging_window`·`resolve_battle`·`settle_expired_battles`·`close_expired_judging_windows`·`submit_judgment`, `accept_submission` 재정의(**시그니처 유지**), `record_speed_verdict`·`sweep_stale_submissions` 드롭 + `sweep_stale_criteria_calls` 신설, Storage select/insert 정책 교체, cron `close-judging-windows` 등록 + `ai-judge-tick` 명령 갱신.
- Edge: `submit-evidence/index.ts`(Gemini 호출 제거, 교체 사진 삭제 추가). **적용 직후 재배포 필수** — 옛 함수가 드롭된 `record_speed_verdict`를 부른다.
- SQL 테스트: 신규 `mutual_judge_rules.sql`·`mutual_judge_flow_smoke.sql`, 기존 `settle_expired_battles_smoke.sql`·`resolve_battle_smoke.sql`·`ai_judge_flow_smoke.sql` 교체, 나머지 스모크는 새 컬럼에 맞춰 최소 수정.
- Dart: `battle_submission.dart`·`battle_participant.dart`·`battle_detail.dart`·`battle_summary.dart`·`submission_rules.dart` + 테스트. 판정 화면은 4단계이므로 상세에는 "판정 기능은 준비 중" 안내만.
- 커밋: `feat: 판정 창과 상호 판정 기록 스키마` / `feat: 속도전 제출 교체` / `refactor: 제출 즉시 AI 판정 제거`.
- 검증: 규칙 테스트 전 케이스, 흐름 스모크 `ok=t`, 두 번째 계정으로 진행 중 상대 `battle_submissions` 0행·서명 URL 발급 실패 / 창 열린 뒤 1행.

### 2단계 원격 적용 체크리스트 (오너 — 순서 그대로, 2026-10-28 작성)

로컬 구현은 `af017f7`로 커밋·푸시됐다. 모든 명령은 `C:\workspaces\todododo`에서 실행한다.

1. `supabase db push --dry-run` — 새 파일 **1개**(`20260922120000_judging_window.sql`)만 나오는지 확인. 다른 파일이 같이 나오면 멈추고 원인부터 본다.
2. `supabase db push`
3. **즉시** `supabase functions deploy submit-evidence` — 2와 3 사이에는 속도전 제출이 전부 실패한다(배포된 옛 함수가 드롭된 `record_speed_verdict`를 부른다). 2가 끝나면 다른 것 보지 말고 이것부터 한다.
4. `supabase migration list --linked` — 로컬 25개 = 원격 25개, 마지막이 `20260922120000`.
5. cron 확인: `supabase db query --linked "select jobname, schedule, command from cron.job order by jobname;"`
   - `close-judging-windows`가 새로 있고 `* * * * *`.
   - `ai-judge-tick` 명령이 `select public.sweep_stale_criteria_calls(); select public.dispatch_quality_judgments();`.
   - `settle-expired-battles`는 `* * * * *` 그대로.
6. SQL 테스트 — 순서 그대로, 앞이 깨지면 뒤를 돌리지 않는다. 쓰기가 있는 스모크는 마지막에 롤백하므로 원격 데이터는 그대로다.
   1. `supabase db query --linked -f supabase/tests/mutual_judge_rules.sql` → 39케이스 전부 `ok=t`, 요약 행(`case_no 99`)이 `39케이스 / 39 통과 / t`
   2. `supabase db query --linked -f supabase/tests/mutual_judge_flow_smoke.sql` → `SMOKE RESULT ok=t`
   3. `supabase db query --linked -f supabase/tests/ai_judge_flow_smoke.sql` → `ok=t`
   4. `supabase db query --linked -f supabase/tests/resolve_battle_smoke.sql` → `ok=t`
   5. `supabase db query --linked -f supabase/tests/settle_expired_battles_smoke.sql` → `ok=t`
   6. 회귀(순서 무관): `forfeit_battle_smoke.sql` / `delete_account_smoke.sql` / `criteria_smoke.sql` / `join_battle_smoke.sql` / `ai_consent_smoke.sql` / `push_token_smoke.sql` / `custom_duration_smoke.sql` → 각 `ok=t`
   - **`battle_outcome_rules.sql`은 이번 단계에서 삭제됐다. 돌리지 말 것**(검증 대상 함수 `speed_outcome`·`quality_outcome`·`quality_deadline_outcome`이 드롭됐고 `mutual_judge_rules.sql`이 대체한다).
7. 에뮬레이터 확인(아래 "에뮬레이터 수동 확인"): 두 계정으로 속도전 제출·교체까지. 판정 화면은 4단계이므로 창이 열리면 "판정 기능은 준비 중" 안내만 보이는 것이 정상이다.

#### 이번 단계에서 하지 않는 것
- **Storage 정리 불필요** — 이 마이그레이션은 사진을 지우지 않고 정책만 교체한다(1단계에서 남은 고아 사진 8장은 대시보드 정리 대기 그대로).
- **`judge-quality` 삭제·Vault 값 교체 없음** — 3단계 몫. 테이블·함수는 살아 있지만 새 잡이 생기지 않아 무해하다.
- `create_battle`/`join_battle`/`list_open_recruits`는 손대지 않았다(1단계 상태 그대로).

#### 되돌리기 어려운 지점
- `battle_participants`(`first_submitted_at`·`attempts_used`·`last_verdict`·`passed_at`)·`battle_submissions`(`status`·`judging_started_at`) 컬럼 드롭 — 1단계 reset으로 대결이 0건이라 실제 잃는 데이터는 없다는 전제다. `db push` 전에 `supabase db query --linked "select count(*) from public.battles;"`로 0을 확인하면 전제가 유지된다.
- `record_speed_verdict`·`sweep_stale_submissions`·`speed_outcome`·`quality_outcome`·`quality_deadline_outcome` 드롭 — 되살리려면 역방향 마이그레이션을 새로 써야 한다.
- cron 변경은 `cron.schedule` 재호출로 되돌릴 수 있다(파괴적이지 않다).

## 3단계 — AI 재판정 (착수 메모)

- 마이그레이션 `..._ai_rejudgment.sql`: `ai_judgment_jobs` + RLS(정책 없음), `ai_judgment_backoff`·`fail_ai_judgment`·`ensure_ai_judgment_job`·`claim_ai_judgment`·`record_min_criteria_verdict`·`record_superiority_verdict`·`record_ai_judgment_failure`·`dispatch_ai_judgments`, `submit_judgment`·`resolve_battle`에 잡 배선, `void_battle`·`forfeit_battle`·`delete_account` 재정의, `quality_judgments` 관련 전부 드롭, `ai-judge-tick` 명령 갱신.
- **`delete_account`는 반드시 가장 늦은 정의(`20260920120000_push_tokens_and_outbox.sql`)를 기반으로** 고친다. 여섯 번 재정의된 함수라 옛 정의를 베끼면 기준 증서·동의 기록·품질전 잡·알림 토큰 삭제가 조용히 사라진다. **인자 없는 시그니처 유지.**
- Edge: `judge-dispute/index.ts` 신규, `_shared/{dispute_judge.ts,prompts.ts,schemas.ts}`, `supabase/config.toml`의 `[functions.judge-quality]` → `[functions.judge-dispute] verify_jwt = false`.
- 오너: `functions deploy judge-dispute` → Vault `judge_function_url` 값 교체 → 실호출 확인 → `functions delete judge-quality`. **순서는 아래 "3단계 원격 적용 체크리스트"가 최종이다**(배포를 먼저 해야 교체 직후부터 받을 수 있다).
- 커밋: `feat: 불복·우열 불일치 AI 재판정`.


### 3단계 작업 순서 (확정, 2026-10-29 developer)

입력: `spec.md`, `design.md`의 "AI 재판정 재배선"·"새 서버 전용 함수"·"AI 호출별 입력/출력"·
전이표 T8~T11·`mutual_quality_outcome` 표·"주기 작업(cron) 구성"·"구현 단계 분할 3단계",
그리고 **원격에 적용된 `20260922120000_judging_window.sql`의 실제 함수 본문**(2단계가 남겨 둔
"3단계가 여기에 끼워 넣는다" 자리). 서버가 진실이고 화면은 이 단계에서 손대지 않는다.

1. **`supabase/migrations/20261029120000_ai_rejudgment.sql`** — 아래 "3단계에서 실제로 만든 것" 참고.
2. **`supabase/functions/_shared/schemas.ts`** — 속도전 판정 스키마를 최소 기준 공용으로 이름 변경,
   품질전 2단계 통합 스키마를 우열 전용으로 교체, 판정 요청을 `{job_id}`로.
3. **`supabase/functions/_shared/prompts.ts`** — `SPEED_JUDGE_*` → `MIN_CRITERIA_JUDGE_*`,
   `QUALITY_JUDGE_*` → `SUPERIORITY_JUDGE_*`(2단계 부분만).
4. **`supabase/functions/_shared/dispute_judge.ts` 신규** + **`judge-dispute/index.ts` 신규**,
   `_shared/quality_judge.ts`·`judge-quality/` 삭제, `supabase/config.toml` 블록 교체.
5. **`_shared/{prompts_test,schemas_test}.ts`** 갱신(우열 응답 검증·승자 누락=실패·A/B 역매핑·
   프롬프트에 최소 기준과 우열 기준이 섞이지 않음).
6. **`supabase/tests/ai_rejudgment_smoke.sql` 신규**.
7. `flutter analyze`(이슈 0) + `flutter test` + `deno test --allow-all supabase/functions/_shared/`.
   **커밋·원격 적용·배포는 하지 않는다.**

### 3단계 원격 적용 체크리스트 (오너 — 순서 그대로, 2026-10-29 작성)

> **전부 적용 완료(2026-10-29).** 1~10번을 순서대로 돌렸다. 5번 실호출은 속도전 불복 → 최소 기준
> 재판정 → 종결 → 점수까지 확인했다(`verdict_source='ai'`, `ai_model='gemini-2.5-flash/p1'`).
> **우열(superiority) 재판정은 실호출로 확인하지 않았다 — 스모크 테스트만 통과했다.**
> 6번 `judge-quality` 삭제됨: 원격에 남은 함수는 `battle-criteria`·`submit-evidence`·`judge-dispute` 3개다.

모든 명령은 `C:\workspaces\todododo`에서 실행한다. **순서를 지키면 발송 공백이 없다.**
Vault URL이 옛 함수를 가리키는 동안 보낸 요청은 `judge-dispute`가 아닌 곳으로 가 404/401로
버려지는데, 그 요청은 `claim_ai_judgment`에 도달하지 못하므로 **시도(`attempts`)도 임대도 생기지
않는다** — 잡은 그대로 남고 다음 분 tick에서 다시 보낸다. 즉 틀린 순서의 증상은 `voided`가 아니라
"재판정이 몇 분 늦어진다"뿐이다. 그래도 배포를 먼저 하면 그 공백 자체가 없어진다.

1. `supabase db push --dry-run` — 새 파일 **1개**(`20261029120000_ai_rejudgment.sql`)만 나오는지 확인.
   다른 파일이 같이 나오면 멈추고 원인부터 본다.
2. `supabase db push`
   - 이 시점부터 `quality_judgments`·`dispatch_quality_judgments`가 사라지고 cron `ai-judge-tick`이
     `dispatch_ai_judgments()`를 부른다. 배포된 `judge-quality`는 드롭된 `claim_quality_judgment`를
     부르므로 더는 동작하지 않는다 — 아무도 부르지 않으므로 무해하다.
3. `supabase functions deploy judge-dispute` — 새 함수를 먼저 올린다(Vault 교체 전에 올려 두면
   교체 직후부터 바로 받을 수 있다).
4. **Supabase 대시보드 Vault에서 `judge_function_url` 값을 교체** —
   `https://<project-ref>.supabase.co/functions/v1/judge-dispute`. `judge_cron_secret`은 그대로.
   값은 코드·로그·커밋·보고에 적지 않는다.
5. **실호출 확인** — 두 계정으로 속도전 하나를 양쪽 제출 → 한쪽이 "통과하지 못했어요"로 불복 →
   1분 안에 `ai_judgment_jobs` 행이 사라지고 대결이 종결되는지 본다.
   - 확인 쿼리: `supabase db query --linked "select id, kind, attempts, last_error from public.ai_judgment_jobs;"`
     (1분 뒤 0행이어야 한다. `attempts`가 올라가고 `last_error`가 쌓이면 4·3번을 다시 본다.)
   - Edge 로그: 대시보드 Functions → judge-dispute → Logs.
6. `supabase functions delete judge-quality` — 실호출이 확인된 뒤에만. 이 함수를 지우면 되돌리려면
   다시 배포해야 한다(소스는 이 커밋에서 삭제됐으므로 git 이력에서 꺼내야 한다).
7. `supabase migration list --linked` — 로컬 27개 = 원격 27개, 마지막이 `20261029120000`.
8. cron 확인: `supabase db query --linked "select jobname, schedule, command from cron.job order by jobname;"`
   - `ai-judge-tick` 명령이 `select public.sweep_stale_criteria_calls(); select public.dispatch_ai_judgments();`
   - `close-judging-windows`·`settle-expired-battles`는 `* * * * *` 그대로.
9. SQL 테스트 — 순서 그대로, 앞이 깨지면 뒤를 돌리지 않는다. 쓰기가 있는 스모크는 마지막에
   롤백하므로 원격 데이터는 그대로다.
   1. `supabase db query --linked -f supabase/tests/ai_rejudgment_smoke.sql` → `SMOKE RESULT ok=t`
   2. `supabase db query --linked -f supabase/tests/mutual_judge_rules.sql` → 39케이스 전부 `ok=t`
   3. `supabase db query --linked -f supabase/tests/mutual_judge_flow_smoke.sql` → `ok=t`
      - **주의**: 이 파일의 13·14번(`quality_mismatch`·`reject_pending`)은 "3단계 전까지 `judging`에
        머문다"를 기대값으로 적어 두었고, 3단계 적용 뒤에도 **기대값이 그대로 맞다** — 잡이 생기기만
        하고 AI 응답은 트랜잭션 안에서 오지 않으므로 상태는 여전히 `judging`이다. 고칠 것이 없다.
   4. 회귀(순서 무관): `ai_judge_flow_smoke.sql` / `resolve_battle_smoke.sql` /
      `settle_expired_battles_smoke.sql` / `forfeit_battle_smoke.sql` / `delete_account_smoke.sql` /
      `criteria_smoke.sql` / `join_battle_smoke.sql` / `ai_consent_smoke.sql` / `push_token_smoke.sql` /
      `custom_duration_smoke.sql` / `recruit_browse_smoke.sql` → 각 `ok=t`
   - `battle_outcome_rules.sql`은 2단계에서 삭제됐다. 돌리지 말 것.
10. Gemini 키·모델·cron 시크릿은 **새로 넣을 것이 없다**(기존 값 그대로 쓴다).

#### 이번 단계에서 하지 않는 것
- Storage 정리 불필요(사진을 지우지 않는다).
- 화면 변경 없음 — 불복 뒤 "AI가 다시 보고 있어요"는 4단계에서 이미 만들었고, 이 단계가 그 상태를
  실제로 끝내게 한다. 종결 후 판정 내역·`verdict_source` 공개는 5단계 몫이다.
- `submit-evidence` 재배포 불필요(2단계에서 이미 Gemini 호출이 빠진 버전이 배포돼 있고 이번 단계는
  그 파일을 고치지 않았다 — 아래 "설계와 달라진 점" 2 참고).

#### 되돌리기 어려운 지점
- `quality_judgments` 테이블과 `claim_quality_judgment`·`record_quality_verdict`·
  `record_quality_failure`·`dispatch_quality_judgments`·`quality_judgment_backoff`·
  `fail_quality_judgment` 드롭. 2단계 적용 뒤로는 아무도 새 잡을 만들지 않아 테이블이 비어 있다는
  전제다. `db push` 전에 `supabase db query --linked "select count(*) from public.quality_judgments;"`로
  0을 확인하면 전제가 유지된다.
- `supabase functions delete judge-quality`(6번) — 소스가 이 커밋에서 지워지므로 되살리려면 git
  이력에서 꺼내야 한다.
- Vault `judge_function_url` 값 교체는 되돌릴 수 있다(값을 다시 바꾸면 된다).

## 4단계 — 판정 화면과 교체 화면 (착수 메모)

- `presentation/{judgment_section.dart,evidence_section.dart,battle_detail_screen.dart}`, `domain/{judgment_rules.dart,battle_detail.dart}`, `data/battle_repository.dart`, `strings.dart` + 위젯·유닛 테스트.
- 커밋: `feat: 상호 판정 화면` / `feat: 제출 교체 화면`(화면 하나 = 커밋 하나).
- **순서 변경: 4단계를 3단계보다 먼저 한다(오너 결정, 2026-10-28).** 2단계 원격 적용 뒤 실기기로 확인하다 "판정 창은 열리는데 판정할 화면이 없다"는 문제가 드러났다. 오너가 요구한 흐름은 그대로다 — 서로의 사진을 보여 주고, 서로 판정해 승패가 나면 끝, 이의제기하면 AI 판정.
  - 바꿔도 되는 이유: 화면이 부르는 `submit_judgment(대결, 승인/불복, 우열)` 시그니처를 3단계가 바꾸지 않는다. 3단계는 불복이 들어온 **뒤**의 서버 내부 배선이라 화면을 다시 뜯을 일이 거의 없다. 승인 경로는 지금 서버로 완전히 동작한다(양쪽 승인 → 즉시 종결).
  - 감수하는 것: **불복을 누르면 그 대결은 3단계가 올 때까지 `judging`에 멈춘다.** 실사용자가 없고 오너가 테스트하는 중이라 감수한다. 화면에는 "AI가 다시 보는 중" 류로 진행 중임을 보여 주고, 3단계가 그 상태를 실제로 끝내게 한다.

### 4단계 작업 순서 (확정, 2026-10-28 developer)

`spec.md` 수용 기준 "판정 창과 절차"·"속도전"·"품질전", `design.md` 화면 4·5와 API 계약(`submit_judgment`),
그리고 **원격에 적용된 `supabase/migrations/20260922120000_judging_window.sql`의 실제 함수 본문**을 입력으로 삼았다.
서버가 진실이고 화면은 그 값을 표시만 한다.

1. **`lib/features/battle/domain/judgment_rules.dart` (신규)** — 순수 함수만.
   - `JudgmentStage` enum(`notOpen`·`nothingToJudge`·`myTurn`·`windowClosed`·`waitingOpponent`·`waitingAi`)과
     `judgmentStageOf(...)`. 서버 값(`status`, `has_submitted`, `has_judged`, `judge_deadline_at`)만 본다.
   - `judgmentErrorCodeOf`/`judgmentErrorMessage`/`isJudgeWindowClosedError` — `PostgrestException.hint` 기준
     (`criteria_rules.dart`·`submission_rules.dart`와 같은 모양).
2. **`domain/battle_detail.dart`** — `judgmentStageAt(now)`/`judgmentStage`/`isMyJudgmentTurn`/`isPastJudgeDeadline(now)`
   getter 추가. 위 순수 함수를 부르는 얇은 층이다.
3. **`data/battle_repository.dart`** — `submitJudgment({battleId, passed, superiorId})` → RPC `submit_judgment`.
   승인/불복 어휘(`approve`/`reject`)는 이 계층에서만 쓴다. `implements BattleRepository`로 만든 테스트 가짜들을 함께 고친다.
4. **`lib/core/strings.dart`** — 판정 질문·버튼·단계 안내·오류 코드 문구와 헤더의 시간 두 줄 라벨 추가,
   2단계의 자리 문구(`battleJudgingPlaceholder*`) 제거.
5. **`presentation/judgment_section.dart` (신규)** — 단계별 블록 + 판정 입력 폼. (커밋 후보: `feat: 상호 판정 화면`)
6. **`presentation/battle_detail_screen.dart`** — `judging` 분기에서 판정 섹션을 쓰고, 헤더에 "사진 마감"·"판정 마감" 두 줄.
7. **`presentation/evidence_section.dart`** — 제출 후 내 사진 표시, 마감 지난 뒤 교체 버튼 감춤, 판정 자리 문구 제거.
   (커밋 후보: `feat: 제출 교체 화면`)
8. **테스트** — `test/features/battle/domain/judgment_rules_test.dart`(단계 표 전 행),
   `test/features/battle/domain/battle_detail_test.dart`(추가 getter), `test/features/battle/battle_judgment_test.dart`(위젯),
   기존 `battle_evidence_test.dart` 보강.
9. `flutter analyze`(이슈 0) + `flutter test`(전부 통과). **커밋·원격 적용·배포는 하지 않는다.**

#### 단계 판정 표 (순수 함수 `judgmentStageOf`, 위에서부터 먼저 맞는 줄)

| # | 조건 | 단계 | 화면 |
|---|---|---|---|
| 1 | `status <> 'judging'` | `notOpen` | 판정 영역을 그리지 않는다 |
| 2 | 상대가 제출하지 않음 | `nothingToJudge` | "판정할 것이 없어요"(속도전 한쪽 제출의 제출자) |
| 3 | 내가 아직 판정 안 함 + 기한 남음 | `myTurn` | 판정 폼 |
| 4 | 내가 아직 판정 안 함 + 기한 지남 | `windowClosed` | "기한이 지나 자동 처리 중" |
| 5 | 내가 판정했고, 내가 제출했는데 상대가 아직 판정 안 함 | `waitingOpponent` | "상대 판정을 기다리는 중" |
| 6 | 그 밖(양쪽 판정이 끝났는데 아직 `judging`) | `waitingAi` | "AI가 다시 보고 있어요" |

6번이 추측이 아닌 이유: `submit_judgment`가 마지막 판정과 **같은 트랜잭션**에서 `resolve_battle`을 부르므로,
양쪽 판정이 끝났는데 `judging`이 남아 있다면 결론이 `pending`(= 불복 건의 AI 대기)인 경우뿐이다.
**3단계가 오기 전에는 이 상태가 실제로 끝나지 않는다**(오너가 감수한 사항, 위 절 참고).

#### design과 달라지는 점 (이유 포함)

1. **속도전도 "고른 뒤 보내기"로 받는다.** design 화면 5는 속도전을 `[통과했어요]`/`[통과하지 못했어요]` 두 버튼으로
   적었지만, 같은 절에서 "보내기 전 확인 다이얼로그"도 요구한다. 버튼이 곧 전송이면 "고르기"와 "보내기"가 섞이고
   사진을 못 불러왔을 때의 비활성 처리도 두 군데로 갈린다. 두 유형 모두 `SegmentedButton`(선택) + `판정 보내기`(전송)로
   통일한다. 질문·선택지 문구는 design 그대로다.
2. **"사진 로드 실패 시 판정 비활성"은 서명 URL 발급 실패·로딩 중으로 좁힌다.** 사진 디코딩 실패는 `EvidencePhotoFrame`이
   틀 안에서 "다시 시도"로 처리하고 버튼을 막지 않는다 — 디코딩 실패를 바깥으로 알리려면 공용 위젯에 콜백을 더해야 하고,
   그것은 retro-theme의 공용 위젯 계약을 이 단계에서 넓히는 일이다. 실제로 막히는 경로(RLS·네트워크)는 URL 발급에서 걸린다.
3. **`judging`에서 내 판정 차례일 때는 양쪽 증거 블록을 함께 그리지 않는다.** 판정 섹션이 상대 사진을 크게 보여 주므로
   같은 사진이 두 번 나온다. 판정을 보낸 뒤(또는 판정할 것이 없을 때)에만 양쪽 증거 블록을 보여 준다.
4. **`active`에서 "상대가 제출해서 사진이 잠겼어요" 안내는 만들지 않는다.** 서버 불변식상 양쪽이 모두 제출하면 그 트랜잭션에서
   `judging`으로 넘어가므로 `active`에 그 상태가 존재하지 않는다. 경합으로 교체가 밀린 경우는 이미 `SUBMISSION_LOCKED`
   스낵바가 같은 문구로 알린다.
5. **교체 버튼을 마감 지난 뒤에는 감춘다.** 2단계의 `isReplacingEvidence`는 마감을 보지 않아 정산 전(최대 1분) 교체 버튼이
   남아 있었다. 서버가 `DEADLINE_PASSED`로 거부하므로 버튼을 보여 줄 이유가 없다.

## 5단계 — 결과·공개·문서 (착수 메모)

- `battle_detail_screen.dart`(종결 후 양쪽 증거·판정 내역·`verdict_source`), `battle_summary.dart`(상태 줄 표), `strings.dart`(미사용 문자열 삭제), `CLAUDE.md`(조항 대조표의 **대체·부분 대체 행만**), `docs/specs/push-notification/{spec,design}.md` 인계 메모, `DEPLOY.md`·`TODO_BACKLOG.md`.
- `AiConsentRepository.currentVersion`을 `'2026-09-18'`로 올린다(재동의는 받지 않는다 — design 결정 사항 4).
- 커밋: `feat: 종결 후 판정 내역 공개` / `docs: 상호 판정 기준으로 도메인 규칙 갱신`.
- 오너 몫: 개인정보처리방침(`C:\workspaces\todododo-legal`과 게시본), Play Console 데이터 보안.

---

## 진행 기록

### 3단계 (로컬 구현 완료, 2026-10-29)
- developer 에이전트가 구현했다. **커밋·원격 적용·배포 없음** — 작업 트리에 변경만 있다.
  원격 DB·Storage·시크릿·Vault·Gemini는 읽지도 건드리지도 않았다.
- **새 파일**: `supabase/migrations/20261029120000_ai_rejudgment.sql`(937줄),
  `supabase/functions/judge-dispute/index.ts`, `supabase/functions/_shared/dispute_judge.ts`,
  `supabase/tests/ai_rejudgment_smoke.sql`(514줄, 비교 항목 49개 — 리뷰 보강 전 45개).
- **고친 파일**: `supabase/functions/_shared/schemas.ts`(최소 기준 스키마로 이름 변경, 우열 스키마 신규,
  `parseJudgeDisputeRequest`), `_shared/prompts.ts`(`MIN_CRITERIA_JUDGE_*`·`SUPERIORITY_JUDGE_*`),
  `_shared/{prompts_test,schemas_test}.ts`, `_shared/secret.ts`·`secret_test.ts`(주석의 함수 이름),
  `supabase/config.toml`.
- **지운 파일**: `supabase/functions/_shared/quality_judge.ts`, `supabase/functions/judge-quality/index.ts`.
- **마이그레이션이 하는 일**: `battles.verdict_model` 컬럼 추가 / `ai_judgment_jobs`(+RLS, 정책 없음, 부분 유니크 2개) /
  `ai_judgment_backoff`·`fail_ai_judgment`·`ensure_ai_judgment_job`(내부) /
  `claim_ai_judgment`·`record_min_criteria_verdict`·`record_superiority_verdict`·
  `record_ai_judgment_failure`(service_role) / `dispatch_ai_judgments`(cron) /
  `resolve_battle`에 잡 배선 / `void_battle`·`forfeit_battle`·`delete_account`의 잡 삭제 줄 교체 /
  cron `ai-judge-tick` 명령 교체 **→ 그 뒤에** `quality_judgments` 일체 드롭
  (순서가 이것이어야 드롭된 함수를 가리키는 tick이 한 번도 못 돈다).
- 위 "3단계 작업 순서"에 적은 1→7 순서를 **그대로** 따랐고 중간에 바꾸지 않았다.
- 검증: `flutter analyze` 이슈 0, `flutter test` **351개 통과**(이 단계는 Dart를 고치지 않아 숫자 변화 없음),
  `deno test --allow-all supabase/functions/_shared/` **25개 통과**(26 → 25: 품질전 통합 응답 검증
  테스트 3개가 우열 전용 3개로 바뀌고, `mapQualityVerdictToParticipants` 테스트가 승자 되돌리기
  하나로 합쳐졌다), `deno check`로 Edge Function 3개 타입 검사 통과.
- **SQL은 로컬에서 실행할 수 없다**(Docker 없음). 마이그레이션과 새 스모크는 원격에 처음 돌 때
  검증된다 — 2단계에서 네 파일을 고쳐야 했던 것과 같은 위험이 남아 있다(위 체크리스트 9번 순서대로).

#### 리뷰 반영 (2026-10-29, Critical 없음 / W1·W2·N1·N2)
- **W1** 우열 재판정의 모델 기록을 `battles.verdict_model`로 옮겼다(아래 "설계와 달라진 점" 4 참고).
  같은 마이그레이션 파일에 컬럼을 더했고(새 파일을 만들지 않았다), `record_superiority_verdict`에서
  `battle_submissions.ai_model` 갱신 문장을 **지웠다**. 스모크에 `superiority_model`과
  `superiority_subs_ai_model`(= 0, 제출 행은 그대로) 두 항목을 더했다.
- **W2** "늦게 도착한 응답" 검증이 `lease_token is null` 경로만 보고 있었다. 속도전 대결 하나
  (`v_stale_lease`)를 더해 **claim(T1) → 임대 만료 → 다른 실행이 claim(T2) → 옛 토큰 T1으로 기록**
  경로를 추가했고, `skipped`와 대상 제출의 `meets_criteria`가 **여전히 null**인 것을 함께 단정한다
  (`old_token_result`·`old_token_untouched`). 기존 6번(토큰이 null로 비워진 경로)은 그대로 남겼다.
- **N1** `cron.schedule` 교체를 `drop function dispatch_quality_judgments()` **앞으로** 옮겼다.
  "`db push`가 파일 하나를 단일 트랜잭션으로 적용한다"는 전제 없이도 안전해진다.
- **N2** 위 체크리스트 머리말의 고장 모델을 고쳤다. 틀린 순서의 증상은 `voided`가 아니라 "발송이
  버려지고 다음 분에 다시 시도"다(`attempts`를 올리는 유일한 지점이 `claim_ai_judgment`이고, 잘못된
  URL로 간 요청은 거기에 도달하지 못한다).
- 손대지 않은 것(판단 완료): N3(발송 루프 예외 흡수), N5(스모크 공백), N7(종결 전 최소 기준 사유
  가시성 — 2단계 가시성 결정의 귀결, 5단계 몫).

#### 설계와 달라진 점 (의도적)
1. **`submit_judgment`를 고치지 않았다.** design 흐름 3은 `submit_judgment`가 불복 시
   `ensure_ai_judgment_job`을 부른다고 적었지만, 같은 문서의 "잡 생성이 한 곳에만 있게 한다"와
   3단계 지시의 "`ensure_ai_judgment_job` 호출은 한 곳에만"을 지키려면 둘 중 하나여야 한다.
   `submit_judgment`는 이미 마지막에 같은 트랜잭션으로 `resolve_battle`을 부르므로 **`resolve_battle`
   한 곳**에 두었다. 결과는 같고(불복이 기록된 트랜잭션에서 잡이 생긴다), 자동 승인(cron)·AI 기록
   경로에서도 같은 조건으로 보정된다. 두 곳에 두면 "불복은 기록됐는데 잡이 없다"가 조용히 생긴다.
   - `resolve_battle`은 `min_verdict_effect`가 pending을 돌려준 이유를 **직접 다시 본다**
     (`상대 판정이 reject` + `meets_criteria is null`). 이 구분이 없으면 "상대가 아직 판정하지 않아
     pending"인 경우에도 AI를 불러 사람의 차례를 가로챈다.
2. **`submit-evidence/index.ts`를 고치지 않았다.** 3단계 지시에 적힌 "Gemini 호출·다운로드·
   `record_speed_verdict` 호출 제거, 교체된 사진 삭제 추가"는 **2단계가 이미 했다**(그 파일은
   `20260922120000` 적용 직후 재배포됐다). 지금 파일에는 Gemini 관련 코드가 없고 교체 사진 삭제가
   들어 있다 — 이 단계에서 다시 손댈 것이 없었다. 같은 이유로 `record_speed_verdict`·
   `sweep_stale_submissions` 드롭과 `sweep_stale_criteria_calls` 신설도 이 마이그레이션에 넣지 않았다
   (없는 함수를 드롭하면 `db push`가 통째로 실패한다). 마이그레이션 머리말에 이 사실을 적어 두었다.
3. **`record_superiority_verdict`는 `resolve_battle`을 다시 부르지 않고 바로 `finalize_battle`로 끝낸다.**
   design "새 서버 전용 함수" 표는 `... -> 잡 삭제 -> resolve_battle`이라고 적었지만, 우열 승자는
   사람의 판정 행(`battle_judgments.superior_id`)에 들어가지 않으므로 `resolve_battle`을 다시 부르면
   `mutual_quality_outcome`이 **또** `next='ai'`로 갈라져 잡이 다시 생긴다(무한 루프). AI 승자를
   사람의 답인 척 `superior_id`에 적는 쪽은 "사람도 AI도 사실만 말한다"는 설계 원칙 1을 깬다.
   그래서 이 함수만 종결을 직접 적용한다 — 점수·outcome 표는 그대로다(`win`/`loss`, 품질전 감면 없음).
4. **우열 재판정의 모델은 `battles.verdict_model`(신규 컬럼)에 적고, 제출 행의 `ai_model`은
   건드리지 않는다.** design은 우열 재판정이 `battles.verdict_reason`만 기록한다고 적었지만 함수
   시그니처에는 `p_model`이 있고, 프롬프트 인젝션 방어 원칙 7("`PROMPT_VERSION`을 기록에 남긴다")은
   모델 기록을 요구한다. 처음에는 제출 행의 `ai_model`이 비어 있을 때만 적었는데 **리뷰에서 두 경로가
   모두 어긋나는 것이 드러나 고쳤다**(W1):
   - 전형적 경로(양쪽 사람이 `approve` → 픽 불일치)에서는 두 제출 행이 모두 비어 있어,
     `verdict_source='opponent'`인 행에 `ai_model`만 채워진다. 한 행의 두 값이 서로 모순되고
     5단계의 판정 내역 공개가 "사람이 승인한 제출"을 AI 판정으로 보여 준다.
   - 양쪽 불복 뒤 우열로 간 경로에서는 두 행이 이미 차 있어 0행이 갱신된다 — AI 호출이 2회인
     경로에서 우열 모델이 **어디에도 남지 않는다.**
   그래서 같은 마이그레이션 파일에 `alter table public.battles add column verdict_model text`를 더하고
   `verdict_reason`과 같은 문장에서 함께 적는다(같은 판정의 사유와 모델이 한 행에 나란히 있다).
   스모크가 `verdict_model` 값과 **두 제출 행의 `ai_model`이 여전히 null인 것**을 함께 단정한다.
5. **종결 시 남은 잡을 `resolve_battle`에서도 지운다.** `claim`·`fail`이 종결 상태를 보고 버리므로
   결과에는 영향이 없지만, Vault 값이 비어 발송이 멈춘 동안에는 아무도 그 잡을 집지 않아 고아로
   남는다. 한 문장(`delete ... where battle_id = ...`)으로 그 경로를 없앴다.
6. **오너 작업 순서를 "배포 -> Vault 교체"로 적었다.** 위 착수 메모는 "Vault 교체 -> 배포"였지만,
   그 순서로는 교체와 배포 사이에 보낸 요청이 아직 없는 함수로 가서 버려진다(잡은 남고 다음 분에
   다시 보내므로 결과가 몇 분 늦어질 뿐이다 — `attempts`를 올리는 곳은 `claim_ai_judgment` 하나라
   실패로 쌓이지는 않는다. 리뷰 N2에서 바로잡은 고장 모델이다). 배포를 먼저 하면 그 공백이 아예
   없어진다(3단계 지시에 적힌 순서와 같다).

#### 함정 메모
- **`ai_judgment_jobs`의 부분 유니크 인덱스 두 개가 `on conflict do nothing`의 멱등성을 만든다.**
  `kind`별로 유니크 범위가 다르므로(최소 기준은 `(battle_id, target_id)`, 우열은 `(battle_id)`)
  충돌 대상을 지정하지 않는 `on conflict do nothing`을 써야 둘 다 걸린다.
- 같은 트랜잭션에서는 `now()`가 고정이라 백오프로 미뤄진 잡(`next_attempt_at = now() + 2분`)은
  **그 트랜잭션 안에서 다시 claim되지 않는다.** 스모크의 4회 소진 테스트는 매 시도 전에
  `next_attempt_at`을 과거로 돌려 놓는다(`.claude/agent-memory/developer/sql_smoke_test_now_frozen.md`).
- 스모크의 `dispatch_ai_judgments()` 호출 시점에 **기한이 된 잡이 없도록** 순서를 짰다. 원격 Vault에
  값이 들어 있으면 due 잡마다 `net.http_post`가 큐에 들어가는데, 롤백으로 큐 행도 사라지지만
  실호출 확인 중인 함수에 테스트 잡 id가 가는 일 자체를 만들지 않는 편이 낫다.

### 4단계 (로컬 구현 완료, 2026-10-28 — 3단계보다 먼저 했다)
- developer 에이전트가 구현했다. **커밋·원격 적용·배포 없음** — 작업 트리에 변경만 있다.
  원격 DB·Storage·시크릿·Edge Function은 읽지도 건드리지도 않았다(스키마 변경이 없는 단계다).
- **새 파일**: `lib/features/battle/domain/judgment_rules.dart`,
  `lib/features/battle/presentation/judgment_section.dart`,
  `test/features/battle/domain/judgment_rules_test.dart`, `test/features/battle/battle_judgment_test.dart`.
- **고친 파일**: `lib/core/strings.dart`(판정 문구·오류 코드 문구·시간 두 줄 라벨 추가, 2단계 자리 문구 제거),
  `domain/battle_detail.dart`, `data/battle_repository.dart`(`submitJudgment`),
  `presentation/{battle_detail_screen.dart,evidence_section.dart}`,
  테스트 7개(`BattleRepository` 가짜 6곳에 `submitJudgment` 추가 + 판정 자리 문구를 쓰던 단언 교체).
- 헤더가 "마감" 한 줄에서 "사진 마감"·"판정 마감" 두 줄로 바뀌면서 `AppStrings.battleDeadlineLabel`의 참조가
  0이 되어 함께 지웠다(5단계 "미사용 문자열 0건"을 미리 지킨 것이고, 범위를 넓힌 것은 아니다).
- 위 "4단계 작업 순서"에 적은 1→9 순서를 **그대로** 따랐고 중간에 바꾸지 않았다. design과 달라진 5건도 그 절에 있다.
- 검증: `flutter analyze` 이슈 0, `flutter test` **304개 통과**(기준선 273 + 판정 단계·오류 문구 유닛 12 +
  판정 화면 위젯 13 + 상세 모델 유닛 6).
- 함정 메모
  - **`DateTime.now()`를 쓰는 getter는 고정 픽스처로 검증할 수 없다.** `isReplacingEvidence`·`isMyJudgmentTurn`처럼
    시각을 인자로 받지 않는 getter는 과거 날짜 픽스처에서 늘 false가 된다. 유닛 테스트는 `...At(now)` 쪽을 부르고,
    getter 경로는 위젯 테스트(픽스처가 `DateTime.now()` 기준)가 덮는다. 2단계 테스트에 있던 `isReplacingEvidence`
    단언이 이 때문에 깨져 `isReplacingEvidenceAt(_now)`로 바꿨다.
  - **판정 선택지는 사진·기준 블록 아래라 기본 테스트 화면(800x600) 밖으로 밀린다.** 위젯 테스트에서
    `ensureVisible` 없이 탭하면 "would not hit test" 경고와 함께 실패한다(기존 제출 버튼 테스트와 같은 함정).
  - 위젯 테스트에서 `NetworkImage`는 400으로 실패한다(테스트용 HTTP 클라이언트). 그래서 판정 버튼 활성 판단을
    **서명 URL 발급 결과**에 걸었다 — 사진 디코딩까지 조건에 넣으면 테스트에서 활성 경로를 전혀 볼 수 없다.
- **보류 그대로**: AI 재판정 배선(3단계 — 불복을 누르면 대결이 `judging`에 머문다),
  종결 후 판정 내역·`verdict_source` 공개와 목록 상태 줄·문서 갱신(5단계).

### 2단계 (로컬 구현 완료, 2026-09-22 — 원격 적용은 아래 "2단계 원격 적용 결과")
- developer 에이전트가 재개해 로컬 구현을 끝냈다. **커밋·원격 적용·배포는 하지 않았다** — 작업 트리에 변경만 남아 있다. 메인 세션이 `flutter analyze`(이슈 0)·`flutter test`(273개 통과)·`deno test supabase/functions/_shared/`(26개 통과)를 다시 돌려 보고를 검증했다.
- **새 파일**: `supabase/migrations/20260922120000_judging_window.sql`, `supabase/tests/mutual_judge_rules.sql`, `supabase/tests/mutual_judge_flow_smoke.sql`.
- **고친 파일**: `supabase/functions/submit-evidence/index.ts`(Gemini 즉시 호출 제거, 교체 시 밀려난 사진 삭제), `supabase/functions/_shared/errors.ts`(`JUDGING_IN_PROGRESS`/`ATTEMPTS_EXHAUSTED` 제거), `supabase/tests/{ai_judge_flow_smoke,resolve_battle_smoke,settle_expired_battles_smoke,delete_account_smoke}.sql`, Dart data/domain/presentation 9개 파일(`battle*.dart`, `submission_rules.dart`, `submission_result.dart`, `evidence_section.dart`, `strings.dart`) + 테스트 5개.
- **지운 파일**: `supabase/tests/battle_outcome_rules.sql`(검증 대상 함수가 drop돼 `mutual_judge_rules.sql`로 대체).
- **design과 달라진 점(의도적 — 상세 이유는 developer 보고 원문, 2026-09-22 세션 로그 참고)**
  1. `resolve_battle`은 아직 `ensure_ai_judgment_job`을 호출하지 않는다(그 테이블은 3단계 산물). reject된 제출은 3단계 전까지 `judging`에 머문다 — 4단계 전까지 판정 화면이 없어 실사용자가 reject를 낼 길이 없으므로 안전.
  2. `submit_judgment` approve 경로가 `battle_submissions.meets_criteria`/`verdict_source`를 채운다(design 흐름 3엔 명시 안 됐지만 종결 후 공개용 정보가 필요해서). 판정 규칙 자체는 이 값을 안 쓴다.
  3. 품질전 `submit_judgment`는 min_verdict와 무관하게 항상 `superior_id`를 요구한다(화면이 "두 질문을 한 번에" 받는 설계이므로 왕복 방지).
  4. `judging_gate`는 "내 제출 존재 여부"만으로 교체/신규를 가른다 — 참가자당 제출 최대 1개 불변식을 이용해 "상대도 냈는데 나도 또 낸다" 경로를 코드에서 없앴다. 결과는 design 표와 동일.
- **원격 적용 전 오너가 반드시 할 것**
  1. **적용 순서**: `db push` → **즉시** `supabase functions deploy submit-evidence`(미루면 배포된 옛 함수가 drop된 `record_speed_verdict`를 불러 속도전 제출이 전부 실패) → `migration list --linked` 확인.
  2. SQL 테스트 순서: `mutual_judge_rules.sql`(39케이스, ok=t) → `mutual_judge_flow_smoke.sql` → `ai_judge_flow_smoke.sql` → `resolve_battle_smoke.sql` → `settle_expired_battles_smoke.sql` → 나머지(`forfeit_battle`/`delete_account`/`criteria`/`join_battle`/`ai_consent`/`push_token`/`custom_duration`). **`battle_outcome_rules.sql`은 삭제됐으니 실행하지 말 것.**
  3. cron 확인: `close-judging-windows` 신규 등록 여부, `ai-judge-tick` 명령이 `sweep_stale_criteria_calls(); dispatch_quality_judgments();`로 바뀌었는지.
  4. `create_battle`/`join_battle`/`list_open_recruits`는 이번 단계가 건드리지 않았다(1단계 상태 그대로).
  5. `quality_judgments` 테이블·`judge-quality` Edge Function은 아직 살아있다(3단계가 지운다) — 이제 아무도 새 잡을 안 만들어 비어 있을 뿐 무해.
  6. Storage 정리는 필요 없다(이 단계는 기존 사진을 지우지 않음, 정책만 교체).
  7. 되돌리기 어려운 지점: `battle_participants`/`battle_submissions` 컬럼 drop(데이터 없음 전제), `record_speed_verdict`/`sweep_stale_submissions`/`speed_outcome`류 drop.
  8. SQL 테스트 함정: 같은 트랜잭션 안에서는 `now()`가 고정된다(`pg_sleep`으로 시각차를 못 만든다) — `.claude/agent-memory/developer/sql_smoke_test_now_frozen.md` 참고, 3단계 테스트 작성 시에도 적용됨.
- **보류 그대로**: AI 재판정 배선(3단계), 판정 화면(4단계, 지금은 "판정 창이 열렸어요" 안내만), `push-notification` 2단계부터(알림 정의가 바뀌어 mutual-judge 종료 후 재개), CLAUDE.md 문구 갱신·동의 문구 갱신(5단계), Storage 고아 사진 8장·더미 계정 8개 정리.


### 2단계 원격 적용 결과 (2026-10-28, 메인 세션)
- 오너 지시로 메인 세션이 직접 적용했다. 대결 0건을 확인하고 `db push --dry-run`(1개) → `db push` → **즉시** `supabase functions deploy submit-evidence` → `migration list --linked`(25개 일치) 순으로 진행했다. cron 3개 전부 기대대로다(`close-judging-windows` 신규 `* * * * *`, `ai-judge-tick` 명령이 `sweep_stale_criteria_calls(); dispatch_quality_judgments();`, `settle-expired-battles` 그대로).
- **SQL 테스트 12개 전부 통과. 다만 4개 파일을 고쳐야 했다** — 로컬에 Docker가 없어 이 테스트들은 작성 뒤 한 번도 실행된 적이 없었고, 원격에 처음 돌려 보고서야 드러났다.
  - `mutual_judge_rules.sql`: `verdict_effect_cases`의 `ai_meets` 열이 첫 행들에서 타입 없는 `null`이라 text로 굳어 뒤의 boolean과 `UNION types text and boolean cannot be matched`. 첫 행을 `null::boolean`으로 고정했다. **교훈: 테이블 구동 테스트의 첫 행은 null 열에 타입을 박아 둔다.**
  - `mutual_judge_flow_smoke.sql`: 14번(불복 후 judging 유지)이 품질전인데 `submit_judgment(..., 'reject', null)`로 우열 답을 빼서 `SUPERIORITY_REQUIRED`. 같은 파일 15번이 바로 그 예외를 검증하고 있었다 — 테스트가 자기 모순이었다. 양쪽 판정에 `v_a`를 넘기게 고쳤다(불복 대기 중엔 우열 값이 결과에 쓰이지 않는다).
  - `forfeit_battle_smoke.sql`·`ai_consent_smoke.sql`: `status='judging'` 대결을 직접 insert하면서 `judging_opened_at`을 안 채워 신규 제약 `battles_judging_requires_window_check` 위반. 두 파일 모두 `judging_opened_at`·`judge_deadline_at`을 채우게 고쳤다. **2단계가 고친 스모크 목록(ai_judge_flow·resolve_battle·settle_expired_battles·delete_account)에 이 둘이 빠져 있었다 — judging을 직접 만드는 픽스처는 전부 찾아야 한다.**
- 마이그레이션 자체는 한 줄도 고치지 않았다. 고친 것은 테스트 4개뿐이다.
- 아직 안 한 것: 에뮬레이터·실기기 수동 확인, 폰 앱 빌드(이 머신에 릴리스 서명 키가 없다).

### 1단계 (구현 완료, 원격 적용·스모크 통과, 2026-09-18)
- **원격 적용 결과 (2026-09-18, 메인 세션)**
  - `db push`로 두 파일 적용, `migration list --linked` 로컬 24개 = 원격 24개. 적용 직후 `battle-criteria`를 재배포했다(배포된 옛 함수는 분 단위 값을 거부하므로 그 사이 대결 생성이 막히는 공백을 줄였다). 대결 0건, cron `settle-expired-battles`가 `* * * * *`로 바뀐 것을 확인했다.
  - 스모크 **11개 전부 통과**. `battle_outcome_rules.sql`은 24행 전부 `ok: true`다 — 체크리스트에 적힌 "23행"은 옛 숫자다.
  - **`criteria_smoke`가 처음에는 실패했다**(`consumed_checks expected=4 actual=6`). 마이그레이션 회귀가 아니라 이 스모크의 잠재 결함이었다: 소비된 증서를 **테이블 전체**에서 세는데, reset이 `battles`만 지우고 `criteria_checks`는 남기므로 어젯밤 실제 사용으로 소비된 2건이 함께 잡혔다. 이 스모크가 만든 사용자(`v_a`·`v_b`·`v_c`)로 범위를 좁혀 해결했다. **교훈: 스모크가 전역 개수를 세면 실데이터가 쌓일수록 깨진다. 자기가 만든 행으로 좁힐 것.**
  - **Storage 비우기는 실패했다.** `supabase storage rm -r ss:///battle_evidence/ --linked --experimental`이 `{"deleted":[]}`만 돌려주고 사진 **8장이 남았다**(ai-judge 1단계와 같은 증상 — CLI가 조용히 아무것도 하지 않는다). 대결 행이 사라졌으므로 참조 없는 고아 사진이고 동작에는 영향이 없다. 정리는 대시보드에서 해야 한다.

- **위에 적은 순서대로 진행했고 중간에 바꾸지 않았다.**
- 구현 단계에서는 원격 DB에 쓰기·DDL을 실행하지 않았고 배포·시크릿·Vault·Gemini·FCM도 건드리지 않았다. 적용과 스모크는 아래 "원격 적용 결과"에 있다.
- 로컬 검증: `flutter analyze` 이슈 0, `flutter test` **280개 통과**(기준선 273 + 기간 규칙·라벨 유닛 6 + 기간 입력 화면 위젯 1). `deno test supabase/functions/_shared/` **26개 통과**(개수 변화 없음 — 기존 "생성 요청은 제목·유형·기간을 검증한다" 안에서 경계값 케이스를 분 단위로 바꿔 늘렸고 테스트 함수를 새로 만들지 않았다). `deno check`로 Edge Function 3개 타입 검사도 통과.
- 마이그레이션 2개를 새로 썼고 적용된 파일은 한 줄도 고치지 않았다.
  - `20260921120000_mutual_judge_reset.sql` — `delete from public.battles;`
  - `20260921120100_custom_duration.sql` — `duration_minutes` 이전, `create_battle` 드롭·재생성, `join_battle`·`list_open_recruits` 재정의, cron 1분.
- **`create_battle` 드롭·재생성과 Dart 동시 변경**: 같은 단계에서 함께 바꿨다. 마이그레이션이 `drop function public.create_battle(uuid, integer)` 후 `p_duration_minutes`로 재생성하고, 재생성 뒤 `revoke ... from public, anon` + `grant ... to authenticated`를 다시 붙였다(드롭과 함께 권한이 사라진다). 같은 커밋 후보 2에 `battle_repository.dart`의 RPC 인자 이름(`p_duration_hours` → `p_duration_minutes`)을 넣어, PostgREST가 인자 이름으로 함수를 찾는 것 때문에 앱이 깨지는 구간을 만들지 않았다.
- 기존 스모크 9개를 새 컬럼·값으로 고쳤고(`battle_outcome_rules.sql`은 순수 함수 SELECT뿐이라 손대지 않았다), 신규 `custom_duration_smoke.sql`을 더했다.
- 설계와 달라진 점
  - **기간 라벨 문자열을 고정 상수 3개에서 포맷 함수 3개로 바꿨다.** design은 "문자열(`battleDuration1Day/3Days/7Days`)을 빠른 선택 칩 라벨로 재사용"이라고 했지만, 분 단위가 되면 라벨이 무한히 많아져 상수로 덮을 수 없다. `AppStrings.battleDurationDays/Hours/Minutes(int)` 세 함수로 바꾸고 `battleDurationLabel(minutes)`이 떨어지는 가장 큰 단위를 고르게 했다. 결과 문구는 그대로다(1440 → "1일"). 상수 3개는 참조가 0이 되어 지웠다(`lib`·`test` grep 확인).
  - **빠른 선택을 `ChoiceChip`이 아니라 `SegmentedButton`(`emptySelectionAllowed`) + "직접 입력" 토글 버튼으로 만들었다.** 이 저장소 테마에 `chipTheme`이 없어 `ChoiceChip`을 쓰면 픽셀 테두리를 벗어난 Material 3 라운드 칩이 섞인다. 기존 화면이 유형 선택에 이미 `SegmentedButton`을 쓰고 있어 같은 모양을 재사용했다. design "빠른 선택 칩"의 역할(자주 쓰는 값 한 번에 고르기)은 그대로다.
  - **기간 파싱·검증을 `domain/duration_rules.dart`로 분리했다.** design 파일 목록에는 없지만 dev-standards의 "presentation에 판단 로직을 직접 쓰지 않고 domain 순수 함수로 올려 유닛 테스트로 덮는다"를 따랐다. 화면은 `durationMinutesOf`/`validateDurationMinutes`만 부른다.
  - **생성 화면 기본값을 1440분이 아니라 4320분(3일)으로 뒀다.** design의 1440은 **DB 컬럼 기본값**(스모크 편의용)이고 화면 기본값은 정하지 않았다. 기존 화면의 기본값 72시간과 그 이유("하루는 촉박하고 일주일은 늘어진다")를 그대로 옮겼다.
  - **`create_battle`의 범위 검증에 `p_duration_minutes is null`을 더했다.** 옛 `not in (24,72,168)`은 null이면 NULL → false로 통과해 not null 컬럼 제약에서 깨졌다. 같은 함수에서 같은 문구로 막는 쪽이 오류가 읽힌다.
  - **스모크 픽스처의 기간 값을 환산했다**(24→1440, 72→4320, 168→10080). 컬럼명만 바꿔도 제약(1~10080)을 통과하지만 "24분"으로 읽혀 다음 사람이 오해한다.
- 함정 메모
  - `create_battle`은 **드롭 없이는 못 고친다**. 인자 타입이 같고 이름만 바뀌므로 `create or replace`가 `cannot change name of input parameter "p_duration_hours"`로 거부한다. 드롭하면 GRANT도 함께 사라지므로 재생성 뒤 권한 두 줄이 필수다.
  - `join_battle`·`list_open_recruits`는 시그니처가 그대로여서 `create or replace`로 고쳤고 GRANT를 다시 쓰지 않았다. 다시 쓰면 해로울 것은 없지만, 어느 것이 드롭됐고 어느 것이 아닌지가 파일에서 읽히지 않게 된다.
  - `BattleRepository`·`BattleCriteriaRepository`의 인자 이름을 바꾸면 `implements`로 만든 위젯 테스트 가짜가 한꺼번에 깨진다(이번에는 6개 파일). ai-judge 7단계와 같은 함정이다.
  - `supabase/functions/battle-criteria/index.ts`는 고칠 것이 없었다. `parseCriteriaRequest`가 만든 `request` 객체를 프롬프트 빌더에 그대로 넘기므로 필드 이름만 바뀌면 따라온다.
  - 직접 입력 필드에 `InputDecoration.errorText`를 쓰면 같은 오류 문구가 두 번 보인다(필드 아래 + 우리가 따로 둔 안내 줄). `error: SizedBox.shrink()`로 **테두리만** 오류 상태로 바꾸고 문구는 한 줄에서만 말한다. 위젯 테스트가 `findsOneWidget`으로 이 중복을 잡았다.
