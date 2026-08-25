# Polars.jl API gap audit: full inventory of what's missing vs py-polars

## Status

**Audit complete; gap-closure in progress.** This file started as a static inventory; it is now
also being used to track closure. Two items have since been closed on `main` (merged into this
branch), independent of this effort:

- **`Selectors.array()`** (Group 0) — no longer a stub; now `_dtype_simple(API.PolarsDtypeSelectorKindArray)`.
  The staleness caveat below is resolved.
- **`polars_dataframe_new_from_series`** (Group 9, item 7) — now surfaced as
  `DataFrame(series::AbstractVector{<:Series})` in `src/dataframe.jl`.
- **`polars_value_time_zone`** (Group 9, item 7) — now used by `ext/PolarsTimeZonesExt.jl`'s
  `load_value(::Value{ZonedDateTime})`, which the merge also brought in.

Closed by this effort, on top of the merge:

- **Three of the four remaining Group 9 item-7 symbols** — `polars_expr_selector_empty` (now
  `Selectors.empty()`), `polars_series_type` (now `Polars.dtype(series)`), `polars_dataframe_show`
  (now `Polars.native_repr(df)`). `polars_value_list_type` remains unsurfaced: it backs a
  `Value`-level (internal, unexported) correctness case for nested-list element typing that needs
  its own design pass, not a thin wrapper — deferred, not attempted here.
- **JSON/NDJSON I/O (Group 7)** — closed in full, and turned out to need zero Cargo.toml changes:
  `read_json`/`write_json` (plain JSON, eager-only — matching upstream, which has no lazy JSON
  scan either) and `read_ndjson`/`write_ndjson`/`scan_ndjson`/`sink_ndjson` (NDJSON, with a lazy
  scan and streaming sink) are now all live in `src/io/json.jl`, backed by six new `c-polars`
  `extern "C"` functions. The `json` feature already covered both formats fully upstream
  (`LazyJsonLineReader` and `FileWriteFormat::NDJson` are both gated on `json`, not a separate
  `ndjson` feature as [Group 10](#group-10) speculated) — that entry is now stale, see its own
  note.

A second merge (bringing in `main`'s macro-generation/`guard_error` refactor, PRs #42/#43) landed
after the above with no further API-surface change — purely internal, re-checked live. On top of
that merge, this effort additionally closed a "quick wins" batch of no-Cargo-feature-change gaps:

- **Math (Group 3)**: `cbrt`, `cot`, `arcsinh`, `arccosh`, `arctanh` — five new `polars_expr_*`
  symbols, all under the already-enabled `trigonometry` feature (`cbrt` itself is ungated). `cbrt`
  turned out to share polars' `PowFunction` family with `sqrt`: unlike every other function closed
  here, it implicitly casts a String column to `Float64` (non-numeric strings become `missing`)
  rather than raising `PolarsError` — verified live, see the test in `test/expr/arithmetic.jl`.
- **`Dt` sub-second components (Group 4)**: `microsecond`, `millisecond`, `nanosecond` — three new
  `polars_expr_dt_*` symbols, ungated like their `year`/`month`/`day` siblings.
- **`exclude` (Group 2)**: needed **zero** new Rust — it's `Selectors.all() -
  Selectors.by_name(names...; strict=false)` composed from selector primitives that already
  existed, added as a plain Julia function in `src/expr/selectors.jl`.
- **Explicitly deferred, not attempted**: `arg_where` and `is_close` looked like the same kind of
  quick win but turned out to be gated behind Cargo features (`arg_where`, `is_close`) not in
  `c-polars/Cargo.toml`'s current list — [Group 10](#group-10)'s table missed both; corrected
  there and at their own entries (Group 2, Group 3) rather than adding a Cargo change outside a
  dedicated, batched PR per `CLAUDE.md`.

A subsequent `pypolars-test-parity` sweep of this batch (per its own skill) against
`py-polars/tests/unit/series/test_series.py`, `.../datatypes/test_temporal.py`, and
`.../expr/test_exprs.py`/`.../operations/test_expansion.py` found the initial tests happy-path-only
in the ways that skill predicts, and one real API-surface gap:

- **`exclude` was missing the dtype-based form entirely.** Upstream `pl.exclude`'s actual signature
  is `str | PolarsDataType | Collection[...]`, not name-only — `pl.exclude(pl.Int64)`/
  `pl.all().exclude(pl.Boolean)` are real, tested upstream calls. **Closed**: `exclude(dtypes::Type...)`
  now composes `Selectors.all() - Selectors.by_dtype(dtypes...)`, plus an explicit `exclude()`
  method to resolve the otherwise-ambiguous zero-argument dispatch between the two vararg forms.
  Mixing a name and a dtype in one call (`exclude("a", Int64)`) is a plain `MethodError` here,
  matching upstream's own rejection of the same mix (there, a `TypeError`) — deliberately not
  supported, documented on the docstring. Upstream's `pl.exclude` also accepts a `"^regex$"`
  string, which this package's `by_name` has never supported (regex goes through the separate
  `Selectors.matches` instead, per its own docstring) — `exclude` follows that existing precedent
  and does not add regex support either.
- Depth gaps closed without a signature change: `cot(π)` (a near-pole finite value,
  `-8.1656e15`, distinct from `cot(0)`'s exact `+Inf`), the shared `[0.0, π, missing, NaN]`
  trig fixture cross-checked against `arcsinh`/`arccosh`/`arctanh` (π lands in-domain for
  `arccosh` but out-of-domain for `arctanh` — the two hand-picked fixtures already in place don't
  happen to probe that), a `Date`-dtype wrong-dtype check for `arccosh`/`arcsinh`/`arctanh`/`cot`
  (upstream tests this via `cosh`, not just via `String`) — `cbrt` again silently casts rather
  than raising, on `Date` same as `String` — and genuine (non-multiple-of-1000) sub-millisecond
  precision for the `Dt` components via `cast_datetime(...; time_unit=:ns)`, since a
  `Dates.DateTime` literal can't itself carry that precision.

Everything else in this file was re-checked against `main` after the merge and remains accurate.

**2026-08-25 update.** Re-verified this whole file live against current `main` (past PR #45,
`v0.5.1+jl`) rather than trusting the text above, since it predates that merge. Two further
closures had landed independently of this effort, both now stale where mentioned below:

- **The `parity-group1-group4` merge (PR #45)** closed almost all of [Group 4](#group-4--gaps-inside-existing-namespaces)'s
  `Dt` list — `iso_year`, `is_leap_year`, `century`, `millennium`, `combine`, `datetime`,
  `cast_time_unit`, `with_time_unit`, `base_utc_offset`, `dst_offset`, and `dt.replace` (component
  replacement, distinct from [`replace_time_zone`](@ref)) are all live now, each backed by its own
  `polars_expr_dt_*` symbol. Only `add_business_days` (genuinely gated behind the `business`
  feature, see [Group 10](#group-10)) and `to_string` remain missing. The same merge closed the
  `.name` namespace's `prefix_fields`/`suffix_fields`.
- **`scan_parquet`'s `allow_extra_columns`** (mentioned only via `docs/src/limitations.md` cross-ref
  elsewhere) also landed in that merge, independent of this file's own Group 6/7 findings.

This session additionally closed a batch of low-hanging, zero-Cargo-change items found by
re-deriving [Group 10](#group-10)'s "already-enabled feature" claim from scratch (it turned out
still accurate — `concat_str`'s Cargo feature really is on, just the *top-level* `pl.concat_str`/
`pl.concat_list` functions themselves, as opposed to `Strings.join`, had never been wrapped):

- **Top-level `concat_str`/`concat_list`** ([Group 2](#group-2--missing-top-level-functions-pl))
  — new `polars_expr_concat_str`/`polars_expr_concat_list` FFI symbols, no Cargo change (`concat_str`
  was already enabled; `concat_list` is ungated). Distinct from `Strings.join`/`Lists.join`
  (aggregations), which already existed.
- **Frame-level `fill_null`, `cast` (both the per-column `AbstractDict` form and the whole-frame
  single-`Type` form), `slice`, `top_k`, `bottom_k`** ([Group 6](#group-6--missing-frame-level-dataframelazyframe-methods))
  — five new `polars_lazy_frame_*` FFI symbols (`cast`'s `AbstractDict` form needed none — it
  composes `with_columns` + the pre-existing per-`Expr` `cast`). `top_k`/`bottom_k` turned out to
  need one design correction versus the naive port: upstream's own `LazyFrame::top_k`/`bottom_k`
  unconditionally force `nulls_last: true` internally regardless of what's passed in the sort
  options, so there is deliberately no `nulls_last` parameter on the Julia side (matching upstream's
  own public API, which doesn't expose one there either) — see the docstring on `top_k` in `sort.jl`.

Also corrects a claim in [`gap_closure_scope.md`](gap_closure_scope.md)'s Group B3 (now itself
annotated): `strict_cast` was never actually a gap by the time that file's "expose as `cast(expr,
T; strict=false)`" suggestion was written up here — `cast(expr, dtype; strict=true)` already
dispatches to `polars_expr_strict_cast` (`src/expr/expr.jl`, `_plain_value_type_code`'s call site).

Read alongside its two siblings, which cover different slices of the same problem:

- [`LEDGER.md`](LEDGER.md) — the py-polars *test*-parity sweep (batches 0-9 done, 10-14 unswept).
- [`gap_closure_scope.md`](gap_closure_scope.md) — the gap-closure plan the sweep's own findings
  produced. **Its "Group C" (features needing a Cargo change) is now stale:** all twelve of the
  features it listed (`list_sets`, `list_count`, `list_gather`, `list_drop_nulls`, `list_sample`,
  `list_to_struct`, `dtype-array`, `concat_str`, `extract_groups`, `json`, `is_first_distinct`,
  `is_last_distinct`) are present in `c-polars/Cargo.toml` today. [Group 10](#group-10) below is the
  current replacement for that table.

## Context

Polars.jl wraps the Rust `polars` crate through a hand-written C ABI. A capability is only reachable
from Julia if someone wrote an `extern "C"` shim for it, so the API surface is *additive and
incomplete by construction* — and per `CLAUDE.md`, a symbol missing from Rust is silently invisible
to Julia rather than a build error. That makes the absent surface hard to see from inside the
package, which is what this file exists to fix.

### Method

Produced statically, without a Julia runtime:

- **"Present"** = the 422 `polars_*` symbols in `src/api/generated.jl`, plus every function
  definition across `src/**/*.jl` (403 distinct names, excluding `generated.jl`), plus the
  `@generate_expr_fns` / `gen_impl_expr_{dt,list,str}!` macro blocks.
- **"Missing"** = each py-polars name checked against *both* sets. Every verdict below was
  re-derived mechanically after the first pass; findings that assert *presence* cite `file:line`.

### Headline

**382 wrapped FFI functions, of which only 6 are unsurfaced in Julia.** The Julia layer is not the
bottleneck — essentially every gap below is a missing `c-polars` shim, and roughly a third of those
additionally need a Cargo feature. Three whole py-polars namespaces (`.bin`, `.cat`, `.arr`), the
entire JSON/NDJSON I/O family, all UDF entry points, and *all* join options beyond the join type
itself are absent.

---

## Group 0 — Explicit "unavailable in this build" stubs (6)

Bindings that exist and hard-error at runtime. Found by `grep -rn "unavailable in this build" src`.

| Function | Location | Gate | Note |
|---|---|---|---|
| `Selectors.array()` | `src/expr/selectors.jl:249` | `dtype-array` | **Stale — the gate is gone.** `dtype-array` *is* in `c-polars/Cargo.toml`'s feature list, and `PolarsDtypeSelectorKindArray = 15` is in `src/api/generated.jl:121`. The error text, the surrounding comment, and the `docs/src/limitations.md` entry all still claim the feature is off. Needs a live check (see [Caveats](#caveats)), then likely a one-line fix. |
| `Strings.titlecase` | `src/expr/string.jl:62` | `nightly` rustc | Genuinely blocked — `c-polars/rust-toolchain` pins stable deliberately. Currently `@test_broken`. |
| `Strings.to_integer` | `src/expr/string.jl:413` | `string_to_integer` | Feature genuinely absent. |
| `Strings.reverse` | `src/expr/string.jl:444` | `string_reverse` | Feature genuinely absent. |
| `Dt.month_start` | `src/expr/datetime.jl:112` | `month_start` | Feature genuinely absent. |
| `Dt.month_end` | `src/expr/datetime.jl:126` | `month_start` | Feature genuinely absent. |

## Group 1 — Already-documented behavioural limitations

Recorded in `docs/src/limitations.md`; listed for completeness, not re-derived here.

- `Decimal` columns can be queried and cast but not materialized into Julia.
- No `hive_partitioning` for CSV scans (upstream `LazyCsvReader` hardcodes it off).
- `allow_missing_columns` covers *missing* columns only, not extra ones.
- `lit(::DateTime)` is always `:ns`, inheriting that representation's ~1678-2262 range limit;
  mismatched-resolution Datetime join keys error rather than aligning.
- `Meta.is_literal` returns `false` for `Date`/`Time`/`DateTime` literals (cosmetic).
- No handle is thread-safe.

## Group 2 — Missing top-level functions (`pl.*`)

Confirmed absent from both the definition set and the FFI symbol table.

**Ranges and generators** — nothing in this family exists: `int_range`, `int_ranges`, `arange`,
`date_range`, `date_ranges`, `datetime_range`, `datetime_ranges`, `time_range`, `time_ranges`,
`repeat`, `ones`, `zeros`.

**Temporal constructors** — `date()`, `datetime()`, `time()`, `duration()`, `from_epoch`. Note
`cast_datetime`/`cast_duration` exist but are *casts*, not constructors from component expressions.

**String and list combination** — ~~`concat_str`, `concat_list`~~ **Closed** (see [Status](#status)).
`concat_arr`, `format` remain missing. `Strings.join`/`Lists.join` are the *aggregating* joins,
distinct from the row-wise horizontal `concat_str`/`concat_list`.
(`format` is defined in `src/arrow/array.jl:90`, but that is the internal Julia-type-to-Arrow-format
mapping — unrelated to `pl.format`, and a name collision to watch when adding the real one.)

**Reductions and folds** — `fold`, `reduce`, `cum_fold`, `cum_reduce`, `cum_sum_horizontal`,
`approx_n_unique`, `len`.

**Selection and ordering** — ~~`exclude`~~ **Closed** (see [Status](#status)); `arg_where`,
`arg_sort_by`. **`arg_where` is gated behind Cargo's `arg_where` feature** — absent from
`c-polars/Cargo.toml`'s current feature list and from [Group 10](#group-10)'s table below, which
was therefore itself incomplete; do not add it without batching the Cargo change per `CLAUDE.md`.

**Windowed correlation** — `rolling_corr`, `rolling_cov`. (Scalar `cov`/`cor` and
`spearman_rank_corr` do exist, in `src/expr/statistics.jl`.)

**Math** — `arctan2`. **Business calendar** — `business_day_count`. **SQL** — `sql_expr`.

> Present, for contrast: `col`, `nth`, `lit`, `element`, `when`, `coalesce`, `as_struct`,
> `all_horizontal`, `any_horizontal`, `min_horizontal`, `max_horizontal`, `sum_horizontal`,
> `mean_horizontal`, and frame `concat`.

## Group 3 — Missing `Expr` methods

**Aggregations and reductions**: `mode`, `entropy`, `unique_counts`, `approx_n_unique`, `arg_true`,
`arg_unique`, `dot`, `len` (distinct from `count`, which exists and skips nulls), and the bitwise
reductions (`bitwise_and`, `bitwise_or`, `bitwise_xor`, `bitwise_count_ones`,
`bitwise_leading_zeros`).

**Selection within an expression** — the most-felt group, since these are the standard idioms
inside `agg`. **Closed** by this effort: `filter`, `sort`, `head`/`tail`/`slice`/`get`/`limit`,
`top_k_by`/`bottom_k_by` are all now plain `Expr` methods in `src/expr/expr.jl`, each backed by a
new `polars_expr_*` FFI symbol (`get`/`sort`/`tail` extend `Base.get`/`Base.sort`/`Base.tail`
rather than shadowing them — see the in-source note on `tail`'s definition for why a plain,
non-`Base.`-qualified `function tail(...)` breaks `select.jl`'s later `import Base: tail`; `limit`
is a plain alias for `head`, matching upstream). `Expr.explode` was never actually a gap — it's
covered by `flatten` (`src/expr/expr.jl`, calling `polars_expr_flatten`), which is upstream's own
alias for it.

**Window and ordering**: `cumulative_eval`, `peak_min`, `peak_max`, `search_sorted`, `set_sorted`,
`lower_bound`, `upper_bound`, `rolling_skew`, `rolling_kurtosis`, `rolling_map`, every temporal
`rolling_*_by` variant (`rolling_mean_by`, `rolling_sum_by`, …), `ewm_mean_by`, `interpolate_by`.

**Manipulation**: `extend_constant`, `repeat_by`, `reshape`, `shuffle`, `round_sig_figs`,
`shrink_dtype`, `to_physical`, `reinterpret`, `hist`, `is_close`. **`is_close` is gated behind
Cargo's `is_close` feature** — like `arg_where` above, absent from `c-polars/Cargo.toml` and from
[Group 10](#group-10)'s table; needs a batched Cargo change, not a thin wrapper.

**Math**: ~~`cbrt`, `cot`, `arcsinh`, `arccosh`, `arctanh`~~ **Closed** (see [Status](#status)).
(`sin`, `cos`, `tan`, `sinh`, `cosh`, `tanh`, `arcsin`, `arccos`, `arctan`, `degrees`, `radians`,
`exp`, `log`, `log10`, `log1p`, `sqrt`, and `sign` all exist too.)

**UDFs**: `map_elements`, `map_batches` — blocked on [Group 9](#group-9).

## Group 4 — Gaps inside existing namespaces

### `Strings` (upstream `.str`)

`json_decode`, `json_path_match`, `to_decimal`, `to_time`, `strptime` (the generic form — `to_date`
and `to_datetime` cover two of its three targets), `decode`/`encode` (base64/hex), `contains_any`,
`replace_many`, `find_many`, `extract_many`, `escape_regex`, `normalize`. Plus `to_integer`,
`reverse`, and `titlecase` from [Group 0](#group-0--explicit-unavailable-in-this-build-stubs-6).

### `Dt` (upstream `.dt`)

~~Missing **sub-second component extraction — `microsecond`, `millisecond`, `nanosecond`.**~~
**Closed** (see [Status](#status)) — each is the sub-second part of the timestamp expressed at
that unit's own resolution (not a decomposed digit group), mirroring the `total_*` family's own
scaling convention; only works on `Datetime`/`Time`, not a plain `Date`
(`` `nanosecond` operation not supported for dtype `date` ``, verified live).

~~Also: `iso_year`, `is_leap_year`, `century`, `millennium`, `combine`, `datetime`, `cast_time_unit`,
`with_time_unit`, `base_utc_offset`, `dst_offset`, `dt.replace` (replacing date components)~~ **All
closed** (PR #45, see [Status](#status)). Still missing: `add_business_days` (genuinely
Cargo-gated, see [Group 10](#group-10)) and `to_string`. Plus `month_start`/`month_end` from
Group 0.

### `Lists` (upstream `.list`)

Nearly complete after the batch-9 gap closure. Missing: `concat`, and expression-level `explode`.
Two naming notes that are *not* gaps: upstream's `len` is spelled `lengths` here, and `eval`/`filter`
are reachable via `Lists.apply` (`src/expr/list.jl:370`), renamed because `eval` is a reserved
per-module name in Julia.

### `Structs` (upstream `.struct`)

Expression-level `unnest` (the frame-level verb exists), and field/schema introspection (`fields`,
`schema`).

### Name namespace (upstream `.name`)

`name.map` (needs a callback — Group 9). ~~`prefix_fields`, `suffix_fields`~~ **Closed** (PR #45,
see [Status](#status)). Present: `keep_name`, `prefix`, `suffix`, `prefix_fields`, `suffix_fields`,
`to_lowercase`, `to_uppercase`.

## Group 5 — Entirely missing namespaces (3)

Confirmed by symbol search: **zero** `polars_expr_bin_*`, `polars_expr_cat_*`, or
`polars_expr_arr_*` symbols exist.

| Namespace | State |
|---|---|
| **`.bin` (Binary)** | `contains`, `starts_with`, `ends_with`, `size`, `decode`, `encode`. Binary columns *read* correctly (`test/datatypes/binary.jl`); there are simply no operations on them. |
| **`.cat` (Categorical)** | `get_categories` and the categorical string ops. `cast_categorical` and `Selectors.categorical()` exist, so categorical columns can be produced and selected but never introspected. |
| **`.arr` (Array / fixed-size list)** | The whole namespace. `Lists.to_array` exists and `dtype-array` is enabled, so Array columns can be *created*; nothing operates on them, and there is no write-side path for building one from Julia data. |

## Group 6 — Missing frame-level (`DataFrame`/`LazyFrame`) methods

The complete frame FFI surface is 33 `polars_lazy_frame_*` + 16 `polars_dataframe_*` symbols.

**Row/column selection**: ~~`slice`~~, `limit`, `reverse`, `sample`, ~~frame-level `top_k`/`bottom_k`
(the `Expr` forms exist)~~, `partition_by` (distinct from the sink-side `PartitionByKey`),
`insert_column`, `replace_column`, `drop_in_place`, `extend`, `clear`. `slice`/`top_k`/`bottom_k`
are **closed** (see [Status](#status)); `limit` is a plain alias for `head` upstream and is still
missing here as its own frame-level name (the `Expr`-level `limit` already exists, see Group 3).

**Whole-frame computation**: ~~frame-level `fill_null`~~, `fill_nan`, `interpolate`, ~~`cast` (dtype
mapping)~~, `null_count`, `count`, `approx_n_unique`, `to_dummies`, `corr`, and the frame-level
aggregations `sum`/`mean`/`min`/`max`/`median`/`std`/`var`/`product`/`quantile` — all reachable today
only by rewriting as `select(df, mean(col("*")))`. `fill_null`/`cast` are **closed** (see
[Status](#status)) — `cast` covers both upstream's per-column `AbstractDict` form and its
single-`Type` whole-frame form (only plain, parameter-free dtypes reach the latter, same
restriction as the single-`Expr` `cast`).

**Joins**: `join_where` (inequality/IE join), `merge_sorted`, `update`. **Reshaping**: `unstack`.

**Introspection and plumbing**: `explain`, `profile`, `cache`, `set_sorted`, `with_context`,
`glimpse`, `estimated_size`, `rechunk`, `is_empty`, frame-level `is_duplicated`/`is_unique`.

**Not real gaps**: `equals` (covered by `Base.==`, `src/dataframe.jl:159`), `pipe` (covered by `|>`),
and the whole row/dict iteration family (`iter_rows`, `rows`, `row`, `rows_by_key`, `iter_slices`,
`to_dict`, `to_dicts`, `to_series`) — `DataFrame` implements the Tables.jl interface, which is the
idiomatic Julia equivalent.

### Missing keyword arguments on functions that already exist

Called out separately because each function looks complete from the outside.

- ~~**Joins carry no options at all.**~~ **Closed**, except `slice`: `innerjoin`/`leftjoin`/
  `rightjoin`/`outerjoin`/`semijoin`/`antijoin`/`crossjoin` now accept `suffix`, `coalesce`,
  `validate`, `nulls_equal` (`src/join.jl`). **`slice` is deliberately *not* exposed** — verified
  live that `JoinArgs.slice` panics unconditionally in this polars version
  (`"impl error: slice is not handled"`, both the in-memory and `:streaming` engines), caught by
  `guard_error`'s `catch_unwind` rather than crashing the process, but with no working codepath
  behind it. The FFI parameter is still threaded through (always null from Julia) so a future
  polars upgrade needs only a Julia-side change once this is fixed upstream.
- ~~**`join_asof` hardcodes `tolerance: None`**~~ **Closed**: `join_asof` now accepts `tolerance`
  (string form only — e.g. `"1d"`; a numeric `Scalar` tolerance for non-temporal `on` columns is
  a further scope cut, not attempted), `allow_eq`, `check_sortedness`, plus the same `suffix`/
  `nulls_equal` the other join verbs got.
- ~~**`maintain_order` appears nowhere in the FFI**~~ **Closed**: `group_by(maintain_order=)`,
  frame `unique(maintain_order=)`, and `Base.unique(expr::Expr; maintain_order=)` are all now
  available. Each dispatches between polars' own paired methods (`group_by`/`group_by_stable`,
  `unique`/`unique_stable`, `Expr::unique`/`Expr::unique_stable`) rather than threading a bool
  through a single call, matching how upstream itself expresses the option.
- `rolling_*` accept `window_size`/`min_samples`/`center` but have no `by`/`closed` temporal form.
- `describe` is `DataFrame`-only (upstream also has it on `LazyFrame`). `pivot`, `transpose`,
  `hstack`, `vstack`, and `upsample` being `DataFrame`-only matches upstream.

## Group 7 — Missing I/O

Present: Parquet, CSV, IPC, and (as of this effort) JSON/NDJSON, each with read/scan/write/sink and
a good option surface (`src/io/`), plus cloud `storage_options` and partitioned parquet sinks.

- ~~**JSON / NDJSON**~~ **Closed.** `read_json`/`write_json` (plain JSON, eager-only — no lazy
  scan, matching upstream) and `read_ndjson`/`write_ndjson`/`scan_ndjson`/`sink_ndjson` (NDJSON,
  with a lazy scan and streaming sink) are now all in `src/io/json.jl`, backed by six new
  `c-polars` functions. No Cargo.toml change was needed: `json` alone gates both formats fully
  upstream (see [Status](#status)).
- **Avro** — `read_avro`, `write_avro`.
- **Delta / Iceberg** — `scan_delta`, `write_delta`, `scan_iceberg`.
- **Partitioned sinks for CSV/IPC** — only `polars_lazy_frame_sink_parquet_partitioned` exists.
- **Excel/ODS and database** — `read_excel`, `write_excel`, `read_database`, `write_database`.
  Arguably out of scope: upstream leans on Python libraries for these, and Julia has its own
  ecosystem.

## Group 8 — `Series` surface

`Series` here is a thin materialization handle, not upstream's `Series`. Its entire public API:
`Series(name, values)`, `getindex` (scalar and `UnitRange`), `size`, `copy`, `collect`, `item`,
`name`, `null_count`. Everything else upstream puts on `Series` — arithmetic, aggregations,
`to_list`, `value_counts`, `sort`, `unique`, `cast`, the namespaces — is absent.

This is plausibly a deliberate design choice: Julia users work with `Vector`s and the expression
DSL, and Tables.jl covers column access. It belongs here as **a scope decision to confirm**, not an
obvious bug — and either way deserves an explicit statement in `docs/src/limitations.md`.

## Group 9 — Infrastructure-level gaps

These block whole families of functions rather than individual ones.

1. **No Julia callback into expression evaluation.** Blocks `Expr.map_elements`, `Expr.map_batches`,
   `pl.map_groups`, `Expr.name.map`, `Expr.rolling_map`, and `Expr.cumulative_eval`.
   `plans/callback_infra.md` covers this and is explicitly a problem statement with **no design
   decisions made** ("Not started"); its own recommendation is to spike `.name.map` first
   (plan-construction time, so no threading concern) before the execution-time shapes. The existing
   `_io_callback()` machinery in `src/Polars.jl` only streams bytes *out*.
2. **No SQL interface** — `SQLContext`, `pl.sql`, `pl.sql_expr`, `DataFrame.sql`.
3. **No query-plan introspection** — frame-level `explain`, `profile`, `show_graph`.
   `Meta.tree_format`/`Meta.show_graph` exist for `Expr` only.
4. **No `pl.Config`** — formatting is delegated to PrettyTables.jl, a reasonable Julia-native answer,
   but global toggles like `set_tbl_rows` have no equivalent.
5. **No string cache** — `enable_string_cache`, `StringCache`.
6. **No test helpers** — `assert_frame_equal`, `assert_series_equal`. `Base.==` on `DataFrame` exists
   but there is no tolerance-aware or schema-aware comparison for downstream packages to use.
7. **~~Six~~ One FFI symbol still wrapped in Rust but never surfaced in Julia** —
   `polars_value_list_type`. (The other five — `polars_dataframe_new_from_series`,
   `polars_value_time_zone`, `polars_dataframe_show`, `polars_expr_selector_empty`,
   `polars_series_type` — are all closed now; see [Status](#status).)

## Group 10

### Cargo features that would need enabling

Currently-enabled features are in `c-polars/Cargo.toml`. Per `CLAUDE.md` a feature change forces a
full optimized dependency rebuild (`-j 1`) plus a new `libpolars` release, so **these must be
batched into one change** — and a clean `cargo build` is never evidence a path is safe, so every new
option must be exercised live.

**Feature names in this table are unverified** — see [Caveats](#caveats).

| Feature | Unlocks |
|---|---|
| `arg_where` | top-level `arg_where` — **verified** (`#[cfg(feature = "arg_where")]` on `polars_plan::dsl::functions::index::arg_where`), unlike the rest of this table; this row was missing entirely until the quick-win batch in [Status](#status) went looking for it. |
| `is_close` | `Expr.is_close` — **verified** (`#[cfg(feature = "is_close")]` on `Expr::is_close`), same story as `arg_where` above. |
| `range` | the entire `int_range`/`date_range`/`datetime_range`/`time_range` family |
| `mode` | `Expr.mode` |
| `search_sorted` | `Expr.search_sorted` |
| `approx_unique` | `approx_n_unique` |
| `hist` | `Expr.hist` |
| `peaks` | `peak_min`/`peak_max` |
| `repeat_by` | `Expr.repeat_by` |
| `cumulative_eval` | `Expr.cumulative_eval` (also needs Group 9's callback) |
| `reinterpret` | `Expr.reinterpret` |
| `to_dummies` | frame `to_dummies` |
| `merge_sorted` | `merge_sorted` |
| `iejoin` | `join_where` |
| `business` | `business_day_count`, `Dt.add_business_days` |
| `binary_encoding` | the `.bin` decode/encode ops, `Strings.decode`/`encode` |
| `extract_jsonpath` | `Strings.json_decode`, `Strings.json_path_match` |
| `find_many` | `contains_any`, `replace_many`, `find_many`, `extract_many` |
| `string_normalize` | `Strings.normalize` |
| `string_to_integer` | unblocks the `Strings.to_integer` stub |
| `string_reverse` | unblocks the `Strings.reverse` stub |
| `month_start` | unblocks the `Dt.month_start`/`month_end` stubs |
| `array_any_all`, `array_count`, `array_to_struct` | the `.arr` namespace |
| `bitwise` | the `bitwise_*` reductions |
| `rolling_window_by`, `ewma_by` | the temporal `rolling_*_by` and `ewm_mean_by` variants |
| ~~`ndjson`~~ | **Stale — no such feature was needed** (`json` alone gates NDJSON fully upstream); JSON/NDJSON I/O is closed, see [Status](#status). |
| `avro` | Avro I/O |
| `sql` / the `polars-sql` crate | the SQL interface |
| `nightly` | `Strings.titlecase` — **do not add**; `rust-toolchain` pins stable deliberately |

## Group 11 — Test-coverage gaps (adjacent, not API gaps)

Per [`LEDGER.md`](LEDGER.md), **batches 10-14 of the py-polars parity sweep are unswept**: frame
verbs/reshape/concat/select/filter (11 upstream files), join/group_by/group_by_dynamic/rolling (7),
series/binary/construction/io/describe (9), lazyframe scan/sink/collect_schema/head (9), and
selectors/meta/horizontal/naming/sample (8).

**So this audit is not the final list.** It is the static view — what has no binding at all. The
unswept batches are the behavioural view: what has a binding that does the wrong thing. Expect the
latter to add entries.

`LEDGER.md` also carries three known hygiene problems: its batch-order table still says `unswept`
for batches 1-7 (all merged), the 211-row per-function table is entirely stale, and its `## Status`
preamble still describes a pre-sweep baseline.

## Caveats

1. ~~The `Selectors.array()` staleness claim (Group 0).~~ **Resolved** — closed on `main`, see
   [Status](#status).
2. **Feature-name accuracy in [Group 10](#group-10).** Each name should be checked against
   `~/.cargo/registry/src/*/polars-*-0.54.4/Cargo.toml`, plus a grep for `"activate .* feature"`
   under the registry source, per `CLAUDE.md`'s warning that a feature on the `polars` facade is not
   that feature on each sub-crate.
