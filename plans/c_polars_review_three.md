# c-polars Rust-side review (round three)

## Status

**Partially done** (branch `claude/c-polars-hardening-review`). Everything reachable without
touching the C ABI surface is landed; the remaining items all change `include/polars.h` and are
listed under "Deferred" below, unstarted.

Verification for the landed half: `rustfmt --check` clean on all 9 files,
`check_header_drift.py` reports the same 382 exported symbols as before (so the ABI is provably
unchanged), and `check_panic_guards.py` — added by this branch — passes. **Neither `cargo build`
nor `cargo clippy` nor the Julia suite was run**: the review environment had no cargo registry
cache, and a cold polars build is the OOM hazard `CLAUDE.md` documents. CI is the check.

## Landed

- **Every fallible entry point is `guard_error`-wrapped.** Coverage went from 30/87 to 87/87.
  The rule is now the signature (`-> *const polars_error_t` ⇒ guarded), not a per-function
  judgement about which upstream calls look panic-prone — the old phrasing produced 8/9 coverage
  in `io.rs` and 3/142 in `expr.rs`. Includes the functions generated inside `macro_rules!`
  bodies (`gen_horizontal!`, `gen_value_get!`, `gen_series_get!`, `gen_selector_combinator!`),
  which name their function with a metavariable and are easy to miss in a by-hand sweep.
- **`check_panic_guards.py`** enforces that rule in CI, next to the existing header-drift checks.
  Without it the coverage decays again on the next function added.
- **The 14 best-effort `assert!(!ptr.is_null())` calls are gone**, and `lib.rs`'s ownership
  section now says plainly that handle pointers are non-null and unchecked. They covered under
  half the surface and aborted the process when they did fire, so they neither enforced the
  contract nor degraded gracefully.
- **`lib.rs` documents the write-path `&mut` exception** — `write_parquet`/`write_csv`/`write_ipc`
  take `&mut (*df).inner` because upstream's writers align/rechunk while serializing. The value is
  unchanged but the handle's representation is, which the "argument handles are always borrowed"
  rule otherwise reads as excluding.
- **The `mem::take` mutators carry their unwind coupling in a comment.** The take is only sound
  because those functions are unguarded (a panic aborts rather than returning a handle holding
  `LazyFrame::default()`). Anyone adding an error channel there must restore `*df` on the unwind
  path in the same edit.
- **`gen_series_get!`'s error names the expected and actual dtype** instead of
  `"series type is invalid"` for both a dtype mismatch and a null element.
- **`CLAUDE.md` and `plans/ffi_panic_safety.md` no longer claim unwinding across `extern "C"` is
  UB.** It is a defined abort as of Rust 1.81 and this crate pins stable. The Rust sources were
  already correct; only the guidance docs were stale. The distinction matters: "abort" means you
  get SIGABRT plus the panic message, which is what makes the guard rule above tractable.

## Deferred: needs an ABI change

Each of these edits `include/polars.h` and `src/api/generated.jl`, which must be regenerated
(`c-polars/regen_header.sh`, then `julia --project=gen gen/generate.jl`, then
`runic -i src/api/generated.jl`) — neither cbindgen nor Julia was available in the review
environment, and hand-editing either file is forbidden. All of them also need a `libpolars`
version bump before users see them.

1. **`polars_value_t<'a>` launders an unconstrained lifetime** (`series.rs`, `polars_series_get`).
   `'a` is caller-chosen, so it infers `'static`, while the value it holds borrows from the
   series. Today the invariant is enforced only by Julia-side rooting discipline, and violating
   it is silent memory corruption. Making `polars_value_t` own its data (`AnyValue::into_static()`)
   deletes the contract outright.
   **Note this one is ABI-neutral** — `polars_value_t` is opaque in the header and lifetimes do
   not survive into C, so it is a pure Rust-side change and much cheaper than its severity
   suggests. It was left out here only because it needs a live build to confirm `into_static()`'s
   signature in polars 0.54.4 and a Julia run to confirm the rooting can then be dropped.
   Highest value of anything in this list.
2. **`Meta.root_names` is O(n²)** — `polars_expr_meta_root_names_len` and `_get(i)` each recompute
   the entire name vector, and Julia calls `_get` once per name. One new symbol that writes all
   names through the existing callback collapses n+1 tree walks to one.
3. **`nulls_last` is a scalar where `descending` is a per-column mask**, in both
   `polars_lazy_frame_sort` and `polars_expr_sort_by`. `SortMultipleOptions` takes `Vec<bool>` for
   both and py-polars exposes both as lists, so this caps what the Julia API can express.
4. **Signature inconsistencies.** 3 of 8 destructors take `*const` and `cast_mut()` internally
   while the other 5 take `*mut`; `make_expr` returns `*const` while every other factory returns
   `*mut`, which propagates through all 142 expr signatures into the Julia bindings.
   `polars_expr_nth` carries the fallible out-param shape but cannot fail.

## Deferred: needs the Julia suite to land safely

5. **`read_str` accepts `len == 0` as `""`** rather than rejecting it for *required* strings, so
   `polars_expr_col(ptr, 0)` builds `col("")` instead of erroring. A blanket change is wrong —
   empty is legitimate for `group_by_dynamic`'s `offset` and `str_join`'s delimiter — so this
   needs a separate `read_required_str` applied per call site, and new error paths should not be
   introduced without running the Julia tests.
