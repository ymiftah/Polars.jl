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

A further pass closed the frame-level reductions and the top-level row-count constructor:

- **Top-level `len()`** ([Group 2](#group-2--missing-top-level-functions-pl) and
  [Group 3](#group-3--missing-expr-methods)) — one new zero-arg `polars_expr_len` FFI symbol
  wrapping `polars_plan::dsl::functions::len()`, ungated. Output column named `"len"`, matching
  upstream; includes `null`s, distinct from [`Polars.count`](@ref).
- **Frame-level `sum`/`mean`/`min`/`max`/`median`/`std`/`var`/`quantile`**
  ([Group 6](#group-6--missing-frame-level-dataframelazyframe-methods)) — eight new
  `polars_lazy_frame_*` FFI symbols wrapping the genuine `LazyFrame::sum`/etc methods
  (`polars-lazy-0.54.4/src/frame/mod.rs`), ungated. **Deliberately not** composed from
  `select(df, wildcard.sum())` the way `fill_null`/`cast` above were — verified live that the two
  shapes disagree: upstream's own methods are null-tolerant per column (e.g. a `String` column
  sums to `null`), matching py-polars' `DataFrame.sum()` etc (which delegate to
  `self.lazy().sum()`), whereas the wildcard-`select` composition raises `PolarsError` on the first
  unsupported dtype instead.
- **Frame-level `prod`** (same Group 6 entry) — has no Rust-side `LazyFrame::product` to wrap at
  all (verified absent from that same file); py-polars' own `DataFrame.product()` is pure-Python,
  branching per column dtype (`numeric` or `Bool` → product, else → `null`) — that's what this
  composes instead, via `with_columns` + the pre-existing per-`Expr` `Base.prod`, no new FFI
  symbol.

Also corrects a claim in [`gap_closure_scope.md`](gap_closure_scope.md)'s Group B3 (now itself
annotated): `strict_cast` was never actually a gap by the time that file's "expose as `cast(expr,
T; strict=false)`" suggestion was written up here — `cast(expr, dtype; strict=true)` already
dispatches to `polars_expr_strict_cast` (`src/expr/expr.jl`, `_plain_value_type_code`'s call site).

**2026-09-01 update.** [`tier12_low_hanging_parity.md`](tier12_low_hanging_parity.md) closed the
entire no-Cargo-change remainder identified by a fresh triage of Groups 2, 3, 4, and 6: seven
frame-level verbs (`limit`, `Base.reverse`, `null_count`, `Base.count`, `fill_nan`, `explain`,
`cache`), eleven `Expr` methods (`arctan2`, `dot`, `entropy`, `arg_unique`, `to_physical`,
`lower_bound`, `upper_bound`, `extend_constant`, `shuffle`, `Base.reshape`,
`Strings.escape_regex`), three top-level functions (`format`, `concat_arr`, plus the temporal
constructors `datetime`/`duration`/`date`/`Base.time`/`from_epoch`), and `Dt.to_string`. No
`Cargo.toml` change was needed for any of it — every symbol was reachable under features already
enabled — so this closure needs no new `libpolars` artifact release. Cost: four commits over five
tasks, all live-verified before their tests were written per `CLAUDE.md`'s workflow, each with its
own plan-file correction where the live behavior diverged from what was assumed going in (recorded
in [`tier12_low_hanging_parity.md`](tier12_low_hanging_parity.md) itself rather than repeated here
in full). The findings worth carrying forward:

- **`LazyFrame::count()` counts non-null values per column, not rows.** Confirmed with a
  fully-`missing` 3-row column, which reports `count == 0`. So `count` and `null_count` are
  complementary — `count(df).a + null_count(df).a == nrow(df)` — not redundant as the pre-closure
  Group 6 text implied by listing them side by side with no distinction drawn.
- **`Expr::reshape`'s `-1` placeholder is only inferred in the *first* dimension.**
  `reshape(col("x"), -1, 2)` works; `reshape(col("x"), 2, -1)` raises `PolarsError("can only infer
  the first dimension")`. Not previously documented anywhere in this repo.
- **Array-dtype columns are less broken than Group 5's `.arr` entry said.** `collect` on a plan
  containing a `reshape`/`concat_arr`-built `Array` column succeeds — the failure is specifically
  in the Arrow *schema* path (`collect_schema`, `Polars.schema`, indexing a collected `Array`
  column), which raises a plain `ErrorException` (not `PolarsError`) from
  `src/arrow/schema.jl:136`'s `parse_format`, which doesn't recognize the fixed-size-list Arrow
  format (`"+w:N"`). Group 5's `.arr` row above is updated to reflect this.
- **`Dt.to_string` needed no new FFI symbol.** `polars-plan-0.54.4/src/dsl/dt.rs`'s
  `DateLikeNameSpace::strftime` is defined as `self.to_string(format)` — the same upstream method
  under two names, not two capabilities — and `strftime` was already wrapped as
  `polars_expr_dt_strftime`. `Dt.to_string` is a plain Julia-level alias over that existing
  binding, honoring `CLAUDE.md`'s "one new symbol per capability" principle by adding zero symbols.
- **`format` coexists with the internal `format(T)` in `src/arrow/array.jl` with no new
  ambiguity.** `Aqua.detect_ambiguities` reports 46 ambiguities before and after this change,
  checked in the same session by stashing and re-running — an exact match, not just "no crash."
- **`Base.time` needed an Aqua carve-out.** Its whole point (`time(9, 30)` on bare scalars) means
  none of its methods has an argument of this package's own type, which is what every other
  `Base.*` extension here relies on to not be piracy — `test/aqua.jl` whitelists it via
  `piracies = (treat_as_own = [Base.time],)`, the exact shape Aqua's own docs recommend for a
  lightweight C-wrapper package adding scalar-taking convenience functions.

Also closed, independently discovered while executing that plan: `docs/src/reference/functions.md`
had no `@docs` entry for `concat_str`/`concat_list` at all (added by PR #46, this branch's base),
which had silently forced two `@ref` links in `format`'s and `concat_arr`'s own docstrings down to
plain backticks to avoid a docs-build failure. Both are now in the same `@docs` block as
`format`/`concat_arr`, and the two downgraded links are restored to `@ref`.

**2026-09-01, same day: `pypolars-test-parity` sweep of everything the above added.** The tests
written alongside those 25 functions were derived from *live-observed behavior of this
implementation* rather than from upstream fixtures -- the exact anti-pattern
`.claude/skills/pypolars-test-parity/` exists to prevent, since such a test pins whatever we
already do and can never detect that we diverge from polars. All 25 were re-swept against upstream's
own fixtures in four batches, each with its own note:
[frame verbs](tier12-sweep-frame-verbs.md), [Expr math](tier12-sweep-expr-math.md),
[Expr manipulation](tier12-sweep-expr-manipulation.md), [temporal/top-level](tier12-sweep-temporal.md).
Test count went 3116 -> 3304 (+188) with 4 -> 6 `@test_broken`.

The sweep paid for itself: **three user-visible wrong answers and one shape divergence that the
original tests all passed against.**

- **`from_epoch` silently truncated sub-second precision** -- `:s`/`:ms` scaled to `Datetime(:ms)`
  instead of upstream's x1,000,000/x1,000-then-`Datetime(:us)`, losing five digits on upstream's own
  fractional-second fixture (`-609066.723456` gave `.277`, not `.276544`). Fixed in
  `src/expr/ranges.jl`; a `String` input at `:s`/`:ms` now raises `PolarsError` rather than silently
  becoming `missing`.
- **`date`/`Base.time` never aliased their output column** -- both compose over `datetime`, whose
  output is always named `"datetime"`; upstream's `pl.date`/`pl.time` rename to `"date"`/`"time"`.
  Fixed.
- **`null_count`/`count` on a 0-column frame** return shape `(0,0)` here vs upstream's `(1,0)`. Ours
  are `collect .∘ verb .∘ lazy` and so hit `LazyFrame::null_count()`, while py-polars' eager
  `DataFrame.null_count()` uses a different binding that special-cases zero columns. Rust-side, not
  a marshalling bug -- 2 `@test_broken` in `test/operations/frame_verbs.jl`.
- **`datetime`'s output column is always named `"datetime"`**, never the left-hand argument's name.
  The vendored `polars-plan` 0.54.4 source carries a `// TODO: follow left-hand rule in Polars 2.0`
  for exactly this -- upstream behavior, not ours; 2 `@test_broken`.

Non-bugs worth recording, each verified against upstream source rather than assumed: `arctan2` on a
String column non-strictly casts to `Float64` rather than raising (upstream's own
`arctan2_on_columns` dispatch does this, same shape as `cbrt`'s already-recorded behavior);
`reshape`'s `-1` is inferrable only in the first dimension **upstream too**; `shuffle` reproduces
upstream's pinned permutation bit-for-bit at `seed=1`; `entropy`'s `base`/`normalize` defaults match
upstream's documented value exactly. `reshape(expr)` with zero dimensions panics inside
`polars-plan`'s schema resolution but is caught by `guard_error` and surfaces as a clean
`PolarsError` -- the FFI panic-safety net working as designed, now pinned by a test.

Two API divergences recorded rather than closed (Step 8): there is no top-level
`escape_regex(::AbstractString)` (only the `Expr`-level `Strings.escape_regex`; upstream keeps
`pl.escape_regex` and `Expr.str.escape_regex` separate), and `dot`/`arctan2` take a Julia `String`
as a string *literal* rather than as `col(name)` -- pre-existing package-wide
`gen_impl_expr_binary!` convention, not new.

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

**Temporal constructors** — ~~`date()`, `datetime()`, `time()`, `duration()`, `from_epoch`~~
**Closed** (see [Status](#status)). Note `cast_datetime`/`cast_duration` exist but are *casts*, not
constructors from component expressions.

**String and list combination** — ~~`concat_str`, `concat_list`~~ **Closed** (see [Status](#status)).
~~`concat_arr`, `format`~~ **Closed** (see [Status](#status)). `Strings.join`/`Lists.join` are the
*aggregating* joins, distinct from the row-wise horizontal `concat_str`/`concat_list`.
(`format` coexists with the internal `format(T)` in `src/arrow/array.jl:90` — the
Julia-type-to-Arrow-format mapping — with no dispatch ambiguity; see [Status](#status).)

**Reductions and folds** — `fold`, `reduce`, `cum_fold`, `cum_reduce`, `cum_sum_horizontal`,
`approx_n_unique`. ~~`len`~~ **Closed** (see [Status](#status)).

**Selection and ordering** — ~~`exclude`~~ **Closed** (see [Status](#status)); `arg_where`,
`arg_sort_by`. **`arg_where` is gated behind Cargo's `arg_where` feature** — absent from
`c-polars/Cargo.toml`'s current feature list and from [Group 10](#group-10)'s table below, which
was therefore itself incomplete; do not add it without batching the Cargo change per `CLAUDE.md`.

**Windowed correlation** — `rolling_corr`, `rolling_cov`. (Scalar `cov`/`cor` and
`spearman_rank_corr` do exist, in `src/expr/statistics.jl`.)

**Math** — ~~`arctan2`~~ **Closed** (see [Status](#status)). **Business calendar** —
`business_day_count`. **SQL** — `sql_expr`.

> Present, for contrast: `col`, `nth`, `lit`, `element`, `when`, `coalesce`, `as_struct`,
> `all_horizontal`, `any_horizontal`, `min_horizontal`, `max_horizontal`, `sum_horizontal`,
> `mean_horizontal`, and frame `concat`.

## Group 3 — Missing `Expr` methods

**Aggregations and reductions**: `mode`, ~~`entropy`~~ **Closed** (see [Status](#status)),
`unique_counts`, `approx_n_unique`, `arg_true`, ~~`arg_unique`~~ **Closed** (see [Status](#status)),
~~`dot`~~ **Closed** (see [Status](#status)), and the per-`Expr` aggregation form of `len`
(`expr.len()`, distinct from
`count`, which exists and skips nulls -- also distinct from the now-closed top-level `pl.len()`,
see [Status](#status), which this Group 3 row does not cover: `expr.len()` would need its own
`gen_impl_expr!(polars_expr_len_agg, Expr::len)` under a name that doesn't collide with the
top-level constructor's own `polars_expr_len` symbol; not attempted here since the top-level form
covers the overwhelmingly more common `group_by(...).agg(len())`/`select(len())` idiom), and the
bitwise reductions (`bitwise_and`, `bitwise_or`, `bitwise_xor`, `bitwise_count_ones`,
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
~~`lower_bound`, `upper_bound`~~ **Closed** (see [Status](#status)), `rolling_skew`,
`rolling_kurtosis`, `rolling_map`, every temporal `rolling_*_by` variant (`rolling_mean_by`,
`rolling_sum_by`, …), `ewm_mean_by`, `interpolate_by`.

**Manipulation**: ~~`extend_constant`~~ **Closed** (see [Status](#status)), `repeat_by`,
~~`reshape`, `shuffle`~~ **Closed** (see [Status](#status)), `round_sig_figs`, `shrink_dtype`,
~~`to_physical`~~ **Closed** (see [Status](#status)), `reinterpret`, `hist`, `is_close`.
**`is_close` is gated behind Cargo's `is_close` feature** — like `arg_where` above, absent from
`c-polars/Cargo.toml` and from [Group 10](#group-10)'s table; needs a batched Cargo change, not a
thin wrapper.

**Math**: ~~`cbrt`, `cot`, `arcsinh`, `arccosh`, `arctanh`~~ **Closed** (see [Status](#status)).
(`sin`, `cos`, `tan`, `sinh`, `cosh`, `tanh`, `arcsin`, `arccos`, `arctan`, `degrees`, `radians`,
`exp`, `log`, `log10`, `log1p`, `sqrt`, and `sign` all exist too.)

**UDFs**: `map_elements`, `map_batches` — blocked on [Group 9](#group-9).

## Group 4 — Gaps inside existing namespaces

### `Strings` (upstream `.str`)

`json_decode`, `json_path_match`, `to_decimal`, `to_time`, `strptime` (the generic form — `to_date`
and `to_datetime` cover two of its three targets), `decode`/`encode` (base64/hex), `contains_any`,
`replace_many`, `find_many`, `extract_many`, ~~`escape_regex`~~ **Closed** (see [Status](#status)),
`normalize`. Plus `to_integer`, `reverse`, and `titlecase` from
[Group 0](#group-0--explicit-unavailable-in-this-build-stubs-6).

### `Dt` (upstream `.dt`)

~~Missing **sub-second component extraction — `microsecond`, `millisecond`, `nanosecond`.**~~
**Closed** (see [Status](#status)) — each is the sub-second part of the timestamp expressed at
that unit's own resolution (not a decomposed digit group), mirroring the `total_*` family's own
scaling convention; only works on `Datetime`/`Time`, not a plain `Date`
(`` `nanosecond` operation not supported for dtype `date` ``, verified live).

~~Also: `iso_year`, `is_leap_year`, `century`, `millennium`, `combine`, `datetime`, `cast_time_unit`,
`with_time_unit`, `base_utc_offset`, `dst_offset`, `dt.replace` (replacing date components)~~ **All
closed** (PR #45, see [Status](#status)). Still missing: `add_business_days` (genuinely
Cargo-gated, see [Group 10](#group-10)). ~~`to_string`~~ **Closed** (see [Status](#status)) — a
plain Julia-level alias of the already-wrapped `strftime`, no new FFI symbol; see that entry for
why. Plus `month_start`/`month_end` from Group 0.

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
| **`.arr` (Array / fixed-size list)** | The whole namespace. `Lists.to_array`, `reshape`, and `concat_arr` all exist and `dtype-array` is enabled, so Array columns can be *created* — and, sharpened by this effort's live testing (see [Status](#status)): building the plan **and `collect`ing it both succeed**, so materialization itself is not the blocker as earlier text here implied. What actually fails is the Arrow *schema* path specifically — `collect_schema`, `Polars.schema`, and indexing an `Array` column of an already-collected `DataFrame` all raise a plain `ErrorException` (not `PolarsError`) from `src/arrow/schema.jl:136`'s `parse_format`, which doesn't recognize the fixed-size-list Arrow format (`"+w:N"`). Nothing else operates on Array columns either, and there is no write-side path for building one from Julia data. |

## Group 6 — Missing frame-level (`DataFrame`/`LazyFrame`) methods

The complete frame FFI surface is 33 `polars_lazy_frame_*` + 16 `polars_dataframe_*` symbols.

**Row/column selection**: ~~`slice`~~, ~~`limit`~~ **Closed** (see [Status](#status)),
~~`reverse`~~ **Closed** (see [Status](#status)), `sample`, ~~frame-level `top_k`/`bottom_k`
(the `Expr` forms exist)~~, `partition_by` (distinct from the sink-side `PartitionByKey`),
`insert_column`, `replace_column`, `drop_in_place`, `extend`, `clear`. `slice`/`top_k`/`bottom_k`
are **closed** (see [Status](#status)); `limit` is a plain alias for `head` upstream, matching the
same relationship at the `Expr` level.

**Whole-frame computation**: ~~frame-level `fill_null`~~, ~~`fill_nan`~~ **Closed** (see
[Status](#status)), `interpolate`, ~~`cast` (dtype mapping)~~, ~~`null_count`~~ **Closed** (see
[Status](#status)), ~~`count`~~ **Closed** (see [Status](#status)), `approx_n_unique`,
`to_dummies`, `corr`, and ~~the frame-level aggregations
`sum`/`mean`/`min`/`max`/`median`/`std`/`var`/`product`/`quantile`~~. `fill_null`/`cast`
are **closed** (see [Status](#status)) — `cast` covers both upstream's per-column `AbstractDict`
form and its single-`Type` whole-frame form (only plain, parameter-free dtypes reach the latter,
same restriction as the single-`Expr` `cast`). The frame-level aggregations are **closed** too (see
[Status](#status)): `sum`/`mean`/`min`/`max`/`median`/`std`/`var`/`quantile` wrap genuine
`LazyFrame` methods (null-tolerant per column, not the naive `select(df, wildcard.sum())` that
raises instead); `product` has no such upstream Rust method and is composed per-column like
py-polars' own pure-Python `DataFrame.product()`. `null_count`/`count` are also now **closed** (see
[Status](#status)) as genuine `LazyFrame` methods, distinct from each other in a way that turned
out to matter: `count()` counts non-null values per column (same semantics as the per-`Expr`
`count`), not the row count including nulls, so the two are complementary rather than redundant.
`approx_n_unique`/`to_dummies`/`corr` remain open — still only reachable via
`select(df, ...(col("*")))` (`corr` additionally needs two named columns, not a single wildcard).

**Joins**: `join_where` (inequality/IE join), `merge_sorted`, `update`. **Reshaping**: `unstack`.

**Introspection and plumbing**: ~~`explain`~~ **Closed** (see [Status](#status)), `profile`,
~~`cache`~~ **Closed** (see [Status](#status)), `set_sorted`, `with_context`,
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
- ~~**No join variant accepts `maintain_order`**~~ **Closed**: `innerjoin`/`leftjoin`/`rightjoin`/
  `outerjoin`/`semijoin`/`antijoin`/`crossjoin`/`join_asof` all now accept
  `maintain_order::Symbol=:none` (`:none`/`:left`/`:right`/`:left_right`/`:right_left`), threaded
  through a new `polars_maintain_order_join_t` FFI enum into `JoinArgs::maintain_order`
  (`c-polars/src/types.rs`, `dataframe.rs`) — the same `JoinArgs` struct whose other fields
  (`suffix`/`coalesce`/`validation`/`nulls_equal`) were already threaded through above, this field
  had simply been missed. Live-verified `crossjoin`'s left-major/right-major ordering matches
  upstream's own iteration pattern exactly, and `innerjoin(...; maintain_order=:left)` preserves
  the left frame's key order against an out-of-order right frame.
- ~~**`drop` has no `strict` keyword**~~ **Closed**: `drop(df, columns; strict=true)` now matches
  `rename`'s existing convention — `strict=false` silently ignores an unknown column instead of
  raising. `LazyFrame::drop` already took a `Selector::ByName { names, strict }`; the FFI shim
  (`polars_lazy_frame_drop`) had simply hardcoded `strict: true` with no parameter to control it.
- `rolling_*` accept `window_size`/`min_samples`/`center` but have no `by`/`closed` temporal form.
- `describe` is `DataFrame`-only (upstream also has it on `LazyFrame`). `pivot`, `transpose`,
  `hstack`, `vstack`, and `upsample` being `DataFrame`-only matches upstream.
- **No join variant accepts `maintain_order`** (confirmed live, Batch 11 of the test-parity
  sweep — `crossjoin(a, b; maintain_order=:left)` is a plain `MethodError`, and `maintain_order`
  doesn't appear anywhere in `c-polars/src/*.rs`'s join-related code at all, unlike the
  `group_by`/`unique`/sort family closed above). Upstream's `JoinArgs`/`.join(maintain_order=...)`
  covers every join type, not just cross joins (`test_cross_join_maintain_order_24663`); a
  Rust-side fix here would need the same "closed" treatment `group_by`/`unique` already got —
  out of scope for a no-Cargo-change batch.

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

Per [`LEDGER.md`](LEDGER.md), **the full py-polars parity sweep (batches 0-14) is now complete** —
findings below.

**So this audit is not the final list.** It is the static view — what has no binding at all. The
unswept batches are the behavioural view: what has a binding that does the wrong thing. Expect the
latter to add entries.

`LEDGER.md` also carries three known hygiene problems: its batch-order table still says `unswept`
for batches 1-7 (all merged), the 211-row per-function table is entirely stale, and its `## Status`
preamble still describes a pre-sweep baseline.

**Batch 10 findings** (`operations/frame_verbs.jl`, `reshape.jl`, `concat.jl`,
`select_with_columns.jl`, `filter.jl` vs. 11 upstream files — see
`plans/parity/batch-10-frame-verbs.md`): four confirmed behavioural divergences, all `@test_broken`
or documented in place rather than fixed, since none are reachable without a Rust/FFI change or are
outside this batch's no-Cargo-change scope:

- **`drop(df, ["*"])` doesn't wildcard-drop every column.** Upstream's `.drop("*")` drops all
  columns (shape `(n, 0)`); this wrapper calls `Selector::ByName` with the literal string `"*"`,
  which isn't a real column name, so it raises `ColumnNotFoundError`-equivalent instead. Fixing it
  would mean special-casing `"*"` in `drop`'s Julia wrapper (resolving it to `names(df)` first) —
  plausible as a follow-up, not attempted here to avoid scope creep into a "new capability" during
  a test-porting pass.
- **`drop_nulls(df, subset)`'s explicitly-empty `subset` is not a no-op**, unlike upstream's
  `subset=[]`. Root cause: `c-polars/src/ffi_util.rs::selector_by_name_opt` collapses an empty name
  list to `None` ("no subset specified" = check all columns) rather than `Some(vec![])` ("check
  zero columns" = no-op) — the two are indistinguishable once both become an empty Julia `Vector`.
  `drop_nulls`'s docstring now documents this; fixing it for real needs a Rust-side way to pass
  "explicitly none" separately from "unspecified", which is a real signature change.
- **`concat([schemaless_df, ...])` fails where upstream succeeds**, specifically for a genuinely
  0-column frame (`DataFrame(NamedTuple())`) mixed with a real one — `pl.concat` treats a 0-column
  input as vacuously compatible with any schema; this wrapper's `:vertical` passes every frame
  straight to the Rust `concat`/`union` primitive, which enforces exact schema equality with no
  such special case. A 0-row-but-typed frame (a real schema, just no rows) concats fine either
  order — confirmed live, only the *columnless* case diverges. A Julia-side pre-filter (drop any
  0-column frame from the list before the FFI call, for `:vertical`/`:vertical_relaxed`) would
  likely fix this without touching Rust, but wasn't attempted here — same "don't add capability
  mid-sweep" reasoning as `drop`'s wildcard above.
- **`transpose` on any 0-row frame raises, where the current upstream *main* branch's test suite
  expects it to succeed** (`pl.DataFrame(schema={"a": Int32, "b": Int32}).transpose().shape ==
  (2, 0)`). Live-verified against this repo's vendored `polars-plan`/`polars-core` 0.54.4: `no
  data: unable to transpose an empty DataFrame` is raised unconditionally, so this is a genuine
  Rust-crate-version-pinned gap between 0.54.4 and whatever newer polars-rust version the current
  py-polars main branch's tests are written against — not fixable without an artifact bump. The
  existing test (`test/operations/reshape.jl`'s `"transpose"` testset) already asserted this
  correctly; this sweep just confirmed it against the real upstream test name
  (`test_transpose_empty`) instead of an untraced assumption.

**Also found, not a parity gap**: `drop` has no `strict` keyword at all (upstream's
`drop(..., strict=False)` silently ignores an unknown column name instead of raising) — the
underlying `polars_lazy_frame_drop` FFI function hardcodes `Selector::ByName { strict: true, .. }`
with no parameter to control it, unlike `rename`'s already-threaded `strict`. Needs a Rust
signature change to add, out of scope here; add to a future no-Cargo-change batch alongside a
frame-level `drop_nans` (`Expr`-level `drop_nans` exists in `src/expr/aggregation.jl`, but there is
no `DataFrame`/`LazyFrame` form the way `drop_nulls` has both — confirmed via `MethodError` live).

**Also found, unrelated to this batch's own changes**: a fresh `origin/main` checkout's full test
suite currently errors on at least 8 pre-existing testsets (`fill_null`/`cast`/frame-level
aggregations in `frame_verbs.jl`; `top_k`/`bottom_k`/`slice` in `sort.jl`; `len` in
`expr/aggregation.jl`; `concat_str`/`concat_list` in `expr/horizontal.jl`) with `could not load
symbol "polars_lazy_frame_..."` / `undefined symbol` from `libpolars.so`. This is the exact hazard
`CLAUDE.md`'s generation-pipeline section describes: `src/api/generated.jl` on `main` already
references FFI symbols (`polars_lazy_frame_fill_null`, `_cast_all`, `_sum`, and others) that
aren't in the currently-published `Artifacts.toml`-pinned `libpolars.so` binary — some `c-polars`
change landed without a corresponding new artifact release. Confirmed unrelated to this batch: none
of these functions or their tests were touched here, and running just this batch's own new/changed
testsets in isolation (bypassing the broken ones) shows 285 passed, 0 failed, 3 broken (exactly the
three divergences above) — so this is a pre-existing, repo-wide infrastructure gap, not something
introduced by this sweep. Worth a `c-polars/check_header_drift.py --lib PATH` run and a fresh
artifact release; out of scope for this PR.

**Batch 12 findings** (`datatypes/series.jl`, `binary.jl`, `dataframe/construction.jl`, `io.jl`,
`describe.jl` vs. `series/test_series.py`, `test_getitem.py`, `test_to_list.py`,
`dataframe/test_df.py`, `test_shape.py`, `test_describe.py`, `datatypes/test_binary.py`,
`test_null.py`, `constructors/test_constructors.py` — see
`plans/parity/batch-12-series-dataframe.md`): **one real bug fixed** and two divergences/gaps
recorded:

- **`describe`'s fractional-percentile labels were wrong, and are now fixed.** `percentiles=[0.99,
  0.999, 0.9999]` previously labeled the last two rows both `"100%"` (`round(Int, q*100)` truncates
  all fractional precision), silently colliding two distinct statistic rows under one ambiguous
  label. Fixed in `src/describe.jl` to preserve fractional precision (`"99.9%"`, `"99.99%"`) only
  when the percentage isn't a whole number, matching `test_df_describe_quantile_precision`'s
  expected labels exactly. This is a Julia-side label-formatting bug, not an FFI gap — confirmed
  fixed live and covered by a new test in `test/dataframe/describe.jl`.
- **`describe` on a genuinely columnless (0-row, 0-column) frame doesn't raise here**, where
  upstream raises `TypeError: cannot describe a DataFrame that has no columns`. This wrapper
  instead returns a `(9, 1)` frame containing only the `statistic` column. `@test_broken` in
  `test/dataframe/describe.jl`; not fixed here since it would need `describe` to validate
  `size(df, 2) == 0` up front and raise something upstream-shaped, which is a small but real
  behavior change to a widely-used function's error path, better done as its own reviewed change
  than folded into a test-porting pass.
- **No `eq_missing`/`ne_missing` `Expr` methods, and no `hash_rows`/`Series`/`Expr` `hash`** —
  confirmed absent via `grep` (not just untested): upstream's null-aware equality variants
  (`eq_missing`: `null == null` is `true`, unlike plain `==`'s null-propagating `missing`) and its
  row/column hashing family have no binding at all here. Feature-gate status not yet checked
  against the vendored `polars-plan`/`polars-ops` source; flagging for a future no-Cargo-change
  batch to scope properly rather than guessing here.

**Batch 13 findings** (`lazyframe/scan_*.jl`, `sink_*.jl`, `collect_schema.jl`, `head.jl` vs.
`io/test_csv.py`, `test_ipc.py`, `test_lazy_csv.py`, `test_lazy_ipc.py`, `test_lazy_parquet.py`,
`test_parquet.py`, `test_scan_options.py`, `test_sink.py`, `lazyframe/test_collect_schema.py` —
combined ~13,700 lines, two files over 3000 lines each; triaged via `grep` for named-regression
tests given the scale — see `plans/parity/batch-13-io-lazyframe.md`): **one real bug fixed**:

- **`head(df, n)`/`tail(df, n)` crashed with a bare `InexactError` on a negative `n`**, instead of
  either supporting it or rejecting it cleanly. The underlying `polars_lazy_frame_head`/`_tail` FFI
  functions take an unsigned `usize`; upstream's own Python-level `.head(n=-2)` negative-index
  convenience (`height + n`) is implemented in Python before ever reaching Rust, so it was never
  ported here — but the missing case fell through to an unguarded `@ccall` type-coercion failure
  rather than a clear rejection. Fixed with an explicit `n >= 0` check raising a descriptive
  `ArgumentError` in both `head` and `tail` (`src/select.jl`); negative-`n` support itself remains
  unimplemented (would need `DataFrame`'s known height, straightforward, vs. `LazyFrame`'s
  unknown height without materializing, not straightforward) and is not attempted here.

**Batch 14 findings** (`expr/selectors.jl`, `meta.jl`, `horizontal.jl`, `naming.jl`, `sample.jl`,
`curried_forms.jl`, `misc.jl` vs. `operations/test_selectors.py`,
`operations/namespaces/test_meta.py`, `expr/test_meta.py`, `operations/namespaces/test_name.py`,
`functions/test_horizontal.py`, `operations/aggregation/test_horizontal.py`,
`operations/test_random.py`, `functions/test_col.py`, `functions/test_nth.py` — see
`plans/parity/batch-14-selectors-misc.md`): 2 fixtures ported (a third, initially misdiagnosed as a
gap, turned out to already work — see the correction below), 2 gaps recorded:

- **`Meta` is missing `is_scalar`, `is_known_length`, `is_row_separable`, `is_length_preserving`,
  and `eq`** — confirmed absent via `grep` across `src/expr/meta.jl` while porting
  `expr/test_meta.py`'s `test_meta_properties`/`test_meta_eq_tot_cmp_28469`. Every other `Meta`
  introspection method this repo already has (`output_name`, `is_column`, `is_literal`,
  `has_multiple_outputs`, `root_names`, `undo_aliases`, `tree_format`, `show_graph`) has a
  corresponding upstream `expr.meta.*` counterpart; these five don't yet.
- **`nth` has no multi-argument or vector form.** Upstream's `pl.nth(2, 1)` and `pl.nth([2, -2,
  0])` both select several columns in one call; this wrapper's `nth(n)` takes exactly one integer
  (`src/expr/expr.jl`). A minor but real surface gap — every other multi-column selector
  (`by_name`, `by_index`) already accepts varargs.
- **No frame-level `sample`** — only the `Expr`-level `sample_n`/`sample_frac` exist; upstream's
  `DataFrame.sample()`/`LazyFrame`-adjacent convenience has no counterpart here.

**Correction (found while scoping a follow-up kwarg-gap PR): the "no `shuffle` on `sample_n`/
`sample_frac`" claim above was wrong.** It was based on `grep`-ing only `src/expr/expr.jl`; the
functions actually live in `src/expr/statistics.jl`, which already has `shuffle::Bool=false`
threaded all the way through to `polars_expr_sample_n`/`_sample_frac` (both already take a
`shuffle: bool` FFI parameter). Live-verified: `sample_n(col("a"), 3; shuffle=false, seed=...)`
(no `with_replacement`) already preserves row order exactly like upstream, across ten seeds.
Fixed by porting the actual upstream fixture (`test_sample_no_shuffle_preserves_order_23557`) into
`test/expr/sample.jl` instead of leaving the false gap claim standing.

That upstream test has a `with_replacement=True` sibling
(`test_sample_no_shuffle_with_replacement_preserves_order_23557`) which does **not** port cleanly:
it exercises `DataFrame.sample()` (the gap just added above), not `Expr.sample_n`, and
live-verified `Expr.sample_n(...; shuffle=false, with_replacement=true)` does not preserve order
here (arbitrary draw order across ten seeds) — a real behavioral difference between the two
functions, not a bug in `Expr.sample_n` itself. Documented as a narrow finding in
`test/expr/sample.jl` rather than conflated with either the fixture above or the missing-`sample`
gap.

## Caveats

1. ~~The `Selectors.array()` staleness claim (Group 0).~~ **Resolved** — closed on `main`, see
   [Status](#status).
2. **Feature-name accuracy in [Group 10](#group-10).** Each name should be checked against
   `~/.cargo/registry/src/*/polars-*-0.54.4/Cargo.toml`, plus a grep for `"activate .* feature"`
   under the registry source, per `CLAUDE.md`'s warning that a feature on the `polars` facade is not
   that feature on each sub-crate.
