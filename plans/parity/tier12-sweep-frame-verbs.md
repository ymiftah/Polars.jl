# Tier 1/2 sweep parity note: limit / Base.reverse / null_count / Base.count / fill_nan / explain / cache (frame-level)

## Status

**Done.** Re-anchored `test/operations/frame_verbs.jl`'s `"limit/reverse/null_count/count/fill_nan/explain/cache
(frame-level)"` testset on upstream fixtures per the `pypolars-test-parity` skill. These seven
functions were added in `2d02cbe` with tests derived from live-observed behavior of our own
implementation rather than from upstream; this note re-derives them from py-polars' actual test
suite and records one real (Rust-side) divergence found along the way.

Upstream sources fetched to `/home/simba/workspace/pypolars-ref/`: `test_reverse.py`,
`test_null_count.py` (dataframe), `test_df.py`, `test_series.py`, `test_lazyframe.py`,
`test_statistics.py` (operations), `test_engine.py`, plus `conftest.py` for the `fruits_cars`
fixture and `frame.py` (full `DataFrame` source, to check `null_count`'s Python-side binding).

## Fixtures ported (all live-verified before asserting, Step 7)

| function | upstream test | fixture | category | outcome |
|---|---|---|---|---|
| `limit` | `test_limit` (`lazyframe/test_lazyframe.py`) | `fruits_cars` fixture (`conftest.py`), `.lazy().limit(1)` == first row | happy path, non-default fixture | matches (`A=[1]`, `fruits=["banana"]`, `cars=["beetle"]`); added |
| `Base.reverse` | `test_reverse_df` (`operations/test_reverse.py`) | `{a:[1,2], b:[3,4]}` → `{a:[2,1], b:[4,3]}` | happy path | matches; added |
| `Base.reverse` | `test_reverse_list_22829` (`operations/test_reverse.py`) | schema preserved on a 0-row frame (List(Binary) dtype itself out of scope, see below) | empty input | matches on a plain-numeric 0-row frame (size `(0,2)`); added |
| `null_count` | `test_null_count` (`lazyframe/test_lazyframe.py`) | `a=[1,2,None,2]` (1 null), `b=[None,3,None,3]` (2 nulls) | null propagation | matches (`[1]`, `[2]`); added |
| `null_count`/`Base.count` | `test_null_count` (`dataframe/test_null_count.py`, hypothesis `@example`s) | `pl.DataFrame(schema=["x","y","z"])` (0 rows, 3 cols) → shape `(1,3)`; `pl.DataFrame()` (0 rows, 0 cols) → shape `(1,0)` | empty input | schema-only case matches (`(1,3)`); the 0×0 case **diverges**, see below |
| `Base.count` | `test_count` (`operations/test_statistics.py`) | 4 columns (`nulls`/`one_null_str`/`one_null_float`/`no_nulls_int`) against non-null counts cast to `pl.get_index_type()` (`UInt32`) | happy path, dtype-pinning | matches values (`[0,2,2,3]`) and dtype (`UInt32`); added |
| `fill_nan` | `test_fill_nan` (`dataframe/test_df.py`, `lazyframe/test_lazyframe.py`) | `fill_nan(None)` turns `NaN` into a genuine null (not a no-op) | non-default parameter value | matches (`convert(Expr, missing)` already existed in `src/expr/expr.jl`, no fix needed); added |
| `fill_nan` | `test_fill_nan` (`dataframe/test_df.py`) | frame with a NaN-bearing `Float64` column + a `Datetime` column → only the float column changes, `Datetime` dtype/values untouched | happy path / dtype isolation | matches; added |
| `explain` | `test_describe_plan` (`lazyframe/test_lazyframe.py`) | `explain(optimized=True/False)` returns a `str` | happy path | matches (`String` in both cases); added |
| `explain` | `test_explain_streaming_flag_reaches_optimizer` (`lazyframe/test_engine.py`) | `explain(engine="streaming")` vs `"in-memory"` | n/a (no streaming engine here) | not ported, Step 4 exclusion |
| `cache` | `test_cache_hit_with_proj_and_pred_pushdown` (`lazyframe/test_lazyframe.py`) | `concat([cached, cached])` dedups to **one** `CACHE[id: ...]` node reused on both branches, in the optimized plan | happy path, structural | matches: two `CACHE[id: ...]` occurrences in `explain(q)`, same id both times, `collect` still yields both branches' rows (`a=[1,2,3,1,2,3]`); added |

## Not ported (Step 4 exclusions)

- `test_null_count`/`test_count` **hypothesis property tests** (`@given(df=dataframes(...))`) —
  don't port mechanically; only their explicit `@example` fixtures were pulled out and ported
  above.
- `test_cache_hit_child_removal` — exercises `sort().cache()` interacting with `unique()`
  optimizer collapse (asserting `"SORT" not in explain(...)`); redundant with the dedup mechanism
  already covered by `test_cache_hit_with_proj_and_pred_pushdown` above, and adds a second
  optimizer-internals assertion (`SORT` elision) that isn't really about `cache` itself. Skipped
  to avoid over-fitting the test to today's optimizer internals.
- `test_reverse_series`/`test_reverse_binary` — `Series`-level `reverse`, not the frame-level verb
  this batch covers (Step 9: same name, different function upstream).
- `test_count_suffix_10783` — exercises `pl.len().over(...)`, an unrelated `len`/`over` regression
  test that only incidentally matched the `count` search term.
- `test_null_count_optimization_23031` — a query-plan-optimization regression test for
  `Expr.count()` interacting with `when/then`; tests the `Expr`-level `count`, not the frame-level
  verb (Step 9 again), and isn't reachable through our current `when`/`then` API shape the same
  way.

## Genuine divergence found (Step 8)

**`null_count`/`Base.count` on a genuinely 0-column `DataFrame` return shape `(0, 0)`, not
upstream's `(1, 0)`.** Upstream's own hypothesis test pins this explicitly via
`@example(df=pl.DataFrame())`, asserting `null_count.shape == (1, ncols)` even when `ncols == 0`.

Root cause, confirmed live: our frame-level `null_count`/`count` are `collect ∘ verb ∘ lazy`
(per `CLAUDE.md`'s guiding principle), calling `polars_lazy_frame_null_count`/`_count`
(`c-polars/src/dataframe.rs:817-824`), which is a thin wrapper over upstream's own
`LazyFrame::null_count()`/`count()`. On a 0-column input, the lazy planner never has a column to
derive an output row from and reports height 0. Upstream's **eager** `DataFrame.null_count()`
(`py-polars/polars/dataframe/frame.py:11615-11636`) instead calls `self._df.null_count()` —
a *different* Rust binding (`PyDataFrame.null_count`, not `LazyFrame::null_count()`) — which
apparently special-cases the 0-column case to still emit one row.

This is a Rust/FFI-path divergence (a different underlying Rust method entirely), not a Julia-side
marshalling bug, and no Rust changes were made in this task per its constraints. Recorded as
`@test_broken` in `test/operations/frame_verbs.jl` (both `null_count` and `count`), documenting
both the expected upstream shape (`(1, 0)`, broken) and the actual current shape (`(0, 0)`,
asserted as fact) side by side. Fixing it for real would mean adding an eager-specific
`polars_data_frame_null_count`/`_count` FFI entry point that calls `DataFrame::null_count()`
directly instead of going through the lazy path — worth flagging for a future batch, not fixed
here.

## Running ledger

| function | our test file | upstream file::test | status | note |
|---|---|---|---|---|
| `limit` | `test/operations/frame_verbs.jl` | `lazyframe/test_lazyframe.py::test_limit` | done | `fruits_cars` fixture ported |
| `Base.reverse` | `test/operations/frame_verbs.jl` | `operations/test_reverse.py::test_reverse_df`, `test_reverse_list_22829` | done | round-trip + upstream value fixture + 0-row schema preservation |
| `null_count` | `test/operations/frame_verbs.jl` | `lazyframe/test_lazyframe.py::test_null_count`, `dataframe/test_null_count.py::test_null_count` | done, 1 `@test_broken` | 0×0-frame shape divergence, see above |
| `Base.count` | `test/operations/frame_verbs.jl` | `operations/test_statistics.py::test_count` | done, 1 `@test_broken` | dtype (`UInt32`) pinned; same 0×0-frame divergence |
| `fill_nan` | `test/operations/frame_verbs.jl` | `dataframe/test_df.py::test_fill_nan`, `lazyframe/test_lazyframe.py::test_fill_nan` | done | `fill_nan(missing)` and dtype-isolation (Datetime untouched) both ported |
| `explain` | `test/operations/frame_verbs.jl` | `lazyframe/test_lazyframe.py::test_describe_plan` | done | streaming-engine variant excluded (n/a) |
| `cache` | `test/operations/frame_verbs.jl` | `lazyframe/test_lazyframe.py::test_cache_hit_with_proj_and_pred_pushdown` | done | CACHE-node-dedup structural assertion added |

## Verification

- `timeout 900 julia --project=. -e 'using Pkg; Pkg.test()'`: **3143 passed, 4 broken** (baseline
  3116 passed / 2 broken — the delta is +27 passing assertions and +2 new `@test_broken` for the
  divergence above; the pre-existing 2 broken are unrelated Aqua/`Strings.titlecase` exclusions).
- `pre-commit run --all-files`: all hooks passed (no Rust or docstring changes in this batch, so
  `docs/make.jl` was not run).
