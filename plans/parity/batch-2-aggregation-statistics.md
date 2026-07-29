# Batch 2 parity note: expr/aggregation.jl, expr/statistics.jl

Upstream sources fetched to `/home/simba/workspace/pypolars-ref/`: `test_aggregations.py`,
`test_vertical.py`, `test_statistics.py`.

## Fixtures ported (all live-verified before asserting, Step 7)

| function | upstream test | fixture | category | outcome |
|---|---|---|---|---|
| `Polars.count` | `test_count` | mix of all-null/one-null/no-null columns | null propagation (excludes nulls, unlike `size`) | matches (`[0,2,2,3]`, `UInt32`); added |
| `mean`/`Polars.std`/`Polars.var` | `test_boolean_aggs` | `Bool` column `[true,false,missing,true]` | happy path on a dtype we hadn't exercised for aggregation (Boolean, not just Float64) | matches exactly (`0.6667`, `0.5774`, `0.3333`); added |
| `Polars.sum` | `test_sum_empty_and_null_set` | empty `Float32` column, single-`missing` column | empty input / null propagation — sum's identity is `0`, **not** `missing` (opposite of `median`'s empty/all-null convention, already tested) | matches (`0.0` both cases); added |
| `sum_horizontal` | `test_horizontal_sum_null_to_identity` | `a=[1,5], b=[10,missing]` | null propagation — a `missing` operand is treated as the identity (ignored), **not** propagated, unlike the plain `+` operator | matches (`[11,5]`); added |
| `Polars.min`/`Polars.max`/`mean` grouped | `test_nan_inf_aggregation` | 6 groups: both-NaN, NaN+real, NaN+null, both-null, both-Inf, Inf+null | NaN/domain edge — **min/max treat `NaN` as non-extremal when a real value is present** (`[NaN,5]`→min=max=`5`), but `mean` is poisoned by any `NaN` (→`NaN`); both-null group returns `missing` for all three; `Inf` behaves as an ordinary value throughout | matches exactly across all 6 groups; added |
| `Polars.std`/`Polars.var`/`Polars.max`/`Polars.min`/`median`/`Polars.quantile` | `test_std`/`test_var`/`test_max`/`test_min`/`test_median`/`test_quantile` | `fruits_cars_df()`'s `A` column — **reused our own existing shared fixture** rather than inventing a new one, since it happens to be exactly upstream's `fruits_cars` fixture | happy path, but pins upstream's exact numeric answers (`std≈1.5811388300841898`, quantile at 5 different methods incl. `0.24` linear → `1.96`) as a regression floor | matches exactly on all values; added |

## Not ported (Step 4 exclusions)

- `test_mean_overflow`, `test_online_variance`, `test_min_max_2850` — `@pytest.mark.release`/large-N
  regression or randomized-order robustness tests; not adversarial-fixture material in the sense
  this sweep targets, and don't port mechanically.
- `test_alias_for_col_agg*` — tests py-polars' *string-column-selector* form of `pl.min("a")` /
  `pl.all("a")` (bare column-name string passed to a module-level function); Polars.jl has no
  equivalent module-level `min(::String)`/`all(::String)` API, only `Polars.min(col(...))`. Not a
  gap — a different (and, for a statically-dispatched language, less natural) API shape upstream
  offers alongside its `Expr`-based one.
- `test_quantile_date`/`_datetime`/`_duration`/`_time`, `test_duration_aggs` — temporal-dtype
  aggregation; belongs to the Batch 8 (temporal) sweep, not this one.
- `test_multi_quantile_group_by_unsupported_26956`, `test_agg_invalid_same_engines_behavior`,
  `test_invalid_agg_dtypes_should_raise` — assert exact upstream error *classes*
  (`InvalidOperationError` subclasses) tied to py-polars' own engine-selection machinery, which this
  wrapper doesn't expose the same way.
- `test_item_*` (lines 1192-1239) — these exercise `Expr.item()` (an aggregation erroring on
  `N != 1` values), a **different function** from `DataFrame.item()`/`Series.item()` already ported
  in Batch 0 (Step 9 — don't conflate same-named functions). `Expr.item()` has no Polars.jl
  counterpart at all; flagged below, not fixed.

## Genuine gaps found (flagged, not fixed — out of scope for this sweep)

1. **`corr`/`cov`/`skew`/`kurtosis` have no Polars.jl binding at all** (absent from the 200-name
   exported surface). `test_statistics.py` devotes roughly a third of its fixtures to these. New
   Rust FFI + (for `corr`/`cov`) likely a Cargo feature check, not a Julia-side fix — recorded in
   `LEDGER.md`, not implemented here.
2. **`Expr.item()`** (the aggregation form, distinct from `DataFrame`/`Series.item()`) has no
   Polars.jl counterpart. Same bucket as above.

## Resolved non-issues (verified before assuming a bug)

- None this batch — every fixture checked live matched upstream on the first try, including the
  subtle `NaN`-in-min/max-vs-mean asymmetry, so there was nothing to second-guess.
