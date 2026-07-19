# Land the codebase-review improvements, priority-ranked

## Status

In progress (branch `review-one`). P0 was already resolved by an earlier commit on this branch
(`9bf0fbd`) before this plan's execution began — verified below, no new commit needed for it.

## Context

A full review of Polars.jl (branch `review-one`) verified the three earlier hardening passes held
up, and found a remaining set of issues: one genuine memory-safety bug (GC use-after-free in the
`Value` accessors), two uncommitted stragglers in the working tree, a resource leak, a structural
panic-guard blind spot in the Rust layer, two O(n²) performance defects, and assorted
consistency/CI/hygiene debt. This plan lands those fixes in priority tiers P0–P5. Each tier is
independently verifiable and committable, so execution can stop cleanly at any tier boundary. P5
items are explicitly deferred to separate efforts.

## P0 — Resolve the uncommitted working tree

**Already done before this plan's execution** (commit `9bf0fbd "fix"`, predating this session):
- `c-polars/src/dataframe.rs`'s `polars_lazy_frame_collect_schema` already uses `out.write(...)`
  instead of `*out = ...`, with the UB explanation comment in place.
- `test/aqua.jl:12`'s `ambiguities = (broken = true,)` is already restored (not commented out),
  matching the file's own comment that the ambiguities are real.

Verified: `cargo build -j 4`, `cargo clippy --all-targets -- -D warnings`, `cargo test` all clean;
Aqua testset passes with `ambiguities = (broken = true,)` in place.

## P1 — Memory safety: Value GC use-after-free + Series constructor leak (Julia-only)

Why: the only remaining memory-unsafety reachable from normal use. `ccall` roots arguments passed
through `cconvert`/`unsafe_convert`; passing raw `value.ptr` bypasses that, so a dead wrapper can be
finalized (running `polars_value_destroy`) while Rust still uses the pointer — ccalls are
GC-safe regions, so another thread's GC can do this mid-call.

Replace `value.ptr` with `value` at all six sites so the existing
`Base.unsafe_convert(::Type{Ptr{polars_value_t}}, ::Value)` (`src/value.jl:15`) roots the wrapper
for the duration of each ccall:
- `src/value.jl:124` (`polars_value_duration_get`), `:144` (`polars_value_datetime_get`), `:164`
  (`polars_value_date_get`), `:174` (`polars_value_time_get`)
- `ext/PolarsTimeZonesExt.jl:14` (`polars_value_datetime_get`), `:29` (`polars_value_time_zone`)

Fix the extension's cross-statement borrow at `ext/PolarsTimeZonesExt.jl:28-31`:
`polars_value_time_zone` returns a pointer into the value's Rust-owned memory, and `unsafe_string`
(an allocating call — a GC point) reads it in a later statement. Wrap the ccall and the
`unsafe_string` in a single `GC.@preserve value begin ... end` block.

Fix the Series constructor leak (`src/series.jl:11-25`): three ccalls + `load_series_schema` run
before `finalizer(polars_series_destroy, series)` is registered; `parse_format` throws on
unsupported dtypes (e.g. fixed-size list, `src/arrow/schema.jl:134`), leaking the owned pointer.
Wrap the pre-finalizer body in `try ... catch; polars_series_destroy(ptr); rethrow(); end` (the
generated wrapper accepts a raw `Ptr`, so calling it directly is fine).

Tests: add a GC-stress smoke test to `test/misc_ffi_safety.jl`: materialize date/time/tz values in
a loop with interleaved `GC.gc()` (documents intent; won't deterministically catch regressions).

## P2 — Rust: close the panic-guard blind spot + destructor uniformity (C ABI change)

Why: `guard_error` covers all execution paths except three functions that return Arrow structs by
value and therefore can't use the error-pointer convention: any panic inside them aborts the whole
Julia process. They sit on hot paths (Series construction, column names). Breaking the C ABI is
acceptable — the header/bindings/.so all live in and version with this repo.

Convert the three by-value exports to out-param + error-pointer (follow the exact shape of
`polars_lazy_frame_collect_schema`):
- `polars_series_schema` (`c-polars/src/series.rs:35`) → `(series, out: *mut ArrowSchema) -> *const polars_error_t`
- `polars_series_export_carray` (`series.rs:46`) → `(series, out: *mut ArrowArray) -> *const polars_error_t`;
  also replace the unguarded `rechunked.chunks()[0]` with a `match .first()` that returns
  `make_error` on `None`
- `polars_dataframe_schema` (`dataframe.rs:82`) → `(df, out: *mut ArrowSchema) -> *const polars_error_t`

Add the missing null asserts for uniformity: `polars_dataframe_destroy` (`dataframe.rs:130`) and
`polars_dataframe_schema`.

Header + bindings workflow: hand-edit `c-polars/include/polars.h` → `check_header_drift.py` →
`julia --project=gen gen/generate.jl` → `runic -i src/api/generated.jl`.

Update the Julia call sites to the `Ref` pattern already used by `collect_schema`:
`src/series.jl:14`, `src/arrow/read.jl:80` (`polars_series_schema`), `src/arrow/read.jl:86-117`
(`polars_series_export_carray`, hoisted into one small helper), `src/dataframe.jl:101`
(`_column_names`), `:112` (`schema`).

Note: the ownership-convention doc comment in `c-polars/src/lib.rs:1-19` was already updated to
describe the real `&mut`-borrow pattern (not stale). Only `CLAUDE.md`'s matching paragraph still
described the old `Box::from_raw`+`mem::forget` pattern and needed the same fix.

## P3 — Performance fixes (Julia-only)

O(n²) list flattening (`src/arrow/array.jl:367` and `:375`): `reduce(vcat, ...; init = T[])` misses
Base's optimized single-allocation `vcat` and degrades to left-fold concatenation. Replace with a
preallocated `Vector{T}(undef, Int(offsets[end]))` + `copyto!` loop, using the offsets already
computed two lines earlier.

Benchmark (`Vector{Vector{Int}}`, random sublist length 1-5, warmed up, `@elapsed`):

| sublists (n) | old (`reduce(vcat, ...; init=T[])`) | new (preallocate + `copyto!`) | speedup |
|---|---|---|---|
| 10,000 | 0.39 s | 0.00015 s | ~2,600x |
| 20,000 | 2.09 s | 0.00058 s | ~3,600x |
| 40,000 | 10.31 s | 0.00108 s | ~9,500x |
| 100,000 | (extrapolated: ~64 s) | 0.00280 s | -- |

The old method's timings roughly quadruple on each size doubling (quintic-ish growth observed:
0.39 → 2.09 → 10.31 s for 10k → 20k → 40k), confirming O(n²); the new method scales linearly (its
100k timing, 2.8 ms, is barely 2.6x its 40k timing despite 2.5x the input size). The 500k-sublist
old-method run was aborted after several minutes without completing -- consistent with the O(n²)
extrapolation (~27 minutes) -- since the scaling trend from smaller sizes was already conclusive.

`schema(df)` (`src/dataframe.jl:111-126`): replace the full-frame `null_count` `select` query with
per-column `iszero(df[string(name)].null_count)` — identical semantics (the `Series` constructor
already fetches `polars_series_null_count`, a validity-bitmap count, no query engine), no query.

Positional column iteration O(ncols²) (`src/dataframe.jl:141`): `Tables.getcolumn(df, ::Int)`
re-runs `_column_names` per call. Fix via a `DataFrameColumns` snapshot struct returned from
`Tables.columns(df)`, holding `df` + the names computed once.

Small API completeness: add `Base.size(df::DataFrame, dim::Integer)`.

## P4 — Consistency, docs, CI, hygiene polish

Exports: move scattered top-level `export` statements (`src/describe.jl:64`,
`src/reshape.jl:107,135`) into the canonical block in `src/Polars.jl`. Drop the Base-colliding
exports from the namespace submodules (`Lists`: `get`/`contains`/`head`; `Strings`' overlapping
names) — designed for qualified use; qualify affected tests. Breaking at 0.2.0 is acceptable.

Docstrings: add one for `clone` (`src/lazyframe.jl:55`); extend `@generate_expr_fns` so
Base-qualified methods also get a docstring attached; fix the `src/arrow.jl` path typo in
`ext/PolarsTimeZonesExt.jl:6`.

Repo hygiene: add `.claude/` to `.gitignore`; fix README typo "thWe" (line 11) and add a note that
the walkthrough example is illustrative; add `## Status` lines to `plans/parquet_io_options.md` and
`plans/timezones.md`; refresh stale "not yet committed/pushed" claims in the Done plans' Status
lines.

CI: add a macOS job to the test matrix in `.github/workflows/Tests.yml`.

Optional cosmetics: rename `PolarsEngine` → `polars_engine_t` for header naming uniformity.

## P5 — Deferred (separate plans, not folded into this one)

- Docs reference-page curation (~200 exported symbols absent from `@docs`/`@autodocs` blocks).
- Zero-copy read path revival (`plans/zero_copy_rust_to_julia.md`, unmerged branch, needs its own
  rebase/review cycle).

## Verification

Rust (P0, P2): `cd c-polars && cargo build -j 4` (stable, never nightly), `cargo clippy --all-targets -- -D warnings`,
`cargo fmt --check`, `cargo test`, `python3 check_header_drift.py`. After any header change:
regenerate + `runic -i src/api/generated.jl`.

Live exercise (mandatory after every rebuild): restart the Kaimon REPL, run the touched paths with
real data: non-ASCII column names, each converted export function, nested list/struct columns, a
tz-aware datetime with TimeZones loaded.

Julia suite: scratch env per `CLAUDE.md` — baseline to beat: 1235 passed / 2 broken / 0 failed,
Aqua green.

Per-tier commits so each priority level is a reviewable, revertable unit.
