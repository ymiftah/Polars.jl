# Batch 5 parity note: expr/sort_top_k.jl, expr/is_unique_dup.jl, operations/sort.jl, operations/unique.jl

Upstream sources fetched to `/home/simba/workspace/pypolars-ref/`: `test_sort.py`, `test_top_k.py`,
`test_is_first_last_distinct.py`, `test_unique.py`, `test_n_unique.py`, `test_is_unique.py`,
`test_value_counts.py`.

## Fixtures ported (all live-verified before asserting, Step 7)

| function | upstream test | fixture | category | outcome |
|---|---|---|---|---|
| `value_counts` | `test_value_counts_duplicate_name` | counting a column literally named `"count"` without a custom `name` | wrong-input raises cleanly (Step 5) | matches (`PolarsError` naming the exact issue); added |
| `value_counts` | `test_value_counts_expr` | `sort=true` tie-break order (`b`/`d` both count=2) | happy path, but pins upstream's exact tie-break order as a regression floor | matches (`c,b,d,a`); added |
| `is_unique`/`is_duplicated` | `test_is_unique_null`/`test_is_duplicated_null` | empty / one-null / three-null columns | empty input / null propagation | matches exactly across all 3; added |
| `n_unique` | `test_n_unique_null` | empty / one-null / two-null columns | empty input / null propagation (a null counts as one distinct value) | matches (`0`/`1`/`1`); added |
| `top_k` | `test_top_k_empty` | empty `Float64` column | empty input | matches (empty result, not an error); added |
| `top_k` | `test_top_k_nulls` (adapted from the hypothesis property to a concrete fixture) | `[3,1,None,4,None,2]`, `top_k(valid_count)` vs `top_k(len)` | null propagation — `top_k(n)` for `n` = the non-null count excludes all nulls; `top_k(len)` includes them, sorted last | matches (`[3,1,4,2]` then `[3,1,4,2,missing,missing]`); added |
| `arg_sort` | `test_arg_sort_nulls` | `[1.0,2.0,3.0,None,None]`, both `nulls_last` values | null propagation | matches exactly (`[0,1,2,3,4]` / `[3,4,0,1,2]`); added |
| `Base.sort` (DataFrame) | `test_arg_sort_nulls` (the frame-level half) | same fixture, both `nulls_last` values | null propagation | matches exactly; added |

## Genuine gaps found (flagged, not fixed — new Rust FFI needed, out of scope)

1. **`is_first_distinct`/`is_last_distinct` don't exist at all** — no Rust FFI symbol, no Julia
   binding. `test_is_first_last_distinct.py` devotes its entire ~160 lines to these (numeric,
   string, boolean, struct, and an all-null-input case for each). Not implemented here.
2. **`bottom_k` doesn't exist** — only `top_k` is wrapped. `test_top_k.py` tests both as a
   matched pair (`test_bottom_k_nulls`, `test_bottom_k_by`). A `bottom_k` FFI wrapper would mirror
   `polars_expr_top_k`'s existing shape closely, but is still new Rust source, out of scope here.

Both recorded in `LEDGER.md`.

## Not ported (Step 4 exclusions)

- `test_series_sort_idempotent`, `test_df_sort_idempotent`, `test_top_k_nulls`/`test_bottom_k_nulls`
  themselves (both `@given`/hypothesis) — don't port mechanically; adapted to a concrete fixture
  instead where the underlying property was worth capturing (see `top_k` row above).
- `test_is_first_distinct_bool_bit_chunk_index_calc` — an internal SIMD/bit-chunking fast-path
  regression test tied to py-polars' own implementation internals; not applicable even once
  `is_first_distinct` exists.
- `test_n_unique_categorical`, `test_n_unique_list_of_struct_20341`, `test_n_unique_array`,
  `test_is_unique_struct/_list/_array` — Categorical/List/Array/Struct dtype specifics; belong to
  Batch 9 (list/struct namespaces) or are otherwise out of this batch's scope.
- `test_value_counts_logical_type` — Categorical dtype-preservation; not applicable without a
  dtype-introspection API (same reasoning as prior batches).
- `test_expr_arg_sort_nulls_last`/`test_arg_sort_by_nulls` — multi-column `arg_sort_by`/tie-break
  parametrization; `pl.arg_sort_by(...)` is a module-level function with no direct Polars.jl
  counterpart (only the `Expr`-level `sort_by`, a different shape — sorts a *value* expression by
  other keys, doesn't return bare indices). Not a gap worth flagging on its own; the single-key
  `arg_sort` case above already covers the null-handling behavior that mattered.
- `test_top_k.py`'s remaining ~600 lines (`test_top_k_by`, `test_sorted_top_k_*`,
  `test_top_k_list_dtype`, `test_top_k_categorical_lexical_28344`, streaming/dyn-predicate-pushdown
  cases) — internal-optimization regressions or dtype-specific parametrization, not adversarial
  value fixtures of the kind this sweep targets.
- `test_unique.py` (423 lines) — skimmed; dominated by `keep` strategy variants (`first`/`last`/
  `any`/`none`) at the DataFrame level (`operations/unique.jl` already covers `keep` strategies per
  `plans/test_porting.md`'s Phase 1) and dtype-matrix parametrization. Nothing new pulled from it.

## Resolved non-issues (verified before assuming a bug)

- Initially mis-verified `arg_sort(nulls_last=...)` against the *wrong* upstream fixture (confused
  `test_arg_sort_nulls`'s single-column `[1,2,3,None,None]` fixture with a different, multi-column
  test's expected output for a different input). Caught by actually reading which fixture produced
  which expected list before writing the test, not just pattern-matching a plausible-looking
  expected array — re-verified against the correct fixture, which matched cleanly.
