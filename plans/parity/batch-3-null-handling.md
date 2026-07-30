# Batch 3 parity note: expr/null_handling.jl

Upstream sources fetched to `/home/simba/workspace/pypolars-ref/`: `test_fill_null.py`,
`test_is_null.py`, `test_has_nulls.py`, `test_drop_nulls.py`, `test_interpolate.py`,
`test_is_in.py`.

Baseline: this file is already fairly deep (Phase 3 gap-closure work already ported
strategy-based `fill_null`, both `interpolate` methods, `coalesce`, and `is_in`). The gap this
batch found wasn't missing edge cases in what exists, but a **missing function entirely**.

## Genuine gap found and fixed (Julia-side, safe to fix per this sweep's triage rule)

**`has_nulls()` didn't exist at all.** `test_has_nulls.py` (`test_has_nulls_expr`,
`test_has_nulls_group_by`) exercises it heavily upstream. It composes trivially and safely from
the already-wrapped `null_count` (`has_nulls(expr) = null_count(expr) > 0` — no new Rust/FFI
needed, mirrors the existing `log10`-over-`log` composition precedent in `src/expr/expr.jl`).
Live-verified against both of upstream's fixtures before adding:
- `test_has_nulls_expr`: `{a: [1,2,None], b: ["x","y","z"]}` → `has_nulls` gives `a=true, b=false`.
- `test_has_nulls_group_by`: 4 groups with varying null patterns → `[true,false,true,false]`.

Added `has_nulls` to `src/expr/expr.jl` (exported), and to `docs/src/reference/expressions.md`'s
`@docs` block next to `null_count`.

## Fixtures ported (all live-verified before asserting, Step 7)

| function | upstream test | fixture | category | outcome |
|---|---|---|---|---|
| `has_nulls` | `test_has_nulls_expr` | `{a:[1,2,None], b:["x","y","z"]}` | happy path (new function) | matches (`true`/`false`); added |
| `has_nulls` | `test_has_nulls_group_by` | 4 groups, mixed null patterns | happy path, group-by context | matches (`[true,false,true,false]`); added |
| `is_null`/`is_not_null` | `test_is_null_null` | all-null `Series` | empty/all-null edge | matches (`[true,true]`/`[false,false]`); added |
| `fill_null` | `test_fill_null_non_lit` (adapted) | fill value is a **column expression**, not a literal | happy path — a shape our existing tests hadn't exercised (only `lit(...)` fills so far) | matches (`[1,20,3]`); added |

## Not ported (Step 4 exclusions)

- `test_*_parametric` (hypothesis `@given`) across all four files — doesn't port mechanically.
- `test_df_drop_nulls_struct` — this is **`DataFrame.drop_nulls()`** (whole-row drop), a different
  function from the `Expr`-level `drop_nulls` this file tests (Step 9 — don't conflate). Belongs to
  `operations/frame_verbs.jl` (Batch 10), not here.
- `test_fill_null_minimal_upcast_4056`, `test_fill_enum_upcast`, `test_fill_null_static_schema_4843`,
  `test_fill_null_f32_with_lit`, `test_fill_null_decimal_with_int_14331`,
  `test_fill_null_date_with_int_11362`, `test_fill_null_int_dtype_15546` — dtype-preservation/upcast
  assertions; no clean dtype-introspection API to assert against (same reasoning as Batch 1/2).
  `test_fill_null_with_list_10869` — List-dtype fill, belongs to Batch 9 (list namespace).
  `test_fill_null_null_dtype_24451` — fill on a Null-dtype column; overlaps the all-`missing`
  construction bug flagged in Batch 1, deferred to Batch 12.
- `test_forward_fill_chunking_25273`, `test_fill_streaming_matches_in_memory` — chunking/streaming
  internals, not applicable.
- `test_is_null_struct` — Struct-dtype `is_null`; belongs to Batch 9 (struct namespace).
- `test_is_in.py` (775 lines) — skimmed for anything not already covered by the existing `is_in`
  testset; the bulk is dtype-coercion-matrix parametrization (`@pytest.mark.parametrize` over every
  numeric/string/temporal dtype pair) that doesn't port as discrete fixtures the way this sweep
  targets. Nothing pulled from it this batch.

## Resolved non-issues (verified before assuming a bug)

- None — every fixture checked matched on the first try.
