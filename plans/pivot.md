# `pivot()`: wrapping polars' native Rust Pivot DSL node

## Status
Tier 1, Tier 2, curried forms, and `describe()` are all done, committed, and pushed (originally on
`scan-parquet`, latest `39091ff`; `scan-parquet` has since merged into `main` via PR #1). This plan
covers `pivot()` — the last remaining Tier 3 item from the original roadmap.

## Key finding: this is not a from-scratch composition, it's a real Rust DSL node
The original assessment ("no single Rust function exists for pivot, py-polars composes it in
Python") was **wrong** — confirmed by direct inspection of `polars-plan`/`polars-lazy` 0.54.4:

- `LazyFrame::pivot(self, on: Selector, on_columns: Arc<DataFrame>, index: Selector, values:
  Selector, agg: Expr, maintain_order: bool, separator: PlSmallStr, column_naming:
  PivotColumnNaming) -> LazyFrame` exists in `polars-lazy/src/frame/mod.rs`, gated by the
  `"pivot"` feature — **already active** in `c-polars/Cargo.toml` (used for `unpivot`).
- At plan-build time (`polars-plan/src/plans/conversion/dsl_to_ir/mod.rs:853`), `DslPlan::Pivot`
  expands into: for each distinct value of `on`, build a conditional aggregation
  (`col(value).filter(on_col == that_value)`, substituted into `agg` via a special
  `Expr::Element` placeholder — public constructor `polars_plan::dsl::functions::selectors::
  element() -> Expr`), then wraps everything in an ordinary
  `IRBuilder::group_by(keys, aggs, None, maintain_order, ...)` IR node
  ([dsl_to_ir/mod.rs:1032](dsl_to_ir/mod.rs#L1032)).
- **This means zero new execution-side risk**: it bottoms out in the same `group_by`/`agg`
  executor this package already wraps and tests extensively. Confirmed via the usual
  `"activate .. feature"` panic-risk grep across the conversion path — zero hits.
- The one real constraint: `on_columns: Arc<DataFrame>` (the distinct `on`-column values) must be
  **precomputed eagerly** before building the plan — this is why py-polars only exposes
  `.pivot()` on the eager `DataFrame`, never `LazyFrame`. Same design here: `pivot(df::DataFrame,
  ...)` only, no `pivot(lf::LazyFrame, ...)`.

## Cargo.toml changes
**None** — `"pivot"` is already active.

## Items

### P1 — `element()` (new expr constructor, needed for the `agg` argument)
- **Rust** ([expr.rs](c-polars/src/expr.rs)): `polars_expr_element() -> *const polars_expr_t`,
  body `make_expr(element())` (from `polars_plan::dsl::functions::selectors::element`, likely
  already in scope via the existing `use polars::prelude::*` wildcard — confirm at
  implementation time, add an explicit import if not).
- **Header/API.jl**: prototype + ccall matching neighboring no-arg expr constructors (e.g. `col`).
- **Julia** ([expr.jl](src/expr.jl)): `element()::Expr`, exported (no Base collision --
  `isdefined(Base, :element)` confirmed `false`). This is the placeholder users build their `agg`
  expression from, e.g. `Base.sum(element())`, `Base.first(element())` (the default, matching
  py-polars).

### P2 — `polars_pivot_column_naming_t` enum
- **Rust** ([lib.rs](c-polars/src/lib.rs) or expr.rs, near other small enums): `#[repr(C)]
  polars_pivot_column_naming_t { PolarsPivotColumnNamingCombine, PolarsPivotColumnNamingAuto }`
  (mirroring `polars_core::frame::PivotColumnNaming`'s two variants, `Auto` is the Rust-side
  `#[default]`) + a `to_pivot_column_naming()` match method.
- **Julia**: `@cenum polars_pivot_column_naming_t::UInt32 begin ... end` mirror in API.jl.

### P3 — `polars_lazy_frame_pivot` (the main wrapper)
- **Rust** ([lib.rs](c-polars/src/lib.rs), near `unpivot`): reuses the existing shared
  `read_names`/`Selector::ByName` marshaling helpers exactly as `unpivot` does, for three
  separate name lists (`on`, `index`, `values` -- all required non-empty per polars' own
  `polars_ensure!` checks, so plain `Selector::ByName{names,strict:true}`, not the `Option`-
  wrapping `selector_by_name_opt` used for optional subsets elsewhere). Additional params: an
  `on_columns: *mut polars_dataframe_t` (clone `.inner`, wrap in `Arc::new(...)`), an
  `agg: *const polars_expr_t` (clone `.inner`), `maintain_order: bool`, a `(separator_ptr,
  separator_len)` string pair, and `column_naming: polars_pivot_column_naming_t`. Signature:
  ```rust
  pub unsafe extern "C" fn polars_lazy_frame_pivot(
      lf: *mut polars_lazy_frame_t,
      on_names: *const *const u8, on_lens: *const usize, n_on: usize,
      on_columns: *mut polars_dataframe_t,
      index_names: *const *const u8, index_lens: *const usize, n_index: usize,
      values_names: *const *const u8, values_lens: *const usize, n_values: usize,
      agg: *const polars_expr_t,
      maintain_order: bool,
      separator: *const u8, separator_len: usize,
      column_naming: polars_pivot_column_naming_t,
      out: *mut *mut polars_lazy_frame_t,
  ) -> *const polars_error_t
  ```
  `LazyFrame::pivot(...)` itself returns a plain `LazyFrame` (not `PolarsResult`, matching the
  general "lazy builders defer validation to collect-time" pattern) — the C ABI function is only
  fallible through the UTF-8 validation steps (`read_names`, separator), same shape as `unpivot`.
- **Header/API.jl**: prototype + ccall, matching `unpivot`'s style for the repeated
  `(ptrs,lens,n)` triples.

### P4 — Julia entry point (`pivot`)
- **Julia** ([Polars.jl](src/Polars.jl), near `unpivot`): eager-only, `DataFrame` -> `DataFrame`
  (no `LazyFrame` form, per the design note above):
  ```julia
  function pivot(
          df::DataFrame, on, index, values; agg = Base.first(element()),
          maintain_order::Bool = true, separator::String = "_", column_naming::Symbol = :auto
      )
      on = on isa AbstractVector ? String.(on) : [String(on)]
      index = index isa AbstractVector ? String.(index) : [String(index)]
      values = values isa AbstractVector ? String.(values) : [String(values)]

      on_columns = collect(unique(select(lazy(df), map(col, on)...)))

      naming_enum = column_naming == :auto ? API.PolarsPivotColumnNamingAuto :
          column_naming == :combine ? API.PolarsPivotColumnNamingCombine :
          error("unknown column_naming $column_naming, expected one of (:auto, :combine)")

      GC.@preserve on index values begin
          on_ptrs, on_lens = _name_ptrs(on)
          index_ptrs, index_lens = _name_ptrs(index)
          values_ptrs, values_lens = _name_ptrs(values)
          out = Ref{Ptr{polars_lazy_frame_t}}()
          err = polars_lazy_frame_pivot(
              lazy(df), on_ptrs, on_lens, length(on_ptrs), on_columns,
              index_ptrs, index_lens, length(index_ptrs),
              values_ptrs, values_lens, length(values_ptrs),
              agg, maintain_order, separator, length(separator), naming_enum, out
          )
          polars_error(err)
      end
      return collect(LazyFrame(out[]))
  end
  export pivot
  ```
  (reuses the existing `_name_ptrs` helper already shared by `drop`/`rename`/`unpivot`).

## Verification
Build (`cd c-polars && cargo build -j 1`, memory-safety-tripped Monitor pattern — check `free -m`
before launching), restart Julia, exercise live before writing tests:
- `element()` alone: `select(df, alias(Base.first(element()), "x"))` inside a `group_by`/`agg`
  context first, to confirm the placeholder substitution behaves as expected outside of `pivot`
  too (sanity check before the full pivot call).
- Full pivot: classic wide-reshape fixture, e.g. `DataFrame((; id=[1,1,2,2], var=["a","b","a","b"],
  val=[10,20,30,40]))`, `pivot(df, "var", "id", "val")` -> expect columns `id, a, b` with rows
  `(1,10,20)`, `(2,30,40)`.
- Multiple `values` columns (tests `column_naming`), a custom `agg` (e.g. `Base.sum(element())`
  with duplicate `(id,var)` pairs to confirm aggregation actually happens), and `maintain_order`.

Then run the full suite via the scratch-env workaround (never `Pkg.test()`, never
`--project=test` directly).

## Suggested order
P1 (`element()` — smallest, independently useful/testable) → P2 (enum, trivial) → P3 (main
wrapper, reuses `unpivot`'s exact marshaling shape) → P4 (Julia entry point, mechanical once P1-P3
exist).
