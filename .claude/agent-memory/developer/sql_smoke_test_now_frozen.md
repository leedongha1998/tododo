---
name: sql-smoke-test-now-frozen
description: Postgres smoke-test premises that quietly fail — now() is frozen for the whole do $$ block, and a begin/exception block rolls back whatever the refused call did before raising.
metadata:
  type: feedback
---

In this repo's `supabase/tests/*.sql` smoke tests, each test runs as one `do $$ ... $$` block inside a single transaction (ends with `raise exception` to roll back). Within that single transaction, `now()` (= `transaction_timestamp()`) returns the **same value every time it's called**, no matter how much real time passes or how many `pg_sleep()` calls happen in between. Only `clock_timestamp()` would actually advance.

**Why this matters:** any DB function that stamps a row with `now()` (e.g. `accept_submission` setting `submitted_at = now()`) will produce **identical timestamps** for every call made within one smoke test, even across different users/rows at different "logical steps" in the test. A test that does `submit A -> pg_sleep(0.05) -> submit B -> expect A.submitted_at < B.submitted_at` will fail — not because the underlying feature is broken, but because the test's premise (timestamps differ) is false inside a single transaction.

**How to apply:** when a smoke test needs to assert ordering/tie-break behavior that depends on real elapsed time (e.g. mutual-judge's "earlier submission wins, tie-break by row id/seq"), don't rely on wall-clock gaps via `pg_sleep`. Either:
- Assert the **tie-break path itself** (e.g. equal timestamps -> lower `id`/seq wins) since that's what will actually execute, or
- Use literal `timestamptz` constants (as `resolve_battle_smoke.sql`/`mutual_judge_rules.sql` already do for pure-function tests) instead of `now()`-derived values when the test needs two genuinely different instants, or
- Assert row-identity (same `id` returned by two calls) instead of timestamp inequality when testing "does this overwrite the same row" (e.g. speed submission replace/overwrite semantics) — this sidesteps the frozen-clock issue entirely and is a stronger assertion anyway.

**두 번째 함정 — 거부를 확인하려고 감싼 `begin … exception` 블록은 서브트랜잭션이라, 그 호출이 거부되기 전에 한 일까지 함께 되돌린다.** 이 저장소의 스모크는 힌트를 받으려고 모든 거부를 `begin … exception when others then get stacked diagnostics …; end;`로 감싸는데, 거부 전에 **부수 효과를 내는** 함수(예: `forfeit_battle`의 봇전 분기가 거부 전에 `settle_bot_battle`로 먼저 정산한다)를 감싸면 그 부수 효과가 예외와 함께 사라진다. 그래서 "거부됐다"와 "그 부수 효과가 남았다"를 **한 블록에서 동시에 단정할 수 없다** — 블록을 빠져나온 뒤 그 부수 효과를 **멱등 함수로 다시 만들고** 모양을 읽어야 한다(2026-11-22 `bot_battle_flow_smoke.sql`의 W1 회귀에서 확인). 반대로 이 성질이 유용한 자리도 있다: 거부 네 건을 연달아 던져도 상태가 더럽혀지지 않으므로 같은 대결 행 하나로 증거 규칙 가드를 전부 두드릴 수 있다.

Also related: a PL/pgSQL function with **exactly one `OUT` parameter** returns a plain scalar (call it directly in a `SELECT`/expression), not a composite row — don't put it in a `FROM` clause as a table function (`FROM foo() AS o` + `o.col`) the way you would for a function with multiple `OUT` params (e.g. `mutual_speed_outcome`). Mixing the two calling conventions up in the same rule-test file is an easy mistake (`judging_gate`/`min_verdict_effect` are single-OUT; `mutual_speed_outcome`/`mutual_quality_outcome` are multi-OUT).

See [[workflow_edit_hooks]] for the related "ignore mid-edit analyzer noise, judge once at the end" habit — the same "don't react to intermediate signals" discipline applies here: don't trust a smoke test's apparent pass/fail without checking whether its premise (e.g. "timestamps differ") actually holds under the transaction model.
