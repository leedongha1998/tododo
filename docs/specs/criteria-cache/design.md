# criteria-cache 설계

## 참고

- spec.md: `docs/specs/criteria-cache/spec.md` (2026-11-11 오너 승인, **이 설계의 유일한 요구사항**). 특히 "## 도메인 경계", "## 범위 안"의 P0 7덩어리·P1 1덩어리, "## 수용 기준" 전체, "## 결정 기록"(1차 4건 + 2026-11-11 4건 + "오너가 알고 고른 것")이 기준이다.
- **spec의 "## 결정 기록"(2026-11-11)이 "## 범위 안"의 P1 조항을 뒤집었다.** 이 설계는 뒤집힌 쪽(= 결정 기록)을 따른다. 대조는 아래 "## spec 조항 대조"에 표로 적었다.
- 선례로 읽은 설계: `docs/specs/todo-reorder/design.md`(이 저장소의 설계 형식·SQL 전문 표기·폐기 목록·단계 분할의 기준), `docs/specs/ai-judge/design.md`(기준 생성 화면 A·B·C 단계와 사전 차단 안내의 출처).
- 근거로 읽은 현재 구현:
  - `supabase/migrations/20260916130000_ai_criteria.sql`(`criteria_checks`·`ai_criteria_calls`·`criteria_calls_used`·`begin/finish/fail_criteria_call`·`create_battle`·`update_battle_criteria`·`get_my_limits`·`delete_account`), `supabase/migrations/20261106120000_remove_battle_limits.sql`(**이 세 함수의 가장 늦은 정의**: `begin_criteria_call`·`create_battle`·`get_my_limits`·`delete_account`).
  - `supabase/functions/battle-criteria/index.ts`, `supabase/functions/_shared/{gemini.ts,prompts.ts,schemas.ts,auth.ts,errors.ts}`.
  - `lib/core/strings.dart`(306~366행), `lib/features/battle/data/{battle_criteria_repository.dart,criteria_check_result.dart}`, `lib/features/battle/domain/criteria_rules.dart`, `lib/features/battle/presentation/{create_battle_screen.dart,criteria_views.dart,edit_recruit_criteria_screen.dart}`.
  - `DEPLOY.md` 5번, `C:\workspaces\todododo-legal\{privacy.html,account-deletion.html}`(개인정보처리방침 — **아직 게시되지 않았다**).
- **코드를 읽고 확인한 사실 7건**(설계가 여기에 걸려 있다):
  1. **동의 확인이 `begin_criteria_call` 안에 있다.** 그 함수는 동의 확인과 **한도 예약(`in_progress` 행 insert)을 한 트랜잭션에서 같이** 한다. 즉 "동의만 확인하고 한도는 쓰지 않는" 호출 수단이 지금 **없다.** 이 한 줄이 이 설계의 핵심 문제다(3.1).
  2. **`criteria_checks`에는 사용자가 손으로 고친 기준이 들어 있다.** `action = 'check'` 행의 `min_criteria`는 **사용자가 쓴 문장**을 그대로 담는다(`index.ts` 103~104행: "재검사에서는 AI가 기준을 다시 쓰지 않는다"). 그래서 이 테이블을 캐시로 그대로 쓰면 **인젝션 문장 전파 차단**(spec이 보안 성질로 격상한 결정 4)이 즉시 깨진다 → 2.1.
  3. **`criteria_checks`는 탈퇴 때 지워진다**(`delete_account` 5단계). 캐시가 같은 테이블이면 오너 결정 3("탈퇴와 무관하게 남는다")을 만족할 수 없다 → 2.1.
  4. **`criteria_checks.ai_model`을 읽는 코드가 없다.** `finish_criteria_call`이 쓰기만 하고 어떤 함수·화면도 비교하지 않는다. 그래서 적중 증서에 `/cache` 꼬리를 붙여도 동작이 바뀌지 않는다(진단 자료만 늘어난다) → 2.5의 `issue_cached_criteria_check`.
  5. **`duration_minutes`가 생성 프롬프트의 입력이다**(`prompts.ts`의 `buildGenerateUserText`). spec의 캐시 키에는 기간이 없다 → 이 설계는 기간을 키에 넣지 않기로 하고 근거와 함께 "## 결정 필요" 2번에 올렸다.
  6. **화면이 한도 소진을 사전 차단한다.** `createBattleBlockMessage`가 `criteriaCallsLeft <= 0`이면 문구를 돌려주고 `canGenerate`가 false가 되어 **버튼이 비활성된다**(`create_battle_screen.dart` 328~330행). 이걸 그대로 두면 수용 기준 "한도를 다 쓴 사용자도 캐시 적중이면 기준을 받을 수 있다"가 **코드 한 줄 때문에 깨진다** → 5.6.
  7. **`battleCriteriaLeaveBody`는 두 화면이 공유한다.** `CriteriaLeaveGuard`가 본문을 상수로 고정하고 제목만 받는다(`criteria_views.dart` 249행, 대결 만들기·모집 기준 수정 두 화면) → 5.4.

---

## 설계 원칙 (전체를 관통하는 8가지)

1. **캐시는 사용자와 아무 관계가 없는 읽기 전용 지식 저장소다.** 행에 `user_id`도 `battle_id`도 `criteria_checks` 참조도 **없다.** 그래서 탈퇴·동의 철회·RLS와 엮이지 않고(오너 결정 3), 캐시에서 원 작성자·원 대결로 돌아가는 경로가 물리적으로 존재하지 않는다(수용 기준 "원 작성자·원 제목·원 대결 정보가 함께 오지 않는다").
2. **동의가 모든 Gemini 호출보다 먼저다. 임베딩도 Gemini 호출이다.** 그래서 임베딩 앞에 동의 관문을 따로 세운다(3.1). 이 순서가 깨지면 반려다(spec "동의와 개인정보 — 위반하면 반려").
3. **한도 원장(`ai_criteria_calls`)에 들어가는 것은 생성·재검사 호출뿐이다.** "1회가 소모되는가"는 **`begin_criteria_call`을 불렀는가와 1:1**이다. 적중 경로는 그 함수를 부르지 않으므로 셀 것이 없다. 원장에 `cached` 같은 새 상태를 만들지 않는다(그 순간 "10회"의 뜻이 흐려진다).
4. **캐시에서 왔든 AI에서 왔든 결과는 증서(`criteria_checks`) 1행이다.** `create_battle`·`update_battle_criteria`는 **한 줄도 바뀌지 않는다.** 증서를 거치지 않는 대결 생성 경로가 생기지 않는다(spec "보안 성질 유지").
5. **캐시에 들어가는 것은 AI가 쓴 문장뿐이다.** 적재 호출은 `generate` 성공 경로 **한 자리**에만 있고, `check`(사용자 수정분 재검사) 경로에는 적재 코드가 존재하지 않는다. 사용자가 쓴 문장이 캐시를 타고 다른 사용자에게 가는 길이 없다(spec 결정 4의 보안 성질).
6. **조회 실패와 적재 실패는 관문이 아니다.** 둘 다 "캐시가 없었다"와 **같은 결과**로 끝난다 — 조회가 실패하면 지금처럼 AI를 부르고, 적재가 실패하면 사용자의 기준 생성은 성공으로 끝난다(수용 기준 "기존 동작 보존" 2·3항). 로그만 남긴다.
7. **임계값은 코드의 상수 하나다.** DB 컬럼도, 시크릿도, 사용자 설정도 아니다. 판정의 근거가 되는 품질 손잡이라 **버전 관리되는 자리**에 두고 유닛 테스트가 그 값을 읽는다(8장).
8. **캐시가 내주는 것은 기준 문장과 통과/차단 여부뿐이다.** 조회 함수가 **원 제목(`title_norm`)과 원 차단 사유를 반환값에 담지 않는다.** 실수로 흘릴 코드가 존재할 수 없게 함수의 반환 모양으로 막는다(2.5).

---

## CLAUDE.md 규칙 대조

| 규칙 | 이 설계에서 |
|---|---|
| 대결 상태 전이·판정 로직은 DB/Edge에서, 화면은 표시만 | 이 기능은 **`battles`를 읽지도 쓰지도 않는다.** 상태 전이·승부·점수·마감·판정 기한·`settle_expired_battles()`·AI 재판정에 한 줄도 닿지 않는다. 닿는 것은 기준 **생성** 경로 하나다 |
| 판정 로직은 클라이언트가 아니라 DB/Edge | 적중 판단·유사도 비교·한도 소모 여부가 전부 서버(DB 함수 + Edge Function)에 있다. 클라이언트가 보내는 것은 `skip_cache` 불리언 하나이고 그건 "캐시를 건너뛰고 1회를 쓰겠다"는 **손해 보는 요청**이라 우회 수단이 되지 않는다(3.2) |
| 스키마 변경은 마이그레이션 파일로만 | 2.2의 파일 하나(확장 1 + 테이블 1 + 인덱스 1 + RPC 4). 대시보드 수정 없음 |
| RLS 정책은 테이블 만들 때 같이 작성한다 | `criteria_cache`는 **RLS를 켜고 정책을 0개 둔다**(= 어떤 사용자 롤도 한 행도 못 읽는다) + `revoke all ... from anon, authenticated`. "나중에 붙이지 않는다"를 지키되, 이 테이블의 정답이 "정책 없음"인 근거를 2.3에 적었다 |
| 새 RPC는 `revoke execute ... from public, anon`을 같이 쓴다 | 새 함수 4개 전부 `revoke execute ... from public, anon, authenticated` + `grant execute ... to service_role`(2.5) |
| SECURITY DEFINER 함수는 `auth.uid() is null` 가드 | **Edge Function 전용 함수의 예외**를 적용한다(선례: `settle_expired_battles`·`begin_criteria_call`). service_role에는 `auth.uid()`가 없어 그 가드가 항상 실패한다. 대신 ① authenticated까지 EXECUTE 회수 ② 사용자 id는 Edge가 JWT로 확인해 인자로 넘김 ③ **함수 주석에 이 예외의 이유를 적는다**(2.5) |
| 참가자 검사에 `not in` 금지 | 해당 없음(대결을 건드리지 않는다). 사용자 검사는 `where user_id = p_user_id` + `not found`다 |
| 사용자 FK는 `public.profiles`를 가리킬 것 | **`criteria_cache`에는 사용자 FK가 없다**(원칙 1). 새 증서는 기존 `criteria_checks.user_id`(이미 `profiles` 참조)를 그대로 쓴다 |
| 함수·변수는 영어, 사용자 문구는 한국어, `lib/core/strings.dart`에 모은다 | 5.4에 새 문구 3개와 고치는 문구 2개 전부. 예외 하나(서버가 쓰는 차단 사유 한 줄)의 근거도 5.4에 적었다 |
| 에러는 삼키지 않는다 | 사용자에게 보이는 실패(한도 초과·AI 실패)는 전부 지금처럼 문구가 뜬다. **로그만 남기는 것은 캐시 조회·적재 실패 둘뿐**이고(원칙 6) 그 둘은 사용자의 기준 생성을 막지 않는다 — `CLAUDE.md`의 로그-전용 예외 목록에 **새 항목을 추가하지 않는다**(사용자에게 보고할 실패가 아니라 아예 실패가 아니기 때문이다. 미적중과 결과가 같다) |
| 새 패키지 추가 전에 기존 것으로 가능한지 확인 | **Dart 새 패키지 없음.** Edge는 `fetch` 한 번(기존 `gemini.ts`와 같은 방식)이고 벡터 연산은 Postgres 확장(`pgvector`)이 한다 — Deno 의존성도 늘지 않는다 |
| 새 화면 하나 = 새 커밋 하나 | **새 화면이 없다.** 10장의 단계가 커밋 단위다(확정은 plan.md) |
| 테스트 없이 판정 로직 수정 금지 | 판정 로직을 수정하지 않는다. 캐시 판단·한도 비용·정규화·버전 대조는 순수 함수로 떼어 `deno test`로 고정한다(9장) |
| iOS·i18n·미래 대비 추상화 금지 | Android 전용. 적중률 통계·캐시 관리 화면·품질 평가·추천 주제를 가정한 컬럼·함수·플래그를 만들지 않는다(spec "범위 밖") |

---

## spec 조항 대조 — 오너 결정 1이 뒤집은 것

spec의 "## 범위 안 P1"과 "## 수용 기준 P1"은 **기획 권고(완전 일치 한정)** 기준으로 적혀 있고, 그 뒤의 "## 결정 기록(2026-11-11)" 1번이 그것을 뒤집었다. 이 설계가 따르는 쪽을 표로 못 박는다.

| spec 조항 | 기획 권고(범위 안 P1) | **오너 결정(2026-11-11 1번) = 이 설계** |
|---|---|---|
| 차단 판단의 재사용 범위 | 제목 완전 일치에서만 | **유사도로 전파한다.** 통과 기준과 같은 경로·같은 임계값을 쓴다(2.4) |
| 수용 기준 "차단 판단이 **제목 완전 일치**에서만 재사용된다" | 지킨다 | **폐기.** 이 줄은 뒤집힌 조항이다 |
| 수용 기준 "차단 사유 문구가 재사용되더라도 제목이 완전히 같은 경우에만 보인다" | 지킨다 | **더 강하게 바꾼다 — 캐시에서 온 차단은 원래 사유를 어떤 경우에도 보여 주지 않는다**(5.3). 완전 일치 경로에서도 보여 주지 않으므로 이 수용 기준은 "보이지 않는다"로 더 안전한 쪽으로 만족된다 |
| 수용 기준 "완전 일치 판단이 공백·대소문자를 정규화한 뒤에 이뤄진다" | 완전 일치 비교용 | **살아 있다.** 정규화는 ① 임베딩에 넣는 입력 ② 정규화 일치 빠른 경로(2.4)에 쓰인다. 유닛 테스트도 그대로 남는다(9장) |
| 수용 기준 "차단 적중 화면에 AI에게 다시 확인받는 길이 있고, 그것으로 차단을 뚫을 수 있다" | P1 | **P0로 올라간다**(결정 기록 1번이 명시). 5.3·10장 단계 5 |

그 밖의 spec 조항은 전부 그대로 유효하다.

---

## 0. 전체 그림

```
서버 (마이그레이션 파일 하나)
  ├ extension vector                      ← pgvector (extensions 스키마)
  ├ public.criteria_cache                 ← 사용자 정보가 없는 지식 저장소
  │   (type, title_norm, provable, min/superiority, block_reason,
  │    ai_model, embedding_model, embedding vector(768), created_at)
  │   RLS on + 정책 0개 + anon·authenticated 권한 회수
  ├ assert_criteria_consent(user)         ← **한도를 쓰지 않는 동의 관문** (이 설계의 핵심)
  ├ lookup_criteria_cache(...)            ← 정규화 일치 → 벡터 유사도. 원 제목·원 사유를 안 내준다
  ├ put_criteria_cache(...)               ← AI 원본만 적재
  └ issue_cached_criteria_check(...)      ← 적중 → 증서 1행(원장은 건드리지 않는다)

  바뀌지 않는 것: begin/finish/fail_criteria_call, create_battle,
                  update_battle_criteria, get_my_limits, delete_account,
                  criteria_checks·ai_criteria_calls의 스키마

Edge Function (battle-criteria/index.ts)
  generate:
    JWT → 입력 검증(+ skip_cache)
      → assert_criteria_consent           ← 임베딩보다 **먼저**. 한도는 아직 안 씀
      → (skip_cache가 아니면) 정규화 일치 조회       … 적중이면 임베딩조차 안 한다
      → (미적중) 임베딩 1회 → 벡터 조회
      → 적중  : issue_cached_criteria_check         … 한도 0회
      → 미적중: begin_criteria_call → Gemini 생성 → finish/fail
                → put_criteria_cache(적재, 실패는 로그만)   … 한도 1회
  check: **한 줄도 바뀌지 않는다**(캐시도, 임베딩도 없다. 한도 1회)

_shared (순수 함수 + Gemini 호출 한 자리)
  ├ gemini.ts    : embedText() 추가(모델명·키는 이 파일에만 둔다는 기존 규칙 유지)
  └ criteria_cache.ts (신규, 전부 순수)
      normalizeTitle / aiModelKey / embeddingModelKey / l2Normalize /
      toVectorLiteral / cosineSimilarity / parseCacheHit /
      decideCriteriaSource / limitCostOf / CRITERIA_CACHE_MIN_SIMILARITY

앱 (새 화면 없음, 새 패키지 없음)
  ├ repository.generate(..., skipCache: false)
  ├ create_battle_screen: `기준 다시 만들기(1회 차감)` + 차단 화면의 `AI에게 다시 확인받기(1회 차감)`
  ├ 한도 소진 사전 차단을 **푼다**(적중은 한도와 무관하므로)
  └ 문구 2개 교체 + 3개 추가
```

**새 화면이 없고, 새 cron이 없고, 새 Edge Function이 없다.** 서버 변경은 마이그레이션 파일 하나이고 원격 적용은 오너 승인 뒤다(11장).

---

## 1. 외부 사실 — 임베딩 모델과 요청 한도 (spec 백로그가 설계로 넘긴 숙제)

### 1.1 임베딩 모델 선택

| 항목 | 값 | 근거 |
|---|---|---|
| 모델 | **`gemini-embedding-001`** | 지금 쓰는 무료 등급 Gemini API(`generativelanguage.googleapis.com/v1beta`)의 현행 임베딩 모델이다. 구형 `text-embedding-004`(768차원 고정)는 차원 선택이 없고 후속 모델에 자리를 넘겼다 |
| 엔드포인트 | `POST /v1beta/models/{model}:embedContent` | `generateJson`이 쓰는 `:generateContent`와 같은 호스트·같은 키 헤더(`x-goog-api-key`) |
| `taskType` | **`SEMANTIC_SIMILARITY`** | 우리가 하는 일이 정확히 "두 문장이 같은 뜻인가"다. `RETRIEVAL_*`는 질의-문서 비대칭 공간이라 제목 대 제목 비교에 맞지 않는다. **taskType이 다르면 벡터 공간도 다르므로 캐시 키에 넣는다**(2.4) |
| `outputDimensionality` | **768** | ① pgvector의 ANN 인덱스(ivfflat·hnsw)가 **2000차원까지만** 다뤄 기본값 3072는 나중에 인덱스를 붙일 길이 막힌다 ② 768은 저장·비교 비용이 1/4이고 이 규모에서 품질 차이가 유사도 임계값 판단을 바꾸지 않는다 ③ 차원도 캐시 키에 넣는다 |
| 정규화 | **받은 벡터를 L2 정규화해서 저장·비교한다** | `gemini-embedding-001`은 **기본 차원(3072)이 아닌 출력은 정규화돼 오지 않는다**. 정규화하지 않은 벡터로 코사인을 계산하면 임계값이 길이에 흔들린다. 이미 정규화된 벡터를 다시 정규화해도 결과가 같으므로 **어느 쪽이든 안전한 쪽**을 고정한다 |
| 거리 연산 | `<=>`(코사인 거리). 유사도 = `1 - (a <=> b)` | 정규화했으므로 코사인 = 내적이고, 유사도가 [-1, 1]에 들어와 임계값을 사람이 읽을 수 있다 |
| 모델명 바꾸는 수단 | 시크릿 **`GEMINI_EMBEDDING_MODEL`**(없으면 코드 기본값) | 기존 `GEMINI_MODEL`의 선례 그대로(`gemini.ts` 머리 주석: "무료 등급 모델이 바뀌면 시크릿만 바꾼다"). 모델명이 바뀌면 `embedding_model` 키가 자동으로 바뀌어 **옛 벡터가 조회 대상에서 빠진다**(수용 기준 "임베딩 모델이 바뀌기 전의 벡터와 비교하지 않는다") |
| 실패 처리 | `GeminiError`를 던지고 호출부가 **미적중으로 간주**한다 | 수용 기준 "임베딩 호출이 실패하면 AI 생성으로 그대로 넘어간다". 타임아웃은 **10초**(생성은 30초) — 조회 한 단계가 사용자 체감을 30초 늘리는 일이 없어야 한다 |

**차원이 768로 못 박히는 자리는 두 곳**(DB 컬럼 `vector(768)`, 코드 상수 `EMBEDDING_DIM`)이고 둘이 어긋나면 적재가 insert에서 깨진다. 그래서 `toVectorLiteral`이 길이를 먼저 검사한다(4장). 768을 지원하지 않는 모델로 갈아타려면 **마이그레이션이 필요하다**(컬럼 차원 변경) — 지금 미리 대비하지 않는다.

### 1.2 생성 모델과 임베딩 모델의 요청 한도가 별도 풀인가

**결론: 별도 풀로 설계하되, 숫자와 사실 확인은 developer가 배포 전에 문서에서 다시 본다(= 이 설계에서 "확인 못 함"으로 표시한다).**

- 내가 아는 바로는 Gemini API의 무료 등급 한도(RPM/RPD)는 **모델별로 표에 적혀 있고**, 임베딩 모델의 RPM·RPD는 Flash 계열 생성 모델보다 **훨씬 넉넉하다.** 즉 `gemini-2.5-flash`의 RPD를 임베딩이 깎지 않는다.
- **다만 이 설계는 네트워크 접근 없이 쓰였고, 그 표는 수시로 바뀐다.** 그래서 숫자를 이 문서에 적지 않는다(적으면 틀린 숫자가 근거로 굳는다). **확인 못 함으로 남긴다.**
- **developer가 할 일**(10장 단계 2에 포함): `https://ai.google.dev/gemini-api/docs/rate-limits`의 Free tier 표에서 ① `gemini-2.5-flash`와 ② `gemini-embedding-001`의 RPM/RPD가 **각 모델 행에 따로 적혀 있는지**, ③ 프로젝트 단위 공유 한도(TPM 등)가 둘을 묶는지 확인하고, 결과를 `plan.md`에 세 줄로 적는다.
- **같은 풀이었다면**(= 임베딩이 생성 모델의 RPD를 깎는다면): spec 트레이드오프 1번이 그대로 살아나 **적중률 50% 전까지 이 기능이 요청 수를 늘리기만 한다.** 그때는 구현을 멈추고 오너에게 다시 묻는다 → "## 결정 필요" 1번.
- **어느 쪽이든 바뀌지 않는 것**: 캐시 적중이 **하루 10회 한도**를 쓰지 않는다는 사용자 이익(이건 Google의 한도와 무관한 우리 원장이다)과 체감 속도.

---

## 2. 데이터

### 2.1 캐시를 어디에 두는가 — **별도 테이블**(`criteria_checks` 재사용 기각)

| 안 | 판단 | 이유 |
|---|---|---|
| A. `criteria_checks`를 그대로 조회한다 | **기각** | ① **보안 성질이 즉시 깨진다.** 이 테이블에는 `action = 'check'` 행으로 **사용자가 손으로 쓴 기준**이 들어 있다(참고 사실 2). 조회에서 `action = 'generate'`만 걸러도, 그 필터 한 줄이 "사용자 입력 전파 차단"의 전부가 된다 — spec이 보안 성질로 격상한 조항을 `where` 절 하나에 매단다 ② **탈퇴 때 지워진다**(참고 사실 3). 오너 결정 3("탈퇴와 무관하게 남는다")을 만족할 수 없고, 1인~소수 사용자 단계에서 탈퇴 한 번에 캐시가 거의 비워진다 ③ **RLS가 자기 행만 보게 되어 있다.** Edge는 service_role이라 뚫고 지나가지만, 그러면 "교차 사용자 재사용"이 정책이 아니라 **키의 힘으로** 이뤄진다 — 사용자 롤에 정책 하나를 잘못 추가하면 남의 증서가 그대로 노출된다 ④ 증서는 **1회 소진·24시간 만료**가 있는 물건이고 캐시는 영구 지식이다. 한 행이 두 수명을 가질 수 없다 ⑤ 임베딩 벡터·임베딩 모델 버전을 담을 자리가 없어 컬럼을 더해야 하는데, 그 컬럼은 **사용자 증서의 99%에게 의미가 없다** |
| **B. 별도 테이블 `public.criteria_cache`** | **채택** | ① **사용자 식별 정보가 한 칸도 없다** → 개인 데이터가 아니고(오너 결정 3), 탈퇴·동의 철회·RLS와 엮이지 않는다 ② **AI 원본만 들어가는 테이블**이 되어 보안 성질이 `where` 절이 아니라 **적재 코드의 위치**로 지켜진다(원칙 5 — 적재 호출이 `generate` 성공 경로 한 자리에만 있다) ③ 제약을 `criteria_checks`와 **같은 모양으로** 걸어, 캐시 행이 언제나 유효한 증서가 될 수 있음을 DB가 보장한다 ④ 교차 사용자 재사용이 "정책 0개 + 서버 함수 한 짝"으로 설명된다 |
| C. `criteria_checks`에 벡터 컬럼만 더하고 `action='generate'`를 캐시로 본다 | 기각 | A의 ②③④를 그대로 물려받는다. "조금 덜 고치는" 안이지만 **깨지는 성질이 줄지 않는다** |

### 2.2 마이그레이션 (파일 하나, 이게 서버 변경의 전부다)

`supabase/migrations/20261111120000_criteria_cache.sql`

```sql
-- 판정 기준 캐시(criteria-cache P0·P1).
--
-- 근거: docs/specs/criteria-cache/spec.md(2026-11-11 오너 승인)와 같은 폴더 design.md.
--
-- 무엇인가: **기준 생성 AI 호출 앞에 끼우는 조회 한 단계**다. 제목을 임베딩해 뜻이 가까운 주제의
-- AI 원본 기준이 이미 있으면 그것으로 증서를 만들고 Gemini 생성 호출을 하지 않는다.
-- 판정(1차 상호 판정 → 2차 AI 재판정)·상태 전이·승부·점수·마감·정산에는 한 줄도 닿지 않는다.
--
-- 핵심 규칙
--   - 이 테이블에는 **사용자 식별 정보가 없다**(user_id도 battle_id도 없다). 그래서 개인 데이터가
--     아니고 탈퇴와 무관하게 남는다(오너 결정 3). delete_account()는 이 테이블을 건드리지 않는다.
--   - **AI 원본만 들어온다.** 사용자가 손으로 고친 기준(criteria_checks의 action='check')은 적재
--     경로가 아예 없다 - "무조건 합격시켜라" 같은 문장이 캐시를 타고 전파되는 길을 만들지 않는다.
--   - 조회 대상은 **지금의 생성 모델/프롬프트 버전 + 지금의 임베딩 모델/작업유형/차원**으로 만든
--     행뿐이다. 버전이 바뀌면 옛 행은 지우지 않고 조회에서만 빠진다(끝난 대결의 기준 설명 자료).
--   - 적중은 하루 10회 한도를 소모하지 않는다. 그래서 적중 경로는 ai_criteria_calls에
--     **아무것도 쓰지 않는다**(원장의 뜻을 "AI에게 기준을 물은 횟수"로 유지한다).
--
-- 적용 순서: 이 파일 → Edge Function 배포. 반대로 하면 Edge가 없는 함수를 불러 조회가 실패하는데,
-- 그 실패는 "캐시 미적중"과 결과가 같아 기준 생성 자체는 계속 동작한다(설계 원칙 6).

-- ---------------------------------------------------------------------------
-- 0) pgvector
-- ---------------------------------------------------------------------------
-- Supabase의 관례대로 extensions 스키마에 둔다(public을 확장 타입으로 더럽히지 않는다).
-- 아래 함수들이 set search_path = public, extensions로 선언되는 이유가 이것이다 - 벡터 타입과
-- <=> 연산자가 그 스키마에 있다. search_path에서 extensions를 빼면 함수가 깨진다.
create extension if not exists vector with schema extensions;

-- ---------------------------------------------------------------------------
-- 1) 캐시 테이블
-- ---------------------------------------------------------------------------
create table public.criteria_cache (
  id uuid primary key default gen_random_uuid(),
  -- 유형이 캐시 키에 들어간다(spec P0). 품질전은 우열 기준이 있어야 하고 속도전은 없어야 하며,
  -- 최소 기준의 뜻도 다르다(통과선 vs 참가선). 섞으면 증서 제약에서 깨지거나 뜻이 틀어진다.
  type text not null
    constraint criteria_cache_type_check check (type in ('speed', 'quality')),
  -- 정규화된 제목. **조회 키이고 진단 자료다.** 사용자에게 보여 주지 않으며, 조회 함수는 이 값을
  -- 반환값에 담지 않는다(남의 제목이 내 화면에 가는 경로를 반환 모양으로 막는다).
  title_norm text not null
    constraint criteria_cache_title_check check (length(title_norm) between 1 and 60),
  provable boolean not null,
  min_criteria jsonb not null default '[]'::jsonb,
  superiority_criteria jsonb,
  -- AI가 쓴 차단 사유 원문. **오너 진단용으로만 남긴다.** 다른 제목에 붙으면 틀린 설명이 되므로
  -- 적중 증서에는 이 값을 복사하지 않고 제목과 무관한 고정 문장을 쓴다(issue_cached_criteria_check).
  block_reason text,
  -- 'gemini-2.5-flash/p1' 형태. criteria_checks.ai_model과 같은 표기를 쓴다.
  ai_model text not null,
  -- 'gemini-embedding-001/SEMANTIC_SIMILARITY/768' 형태. 모델·작업유형·차원이 모두 벡터 공간을
  -- 바꾸므로 셋을 한 키로 묶는다. 서로 다른 공간의 벡터를 비교한 유사도는 아무 뜻이 없다.
  embedding_model text not null,
  -- L2 정규화된 제목 임베딩. 코사인 거리(<=>)로 비교한다.
  embedding extensions.vector(768) not null,
  created_at timestamptz not null default now(),
  -- 아래 네 제약은 criteria_checks의 것과 **같은 모양**이다. 캐시 행이 언제나 유효한 증서가 될 수
  -- 있음을 DB가 보장한다(한쪽만 바뀌면 적중이 증서 insert에서 깨진다).
  constraint criteria_cache_min_shape
    check (not provable or public.is_criteria_list(min_criteria)),
  constraint criteria_cache_superiority_shape
    check (superiority_criteria is null or public.is_criteria_list(superiority_criteria)),
  constraint criteria_cache_superiority_by_type
    check (not provable or ((type = 'quality') = (superiority_criteria is not null))),
  constraint criteria_cache_block_reason
    check (provable or (block_reason is not null and length(btrim(block_reason)) > 0))
);

comment on table public.criteria_cache is
  'AI가 만든 판정 기준의 재사용 저장소. 사용자 식별 정보가 없어 개인 데이터가 아니며 탈퇴와 '
  '무관하게 남는다. AI 원본만 들어오고 사용자가 고친 기준은 들어오지 않는다.';
comment on column public.criteria_cache.title_norm is
  '정규화된 제목(앞뒤·중복 공백 정리, 소문자화, NFC). 조회 키와 진단 자료이며 사용자에게 보여 주지 않는다.';
comment on column public.criteria_cache.block_reason is
  'AI가 쓴 차단 사유 원문. 진단용이다 - 다른 제목에 붙으면 틀린 설명이 되므로 증서로 복사하지 않는다.';
comment on column public.criteria_cache.embedding is
  'L2 정규화된 제목 임베딩(768차원). embedding_model이 가리키는 공간의 벡터끼리만 비교한다.';

-- 조회 두 경로가 함께 쓰는 인덱스. 앞의 세 칸이 버전 대조 필터이고, title_norm·created_at이
-- 정규화 일치 경로의 "가장 최근 하나"를 바로 집는다. 벡터 경로는 앞 세 칸으로 후보를 좁힌 뒤
-- 순차 비교한다 - **ANN 인덱스(ivfflat·hnsw)를 만들지 않는다.**
--   이유: ① 지금 행 수는 0이고 배포 후에도 수백 규모다. 그 규모에서 순차 비교가 ANN보다 빠르고
--   무엇보다 **정확하다**(ANN은 근사라 임계값 바로 위의 후보를 놓칠 수 있는데, 이 기능에서
--   "놓침"은 AI를 한 번 더 부르는 손해로 끝나지만 **재현되지 않는 적중/미적중**은 디버깅을
--   불가능하게 만든다) ② ivfflat은 학습 데이터가 있어야 제 성능이 나오고 지금은 데이터가 없다
--   ③ CLAUDE.md "미리 만들지 말 것". 행이 1만을 넘고 조회가 느려지면 그때 hnsw를 붙인다
--   (768차원이라 붙일 수 있다 - 그래서 3072차원을 고르지 않았다).
create index criteria_cache_lookup_idx
  on public.criteria_cache (type, ai_model, embedding_model, title_norm, created_at desc);

-- ---------------------------------------------------------------------------
-- 2) RLS - 정책을 **하나도** 만들지 않는다
-- ---------------------------------------------------------------------------
-- CLAUDE.md는 "RLS 정책은 테이블 만들 때 같이 작성한다"고 정한다. 이 테이블의 정답은 **정책 0개**다:
-- 어떤 사용자도 이 테이블을 직접 읽어서는 안 된다(spec 보안 성질 - "클라이언트가 캐시를 직접 읽어
-- 기준 텍스트를 들고 와 대결을 만드는 경로가 없다", "다른 사용자의 캐시 내용을 직접 조회하는
-- 클라이언트 경로가 없다"). RLS를 켜고 정책을 비우면 anon·authenticated는 0행을 본다.
-- Supabase는 public 스키마의 새 테이블에 anon·authenticated로 권한을 기본 부여하므로 권한까지 닫는다.
-- 닿는 길은 service_role(Edge Function)이 부르는 아래 함수들뿐이다.
alter table public.criteria_cache enable row level security;

revoke all on table public.criteria_cache from anon, authenticated;
```

### 2.3 인덱스·RLS·권한·탈퇴 영향 요약

| 항목 | 판단 |
|---|---|
| 인덱스 | btree 하나(`criteria_cache_lookup_idx`). **ANN 벡터 인덱스를 만들지 않는다**(2.2 주석의 근거 3개) |
| RLS 정책 | **0개.** RLS 켜고 권한 회수 → 사용자 롤에서 보이지 않는다. 정책을 "나중에 붙이지 않는다"가 아니라 **끝까지 붙이지 않는 것이 설계**다 |
| 테이블 권한 | `revoke all ... from anon, authenticated`. service_role은 기본 권한을 유지하되, 네 함수가 SECURITY DEFINER라 테이블 권한에 의존하지 않는다 |
| `delete_account()` | **한 줄도 고치지 않는다.** 캐시에 `user_id`가 없어 지울 대상이 없다(오너 결정 3). 증서·호출 원장 삭제는 그대로 |
| `withdraw_ai_consent` | **고치지 않는다.** 캐시는 사용자와 무관하고, 철회 뒤에는 `assert_criteria_consent`가 조회 자체를 막는다 |
| `is_criteria_list` | 기존 함수를 그대로 쓴다(새로 만들지 않는다) |
| 개인정보처리방침 | `privacy.html`의 "탈퇴 시 처리" 표에 **캐시에 해당하는 행이 없다.** "대결 기록(대결 제목, 유형, 판정 기준…) → 탈퇴자를 식별할 수 없는 상태로 보존"이 가장 가깝지만, 캐시에는 **대결이 된 적 없는 제목**(차단된 제목·올리지 않은 제목)도 남는다 → "## 결정 필요" 3번 |

### 2.4 캐시 키와 조회 조건

**키(= 같은 공간에 있다고 보는 조건, 전부 `and`)**

| 칸 | 값 | 왜 키인가 |
|---|---|---|
| `type` | `speed` \| `quality` | spec P0. 모양이 다르고(DB 제약), 최소 기준의 뜻이 다르고, 애초에 프롬프트의 입력이다 |
| `ai_model` | `${GEMINI_MODEL}/${PROMPT_VERSION}` 예: `gemini-2.5-flash/p1` | spec P0 "프롬프트·모델 버전이 바뀌면 그 전 캐시는 쓰지 않는다". 프롬프트를 고친 효과가 **모든 사용자에게 같이** 나타난다 |
| `embedding_model` | `${GEMINI_EMBEDDING_MODEL}/${TASK_TYPE}/${DIM}` | 서로 다른 공간의 벡터를 비교한 유사도는 뜻이 없다 |
| `provable` | P0에서는 `true`만, P1에서 차단 행까지 | 10장 단계 6이 플래그 하나를 바꾼다 |

**기간(`duration_minutes`)은 키에 넣지 않는다.** 프롬프트의 입력이긴 하지만(참고 사실 5) ① 프롬프트가 "시간의 경과는 기준으로 쓰지 않는다"를 강제하므로 기간이 기준 문장을 바꾸는 폭이 작고 ② 기간은 1~10080의 자유 정수라 키에 넣으면 적중률이 사실상 0이 되어 기능의 동기가 사라지고 ③ 어긋나면 생성자가 그 자리에서 고친다. spec이 정하지 않은 자리라 "## 결정 필요" 2번에 올린다.

**조회(두 경로, 위에서부터 먼저 시도한다)**

| 경로 | 조건 | Gemini 호출 | 왜 필요한가 |
|---|---|---|---|
| ① 정규화 일치 | 키 전부 일치 **and** `title_norm = ?`<br>`order by created_at desc limit 1` | **0회** | 같은 제목을 그대로 다시 적는 가장 흔한 경우를 **임베딩조차 없이** 잡는다(= spec 트레이드오프 1번의 "미적중이면 임베딩이 그냥 얹힌다"를 가장 흔한 구간에서 피한다). 그리고 `order by created_at desc`가 **"같은 주제에 여러 개면 가장 최근 것"** 규칙을 그대로 구현한다(`기준 다시 만들기`로 생긴 둘째 행이 다음 사람에게 간다) |
| ② 벡터 유사도 | 키 전부 일치 **and** `1 - (embedding <=> ?) >= 임계값`<br>`order by embedding <=> ? asc, created_at desc limit 1` | 임베딩 1회 | 오너 결정 2("뜻이 가까우면 재사용"). 가장 가까운 하나를 고르고, 거리가 같으면(= 제목이 같아 벡터가 같으면) 가장 최근 것을 고른다 |

- **두 경로의 비교 방식이 둘로 갈리지 않는다.** 정규화 일치는 "유사도 1.0"의 특수한 경우이고, 결과의 종류(기준 목록 + 통과/차단)와 그 뒤의 처리가 완전히 같다. 경로 ①은 **경로 ②가 반드시 잡을 적중을 임베딩 없이 먼저 잡는 지름길**이고, ①이 ②보다 느슨한 적중을 만드는 경우가 없다.
- **차단 캐시의 조회가 통과 캐시와 다른 점은 `provable` 필터 하나뿐이다**(오너 결정 1로 완전 일치 한정이 사라졌다). 다른 점은 조회가 아니라 **증서를 만들 때** 생긴다 — 차단 사유를 복사하지 않는다(5.3).
- **임계값을 넘지 못하면 아무 일도 일어나지 않는다.** 오류가 아니고 화면에 흔적도 없다. 지금과 똑같이 AI를 부른다.

### 2.5 새 RPC 넷 (같은 마이그레이션 파일에 이어 적는다)

```sql
-- ---------------------------------------------------------------------------
-- 3) 아래 네 함수는 service_role 전용이다 - Edge Function battle-criteria가 부른다.
-- ---------------------------------------------------------------------------
-- CLAUDE.md의 "SECURITY DEFINER 함수는 auth.uid() is null 가드를 둔다" 규칙의 **예외**를 적용한다
-- (선례: settle_expired_battles, begin_criteria_call). service_role에는 auth.uid()가 없어 그 가드가
-- 항상 실패하기 때문이다. 대신 ① authenticated까지 EXECUTE를 회수하고 ② 사용자 id는 Edge Function이
-- JWT로 확인한 값을 인자로 넘기며 ③ 이 주석이 그 예외의 이유를 남긴다.

-- (3-1) 한도를 쓰지 않는 동의 관문.
--
-- **이 함수가 있어야 하는 이유**: 동의 확인은 지금 begin_criteria_call 안에 있고 그 함수는 확인과
-- **한도 예약을 한 트랜잭션에서 같이** 한다. 캐시 조회(임베딩 호출)는 동의 **뒤**에, 한도 예약
-- **앞**에 와야 하는데(design 3.1) 지금 그 사이에 설 자리가 없다. 그 자리를 이 함수가 만든다.
-- begin_criteria_call은 **한 줄도 바꾸지 않는다** - 동의 확인이 거기 남아 있어야 생성 경로의
-- 기존 보장("동의 전에는 Gemini를 부르지 않는다")이 이 함수의 존재와 무관하게 유지된다.
create function public.assert_criteria_consent(p_user_id uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  if p_user_id is null then
    raise exception '사용자가 필요합니다.';
  end if;

  perform 1 from public.ai_consents where user_id = p_user_id;
  if not found then
    raise exception using message = 'AI 데이터 제공 동의가 필요합니다.', hint = 'CONSENT_REQUIRED';
  end if;
end;
$$;

comment on function public.assert_criteria_consent(uuid) is
  'AI 데이터 제공 동의만 확인한다(한도를 쓰지 않는다). 캐시 조회의 임베딩 호출 전에 부르는 관문 - '
  '동의 전에는 대결 제목이 임베딩으로도 Gemini에 가지 않는다. Edge Function 전용.';

-- (3-2) 캐시 조회. 정규화 일치 → 벡터 유사도 순.
--
-- **반환값에 title_norm과 block_reason을 담지 않는다.** 원 제목과 원 차단 사유가 호출부로 나가지
-- 않으므로, 그것을 사용자에게 흘릴 코드가 Edge에 존재할 수 없다(design 원칙 8).
--
-- p_embedding을 text로 받는 이유: PostgREST가 JSON 배열을 vector로 바꿔 주는 동작에 의존하지
-- 않는다. Edge가 '[0.1,-0.2,...]' 문자열을 만들어 보내고(toVectorLiteral, 유닛 테스트 있음) 여기서
-- 한 번 캐스팅한다. 형식이 깨지면 예외가 나고, 호출부는 그것을 **미적중**으로 처리한다
-- (조회 실패가 기준 생성 실패가 되지 않는다 - 수용 기준 "기존 동작 보존").
create function public.lookup_criteria_cache(
  p_type text,
  p_title_norm text,
  p_ai_model text,
  p_embedding_model text,
  p_embedding text default null,
  p_min_similarity real default null,
  p_include_blocked boolean default false
)
returns jsonb
language plpgsql
security definer set search_path = public, extensions
as $$
declare
  v_vec extensions.vector(768);
  v_row public.criteria_cache%rowtype;
  v_similarity real;
begin
  if p_type not in ('speed', 'quality') then
    raise exception '올바르지 않은 대결 유형입니다.';
  end if;

  -- 경로 ① 정규화 일치. 임베딩 없이도 되는 경로라 벡터 인자를 보지 않는다.
  -- "같은 주제에 여러 개면 가장 최근 것"(spec 탈출구 절)이 이 order by 한 줄이다.
  select * into v_row
  from public.criteria_cache
  where type = p_type
    and ai_model = p_ai_model
    and embedding_model = p_embedding_model
    and title_norm = p_title_norm
    and (provable or p_include_blocked)
  order by created_at desc
  limit 1;

  if found then
    return jsonb_build_object(
      'cache_id', v_row.id,
      'type', v_row.type,
      'provable', v_row.provable,
      'min_criteria', v_row.min_criteria,
      'superiority_criteria', v_row.superiority_criteria,
      'ai_model', v_row.ai_model,
      'embedding_model', v_row.embedding_model,
      'similarity', 1.0,
      'matched_by', 'title'
    );
  end if;

  -- 경로 ② 벡터 유사도. 임베딩이 없으면(호출 실패했으면) 여기서 끝낸다 = 미적중.
  if p_embedding is null or p_min_similarity is null then
    return null;
  end if;

  v_vec := p_embedding::extensions.vector(768);

  select c.*, (1 - (c.embedding <=> v_vec))::real
  into v_row, v_similarity
  from public.criteria_cache c
  where c.type = p_type
    and c.ai_model = p_ai_model
    and c.embedding_model = p_embedding_model
    and (c.provable or p_include_blocked)
    and (1 - (c.embedding <=> v_vec)) >= p_min_similarity
  order by c.embedding <=> v_vec asc, c.created_at desc
  limit 1;

  if not found then
    return null;
  end if;

  return jsonb_build_object(
    'cache_id', v_row.id,
    'type', v_row.type,
    'provable', v_row.provable,
    'min_criteria', v_row.min_criteria,
    'superiority_criteria', v_row.superiority_criteria,
    'ai_model', v_row.ai_model,
    'embedding_model', v_row.embedding_model,
    'similarity', v_similarity,
    'matched_by', 'vector'
  );
end;
$$;

comment on function public.lookup_criteria_cache(text, text, text, text, text, real, boolean) is
  '재사용할 AI 원본 기준을 찾는다(정규화 일치 → 벡터 유사도, 없으면 null). 원 제목·원 차단 사유· '
  '작성자는 반환하지 않는다. Edge Function 전용.';

-- (3-3) 적재. **AI 원본만** 들어온다.
--
-- 이 함수를 부르는 자리는 battle-criteria의 generate 성공 경로 **한 곳**이다. check(사용자 수정분
-- 재검사) 경로에는 호출이 없다 - 사용자가 쓴 문장이 캐시에 들어가는 길을 코드의 위치로 막는다
-- (spec 결정 4의 보안 성질). 같은 주제에 여러 행이 쌓이는 것은 정상이고, 조회가 가장 최근 것을
-- 고른다. 중복 제거·정리를 하지 않는다(지워야 할 행이 생기면 오너가 DB에서 직접 지운다 - spec 범위 밖).
create function public.put_criteria_cache(
  p_type text,
  p_title_norm text,
  p_provable boolean,
  p_min_criteria jsonb,
  p_superiority_criteria jsonb,
  p_block_reason text,
  p_ai_model text,
  p_embedding_model text,
  p_embedding text
)
returns uuid
language plpgsql
security definer set search_path = public, extensions
as $$
declare
  v_id uuid;
begin
  insert into public.criteria_cache (
    type, title_norm, provable, min_criteria, superiority_criteria,
    block_reason, ai_model, embedding_model, embedding
  )
  values (
    p_type,
    p_title_norm,
    p_provable,
    coalesce(p_min_criteria, '[]'::jsonb),
    p_superiority_criteria,
    p_block_reason,
    p_ai_model,
    p_embedding_model,
    p_embedding::extensions.vector(768)
  )
  returning id into v_id;

  return v_id;
end;
$$;

comment on function public.put_criteria_cache(text, text, boolean, jsonb, jsonb, text, text, text, text) is
  'AI가 방금 만든 기준을 캐시에 넣는다. 사용자 수정분은 이 함수를 부르는 경로가 없다. '
  '적재 실패는 사용자의 기준 생성을 막지 않는다(호출부가 로그만 남긴다). Edge Function 전용.';

-- (3-4) 적중 → 증서 1행. **원장(ai_criteria_calls)에 아무것도 쓰지 않는다.**
--
-- 대결 생성은 증서로만 되므로(create_battle) 적중도 증서를 만들어야 한다. 채우는 방식:
--   - title      : **호출자가 쓴 제목**을 그대로 넣는다. 캐시의 title_norm을 넣지 않는다
--                  (남의 제목이 내 대결 제목이 되는 일이 없어야 한다 - spec P0 조회 절).
--   - type·기준  : 캐시 행에서 그대로 복사한다(클라이언트가 보낸 텍스트를 쓰지 않는다).
--   - block_reason: 차단이면 **제목과 무관한 고정 문장**을 쓴다. 캐시의 원문은 원래 제목에 대한
--                  한 줄이라 다른 제목에 붙으면 틀린 설명이 된다(오너 결정 1이 남긴 숙제).
--   - ai_model   : 캐시의 값 + '/cache'. 어떤 코드도 이 컬럼을 읽지 않으므로(동작 변화 없음)
--                  오너가 "이 증서가 어디서 왔는가"를 DB에서 알아볼 수 있게 꼬리만 남긴다.
--                  이 값은 앱 응답에 들어가지 않는다(적중 여부가 화면으로 누설되지 않는다).
--   - consumed_at: null. created_at은 now()이므로 **증서의 24시간 만료는 발급 시점부터** 센다
--                  (캐시 행이 오래됐어도 증서는 신선하다). 1회 소진 규칙도 그대로다.
create function public.issue_cached_criteria_check(
  p_user_id uuid,
  p_title text,
  p_type text,
  p_cache_id uuid,
  p_ai_model text,
  p_embedding_model text
)
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_cache public.criteria_cache%rowtype;
  v_check_id uuid;
  v_block_reason text;
  v_today date := (now() at time zone 'Asia/Seoul')::date;
begin
  -- 조회와 증서 발급 사이에 동의를 철회했을 수도 있다. 증서는 동의 없이 생기지 않는다.
  perform public.assert_criteria_consent(p_user_id);

  -- 키를 다시 대조한다. 조회가 이미 걸렀지만, 증서를 만드는 자리에서 유형·버전을 한 번 더 본다
  -- (유형이 어긋난 기준으로 증서가 만들어지면 그 뒤의 모든 제약이 무의미해진다).
  select * into v_cache
  from public.criteria_cache
  where id = p_cache_id
    and type = p_type
    and ai_model = p_ai_model
    and embedding_model = p_embedding_model;

  if not found then
    raise exception using message = '사용할 수 없는 기준입니다.', hint = 'CHECK_INVALID';
  end if;

  if not v_cache.provable then
    -- 제목과 무관하게 참인 한 줄. 원래 제목의 사유를 복사하지 않는다.
    v_block_reason := '사진 한 장으로는 완료를 확인할 수 없는 주제로 보여요.';
  end if;

  insert into public.criteria_checks (
    user_id, action, battle_id, title, type,
    min_criteria, superiority_criteria, provable, block_reason, ai_model
  )
  values (
    p_user_id,
    'generate',
    null,
    btrim(p_title),
    v_cache.type,
    v_cache.min_criteria,
    v_cache.superiority_criteria,
    v_cache.provable,
    v_block_reason,
    v_cache.ai_model || '/cache'
  )
  returning id into v_check_id;

  -- calls_left는 finish_criteria_call과 **같은 식**이다. 적중은 원장을 건드리지 않았으므로 이 값이
  -- 요청 전과 같고, 화면의 `오늘 남은 기준 생성 N/10회`가 줄지 않는다(spec P0 한도 절).
  return jsonb_build_object(
    'check_id', v_check_id,
    'provable', v_cache.provable,
    'min_criteria', v_cache.min_criteria,
    'superiority_criteria', v_cache.superiority_criteria,
    'block_reason', v_block_reason,
    'calls_left', greatest(10 - public.criteria_calls_used(p_user_id, v_today), 0)
  );
end;
$$;

comment on function public.issue_cached_criteria_check(uuid, text, text, uuid, text, text) is
  '캐시 적중을 기준 증서 1행으로 만든다. 제목은 호출자가 쓴 것을 쓰고, 차단이면 제목과 무관한 '
  '고정 사유를 쓴다. 하루 10회 원장에는 아무것도 쓰지 않는다. Edge Function 전용.';

-- ---------------------------------------------------------------------------
-- 4) 권한. Postgres는 PUBLIC에, Supabase는 anon에 EXECUTE를 기본으로 준다.
--    네 함수 모두 사용자 롤이 직접 부를 수 있어서는 안 되므로 authenticated까지 회수한다.
-- ---------------------------------------------------------------------------
revoke execute on function public.assert_criteria_consent(uuid)
  from public, anon, authenticated;
revoke execute on function public.lookup_criteria_cache(text, text, text, text, text, real, boolean)
  from public, anon, authenticated;
revoke execute on function public.put_criteria_cache(text, text, boolean, jsonb, jsonb, text, text, text, text)
  from public, anon, authenticated;
revoke execute on function public.issue_cached_criteria_check(uuid, text, text, uuid, text, text)
  from public, anon, authenticated;

grant execute on function public.assert_criteria_consent(uuid) to service_role;
grant execute on function public.lookup_criteria_cache(text, text, text, text, text, real, boolean)
  to service_role;
grant execute on function public.put_criteria_cache(text, text, boolean, jsonb, jsonb, text, text, text, text)
  to service_role;
grant execute on function public.issue_cached_criteria_check(uuid, text, text, uuid, text, text)
  to service_role;
```

**이 파일에 더 들어가는 것은 없다.** 트리거·cron·새 정책·`criteria_checks` 스키마 변경·`begin_criteria_call` 재정의가 **없다**(기존 함수 7개를 한 줄도 고치지 않는 것이 이 설계의 성질이다).

---

## 3. Edge Function 흐름 (`supabase/functions/battle-criteria/index.ts`)

### 3.1 **동의 확인이 임베딩보다 먼저, 한도 예약은 그 뒤** — 이 설계의 핵심

**문제.** 두 요구가 지금 코드 한 줄에서 충돌한다.

| 요구 | 출처 |
|---|---|
| (가) 동의하지 않은 사용자의 제목은 **임베딩으로도** Gemini에 가지 않는다 | spec "동의와 개인정보 — 위반하면 반려" |
| (나) 캐시 적중은 하루 10회 한도를 **소모하지 않는다** | spec "P0 한도" |

지금 동의 확인은 `begin_criteria_call` 안에 있고, 그 함수는 **확인과 한도 예약(`in_progress` 행 insert)을 한 트랜잭션에서 같이** 한다. 그래서:
- 조회를 `begin_criteria_call` **뒤**에 두면 (가)는 지켜지지만 **적중인데도 1회가 예약된다** → (나) 위반. 적중 뒤에 그 행을 `failed`로 지우는 보정은 "성공했는데 실패로 적는" 원장이 되고, 그 사이에 들어온 동시 요청은 2분 규칙 때문에 한도를 한 칸 덜 받는다.
- 조회를 `begin_criteria_call` **앞**에 두면 (나)는 지켜지지만 **동의 확인 전에 임베딩이 나간다** → (가) 위반, 즉 반려.

**해결.** 동의 확인을 한도 예약에서 **떼어 앞에 세운다.** 새 함수 `assert_criteria_consent`(2.5)가 동의만 보고 원장을 건드리지 않는다.

```
   JWT 확인 → 입력 검증
      ↓
 ① assert_criteria_consent        ← 동의 관문. 한도를 쓰지 않는다.    (가) 해결
      ↓                             여기서 막히면 Gemini를 **한 번도** 부르지 않는다
 ② 캐시 조회(정규화 일치 → 임베딩 → 벡터)                             (나) 해결
      ↓
   적중? ──예→ issue_cached_criteria_check        … 원장 0행, 한도 0회
      │
      아니오
      ↓
 ③ begin_criteria_call            ← 여기서 처음 한도를 본다/예약한다
      ↓                             (동의 확인이 이 안에 **그대로 남아 있다**)
   Gemini 생성 → finish / fail → put_criteria_cache
```

**왜 이게 안전한가**
- **동의 확인이 두 번 일어난다(①과 ③ 안).** 중복이 아니라 **두 보장이 각각 서다**: ①은 "임베딩보다 먼저"를, ③은 "생성 호출보다 먼저"를 지킨다. `begin_criteria_call`을 고치지 않으므로, 이 Edge Function의 순서가 미래에 바뀌어도 생성 경로의 기존 보장은 무너지지 않는다.
- **동의 철회와의 경합**: ①을 지난 뒤 철회해도 ③(미적중)이나 `issue_cached_criteria_check`(적중)가 다시 보고 막는다. 즉 **증서는 동의 없이 생기지 않는다.**
- **한도를 다 쓴 사용자**도 ①②를 지나므로 적중이면 기준을 받는다(수용 기준). 대가는 "한도 소진 사용자가 임베딩 쿼터를 쓸 수 있다"이고, 임베딩에 상한을 두지 않기로 한 오너 결정 2가 이미 그것을 받아들였다.
- **`check`(재검사) 경로는 ①②를 지나지 않는다.** 임베딩이 없으므로 (가)의 새 위험이 없고, 동의 확인은 `begin_criteria_call`에 그대로 있다 → **코드가 한 줄도 바뀌지 않는다**(수용 기준 "재검사의 한도 소모가 지금과 같다").

### 3.2 `generate` 흐름 (단계별로 확정)

```
0. req.method !== 'POST'             → BAD_REQUEST                      (그대로)
1. getUserId(req)                    → 없으면 UNAUTHORIZED              (그대로)
2. parseCriteriaRequest(body)        → 실패면 BAD_REQUEST                (skip_cache 추가, 4장)
3. assert_criteria_consent(userId)   → hint CONSENT_REQUIRED면 403        (신규)
4. source 결정 (skip_cache가 false일 때만 조회한다)
   4-1. titleNorm = normalizeTitle(request.title)
   4-2. lookup_criteria_cache(정규화 일치용 인자만: p_embedding = null)
        → 적중이면 6으로
   4-3. embedText(titleNorm)              … 10초 타임아웃
        실패(GeminiError) → console.error 후 **미적중으로 간주**하고 5로
   4-4. lookup_criteria_cache(벡터 인자까지)
        → 적중이면 6으로
   4-5. 조회 자체가 예외(RPC 오류·캐스팅 실패) → console.error 후 미적중으로 간주
5. 미적중 경로 (= 지금의 흐름 그대로)
   5-1. begin_criteria_call(userId, 'generate', null)
        hint 그대로 매핑(CONSENT_REQUIRED / CRITERIA_CALL_LIMIT …)
   5-2. generateJson(생성 프롬프트, 30초)  → parseGenerationResponse
        실패 → fail_criteria_call → AI_FAILED (한도 미산입)
   5-3. finish_criteria_call(...)         → 증서 + calls_left
   5-4. 적재: 임베딩이 없으면(skip_cache 경로거나 4-3이 실패했으면) 여기서 한 번 만든다.
        그마저 실패하면 적재를 건너뛴다. 성공이면 put_criteria_cache(...).
        **이 단계의 어떤 실패도 응답을 바꾸지 않는다**(console.error만).
   5-5. 응답 = finish_criteria_call의 결과
6. 적중 경로
   6-1. parseCacheHit(row, {type, aiModel, embeddingModel, minSimilarity, includeBlocked})
        → 유형·버전·임계값을 **Edge에서 한 번 더** 본다(순수 함수, 유닛 테스트).
          어긋나면 console.error 후 5로 내려간다(= 미적중 취급)
   6-2. issue_cached_criteria_check(userId, request.title, type, cacheId, aiModel, embeddingModel)
        실패 → console.error 후 **5로 내려간다**(한도 1회를 쓰고 사용자는 결과를 받는다.
        드문 서버 오류로 사용자를 빈손으로 돌려보내지 않는다)
   6-3. 응답 = issue_cached_criteria_check의 결과
7. 응답 모양은 두 경로가 **완전히 같다**(아래 7장). 적중 여부를 가리키는 필드가 없다.
```

- **`skip_cache = true`(= `기준 다시 만들기`)**: 4를 통째로 건너뛰고 5로 간다. 즉 **캐시를 건너뛰고 AI에게 새로 묻고 한도 1회를 쓴다.** 그 결과는 5-4에서 다시 캐시에 들어가고, `created_at`이 더 커서 **다음 사람에게는 그것이 간다**(2.4 경로 ①·②의 `created_at desc`).
- **로그**(관측 도구를 만들지 않으므로 이게 전부다): 적중 시 `console.log`에 `matched_by`·`similarity`·`cache_id`·두 모델 키만 남긴다. **제목·기준 문장은 로그에 남기지 않는다**(기존 코드도 그렇다).

### 3.3 `check` 흐름

**한 줄도 바뀌지 않는다.** 캐시 조회·임베딩·적재가 없고, `begin_criteria_call`이 동의와 한도를 지금처럼 본다. `skip_cache`가 `true`로 오면 입력 검증에서 `BAD_REQUEST`로 막는다(클라이언트 버그를 조용히 넘기지 않는다).

### 3.4 실패 모드 표

| 상황 | 결과 | 한도 | 사용자가 보는 것 |
|---|---|---|---|
| 동의 없음 | ①에서 403 `CONSENT_REQUIRED` | 0 | 기존 동의 안내(`aiConsentRequired`) |
| 정규화 일치 적중 | 증서 발급 | **0** | 지금과 같은 기준 화면 |
| 벡터 적중 | 증서 발급 | **0** | 지금과 같은 기준 화면 |
| 임베딩 실패·타임아웃 | 미적중으로 진행 | 1 | **아무 차이 없음**(기준이 나온다) |
| 조회 RPC 실패 | 미적중으로 진행 | 1 | 차이 없음 |
| `parseCacheHit` 불일치 | 미적중으로 진행 | 1 | 차이 없음 |
| 증서 발급 실패(적중) | 미적중으로 진행 | 1 | 차이 없음 |
| 한도 소진 + 적중 | 증서 발급 | 0 | 기준이 나온다(수용 기준) |
| 한도 소진 + 미적중 | 429 `CRITERIA_CALL_LIMIT` | 0 | 기존 한도 문구 |
| Gemini 생성 실패 | `fail_criteria_call` → 502 `AI_FAILED` | 0 | 기존 AI 실패 문구 |
| 적재 실패 | 무시(로그만) | 1 | 차이 없음(기준은 나왔다) |
| 캐시가 비어 있음(배포 직후) | 전부 미적중 | 1 | 지금과 완전히 같다 |

---

## 4. 공용 모듈 — 순수 함수를 어디에 둘 것인가

### 4.1 `gemini.ts`에 `embedText()`를 **얹는다**(새 파일을 만들지 않는다)

`gemini.ts`의 머리 주석이 "**Gemini 호출은 여기 한 곳에서만 한다. 모델명도 여기에만 있다.** 키는 Edge 환경변수로만 읽는다"를 규칙으로 못 박았다. 임베딩도 Gemini 호출이고 키를 읽으므로 **그 규칙을 지키려면 같은 파일**이다. `generateJson`과는 별개 함수다(엔드포인트·요청 본문·응답 모양이 다르고, 구조화 출력 스키마가 없다).

```ts
// gemini.ts에 더하는 것
const DEFAULT_EMBEDDING_MODEL = 'gemini-embedding-001';
export const embeddingModel = Deno.env.get('GEMINI_EMBEDDING_MODEL') ?? DEFAULT_EMBEDDING_MODEL;
/// 제목 대 제목 비교이므로 비대칭 공간(RETRIEVAL_*)을 쓰지 않는다. 이 값도 캐시 키에 들어간다.
export const EMBEDDING_TASK_TYPE = 'SEMANTIC_SIMILARITY';
/// pgvector의 ANN 인덱스가 2000차원까지만 다루고, 비교·저장 비용도 1/4이다(design 1.1).
export const EMBEDDING_DIM = 768;

/// 제목 하나의 임베딩. 실패는 전부 GeminiError다(호출부가 "미적중"으로 처리한다).
/// 반환값은 **L2 정규화되지 않은 원본**이고, 정규화는 호출부가 순수 함수로 한다(테스트 가능한 자리).
export async function embedText(text: string, timeoutMs = 10_000): Promise<number[]>
//   POST /v1beta/models/{embeddingModel}:embedContent
//   body { model: `models/${embeddingModel}`, content: { parts: [{ text }] },
//          taskType: EMBEDDING_TASK_TYPE, outputDimensionality: EMBEDDING_DIM }
//   응답 embedding.values(number[])가 아니거나 길이가 EMBEDDING_DIM이 아니면 GeminiError('PARSE')
```

- 실패 분류는 기존 `GeminiFailure`를 그대로 쓴다(`CONFIG`/`HTTP`/`TIMEOUT`/`NETWORK`/`EMPTY`/`PARSE`). 새 오류 타입을 만들지 않는다.
- `errors.ts`의 `ERROR_CODES`에 **새 코드를 추가하지 않는다.** 임베딩 실패는 사용자에게 보이는 실패가 아니기 때문이다(미적중과 같다).

### 4.2 `supabase/functions/_shared/criteria_cache.ts` (신규, **전부 순수**)

Deno 의존성 없음, `Deno.env`를 읽지 않음 → `deno test`가 그대로 돈다. 환경에서 오는 값(모델명 등)은 **인자로 받는다.**

```ts
/// 캐시 조회에 쓰는 제목 정규화. **증서·프롬프트에 들어가는 제목은 정규화하지 않는다**
/// (증서의 제목은 "내가 쓴 제목"이어야 한다 - spec 수용 기준).
export function normalizeTitle(raw: string): string
//   NFC 정규화 → 모든 공백류(전각 공백 U+3000 포함)를 하나로 접기 → trim → 소문자화

export function aiModelKey(model: string, promptVersion: string): string        // 'gemini-2.5-flash/p1'
export function embeddingModelKey(model: string, taskType: string, dim: number): string

export function l2Normalize(values: number[]): number[]      // 길이 0이면 ValidationError
export function toVectorLiteral(values: number[], dim: number): string
//   '[0.1,-0.2,...]'. 길이가 dim이 아니거나 유한수가 아니면 ValidationError

export function cosineSimilarity(a: number[], b: number[]): number   // 임계값 측정 스크립트와 테스트용

/// 유사도 임계값. **이 값이 사는 자리는 여기 하나다**(DB도, 시크릿도, 화면도 아니다 - design 원칙 7).
/// 8장의 측정 결과로 정하고, 바꿀 때는 그 표를 함께 갱신한다.
export const CRITERIA_CACHE_MIN_SIMILARITY = 0.90;   // ← 8장의 측정 뒤 확정

/// 차단 판단을 캐시에서 쓰는가. P0는 false(통과 기준만), P1(단계 6)에서 true.
export const CACHE_BLOCKED_DECISIONS = false;

export interface CacheHit {
  cacheId: string; type: 'speed' | 'quality'; provable: boolean;
  minCriteria: string[]; superiorityCriteria: string[] | null;
  aiModel: string; embeddingModel: string; similarity: number;
  matchedBy: 'title' | 'vector';
}

/// 조회 결과를 **Edge에서 한 번 더** 검증한다(SQL이 이미 걸렀지만, 믿지 않는다 -
/// schemas.ts가 Gemini의 responseSchema를 믿지 않는 것과 같은 태도).
/// 유형·두 버전 키·임계값·차단 허용 여부가 어긋나면 ValidationError → 호출부는 미적중으로 간다.
/// **spec 수용 기준의 "유형이 다르면 재사용되지 않는다"·"버전이 다르면 재사용되지 않는다"를
/// 유닛 테스트로 고정할 수 있는 자리가 여기다**(벡터 검색 자체는 자동 테스트가 닿지 않는다).
export function parseCacheHit(row: unknown, expected: {
  type: 'speed' | 'quality'; aiModel: string; embeddingModel: string;
  minSimilarity: number; includeBlocked: boolean;
}): CacheHit

/// 요청과 조회 결과로 "어디서 기준을 얻는가"를 정한다. 흐름의 분기를 값으로 만든 것이다.
export type CriteriaSource = 'cache' | 'generate';
export function decideCriteriaSource(input: { skipCache: boolean; hit: CacheHit | null }): CriteriaSource

/// 그 결정이 하루 10회 한도를 몇 번 쓰는가. 수용 기준의 숫자를 코드로 적은 것이다.
///   적중 0 / 미적중 1 / 다시 만들기 1 / 재검사 1
export function limitCostOf(source: CriteriaSource): 0 | 1
```

### 4.3 `schemas.ts`에 더하는 것

```ts
export interface CriteriaRequest {
  ...                      // 기존 그대로
  /// `기준 다시 만들기`. true면 캐시를 건너뛰고 AI에게 새로 묻는다(한도 1회).
  /// 클라이언트가 이 값으로 **얻는 것이 없다** - 손해 보는 요청이라 우회 수단이 되지 않는다.
  skipCache: boolean;
}
```
`parseCriteriaRequest`: `raw.skip_cache`가 불리언이 아니면 false로 본다. **`action === 'check'`인데 true면 `ValidationError`**(재검사에는 캐시가 없다).

---

## 화면

## 5. 화면·문구

**새 화면이 없다.** 바뀌는 자리는 `create_battle_screen.dart` 하나(+ 공유 문구 상수 둘)이고, `edit_recruit_criteria_screen.dart`·`criteria_views.dart`의 구조는 그대로다.

### 5.1 단계 A·B·C는 그대로, 상태가 늘지 않는다

| 단계 | 지금 | 이 설계에서 |
|---|---|---|
| A 입력 | 유형·제목·기간 + `AI 기준 만들기` + `오늘 남은 기준 생성 N/10회` | **같다.** 다만 한도 소진이 버튼을 막지 않는다(5.6) |
| B 대기 | 전체 로딩 `AI가 판정 기준을 만들고 있어요` / `최대 30초 정도 걸려요` | **같은 자리, 문구만 교체**(5.4). 적중이면 아주 빨리 끝난다(5.5) |
| C 결과(통과) | 제목 + 기준 목록 + `이 기준으로 올리기` / `수정` | **`기준 다시 만들기(1회 차감)` 한 줄 추가**(5.2) |
| C 결과(차단) | 차단 패널 + `제목 고치기` | **`AI에게 다시 확인받기(1회 차감)` 추가**, 차단 사유는 고정 문장일 수 있다(5.3) |
| C 결과(오류) | `StatusMessage.error` + `다시 시도` | **같다.** 단 `기준 다시 만들기`의 실패는 이 화면으로 가지 않는다(5.2) |

**적중/미적중으로 갈리는 화면·단계·버튼이 하나도 없다**(수용 기준 "화면 구성·단계·버튼이 같다", "적중 여부를 알리는 표시·배지·문구가 없다"). 상태 변수도 늘지 않는다 — `_Stage`·`_result`·`_editing`·`_busy`·`_error` 그대로다.

### 5.2 `기준 다시 만들기` — 자리와 실패 처리

- **자리**: 결과 단계의 **읽기 모드**에서 `수정`(OutlinedButton) 아래에 `TextButton`으로 둔다. 문구는 `기준 다시 만들기(1회 차감)`(기존 `다시 검사하기(1회 차감)`의 표기를 따른다).
- **편집 모드에서는 보이지 않는다.** 그 자리는 `원래 기준으로 되돌리기`가 쓰고 있고, 편집 중에 누르면 쓰던 내용이 사라져 확인창이 하나 더 필요해진다. **적중 여부와 무관한 조건**이라 "버튼의 존재로 적중이 누설되지 않는다"는 요구와 충돌하지 않는다(사소한 UI 결정).
- **동작**: `_generate(skipCache: true)`. 기존 `_generate`에 이름 있는 인자 하나를 더한다.
  - 호출 전에 **`_result`를 비우지 않는다**(지금의 `_generate`는 비운다). 실패했을 때 들고 있던 기준이 사라지면 안 된다(수용 기준).
  - `_stage = generating`으로 가서 **첫 생성과 똑같은 로딩**을 보여 준다.
  - **성공**: `_applyResult(result)` — 지금과 같다(편집 상태도 새 결과로 초기화된다).
  - **실패**: `_error`를 세우지 **않고** `_stage = result`로 되돌린 뒤 **스낵바**로 `criteriaErrorMessage(error)`를 띄운다. 들고 있던 `_result`가 그대로 보인다.
    - 한도 소진이면 기존 문구 `오늘 기준 만들기 횟수를 다 썼어요. 내일 다시 시도해주세요.`가 뜬다(수용 기준 "기존 한도 초과 문구로 안내되고, 들고 있던 기준이 사라지지 않는다").
    - 이 처리는 `_submit` 실패(스낵바)의 선례와 같고, `_handleFailure`(전체 오류 화면)를 쓰지 않는다 — 그 함수는 "보여 줄 결과가 없을 때"의 것이다.
- **누르기 전에 비용을 알린다**: 버튼 문구의 `(1회 차감)`이 그 역할을 한다(수용 기준 "누르기 전에 그 사실이 보인다"). 추가 확인창을 넣지 않는다 — `다시 검사하기(1회 차감)`도 확인창 없이 같은 방식으로 1회를 쓴다.
- **한도 소진이어도 버튼을 비활성화하지 않는다**: 비활성화하면 "왜 막혔나"를 또 설명해야 하고, 서버가 같은 판단을 다시 하므로 눌러서 안내받는 쪽이 일관된다(5.6과 같은 태도).
- `_blocksLeaving`(떠나기 가드)는 **그대로다**: `_busy || _result != null`.

### 5.3 차단이 캐시로 내려온 경우 — 탈출구와 사유 문구 (P0 수용 기준)

**탈출구.** 차단 화면(`!result.provable && !_editing`)에 버튼을 하나 더 둔다.

```
┌ (danger 패널) 사진으로 증명할 수 없는 미션이라 대결로 만들 수 없어요
│   사진 한 장으로는 완료를 확인할 수 없는 주제로 보여요.      ← 캐시에서 온 차단
├ [FilledButton]  AI에게 다시 확인받기(1회 차감)               ← 신규. _generate(skipCache: true)
└ [OutlinedButton] 제목 고치기                                 ← 기존
```

- **왜 FilledButton(주 버튼)인가**: 캐시 차단의 **유일한 탈출구**다. `제목 고치기`는 "다른 주제를 쓴다"는 포기에 가깝다.
- **캐시 적중 여부와 무관하게 늘 있다.** AI가 방금 차단한 경우에도 같은 버튼이 같은 자리에 있다 — 그래야 버튼의 존재로 적중이 누설되지 않고(spec P0 탈출구 절), "AI가 방금 한 차단도 한 번은 다시 받아볼 수 있다"는 사용자 스토리도 만족한다.
- **그것으로 차단을 뚫을 수 있다**: `skip_cache = true`라 캐시를 건너뛰고 AI가 다시 판단한다. AI가 `provable = true`를 주면 그대로 기준 화면으로 간다. 즉 **캐시된 차단이 사용자를 영구히 막는 경로가 없다**(오너 결정 1이 요구한 P0 조건).
- 실패 처리는 5.2와 같다(스낵바, 차단 패널 유지).

**차단 사유 문구 — 원래 제목의 사유를 보여 주지 않는 방법.**

| 무엇 | 어디에 | 사용자에게 |
|---|---|---|
| AI가 쓴 사유 원문(예: `독서는 사진으로 증명할 수 없어요`) | `criteria_cache.block_reason`에 남는다(오너 진단용) | **보여 주지 않는다.** `lookup_criteria_cache`가 **반환값에 담지 않으므로** Edge에도 오지 않는다(설계 원칙 8) |
| 제목과 무관한 고정 한 줄 `사진 한 장으로는 완료를 확인할 수 없는 주제로 보여요.` | `issue_cached_criteria_check`가 증서의 `block_reason`에 쓴다 | **이것이 보인다** |
| AI가 방금 쓴 사유 | 미적중 경로의 증서(`finish_criteria_call`) | 지금과 같이 **그대로 보인다** |

- **왜 고정 문장인가**: 유사도로 차단이 전파되면 "독서 30분"의 사유가 "책 정리하기"에 붙어 **틀린 설명**이 된다. 제목을 가리키지 않는 문장은 차단된 모든 주제에 대해 참이다(차단의 정의가 "사진 한 장으로 완료를 확인할 수 없다"이기 때문이다).
- **정규화 일치(제목이 같은) 경우에도 원문을 쓰지 않는다.** 두 경로의 문구가 달라지면 설명해야 할 규칙이 하나 늘고, "원래 제목의 표현이 내 화면에 보인다"는 잔여 위험이 차단 경로에서 **완전히 사라진다**. spec 수용 기준("제목이 완전히 같은 경우에만 보인다")은 "아예 보이지 않는다"로 더 안전하게 만족된다.
- **패널 제목과 약간 겹친다**(`사진으로 증명할 수 없는 미션이라…` + `사진 한 장으로는…`). 받아들인다 — 제목은 **결과**를, 본문은 **이유**를 말하고, DB 제약이 `block_reason`을 비워 두는 것을 허용하지 않는다.
- 이 문장이 `strings.dart`가 아니라 **서버에** 있는 이유는 5.4에 적었다.

### 5.4 문구 — 고치는 것 둘, 더하는 것 셋

**고치는 것**(spec이 지목한 거짓이 되는 문구 둘)

| 상수(`lib/core/strings.dart`) | 지금 | 새 값 | 근거 |
|---|---|---|---|
| `battleCriteriaGenerating` (309행) | `AI가 판정 기준을 만들고 있어요` | **`AI 판정 기준을 준비하고 있어요`** | 적중에서는 "지금 만들고 있다"는 **시제**가 어긋난다. "준비하고 있어요"는 두 경우에 모두 참이다(만든 주체가 AI라는 사실은 어긋나지 않으므로 `AI 판정 기준`을 남긴다) |
| `battleCriteriaLeaveBody` (333행) | `지금 나가면 만든 기준이 사라져요. 사용한 횟수는 돌아오지 않아요.` | **`지금 나가면 받은 기준이 사라져요. 다시 받으려면 처음부터 다시 해야 해요.`** | 적중에서는 "사용한 횟수"가 **없다**(거짓). 첫 문장도 "만든"보다 "받은"이 두 경우에 참이다. 둘째 문장은 "나가면 손해가 있다"는 무게를 유지하면서 한도를 주장하지 않는다 |

- `battleCriteriaGeneratingDetail`(`최대 30초 정도 걸려요`)은 **그대로 둔다.** "최대"라서 적중에서도 거짓이 아니다.
  - **2026-11-11 구현·리뷰에서 뒤집혔다 → `최대 40초 정도 걸려요`로 고쳤다.** 이 검토가 **적중 쪽만** 봤다. **미적중에서는 임베딩 타임아웃이 생성 타임아웃 앞에 쌓인다**(임베딩 5초 + 생성 30초 ≈ 35초) → 30초는 그 경우에 거짓이 된다. 그래서 ① `EMBED_TIMEOUT_MS`를 10초에서 **5초**로 줄이고(임베딩은 본래 빠르고, 늦어서 건너뛴 결과는 "캐시가 없었다"와 같다) ② 문구를 **40초**로 올려 여유를 뒀다. 적재 단계의 임베딩도 조회에서 이미 실패했으면 다시 부르지 않아 최악이 35초로 묶인다.
- `battleCriteriaLeaveBody`는 **모집 기준 수정 화면도 공유한다**(참고 사실 7). 그 화면의 경로(`check`)는 **항상** 1회를 쓰므로 옛 문장도 참이었지만, 새 문장은 두 화면에서 모두 참이다. **상수를 둘로 쪼개지 않는다** — 거짓을 말하지 않으면서 문구가 하나로 남는 쪽을 고른다(수정 화면이 잃는 것은 "횟수를 썼다"는 정보 한 줄이고, 그 화면은 `오늘 남은 기준 생성 N/10회`를 같은 화면에서 보여 준다).

**더하는 것**

| 새 상수 | 값 | 쓰는 자리 |
|---|---|---|
| `battleCriteriaRegenerate` | `기준 다시 만들기(1회 차감)` | 결과(통과) 화면의 TextButton (5.2) |
| `battleCriteriaRecheckBlocked` | `AI에게 다시 확인받기(1회 차감)` | 차단 화면의 FilledButton (5.3) |
| `battleCriteriaCallsExhausted` | `오늘 기준 만들기 횟수를 다 썼어요.` | 입력 화면의 사전 안내 패널 (5.6) |

- 전부 한국어이고 `lib/core/strings.dart`에 모인다(수용 기준).
- **예외 하나 — 차단 사유 고정 문장은 서버에 둔다**(`issue_cached_criteria_check` 안). 근거: `block_reason`은 **이미 "서버가 쓴 사용자 문구"가 들어오는 슬롯**이다(AI가 쓴 한 줄이 그대로 화면에 간다). `strings.dart`는 **앱이 고르는 문구**의 출처이고 이 값은 앱이 고르지 않는다. 같은 슬롯에 성격이 다른 두 출처를 만들지 않는 쪽이 일관된다. 앱 코드는 지금처럼 `result.blockReason`을 **표시만** 한다.

### 5.5 적중/미적중을 사용자가 구분하지 못한다 — 화면에서 지켜지는 방식

| 누설 가능한 신호 | 이 설계에서 |
|---|---|
| 응답 필드 | **없다.** 두 경로의 응답 키가 완전히 같다(7장). `matched_by`·`similarity`·`cache_id`는 **Edge 밖으로 나가지 않는다** |
| 화면 구성·버튼 | 같다(5.1). `기준 다시 만들기`는 두 경우에 모두 있다 |
| 문구 | 두 경우에 모두 참인 문구로 고쳤다(5.4) |
| 차단 사유의 모양 | 캐시 차단은 고정 문장, AI 차단은 구체적 사유 → **모양이 다르다.** 한 사용자가 한 번의 시도에서 보는 것은 하나뿐이고 제목이 다르면 사유도 어차피 다르므로, 비교할 기준이 사용자에게 없다. 받아들인다 |
| `오늘 남은 기준 생성 N/10회` | **줄지 않는다 → 누설된다.** spec이 "숨기지 않는다"로 이미 정했다. 설명을 붙이지 않는다 |
| **응답 속도** | 적중은 즉시 돌아와 로딩 화면이 한두 프레임만 번쩍인다 → **누설된다.** `N/10회`와 같은 급의 누설로 보고 받아들인다 |

- **로딩을 일부러 늦추지 않는다.** spec이 "체감 속도가 빨라지는 것은 그대로 사용자 이익으로 둔다. 즉시 나오는 것을 일부러 늦추지 않는다"로 못 박았다. 최소 표시 시간(예: 300ms)을 넣는 것은 **사용자를 기다리게 해서 적중을 숨기는 일**이라 그 조항과 정면으로 어긋난다.
- 그래서 **로딩 연출을 다루지 않는다**(지금의 `StatusMessage.loading` 그대로). 번쩍임은 "빨라서 생기는 모습"이고 오류가 아니다.

### 5.6 한도 소진 사전 차단을 **푼다** (이게 없으면 수용 기준이 깨진다)

지금 `createBattleBlockMessage`는 `criteriaCallsLeft <= 0`일 때 문구를 돌려주고, 화면은 그걸로 **버튼을 비활성화**한다(참고 사실 6). 캐시 적중은 한도와 무관하므로 그대로 두면 **"한도를 다 쓴 사용자도 캐시 적중이면 기준을 받을 수 있다"가 클라이언트 한 줄 때문에 불가능**해진다.

```dart
// criteria_rules.dart
/// 대결을 만들 수 **없는** 이유. 이제 동의 하나뿐이다.
/// 한도 소진은 더 이상 차단 사유가 아니다 - 캐시 적중은 한도를 쓰지 않으므로 소진 상태에서도
/// 기준이 나올 수 있고, 미적중이면 서버가 CRITERIA_CALL_LIMIT로 거절해 같은 문구가 뜬다.
String? createBattleBlockMessage(MyLimits limits) {
  if (!limits.consented) return AppStrings.aiConsentRequired;
  return null;
}

/// 한도 소진 **안내**(차단이 아니다). 버튼을 막지 않는다.
String? criteriaCallsExhaustedNotice(MyLimits limits) =>
    limits.criteriaCallsLeft <= 0 ? AppStrings.battleCriteriaCallsExhausted : null;
```

- 화면: `canGenerate`는 `blockMessage == null`만 본다(한도를 보지 않는다). danger 패널은 `blockMessage ?? notice`를 그대로 보여 준다.
- **안내 문구가 기존 오류 문구와 다른 이유**: 기존 `battleErrorCriteriaCallLimit`은 `…내일 다시 시도해주세요`인데, 버튼을 누를 수 있게 된 지금 그 조언은 어긋난다. 그래서 사전 안내용으로 `오늘 기준 만들기 횟수를 다 썼어요.`만 쓴다. **"그래도 받을 수 있어요" 같은 설명을 붙이지 않는다** — 캐시의 존재를 알리는 것이 되어 "구분해 말하지 않는다"를 깬다.
- 서버가 같은 판단을 다시 하므로(`begin_criteria_call`) 이 완화가 한도를 느슨하게 만들지 않는다. 미적중이면 429가 그대로 돌아온다.

---

## 데이터 흐름

## 6. 데이터 흐름

```
[입력 A] 제목·유형·기간 + `AI 기준 만들기`
   │  (ConsumerState) _generate(skipCache: false)
   ↓
battleCriteriaRepositoryProvider.generate(title, type, durationMinutes, skipCache: false)
   │  supabase.functions.invoke('battle-criteria', body: {action:'generate', ..., skip_cache:false})
   ↓
Edge: JWT → 입력 검증 → assert_criteria_consent            ← 동의 관문(한도 0)
   ├─ 정규화 일치 조회 ─────────────┐
   ├─ 임베딩 1회 → 벡터 조회 ───────┤ 적중
   │                                 ↓
   │                        issue_cached_criteria_check → criteria_checks 1행 (원장 0행)
   │                                 ↓
   └─ 미적중 → begin_criteria_call(ai_criteria_calls: in_progress)
                 → Gemini 생성 → finish_criteria_call(succeeded + criteria_checks 1행)
                 → put_criteria_cache(적재; 실패는 로그만)
                                     ↓
응답 {check_id, provable, block_reason, min_criteria, superiority_criteria, calls_left}
   │  CriteriaCheckResult.fromMap  (모델 변경 없음)
   ↓
[결과 C] _applyResult → 기준 표시 + ref.invalidate(myLimitsProvider)   ← N/10회 갱신(적중이면 그대로)
   ├─ `이 기준으로 올리기` → battleRepository.createBattle(checkId, durationMinutes)
   │     → RPC create_battle: **증서의 제목·유형·기준을 그대로 복사**(한 줄도 바뀌지 않았다)
   ├─ `수정` → 편집 → `다시 검사하기(1회 차감)` → action:'check'(캐시 없음, 한도 1회)
   └─ `기준 다시 만들기(1회 차감)` → _generate(skipCache: true)
         성공 → _applyResult / 실패 → 스낵바(기준 유지)

[차단 C'] `AI에게 다시 확인받기(1회 차감)` → _generate(skipCache: true)
          `제목 고치기` → _stage = input (지금과 같다)
```

**참가자 쪽 흐름은 한 줄도 바뀌지 않는다**: 확정된 기준은 `battles.min_criteria`/`superiority_criteria`에 복사된 값이고, 참가 전 공개와 `criteria_version` 규칙은 그대로다.

---

## API 계약

## 7. API 계약

### 7.1 Edge Function `battle-criteria`

**요청**(바뀌는 것은 `skip_cache` 하나)

```jsonc
// 기준 만들기 / 기준 다시 만들기
{ "action": "generate", "title": "방 청소하기", "type": "speed",
  "duration_minutes": 4320, "skip_cache": false }      // true = 캐시 건너뛰기(한도 1회)

// 재검사(바뀌지 않음). skip_cache가 true로 오면 BAD_REQUEST.
{ "action": "check", "title": "...", "type": "quality", "duration_minutes": 4320,
  "min_criteria": ["..."], "superiority_criteria": ["..."], "battle_id": null }
```

**응답**(200) — **적중·미적중이 완전히 같다. 새 필드가 없다.**

```jsonc
{ "check_id": "uuid", "provable": true, "block_reason": null,
  "min_criteria": ["..."], "superiority_criteria": null, "calls_left": 7 }
```

**오류 코드** — `errors.ts`의 기존 목록 그대로, **새 코드 없음**: `CONSENT_REQUIRED`(403) / `CRITERIA_CALL_LIMIT`(429) / `AI_FAILED`(502) / `BAD_REQUEST`(400) / `UNAUTHORIZED`(401) / `SERVER_ERROR`(500) / `NOT_PENDING`(409, check 경로).

### 7.2 새 RPC 넷 (전부 service_role 전용, 앱은 부를 수 없다)

| 함수 | 인자 | 반환 | 한도 |
|---|---|---|---|
| `assert_criteria_consent` | `p_user_id uuid` | `void`(미동의면 `hint = CONSENT_REQUIRED`) | 건드리지 않음 |
| `lookup_criteria_cache` | `p_type`, `p_title_norm`, `p_ai_model`, `p_embedding_model`, `p_embedding text = null`, `p_min_similarity real = null`, `p_include_blocked bool = false` | `jsonb`(적중) \| `null`. 키: `cache_id`·`type`·`provable`·`min_criteria`·`superiority_criteria`·`ai_model`·`embedding_model`·`similarity`·`matched_by`. **`title_norm`·`block_reason` 없음** | 건드리지 않음 |
| `put_criteria_cache` | `p_type`, `p_title_norm`, `p_provable`, `p_min_criteria`, `p_superiority_criteria`, `p_block_reason`, `p_ai_model`, `p_embedding_model`, `p_embedding text` | `uuid` | 건드리지 않음 |
| `issue_cached_criteria_check` | `p_user_id`, `p_title`, `p_type`, `p_cache_id`, `p_ai_model`, `p_embedding_model` | `jsonb{check_id, provable, min_criteria, superiority_criteria, block_reason, calls_left}` | **0회**(원장에 쓰지 않음) |

### 7.3 바뀌지 않는 계약 (한 줄도 손대지 않는다)

`begin_criteria_call` · `finish_criteria_call` · `fail_criteria_call` · `create_battle` · `update_battle_criteria` · `join_battle` · `get_my_limits` · `delete_account` · `withdraw_ai_consent` · `criteria_checks`/`ai_criteria_calls` 스키마와 RLS · 증서의 24시간 만료와 1회 소진 · 제출·판정·정산 일체.

### 7.4 테이블 접근

| 테이블 | 접근 경로 |
|---|---|
| `criteria_cache` | **service_role이 부르는 위 세 함수뿐.** 클라이언트 select-eq 경로가 없다(RLS 정책 0개 + 권한 회수) |
| `criteria_checks` | 지금과 같다(본인 행 select 정책 + 서버 함수가 insert) |
| `ai_criteria_calls` | 지금과 같다 |

---

## 8. 임계값 검증 계획 (오너는 표를 보고 승인만 한다 — 오너 결정 4)

### 8.1 누가 언제 무엇으로

- **만드는 사람**: designer가 쌍 목록(8.2)과 표의 모양(8.3)을 확정했다. **developer가 측정 스크립트를 쓰고 돌려 표를 채운다.**
- **언제**: 10장 **단계 4**. Edge 흐름(단계 3)과 병행 가능하지만 **배포 전에 반드시 끝난다**(수용 기준 "임계값을 배포 전에 확인한 기록이 남는다").
- **무엇으로**: `tool/criteria_cache_threshold.ts`(신규, Deno 스크립트)
  - 실행: `deno run --allow-net --allow-env tool/criteria_cache_threshold.ts`(키는 `GEMINI_API_KEY` 환경변수)
  - **운영과 같은 코드 경로를 쓴다**: `supabase/functions/_shared/gemini.ts`의 `embedText`와 `criteria_cache.ts`의 `normalizeTitle`·`l2Normalize`·`cosineSimilarity`를 그대로 import한다. 그래야 측정한 숫자가 실제 조회와 같은 공간의 값이다.
  - 출력: 8.3의 표를 마크다운으로 찍는다(붙여 넣기만 하면 되게).
  - 호출 수: 쌍 26개 × 2 = **52회 임베딩**(제목 중복은 캐시해 더 줄어든다). 임베딩 한도 안이다.
  - **이 스크립트는 DB·캐시를 건드리지 않는다**(읽기도 쓰기도 없다. 임베딩 호출과 산수뿐).
- **어디에 남기나**: 결과 표는 `plan.md`에 그대로 넣고, 확정된 숫자를 `criteria_cache.ts`의 `CRITERIA_CACHE_MIN_SIMILARITY`에 적는다. 커밋 메시지에 "임계값 N = 측정 결과(B 최고 M)" 한 줄.

### 8.2 제목 쌍 목록 (26쌍 — 부정·반대 5쌍 포함)

**그룹 A — 묶여도 되는 쌍**(같은 주제, 표현만 다름). 묶이면 좋지만 **못 묶여도 손해는 AI 호출 1회뿐이다.**

| # | 제목 A | 제목 B |
|---|---|---|
| A1 | 방 청소하기 | 방 치우기 |
| A2 | 아침 운동 | 아침에 운동하기 |
| A3 | 설거지하기 | 설거지 끝내기 |
| A4 | 책상 정리 | 책상 정리하기 |
| A5 | 이불 개기 | 이불 정리하기 |
| A6 | 분리수거 하기 | 재활용 분리배출 하기 |

**그룹 B — 절대 묶이면 안 되는 쌍**(묶이면 판정의 근거가 틀린다). spec이 요구한 네 유형을 모두 넣었다.

| # | 유형 | 제목 A | 제목 B |
|---|---|---|---|
| B1 | **부정·반대** | 방 청소하기 | 방 어지럽히기 |
| B2 | **부정·반대** | 설탕 끊기 | 디저트 먹기 |
| B3 | **부정·반대** | 일찍 자기 | 밤새우기 |
| B4 | **부정·반대** | 금연하기 | 담배 피우기 |
| B5 | **부정·반대** | 라면 안 먹기 | 라면 먹기 |
| B6 | 숫자·시간대 | 아침 산책 30분 | 저녁 산책 1시간 |
| B7 | 숫자·시간대 | 팔굽혀펴기 10개 | 팔굽혀펴기 100개 |
| B8 | 숫자·시간대 | 물 1리터 마시기 | 물 3리터 마시기 |
| B9 | 숫자·시간대 | 아침 7시 기상 | 아침 10시 기상 |
| B10 | 상위어/하위어 | 운동하기 | 턱걸이 10개 |
| B11 | 상위어/하위어 | 청소하기 | 화장실 변기 닦기 |
| B12 | 상위어/하위어 | 요리하기 | 계란말이 만들기 |
| B13 | 증명 가능/불가능 | 독서 30분 | 책 정리하기 |
| B14 | 증명 가능/불가능 | 명상 10분 | 요가 매트 펴기 |
| B15 | 증명 가능/불가능 | 영어 공부하기 | 영어책 펴 놓기 |

**그룹 C — 어느 쪽이어도 되는 쌍**(기준선 읽기용. 판정 대상이 아니라 **숫자의 분포를 보는 자료**다).

| # | 제목 A | 제목 B |
|---|---|---|
| C1 | 쓰레기 버리기 | 분리수거 하기 |
| C2 | 머리 감기 | 샤워하기 |
| C3 | 산책하기 | 조깅하기 |
| C4 | 아침 운동 | 저녁 운동 |
| C5 | 설거지하기 | 주방 청소하기 |

**정규화도 같은 표로 확인한다**(유닛 테스트와 별개로 눈으로 본다): `  아침   운동  ` vs `아침 운동`, `Morning Run` vs `morning run`은 **유사도 1.000**이어야 한다(= 정규화가 같은 문자열을 만들었다는 뜻).

### 8.3 결과표의 모양

```markdown
측정: 2026-__-__ / gemini-embedding-001 / SEMANTIC_SIMILARITY / 768차원 / L2 정규화
임계값 후보: 0.90

| # | 그룹 | 제목 A | 제목 B | 유사도 | 0.90에서 묶이는가 | 기대 | 판정 |
|---|---|---|---|---|---|---|---|
| A1 | A | 방 청소하기 | 방 치우기 | 0.93 | 묶임 | 묶여도 됨 | OK |
| B1 | B 부정 | 방 청소하기 | 방 어지럽히기 | 0.86 | 안 묶임 | **안 묶여야 함** | OK |
| … | | | | | | | |

요약
- 그룹 B 최고 유사도: B_ = 0.___   ← **임계값은 이 값보다 위여야 한다**
- 그룹 A 최저 유사도: A_ = 0.___
- 그룹 C 분포: 0.___ ~ 0.___
- 권장 임계값: ____   (B 최고 + 0.02를 0.01 단위로 올림)
- 그 임계값에서 그룹 A 적중: _/6, 그룹 B 오적중: **0/15이어야 한다**
```

**임계값을 정하는 규칙**(측정 전에 못 박는다 — 숫자를 보고 규칙을 고르지 않는다)

1. **그룹 B에서 오적중이 하나라도 있으면 임계값을 올린다.** 적중률은 목표가 아니다(spec).
2. 임계값 = `그룹 B 최고 유사도 + 0.02`를 0.01 단위로 올림. 여유 0.02는 목록에 없는 패턴 몫이다.
3. 그 결과 **그룹 A가 하나도 안 묶여도 그대로 간다.** 그때 이 기능은 "정규화 일치에서만 적중하는 캐시"가 되고, 그래도 가장 흔한 반복(같은 제목 다시 쓰기)은 잡는다. 임계값을 내려 적중률을 올리는 것은 **선택지가 아니다**(spec 백로그에도 그렇게 적혀 있다).
4. **그룹 B 최고가 0.97 이상이면**(= 반대 뜻을 벡터로 가를 수 없다는 뜻) 구현을 멈추고 오너에게 보고한다 → "## 결정 필요" 1번과 같은 성격의 재판단 지점이다. 이때 선택지는 ① 임계값 0.98+로 두어 사실상 정규화 일치만 쓰기 ② 유사도 경로 자체를 접기다.

---

## 9. 테스트 계획

### 9.1 `deno test supabase/functions/_shared/` (순수 함수 — 자동 테스트가 닿는 자리)

`supabase/functions/_shared/criteria_cache_test.ts`(신규)

| 대상 | 케이스 | 어느 수용 기준인가 |
|---|---|---|
| `normalizeTitle` | 앞뒤 공백 / 중복 공백 / 탭·개행 / 전각 공백(U+3000) / 영문 대소문자 / NFC 결합 한글 / 60자 경계 | "완전 일치 판단이 공백·대소문자를 정규화한 뒤에 이뤄진다", "제목 정규화가 유닛 테스트된다" |
| `aiModelKey`·`embeddingModelKey` | 모델·프롬프트 버전·작업유형·차원이 하나라도 다르면 키가 다르다 | "프롬프트·모델 버전이 다를 때 재사용되지 않는다"의 전제 |
| `l2Normalize` | 길이 1이 된다 / 이미 정규화된 벡터는 그대로 / 0 벡터는 `ValidationError` | 임계값이 길이에 흔들리지 않는다 |
| `toVectorLiteral` | 768개면 `'[...]'` / 길이 불일치·NaN·Infinity는 `ValidationError` | 적재가 insert에서 조용히 깨지지 않는다 |
| `cosineSimilarity` | 같은 벡터 1.0 / 직교 0 / 반대 -1 | 8장 측정의 산수 |
| `parseCacheHit` | **유형이 다른 행 → 거부** / **`ai_model`이 다른 행 → 거부** / **`embedding_model`이 다른 행 → 거부** / 유사도가 임계값보다 작으면 거부 / `provable = false`인데 `includeBlocked = false`면 거부 / 모양이 깨진 행 거부 / 정상 행 통과 | "유형이 다를 때 재사용되지 않는다", "프롬프트·모델 버전이 다를 때 재사용되지 않는다", "임베딩 모델이 바뀌기 전의 벡터와 비교하지 않는다"(키 차원에서) |
| `decideCriteriaSource` + `limitCostOf` | **적중 → `cache`, 0회** / **미적중 → `generate`, 1회** / **`skipCache: true`면 적중 후보가 있어도 `generate`, 1회** | "적중은 한도를 소모하지 않는다", "미적중은 1회만", "다시 만들기는 1회" |
| `parseCriteriaRequest`(기존 파일) | `skip_cache` 기본 false / 불리언 아닌 값 무시 / `action:'check'` + `skip_cache:true` → `ValidationError` | 클라이언트가 조용히 이상한 조합을 보내지 못한다 |
| `CRITERIA_CACHE_MIN_SIMILARITY` | 0 < 값 < 1이고, 8장에서 확정한 값과 같다 | "임계값이 서버가 가진 값 하나다" |

재검사(`check`) 경로의 한도 1회는 **코드가 바뀌지 않는다**는 사실로 지키고, 기존 테스트가 그대로 통과하는 것으로 확인한다.

### 9.2 `flutter test`

| 대상 | 케이스 |
|---|---|
`battle_criteria_repository` | `generate(skipCache: true)`가 본문에 `skip_cache: true`를 담는다 / 기본값이 false다 |
| `criteria_rules` | `createBattleBlockMessage`가 **한도 소진으로는 차단하지 않는다**(동의만) / `criteriaCallsExhaustedNotice`가 0회에서만 문구를 준다 |
| `create_battle_screen`(위젯) | 통과 결과 화면에 `기준 다시 만들기(1회 차감)`가 **있다** / 편집 모드에서는 없다 / 차단 화면에 `AI에게 다시 확인받기(1회 차감)`가 **있다** / **`기준 다시 만들기`가 실패하면 들고 있던 기준이 그대로 보이고 스낵바가 뜬다**(수용 기준) / 한도 0회에서도 `AI 기준 만들기` 버튼이 **눌린다** / 적중을 흉내낸 응답(즉시 반환)과 미적중 응답이 **같은 화면을 만든다** |
| 기존 테스트 | 떠나기 가드 테스트(`test/features/battle/create_battle_test.dart`)의 본문 문구 기대값을 새 문구로 고친다 |

### 9.3 자동 테스트가 **닿지 않는** 경계 (명시)

로컬 Docker가 없어 DB를 돌릴 수단이 없다. 다음은 자동 테스트의 밖이고 11장의 수동 확인으로 본다.

- **벡터 검색 그 자체**: `<=>` 연산자·`order by` 정렬·임계값 비교·`provable` 필터·인덱스 사용.
- **`lookup_criteria_cache`의 두 경로 전환**과 `order by created_at desc`("가장 최근 것").
- **RLS·권한**(정책 0개로 사용자 롤이 0행을 보는지, 네 함수가 authenticated에서 막히는지).
- **`issue_cached_criteria_check`가 원장을 건드리지 않는지**(= `calls_left`가 그대로인지).
- **Edge Function의 호출 순서**(동의 → 임베딩 → 한도). 순수 함수로 뗄 수 없는 자리라 ① `index.ts`에 그 순서의 이유를 주석으로 못 박고 ② 리뷰 체크리스트에 올리고 ③ 11장에서 미동의 계정으로 직접 확인한다. **이 순서가 이 기능에서 가장 조용히 깨질 수 있는 자리다**(깨져도 사용자에게는 아무 증상이 없고, 깨진 결과는 "동의하지 않은 사람의 제목이 Google에 갔다"는 되돌릴 수 없는 사실이다).

---

## 10. 단계 분할 (커밋 단위 제안 — 확정은 plan.md)

| 단계 | 내용 | P0/P1 | 끝났는지 확인하는 방법 |
|---|---|---|---|
| **1** | 마이그레이션 파일 하나(2.2 + 2.5). **적용하지 않고 파일만** | P0 | SQL 리뷰. 원격 적용은 오너 승인 뒤(11장) |
| **2** | `gemini.ts`에 `embedText` + `criteria_cache.ts`(순수 함수 전부) + `criteria_cache_test.ts` + `schemas.ts`의 `skip_cache`. **1.2의 요청 한도 확인 결과를 `plan.md`에 세 줄로 적는다** | P0 | `deno test supabase/functions/_shared/` 통과 |
| **3** | `battle-criteria/index.ts` 흐름 교체(3.2) + 적재. 조회·적재 실패가 기준 생성을 막지 않는 경로 포함 | P0 | 코드 리뷰 + 11장 수동 확인 |
| **4** | `tool/criteria_cache_threshold.ts` + 측정 + 결과표를 `plan.md`에 + `CRITERIA_CACHE_MIN_SIMILARITY` 확정 | P0 | **오너 승인**(표만 보고) |
| **5** | 앱: `skipCache` 전달, `기준 다시 만들기`, 차단 화면 탈출구, 문구 2개 교체·3개 추가, 한도 사전 차단 해제(5.6) | P0 | `flutter analyze` + `flutter test` 통과 |
| **6** | **차단 판단 캐시 켜기**: `CACHE_BLOCKED_DECISIONS = true` + `parseCacheHit`·`decideCriteriaSource`의 차단 케이스 테스트 추가 | **P1** | `deno test` 통과 + 11장 차단 적중 확인 |

- **P0와 P1의 경계는 단계 5와 6 사이다.** 단계 5까지로 멈춰도 기능이 성립한다(통과 기준만 캐시된다). 단계 6은 **상수 하나 + 테스트**다.
- 단계 3에서 **차단 행도 적재는 한다**(조회만 하지 않는다). 그래야 단계 6이 켜지는 순간 쓸 데이터가 있고, 켜지 않으면 아무 동작도 바뀌지 않는다. 적재/조회가 따로 끊기는 것이 P1을 안전하게 뒤에 두는 방법이다.
- `TODO_BACKLOG.md`에 **새 항목을 추가하지 않는다**(spec의 백로그 6건은 메인 세션이 이미 반영 요청했다).

---

## 11. 오너가 손수 해야 할 일

1. **Supabase에서 `vector` 확장 사용 가능 확인.** 마이그레이션의 `create extension if not exists vector with schema extensions;`가 통하는 플랜·프로젝트인지(Supabase는 기본 제공한다). 대시보드에서 미리 켜도 되고 마이그레이션이 켜도 된다.
2. **마이그레이션 원격 적용**(로컬 Docker가 없다). **단계마다 오너 확인**이 필요하다 — 이 파일은 `create`만 하고 기존 객체를 고치지 않으므로 되돌리기가 쉽다(`drop table`·`drop function` 4개).
3. **`supabase functions deploy battle-criteria`** (계정 소유자 실행). 순서는 마이그레이션 → 배포.
4. **임베딩 모델 시크릿**은 **설정하지 않아도 된다**(코드 기본값 `gemini-embedding-001`). 모델을 바꿀 때만 `supabase secrets set GEMINI_EMBEDDING_MODEL=...`.
5. **임계값 결과표 승인**(8.3). 숫자 하나만 보면 된다 — 그룹 B 오적중이 0인가.
6. **개인정보처리방침 한 줄 확인·수정**(아래 "결정 필요" 3번). `C:\workspaces\todododo-legal\privacy.html`은 **아직 게시되지 않았으므로**(DEPLOY.md 5번) 지금이 가장 싸게 고칠 수 있는 시점이다.
7. **수동 확인 절차**(`docs/manual-test-plan.md`에 developer가 추가한다):
   1. 같은 제목·같은 유형으로 두 번 만들기 → 두 번째에 **`N/10회`가 줄지 않는다**(정규화 일치 적중).
   2. 같은 제목을 **유형만 바꿔** 만들기 → **적중하지 않는다**(횟수가 줄고, 품질전에 우열 기준이 있다).
   3. 비슷한 제목(그룹 A 쌍)으로 만들기 → 적중 여부를 로그(`matched_by`·`similarity`)로 확인.
   4. **부정·반대 쌍**(B1)으로 만들기 → **적중하지 않는다.**
   5. `기준 다시 만들기` → 횟수가 1 줄고 기준이 바뀔 수 있다. 그 뒤 같은 제목으로 다시 만들기 → **마지막에 만든 기준**이 온다.
   6. 하루 10회를 다 쓴 상태에서 ① 이미 만든 적 있는 제목 → **기준이 나온다** ② 처음 쓰는 제목 → 한도 문구 ③ `기준 다시 만들기` → 한도 문구가 뜨고 **들고 있던 기준이 그대로 있다.**
   7. 차단되는 제목(예: `독서 30분`)으로 만들기 → 차단 화면에 `AI에게 다시 확인받기`가 있다. (단계 6 뒤) 비슷한 차단 제목으로 다시 → **차단 사유가 고정 문장**이고 다시 확인받기로 뚫린다.
   8. **미동의 계정**으로 `AI 기준 만들기` → 동의 안내. **Edge 로그에 임베딩 호출 기록이 없다**(가장 중요한 확인).
   9. 동의 철회 → 진행 중 대결 포기·모집 취소가 지금과 같다.
   10. 캐시가 비어 있는 상태(배포 직후)에서 기준 생성이 지금과 똑같다.

---

## 12. 결정 필요

1. **생성 모델과 임베딩 모델의 요청 한도가 같은 풀이라면 이 기능을 계속할 것인가**(1.2).
   설계 단계에서 **확인하지 못했다**(네트워크 접근 없음). 내가 아는 바로는 Gemini API 무료 등급 한도는 **모델별**이라 별도 풀이고, 그 전제로 설계했다. developer가 단계 2에서 `ai.google.dev/gemini-api/docs/rate-limits`로 확인한다.
   - (a) **별도 풀이다** → 그대로 진행. 생성 모델의 한도 압박이 적중률만큼 줄고, 임베딩은 훨씬 넉넉한 자기 풀을 쓴다.
   - (b) **같은 풀이다**(또는 프로젝트 단위 공유 한도가 둘을 묶는다) → **적중률 50% 전까지 요청 수가 늘기만 한다**(spec 트레이드오프 1번). 그때 오너가 ① 그래도 진행(체감 속도와 하루 10회 이익은 남는다) ② 정규화 일치 경로만 남기고 벡터 경로를 접는다(임베딩 호출이 0이 되고 적중률은 떨어진다) ③ 배포 후로 미룬다 중에서 고른다.
   **②가 싸게 가능한 구조로 설계했다** — 벡터 경로를 접는 것은 `lookup_criteria_cache` 호출에서 임베딩 인자를 빼는 일이다(2.4 경로 ①만 쓴다).

2. **대결 기간(`duration_minutes`)을 캐시 키에 넣지 않는 것을 승인하는가**(2.4).
   spec의 캐시 키 조항에는 기간이 없는데, **기간은 생성 프롬프트의 입력이다**(참고 사실 5). 즉 7일 대결용으로 만들어진 기준이 1분 대결에 그대로 올 수 있다.
   - (a) **넣지 않는다**(이 설계의 선택) — 프롬프트가 "시간의 경과는 기준으로 쓰지 않는다"를 강제하므로 기간이 기준 문장을 바꾸는 폭이 작고, 어긋나면 생성자가 그 자리에서 고친다. 기간을 키에 넣으면 1~10080의 자유 정수라 **적중률이 사실상 0**이 되어 기능의 동기가 사라진다.
   - (b) 기간을 키에 넣는다 — 안전하지만 캐시가 거의 적중하지 않는다.
   - (c) 기간을 구간으로 묶어 키에 넣는다(예: 1시간 미만 / 1일 미만 / 그 이상) — spec에 없는 구조를 새로 들이는 것이고, 구간 경계가 또 하나의 설명해야 할 규칙이 된다.

3. **개인정보처리방침의 "탈퇴 시 처리" 서술을 한 줄 손볼 것인가**(2.3, spec 수용 기준 "방침 서술과 어긋나지 않는 것을 확인한다").
   확인 결과: `privacy.html`의 표에 **캐시에 해당하는 행이 없다.** 가장 가까운 행은 `대결 기록(대결 제목, 유형, 판정 기준, 승패와 판정 사유) → 탈퇴자를 식별할 수 없는 상태로 보존`이고, 캐시는 그 서술과 **성질이 같다**(식별 정보 없음, 보존). 다만 캐시에는 **대결이 된 적 없는 제목**(차단된 제목, 올리지 않은 제목)도 남으므로 "대결 기록"으로 다 덮이지 않는다.
   - (a) **방침 표에 한 줄 더한다**(권고) — 예: `판정 기준(AI 생성) | 다음 대결에 재사용하기 위해 이용자 정보와 분리해 보관 | 식별 정보 없이 보존`. **문서가 아직 게시되지 않았으므로 지금이 가장 싸다**(DEPLOY.md 5번). 고치는 파일은 `C:\workspaces\todododo-legal\privacy.html`로 **이 저장소 밖**이라 오너가 직접 한다.
   - (b) 손대지 않는다 — "대결 기록"이 포괄한다고 본다. 대결이 되지 않은 제목까지 덮는다고 읽기에는 무리가 있다.
   - (c) 캐시도 탈퇴 때 지운다 — **오너 결정 3을 뒤집는 것**이고, 1인~소수 사용자 단계에서 탈퇴 한 번에 캐시가 거의 비워져 기능이 성립하지 않는다.

4. **캐시 행에 정규화된 제목(`title_norm`)을 남기는 것을 승인하는가**(2.2).
   spec은 "캐시 행에 **사용자 식별 정보**를 담지 않는다"고 했고 제목은 식별 정보가 아니다(누가 썼는지 알 수 없고, 모집 목록에서 공개되는 종류의 문장이다). 그래도 **사용자가 쓴 문자열이 탈퇴 뒤에도 남는** 유일한 칸이라 오너 확인을 받는다.
   - (a) **남긴다**(이 설계의 선택) — ① 정규화 일치 빠른 경로가 성립해 가장 흔한 반복에서 **임베딩 호출마저 0**이 된다 ② "가장 최근 것을 준다" 규칙이 이 칸으로 구현된다 ③ **오너가 오적중을 진단할 수 있는 유일한 자료다**(이 칸이 없으면 캐시는 뜻을 읽을 수 없는 벡터 더미가 되고, 이 기능의 가장 큰 위험인 오적중을 사후에 조사할 방법이 사라진다). 대가는 3번의 방침 한 줄이다.
   - (b) 남기지 않는다(벡터만 저장) — 캐시에 사용자가 쓴 문장이 **한 칸도** 없어 방침 손질이 필요 없다. 대가: 정규화 일치 경로가 사라져 **같은 제목을 다시 써도 임베딩 1회를 쓴다**, 그리고 적중을 진단할 수단이 없어진다. 설계 변경은 작다(컬럼 1개와 조회 경로 ① 삭제).

5. **오너가 직접 해야 하는 두 가지의 승인**: ① 마이그레이션 원격 적용 시점(단계 1 직후 vs 단계 5까지 끝낸 뒤 한 번에) ② 임계값 결과표(8.3)의 숫자. 둘 다 11장에 절차를 적어 두었다.
