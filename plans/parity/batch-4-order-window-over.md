# Batch 4 parity note: expr/order_window.jl, expr/over.jl

Upstream sources fetched to `/home/simba/workspace/pypolars-ref/`: `test_over.py`,
`test_window.py`, `test_shift.py`, `test_diff.py`, `test_rank.py`, `test_cum_count.py`.

## Fixtures ported (all live-verified before asserting, Step 7)

| function | upstream test | fixture | category | outcome |
|---|---|---|---|---|
| `cum_count` | `test_cum_count_single_arg` | `[5,5,None]`, forward and `reverse=true` | null propagation (nulls don't increment the running count) | matches exactly (`[1,2,2]` / `[2,1,0]`); added |
| `rank` | `test_rank_nulls` | empty, `[None]`, `[None,None]` | empty input / null propagation (nulls stay null, aren't ranked) | matches exactly; added |

## Genuine gap found (confirmed live, flagged not fixed — needs Rust/dependency-level work, out of scope)

**`over(expr)` / `over(expr; order_by=...)` with an empty `partition_by` list fails at query
*execution* time**, even though building the `Expr` itself succeeds and even though
`c-polars/src/expr.rs`'s own comment on `polars_expr_over` explicitly documents the opposite intent:

> "An empty partition list is a real, meaningful window spec (the whole frame as one group) ...
> this used to succeed"

Live-verified all four combinations:
- zero `partition_by`, no `order_by`, only *constructing* the `Expr` (existing
  `test/expr/over.jl:40-41`'s `r_bare = over(col("x")); @test r_bare isa Polars.Expr`) → succeeds.
- zero `partition_by`, no `order_by`, **actually running it** via `collect(with_columns(...))` →
  `PolarsError: at least one key is required in a group_by operation`.
- zero `partition_by`, **with** `order_by` set, run via `collect(...)` → same error.
- **one or more** `partition_by` columns plus `order_by` → works correctly (verified against a
  3-row 2-group fixture, `[2,1,2]`).

So the break is specifically: *zero partition columns, at actual execution time*, regardless of
`order_by`. The existing test only ever exercised the "construct the `Expr`, don't run it" half —
it never actually caught that running it fails, which is exactly the gap this sweep exists to find.
This is not a marshalling bug on the Julia/C-ABI side (an empty `partition_by` slice correctly
produces `Some(vec![])` per the Rust comment's own stated design) — the failure surfaces from
polars-core's actual group-by execution needing at least one key, i.e. this vendored polars
version's `over_with_options` does not actually support the zero-key case the comment assumed,
whether that's a version regression or the comment's assumption was never fully verified
end-to-end. Fixing this needs Rust-side investigation (possibly a different `over_with_options`
call shape, or accepting this is currently unsupported upstream) — out of scope for a test-parity
sweep. Recorded in `LEDGER.md`; added a `@test_broken` regression marker in `test/expr/over.jl` so
this stays visible rather than silently regressing further, instead of leaving it undocumented.

## Not ported (Step 4 exclusions)

- `test_diff_duration_dtype` — Duration-dtype `diff`; belongs to Batch 8 (temporal).
- `test_diff_scalarity` — asserts `ShapeError` for a non-scalar `n` argument (a py-polars-only
  overload accepting an `Expr`/column for `n` rather than a plain integer) and the aggregated-mean
  scalar case; Polars.jl's `diff(a, b)` always takes `b` as a genuine second `Expr` argument with
  no analogous "must be scalar" restriction to test, since our binary `diff` FFI call doesn't
  distinguish. Not a gap, just a different API shape.
- `test_shift_fill_value`, `test_shift_expr`, `test_shift_fill_value_group_logicals`,
  `test_shift_fill_value_nonscalar` — py-polars' `shift(n, fill_value=...)` has a 3-argument form;
  Polars.jl's `shift` only wraps the 2-argument `Expr::shift(n)` FFI (no `fill_value`) — same
  "genuine gap, needs new Rust FFI" bucket as Batch 1's `clip_min`/`clip_max` finding, not fixed
  here. Noted in `LEDGER.md`, not implemented.
- `test_shift_n_null`/`test_shift_n_nonscalar` — `DataFrame.shift(None)` (frame-level shift with a
  `None` count) and non-scalar `n`; frame-level `shift` belongs to a different batch/file
  entirely if this package has one (it doesn't — only the `Expr`-level binary `shift` exists).
- `test_shift_categorical`, `test_shift_object` — Categorical/Object dtype; Categorical belongs to
  a different sweep area, Object dtype isn't supported here at all.
- `test_rank_random_expr`/`test_rank_random_series` (`method="random"`, seeded) — randomized output,
  not a fixed adversarial fixture; `test_rank_string_null_11252` — belongs with Batch 7 (strings).
- `test_window.py`'s 1061 lines are overwhelmingly dtype-preservation checks, streaming-engine
  parity checks (`test_window_cached_keys_sorted_update_4183`, `test_cached_windows_sync_8803`), or
  regression tests for internal caching/optimization bugs (`test_window_function_cache`,
  `test_windows_not_cached`) with no portable adversarial-fixture content; `test_over_args` is
  already covered by the existing multi-column-partition test almost verbatim.

## Resolved non-issues (verified before assuming a bug)

- None beyond the `over()` finding above, which *is* a real, confirmed issue, not a false alarm.
