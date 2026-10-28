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
| 1 | 있음 | 기존 대결 데이터 정리 + 커스텀 마감(분 단위) | `battle-criteria` | **구현 완료(미커밋·미적용)** |
| 2 | 있음 | 판정 창·제출 교체·상호 판정 기록·자동 승인·결론 규칙(즉시 AI 판정 제거) | `submit-evidence`(적용 직후) | 미착수 |
| 3 | 있음 | AI 재판정 재배선 | `judge-dispute` 신규 / `judge-quality` 삭제 | 미착수 |
| 4 | 없음 | 판정 화면·제출 교체 화면 | - | 미착수 |
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

## 3단계 — AI 재판정 (착수 메모)

- 마이그레이션 `..._ai_rejudgment.sql`: `ai_judgment_jobs` + RLS(정책 없음), `ai_judgment_backoff`·`fail_ai_judgment`·`ensure_ai_judgment_job`·`claim_ai_judgment`·`record_min_criteria_verdict`·`record_superiority_verdict`·`record_ai_judgment_failure`·`dispatch_ai_judgments`, `submit_judgment`·`resolve_battle`에 잡 배선, `void_battle`·`forfeit_battle`·`delete_account` 재정의, `quality_judgments` 관련 전부 드롭, `ai-judge-tick` 명령 갱신.
- **`delete_account`는 반드시 가장 늦은 정의(`20260920120000_push_tokens_and_outbox.sql`)를 기반으로** 고친다. 여섯 번 재정의된 함수라 옛 정의를 베끼면 기준 증서·동의 기록·품질전 잡·알림 토큰 삭제가 조용히 사라진다. **인자 없는 시그니처 유지.**
- Edge: `judge-dispute/index.ts` 신규, `_shared/{dispute_judge.ts,prompts.ts,schemas.ts}`, `supabase/config.toml`의 `[functions.judge-quality]` → `[functions.judge-dispute] verify_jwt = false`.
- 오너: Vault `judge_function_url` 값 교체 → `functions deploy judge-dispute` → 실호출 확인 → `functions delete judge-quality`.
- 커밋: `feat: 불복·우열 불일치 AI 재판정`.

## 4단계 — 판정 화면과 교체 화면 (착수 메모)

- `presentation/{judgment_section.dart,evidence_section.dart,battle_detail_screen.dart}`, `domain/{judgment_rules.dart,battle_detail.dart}`, `data/battle_repository.dart`, `strings.dart` + 위젯·유닛 테스트.
- 커밋: `feat: 상호 판정 화면` / `feat: 제출 교체 화면`(화면 하나 = 커밋 하나).

## 5단계 — 결과·공개·문서 (착수 메모)

- `battle_detail_screen.dart`(종결 후 양쪽 증거·판정 내역·`verdict_source`), `battle_summary.dart`(상태 줄 표), `strings.dart`(미사용 문자열 삭제), `CLAUDE.md`(조항 대조표의 **대체·부분 대체 행만**), `docs/specs/push-notification/{spec,design}.md` 인계 메모, `DEPLOY.md`·`TODO_BACKLOG.md`.
- `AiConsentRepository.currentVersion`을 `'2026-09-18'`로 올린다(재동의는 받지 않는다 — design 결정 사항 4).
- 커밋: `feat: 종결 후 판정 내역 공개` / `docs: 상호 판정 기준으로 도메인 규칙 갱신`.
- 오너 몫: 개인정보처리방침(`C:\workspaces\todododo-legal`과 게시본), Play Console 데이터 보안.

---

## 진행 기록

### 2단계 (로컬 구현 완료 — 오너 확인·원격 적용 대기, 2026-09-22)
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
