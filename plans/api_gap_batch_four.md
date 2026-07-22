# API gap batch four: long-tail triage from Phase 8 of the Definitive Guide gap-closure plan

## Status

Not started.

## Context

`plans/definitive_guide_gap_closure.md`'s Phase 8 ("Long tail — ~50 items: triage approach, not
per-function specs") deliberately deferred speccing its remaining named items to a follow-up plan
rather than fully speccing ~50 functions inline. This document is that follow-up, seeded from a
fresh research pass (not a copy of Phase 8's preliminary guesses — every item below was re-verified
against the actual vendored `polars` 0.54.4 sources and this repo's actual `cargo tree -e features`
output as of `features-round-2`, not the declared `Cargo.toml` feature list, per CLAUDE.md's
explicit warning that these two can diverge).

**Excluded — covered by `plans/analytics_gap_batch2.md`:** `rolling_mean`/`rolling_min`/
`rolling_max` (B1), `skew`/`kurtosis` (B4), `ewm_mean`/`ewm_std`/`ewm_var` (B5), `cut`/`qcut`/
`qcut_uniform` (B6). Re-checked that plan's status before writing this one: **still open, none of
these four items are implemented** (confirmed by grep — zero hits for `rolling_mean`, `skew`,
`ewm_mean`, `qcut`, etc. across `src/` and `c-polars/src/`). Execute `analytics_gap_batch2.md` for
those four rather than re-planning them here.

**One correction to that plan's own assumed-still-accurate state, noted for whoever picks it up
next:** `analytics_gap_batch2.md`'s B3 (`concat` diagonal/horizontal modes) **has since been
implemented** — outside that plan, in `914159c` ("API-gap batch (Tier A, no Cargo feature): ...
concat modes ..."), which added `concat(frames; how=:vertical|:vertical_relaxed|:diagonal|
:diagonal_relaxed|:horizontal)` directly (see `src/verbs.jl:126-145`). B3's own section in
`analytics_gap_batch2.md` is now stale; this doesn't affect this plan's exclusion list (B3 was never
one of Phase 8's long-tail items) but is worth a note in that file whenever someone next edits it.
Not fixed here per this task's explicit "do not touch `analytics_gap_batch2.md`'s own four items
beyond re-checking Status" instruction.

**Callback-blocked items — deferred to a separate plan, not covered here or in
`analytics_gap_batch2.md`:** `map_elements`/`map_batches`/`map_groups` (this document's own
research item) and `.name.map` (flagged but not solved back in `definitive_guide_gap_closure.md`
Phase 6). All four need the same missing piece: a Rust→Julia callback calling convention (the
*reverse* FFI direction from everything else in this codebase — see `plans/callback_infra.md`,
a short problem-statement stub written alongside this plan). No attempt is made to solve that
infrastructure here, per this task's explicit scope boundary.

### Research method (applied per item below)

1. Find the actual method in vendored `polars-{core,plan,lazy,ops,expr}-0.54.4` sources
   (`~/.cargo/registry/src/index.crates.io-*/`) and note exact file:line + signature.
2. Check its `#[cfg(feature = "...")]` gate, if any.
3. Run `cargo tree -e features -i <owning crate>` from `c-polars/` and grep the output for
   `<crate> feature "<name>"` lines to determine whether that feature is **already active** in this
   repo's actual build (as opposed to merely implied by the declared `features = [...]` list).
4. Two-pronged safety sweep on the function's actual execution path (not just its constructor):
   `grep -rn "activate .* feature"` across the touched crates, **and** a manual read of the
   `polars-expr` dispatch arm + any `unreachable!()`/`.unwrap()`/`.expect()` in a `#[cfg]`-gated
   match arm it reaches (the `dtype-time` precedent — no "activate" string exists for that failure
   mode, so the grep alone is not sufficient).
5. Bucket per the brief's 4 categories; see below for the actual buckets each item landed in.

## Cargo feature changes, at a glance

| Item(s) | Feature | Current status | Risk |
|---|---|---|---|
| `arccos`, `degrees`, `radians` | `trigonometry` | **already active** (already in `c-polars/Cargo.toml`'s `polars` feature list) | none |
| `log1p` | `log` | **already active** (ditto) | none |
| `log10` | *(none — pure Julia)* | n/a | none |
| `rle`, `rle_id` | `rle` | **already transitively active** (via `polars-stream`, pulled in by the `dtype-struct`→streaming-engine chain — confirmed by `cargo tree`, *not* by the declared list) | none functionally; add explicitly anyway (belt-and-suspenders, matching the `dtype-duration` precedent in Phase 3/5 of the parent plan) |
| `gather`, `gather_every` | *(none — both ungated)* | n/a | low (see live-verify note in Phase 2) |
| `is_between` | `is_between` | **not active** — confirmed absent from `cargo tree -e features -i polars-plan/-i polars-ops/-i polars-expr` output | low (`polars-ops/is_between = []`, zero sub-deps — same shape as `meta`) |
| `hist` | `hist` | **not active** | low (`polars-ops/hist = ["dtype-categorical", "dtype-struct"]`, both already active) |
| `partition_by` | `partition_by` | **already transitively active** on `polars-core` (via `polars-stream`/`polars-io`'s `parquet` chain — confirmed by `cargo tree`) | none functionally; add explicitly anyway (same reasoning as `rle`) |
| `item`, `get_column` | *(none — pure Julia / already wrapped)* | n/a | none |
| `to_numpy` | *(not porting — see below)* | n/a | n/a |

`is_between` and `hist` are the only two genuine **new** Cargo.toml lines in this whole plan. Per
CLAUDE.md ("any feature change forces the expensive full optimized rebuild regardless of how many
features change at once"), land them together with the explicit (currently-redundant-but-safer)
`rle`/`partition_by` additions in **one** commit/rebuild cycle (`cargo build -j 1` for that one, per
the build-environment notes), even though they land in different phases below by mechanism.

## Corrections vs. the parent plan's (and this task's brief's) preliminary bucketing

Several items landed in a different bucket than Phase 8's own preliminary guess, or need less work
than assumed. Recorded here since the brief explicitly asks for these to be flagged:

- **`rle`/`rle_id` are bucket (a), not (b).** The brief grouped them with `is_between`/`gather` as
  "extra-args shape, same hand-written pattern as `clip`/`round`/`rank`". They're not:
  `Expr::rle(self) -> Expr` and `Expr::rle_id(self) -> Expr` (`polars-plan-0.54.4/src/dsl/mod.rs:
  1414-1423`) take **zero** extra arguments — they fit the plain `gen_impl_expr!` macro shape
  exactly like `cos`/`sin`/`abs`, not the hand-written-wrapper shape `clip`/`round` need. Cheaper
  than planned: two `gen_impl_expr!` lines, not two hand-written functions.
- **`log10` needs zero new Rust/FFI code**, not "trivially the same unary-macro shape as `cos`/
  `sin`/`log`/`exp`" as the brief assumed. There is no `Expr::log10` in polars-plan at all (checked
  `dsl/mod.rs` and grepped the whole crate for `Log10`/`log10` — nothing). Upstream py-polars'
  `Expr.log10()` is itself just Python-level sugar for `self.log(10.0)`. This repo already wraps
  the 2-arg `Expr::log(base)` as `Base.log(a, b)` (`src/expr/expr.jl:634`,
  `gen_impl_expr_binary!(polars_expr_log, Expr::log, ...)`) — so `log10(expr) = log(expr, lit(10))`
  is a pure Julia one-liner, the same "compose from existing pieces" pattern Phase 7 (literal
  Date/Datetime/Time) already used, not a Rust addition at all. `log1p` is the genuine Rust
  addition in this pair (`FunctionExpr::Log1p`, its own dedicated dispatch arm, gated `#[cfg(feature
  = "log")]` — already active).
- **`get_column` is already fully implemented**, not a "DataFrame-level, needs new C-ABI shape"
  item as the brief's bucket (c) guessed. `polars_dataframe_get` (`c-polars/src/dataframe.rs:
  244-258`) already wraps `DataFrame::column(&self, name: &str) -> PolarsResult<&Column>`
  (`polars-core-0.54.4/src/frame/mod.rs:1099`) verbatim — it's the exact function backing
  `getindex(df, "name")`/`getindex(df, :name)` (`src/dataframe.jl:44-51`), already fallible-clean
  (a missing name surfaces as a normal `PolarsError`, not a panic). The only real gap is a *named*
  entry point — `get_column(df, name) = df[name]` — for users who want the py-polars-shaped method
  name instead of indexing syntax. Zero Rust work.
- **`item` needs zero new Rust/FFI code.** No dedicated Rust method exists for either
  `Series::item()` or `DataFrame::item()` upstream — py-polars implements both as thin Python
  wrappers over existing scalar-extraction (`Series.__getitem__`/`DataFrame.row`+shape checks).
  This repo already has the equivalent primitives: `Base.size(series::Series)` (`src/series.jl:52`)
  and the existing bounds-checked `getindex(series::Series, i)` (backed by the already-panic-safety-
  hardened `polars_series_get`, see CLAUDE.md), plus `Base.size(df::DataFrame)`
  (`src/dataframe.jl:35-40`) and `getindex(df, row, col)`. `item()` for both types is pure Julia
  composition: check the shape, error with a clear message if it doesn't collapse to exactly one
  value, otherwise return the single element.
- **`partition_by`'s underlying Rust method is already compiled in** (feature-wise) — the brief's
  framing ("needs a genuinely new 'return N handles' C-ABI shape... related to Task 3's
  `root_names` problem but for `Vec<DataFrame>`") is correct about the *mechanism* gap but implies
  a Cargo-feature risk that doesn't actually exist: `cargo tree -e features -i polars-core` shows
  `polars-core feature "partition_by"` already active, pulled in transitively via `polars-stream`/
  `polars-io`'s `"parquet"` feature chain — not something this plan's Cargo.toml diff turns on for
  the first time. The genuinely new work here is 100% the marshaling shape (Phase 4 below), not a
  feature-safety concern.
- **`gather`/`gather_every` are fully ungated** — no `#[cfg(...)]` at all on either
  `Expr::gather`/`Expr::gather_every` (`polars-plan-0.54.4/src/dsl/mod.rs:344-360,1611-1613`). The
  brief's bucket (b) placement (mechanism-wise) is correct, but there is no Cargo-feature dimension
  to this item at all, gated-or-not — it was never a candidate for the "gated-and-inactive" branch.
  See Phase 2's live-verify note below for the one real residual risk (not feature-gating).
- **`to_numpy`'s "don't port" recommendation is confirmed correct**, with one added nuance not in
  the brief: `Base.collect(series::Series)::Vector` (`src/arrow/read.jl:462`) is a genuine full
  substitute for materializing a `Series` to a native Julia array (used by `Base.copy`/`Base.Vector`
  already), and `Tables.getcolumn` covers `DataFrame`-level column access. The one real (very minor)
  gap this repo doesn't have: py-polars' `to_numpy()` on a null-free numeric `Series` returns a
  *zero-copy* NumPy view backed directly by the underlying Arrow buffer; `collect(series)` always
  allocates a fresh `Vector`. Not worth building under the `to_numpy` name (no NumPy-shaped target
  type exists in this ecosystem to view into), and out of scope for this plan — noted here only so
  the "no gap" claim isn't overstated.

## Phase 1 — Near-zero-risk unary `Expr` functions (bucket a)

**Items:** `arccos`, `degrees`, `radians`, `log1p`, `rle`, `rle_id` (Rust + Julia), plus `log10`
(pure Julia, no Rust). All six Rust additions are the exact same `gen_impl_expr!` shape already used
for `cos`/`sin`/`tan`/`sqrt`/`exp`/`abs` — near-zero risk, batch into one commit.

**Cargo**: none required for `arccos`/`degrees`/`radians` (`trigonometry`, already active) or
`log1p` (`log`, already active). For `rle`/`rle_id`, add an explicit `"rle"` line to
`c-polars/Cargo.toml`'s `polars` feature list even though it's already transitively active (same
reasoning as the `dtype-duration` precedent in the parent plan's Phase 3/5 — don't rely on an
incidental transitive path that could disappear if `polars-stream`'s own dependency graph changes).
Land this one Cargo.toml line together with Phase 3's `is_between`/`hist` additions and Phase 4's
`partition_by` explicitness to pay one rebuild for the whole plan (see the feature table above).

**Rust** (`c-polars/src/expr.rs`, `gen_impl_expr!` macro at line 352-361; existing trig block at
lines 528-540 is the direct insertion point): six new `gen_impl_expr!(polars_expr_xxx, Expr::xxx)`
invocations, one per function, following the exact style of the neighboring `polars_expr_cos`/
`polars_expr_sin`/`polars_expr_abs` lines already there — `polars_expr_arccos`/`_degrees`/
`_radians`/`_log1p`/`_rle`/`_rle_id`, each wrapping the same-named `Expr::` method. Sources:
`Expr::arccos`/`degrees`/`radians` at `polars-plan-0.54.4/src/dsl/arithmetic.rs:103-166`;
`Expr::log1p` at `dsl/mod.rs:1570-1573`; `Expr::rle`/`rle_id` at `dsl/mod.rs:1414-1423`. `rle`'s
output is a
`Struct{len, value}` column — reuses the already-active `dtype-struct` feature this repo already
exercises for `unnest`/`as_struct`, no new dtype-shape work needed on the Julia decode side (same
`Series`/`Value` struct-materialization path `test/datatypes/structs.jl` already covers).

**Julia** (`src/expr/expr.jl`, next to the existing `gen_impl_expr!` calls' Julia-side wrapper
block, and the `Base.log`/`prod`/`std` hand-written-name precedent for the Base-collision check):
- `arccos`, `degrees`, `radians`, `log1p`, `rle`, `rle_id` — plain unary `Expr -> Expr`, same shape
  as the existing macro-generated wrappers. Check `isdefined(Base, :xxx)` for each per the
  `@generate_expr_fns` sharp edge in CLAUDE.md before deciding qualified vs. plain naming — `rle`/
  `rle_id` are not Base names (safe unqualified); `log1p` **is** an exported Base function
  (`Base.log1p(::Float64)`) so bind as `Base.log1p(expr::Expr)` matching the `Base.log`/`Base.round`
  precedent already used for the binary `log`; `arccos`/`degrees`/`radians` are not Base names
  either (Julia's own inverse-trig functions are `acos`, not `arccos` — verify this holds, it's the
  reason py-polars' own naming diverges from Julia's `Base.acos` and there is no collision risk to
  handle either way).
- `log10(expr::Expr) = log(expr, lit(10))`, bound as `Base.log10(expr::Expr)` (an exported Base
  name, matching the `log`/`round`/`diff`/`replace` qualified-name precedent block already in
  `src/expr/expr.jl:634-654`). Zero new Rust/FFI code — pure composition over the already-wrapped
  binary `log`.

**Tests** (`test/expr/math.jl`, extending or sibling to the existing `"log / exp / sqrt / sign / %"`
testset): `arccos`/`degrees`/`radians` against hand-checkable values (e.g. `degrees(lit(π))≈180`,
`arccos(lit(1.0))≈0`); `log1p`/`log10` against a small fixture with `Base.log1p`/`Base.log10` on the
materialized column as the oracle (round-trip via `collect`). New `test/expr/rle.jl`: a short
run-length fixture (e.g. `[1,1,2,2,2,3]`) with hand-verified expected `{len, value}` pairs for
`rle`, expected run-id sequence for `rle_id`; a fixture with a single run (whole column identical);
an empty frame; a fixture with nulls (verify actual null-run behavior live, don't assume — nulls are
compared via `not_equal_missing`, so consecutive nulls should form one run, but confirm).

**Docs**: `docs/src/reference/expressions.md`'s "Math & type inspection" section (line ~127) for
`arccos`/`degrees`/`radians`/`log10`/`log1p`, next to the existing `cos`/`sin`/`log`/`exp` rows; new
"Run-length encoding: `rle`/`rle_id`" subsection under "Shaping & rearranging" (line ~263), next to
`implode`/`flatten`/`reverse`.

---

## Phase 2 — Extra-args `Expr` wrappers needing no Cargo change (bucket b, ungated)

**Items:** `gather`, `gather_every`.

**Cargo**: none — both fully ungated, no `#[cfg(...)]` anywhere on either method or the `Expr::
Gather` AST variant.

**Rust** (`c-polars/src/expr.rs`, hand-written functions matching `clip`'s/`polars_expr_over`'s
extra-args shape, not the plain macro):
- `polars_expr_gather(expr, idx: *const polars_expr_t, null_on_oob: bool) -> *const polars_expr_t`
  — `(*expr).inner.clone().gather((*idx).inner.clone(), null_on_oob)`, infallible constructor
  (source: `Expr::gather<E: Into<Expr>>(self, idx: E, null_on_oob: bool)`, `dsl/mod.rs:344-351`).
- `polars_expr_gather_every(expr, n: usize, offset: usize) -> *const polars_expr_t` — direct wrap
  of `Expr::gather_every(self, n: usize, offset: usize)` (`dsl/mod.rs:1611-1613`), infallible.

**Live-verify note (the one real residual risk, not feature-gating):** `Expr::gather`'s execution
path (`polars-expr-0.54.4/src/expressions/gather.rs:23-29`, `evaluate_impl`) calls
`series.take(&idx)` — this is the *general arbitrary-index* gather machinery, the same family that
historically hit `take_chunked_unchecked`'s `unreachable!()` arm for `Time` before `dtype-time` was
added (documented in CLAUDE.md). `dtype-time` is now active in this repo, so that specific
regression shouldn't recur, but `Expr::gather` is a **new entry point** into that machinery that
this repo hasn't exercised before (previous coverage of the gather/take path came from joins/sorts,
not from an explicit `.gather()` call) — per CLAUDE.md's "a clean build is not sufficient evidence
of safety" rule, live-verify `gather` specifically over each of this repo's active non-default
temporal/exotic dtypes (Time, Duration, Decimal, Date, Datetime, Struct, List) before considering
this phase done, not just numeric/string columns. `gather_every` uses a much simpler strided-slice
path (`polars-expr-0.54.4/src/dispatch/misc.rs:357-359`, `Column::gather_every`) with no such
history — lower-priority to stress-test but still worth a quick pass.

**Julia** (`src/expr/expr.jl`, next to `shift`/`pct_change`'s binary-with-curry pattern):
- `gather(expr::Expr, idx; null_on_oob::Bool=false)::Expr` — `idx = convert(Expr, idx)` (accepts a
  bare `Vector{<:Integer}` or another `Expr`, matching `clip`'s `min`/`max` conversion pattern).
- `gather_every(expr::Expr, n::Integer; offset::Integer=0)::Expr`.
- Curried forms following the `shift(n)`/`clip(min,max)` precedent for `|>` pipelines.

**Tests**: new `test/expr/gather.jl` — `gather` with a literal index vector and with another
column's values as the index expr; negative indices (verify actual out-of-range/negative-index
semantics live — `convert_and_bound_index` handles negative wrap-around, confirm behavior matches
expectation, don't assume Python parity); `null_on_oob=true` vs. `false` (default) on a genuinely
out-of-bounds index — confirm clean null vs. clean error respectively, not a panic; `gather_every`
with `offset=0` and nonzero, `n` larger than the column length (should yield a short/empty result,
not error); both over each dtype from the live-verify note above, at least once each (Time,
Duration, Decimal minimum — the exact set CLAUDE.md's `dtype-time` precedent calls out).

**Docs**: `docs/src/reference/expressions.md`'s "Shaping & rearranging" section, next to `top_k`/
`arg_sort`.

---

## Phase 3 — Extra-args `Expr` wrappers needing a new Cargo feature (bucket b, gated-and-inactive)

**Items:** `is_between`, `hist`. Land both Cargo.toml lines together (see feature table) with
Phase 1's explicit `rle` line and Phase 4's explicit `partition_by` line, in one rebuild cycle.

### `is_between`

**Cargo**: add `"is_between"` to `c-polars/Cargo.toml`'s `polars` feature list. Confirmed absent
from `cargo tree -e features -i polars-plan`/`-i polars-ops`/`-i polars-expr` (no `"is_between"`
line anywhere in any of the four crate-specific trees) — genuinely gated-and-inactive, not a
transitively-already-on case like `rle`/`partition_by`. `polars-ops/is_between = []` (zero
sub-deps, `polars-ops-0.54.4/Cargo.toml:123`) — same shape as the `"meta"` feature the parent plan
already added (near-zero risk). Execution path
(`polars-ops-0.54.4/src/series/ops/is_between.rs:7-22`) is plain `Series::gt`/`gt_eq`/`lt`/`lt_eq`
comparisons + a `bitand` — no `unreachable!()`, no `activate ... feature` panics found in the
touched files (`polars-expr-0.54.4/src/dispatch/boolean.rs:34-35` dispatch arm is a clean
`map_as_slice!`).

**Rust**: source is `Expr::is_between<E: Into<Expr>>(self, lower: E, upper: E, closed:
ClosedInterval) -> Self` (`polars-plan-0.54.4/src/dsl/mod.rs:935-942`, gated `#[cfg(feature =
"is_between")]`). **Reuse the existing `polars_closed_window_t` C enum rather than adding a new
one** — `ClosedInterval` (`polars-ops-0.54.4/src/series/ops/linear_space.rs:11-16`: `Both`/`Left`/
`Right`/`None`) has exactly the same variant set as `ClosedWindow`, which already has a full
`#[repr(C)]` mirror (`polars_closed_window_t`, `c-polars/src/value.rs:144-162`) used by
`rolling`/`group_by_dynamic`/`join_asof`. Add a second conversion method to the existing `impl
polars_closed_window_t` block: `pub fn to_closed_interval(&self) -> ClosedInterval { ... }` (same
match shape as the existing `to_closed_window`), rather than duplicating a parallel
`polars_closed_interval_t` enum + its own `@cenum` generation + its own to-Rust match. New
`polars_expr_is_between(expr, lower: *const polars_expr_t, upper: *const polars_expr_t, closed:
polars_closed_window_t) -> *const polars_expr_t` in `c-polars/src/expr.rs`, infallible constructor,
same extra-Expr-args shape as `clip`.

**Julia** (`src/expr/expr.jl`, next to `clip`): `is_between(expr::Expr, lower, upper;
closed::Symbol=:both)::Expr` — `lower`/`upper` via `convert(Expr, ...)` (matching `clip`); `closed`
mapped to `API.PolarsClosedWindow*` via the **exact** `closed === :left ? ... : closed === :right ?
... : ...` chain already used twice in `src/group_by.jl:98-101` and `:168-171` — copy that pattern
verbatim rather than inventing a new one, including its `error(...)` fallback for an unrecognized
symbol.

**Tests**: new `test/expr/is_between.jl` — each of the four `closed` values against boundary-equal
values (off-by-one is the classic bug here, per `cut`/`qcut`'s own `left_closed` warning in
`analytics_gap_batch2.md`); `lower`/`upper` as bare numeric literals and as other column
expressions; a `null` in the tested column (should stay `null`, three-valued logic, not `false`);
`lower > upper` (verify actual behavior — presumably an always-`false` mask, not an error, but
confirm live rather than assume).

**Docs**: `docs/src/reference/expressions.md`, new "Range checks: `is_between`" section right after
"Duplicate detection: `is_duplicated` and `is_unique`" (line ~408).

### `hist`

**Cargo**: add `"hist"` to `c-polars/Cargo.toml`'s `polars` feature list. Confirmed absent from all
four crate-specific `cargo tree` outputs. `polars-ops/hist = ["dtype-categorical", "dtype-struct"]`
(`polars-ops-0.54.4/Cargo.toml:115-118`) — both sub-deps **already active** in this repo (confirmed:
`dtype-categorical` via the `streaming` chain, `dtype-struct` via `performant`/`pivot`, both already
exercised by `unnest`/selectors), so no cascading feature risk beyond the direct `hist` line itself.
No `unreachable!()`/`activate ... feature` found in `polars-ops-0.54.4/src/chunked_array/hist.rs` or
the `polars-expr-0.54.4/src/dispatch/mod.rs:267-274` dispatch arm (a clean `#[cfg(feature =
"hist")] F::Hist { .. } => map_as_slice!(misc::hist, ...)`).

**Rust**: source `Expr::hist(self, bins: Option<Expr>, bin_count: Option<usize>, include_category:
bool, include_breakpoint: bool) -> Self` (`polars-plan-0.54.4/src/dsl/statistics.rs:76-92`). Both
optional args reuse **already-established marshaling patterns, no new mechanism**:
- `bins: Option<Expr>` → nullable `*const polars_expr_t` with a `.is_null()` check, identical to
  `polars_expr_over`'s `order_by` handling (`c-polars/src/expr.rs:451-489`, cite this exact
  function as the template — same "single optional expr, null = None" shape).
- `bin_count: Option<usize>` → nullable pointer, identical to `polars_expr_sample_n`'s `seed:
  *const u64` convention (`c-polars/src/expr.rs:837-856`), just `usize` instead of `u64`.

New `polars_expr_hist(expr, bins: *const polars_expr_t, bin_count: *const usize,
include_category: bool, include_breakpoint: bool) -> *const polars_expr_t` in
`c-polars/src/expr.rs`, infallible constructor (the `Option<Expr>`/`Option<usize>` reads happen
inside, then `expr.hist(bins, bin_count, include_category, include_breakpoint)`).

**Julia** (`src/expr/expr.jl`): `hist(expr::Expr; bins::Union{Nothing,AbstractVector{<:Real}}=
nothing, bin_count::Union{Nothing,Integer}=nothing, include_category::Bool=false,
include_breakpoint::Bool=false)::Expr` — `bins` converts via the already-existing `lit(::Vector)`
literal path (`docs/src/reference/expressions.md`'s "`lit(::Vector)` for multi-value membership"
section documents this exact conversion already; no new literal-building code needed), passed as
`bins === nothing ? Ptr{...}(C_NULL) : convert(Expr, Float64.(bins))`; `bin_count` as a nullable
`Ref{UInt}`/`Ptr{UInt}(C_NULL)` pair under `GC.@preserve`, matching `fill_null`'s existing
`limit_ref` pattern (`src/expr/expr.jl:687-689`). Error if both `bins` and `bin_count` are given
(upstream itself errors on this — `get_breaks`, `polars-ops-0.54.4/src/chunked_array/hist.rs:18-22`
— but surfacing it as a clear Julia-side `error(...)` up front is friendlier than waiting for the
upstream `PolarsError`; either is acceptable, decide at implementation time).

**Tests**: extend `test/expr/statistics.jl` (the natural home once `analytics_gap_batch2.md`'s
`skew`/`kurtosis` land there too — same conceptual "aggregate/statistics" bucket) — default
`bin_count` (verify the upstream default of 10, `DEFAULT_BIN_COUNT` in `hist.rs:8`); explicit
`bins`; `include_category`/`include_breakpoint` each combination, inspecting the resulting `Struct`
column's field names; both `bins` and `bin_count` given together → clean error, not a panic; a
single-value column (edge case for bin-width computation); an empty frame.

**Docs**: `docs/src/reference/expressions.md`'s "Aggregation functions" section (line ~62), noting
its adjacency to `analytics_gap_batch2.md`'s not-yet-landed `skew`/`kurtosis`.

---

## Phase 4 — `partition_by`: new `Vec<DataFrame>`-return C-ABI marshaling shape (bucket c)

**Mechanism**: the genuinely new piece in this whole plan. `DataFrame::partition_by`/
`partition_by_stable` (`polars-core-0.54.4/src/frame/mod.rs:2596-2620`, both `#[cfg(feature =
"partition_by")]`) return `PolarsResult<Vec<DataFrame>>` — the first "return N owned handles of an
existing opaque type" shape this codebase has needed (Task 3's `Expr.meta.root_names()` solved the
analogous problem for `Vec<String>` via count+per-index `IOCallback`, but `DataFrame` handles are
pointers, not byte buffers, so that pattern doesn't directly apply — plain values need to cross via
a fresh intermediate handle instead).

**Cargo**: add an explicit `"partition_by"` line to `c-polars/Cargo.toml`'s `polars` feature list,
even though `cargo tree -e features -i polars-core` already shows it active (transitively, via the
`polars-stream`/`polars-io` `"parquet"` chain) — same "confirmed-safe belt-and-suspenders"
reasoning as `rle` above, not a functional requirement. `_partition_by_impl`
(`polars-core-0.54.4/src/frame/mod.rs:2526-2596`) uses `_take_unchecked_slice_sorted`, part of the
same general internal-gather family flagged in Phase 2's live-verify note, but one this repo already
exercises broadly via `group_by` (which `partition_by` is internally built on top of, via
`group_by_with_series`) — lower incremental risk than `gather`, but still worth a live pass over the
same dtype set for the *partition/group key* column specifically (grouping by a Time/Duration/
Decimal column is a distinct code path from grouping by the already-well-tested String/numeric
keys).

**Rust**:
- New opaque type `polars_dataframe_list_t` in `c-polars/src/types.rs`, next to the existing
  `polars_dataframe_t`/`polars_lazy_group_by_t` definitions (lines 15-25): `pub struct
  polars_dataframe_list_t { pub(crate) inner: Vec<DataFrame> }`, plus a `make_dataframe_list(dfs:
  Vec<DataFrame>) -> *mut polars_dataframe_list_t` constructor mirroring `make_dataframe`/
  `make_lazy_group_by` (lines 35-45) exactly.
- `polars_dataframe_partition_by(df, cols: *const *const u8, lens: *const usize, n: usize, stable:
  bool, include_key: bool, out: *mut *mut polars_dataframe_list_t) -> *const polars_error_t` in
  `c-polars/src/dataframe.rs` — `read_names(cols, lens, n)` (template: `c-polars/src/ffi_util.rs:
  46-56`, already used by `unnest`) → `tri!(df.inner.clone().partition_by(names, include_key))` or
  `.partition_by_stable(...)` depending on `stable` → `*out = make_dataframe_list(result)`.
- `polars_dataframe_list_len(list: *const polars_dataframe_list_t) -> usize` — trivial, `(*list)
  .inner.len()`.
- `polars_dataframe_list_get(list: *const polars_dataframe_list_t, index: usize, out: *mut *mut
  polars_dataframe_t) -> *const polars_error_t` — **bounds-checked, not a raw index** (per
  CLAUDE.md's documented `polars_series_get` panic-safety precedent, `c-polars/src/series.rs:
  112-121`, which uses exactly this out-param + error-pointer shape for the same "index into a
  Rust-side collection" problem): `(*list).inner.get(index)` → `tri!` a clean `PolarsError` on
  `None`, not a panic; on success, **clone** the `DataFrame` at that index into a *fresh* boxed
  `polars_dataframe_t` (`make_dataframe((*list).inner[index].clone())`) — the list handle keeps
  owning its own copies, so retrieved `DataFrame` handles are independent and the list can be
  destroyed (or not) without affecting already-retrieved frames, matching this repo's "construct a
  new object" ownership convention (see CLAUDE.md's ownership-conventions section).
- `polars_dataframe_list_destroy(list: *mut polars_dataframe_list_t)` — `Box::from_raw(list)`, let
  it drop (drops every remaining owned `DataFrame` in the `Vec` too).

**Header** (`c-polars/include/polars.h`): four new prototypes + the new opaque
`polars_dataframe_list_t` struct typedef, matching the style of the existing `polars_lazy_group_by_t`
entry. Verify with `check_header_drift.py` per the usual workflow.

**Julia** (`src/dataframe.jl`, next to the `DataFrame` struct definition — this is a new wrapped
type, so it needs the same finalizer/`unsafe_convert` boilerplate every other handle type gets, per
CLAUDE.md's "Opaque pointers + Julia finalizers" section): a private `DataFrameList` mutable struct
wrapping `Ptr{polars_dataframe_list_t}`, registering `polars_dataframe_list_destroy` in its inner
constructor and a matching `Base.unsafe_convert` method, exactly mirroring the existing `DataFrame`/
`LazyGroupBy` struct definitions at the top of this file and `src/group_by.jl` respectively; a
`Base.length` forwarding to `polars_dataframe_list_len`; a bounds-checked `Base.getindex(l::
DataFrameList, i::Integer)` (1-based, converting to the Rust side's 0-based `index` and forwarding
to `polars_dataframe_list_get`, then wrapping the returned pointer in a normal `DataFrame`) — this
is not exported public API (see below), just the private plumbing `partition_by` uses internally.
Public entry point in `src/verbs.jl` (next to `unique`/`drop`/`concat` — DataFrame-level frame
verbs): `partition_by(df::DataFrame, cols::AbstractString...; maintain_order::Bool=true,
include_key::Bool=true)::Vector{DataFrame}` — builds the `cols` ptr/lens arrays via the existing
`_name_ptrs` helper (already used by `unnest`/join/struct-field code, per `src/verbs.jl`'s own
existing `using`), calls `polars_dataframe_partition_by`, then **materializes the
`DataFrameList` into a plain `Vector{DataFrame}`** immediately (`[list[i] for i in
1:length(list)]`) rather than exposing `DataFrameList` itself as public API — keeps the public
surface a plain, idiomatic Julia `Vector`, consistent with how every other multi-result operation in
this package already returns plain Julia containers (`root_names()` returns `Vector{String}`, not a
custom iterator type). `maintain_order=true` → `partition_by_stable`, `false` → plain
`partition_by` (matches py-polars' own `maintain_order` default of `true`). No `LazyFrame`
equivalent exists upstream (confirmed — `partition_by` only exists on `polars_core::frame::
DataFrame`, not `LazyFrame`) — this is a structural DataFrame-only exception like `hstack`/
`transpose` in the parent plan's Phase 4, not a shortcut being skipped.

**Tests** (`test/operations/frame_verbs.jl`, next to the existing `hstack`/`vstack` tests): use
`fruits_cars_df()` from `test/fixtures.jl` — partition by `"fruits"`, confirm the right number of
groups and that each returned frame's `"fruits"` column is constant; partition by two columns
(`"fruits", "cars"`); `include_key=false` (confirm the key column is actually dropped from each
partition, not just hidden); `maintain_order=true` vs. `false` (confirm the same set of groups,
`true` in original first-appearance order — verify this against upstream's actual documented
ordering guarantee, don't assume); a single-group frame (all rows share one key); an empty frame;
partitioning by a Time/Duration/Decimal-typed key column specifically (the live-verify note above).

**Docs**: `docs/src/reference/manipulation.md`, new "Splitting: `partition_by`" section, placed
after "Removing duplicates: `unique`" (line ~170) and before "Reshaping" (line ~205) — a "splitting
a frame" section reads naturally as the mirror image of "Concatenating: `concat`" (line ~136).

---

## Phase 5 — `item` / `get_column`: pure Julia composition, zero Rust (bucket a-ish)

No new Rust/FFI code for either — both compose from already-wrapped primitives (see "Corrections"
above for why this differs from the brief's bucket-(c) guess).

**Julia**:
- `get_column(df::DataFrame, name::AbstractString) = df[name]` in `src/dataframe.jl`, right after
  the existing `getindex(df, s::String)`/`getindex(df, s::Symbol)` methods (lines 44-51) — a named
  alias for the exact same already-fallible-clean `polars_dataframe_get` call, for users who prefer
  the py-polars-shaped method name over indexing syntax.
- `Polars.item(series::Series)` in `src/series.jl`, next to `Base.size(series::Series)` (line 52):
  `length(series) == 1 ? series[1] : error("item() requires a Series of length 1, got length
  $(length(series))")`. Reuses the existing bounds-checked `getindex(series, i)`.
- `Polars.item(df::DataFrame)` and `Polars.item(df::DataFrame, row::Integer, col)` in
  `src/dataframe.jl`, next to `Base.size(df::DataFrame)` (lines 35-40): the 0-arg form requires
  `size(df) == (1, 1)` (clear `error(...)` otherwise, matching `Series`'s message shape); the 3-arg
  form (`row`, `col` — `col` accepting either an `Integer` index or a column-name `String`/`Symbol`)
  is `getindex(df, row, col)` — already exists, `item` is a thin renaming wrapper for py-polars-name
  parity, not new indexing logic. **Decide up front, don't guess at implementation time**: py-polars'
  `DataFrame.item()` (no args) also has a 1-row **or** 1-column relaxation in some versions (returns
  the sole element of a 1-row-N-col or N-row-1-col frame under certain conditions) — pin down the
  *exact* upstream semantics for the polars version this repo targets before implementing, and
  prefer the strict `(1,1)`-only interpretation if upstream's own behavior is ambiguous/version-
  dependent, documenting the choice in the docstring.
- Both `item` names are **not** exported under a bare `item` — too generic/collision-prone a name to
  add unqualified to a package's top-level namespace (unlike `get_column`, which is unambiguous).
  Reach as `Polars.item(...)`, matching the `Polars.Meta.output_name(...)`-style qualified-access
  precedent the parent plan already established for a similar "name's too generic/collision-prone to
  export bare" case.

**Tests**: `test/operations/frame_verbs.jl` (or a small new `test/dataframe/item.jl`, either is
fine) — `get_column` returns the same `Series` `getindex` would (same values, same name);
nonexistent column name → clean `PolarsError`, not a panic (already covered implicitly by
`polars_dataframe_get`'s existing behavior, but add an explicit assertion); `item(series)` on
length-1/length-0/length-N Series (the latter two should both error, with distinct-enough messages
to debug from); `item(df)` on a genuine 1×1 frame, and on 1×N / N×1 / N×M frames (confirm the
decided-above semantics, whichever way that lands); `item(df, row, col)` with both `col` forms
(name and integer index).

**Docs**: `docs/src/reference/structures.md`'s `DataFrame`/`Series` sections (lines 12-48) — add
both as one-line entries in whatever inventory-style listing already exists there.

---

## `to_numpy` — confirmed: not porting

No phase, no code. See "Corrections" above for the confirmed reasoning: `collect(series)`
(`src/arrow/read.jl:462`) plus `Tables.getcolumn` already cover the underlying need of "get this
column's data as a native Julia container"; there's no NumPy-shaped target type in this ecosystem to
justify porting the name itself. If a future user specifically wants a zero-copy view rather than a
fresh-allocated `Vector`, that's a distinct, separately-justified feature request (not this item),
and not free to build (it would mean exposing raw Arrow-buffer pointers Julia-side, a materially
different and riskier FFI shape than anything else in this package).

## Callback-blocked items — deferred

`map_elements`/`map_batches`/`map_groups` (this plan's own research items) all need Rust to call
back into a live Julia closure mid-query-execution — the reverse FFI direction from every other
capability in this codebase, needing a `@cfunction` trampoline + GC-rooting scheme for the query
plan's lifetime, plus a Rust-side `PlanCallback`-shaped adapter type per callback site. This is the
same missing piece Task 5/Phase 6 already flagged for `.name.map`
(`plans/definitive_guide_gap_closure.md`'s Phase 6). **Not attempted here** — see the short problem-
statement stub `plans/callback_infra.md` (written alongside this plan) for the shared shape of the
gap across all four call sites. That stub does not solve the problem; it exists so a future session
scoping the actual infrastructure work has a single named home to start from instead of re-deriving
"where do all the callback-shaped gaps live" from scratch.

---

## Critical files

- `c-polars/src/expr.rs` — `gen_impl_expr!` macro (352-361) and its existing trig/log block
  (528-540, 729) for Phase 1; `clip` and `polars_expr_over` (451-489) as the extra-args/optional-arg
  templates for Phases 2-3; `polars_expr_sample_n` (837-856) as the nullable-scalar template for
  `hist`'s `bin_count`.
- `c-polars/src/value.rs` — `polars_closed_window_t` (144-162), extend with `to_closed_interval()`
  for `is_between` rather than adding a parallel enum.
- `c-polars/src/types.rs` — `polars_dataframe_t`/`make_dataframe` (15-17, 35-37) and
  `polars_lazy_group_by_t`/`make_lazy_group_by` (23-25, 43-45) as the direct templates for the new
  `polars_dataframe_list_t`/`make_dataframe_list` (Phase 4).
- `c-polars/src/ffi_util.rs` — `read_names` (46-56) for `partition_by`'s `cols` argument;
  `read_exprs`/`read_series` (17-40) as the pattern family this all descends from.
- `c-polars/src/series.rs` — `polars_series_get` (112-121), the panic-safety precedent
  `polars_dataframe_list_get` must follow (bounds-check via `out`-param + error-pointer, not a raw
  index).
- `c-polars/Cargo.toml` — the two genuinely-new feature lines (`is_between`, `hist`) plus two
  explicit-but-currently-redundant ones (`rle`, `partition_by`), landed together in one rebuild.
- `src/expr/expr.jl` — insertion points for Phase 1/2/3's new `Expr` functions; `clip`/`fill_null`
  (686-736) as the extra-args Julia wrapper template; the `Base.log`/`Base.round`/`Base.replace`
  qualified-naming precedent block (634-654) for deciding bare-vs-qualified names.
- `src/group_by.jl` — the `closed::Symbol` → `API.PolarsClosedWindow*` mapping (98-101, 168-171),
  copy verbatim for `is_between`.
- `src/dataframe.jl` — `getindex(df, s::String/Symbol)` (44-51) is what `get_column` aliases;
  `Base.size(df::DataFrame)` (35-40) is what `item(df)` builds on; new `DataFrameList` wrapper type
  for Phase 4 goes here too, next to the `DataFrame` struct itself.
- `src/series.jl` — `Base.size(series::Series)` (52) is what `item(series)` builds on.
- `src/verbs.jl` — `partition_by`'s public entry point, next to `unique`/`drop`/`concat`;
  `_name_ptrs` helper already used here for other string-list marshaling.
- `test/fixtures.jl` — `fruits_cars_df()` (multi-group categorical+numeric fixture) is the natural
  `partition_by` test fixture; no new fixture needed for the other phases (all use small
  inline data per the existing per-testset convention).
- `plans/analytics_gap_batch2.md` — sibling plan; excluded four items live there, execute that plan
  for them rather than re-planning here. Its own B3 section is stale (see Context above) but not
  fixed by this task.
- `plans/callback_infra.md` — sibling stub; problem statement only for the 4 callback-blocked items
  across this plan and Task 5/Phase 6.

## Verification (per phase, before marking it done)

Same sequence as `plans/definitive_guide_gap_closure.md`'s own Verification section — repeated here
for a future session that opens this file standalone:

1. `cd c-polars && python3 check_header_drift.py` after any header edit.
2. `cargo build -j 4` for Phase 1/2 (no feature change); `cargo build -j 1` for the one shared
   Phase 3+4 feature-adding rebuild (`is_between`, `hist`, explicit `rle`/`partition_by`) — see the
   Cargo feature table above for why these land together despite being separate phases.
3. Restart the Julia session (native `.so` doesn't hot-reload) and exercise each new path live
   *before* writing its tests — per CLAUDE.md, this is not optional, this repo has a documented
   history of code that compiles clean but aborts the process at runtime. Specifically hit: the
   dtype sweep called out in Phase 2's and Phase 4's live-verify notes (Time/Duration/Decimal
   columns through `gather` and through `partition_by`'s group-key path); `hist`'s
   both-`bins`-and-`bin_count` error path; `polars_dataframe_list_get` out-of-bounds (confirm clean
   error, not a panic — this is the one brand-new panic-surface this whole plan introduces, so it
   gets the same scrutiny `ffi_panic_safety.md`'s two precedents got).
4. `julia --project=gen gen/generate.jl` then `runic -i src/api/generated.jl` after any header
   change.
5. Add the test(s) per phase above; run via the scratch-env workflow (`Pkg.develop(path=".")` +
   `Pkg.add(["Aqua","Test","Tables","TimeZones"])`), `JULIA_PROJECT=<scratch> julia -e
   'include("test/runtests.jl")'`.
6. Update the relevant `docs/src/reference/*.md` page(s) and confirm `docs/make.jl`'s
   `checkdocs=:exports` build still passes for any newly-exported name (`get_column`, `is_between`,
   `hist`, `gather`, `gather_every`, `rle`, `rle_id`, `arccos`, `degrees`, `radians`, `log1p`,
   `log10`, `partition_by` are all intended-exported; `Polars.item(...)` is deliberately not, see
   Phase 5).
7. Update this file's `## Status` line as each phase lands, following the parent plan's own
   per-phase status-line convention.
