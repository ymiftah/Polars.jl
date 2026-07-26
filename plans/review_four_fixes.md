# Polars.jl review round four — findings & fix plan

## Status

**P0, P1.1, P2, P3 done and verified. P1.2 (bulk list reader) and P4 (DRY polish) were initially
deferred here, then scoped and landed in follow-on sessions — see `plans/bulk_list_reader.md`
(P1.2, landed as a breaking `Vector{Vector{T}}` change) and `plans/ffi_dry_tri_macro.md` (P4).
The API-gap batch (deferred item 2 below) also landed its Tier A slice — see
`plans/api_gap_batch_three.md`.**

Verification (2026-07-19): `cargo build -j 4` clean, `cargo test` 15/15 (including the 4 new
tests), `cargo clippy --all-targets -- -D warnings` clean, `cargo fmt --check` clean,
`check_header_drift.py` clean (256 symbols, no header changes this round). Julia scratch env
(`Pkg.develop(path=".")` + Aqua/Test/Tables/TimeZones/Statistics): full suite **1485 passed / 2
broken (pre-existing) / 0 failed** — exact match to the pre-change baseline, no regressions.
Live-exercised: non-ASCII column names, list/struct columns (bulk vs per-element agreement
confirmed), tz-aware datetime read path (TimeZones extension), `DataFrame` `==`/`hash`, `name()`
on non-ASCII, scan/write round-trips for parquet/CSV/IPC.

**P0 result**: `target/debug/libpolars.so` shrank **4.75 GB → 239 MB** (opt-level 3 + `debug =
false` on all dependencies). Warm-cache benchmark, 5M-row frame: `group_by(1000 groups) +
sum-agg` **~52 ms**, `collect(::Series{Float64})` **~40 ms** — both consistent with genuinely
optimized polars kernels (an unoptimized dev build would be several times slower for numeric
aggregation at this scale).

**Correction, post-review discussion:** the 239 MB dev-build number is *not* representative of
what `[profile.release]` will actually produce — `debug = false` in `[profile.dev.package."*"]`
only covers dependencies; `c-polars` itself still builds under the default `[profile.dev]`
(debuginfo + full symbol table on), confirmed via `file` (`with debug_info, not stripped`) and
`strip`: `strip --strip-debug` only got 228 MB → 215 MB, `strip --strip-all` got to **127 MB** —
the symbol table, not debug info, was the bigger chunk. `[profile.release]`'s `strip` setting was
changed from `"debuginfo"` to `"symbols"` to actually capture that (matches `strip --strip-all`).
A real `cargo build --release` (with `lto = "thin"`, `codegen-units = 1`, the corrected strip
setting) has **not been run yet** — it forces a second full dependency rebuild under different
codegen flags (no cache sharing with the dev-profile build already done), so it carries the same
`-j 1` / OOM-caution as the P0 rebuild above. Deliberately deferred to a later session rather than
run immediately after this correction.

**P0 build note (real incident, worth keeping on record):** the one-time full dependency rebuild
this profile change triggers is not safely buildable at the existing `-j 4` cap on this machine —
a first attempt at `-j 4` right after adding `[profile.dev.package."*"] opt-level = 3` exhausted
RAM+swap and the kernel OOM-killer killed the VS Code host process itself (this session runs as a
VS Code extension), confirmed via `journalctl -k`. Retried at `-j 1` (one rustc worker at a time,
peaking around the size of the single largest crate — `polars-ops` at ~4.7 GB RSS — rather than
four of them concurrently) and completed cleanly in 26m14s. This is now documented in CLAUDE.md's
build-environment section. Subsequent `-j 4` builds (dependencies cached) are back to the normal
fast incremental case, confirmed: 2.3s for a `c-polars`-only rebuild.

**P1.2 finding — the planned bulk list reader doesn't fit the existing `Series`-per-element
contract, so it was not implemented as scoped:** investigation (before writing any unsafe code)
found that `collect(::Series{Series{T}})` for a List column currently returns `Vector{Series{T}}`
— each row is a genuine, independently-owned `polars_series_t` handle (`load_value(::Value{S})
where {S<:Series}` at `src/value.jl:79-88` calls `polars_value_list_get`, which allocates a real
new Rust-side `Series` per row), not a plain Julia `Vector`. `parse_format`'s `"+l"/"+L"` handling
(`src/arrow/schema.jl:122-127`) declares this as the type contract: `eltype` is `Series{T}`, not
`Vector{T}`. The plan's sketch ("slice per row from the offsets buffer → `Vector{Vector{S}}`")
would silently change `collect`'s return type for every List column in the package — a breaking
change dressed as a performance fix, not something to slip in without a deliberate decision. A
real zero-ccall bulk reader would need one of two larger efforts, both out of scope for this
round: (a) a new Rust-side bulk export (e.g. a function returning a whole array of child series
pointers in one call, cutting ccall *count* but not the fundamental per-row allocation), or (b) a
breaking 0.2.0→0.3.0 decision to make `collect` on List columns return plain nested `Vector`s
instead of `Series` objects. Recommend a separate, deliberately-scoped plan for whichever
direction is preferred — not folded into this round.

## Context

Fourth review round of the Julia↔Rust polars wrapper, focused on best practices, memory
alloc/dealloc, performance, and design clarity — with license to challenge design decisions.
Rounds 1–3 already fixed panic safety, UTF-8 lengths, the Value use-after-free, the O(n²)
defects, bulk string reads, and export hygiene; memory management is now fundamentally sound
(all 82 Rust clone sites verified Arc/plan clones; no unconditional deep copies; GC rooting
clean except one site). This round's findings are therefore mostly performance floors, residual
hardening, and strategic debt — plus design verdicts.

## Design verdicts (the "challenge the design" part)

- **Eager-via-lazy: holds up.** Verified: eager DataFrame verbs are `lazy → in-place mutate →
  collect` = 3 FFI calls, Arc-shared source, no data copy, no clone. Keep.
- **Symbol-per-op C ABI + hand-maintained header + Clang.jl generation: holds up.** The drift
  gates (check_header_drift.py + CI regen diff) have caught real drift; the cbindgen alternative
  is blocked upstream (nightly). Keep, no change proposed.
- **Opaque pointer + finalizer memory model: holds up** after rounds 1–3. Residuals are minor (P3).
- **Debug-build dev loop: does NOT hold up.** gen/prologue.jl hardcodes `target/debug/`; the
  debug .so is 4.7 GB; Cargo.toml has no `[profile]` section. Every dev/CI/test/benchmark run
  executes unoptimized polars kernels — for a performance library this invalidates every perf
  impression of the wrapper. Fix in P0 (cheapest highest-value change in the whole review).
- **Distribution story: does NOT hold up.** Registered libpolars_jll is 0.1.1 from the original
  upstream — 153 exported symbols vs this fork's 256 (verified via nm -D). Outside users hit
  undefined-symbol errors at ccall time; the dependency is effectively decorative. Needs its own
  effort (deferred; see below).
- **`when(cond, then, otherwise)` rigid ternary and `cast`'s narrow target list: real API-design
  shortfalls** vs py-polars (no multi-branch conditionals; no cast to Datetime/Duration/
  Categorical/Decimal/List/Struct). Deferred feature plan, not this round.
- **Docs reference pages as hand-listed `@docs` blocks: structural drift** — the ~200-symbol
  checkdocs gap can't close permanently without `@autodocs` or a coverage gate. Deferred.

## P0 — Stop running debug polars (build profile + library resolution)

1. `c-polars/Cargo.toml`: add
   ```toml
   [profile.dev.package."*"]
   opt-level = 3
   debug = false

   [profile.release]
   lto = "thin"
   codegen-units = 1
   strip = "debuginfo"
   ```
   `dev.package."*"` optimizes all dependency crates (all polars kernels) while the thin
   c-polars shim stays opt-level 0 / incremental; build scripts and proc macros are governed by
   `build-override`, so they're unaffected. One-time full dependency rebuild (cached after);
   `debug = false` should also collapse the 4.7 GB artifact. RAM guard: build with `-j 4` as
   always; if thin-LTO release linking OOMs, drop to `codegen-units = 4` and note it.
2. `gen/prologue.jl`: prefer `target/release/` over `target/debug/` when both exist (keep the
   debug fallback and the JLL default). Then regenerate `src/api/generated.jl`
   (`julia --project=gen gen/generate.jl` + `runic -i`) since the prologue is pasted into it.
3. Update CLAUDE.md's build-environment section (dep artifacts now optimized; rebuild-cost note).
4. Verify: rebuild, restart Kaimon REPL, run a before/after benchmark (e.g. `group_by`+`agg` and
   `collect` on a ~1–10M-row frame) and record numbers in the plan. Full suite in scratch env
   (baseline 1485/2/0).

## P1 — Read path: type-stable `collect` + bulk List reader

The last hot per-element paths (src/arrow/read.jl, src/value.jl:79-88): each list row builds a
full Julia `Series` (~6 ccalls + schema parse per row); every `collect` re-fetches the schema.

1. **Store the Arrow format on `Series` at construction.** The constructor (src/series.jl:11-36)
   already fetches the schema; extend `load_series_schema` to also return the format string and
   add a `fmt::String` field (dictionary flag folded in, e.g. `fmt = ""` sentinel as
   `_schema_format!` does). `read_series` then dispatches on `series.fmt` — delete its per-call
   `polars_series_schema` + parse (read.jl:90-93). Refactor the branch body into
   `_dispatch_read(fmt, series, zerocopy)` as a function barrier. Preserve the
   `zerocopy=true` opt-in and the `nothing`-fallback contract exactly.
2. **Bulk `"+l"`/`"+L"` list reader.** In the list branch: fetch the schema once (cold), read the
   child format from `schema.children` *before* releasing it; export the carray; child array =
   `unsafe_load(ca.children, 1)` wrapped in a non-owning view (its release must be a no-op —
   the parent's release frees children; keep the parent `ExportedArray` alive throughout).
   Materialize the child **once** via `_dispatch_read(child_fmt, ...)`, then slice per row from
   the offsets buffer (`buffers[2]`, Int32/Int64) → `Vector{Vector{S}}` (+ Missing via validity).
   Recursion gives list-of-list for free. Stretch (attempt, else explicitly defer): struct
   `"+s"` — bulk-read each child column, zip into NamedTuples.
3. Benchmark a ~100k-row list column before/after; record. Tests: list with nulls, empty lists,
   list-of-list, sliced series (`ca.offset != 0`), plus struct if landed
   (test/datatypes/series.jl / lists.jl).

## P2 — Rust hardening + move semantics (no ABI change)

1. **Extend `guard_error` to `scan_parquet`/`scan_csv`/`scan_ipc`** (c-polars/src/io.rs:113,
   177, 266) — they do eager FS/schema-inference work that can panic upstream → process abort.
2. **Drop the redundant internal clone in in-place mutators**: `*df = df.clone().select(...)` →
   `std::mem::take(&mut (*df).inner).select(...)` (LazyFrame derives `Default` — verified in
   vendored polars-lazy 0.54.4). Sites: dataframe.rs:401, 438, 449, 463, 981, 987. For
   expr.rs:394 (`sort_by` on Expr) apply only if `Expr: Default`; otherwise leave with a comment.
3. Minor: add the missing null assert to `polars_dataframe_size` (dataframe.rs:27); replace
   io.rs:431's infallible `NonZeroUsize::new(1024).unwrap()` with a `const`; doc note on
   `polars_series_export_carray` that rechunk deep-copies fragmented series.
4. **tests.rs additions** (per its own safety mandate): valid multi-byte UTF-8 round-trip;
   `UserIOCallback` error paths (callback returns -1; overlong-write guard, ffi_util.rs:122-133);
   `export_carray`/schema `out.write` smoke test incl. a multi-chunk series; scan of a malformed
   file returns an error, not an abort.
5. Verify: `cargo build -j 4`, clippy `-D warnings`, fmt, `cargo test`, drift check (no header
   change expected); REPL restart + live scan/select/collect exercise; full suite.

## P3 — Julia-side hygiene + TTFX + thread-safety doc

1. `name(series)` (src/series.jl:158-162): wrap borrowed-pointer read in `GC.@preserve series`.
2. `DataFrame(table)` (src/dataframe.jl:13-23): release the `ArrowArray` on the error path
   (currently only the schema is released in `finally`; a failed import leaves the array rooted
   in `LIVE_ARRAYS` forever). Only on error — on success Rust owns it.
3. Marshalling unification: `join_asof`'s inline `_name_ptrs` copy (src/join.jl:111-114) and
   `Structs.rename_fields`'s implicit-cconvert style (src/expr/struct.jl:36-42) → `_name_ptrs`.
4. `pivot` (src/reshape.jl:81, 97): hoist the duplicate `lazy(df)` into one call.
5. Add `Base.==`/`Base.hash` for `DataFrame` (structural: names + columns via `collect`).
   Deliberately NOT overriding `Series` `iterate` (materializing inside iteration risks memory
   blowup on huge columns; `collect`/`copy` already hit the bulk path).
6. **PrecompileTools workload**: small `@compile_workload` (build a 2-column frame, expr chain,
   `select`/`filter`/`collect`, `collect(::Series)`) — currently zero TTFX mitigation.
7. **Thread-safety stance** (doc-only): a short section in docs limitations page + CLAUDE.md:
   handles are unsynchronized (one frame per task), Arrow release callbacks are the only locked
   paths, rayon's pool is independent of Julia threads, `POLARS_MAX_THREADS` controls it.
8. Docstring nits on this branch: `cast` (document the rejected targets: DateTime/Duration/
   List/Struct error), `Structs.field_by_name`/`field_by_index` ("series" → `Expr`),
   `alias`/`prefix`/`suffix` arg-name mismatches.
9. Verify: full suite + docs build (`julia --project=docs docs/make.jl`).

## P4 — Rust DRY polish (optional tier; stop-at-boundary is fine)

Collapse the 50+ repeats of `match read_str(...) { Ok => x, Err => return make_error(err) }`
across dataframe.rs/expr.rs/io.rs with a small `tri!` macro (chosen over the inner-
`PolarsResult` refactor: keeps every extern fn's shape unchanged and auditable, minimal churn).

**Deliberately not doing** (assessed, rejected):
- `c_enum!` macro for the ~18 enum mirrors — explicit exhaustive matches are the repo's
  auditability style; a macro trades that for indirection with no safety gain.
- Const-correctness sweep (*mut → *const on series/value getters) — header+regen churn across
  ~40 symbols for zero behavior change.
- `sort`'s `descending`-mask vs `nulls_last`-scalar asymmetry — mirrors upstream polars' own API.

## Deferred — separate plans (strategic, out of this round's scope)

1. **Cut a new libpolars_jll from this fork** (Yggdrasil/BinaryBuilder) — the single blocker for
   outside installation (153-symbol stale JLL vs 256 needed). Interim option: attach release
   `.so` artifacts to GitHub releases + a lazy artifact override.
2. **API-gap feature batch** (priority order): chained `when/then/otherwise` builder; `cast` to
   Datetime/Duration/Categorical; `fill_null` strategies; `concat` horizontal/diagonal; `over`
   mapping_strategy; `join_where`; JSON/NDJSON IO; Categorical/Decimal dtype surface. Note:
   `plans/analytics_gap_batch2.md` (rolling/corr/EWM/cut) appears unshipped — reconcile first.
3. **Docs restructure**: `@autodocs`-based reference pages to close the ~200-symbol checkdocs
   gap structurally, then drop `warnonly=[:missing_docs]`.
4. **CI**: Windows job (needs .dll handling), CompatHelper, TagBot, a scheduled run.

## Verification (per tier and final)

- Rust tiers: `cd c-polars && cargo build -j 4` (stable), clippy `-D warnings`, `cargo fmt
  --check`, `cargo test`, `python3 check_header_drift.py`; regen + runic after any
  header/prologue change.
- Live exercise after every rebuild (clean build ≠ safe): restart Kaimon REPL; exercise scans,
  eager verbs, list/struct columns, non-ASCII names, tz-aware datetimes (TimeZones scratch env).
- Julia suite: scratch env (`Pkg.develop(path=".")` + Aqua/Test/Tables/TimeZones), baseline to
  beat: **1485 passed / 2 broken (pre-existing) / 0 failed**.
- Record P0/P1 benchmark numbers in the plan Status (repo convention).
- Per-tier commits; update `plans/review_four_fixes.md` Status as tiers land.
