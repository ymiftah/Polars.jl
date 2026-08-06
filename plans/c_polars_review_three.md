# c-polars Rust-side review (round three)

## Status

**In progress — handed off for local verification.** Branch `claude/c-polars-hardening-review`,
three commits on top of `main`:

| commit | what |
| --- | --- |
| `5536b99` | `guard_error` on every fallible entry point, + `check_panic_guards.py` and its CI step |
| `98d85f1` | `polars_value_t` owns its data (`AnyValue::into_static`) |
| `0d41c9b` | CLAUDE.md: the dependency tree needs stable ≥ 1.95 |

No PR is open, so **CI has not run on any of this**.

### What is and is not verified

> **The Rust changes have never been compiled.** Treat that as the headline. Everything below is
> the honest boundary of what was checked.

Checked:

- `rustfmt --check` clean on all 9 files. This proves the sources *parse*; it is not a typecheck.
- `check_header_drift.py` — same 382 exported symbols as `main`, so the C ABI is provably
  unchanged and no regeneration is owed. This is what makes the branch safe to land incrementally.
- `check_panic_guards.py` passes, and was tested against a deliberately broken function to
  confirm it actually fails rather than passing vacuously.

Not checked: `cargo build`, `cargo clippy --all-targets -- -D warnings`, `cargo fmt --check`,
`cargo test`, and the whole Julia suite.

A local build was attempted and abandoned on cost grounds (two full ~35-minute dependency
compiles, the second forced by the toolchain update below). It ran far enough to be worth
recording: reading the vendored polars source is what surfaced the `_iter_struct_av` panic
described under "Landed", which no amount of static review would have caught.

### Resuming locally

```sh
rustup update stable            # ≥ 1.95 required; see CLAUDE.md and commit 0d41c9b
cd c-polars && cargo build -j 4
cargo clippy --all-targets -- -D warnings
cargo fmt --check
cargo test
cd .. && julia --project=test -e 'import Pkg; Pkg.test()'   # restart any live REPL first
```

Where trouble is most likely, in order:

1. **`value.rs` / `types.rs` / `series.rs`** — the ownership change is the only one that alters
   types rather than wrapping existing code. The borrow checker and the match-exhaustiveness
   check are the real reviewers here.
2. **Clippy on the 57 rewritten `guard_error(|| { … })` closures.** A body that is now a single
   expression inside a block may trip a style lint; `cargo clippy --fix` handles that class.
3. **Julia struct/temporal tests** — `test/datatypes/structs.jl`, `test/datatypes/times.jl`,
   `test/datatypes/durations.jl`. These exercise exactly the accessors whose matched variant
   changed (`StructOwned`, `DatetimeOwned`, `BinaryOwned`). If the ownership change is wrong
   anywhere, this is where it shows.

`src/value.jl`'s `parent` field is deliberately left in place: it is no longer load-bearing, but
removing it is an optimization that wants the Julia suite green first.

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
- **`polars_value_t` owns its data.** It wrapped an `AnyValue<'a>` borrowed from its source, with
  `'a` chosen by the caller and therefore inferred `'static` — the compiler checked nothing, and
  "keep the parent alive, destroy the child first" rested entirely on Julia-side rooting, with
  silent memory corruption as the failure mode. Julia finalizers also run in unspecified order, so
  the ordering half was never really guaranteed. `AnyValue::into_static` in `make_value` deletes
  the rule instead of documenting it harder.
  Two consequences worth knowing: `into_static` *normalizes the variant* (`Struct` →
  `StructOwned`, `Datetime` → `DatetimeOwned`, `Binary` → `BinaryOwned`), so five accessors had to
  follow; and polars-core's `_iter_struct_av` — which the old field accessor called — hits an
  `unreachable!()` on an owned struct, with no greppable message. Indexing the materialized field
  vector is both the correct match and O(1), so per-field struct access stops being O(n²) as a
  side effect. This was found by reading the vendored source, not by review.
  **ABI-neutral**: `polars_value_t` is opaque in the header and lifetimes do not survive into C.
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

1. **`Meta.root_names` is O(n²)** — `polars_expr_meta_root_names_len` and `_get(i)` each recompute
   the entire name vector, and Julia calls `_get` once per name. One new symbol that writes all
   names through the existing callback collapses n+1 tree walks to one.
2. **`nulls_last` is a scalar where `descending` is a per-column mask**, in both
   `polars_lazy_frame_sort` and `polars_expr_sort_by`. `SortMultipleOptions` takes `Vec<bool>` for
   both and py-polars exposes both as lists, so this caps what the Julia API can express.
3. **Signature inconsistencies.** 3 of 8 destructors take `*const` and `cast_mut()` internally
   while the other 5 take `*mut`; `make_expr` returns `*const` while every other factory returns
   `*mut`, which propagates through all 142 expr signatures into the Julia bindings.
   `polars_expr_nth` carries the fallible out-param shape but cannot fail.

## Deferred: needs the Julia suite to land safely

4. **`read_str` accepts `len == 0` as `""`** rather than rejecting it for *required* strings, so
   `polars_expr_col(ptr, 0)` builds `col("")` instead of erroring. A blanket change is wrong —
   empty is legitimate for `group_by_dynamic`'s `offset` and `str_join`'s delimiter — so this
   needs a separate `read_required_str` applied per call site, and new error paths should not be
   introduced without running the Julia tests.
