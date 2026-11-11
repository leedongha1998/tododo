# criteria-cache 구현 계획

- 기준 문서: `docs/specs/criteria-cache/spec.md`(2026-11-11 오너 승인), `docs/specs/criteria-cache/design.md`(2026-11-11 오너 승인).
  **설계 10장의 단계 분할을 확정판으로 옮긴 것이 아래 표다.** 설계와 달라진 것은 맨 아래
  "## 설계와 다른 점"에 쌓는다(선례: `docs/specs/todo-reorder/plan.md`).
- 설계의 "## 결정 필요" 5건에 대해 **메인 세션이 정한 것**(이 계획의 전제, 다시 판단하지 않는다):
  1. **요청 한도 풀 확인은 developer가 한다**(단계 2). 같은 풀이면 거기서 멈추고 보고한다 →
     결과는 아래 "## 요청 한도 풀 확인"에 적었다. **별도 풀이므로 그대로 진행했다.**
  2. **기간(`duration_minutes`)은 캐시 키에 넣지 않는다**(설계 권고 채택).
  3. **개인정보처리방침 손질은 오너 몫.** `C:\workspaces\todododo-legal`은 이 세션의 작업 폴더
     밖이라 건드리지 않는다. 방침 표에 넣을 문장 초안은 "## 오너가 할 일" 6번에 있다.
  4. **`title_norm`을 캐시에 남긴다**(설계 권고 채택).
  5. **마이그레이션은 원격에 적용하지 않는다.** 파일만 만든다. 임계값 결과표는 오너가 승인한다.
- 커밋은 **메인 세션이 단계별로 나눠 한다.** 이 작업에서는 작업 트리에만 변경을 남긴다
  (`git add`/`commit`/`push` 없음). **Edge Function 배포도 하지 않는다**(계정 소유자 실행).
- 범위 밖(적중률 관측 수단, 캐시 관리 화면, 추천 주제, 기준 품질 평가·신고, 임베딩 전용 상한)에
  쓸 코드·컬럼·플래그를 미리 만들지 않는다.
- **판정 경로를 건드리지 않는다.** 1차 상호 판정·2차 AI 재판정·상태 전이·점수·마감·정산·증거
  규칙의 코드와 테스트를 한 줄도 수정하지 않는 것이 "이 기능은 기준 생성 경로에만 닿는다"의 증거다.

---

## 단계 표

| # | 단계 | 변경 파일 | 끝 조건 | 테스트 |
|---|---|---|---|---|
| 1 | 마이그레이션 파일 + SQL 스모크 | `supabase/migrations/20261111120000_criteria_cache.sql`(신규: pgvector·`criteria_cache`·인덱스 1·RLS 0정책·RPC 4), `supabase/tests/criteria_cache_smoke.sql`(신규) | **파일만.** 원격 적용 없음, 코드 변경 없음 | 자동 테스트 없음(로컬 Docker 없음). 스모크는 오너가 원격에 적용한 뒤 `supabase db query --linked -f ...`로 돌린다 |
| 2 | 공용 모듈(순수 함수 + 임베딩 호출) | `supabase/functions/_shared/gemini.ts`(`embedText`·`embeddingModel`·`EMBEDDING_TASK_TYPE`·`EMBEDDING_DIM`), `_shared/criteria_cache.ts`(신규, 전부 순수), `_shared/criteria_cache_test.ts`(신규), `_shared/schemas.ts`(`skipCache`), `_shared/schemas_test.ts`(`skip_cache` 케이스) | `deno test supabase/functions/_shared/` 통과. **요청 한도 풀 확인 결과를 이 문서에 세 줄로 적는다** | `criteria_cache_test.ts`: 정규화 7케이스, 두 모델 키, L2 정규화, 벡터 리터럴, 코사인, `parseCacheHit` 거부 6케이스, `decideCriteriaSource`+`limitCostOf`, 임계값 범위 |
| 3 | Edge Function 흐름 | `supabase/functions/battle-criteria/index.ts`(동의 관문 → 조회 → 적중/미적중 → 적재) | 코드 리뷰 + `deno check`. `check` 경로의 동작이 한 줄도 바뀌지 않는다 | 순수 함수는 단계 2가 덮는다. 호출 순서는 주석·리뷰·수동 확인(설계 9.3) |
| 4 | 임계값 측정 도구 | `tool/criteria_cache_threshold.ts`(신규) | 스크립트가 운영과 같은 코드 경로(`embedText`·`normalizeTitle`·`l2Normalize`·`cosineSimilarity`)를 import해 표를 찍는다. **측정 자체는 `GEMINI_API_KEY`가 있어야 돌아간다** | 돌린 결과표를 아래 "## 임계값 결과표"에 넣는다(지금은 **못 돌렸다** — 사유와 돌리는 방법을 같은 절에 적었다) |
| 5 | 앱 | `lib/core/strings.dart`(문구 2개 교체·3개 추가), `lib/features/battle/data/battle_criteria_repository.dart`(`skipCache`), `lib/features/battle/domain/criteria_rules.dart`(사전 차단 완화 + 안내 함수), `lib/features/battle/presentation/create_battle_screen.dart`(`기준 다시 만들기`·차단 탈출구·사전 차단 해제), `test/features/battle/domain/criteria_rules_test.dart`, `test/features/battle/create_battle_test.dart` | `flutter analyze` 이슈 0 + `flutter test` 전부 통과 | 아래 "단계 5 테스트" 목록 |
| 6 | 차단 판단 캐시 켜기(P1) | `supabase/functions/_shared/criteria_cache.ts`(`CACHE_BLOCKED_DECISIONS = true`), `_shared/criteria_cache_test.ts`(차단 케이스) | `deno test` 통과. 상수 하나를 false로 돌리면 P0 상태로 되돌아간다 | 차단 행이 `includeBlocked`에 따라 통과/거부되는 것, 차단 적중의 한도 비용이 0인 것 |

**단계 5 테스트**(설계 9.2를 그대로 옮긴 것 + 가짜 레포지토리가 `skipCache`를 기록하게 한다)
- `criteria_rules_test`: `createBattleBlockMessage`가 **한도 소진으로는 차단하지 않는다**(동의만),
  `criteriaCallsExhaustedNotice`가 0회에서만 문구를 준다.
- `create_battle_test`: 통과 결과 화면에 `기준 다시 만들기(1회 차감)`가 있다 / 편집 모드에는 없다 /
  그 버튼이 `skip_cache = true`로 부른다 / 차단 화면에 `AI에게 다시 확인받기(1회 차감)`가 있고 그것도
  `skip_cache = true`다 / **다시 만들기가 실패하면 들고 있던 기준이 그대로 보이고 스낵바가 뜬다** /
  한도 0회에서도 `AI 기준 만들기`가 눌리고 안내 문구가 뜬다 / 첫 생성은 `skip_cache = false`다.

각 단계 끝에 해당 검증을 돌리고, **마지막에 `flutter analyze` + `flutter test` +
`deno test supabase/functions/_shared/` + `flutter build apk --release --dart-define-from-file=env.json`을
한 번 더 돌린다**(`EXIT=$?`를 따로 찍는다 — CLAUDE.md). 새 Dart 패키지가 없어 릴리스 위험은
낮지만 확인은 한다.

---

## 요청 한도 풀 확인 (설계 1.2 / "결정 필요" 1번)

2026-11-11에 직접 확인했다. **결론: 별도 풀로 읽힌다 → 설계 그대로 진행했다.**

1. `https://ai.google.dev/gemini-api/docs/rate-limits`는 이제 `https://aistudio.google.com/docs/rate-limits`로
   **301 리다이렉트**되고, 그 문서는 한도를 **RPM / TPM(입력) / RPD** 세 축으로 재고 "**Rate limits are
   applied per project, not per API key**", "**Limits vary depending on the specific model being used**"를
   명시한다. 즉 과금 주체는 프로젝트지만 **한도는 모델별**이다.
2. **무료 등급의 모델별 숫자는 이제 문서에 없다.** 그 자리에 "Rate limits … can be viewed in Google AI
   Studio" + `aistudio.google.com/rate-limit` 버튼만 있고(로그인 필요), 모델별 표가 남아 있는 곳은 Batch
   API 절인데 거기서도 `Gemini Embedding`이 `Gemini 2.5 Flash`와 **별개 행**으로 자기 할당량을 갖는다.
   그래서 **숫자는 이 문서에 적지 않는다**(적으면 틀린 숫자가 근거로 굳는다 — 설계 1.2의 태도 그대로).
3. 생성 모델과 임베딩 모델을 **하나로 묶는 집계 한도는 문서에 없다**(교차 모델 공유 풀로 적힌 것은
   Batch/Priority 같은 별도 경로뿐이고, Priority조차 "각 모델·등급 표준 한도의 0.3배"로 **모델별**이다).
   → 설계 "결정 필요" 1번의 **(a) 별도 풀이다**로 읽고 벡터 경로를 그대로 뒀다. **남는 불확실성 하나**:
   오너만 볼 수 있는 AI Studio의 `rate-limit` 페이지에서 `gemini-2.5-flash`와 `gemini-embedding-001`의
   RPM/RPD가 각각 따로 찍히는지 한 번 눈으로 보면 확인이 끝난다("## 오너가 할 일" 5번).

곁에서 확인된 것 둘(설계 1.1이 맞다는 증거):
- `gemini-embedding-001`은 지금도 제공되고 `taskType: SEMANTIC_SIMILARITY`와 `outputDimensionality`를
  받는다(후속 모델 `gemini-embedding-2`는 `task_type`을 **받지 않는다** — 그래서 고르지 않았다).
- 공식 문서가 "**`gemini-embedding-001`은 3072가 아닌 차원이면 직접 L2 정규화해야 한다**"고 못 박는다.
  설계가 정한 "받은 벡터를 L2 정규화해서 저장·비교한다"가 선택이 아니라 **요구사항**이었다.

---

## 임계값 결과표 (설계 8.3 / 오너 승인 대상)

**지금 못 돌렸다. 이유: 이 환경에 `GEMINI_API_KEY`가 없다**(`env.json`에는 Supabase URL·anon key만 있고
Gemini 키는 Edge Function 시크릿에만 있다 — 코드·커밋에 남기지 않는다는 규칙 때문에 당연한 상태다).
임베딩 호출 없이는 유사도 숫자를 만들 수 없으므로 표를 채우지 못했다. **막히지 않고 넘어갔고**, 대신
측정 도구를 완성해 두었다(단계 4).

**돌리는 방법**(키를 가진 오너가 1분이면 끝난다. DB·캐시를 건드리지 않고 임베딩 52회만 쓴다):

```bash
# Git Bash
export GEMINI_API_KEY=...        # 또는 setx로 넣어 둔 값이 이미 있으면 생략
deno run --allow-net --allow-env tool/criteria_cache_threshold.ts
```

출력이 아래 표 모양의 마크다운이다. 그것을 이 절에 붙이고 **요약의 숫자 하나만 본다 —
`그룹 B 오적중 0/15인가`.**

```markdown
측정: ____-__-__ / gemini-embedding-001 / SEMANTIC_SIMILARITY / 768차원 / L2 정규화
임계값 후보: 0.95(아래 "설계와 다른 점" 3번의 미측정 보수값)

| # | 그룹 | 제목 A | 제목 B | 유사도 | 임계값에서 묶이는가 | 기대 | 판정 |
|---|---|---|---|---|---|---|---|
| A1 | A | 방 청소하기 | 방 치우기 | _.___ | | 묶여도 됨 | |
| …  |   |            |          |       | |          | |

요약
- 그룹 B 최고 유사도: B_ = _.___   ← 임계값은 이 값보다 위여야 한다
- 그룹 A 최저 유사도: A_ = _.___
- 그룹 C 분포: _.___ ~ _.___
- 권장 임계값: _.__   (B 최고 + 0.02를 0.01 단위로 올림)
- 그 임계값에서 그룹 A 적중: _/6, 그룹 B 오적중: **0/15이어야 한다**
- 정규화 확인: 공백·대소문자만 다른 두 쌍이 유사도 1.000
```

**측정 뒤에 할 일은 둘뿐이다**: ① `CRITERIA_CACHE_MIN_SIMILARITY`를 권장 임계값으로 고친다(파일 하나,
`supabase/functions/_shared/criteria_cache.ts`. 그 값을 읽는 유닛 테스트가 범위만 보므로 테스트는
안 깨진다) ② **그룹 B 최고가 0.97 이상이면 구현을 멈추고 오너에게 보고한다**(설계 8.3 규칙 4 —
반대 뜻을 벡터로 가를 수 없다는 뜻이므로, 임계값 0.98+로 사실상 정규화 일치만 쓰거나 벡터 경로를
접는다. 접는 것은 `index.ts`에서 임베딩 인자를 빼는 일이라 싸다).

**지금 들어간 값은 0.95다**(설계의 후보 0.90보다 높다. 근거는 "## 설계와 다른 점" 3번).
**그래도 측정 전에 배포하지 말 것** — 0.95는 짧은 한국어 제목에서 **숫자만 다른 쌍**(`팔굽혀펴기 10개`
vs `100개`)이 넘어설 수 있는 구간이다. 먼저 배포해야 하면 임계값을 `1.01`로 두어 벡터 경로를 끈다
("## 오너가 할 일" 머리의 배포 관문 (가)).

---

## CLAUDE.md·dev-standards와의 접점 (충돌 없음을 확인한 기록)

구현을 멈춰야 하는 충돌은 **없다.** 확인한 자리를 남긴다.

| 접점 | 결론 |
|---|---|
| "판정 로직은 클라이언트가 아니라 DB/Edge Function" | 적중 판단·유사도 비교·버전 대조·한도 소모 여부가 전부 서버(RPC 4개 + Edge)에 있다. 클라이언트가 보내는 것은 `skip_cache` 하나이고 그건 "한도 1회를 쓰겠다"는 **손해 보는 요청**이라 우회 수단이 되지 않는다 |
| "테스트 없이 판정 로직 수정 금지" | 판정(1차 상호 판정·2차 AI 재판정) 코드를 한 줄도 수정하지 않는다. 새로 생긴 판단(정규화·버전 키·임계값·한도 비용)은 순수 함수로 떼어 `deno test`가 고정한다 |
| "스키마 변경은 마이그레이션 파일로만" | 파일 하나(단계 1). 대시보드 수정 없음. 기존 함수 7개(`begin/finish/fail_criteria_call`·`create_battle`·`update_battle_criteria`·`get_my_limits`·`delete_account`)를 한 줄도 고치지 않는다 |
| "RLS 정책은 테이블 만들 때 같이 작성한다" | `criteria_cache`는 RLS를 켜고 **정책 0개** + `revoke all from anon, authenticated`. "정답이 정책 없음"인 근거를 마이그레이션 주석에 적었다(사용자 롤이 캐시를 직접 읽는 길이 있으면 spec의 보안 성질이 깨진다) |
| "새 RPC는 `revoke execute ... from public, anon`" | 네 함수 모두 `revoke ... from public, anon, authenticated` + `grant ... to service_role` |
| "SECURITY DEFINER 첫 줄에 `auth.uid() is null` 가드" | **Edge 전용 함수 예외**를 적용한다(선례 `settle_expired_battles`·`begin_criteria_call`). service_role에는 `auth.uid()`가 없다. 대신 ① authenticated까지 EXECUTE 회수 ② 사용자 id는 Edge가 JWT로 확인해 인자로 넘김 ③ 예외의 이유를 함수 주석에 적음 |
| "참가자 검사에 `not in` 금지" | 대결을 읽지도 쓰지도 않아 해당 없음. 사용자 검사는 `where user_id = p_user_id` + `not found` |
| "새 테이블의 사용자 FK는 `public.profiles`" | **`criteria_cache`에는 사용자 FK가 없다**(설계 원칙 1 — 사용자 식별 정보가 한 칸도 없어 개인 데이터가 아니고 탈퇴와 무관하다). 증서는 기존 `criteria_checks.user_id`(이미 profiles 참조)를 그대로 쓴다 |
| "에러는 삼키지 않는다" | 사용자에게 보이는 실패(동의·한도·AI 실패)는 전부 지금 문구가 그대로 뜬다. **로그만 남기는 것은 캐시 조회·적재 실패 둘**이고 그 둘은 "미적중"과 **결과가 같다**(사용자의 기준 생성은 성공으로 끝난다) → `CLAUDE.md`의 로그-전용 예외 목록에 **새 항목을 더하지 않는다**. 보고할 실패가 아니라 아예 실패가 아니기 때문이다 |
| "사용자 문구는 한국어·`lib/core/strings.dart`" | 새 문구 3개·교체 2개 전부 거기에. **예외 하나**: 캐시 차단의 고정 사유 한 줄은 `issue_cached_criteria_check`(서버)에 있다 — `criteria_checks.block_reason`은 **이미 "서버가 쓴 문구"가 들어오는 슬롯**이고(AI가 쓴 한 줄이 그대로 화면에 간다) 앱이 고르는 문구가 아니다. 같은 슬롯에 출처를 둘로 만들지 않는다(설계 5.4) |
| "새 패키지 추가 전 기존 것으로 되는지" | **새 Dart 패키지 없음. 새 Deno 의존성 없음.** 임베딩은 `fetch` 한 번(`gemini.ts`의 기존 방식), 벡터 연산은 Postgres 확장(pgvector) |
| "새 화면 하나 = 새 커밋 하나" | **새 화면이 없다.** 단계 표가 커밋 단위이고 커밋은 메인 세션이 한다 |
| iOS·i18n·미래 대비 금지 | Android 전용, 새 로케일·`.arb` 없음, 범위 밖(관측·관리 화면·평가·추천)을 위한 컬럼·플래그를 만들지 않는다 |
| dev-standards "`data`가 `domain`·`AppStrings`를 import하지 않는다" | `battle_criteria_repository.dart`는 지금처럼 `criteria_check_result.dart`와 supabase만 본다(`skipCache`는 bool 인자 하나). 문구 판단은 `domain/criteria_rules.dart`에 그대로 있다 |
| dev-standards "RPC vs 직접 CRUD" | 캐시는 전부 service_role RPC다(직접 CRUD 경로를 열면 클라이언트가 캐시를 읽는 길이 생긴다) |
| dev-standards "테스트는 lib 구조 미러링" | `criteria_rules_test.dart`는 제자리에, 화면 테스트는 기존 `test/features/battle/create_battle_test.dart`에 보탠다(화면당 파일 하나 선례). Edge 순수 함수는 `_shared/criteria_cache_test.ts` |
| "같은 값을 두 곳에서 각자 판정하지 않는다"(이전 리뷰 지적) | 임계값·두 버전 키가 사는 자리는 **코드 상수 하나씩**이고, SQL은 그 값을 **인자로 받는다**(DB에 임계값 컬럼·기본값을 두지 않는다). `parseCacheHit`의 재검증은 같은 판정을 두 번 하는 것이 아니라 **SQL 응답을 믿지 않는 경계 검사**다(`schemas.ts`가 Gemini의 responseSchema를 믿지 않는 것과 같은 태도) |
| "한 컬럼을 두 경로가 채우면 숫자로 교차 검산"(이전 리뷰 지적) | `criteria_checks`를 이제 **두 함수가** 채운다(`finish_criteria_call`·`issue_cached_criteria_check`). 교차 검산식을 마이그레이션 주석과 스모크에 박았다: **`criteria_checks` 행 수 = `ai_criteria_calls`의 succeeded 수 + `ai_model like '%/cache'` 행 수**. 적중 증서에만 `/cache` 꼬리가 붙으므로 둘이 안 맞으면 어느 경로가 샜는지 숫자로 드러난다 |
| "읽고-고쳐-쓰는 비동기 경로는 직렬화"(이전 리뷰 지적) | 적중 경로는 읽고-고쳐-쓰기가 아니다(캐시는 읽기 전용, 증서는 insert 한 번). 한도 원장을 건드리는 경로는 지금처럼 `begin_criteria_call`의 `pg_advisory_xact_lock` 안에만 있다 |

---

## 설계와 다른 점

구현하면서 설계와 달라진 것만 적는다. **단계 순서는 바꾸지 않았다**(표의 1~6을 그 순서로 했다).

1. **SQL 스모크 테스트 파일을 하나 더 만들었다**(`supabase/tests/criteria_cache_smoke.sql`).
   설계 9.3이 "자동 테스트가 닿지 않는 경계"로 적은 것(벡터 검색, `created_at desc`의 "가장 최근 것",
   RLS·권한, **적중이 원장을 건드리지 않는지**)을 이 저장소의 선례(`supabase/tests/criteria_smoke.sql`
   등 16개)와 같은 방식으로 **SQL 한 파일**로 옮겼다. Gemini를 부르지 않고(벡터는 손으로 만든다)
   마지막에 예외로 롤백한다. 설계 단계 표에 없던 파일이지만 **같은 커밋(단계 1)에 들어가고**,
   돌리는 것은 원격 적용 뒤라 오너 몫이다("## 오너가 할 일" 2번).
2. **적중 증서의 교차 검산식을 주석·스모크에 박았다**(위 접점 표 마지막 줄). 설계에는 `/cache`
   꼬리를 "진단 자료"로만 적어 뒀는데, 한 컬럼을 두 경로가 채우는 상황이라 **검산식 형태로** 남겼다.
3. **임계값 상수를 0.90이 아니라 0.95로 두었다.** 설계는 "8장의 측정 뒤 확정"을 전제로 후보 0.90을
   적었는데, 이 환경에 `GEMINI_API_KEY`가 없어 **측정을 못 했다**(위 "## 임계값 결과표"). 측정하지
   않은 값은 spec의 태도("의심스러우면 AI를 부른다", "느슨하게 잡아 적중률을 올리는 방향으로 기울지
   않는다")에 따라 **높은 쪽으로 틀려야** 한다 — 임계값이 높아서 틀리면 손해가 AI 호출 1회이고,
   낮아서 틀리면 판정의 근거가 틀어진다. 측정 뒤 권장값(= 그룹 B 최고 + 0.02)으로 고치면 되고,
   그 값이 0.95보다 낮을 수도 있다. **상수 하나만 바꾸는 일이다.**
4. **차단 캐시 조회를 켠 상태로 둔다**(`CACHE_BLOCKED_DECISIONS = true`, 단계 6). 설계 단계 6이
   정확히 그 상수를 true로 바꾸는 단계이고, 메인 세션 지시가 "P1까지 포함"이다. **false로 되돌리면
   P0 상태**(통과 기준만 재사용)로 돌아가고 다른 코드는 그대로다.
5. **`skip_cache` 전달을 레포지토리 유닛 테스트가 아니라 화면 테스트의 가짜 레포지토리로 고정했다.**
   설계 9.2는 `battle_criteria_repository` 테스트를 적었지만, 이 저장소에는 `SupabaseClient`를 가짜로
   세우는 선례가 **하나도 없다**(레포지토리는 전부 화면 테스트의 `implements` 가짜로 덮는다 —
   dev-standards). 그래서 가짜가 받은 `skipCache` 값을 단정하는 쪽으로 옮겼다. 첫 생성이 false,
   `기준 다시 만들기`와 `AI에게 다시 확인받기`가 true인 것을 모두 본다.
6. **`battleCriteriaLeaveBody` 교체로 기존 테스트를 고칠 일이 없었다.** 설계 9.2 마지막 줄은 떠나기
   가드 테스트의 기대값을 고친다고 적었지만, 그 테스트들은 문구 **상수**를 참조하므로(리터럴이 아님)
   값만 바꾸면 그대로 통과한다. 고친 파일이 하나 줄었다.
7. **`수동 확인 절차`를 `docs/manual-test-plan.md`에 추가했다**(설계 11장 7번이 developer에게 맡긴
   일). **3-8 ~ 3-16**으로 대결 모집 절 끝에 붙였다 — 기준 생성은 모집 등록 흐름의 일부라 새 절을
   만들지 않았다. 설계 11장의 10개 항목에 "캐시가 비어 있을 때"(3-16)를 더해 9개로 묶었고,
   동의 철회 동작은 바뀌지 않아 기존 항목(8번 절)에 그대로 둔다.
8. **`lookup_criteria_cache`의 본문을 `jsonb_build_object`를 쿼리 안에서 만드는 모양으로 바꿨다.**
   설계 SQL은 `select c.*, (1 - (c.embedding <=> v_vec))::real into v_row, v_similarity`처럼
   **행 변수와 스칼라를 한 INTO 목록에 섞어** 받는데, plpgsql에서 그 조합은 버전·구성에 따라
   "assignment의 필드 수가 맞지 않는다"로 깨질 수 있다. 로컬 Docker가 없어 **SQL을 돌려 볼 수단이
   없으므로** 애매한 문법에 기대지 않고, 두 경로 모두 결과 jsonb를 쿼리가 직접 만들어 한 변수에
   받는다. **반환 모양·조건·정렬은 설계와 한 글자도 다르지 않다**(원 제목·원 사유를 담지 않는
   것까지 같다).
9. **(리뷰 반영 2026-11-11) `EMBED_TIMEOUT_MS` 10초 → **5초**, 로딩 보조 문구 `최대 30초` →
   **`최대 40초`**.** 설계 5.4는 "최대 30초는 '최대'라서 적중에서도 참"이라고 적었는데 **적중 쪽만
   본 검토였다** — 미적중에서는 임베딩 대기가 생성 타임아웃 **앞에 쌓인다.** 지금 최악은
   **35초**(임베딩 5 + 생성 30)이고 문구가 40초로 그것을 덮는다. 함께 넣은 것: **조회에서 임베딩이
   실패했으면 적재 단계에서 다시 부르지 않는다**(`embedFailed`). 설계 3.2의 5-4는 다시 불러 보라고
   적었지만, 같은 요청에서 두 번째도 실패할 가능성이 크고 그 5초가 사용자 대기에 그대로 쌓인다.
   못 넣은 대가는 "그 제목이 캐시에 안 들어감"뿐이고 다음 요청이 다시 넣는다.
10. **(리뷰 반영) `normalizeTitle` 끝에 60자 자르기를 넣었다.** 소문자화가 길이를 늘리는 문자가
   있어(`'İ'` 한 자 → 두 자) 60자 제목이 120자가 되고 `criteria_cache_title_check`를 위반해 **그 제목만
   적재가 깨진다.** 피해는 로그 한 줄이지만 막는 비용이 한 줄이다. 상한은 `schemas.ts`의 `TITLE_MAX`를
   그대로 쓴다(한 수를 두 곳에 적지 않는다). 테스트 1건 추가.
11. **(리뷰 반영) `p_min_similarity`와 반환 `similarity`를 `real` → `double precision`으로.** `<=>`가
   double precision을 돌려주는데 real로 받으면 0.95가 0.949999988…로 좁혀져 **SQL 문턱이 코드 상수보다
   약 1.2e-8 낮아진다.** 실질 영향은 없지만 "임계값이 사는 자리는 코드 상수 하나"가 숫자까지 같아지고,
   SQL의 적중 판단과 Edge의 재검증이 **같은 수를 같은 상수와** 비교한다. `revoke`/`grant`/`comment`의
   서명 세 줄도 함께 고쳤다.
12. **(리뷰 반영) 문서 세 줄을 사실에 맞게 좁혔다**: 마이그레이션 머리 주석·"오너가 할 일" 3번의 배포
   순서(위 1번), `spec.md`의 "가장 최근 것"(정규화 일치 경로에서만 정확하다 — 벡터 경로는 거리 우선),
   `design.md` 5.4의 로딩 문구 근거(위 9번).
13. **`issue_cached_criteria_check`의 `search_path`에 `extensions`를 더했다**(설계는 `public`만).
   그 함수가 `criteria_cache%rowtype`을 선언하는데 그 행에 벡터 칸이 있다. 타입은 OID로 풀리므로
   없어도 될 가능성이 높지만, 돌려 볼 수 없는 코드에서 깨질 여지를 남기지 않는 쪽을 골랐다.

---

## 진행 기록

- 2026-11-11: 단계 1~6을 표 순서대로 구현했다. **커밋·원격 적용(`db push`/`link`)·Edge 배포 없음.**
  - 요청 한도 풀 확인: **별도 풀**로 읽혀 멈추지 않고 진행(위 절).
  - 임계값 측정: **키가 없어 못 돌림.** 도구는 완성하고 `deno check`로 확인, 상수는 보수값 0.95.
  - P1(단계 6)은 **켠 상태**다(`CACHE_BLOCKED_DECISIONS = true`).
  - 검증: `flutter analyze` **이슈 0** / `flutter test` **732개 전부 통과**(앞서 727 → 새 테스트 5건:
    위젯 4 + 도메인 1, 한도 소진 테스트 1건은 기대값이 뒤집혀 교체) /
    `deno test supabase/functions/_shared/` **62개 통과**(앞서 49 → `criteria_cache_test.ts` 12건 +
    `schemas_test.ts` 1건) / `deno check`로 `battle-criteria/index.ts`·측정 도구 타입 확인 /
    `flutter build apk --release --dart-define-from-file=env.json` **종료 코드 0**(62.2MB).
  - 자동 테스트가 닿지 않은 것(설계 9.3 그대로): 벡터 검색·RLS·권한·원장 불간섭·Edge 호출 순서.
    앞의 넷은 `supabase/tests/criteria_cache_smoke.sql`이, 마지막은 수동 확인 3-15가 본다.
- 2026-11-11(리뷰 반영): **반드시 고칠 것은 없었고** 다섯을 넣었다 — 배포 순서 주석·문서 정정(설계와
  다른 점 12번), 임베딩 타임아웃 5초 + 로딩 문구 40초(9번), `normalizeTitle` 60자 자르기(10번),
  `p_min_similarity` double precision(11번), 배포 관문 두 줄("오너가 할 일" 머리). **하지 않은 것**(리뷰
  지시): 같은 `title_norm` 누적 정리, 캐시에 사용자 FK 추가, 임계값 값 변경. 코드의 fail-closed 관문도
  그대로 뒀다. 재검증: `flutter analyze` **이슈 0** / `flutter test` **732개 통과** /
  `deno test supabase/functions/_shared/` **62개 통과**(정규화 테스트 1건이 늘었지만 같은 Deno.test 안이다) /
  릴리스 APK 빌드 **종료 코드 0**. 커밋·원격 적용·배포 없음.

---

## 오너가 할 일

> ### 배포 관문 둘 (먼저 읽을 것)
>
> **(가) 임계값을 측정하기 전에는 Edge를 배포하지 말 것.** 지금 상수는 **측정하지 않은 0.95**이고,
> 그 값은 **짧은 한국어 제목에서 숫자만 다른 쌍**(`팔굽혀펴기 10개` vs `팔굽혀펴기 100개`)이
> 넘어설 수 있는 구간이다. 넘으면 spec이 가장 두려워한 실패(**다른 주제의 기준이 판정의 근거가
> 된다**)가 실제로 일어난다. 먼저 배포해야 한다면 `supabase/functions/_shared/criteria_cache.ts`의
> `CRITERIA_CACHE_MIN_SIMILARITY`를 **`1.01`로 두어 벡터 경로를 사실상 끄고**(정규화 일치만으로도
> 같은 제목 반복의 절감은 그대로 얻는다. 유사도는 최대 1이므로 어떤 행도 통과하지 못한다)
> 측정 뒤 권장값으로 되돌린다.
>
> **(나) 순서는 마이그레이션 → Edge 배포다. 반대로 하면 모든 사용자의 기준 만들기가 500으로
> 끝난다**(아래 3번).

1. **Supabase에서 `vector` 확장 사용 가능 확인.** 마이그레이션이 `create extension if not exists vector
   with schema extensions;`로 직접 켜지만, 플랜·프로젝트에서 막혀 있으면 거기서 멈춘다.
2. **마이그레이션 원격 적용**(로컬 Docker가 없다). `supabase db push` → 그 뒤
   `supabase db query --linked -f supabase/tests/criteria_cache_smoke.sql`로 스모크 한 번.
   되돌리기는 쉽다(`drop table public.criteria_cache` + 함수 4개 drop). 이 파일은 **기존 객체를 하나도
   고치지 않는다.**
3. **`supabase functions deploy battle-criteria`**(계정 소유자 실행). 순서는 **마이그레이션 → 배포**이고
   **지켜야 한다. 반대로 하면 모든 사용자의 `generate`가 500으로 끝난다** — 새 함수 넷 중
   `assert_criteria_consent`는 `try/catch` 밖의 **관문**이라, 함수가 없을 때의 오류에는 `hint`가 없어
   `codeFromHint`가 null이 되고 Edge가 `SERVER_ERROR`(500)로 응답한다(PostgREST 스키마 캐시가 늦게
   갱신되는 동안에도 같다). 관문이 fail-closed인 것은 **맞는 선택이다**(동의 확인이 조용히 통과되는
   쪽이 훨씬 비싸다) — 그래서 코드가 아니라 순서로 지킨다.
   "조회 실패는 미적중과 결과가 같다"(설계 원칙 6)는 **나머지 셋에만** 적용된다
   (`lookup_criteria_cache`·`put_criteria_cache`·`issue_cached_criteria_check`).
4. **임베딩 모델 시크릿은 설정하지 않아도 된다**(코드 기본값 `gemini-embedding-001`). 모델을 바꿀 때만
   `supabase secrets set GEMINI_EMBEDDING_MODEL=...` — 바꾸면 옛 벡터가 자동으로 조회 대상에서 빠진다.
5. **임계값 측정 + 결과표 승인**(위 "## 임계값 결과표"의 명령 한 줄). 같이 보면 좋은 것:
   AI Studio의 `rate-limit` 페이지에서 `gemini-2.5-flash`와 `gemini-embedding-001`의 RPM/RPD가
   **각각 따로** 찍히는지(위 "## 요청 한도 풀 확인" 3번의 남은 불확실성이 이걸로 끝난다).
6. **개인정보처리방침 한 줄 손질**(`C:\workspaces\todododo-legal\privacy.html`, **이 세션의 작업 폴더
   밖이라 손대지 않았다**). 아직 게시 전이라 지금이 가장 싸다(DEPLOY.md 5번). "탈퇴 시 처리" 표에
   넣을 문장 초안:

   | 항목 | 보관·이용 | 탈퇴 시 |
   |---|---|---|
   | AI가 만든 판정 기준과 그 주제의 제목 | 다음 대결의 판정 기준을 다시 만들지 않고 재사용하기 위해 **이용자 정보와 분리해** 보관합니다. 누가 만들었는지, 어느 대결에 쓰였는지는 함께 저장하지 않습니다 | 이용자를 식별할 수 있는 정보가 없어 **삭제 대상이 아니며 그대로 보존**됩니다 |

   같은 표의 기존 행("대결 기록 … 탈퇴자를 식별할 수 없는 상태로 보존")과 성질이 같지만, 캐시에는
   **대결이 된 적 없는 제목**(차단된 제목, 올리지 않은 제목)도 남아 그 행으로 다 덮이지 않는다.
7. **수동 확인**: `docs/manual-test-plan.md`의 **3-8 ~ 3-16**. 그중 **3-15(미동의 계정으로 기준 만들기 →
   Edge 로그에 임베딩 호출이 없다)**가 가장 중요하다 — 깨져도 사용자에게는 아무 증상이 없고, 깨진
   결과는 "동의하지 않은 사람의 제목이 Google에 갔다"는 되돌릴 수 없는 사실이다.
