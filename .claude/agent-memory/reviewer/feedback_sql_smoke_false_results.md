---
name: sql-smoke-false-results
description: SQL 표/스모크 테스트의 기대값 문자열이 구현과 무관하게 틀리거나 공허해지는 두 패턴(concat_ws 불리언, stable 함수의 미참조 서브질의) — 원격 읽기 전용 probe로 확인한다
metadata:
  type: feedback
---

SQL 스모크(`supabase/tests/*.sql`)를 리뷰할 때 **단언 자체가 구현을 보는지** 따로 검산한다. 실행 못 하는 마이그레이션의
유일한 적용 후 검증이라, 단언이 틀리면 운영자가 실패에 익숙해지거나 거짓 안심을 얻는다.

1. `concat_ws('/', bool, bool)`은 `boolout`을 써서 `t/f`를 만든다(`true::text`는 `true`). 기대값을 `'false/false'`로 적은
   권한 표 행은 구현이 맞아도 실패한다. **고칠 때 `concat_ws(...)` 결과가 아니라 인자마다** `::text`를 붙인다 —
   결과에만 붙이면 마지막 인자가 그대로 `f`로 남아(`false/false/f`) 절반만 고쳐진다(2026-11-25에 실제로 그랬다).
2. `(select 'ok' from (select f()) x)`에서 `f`가 **stable/immutable**이면 플래너가 서브질의를 끌어올리고 미참조 열을 버려
   `f`를 부르지 않는다(volatile만 끌어올림을 막는다). "예외 없이 끝나면 ok" 단언이 항상 통과한다. 최상위 `select f()`나
   plpgsql `perform`은 실제로 부른다.

**Why:** 2026-11-24 nickname 리뷰에서 `nickname_rules.sql`의 권한 6행(거짓 실패)과 `assert_nickname_pool_valid()` 행 2개
(공허한 통과)가 이 두 패턴이었다. 둘 다 원격 SELECT probe로 재현했다 — `concat_ws('/', true, false)`, 없는 설정을 읽는
stable `current_setting('nosuch.x')`를 서브질의에 넣어 `ok`가 나오는지.

**How to apply:** 스모크·표 테스트에서 불리언을 문자열로 잇는 곳, "부르기만 하는" 검증 함수 호출을 grep하고, 확신이 없으면
`supabase db query --linked -f`로 함수 없이 같은 모양의 읽기 전용 probe를 돌린다(쓰기·DDL 금지). 관련: [[feedback_sql_trigger_check_verification]]
