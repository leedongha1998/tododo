---
name: feedback-edge-gate-vs-absorbed-calls
description: Edge Function에 새 RPC가 여러 개 붙는 변경은 "try/catch로 흡수되는 호출"과 "관문 호출"을 호출 지점마다 갈라 읽고, 배포 순서·타임아웃 단정을 그 구분으로 검산한다
metadata:
  type: feedback
---

Edge Function에 **새 RPC 여러 개**가 한꺼번에 붙는 변경(예: 캐시 조회/적재/발급)을 리뷰할 때,
"실패하면 어차피 기존 경로로 떨어진다"는 문서의 단정을 **호출 지점마다 따로** 검산한다.
try/catch 안에 있는 호출은 실패가 no-op로 흡수되지만, **catch 밖에 있는 한 호출이 관문이면**
그 함수가 없는 순간 기능 전체가 500으로 죽는다.

**검산 절차**
1. 새 RPC 호출 지점을 전부 세고, 각각이 try/catch 안인지 밖인지 적는다.
2. 밖에 있는 호출의 에러 분기를 따라간다 — 에러에 `hint`가 없으면 보통 `SERVER_ERROR`로 끝나
   사용자 경로가 **전면 차단**된다(함수 미존재·PostgREST 스키마 캐시 지연도 같은 증상).
3. 그 결과를 마이그레이션 머리 주석·plan의 "오너가 할 일"에 적힌 **배포 순서 단정**과 대조한다.
   "순서를 바꿔도 미적중과 결과가 같다"는 문장은 흡수되는 호출만 보고 쓴 것일 때가 많다.
4. 새 외부 호출의 **타임아웃이 기존 타임아웃 앞에 쌓이는지** 본다. 앞에 10초가 붙으면
   화면 문구(`최대 30초 정도 걸려요`)가 최악의 경우에 거짓이 된다.

**Why:** 2026-11-11 `criteria-cache` 리뷰에서 마이그레이션 주석과 plan이 "Edge를 먼저 배포해도
조회만 실패하고 기준 생성은 계속 동작한다"고 단정했는데, 새 RPC 넷 중 `assert_criteria_consent`
하나만 catch 밖의 동의 관문이어서 그 경우 `generate`가 전부 500이 되는 판이었다(나머지 셋은
실제로 흡수된다). 로컬 DB가 없어 돌려 볼 수 없는 저장소라 이런 비대칭은 호출 지점 세기로만 잡힌다.

**How to apply:** `supabase/functions/*/index.ts`에 RPC 호출이 추가되는 모든 변경에 적용한다.
관련: [[feedback_sql_trigger_check_verification]](경계값 대입),
[[feedback_deferred_migration_write_path]](적용을 미룬 마이그레이션의 읽기/쓰기 영향).
