# Batch: coalesce, upsample, interpolate, horizontal reductions, as_struct

## Status
Everything through `972e6d1` (Datetime/Duration eltype fix) is done, committed, and pushed
(`scan-parquet` has since merged into `main` via PR #1). This plan covers the 5-item batch
identified in the latest gap
analysis, in priority order: `coalesce`, `upsample`, `interpolate`, horizontal reductions
(`all_horizontal`/`any_horizontal`/`sum_horizontal`/`min_horizontal`/`max_horizontal`, +
`mean_horizontal` as a bonus, same shape), `as_struct`.

## Research findings (confirmed against vendored polars 0.54.4 source)

**Cargo features needed: only one.** `coalesce`/`as_struct`/all horizontal-reduction functions
live in `polars-plan/src/dsl/functions/{horizontal,coerce}.rs`. `mod horizontal` has **no** feature
gate at all (confirmed via `dsl/functions/mod.rs`). `mod coerce` (holding `as_struct`) is gated by
`dtype-struct`, which is **already active** transitively (Struct support already works throughout
this package). `interpolate` is the only one needing a genuinely new feature:
`#[cfg(feature = "interpolate")]` on `Expr::interpolate` in `polars-plan/src/dsl/mod.rs:1104`.
`upsample` needs **no new feature or import at all** — `PolarsUpsample` (a trait impl on
`DataFrame`, in `polars-time`) is already re-exported through `polars_time::prelude::*` →
`polars::prelude::*` (gated by `temporal`, already active) → this crate's existing
`use polars::prelude::*;` wildcard. Confirmed by tracing the `pub use` chain
(`polars-time/src/lib.rs:50` → `prelude.rs:7` → `polars/src/prelude.rs:10` → already-imported here).

**Panic risk found and must be guarded: `as_struct` has a bare `assert!`.**
`polars-plan/src/dsl/functions/coerce.rs`: `pub fn as_struct(exprs: Vec<Expr>) -> Expr { assert!(!
exprs.is_empty(), ...); ... }` — an empty `exprs` panics, and a panic unwinding across `extern "C"`
is UB per CLAUDE.md. **Must validate non-empty on the C ABI side and return a proper error instead
of calling `as_struct` with zero exprs.** `coalesce`'s doc comment also says "it is an error to
provide an empty exprs" but has no visible assert in its own body (unclear what happens downstream)
-- applying the same defensive empty-check for it too rather than relying on unspecified behavior.

**All 5 (6 counting `mean_horizontal`) share one new marshaling shape**: an n-ary expr function
taking `Vec<Expr>` (no leading "self" expr, unlike `sort_by`/`over` which take `self` + trailing
exprs) and returning one `Expr`. This is exactly `polars_expr_over`'s `partition_by` array
marshaling minus the leading `expr` parameter -- same `(*const *const polars_expr_t, usize)` →
`Vec<Expr>` pattern, reused wholesale.

**`all_horizontal`/`any_horizontal`/`sum_horizontal`/`min_horizontal`/`max_horizontal`/
`mean_horizontal` are genuinely fallible** (`PolarsResult<Expr>`, via `polars_ensure!(!
exprs.is_empty(), ...)` -- safe, non-panicking), so they follow the out-param + error-pointer
convention. `coalesce`/`as_struct` are infallible at the Rust type level (`-> Expr`, no
`PolarsResult`) but need the manual empty-check described above returning our own `make_error(...)`
before calling them.

**`upsample` is eager-only, `DataFrame`-level** (not `LazyFrame`), matching the shape `pivot`/
`describe` already established for operations needing precomputed input. Signature:
`fn upsample<I: IntoVec<PlSmallStr>>(&self, by: I, time_column: &str, every: Duration) ->
PolarsResult<DataFrame>` -- `every` is a `polars_time::Duration` string, parsed via
`Duration::try_parse(str)`, the **exact same pattern already used** for `group_by_dynamic`/
`rolling` in `c-polars/src/lib.rs:685,689,693,745,749` -- reuse verbatim, no new parsing logic
needed. `by` is a plain name list (reuse `read_names`/`Selector`-adjacent marshaling -- actually
just `Vec<PlSmallStr>` directly, no `Selector` needed here since `IntoVec<PlSmallStr>` accepts a
plain vec).

## Items

### B1 -- `coalesce(exprs...)`
- Rust ([expr.rs](c-polars/src/expr.rs)): `polars_expr_coalesce(exprs: *const *const
  polars_expr_t, n: usize, out: *mut *const polars_expr_t) -> *const polars_error_t`. Manual empty
  check → `make_error(...)` before calling `coalesce(&exprs)`.
- Header/API.jl/Julia: `coalesce(exprs...)` variadic, converting String/literal args via the
  existing `col`/`convert(Expr,...)` promotion pattern (mirrors `over`/`sort_by`'s arg handling).
  Check `isdefined(Base, :coalesce)` before naming -- Base has its own `coalesce` for `Union{
  Missing,T}` values, so this likely needs the same `Base.`-qualification handling as `sum`/`diff`.
- Test: `coalesce(col("a"), col("b"), lit(0))` on a fixture with nulls in `a` then `b`.

### B2 -- `upsample(df, time_column; by=[], every, offset="0ns", stable=true)`
- Rust ([lib.rs](c-polars/src/lib.rs)): new `polars_dataframe_upsample(df: *mut
  polars_dataframe_t, by_names, by_lens, n_by, time_column: (ptr,len), every: (ptr,len), stable:
  bool, out: *mut *mut polars_dataframe_t) -> *const polars_error_t`. Parse `every` via
  `Duration::try_parse` (reuse pattern), call `.upsample(...)`/`.upsample_stable(...)` depending on
  `stable`, propagate the inner `PolarsResult` error through `make_error`.
- Header/API.jl/Julia: eager-only `upsample(df::DataFrame, time_column::String; by::Vector{String}
  =String[], every::String, stable::Bool=true)::DataFrame`.
- Test: a fixture with gaps in an hourly time column, `by` grouping, assert the filled rows have
  the expected timestamps and nulls in the non-time columns for newly-inserted rows.

### B3 -- `interpolate(method=:linear)` (expr-level)
- Cargo: add `"interpolate"` feature.
- Rust: new `polars_interpolation_method_t` enum (`Linear`, `Nearest`) + `polars_expr_interpolate
  (expr, method) -> *const polars_expr_t` (infallible, `Expr::interpolate` has no `PolarsResult`).
- Header/API.jl/Julia: `interpolate(expr::Expr; method::Symbol=:linear)`.
- Test: a numeric column with gaps (`missing` in the middle, non-null at the ends), assert linear
  interpolation fills them correctly; leading/trailing nulls remain null per the Rust doc comment.

### B4 -- horizontal reductions
- Rust ([expr.rs](c-polars/src/expr.rs)): `polars_expr_all_horizontal`/`any_horizontal`/
  `sum_horizontal` (extra `ignore_nulls: bool` param)/`min_horizontal`/`max_horizontal`/
  `mean_horizontal` (extra `ignore_nulls: bool`), each taking the shared `Vec<Expr>` marshaling,
  fallible (propagate the `PolarsResult<Expr>` via out-param + error).
- Header/API.jl/Julia: `all_horizontal(exprs...)`, `any_horizontal(exprs...)`,
  `sum_horizontal(exprs...; ignore_nulls=true)`, `min_horizontal(exprs...)`,
  `max_horizontal(exprs...)`, `mean_horizontal(exprs...; ignore_nulls=true)`. Check Base
  collisions for each (`any`/`all`/`sum`/`min`/`max` are all real, exported Base names --
  definitely need `Base.`-qualification, following the `sum`/`diff` precedent, NOT the `product`
  mistake -- confirm `isexported` too before assuming the qualified form "just works" unqualified).
- Test: a small wide fixture (3-4 numeric columns, some nulls), assert each reduction's row-wise
  output by hand, plus `ignore_nulls` true/false behavior for `sum_horizontal`/`mean_horizontal`.

### B5 -- `as_struct(exprs...)`
- Rust ([expr.rs](c-polars/src/expr.rs)): `polars_expr_as_struct(exprs, n, out) -> *const
  polars_error_t`. **Manual empty-check required** (the Rust fn panics on empty input) -- return
  `make_error("as_struct requires at least one field")` before calling `as_struct(exprs)` if
  `n == 0`.
- Header/API.jl/Julia: `as_struct(exprs...)`, converting String/literal args like the others.
- Test: `as_struct(col("a"), col("b"))` then extract fields back via the existing
  `Structs.field_by_name`/`field_by_index` to round-trip-verify -- this also finally gives
  `test/datatypes/structs.jl` a way to construct a struct purely from an expression pipeline
  (previously only possible via `Vector{<:NamedTuple}` at DataFrame-construction time or
  `value_counts`), and the empty-input error path (`@test_throws`).

## Cargo.toml changes
Add `"interpolate"` to the `polars` feature list. Nothing else.

## Verification
Build (`cd c-polars && cargo build -j 1`, memory-safety-tripped Monitor pattern -- check `free -m`
first), restart Julia, exercise each item live before writing its test, matching the order above
(B1 → B2 → B3 → B4 → B5, per the original priority ranking). Then run the full suite via the
scratch-env workaround, commit.
