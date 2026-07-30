# Batch 1 parity note: expr/math.jl, expr/arithmetic.jl

Upstream sources fetched to `/home/simba/workspace/pypolars-ref/`: `test_arithmetic.py`,
`test_pow.py`, `test_neg.py`, `test_abs.py`, `test_clip.py`, `test_bitwise.py`, plus
`series_test.py` (round/sign), `exprs_test.py` (log/exp), `expr_dunders.py` (py-polars
`Expr.__and__`/`__or__`/`__xor__`/`__neg__` dunder source, to resolve the Kleene-logic question
below).

## Fixtures ported (all live-verified before asserting, Step 7)

| function | upstream test | fixture | category | outcome |
|---|---|---|---|---|
| `sqrt` | `test_sqrt_neg_inf` | `[-Inf,-9,0,9,Inf]` → `[NaN,NaN,0,3,Inf]` | domain edge | matches; added |
| `round` | `test_round_int` | `Int` column → identity (no-op) | happy path / dtype | matches; added |
| `clip` | `test_clip_int` | null in `min`/`max` column passes that row through unclamped on that side | null propagation | matches exactly (`[1,1,4,4,5,missing]`); added |
| `log` (base e) | `test_log_exp` (domain via manual extension) | `[0.0,-1.0,e]` vs `lit(e)` → `[-Inf, NaN, 1.0]` | domain edge | matches; added |
| `abs` | `test_abs`, `test_abs_non_numeric` | `[-1,0,1,missing]` → `[1,0,1,missing]`; String column raises | null propagation + wrong-dtype (Step 5) | matches (`PolarsError`); added |
| `+`/`-`/`*` | `test_arithmetic_null_count` | one-null-operand and all-null-column cases | null propagation | matches; added (see workaround note below) |
| `&`/`\|` | none dedicated upstream (behavior confirmed from `polars-compute::boolean::and/or` kernel source directly, see below) | mixed true/false/missing operands | null propagation (Kleene) | matches; added |
| `pow` | `test_power_series` | `col ^ lit(missing)` raises | wrong-dtype/domain (Step 5) | matches (`PolarsError`); added |
| bitwise `\|` on **integer** column | `test_bitwise_6311` | `Int` column `\| 2` (not just Bool) | happy path, different dtype than existing test | matches; added |

## Not ported (Step 4 exclusions)

- `test_round_sig_figs*` — `round_sig_figs` has no Julia binding (n/a, no counterpart).
- `test_pow_dtype`, `test_power_series`'s per-width dtype-preservation assertions
  (`UInt8**UInt8→UInt8`, etc.) — Polars.jl has no public dtype-introspection API to assert
  against cleanly; only the *values* are portable, which are already covered by the existing
  "arithmetic edge cases" testset.
- `test_arithmetic_datetime`, `test_arithmetic_duration_div_multiply`, decimal/i128/u128
  arithmetic, `test_float_truediv_output_type` — dtype-shape assertions, not portable the same way.
- `test_bitwise_bool_ops_deprecated` — asserts a Python-side *deprecation warning* for mixed
  bool/int without an explicit cast; not a runtime-behavior test, doesn't port.
- `test_clip_string_input`, `test_clip_bound_invalid_for_original_dtype`,
  `test_clip_non_numeric_dtype_fails` — not ported this batch; see gap below (single-sided
  `clip_min`/`clip_max` don't exist, so the exact upstream call shape isn't reachable).

## Genuine gaps found (flagged, not fixed — out of scope for this sweep per triage decision)

1. **Unary negation (`-expr` / `.neg()`) does not exist at all** — no Rust FFI symbol (`grep neg
   c-polars/src/expr.rs` finds nothing), no Julia binding. `-col("a")` currently raises
   `MethodError: no method matching -(::Polars.Expr)`.
   **Do not hand-roll it as `0 .- expr`** — live-verified this gives *wrong* results: upstream
   `test_neg_unsigned_int` requires `-col("a")` on a `UInt8` column to raise
   `InvalidOperationError`, but composing via the existing `sub` silently wraps
   (`UInt8[1,2,3]` → `0xff,0xfe,0xfd` instead of raising). Needs a real
   `c-polars/src/expr.rs` `polars_expr_neg` wrapping upstream `Expr::neg()`, which has its own
   dedicated per-dtype validation — a new Rust/FFI addition, not a Julia-side fix. Recorded in
   `LEDGER.md`.
2. **No `clip_min`/`clip_max` (single-sided clip) or floor-division (`//`) exposed** — only the
   two-sided `polars_expr_clip` FFI function exists. Same bucket: new Rust FFI, not fixed here.
3. **`DataFrame((; a = [missing, missing]))` (a bare, untyped all-`missing` column) crashes** with
   `UndefVarError: T not defined in static parameter matching` in `format(::Type{Missing})`
   (`src/arrow/array.jl:108`) instead of raising a clean error or working. Root cause: `format(::Type{Nothing}) = "n"`
   exists (added for the Phase-5 gap-closure Null-dtype fix) but no matching
   `format(::Type{Missing})`/`arrowvector(::Vector{Missing})` pair — `Vector{Nothing}` at least
   fails with a catchable `MethodError`, `Vector{Missing}` does not. **This is Julia-side and pure
   Julia-side bugs are in scope for this sweep's triage rule, but it's out of place in a
   math/arithmetic batch** — it belongs with `dataframe/construction.jl` (Batch 12, ledger already
   routes it there). Worked around here by using explicitly-typed
   `Union{Missing,Int}[missing, missing]` fixtures instead of the bare literal.

## Resolved non-issues (verified before assuming a bug)

- **Kleene three-valued logic for `&`/`\|`**: first-pass reading of the live Julia output looked
  like `false & missing` was returning `missing` instead of `false` — a misread of the printed
  array (off-by-one on which row was which), not a real bug. Verified against
  `polars-compute-0.54.4/src/boolean.rs`'s `and`/`or` kernels directly (both explicitly documented
  as "Kleene logic", confirmed `Expr.__and__`/`__or__` in py-polars' `expr.py` route through the
  exact same `Expr::and`/`Expr::or` our C ABI already calls) — our wrapper's output was correct in
  both directions (`false & missing == false`, `true \| missing == true`). Kept the test (it was
  simply *untested*, not broken) rather than discarding it once the confusion was resolved —
  matches the recipe's Step 7 discipline of verifying live before concluding anything.
