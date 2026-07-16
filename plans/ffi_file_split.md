# Split up c-polars/src/lib.rs

## Status

Done. `lib.rs` (1868 lines) decomposed into `lib.rs` (56), `ffi_util.rs` (67), `types.rs` (218),
`dataframe.rs` (992), `io.rs` (561). `expr.rs`/`series.rs`/`value.rs` untouched content-wise, only
`use`-statement fixups (+ `#[allow(dead_code)]` on 4 enums that lost crate-root reachability once
their consuming functions moved out of `lib.rs` — see "Sharp edges" below). Build clean (zero
warnings, matches pre-split baseline), `cargo fmt --check` and
`cargo clippy --all-targets -- -D warnings` both pass, live Julia smoke test covers every moved
category (write_parquet/write_csv/scan_parquet/sink_parquet/select/group_by+agg/join/join_asof),
full `test/runtests.jl` passes (1090 passed, 3 pre-existing broken, 0 failures). Merged into
`scan-parquet` at `3842aaf`.

**Note (post-merge):** the "mirrors `src/api/*.jl`'s per-category split" rationale below describes
the state of the Julia side *when this work was planned and done*. In parallel, `scan-parquet`
picked up a separate change (`0af9d45`, "Regenerate src/api/ from c-polars/include/polars.h via
Clang.jl") that collapsed `src/api/{dataframe,expr,series,types,value}.jl` into one generated
`src/api/generated.jl`, so that specific Julia-side mirror no longer exists post-merge. The
Rust-side split documented here still stands on its own merits (a 1868-line flat file was hard to
navigate regardless of what the Julia side looks like) — just don't expect a live 1:1 file
correspondence to `src/api/` anymore; check `CLAUDE.md`'s current "Where things live" table instead
of this doc for the up-to-date Julia-side layout.

## Context

The C ABI layer had grown into "a mismash of definitions without clear structure" (the user's own
description) — one flat 1868-line `lib.rs` holding DataFrame ops, LazyFrame ops, LazyGroupBy ops,
scan/sink IO, opaque handle struct defs, and every `#[repr(C)]` enum mirror, all interleaved by
whatever order they were added in. `expr.rs`/`series.rs`/`value.rs` already existed as split-out
files; only `lib.rs` needed decomposing.

A first attempt at this task (separate crashed session) got as far as setting up the worktree and
reading `lib.rs` before an unrelated baseline `cargo build` OOM-killed on this 16-core/15GB-RAM
machine (Cargo's default `-j 16` + debug profile's default `codegen-units=256` against polars'
large dependency graph). This resumed session did all actual file-split work with `cargo build -j 4`
throughout to avoid repeating that crash.

## What changed

Final files under `c-polars/src/`, mirroring the existing Julia-side `src/api/*.jl` split (per this
repo's CLAUDE.md convention that the two sides mirror "almost exactly"):

| File | Contents |
|---|---|
| `lib.rs` | Crate attrs, `mod` decls, `polars_version`, `polars_error_t` + `make_error`/`polars_error_message`/`polars_error_destroy` |
| `ffi_util.rs` | `IOCallback`, `read_names`, `read_opt_str`, `selector_by_name_opt`, `UserIOCallback` + its `impl std::io::Write` |
| `types.rs` | All 6 opaque handle structs (`polars_dataframe_t`/`polars_lazy_frame_t`/`polars_lazy_group_by_t`/`polars_series_t`/`polars_expr_t`/`polars_value_t` — moved here even though 3 of them conceptually "belong" to `series.rs`/`expr.rs`/`value.rs`, since they were *all* physically defined together in `lib.rs` originally, not pre-split as an earlier plan draft assumed) + `make_dataframe` + every `lib.rs`-derived `#[repr(C)]` enum with its `to_*` conversion impl |
| `dataframe.rs` | DataFrame + LazyFrame + LazyGroupBy functions as one bucket (mirrors `src/api/dataframe.jl` 1:1, per CLAUDE.md's own note that the Julia file already covers all three as one category) |
| `io.rs` | `scan_parquet`/`scan_csv`/`scan_ipc`/`sink_parquet`/`sink_csv`/`sink_ipc` + the shared `build_*_write_options` builders (also used by `dataframe.rs`'s `write_*` fns) |

`expr.rs`/`series.rs`/`value.rs` kept their content, only `use` statements changed (explicit
imports from the new modules, replacing the old `use crate::{..., *};` glob-from-crate-root
pattern — itself part of the readability fix, since that glob was exactly the "mismash" complaint).

Mechanically: the actual move was done via a one-off Python script
(`/tmp/.../scratchpad/split_lib.py`, not committed) that partitioned `lib.rs` by exact line ranges
determined from a full read of the file, rather than manual copy-paste — safer for a 1868-line
mechanical reshuffle. Field/method visibility across the new module boundaries was fixed to
`pub(crate)` (the `.inner` field on all 6 opaque structs, the `to_*` conversion methods, the
`ffi_util` helpers, the `io.rs` builder fns) rather than adding accessor methods, matching how
every call site already did bare field access.

## Sharp edges hit during this task (worth knowing for future c-polars reorganization)

- **Rust's "private" visibility means "visible to this module and its descendants", not "this file
  only".** This is *why* `expr.rs`/`series.rs`/`value.rs`'s old `use crate::{..., *};` glob could
  see everything in `lib.rs` (including un-`pub` items like `make_error`) despite `lib.rs` never
  re-exporting anything — they're child modules of the crate root, so private items there were
  already visible to them. Splitting `lib.rs` into sibling modules doesn't preserve this: siblings
  aren't ancestors of each other, so anything crossing a `dataframe.rs`↔`io.rs`↔`types.rs`↔
  `ffi_util.rs` boundary needs explicit `pub(crate)` + an explicit `use crate::other_mod::*;` — a
  private `use` in `lib.rs` no longer helps once the consumer isn't a *direct* descendant scenario
  it used to be (child of crate root reading crate root's private items), it's now a cousin.
- **Moving a `pub unsafe extern "C" fn` out of the crate root into a private submodule can make
  `#[repr(C)]` enum variants it consumes newly trip the `dead_code` "variant is never constructed"
  lint**, even though the function itself keeps exporting fine via `#[no_mangle]` (module privacy
  doesn't affect cdylib symbol export). This hit `PolarsEngine` (moved to `types.rs`) and
  `polars_closed_window_t`/`polars_label_t`/`polars_start_by_t` (stayed in `value.rs`, but their
  only consumers — `group_by_dynamic`/`rolling` — moved to `dataframe.rs`). Fixed the same way this
  codebase already handles it for the other ~8 similar enums: `#[allow(dead_code)]`, since these
  variants are only ever constructed by external Julia callers passing a raw by-value `#[repr(C)]`
  enum across the FFI boundary — something rustc's reachability analysis can't see regardless of
  module structure.
- **A private `use polars::prelude::*;`-style glob at the crate root silently propagating to every
  child module (again via the "private = visible to descendants" rule) hides how much of a file's
  actual dependency surface is implicit.** `series.rs` and `value.rs` had exactly one `use` line
  each pre-split and relied entirely on this; post-split they needed `polars::prelude::*` (and, for
  `series.rs`, the specific `polars_core::utils::arrow::ffi::{self, ArrowArray, ArrowSchema}` path)
  spelled out explicitly. Worth checking for this pattern before extending `c-polars` further.

## Verification performed

1. `cargo build -j 4` — clean, zero warnings (confirmed identical to a from-scratch build of the
   pre-split `lib.rs`, via `git stash` A/B comparison).
2. `cargo fmt -- --check` then `cargo fmt` (minor import-ordering diffs only) — clean after.
3. `CARGO_BUILD_JOBS=4 cargo clippy --all-targets -- -D warnings` — clean (matches the
   `.pre-commit-config.yaml` `cargo-clippy` hook exactly).
4. Live Julia smoke test (scratch `Pkg.develop` environment, `--project` pointed at this package so
   it auto-resolves the freshly rebuilt `c-polars/target/debug/libpolars.so`): eager
   `write_parquet`/`write_csv` round-trip, `scan_parquet`, `sink_parquet`, lazy `select`,
   `group_by`+`agg`, `sort`, `innerjoin`, `join_asof` — one call per moved file/category, not just
   "it compiles".
5. `git diff --stat` confirms `c-polars/include/polars.h` and all `src/api/*.jl` files are
   untouched (expected: `#[no_mangle]` symbol names are unaffected by Rust module structure).
