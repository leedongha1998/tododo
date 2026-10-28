---
name: sql-smoke-test-now-frozen
description: Postgres now() is frozen for the whole transaction inside a do $$ ... $$ smoke test block, not per-statement — breaks naive "sleep then compare timestamps" test designs.
metadata:
  type: feedback
---

In this repo's `supabase/tests/*.sql` smoke tests, each test runs as one `do $$ ... $$` block inside a single transaction (ends with `raise exception` to roll back). Within that single transaction, `now()` (= `transaction_timestamp()`) returns the **same value every time it's called**, no matter how much real time passes or how many `pg_sleep()` calls happen in between. Only `clock_timestamp()` would actually advance.

**Why this matters:** any DB function that stamps a row with `now()` (e.g. `accept_submission` setting `submitted_at = now()`) will produce **identical timestamps** for every call made within one smoke test, even across different users/rows at different "logical steps" in the test. A test that does `submit A -> pg_sleep(0.05) -> submit B -> expect A.submitted_at < B.submitted_at` will fail — not because the underlying feature is broken, but because the test's premise (timestamps differ) is false inside a single transaction.

**How to apply:** when a smoke test needs to assert ordering/tie-break behavior that depends on real elapsed time (e.g. mutual-judge's "earlier submission wins, tie-break by row id/seq"), don't rely on wall-clock gaps via `pg_sleep`. Either:
- Assert the **tie-break path itself** (e.g. equal timestamps -> lower `id`/seq wins) since that's what will actually execute, or
- Use literal `timestamptz` constants (as `resolve_battle_smoke.sql`/`mutual_judge_rules.sql` already do for pure-function tests) instead of `now()`-derived values when the test needs two genuinely different instants, or
- Assert row-identity (same `id` returned by two calls) instead of timestamp inequality when testing "does this overwrite the same row" (e.g. speed submission replace/overwrite semantics) — this sidesteps the frozen-clock issue entirely and is a stronger assertion anyway.

Also related: a PL/pgSQL function with **exactly one `OUT` parameter** returns a plain scalar (call it directly in a `SELECT`/expression), not a composite row — don't put it in a `FROM` clause as a table function (`FROM foo() AS o` + `o.col`) the way you would for a function with multiple `OUT` params (e.g. `mutual_speed_outcome`). Mixing the two calling conventions up in the same rule-test file is an easy mistake (`judging_gate`/`min_verdict_effect` are single-OUT; `mutual_speed_outcome`/`mutual_quality_outcome` are multi-OUT).

See [[workflow_edit_hooks]] for the related "ignore mid-edit analyzer noise, judge once at the end" habit — the same "don't react to intermediate signals" discipline applies here: don't trust a smoke test's apparent pass/fail without checking whether its premise (e.g. "timestamps differ") actually holds under the transaction model.
