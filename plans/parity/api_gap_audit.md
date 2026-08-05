# Polars.jl API gap audit: full inventory of what's missing vs py-polars

## Status

**Audit complete; no gaps closed.** This file is a static inventory, not an implementation plan —
nothing under `src/` or `c-polars/` was changed to produce it. Two of its claims are explicitly
marked as needing a live check before anyone acts on them (see [Caveats](#caveats)).

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

**String and list combination** — `concat_str`, `concat_list`, `concat_arr`, `format`.
`Strings.join` exists as the *aggregating* (vertical) join; the row-wise horizontal concat does not.
(`format` is defined in `src/arrow/array.jl:90`, but that is the internal Julia-type-to-Arrow-format
mapping — unrelated to `pl.format`, and a name collision to watch when adding the real one.)

**Reductions and folds** — `fold`, `reduce`, `cum_fold`, `cum_reduce`, `cum_sum_horizontal`,
`approx_n_unique`, `len`.

**Selection and ordering** — `exclude`, `arg_where`, `arg_sort_by`.

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

**Selection within an expression** — the most-felt group, since these are the standard idioms inside
`agg`. None has a plain `polars_expr_*` symbol:

- **`filter`** — only `polars_lazy_frame_filter` exists; there is no `polars_expr_filter`.
- **`sort`** — `sort_by` exists; sorting an expression's *own* values does not.
- **`head`, `tail`, `slice`, `get`, `limit`** — note `head`/`tail`/`slice` *do* exist inside the
  `Lists` and `Strings` namespaces (`polars_expr_list_head`, `polars_expr_str_slice`, …); it is the
  plain `Expr` forms that are absent. `gather` covers the vector case of `get`; there is no scalar
  `get`.
- **`top_k_by`, `bottom_k_by`** — plain `top_k`/`bottom_k` do exist.
- **`Expr.explode` is *not* a gap** — it is covered by `flatten` (`src/expr/expr.jl:681`, calling
  `polars_expr_flatten`), which is upstream's own alias for it.

**Window and ordering**: `cumulative_eval`, `peak_min`, `peak_max`, `search_sorted`, `set_sorted`,
`lower_bound`, `upper_bound`, `rolling_skew`, `rolling_kurtosis`, `rolling_map`, every temporal
`rolling_*_by` variant (`rolling_mean_by`, `rolling_sum_by`, …), `ewm_mean_by`, `interpolate_by`.

**Manipulation**: `extend_constant`, `repeat_by`, `reshape`, `shuffle`, `round_sig_figs`,
`shrink_dtype`, `to_physical`, `reinterpret`, `hist`, `is_close`.

**Math**: `cbrt`, `cot`, `arcsinh`, `arccosh`, `arctanh`. (`sin`, `cos`, `tan`, `sinh`, `cosh`,
`tanh`, `arcsin`, `arccos`, `arctan`, `degrees`, `radians`, `exp`, `log`, `log10`, `log1p`, `sqrt`,
and `sign` all exist.)

**UDFs**: `map_elements`, `map_batches` — blocked on [Group 9](#group-9).

## Group 4 — Gaps inside existing namespaces

### `Strings` (upstream `.str`)

`json_decode`, `json_path_match`, `to_decimal`, `to_time`, `strptime` (the generic form — `to_date`
and `to_datetime` cover two of its three targets), `decode`/`encode` (base64/hex), `contains_any`,
`replace_many`, `find_many`, `extract_many`, `escape_regex`, `normalize`. Plus `to_integer`,
`reverse`, and `titlecase` from [Group 0](#group-0--explicit-unavailable-in-this-build-stubs-6).

### `Dt` (upstream `.dt`)

Missing **sub-second component extraction — `microsecond`, `millisecond`, `nanosecond`.** Worth
calling out because the similarly-named *duration totals* (`total_microseconds`,
`total_milliseconds`, `total_nanoseconds`) all exist, which makes the components look present.

Also: `iso_year`, `is_leap_year`, `century`, `millennium`, `combine`, `datetime`, `cast_time_unit`,
`with_time_unit`, `base_utc_offset`, `dst_offset`, `dt.replace` (replacing date components),
`add_business_days`, `to_string`. Plus `month_start`/`month_end` from Group 0.

### `Lists` (upstream `.list`)

Nearly complete after the batch-9 gap closure. Missing: `concat`, and expression-level `explode`.
Two naming notes that are *not* gaps: upstream's `len` is spelled `lengths` here, and `eval`/`filter`
are reachable via `Lists.apply` (`src/expr/list.jl:370`), renamed because `eval` is a reserved
per-module name in Julia.

### `Structs` (upstream `.struct`)

Expression-level `unnest` (the frame-level verb exists), and field/schema introspection (`fields`,
`schema`).

### Name namespace (upstream `.name`)

`name.map` (needs a callback — Group 9), `prefix_fields`, `suffix_fields`. Present: `keep_name`,
`prefix`, `suffix`, `to_lowercase`, `to_uppercase`.

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

**Row/column selection**: `slice`, `limit`, `reverse`, `sample`, frame-level `top_k`/`bottom_k`
(the `Expr` forms exist), `partition_by` (distinct from the sink-side `PartitionByKey`),
`insert_column`, `replace_column`, `drop_in_place`, `extend`, `clear`.

**Whole-frame computation**: frame-level `fill_null`, `fill_nan`, `interpolate`, `cast` (dtype
mapping), `null_count`, `count`, `approx_n_unique`, `to_dummies`, `corr`, and the frame-level
aggregations `sum`/`mean`/`min`/`max`/`median`/`std`/`var`/`product`/`quantile` — all reachable today
only by rewriting as `select(df, mean(col("*")))`.

**Joins**: `join_where` (inequality/IE join), `merge_sorted`, `update`. **Reshaping**: `unstack`.

**Introspection and plumbing**: `explain`, `profile`, `cache`, `set_sorted`, `with_context`,
`glimpse`, `estimated_size`, `rechunk`, `is_empty`, frame-level `is_duplicated`/`is_unique`.

**Not real gaps**: `equals` (covered by `Base.==`, `src/dataframe.jl:159`), `pipe` (covered by `|>`),
and the whole row/dict iteration family (`iter_rows`, `rows`, `row`, `rows_by_key`, `iter_slices`,
`to_dict`, `to_dicts`, `to_series`) — `DataFrame` implements the Tables.jl interface, which is the
idiomatic Julia equivalent.

### Missing keyword arguments on functions that already exist

Called out separately because each function looks complete from the outside.

- **Joins carry no options at all.** `c-polars/src/dataframe.rs:699` passes
  `JoinArgs::new(how.to_join_type())` — every default. So no `suffix` (upstream defaults to
  `"_right"`), no `coalesce`, no `validate`, no `nulls_equal`/`join_nulls`, no `slice`.
- **`join_asof` hardcodes `tolerance: None`** (`c-polars/src/dataframe.rs:724`). Also no `allow_eq`,
  no `check_sortedness`.
- **`maintain_order` appears nowhere in the FFI** — so `group_by(maintain_order=)`, frame
  `unique(maintain_order=)`, and `Expr.unique(maintain_order=)` are all unavailable.
- `rolling_*` accept `window_size`/`min_samples`/`center` but have no `by`/`closed` temporal form.
- `describe` is `DataFrame`-only (upstream also has it on `LazyFrame`). `pivot`, `transpose`,
  `hstack`, `vstack`, and `upsample` being `DataFrame`-only matches upstream.

## Group 7 — Missing I/O

Present: Parquet, CSV, and IPC, each with read/scan/write/sink and a good option surface
(`src/io/`), plus cloud `storage_options` and partitioned parquet sinks.

- **JSON / NDJSON** — `read_json`, `read_ndjson`, `scan_ndjson`, `write_json`, `write_ndjson`,
  `sink_ndjson`. **The lowest-hanging item in this audit:** the `json` Cargo feature is *already
  enabled* (for `Structs.json_encode`), so this is plausibly shims-only, possibly plus `ndjson`.
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
7. **Six FFI symbols wrapped in Rust but never surfaced in Julia** — the cheapest wins in this file:
   `polars_dataframe_new_from_series`, `polars_dataframe_show`, `polars_expr_selector_empty`,
   `polars_series_type`, `polars_value_list_type`, `polars_value_time_zone`.

## Group 10

### Cargo features that would need enabling

Currently-enabled features are in `c-polars/Cargo.toml`. Per `CLAUDE.md` a feature change forces a
full optimized dependency rebuild (`-j 1`) plus a new `libpolars` release, so **these must be
batched into one change** — and a clean `cargo build` is never evidence a path is safe, so every new
option must be exercised live.

**Feature names in this table are unverified** — see [Caveats](#caveats).

| Feature | Unlocks |
|---|---|
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
| `ndjson` | NDJSON I/O (`json` is already on) |
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

Two claims here were derived by reading configuration rather than by running code, and should be
confirmed before anyone acts on them:

1. **The `Selectors.array()` staleness claim (Group 0).** Needs a `cargo build`, a REPL restart, and
   a call against a real Array-dtype column (via `Lists.to_array`) to confirm the selector *matches*
   rather than silently matching zero columns. The entire point of the existing guard is that a
   wrong answer here is **silent**, so this must not be taken on faith from reading `Cargo.toml`.
2. **Feature-name accuracy in [Group 10](#group-10).** Each name should be checked against
   `~/.cargo/registry/src/*/polars-*-0.54.4/Cargo.toml`, plus a grep for `"activate .* feature"`
   under the registry source, per `CLAUDE.md`'s warning that a feature on the `polars` facade is not
   that feature on each sub-crate.
