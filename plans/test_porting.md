# Test Porting Plan: py-polars → Polars.jl

## Status
**Phase 0: Complete** ✅ (12 gap-fill tests)
**Phase 1: Complete** ✅ (14 items: joins, group_by, select, filter, sort, frame_verbs, unique)
**Phase 2: Complete** ✅ (4 items: Strings, Dt, Lists, Structs namespaces)
**Phase 3: Complete** ✅ (expression-level ops: aggregation edge cases, arithmetic edge cases, direct-call functions, coalesce variants, element() patterns)
**Phase 4: Complete** ✅ (IO option depth: scan_parquet allow_missing_columns + documented asymmetry regression + passthrough flags, scan_csv missing_is_null/skip_rows_after_header/truncate_ragged_lines/infer_schema_length/ignore_errors, sink_parquet full compression matrix + data_page_size + maintain_order, sink_csv formatting options, sink_ipc compression/record_batch_size/maintain_order)
**Phase 5: Complete** ✅ (constructors, DataFrame/Series misc, expr literals — see commit `0746ed6`; also fixed a genuine source bug along the way, see `7f8c53e`)
**All planned phases (0-5) complete.**

**Gap closure (post-Phase-5):** all 7 genuine gaps found during Phases 0-5 have been closed —
- Null-dtype `getindex`/`collect` (`8b944d3`, test flip `b75725a`): `Series{Union{Missing,Nothing}}`
  now supports indexing/collection (trivial pure-Julia fix — a Null-dtype series carries no real
  data, every index is `missing`); also fixed `DataFrame` `show`/printing for Null-dtype columns as
  a bonus, since it hit the same underlying gap.
- Binary (`Vector{UInt8}`) write-path (`434982f`, test flip `e27013e`): two coordinated pure-Julia
  fixes — a missing `arrowvector` method for `Vector{UInt8}` columns (`src/arrow/array.jl`), and a
  missing `"vz"` (Arrow BinaryView) case in `parse_format` (`src/arrow/schema.jl`).
- Series slicing (`acb3694`, test flip `5bf8bdb`): the only gap requiring a Rust change — added
  `polars_series_slice` to `c-polars/src/series.rs` (zero-copy, mirrors the existing
  `polars_dataframe_get`/`make_series` pattern) plus a Julia `@ccall` wrapper and
  `Base.getindex(::Series, ::UnitRange)`. Required tightening the 4 existing scalar `getindex`
  methods' `index` parameter to `::Integer` to resolve a dispatch ambiguity against the new
  `UnitRange` method (safe, non-behavior-changing — they already assumed scalar semantics).

**Left open, deliberately** (see `~/.claude/plans/explore-the-test-cases-silly-moonbeam.md` for
full reasoning): `test/aqua.jl`'s `ambiguities`/`unbound_args` (documented Aqua static-analysis
false positives, not reachable through normal use) and `test/datatypes/strings.jl`'s
`Strings.titlecase` (blocked on upstream polars' `to_titlecase` requiring a Rust nightly feature
this repo deliberately avoids per `CLAUDE.md`).

**Verified: full suite passes 1081/1084 (3 broken: the 2 Aqua + 1 titlecase items above, all
deliberate exclusions), 0 failed, 0 errored** — stable across repeated runs.

Tests are on branch **`test-porting`**, rebuilt from `scan-parquet` (not `main`). The original
`test-porting` branch (commits `4fb5c70`..`03f763c`+plan-status commits) branched from `main`,
which turned out to be 18+ commits behind `scan-parquet` and missing a same-day FFI panic-safety
fix (`c940fd2`, fixes `polars_series_get`/`polars_dataframe_show` crashing the whole process on
out-of-bounds access) plus substantial feature work (`write_ipc`, real parquet/CSV/IPC options,
timezones, `coalesce`, `pivot`, `describe`). Testing the old branch's Julia bindings against a
`.so` built from `scan-parquet`'s newer Rust source produced an ABI mismatch (wrong argument count
in `@ccall`s) that looked exactly like random memory-corruption crashes and briefly looked like a
Polars.jl bug before the mismatch was found. The rebuilt branch's Phase 0-3 commits are clean
incremental patches of the old branch's phase diffs replayed onto `scan-parquet`'s tree (not a raw
`git rebase`, which would conflict on every file since the old branch's first commit bulk-copied
the whole `test/` directory) — verified to apply with zero content collisions against
`scan-parquet`'s independent evolution of the same files. The old, superseded branch is preserved
as `old-test-porting-broken-base`; `test-porting` is the one to continue from.

A same-day full-suite run (the *first* one ever run cleanly to completion — the crash bug above
made this impossible before) surfaced 87 real test-authoring bugs across Phases 0-3, now all fixed
or (for the genuine Binary-column gap) converted to documented `@test_broken`. See commit
`c8b15e0` for the full breakdown by root cause. Also recovered: `test/expr/aggregation.jl` and
`test/expr/arithmetic.jl`'s Phase 3 content had been written in a prior session but never actually
committed (invisible to `git log`, one `git stash` away from being lost) — now committed.

## Execution notes
Work completed on the **`test-porting-v2` branch** created from `scan-parquet`. Each phase is committed as completed.
Ready to continue with remaining phases (1.3-1.7, 2-5) in subsequent sessions, or merge once approved.

## Context

Polars.jl wraps a large but partial subset of the Rust `polars` crate's functionality, and its own
test suite has grown organically alongside features — some functions are well-tested, some have
only a single happy-path case, and a few (e.g. `name(::Series)`, `Base.show` on `DataFrame`) have
zero coverage at all. The upstream Python binding, `py-polars`, has an extremely thorough test
suite (`py-polars/tests/unit/`, ~490 files) that has already discovered and pinned down the edge
cases that matter for a polars binding: null keys in joins, empty frames, dtype-mix coercion,
window-boundary semantics, etc. Rather than inventing new edge cases from scratch, the fastest path
to real confidence in Polars.jl is to port the *scenarios* those upstream tests already validated,
adapted to Polars.jl's actual (smaller) API surface.

This plan is scoped to be executed by a fast/cheap model with limited reasoning budget (Haiku-tier)
in a follow-up session, so every step is spelled out mechanically: exact file paths, an explicit
Python→Julia translation table, and a literal per-test porting checklist with no open judgment
calls beyond "does Polars.jl expose this kwarg — if not, skip and leave a TODO."

Two research passes already happened during planning (findings folded into this plan, not
re-derivable from a stale doc — they're either verified facts about the current `src/` and `test/`
trees, or verbatim upstream references):
1. A full inventory of every exported Polars.jl function, cross-referenced against every existing
   `test/` file, producing a gap list (zero coverage / shallow / well-covered / indirect-only).
2. A map of `py-polars/tests/unit/`'s directory structure with a HIGH/MED/LOW/SKIP relevance tag
   per file against Polars.jl's implemented surface, plus a sampled pattern summary from 5
   representative files (naming convention, fixture style, assertion helpers, parametrize density).

A handful of the plan's load-bearing claims were spot-checked live against current source during
planning (see "Pre-flight verification" below) — e.g. `join_asof` turned out to already support
`:nearest`, and `eq`/`add`/`sub`/`mul`/`div`/`pow`/`and`/`or`/`lt` are confirmed to be real callable
functions in `src/expr/expr.jl`, not just operator-overload sugar — so those specific items are
locked in, not just inferred from grep.

## Ordering rationale

Phase 0 fills zero/shallow-coverage gaps that require **no Python-source reading or porting
judgment at all** — cheapest possible confidence win, do it first. Phases 1+ then port from
py-polars, ordered so the highest-traffic, most-depended-on operations (frame verbs, join,
group_by) get ported before namespace accessors, which in turn come before IO and constructors —
bugs in foundational operations are more likely to silently corrupt results in everything built on
top of them, so validating the foundation first makes later phases' results trustworthy.

---

## Pre-flight verification (already run during planning — do not re-run unless `src/` has changed)

| Item | Check | Result | Scope decision |
|---|---|---|---|
| Categorical/Enum dtype | grep `src/api/types.jl`, `src/dataframe.jl`, `src/series.jl` | No `Categorical`/`Enum` dtype anywhere | **OUT OF SCOPE** — skip `datatypes/test_categorical.py`, `test_enum.py` |
| Decimal dtype | same | Only hit is CSV writer's `decimal_comma::Bool` formatting flag, not a numeric dtype | **OUT OF SCOPE** — skip `datatypes/test_decimal.py` |
| Binary dtype | grep `src/value.jl`, `src/series.jl` | `load_value(::Value{Vector{UInt8}})` exists (`src/value.jl`); `Vector{UInt8}` is a first-class `MaybeMissing` element type (`src/series.jl`). **Zero test files reference it.** | **IN SCOPE — real gap, moved to Phase 0** |
| `.arr` (FixedSizeList) namespace | grep `src/` | No hits beyond unrelated local vars named `arr` | **OUT OF SCOPE** — skip `operations/namespaces/array/*` |
| `map_elements`/`map_rows`/`map_batches` | grep `src/` | No hits | **OUT OF SCOPE** — skip `operations/map/*` |
| `join_asof` strategies | read `src/join.jl` | `:backward`/`:forward`/`:nearest` all implemented; no `tolerance` kwarg | `:nearest` case → Phase 0. `tolerance` → not portable, omit with TODO if a Python test needs it |
| `group_by_dynamic`/`rolling` kwargs | read `src/group_by.jl` | Full signature confirmed: `every`/`period`/`offset`/`closed`(`:left`/`:right`/`:both`/`:none`)/`label`(`:left`/`:right`/`:data_point`)/`include_boundaries`/`start_by`(`:window_bound`/`:data_point`/`:monday`..`:sunday`); `rolling` has `period`/`offset`/`closed` only | Confirms Phase 0 kwarg-gap items exactly — use these exact symbol sets when writing test loops |
| Direct function forms (`eq`,`lt`,`gt`,`add`,`sub`,`mul`,`div`,`pow`,`and`,`or`) | read `src/expr/expr.jl` | Confirmed real functions called by the `Base.==`/`Base.+`/etc. operator overloads (e.g. `Base.:(==)(a,b) = eq(a,b)`), not merely sugar | Phase 3 direct-call tests are straightforward — no signature guessing needed |

No further verification needed before Phase 3.

---

## Phase 0 — Zero/shallow coverage gap-fill (no Python porting required)

Each row: write direct Julia tests exercising the named function/kwarg with 2–4 cases (happy path
+ 1–2 edge cases: nulls, empty input, boundary value).

| Target file | Function(s) under test | Scope note |
|---|---|---|
| `test/datatypes/series.jl` | `name(series::Series)` | Test on a `Series` obtained via `df[:col]`; check name matches construction/column name |
| `test/dataframe/construction.jl` | `Base.show(io, df::DataFrame)` | `sprint(show, df)` on a small df (non-empty, contains column names), an empty (0-row) df, and a wide (>10 col) df |
| new `test/datatypes/binary.jl` (register in `runtests.jl` after `datatypes/series.jl`) | `Vector{UInt8}` round-trip | Port scenarios from `py-polars/tests/unit/datatypes/test_binary.py`: raw bytes, null bytes in a `MaybeMissing{Vector{UInt8}}` column, empty bytes vector, round-trip through `write_parquet`/`read_parquet` |
| `test/operations/group_by_dynamic.jl` | `rolling(...; offset, closed)` | Vary `offset` (positive/negative duration string) and each `closed ∈ (:left,:right,:both,:none)` against `hourly_store_df()` |
| `test/operations/group_by_dynamic.jl` | `group_by_dynamic(...; closed, label, include_boundaries, start_by)` | One `@testset` per kwarg, looping the exact symbol sets confirmed above |
| `test/operations/join.jl` | `join_asof(...; strategy=:nearest)` | Add alongside existing `:backward`/`:forward` cases in the same fixture shape (see current file's `join_asof` testset) |
| `test/operations/frame_verbs.jl` | `Base.unique(...; keep=:none)` | Add to existing `keep` testset; assert *all* rows sharing a duplicate key are dropped |
| `test/operations/frame_verbs.jl` | `Base.rename(...; strict=false)` | Case: renaming a column name that doesn't exist in the frame does NOT error (contrast with default `strict=true` erroring) |
| `test/operations/sort.jl` | `sort(...; stable=false)` | Duplicate sort keys; assert correct *values* only, not row order among ties |
| `test/operations/frame_verbs.jl` | `upsample(...; stable=false)` | Same treatment as `sort` |
| `test/datatypes/strings.jl` | `Strings.contains(...; strict=false)` + invalid-regex path | Check `src/expr/string.jl` for the exact `strict=false` behavior (likely `missing`/`false`) before asserting |
| new `test/lazyframe/scan_ipc.jl` (register in `runtests.jl` after `sink_ipc.jl`) | `read_ipc`, `scan_ipc` | Mirror shape of `scan_parquet.jl`/`scan_csv.jl`: write via `write_ipc`, read via `read_ipc` and `scan_ipc(...) |> collect`; cover any `n_rows`/`row_index` kwargs `src/io/ipc.jl` exposes (check file first) |

**Register new files:** any brand-new file gets `include("<path>")` added to `test/runtests.jl` in
the matching section, placed after the last existing `include(...)` in that section (see current
`test/runtests.jl` for exact section boundaries/order).

---

## Phase 1 — Core frame ops, join, group_by

| Target Julia file | Source Python file(s) | Scope note |
|---|---|---|
| `test/operations/join.jl` | `operations/test_join.py` | Duplicate-suffix handling, multi-key with nulls in key columns; check `src/join.jl` for a `validate` kwarg before assuming one exists — omit with TODO if absent |
| `test/operations/join.jl` | `operations/test_join_right.py` | `rightjoin`: schema/column-order after join, key coalescing behavior |
| `test/operations/join.jl` | `operations/test_cross_join.py` | Currently size-only (`(9,4)` assertion) — add content assertions: every (left-row, right-row) pair appears exactly once, using a small enumerable fixture |
| `test/operations/join.jl` | `operations/test_join_asof.py` | Beyond Phase 0: any additional kwargs `src/join.jl`'s `join_asof` exposes beyond `by_left`/`by_right`/`strategy` (there are none confirmed — likely nothing further to add beyond richer `by`-group scenarios) |
| `test/operations/group_by.jl` | `operations/test_group_by.py` (121 tests — prioritize a subset) | Multi-key group_by, null keys, multiple agg exprs in one `agg(...)` call, empty-frame group_by; check `src/group_by.jl` for `maintain_order` before assuming it exists |
| `test/operations/group_by_dynamic.jl` | `operations/test_group_by_dynamic.py` | Beyond Phase 0 kwarg fills: overlapping windows, `every`/`period` combinations, extra `group_by` columns |
| `test/operations/select_with_columns.jl` | `operations/test_select.py`, `test_with_columns.py` | Multiple expressions per call, non-existent column (error case), `with_columns` overwriting an existing name, `col("*")` wildcard |
| `test/operations/filter.jl` | `operations/test_filter.py` | Combined `&`/`|` predicates, a `missing`-producing predicate (rows excluded not errored), filter emptying the frame entirely |
| `test/operations/sort.jl` | `operations/test_sort.py` | Multi-column sort with mixed `rev` directions, `nulls_last` × multi-column interaction, sort by expression not bare column |
| `test/operations/frame_verbs.jl` | `operations/test_rename.py` | Name-collision case (two columns renamed to same target — error); current `Base.rename` signature is two parallel `Vector{String}`, not a dict — do not port a dict-mapping scenario |
| `test/operations/frame_verbs.jl` | `operations/test_drop.py` | Drop non-existent column (error), drop all columns (0-column result) |
| `test/operations/frame_verbs.jl` | `operations/test_drop_nulls.py` | `subset` restricted to some columns vs all; row with null in non-subset column is retained |
| new `test/operations/unique.jl` (register in `runtests.jl` after `frame_verbs.jl`) | `operations/unique/test_unique.py`, `test_is_unique.py`, `test_n_unique.py`, `test_unique_counts.py`, `test_approx_n_unique.py` | Split out of the shallow `Base.unique` coverage in `frame_verbs.jl`: `unique` with `subset`, all 4 `keep` modes together; check `src/expr/expr.jl`/`src/dataframe.jl` for `n_unique`/`unique_counts`/`approx_n_unique` before porting — if genuinely absent, note as documented gap, do not fabricate |
| `test/expr/is_unique_dup.jl` | `operations/test_is_first_last_distinct.py` | `is_first`/`is_last`/`is_unique`/`is_duplicated`: subset column, maintain_order interaction |

---

## Phase 2 — Namespace accessors (`Strings.*`, `Dt.*`, `Lists.*`, `Structs.*`)

| Target Julia file | Source Python file(s) | Scope note |
|---|---|---|
| `test/datatypes/strings.jl` | `operations/namespaces/string/test_string.py` | Cross-reference every `Strings.*` function in `src/expr/string.jl` against existing testset names to avoid duplication; fill gaps beyond single happy-path |
| `test/datatypes/strings.jl` | `operations/namespaces/string/test_concat.py` | String-concat separator variants, `ignore_nulls`-equivalent handling — check exact function name in `src/expr/string.jl` first |
| `test/datatypes/strings.jl` | `operations/namespaces/string/test_pad.py` | Only if a pad function exists in `src/expr/string.jl` — else skip with TODO |
| `test/datatypes/datetimes.jl` | `operations/namespaces/temporal/test_datetime.py`, `test_to_datetime.py` | Cross-reference `Dt.*` in `src/expr/datetime.jl` against existing coverage; fill parsing/formatting gaps |
| `test/datatypes/datetimes.jl` | `temporal/test_round.py`, `test_truncate.py`, `test_offset_by.py` | Every distinct duration-string scenario the Python tests cover |
| `test/datatypes/datetimes.jl` | `temporal/test_month_start_end.py`, `test_add_business_days.py`, `test_is_business_day.py` | Only port if the corresponding `Dt.*` function exists — grep first; one TODO line per missing function |
| `test/datatypes/datetimes.jl` | `temporal/test_replace.py` | `Dt.replace`'s `non_existent`/`ambiguous` kwarg matrix — read exact symbol set from `polars_non_existent_t` in `src/api/types.jl` before writing cases |
| `test/datatypes/timezones.jl` | temporal timezone-specific subset of `test_datetime.py` | Requires TimeZones.jl active in the scratch env (per CLAUDE.md's extension pattern) |
| `test/datatypes/lists.jl` | `operations/namespaces/list/test_list.py` | Cross-reference `Lists.*` in `src/expr/list.jl`; fill nested-null / empty-list / zero-length-vs-missing gaps |
| `test/datatypes/lists.jl` | `list/test_eval.py`, `test_set_operations.py`, `test_unique.py` | Only if the corresponding function exists in `src/expr/list.jl` — check first |
| `test/datatypes/structs.jl` | `operations/namespaces/test_struct.py` | `Structs.rename_fields` is shallow (1 case) — port multi-field rename, rename-to-colliding-name error case |

---

## Phase 3 — Remaining expr-level ops, aggregation, arithmetic

| Target Julia file | Source Python file(s) | Scope note |
|---|---|---|
| `test/expr/aggregation.jl` | `operations/aggregation/test_aggregations.py`, `test_vertical.py` | `median`/`prod`/`nan_min`/`nan_max` shallow — add all-null column, single-element, empty-column cases |
| `test/expr/horizontal.jl` | `aggregation/test_horizontal.py`, `test_folds.py` | Check `src/expr/expr.jl` for a fold/reduce function before porting `test_folds.py` — skip with TODO if absent |
| `test/expr/math.jl` | scattered across `operations/arithmetic/` | `floor`/`ceil`/`abs`/`cos`/`sin`/`tan`/`cosh`/`sinh`/`tanh` shallow — add NaN/Inf/negative-input case per function |
| `test/expr/arithmetic.jl` | `arithmetic/test_arithmetic.py`, `test_neg.py`, `test_pos.py`, `test_pow.py` | Division-by-zero, integer overflow, negative exponent |
| `test/expr/arithmetic.jl` | (indirect-only gap items) | Add **direct-call** tests for `eq`,`lt`,`gt`,`or`,`and`,`add`,`sub`,`mul`,`div`,`pow`,`rem`,`log` (confirmed real functions, see pre-flight) — one `@testset` per function calling it directly (`eq(col("a"), col("b"))`), reusing the scenario the existing operator-sugar test already uses |
| `test/expr/null_handling.jl` | `test_fill_null.py`, `test_is_null.py` | Check which `fill_null` strategies `src/expr/expr.jl` exposes before porting a strategy matrix; `is_null`/`is_not_null` combined with other predicates |
| `test/expr/statistics.jl` | `test_statistics.py`, `rolling/test_rolling.py`, `test_rolling_fixed.py` | Add rolling-window statistics only if `src/expr/expr.jl` has rolling stat exprs beyond frame-level `rolling` group_by |
| `test/expr/over.jl`, `test/expr/order_window.jl` | `test_over.py`, `test_window.py` | Multiple partition columns, `over` combined with `sort_by` |
| `test/expr/replace.jl` | `test_replace.py`, `test_replace_strict.py` | `Base.coalesce`'s all-null-row and >3-arg cases (currently shallow) — add here |
| `test/expr/naming.jl` | scattered | `Base.not` on a compound expr, `keep_name` after a chained transform (`col("a") + 1 |> keep_name`) |
| `test/operations/reshape.jl` | `test_pivot.py`, `test_unpivot.py`, `test_reshape.py` | `element()` currently only inside a pivot test — add standalone `@testset "element"` with `sum`/`first`/custom agg inside `pivot` |

---

## Phase 4 — IO (parquet/CSV/IPC option depth)

| Target Julia file | Source Python file(s) | Scope note |
|---|---|---|
| `test/lazyframe/scan_parquet.jl` | `io/test_parquet.py`, `test_lazy_parquet.py` | Already well-covered — check `src/io/parquet.jl` kwargs against existing testset names first, fill only true gaps |
| `test/lazyframe/scan_csv.jl` | `io/test_csv.py`, `test_lazy_csv.py` | Same treatment against `src/io/csv.jl` |
| `test/lazyframe/scan_ipc.jl` (created in Phase 0) | `io/test_ipc.py`, `test_lazy_ipc.py` | Extend the Phase 0 skeleton with option-depth cases |
| `test/lazyframe/sink_parquet.jl`, `sink_csv.jl`, `sink_ipc.jl` | `io/test_sink.py`, `test_write.py` | Compression option matrix — enumerate exact values from `src/api/types.jl`'s `polars_parquet_compression_t`/`polars_csv_compression_t`/`polars_ipc_compression_t`; `mkdir` kwarg (nested-directory write) |
| `test/lazyframe/scan_parquet.jl` (or new `test/io/scan_options.jl`) | `io/test_scan.py`, `test_scan_options.py` | Pin down the documented `allow_missing_columns` asymmetry from CLAUDE.md (missing-column-in-file OK, extra-column-in-file not) as an explicit regression guard |

---

## Phase 5 — Constructors, DataFrame/Series misc, expr literals

| Target Julia file | Source Python file(s) | Scope note |
|---|---|---|
| `test/dataframe/construction.jl` | `constructors/test_constructors.py`, `test_dataframe.py`, `test_argument_types.py` | Port construction-from-various-shapes adapted to Tables.jl (e.g. `DataFrame(NamedTuple)`, `DataFrame` from `Vector` of `NamedTuple` rows) instead of Python dict/list/numpy inputs |
| `test/dataframe/construction.jl` | `test_any_value_fallbacks.py`, `test_strictness.py` | Mixed `Int`/`Float64` column, mixed `missing`/typed column coercion |
| `test/dataframe/describe.jl` | `dataframe/test_describe.py`, `series/test_describe.py` | Diff existing testset names against Python's `percentiles`/`interpolation` kwarg cases, fill gaps only |
| `test/dataframe/io.jl` | `test_df.py`, `test_getitem.py`, `test_vstack.py` | `getindex` negative indices, `Symbol` vs `String` column indexing, out-of-bounds row (error case) |
| `test/datatypes/series.jl` | `series/test_series.py`, `test_getitem.py`, `test_all_any.py` | Indexing/slicing beyond current coverage, boolean-series `all`/`any` with nulls |
| `test/lazyframe/lazy_vs_eager.jl` | `lazyframe/test_lazyframe.py` | General LazyFrame-only behaviors not tied to a specific verb — check `src/lazyframe.jl` for what's exposed (e.g. query-plan introspection) before assuming |
| `test/lazyframe/collect_schema.jl` | `test_collect_schema.py`, `test_schema.py` | Schema mismatch across `concat`, schema after `with_columns` adding a new column |
| `test/expr/literals_cast.jl` | `functions/test_lit.py`, `expr/test_literal.py`, `test_cast.py` | One case per `Base.convert(::Type{Expr}, ...)` overload in `src/expr/expr.jl` (`Int32`,`Int64`,`UInt32`,`UInt64`,`Bool`,`Float32`,`Float64`,`Missing`,`String`,`AbstractVector`), plus `cast` to each supported target dtype |
| `test/expr/when_then_otherwise.jl` | `functions/test_when_then.py` | Chained multi-condition `when`, missing `otherwise` (defaults to null) |

---

## Translation table (Python polars → Julia Polars.jl)

| Python | Julia | Notes |
|---|---|---|
| `pl.DataFrame({...})` | `DataFrame((; col1 = [...], col2 = [...]))` | NamedTuple-of-vectors, not Dict |
| `pl.LazyFrame({...})` | `lazy(DataFrame((; ...)))` | No direct dict-based `LazyFrame` constructor |
| `pl.col("x")` | `col("x")` | |
| `pl.col("*")` | `col("*")` or `:` | `Base.convert(::Type{Expr}, ::Colon) = col("*")` |
| `pl.lit(v)` | `lit(v)` | |
| `pl.when(c).then(a).otherwise(b)` | `when(c, a, b)` | Polars.jl's `when` takes all 3 args directly — verify no chained-builder syntax exists in `src/expr/expr.jl` before assuming one does |
| `df.select(...)` | `select(df, ...)` | |
| `df.with_columns(...)` | `with_columns(df, ...)` | |
| `df.filter(...)` | `filter(df, ...)` (`Base.filter`) | |
| `df.sort(...)` | `sort(df, ...)` | |
| `df.group_by(...).agg(...)` | `agg(group_by(df, ...), ...)` | `group_by(df, exprs...)` takes varargs directly |
| `df.join(other, on=..., how="inner")` | `innerjoin(df, other, col("..."))` | `how="left"/"right"/"outer"/"semi"/"anti"/"cross"` → `leftjoin`/`rightjoin`/`outerjoin`/`semijoin`/`antijoin`/`crossjoin` |
| `df.join_asof(...)` | `join_asof(a, b, on; by_left, by_right, strategy=:backward)` | `strategy ∈ (:backward, :forward, :nearest)`, all confirmed implemented |
| `df.unique(subset=..., keep="first")` | `unique(df, subset; keep=:first)` (`Base.unique`) | `keep ∈ (:first, :last, :none, :any)` |
| `df.rename({"a": "b"})` | `rename(df, ["a"], ["b"]; strict=true)` (`Base.rename`) | Two parallel `Vector{String}`, not a dict |
| `df.drop("a", "b")` | `drop(df, ["a", "b"])` | |
| `df.drop_nulls(subset=...)` | `drop_nulls(df, subset)` | |
| `df.head(n)` / `df.tail(n)` | `head(df, n)` / `tail(df, n)` (`Base.tail`) | |
| `df.explode("col")` | `explode(df, ["col"])` | Check exact signature in `src/verbs.jl` |
| `df.pivot(...)` / `df.unpivot(...)` | `pivot(df, ...)` / `unpivot(df, ...)` | in `src/reshape.jl` |
| `df.describe()` | `describe(df)` | in `src/describe.jl` |
| `pl.concat([a, b])` | `concat([a, b])` | Takes `Vector{LazyFrame}` — `lazy.()` eager frames first if needed |
| `s.name` | `name(series)` | |
| Arithmetic/comparison ops | Same operators work (`+ - * / ^ == < > & |`) | Direct function forms also confirmed real: `add`,`sub`,`mul`,`div`,`pow`,`eq`,`lt`,`gt`,`and`,`or`,`rem`,`log` — prefer these where the gap list flags "indirect-only" |
| `expr.alias("x")` | `alias(expr, "x")` | |
| `expr.name.keep()` | `keep_name(expr)` | |
| `expr.cast(pl.Int64)` | `cast(expr, Int64)` | Check `src/expr/expr.jl` for exact dtype-argument convention |
| `expr.fill_null(v)` | check `src/expr/expr.jl` for exact name/kwarg | Do not assume identical strategy names to Python |
| `expr.str.contains(pattern)` | `Strings.contains(expr, pattern)` | |
| `expr.dt.truncate(every)` | `Dt.truncate(expr, every)` | |
| `expr.list.eval(...)` | `Lists.eval(expr, ...)` (verify it exists) | |
| `expr.struct.field(...)` | `Structs.field_by_name(expr, ...)` / `field_by_index(...)` | Check exact names in `src/expr/struct.jl` |
| `assert_frame_equal(a, b)` | `@test a == b` | Exact row order matters by default |
| `assert_frame_equal(a, b, check_row_order=False)` | Sort both frames by a stable key column first, then `@test a_sorted == b_sorted` | No built-in order-insensitive equality — flag and handle per-test, don't silently assume order doesn't matter |
| `assert_series_equal(a, b)` | `@test a == b` (or `@test collect(a) == collect(b)` if materializing needed) | |
| `pytest.raises(SomeError)` | `@test_throws Exception ...` or `@test_throws ErrorException ...` | Polars.jl errors are plain `error(message)` via `polars_error` — no typed exception hierarchy |
| `@pytest.mark.parametrize("x", [1,2,3])` | `@testset "..." for x in [1,2,3] ... end` | |
| `test_foo_22516` (regression, issue number) | `@testset "foo (#22516)" begin ... end` | Keep the issue number as a breadcrumb |

---

## Literal per-test-case porting procedure (mechanical, no judgment calls)

For **every individual Python test function** ported:

1. **Locate**: open the Python source file at the path given in the phase table; find the
   `def test_<name>(...) -> None:` function; note its line range.
2. **Read**: read only that one function's body. Identify the input DataFrame/LazyFrame/Series
   construction(s), the operation(s) under test, and the expected assertion or exception.
3. **Check availability**: for every polars-python function/kwarg used, grep the matching
   `src/*.jl` file (per the phase table's "Target Julia file") for an equivalent.
   - Kwarg missing, base function exists → port without that variant, add
     `# TODO: <kwarg> not exposed in Polars.jl, see src/<file>.jl — gap` above the omitted case.
   - Whole function missing → do not port this test. Move to the next one. Do not fabricate.
4. **Translate**: using the table above, write one `@testset "<name matching Python's intent>"
   begin ... end` block in the target Julia file — append to an existing `@testset` covering the
   same function if one exists, else add as a new top-level `@testset`.
   - Preserve the same scenario shape (null placement, edge values, dtype mix) — do not simplify.
   - Convert assertions/exceptions per the table; use order-insensitive comparison only if the
     Python test used `check_row_order=False`.
5. **Register (new files only)**: add `include("<relative/path>.jl")` to `test/runtests.jl` in the
   matching section, after the last existing `include(...)` there.
6. **Run in isolation**, then full suite:
   ```
   JULIA_PROJECT=<scratch env> julia -e 'using Polars, Test, Dates, Tables; include("test/fixtures.jl"); include("test/<edited_file>.jl")'
   JULIA_PROJECT=<scratch env> julia -e 'include("test/runtests.jl")'
   ```
   Scratch env (create once per session if not already present):
   `Pkg.develop(path=".")` + `Pkg.add(["Aqua", "Test", "Tables", "TimeZones"])`.
7. **Confirm pass** before moving to the next test function. If it fails, fix the Julia
   translation — do not touch `src/` unless the failure reveals a genuine bug, and if so, flag it
   separately rather than silently patching around it mid-port.
8. **Repeat** from step 1 for the next test function, then the next file in the phase table.

---

## Explicitly out of scope (confirmed by pre-flight checks)

`sql/`, `interop/`, `interchange/`, `ml/`, `test_plot.py`, `test_show_graph.py`, `meta/`, `utils/`,
`cloud/`, `ooc/`, `streaming/`, `test_serde.py`, `test_pickle.py`, `datatypes/test_object.py`,
`test_extension.py`, `io/test_avro.py`, `test_delta.py`, `test_iceberg.py`, `test_spreadsheet.py`,
database/cloud IO, `operations/namespaces/array/*` (no `.arr` namespace), `operations/map/*` (no
`map_elements`/`map_rows`/`map_batches`), `datatypes/test_categorical.py`, `test_enum.py`,
`test_decimal.py` (no such dtypes).

`datatypes/test_binary.py` is **not** out of scope — Binary is implemented via `Vector{UInt8}`,
just untested; it's in Phase 0.

---

## Verification (end-to-end)

After each phase: run the full suite via the scratch-env invocation in step 6 above and confirm
`Test Passed` with zero failures/errors, and record the new total test count. Update this file's
`## Status` line to note which phase last landed and the running test count, per this repo's usual
`plans/` convention (see other files in this directory for examples, e.g.
`plans/csv_ipc_io_options.md`).

### Critical files
- `test/runtests.jl` — include-list, section boundaries for new-file registration
- `test/fixtures.jl` — shared sample-data builders (`fruits_cars_df()`, `kitchen_sink_df()`, `hourly_store_df()`, `write_temp_parquet`/`write_temp_csv`)
- `test/operations/join.jl`, `src/join.jl` — confirmed reference shapes for the join phase
- `src/group_by.jl` — confirmed `group_by_dynamic`/`rolling` kwarg symbol sets
- `src/expr/expr.jl` — confirmed direct-call function forms and `Base.convert` literal overloads
- `CLAUDE.md` — build/test workflow, ownership/error conventions, known sharp edges
