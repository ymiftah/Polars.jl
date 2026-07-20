# FFI DRY: `tri!` macro for the error-mapping boilerplate

## Status

Done. Committed as `e0b7498` ("DRY: collapse 87 error-mapping matches behind a `tri!` macro
(P4)") on `review-one`. Net -243 lines across `c-polars/src/{lib,dataframe,expr,io,series}.rs`.
`cargo build/clippy/fmt/test` (15/15) clean; header drift unchanged (pure body refactor, no
signatures touched); live-smoked select/scan/write/unpivot against the rebuilt `.so`.

## Context

Round four's review flagged 50+ repeats of `match read_str(...) { Ok(v) => v, Err(err) => return
make_error(err) }` across `dataframe.rs`/`expr.rs`/`io.rs` as a DRY opportunity (originally P4 in
`plans/review_four_fixes.md`). A follow-up scoping pass (before implementation) found the actual
count was higher once every `Err => return make_error` shaped match is counted, not just the
`read_*`-specific ones (domain calls like `over`/`concat`/`collect_with_engine`/`sink`/`to_dtype`
follow the identical shape) — 87 sites total, plus 1 unrelated `_ = ` scalar match in `series.rs`.

## What landed

A single crate-root macro:
```rust
macro_rules! tri {
    ($e:expr) => {
        match $e {
            Ok(v) => v,
            Err(err) => return $crate::make_error(err),
        }
    };
}
```
defined in `c-polars/src/lib.rs` before the `mod` declarations (textual macro scoping makes it
visible to every submodule). 85 identity-shaped sites collapsed to `let x = tri!(...);` verbatim;
2 sites that additionally applied `PlSmallStr::from_str` in the `Ok` arm collapsed by wrapping:
`PlSmallStr::from_str(tri!(...))`. The one three-arm match (`Ok(Some)`/`Ok(None)`/`Err`, in
`polars_expr_dt_convert_time_zone`'s time-zone parsing) was deliberately left as hand-written —
`tri!`'s shape doesn't fit a match with more than the two `Result` arms.

Works uniformly whether the site is a plain function body or inside a `guard_error(|| {...})`
closure, since both return `*const polars_error_t` and `return` inside a closure returns from the
closure, not the enclosing function — no `Result`/`?`-operator interaction, since these functions
return a raw error pointer, not `Result`.

## Verification

`cargo build -j 4` / `cargo clippy --all-targets -- -D warnings` / `cargo fmt --check` all clean;
`cargo test` 15/15; `check_header_drift.py` clean (262 symbols — unchanged from before this
effort, confirming zero signature/ABI changes). No Julia-side change, no `generated.jl` regen
needed. Live-exercised via a scratch-env Julia session: non-ASCII `select`, `scan_parquet`,
`scan_csv`, `write_parquet`, `write_csv`, `unpivot`, `unique` — all touched `tri!`-refactored
code paths, all correct.
