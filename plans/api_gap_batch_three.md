# API-gap batch (Tier A): fill_null strategy, chained when, concat modes, over options, parameterized casts

## Status

Done. Committed as `914159c` on `review-one`. 49 new tests; full suite **1534 passed / 2 broken
(pre-existing) / 0 failed** (up from the round-four baseline of 1485/2/0). `cargo
build/clippy/fmt/test` clean; header drift clean (262 symbols); docs build clean.

## Context

Follow-on from round four's review (`plans/review_four_fixes.md`), scoping the "API gaps vs
py-polars" item into concrete, immediately-implementable work. Research against the vendored
polars 0.54.4 source (see the scoping session) split the batch into a **Tier A** (no new Cargo
feature needed, so no dependency rebuild) and a **Tier B** (needs a feature flag — `json` for
NDJSON IO, `iejoin` for `join_where`, `dtype-array` for fixed-size-list reads). The user
explicitly asked for **Tier A only** this round, with JSON/NDJSON and the SQL API both
out of scope; Tier B items remain deferred.

## What landed (Tier A)

Five features, each needing no new Cargo feature and no new FFI handle type — every one is a
plain enum mirror (matching the existing `#[repr(C)]` convention) plus a thin wrapper function or
signature extension:

1. **`fill_null(expr; strategy, limit)`** — forward/backward (+ optional `limit`)/mean/min/max/
   zero/one, via `polars_fill_null_strategy_t` (7-variant enum) +
   `polars_expr_fill_null_with_strategy`.
2. **Chained `when(pairs...; otherwise)`** — the native equivalent of py-polars'
   `when(c1).then(v1).when(c2).then(v2)....otherwise(...)`. Flattens to two parallel expr-slices
   (`conds`, `vals`) + a final `otherwise`, folded right-to-left in Rust
   (`polars_expr_when_then`) — confirmed no `When`/`Then`/`ChainedWhen`/`ChainedThen` builder
   handles are needed, since they all fold to one right-nested `Expr::Ternary` chain buildable
   directly from the free `when()`/`Then::otherwise` functions already in use.
3. **`concat(frames; how)`** — `:vertical` (default), `:vertical_relaxed`, `:diagonal`,
   `:diagonal_relaxed`, `:horizontal`, via `polars_concat_how_t`. Diagonal needs no extra Cargo
   feature: `concat_lf_diagonal` is gated behind `diagonal_concat`, but it's just `concat` with
   `UnionArgs.diagonal = true` set internally — calling `concat` directly with that field set
   sidesteps the feature gate entirely. Horizontal routes to the ungated `concat_lf_horizontal`.
4. **`over(expr, partition_by...; mapping_strategy, order_by, descending, nulls_last)`** —
   `:group_to_rows`/`:explode`/`:join` mapping (`polars_window_mapping_t`) plus sort-within-group
   before evaluating, via extending `polars_expr_over`'s signature.
5. **`cast(expr, DateTime; time_unit, time_zone)`**, **`cast(expr,
   Dates.Nanosecond|Microsecond|Millisecond)`** (Duration), **`cast_decimal(expr, precision,
   scale)`**, **`cast_categorical(expr)`** — targeted entry points reusing the existing
   `polars_time_unit_t` enum and `Categories::global()`, since `polars_value_type_t` (the
   existing plain-type-code cast path) can't carry parameters. Casting *to* Categorical reads
   back as `String` with no new read path needed (matches how Categorical/Enum already
   materialize).

Two design fixes discovered and landed during implementation (not part of the original scoping):
- `cast(dtype)`'s curried form was a bare `Base.Fix2(cast, dtype)`, silently dropping any
  `time_unit`/`time_zone` kwargs passed alongside it (`cast(DateTime; time_unit=:ms)` inside a
  `|>` pipe would `MethodError`). Changed to `cast(dtype; kwargs...) = expr -> cast(expr, dtype;
  kwargs...)`, forwarding kwargs. `over`'s curried form was extended the same way for consistency.
- `polars_expr_over`'s new implementation initially converted an empty `partition_by` to `None`
  (to satisfy `over_with_options`'s "at least one of partition_by/order_by" check when order_by
  alone is used) — this broke an existing test relying on `over(bare_expr)` (zero partition
  columns, no order_by) succeeding, since the *original* `Expr::over` wrapper always passed
  `Some(partition_by)` even when empty. Fixed by always passing `Some(..)`, matching upstream's
  own behavior — an empty partition list is itself a meaningful window spec (whole frame as one
  group).

## Deferred (Tier B, not this round)

- **JSON/NDJSON IO** (`scan_ndjson`/`read_ndjson`/`sink_ndjson`, needs the `json` Cargo feature).
- **`join_where`** (inequality/predicate joins, needs `iejoin` on both `polars` and
  `polars-ops`; carries a `panic!("activate 'iejoin'")` hazard at *collect* time until enabled).
- **Fixed-size Array dtype read path** (needs `dtype-array`; reuses the List bulk-reader
  machinery once enabled).
- **`cast` to `List`/`Struct` targets** — needs a recursive FFI dtype descriptor, out of
  proportion for the demand seen so far.
- **Decimal read path** — no native Julia i128/fixed-point representation; needs a design
  decision (raw `i128` + scale, or a weak-dep extension) before it's worth building.

## Verification

Per-feature live exercise (forward/backward fill with/without limit; 3-branch chained `when`;
each `concat` `how`; `over` with each `mapping_strategy` + `order_by` + `descending`; each new
`cast` target round-tripped through `collect`) plus 49 new automated tests across
`test/expr/{null_handling,when_then_otherwise,over,literals_cast}.jl` and
`test/operations/concat.jl`. Full suite 1534/2/0. `cargo build/clippy/fmt/test`, header-drift,
and docs build all clean.
