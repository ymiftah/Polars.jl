# Parquet IO options: scan_parquet / read_parquet / write_parquet / sink_parquet

## Status

Done. `scan_parquet`/`read_parquet` expose `n_rows`, `row_index_name`/`row_index_offset`,
`parallel`, `low_memory`, `rechunk`, `cache`, `glob`, `use_statistics`, `allow_missing_columns`,
`include_file_paths`, `hive_partitioning`; `write_parquet`/`sink_parquet` expose `compression`,
`compression_level`, `statistics`, `row_group_size`, `data_page_size` (`sink_parquet` additionally
`mkdir`/`maintain_order`). `read_parquet` is `collect ∘ scan_parquet`, as planned. Covered by
`test/lazyframe/scan_parquet.jl`/`test_porting.md`'s Phase 4.

## Context
Every parquet reader/writer in this package currently hardcodes `Default::default()` for its
polars options struct on the Rust side and exposes only a bare `path` on the Julia side
(`src/Polars.jl:177-215`, `c-polars/src/lib.rs:227-283,411-428,477-498`). The user needs real
control over reader/writer behavior (row limits, row index columns, hive partitioning,
compression, statistics, etc.) that the underlying `polars` crate already supports but this
wrapper doesn't expose. Scope was narrowed to **Parquet only** (`scan_parquet`, `read_parquet`,
`write_parquet`, `sink_parquet`) — CSV/IPC are left with bare-path signatures for a future pass,
following the same pattern established here.

## Design precedent found in the codebase
- **Optional scalars cross the FFI boundary as nullable pointers** (`*const T`, null = `None`).
  Established precedent: `polars_expr_sample_n`/`sample_frac`'s `seed: *const u64`
  (`c-polars/src/expr.rs:752-763`), marshalled on the Julia side in `src/expr.jl:661-669` as
  `seed === nothing ? Ptr{UInt64}(C_NULL) : Ref(UInt64(seed))` under `GC.@preserve`. Reuse this
  exact pattern for every new `Option<T>` field below.
- **Optional strings** follow the same idea as a `(ptr, len)` pair: null ptr (+ len 0) = `None`.
  No existing precedent for *optional* strings specifically, but it's the natural extension of the
  existing required-string convention (`(Ptr{UInt8}, Csize_t)`, doc'd in CLAUDE.md).
- **New enums mirror existing `@cenum` style** (`polars_quantile_method_t` in
  `src/API.jl:103-109`, similarly named Rust `#[repr(C)]` enum + `to_*()` match method).
- **Eager-from-lazy**: CLAUDE.md's stated preference is `collect ∘ op ∘ lazy` for eager ops.
  `read_parquet` currently has its own standalone Rust path
  (`polars_dataframe_read_parquet`, `c-polars/src/lib.rs:259-283`) instead of reusing
  `scan_parquet`. This pass retires that duplicate function and redefines
  `read_parquet(path; kwargs...) = collect(scan_parquet(path; kwargs...))`, so all the new read
  options apply to both for free. Confirmed `polars_dataframe_read_parquet` /
  `ParquetReader` have no other callers in this repo.

## Key research findings (save re-deriving these)
- `ScanArgsParquet` (`polars-lazy` `LazyFrame::scan_parquet`) fields worth exposing: `n_rows`,
  `row_index` (name+offset), `parallel` (`ParallelStrategy`), `low_memory`, `rechunk`, `cache`,
  `glob`, `use_statistics`, `allow_missing_columns`, `include_file_paths`, and
  `hive_options.enabled` (`Option<bool>`). **Deliberately excluded** (future work, would need new
  subsystems this codebase doesn't have yet): `cloud_options`/credentials (remote storage —
  out of scope, this package targets local files), `schema`/full `hive_options.schema` (needs a
  general `DataType` marshalling layer that doesn't exist — there's no `polars_data_type_t` today,
  confirmed via grep), `column_mapping`, `default_values`. Column projection is intentionally
  **not** added as a scan-time option — `select()` on the resulting `LazyFrame` already gets
  projection pushdown for free through the existing lazy engine.
- `ParquetWriteOptions` (writer, used by both `write_parquet` and `sink_parquet`) fields worth
  exposing: `compression` (`ParquetCompression` enum) + level, `statistics` (bool — collapse the
  4-field `StatisticsOptions` to a single on/off toggle matching polars' own default
  min/max/null_count-on set), `row_group_size`, `data_page_size`. Excluded: `key_value_metadata`,
  `arrow_schema`, `compat_level` (advanced/rare).
- `UnifiedSinkArgs` (sink-only, `polars-plan`) — trivial extra bools worth adding since they're
  free: `mkdir` (auto-create parent dirs, default `false`), `maintain_order` (default `true`).
  Skip `cloud_options`/`sinked_paths_callback`.
- **`GzipLevel`/`BrotliLevel`/`ZstdLevel` live in `polars_utils::compression`**, not
  `polars_parquet` (despite being re-exported there) — confirmed by reading
  `polars-utils-0.54.4/src/compression.rs`. `polars-utils` is currently only a *transitive*
  dependency of `c-polars` (present in `Cargo.lock`, not in `Cargo.toml`), so it must be added as
  a direct dependency (`polars-utils = "0.54.4"`, matching the pinned version) to name these types.
  All three have infallible-to-name, fallible-to-construct `try_new(level) -> PolarsResult<Self>`
  — route through the existing `make_error` out-param convention.
- **No missing-feature panic risk for compression codecs**: confirmed `polars-io`'s `"parquet"`
  feature (already active, pulled in via `c-polars/Cargo.toml`'s `polars = {features=["parquet",
  ...]}`) transitively enables `polars-parquet/compression` (`brotli`/`gzip`/`lz4`/`snappy`/`zstd`
  codecs) via `polars-io/Cargo.toml`. No other Cargo feature changes needed.
- `RowIndex.offset` is typed `IdxSize`, which is `u32` unless the `bigidx` feature is active
  anywhere in the build graph (Cargo unifies features workspace-wide). Not currently enabled here,
  so plan for `u32` — **double check at implementation time** (e.g. via a throwaway
  `cargo doc`/type-check) before committing to the FFI signature.

## New enums (add near `polars_quantile_method_t` in `c-polars/src/expr.rs`, or a new spot in
`lib.rs` near the parquet functions — match whichever grouping reads more naturally at
implementation time)
1. `polars_parquet_parallel_strategy_t` — mirrors `ParallelStrategy`: `Auto`, `None`, `Columns`,
   `RowGroups`. Read-side only.
2. `polars_parquet_compression_t` — mirrors `ParquetCompression`'s *algorithm* choice only (level
   passed as a separate nullable pointer, not baked into the enum): `Uncompressed`, `Snappy`,
   `Gzip`, `Brotli`, `Zstd`, `Lz4Raw`. Write-side only (`write_parquet` + `sink_parquet`).

Both get a `@cenum ...::UInt32` mirror in `src/API.jl`, numbered from 0 in declaration order.

## Read side: extend `polars_lazy_frame_scan_parquet`
`c-polars/src/lib.rs:411-428` — replace `ScanArgsParquet::default()` with one built from new
params:
```rust
pub unsafe extern "C" fn polars_lazy_frame_scan_parquet(
    path: *const u8, pathlen: usize,
    n_rows: *const usize,
    row_index_name: *const u8, row_index_name_len: usize,
    row_index_offset: u32,
    parallel: polars_parquet_parallel_strategy_t,
    low_memory: bool,
    rechunk: bool,
    cache: bool,
    glob: bool,
    use_statistics: bool,
    allow_missing_columns: bool,
    include_file_paths: *const u8, include_file_paths_len: usize,
    hive_partitioning: *const bool,
    out: *mut *mut polars_lazy_frame_t,
) -> *const polars_error_t
```
`row_index_name_len == 0 || row_index_name.is_null()` → `row_index: None`, else UTF-8-validate
(fallible → `make_error`) and build `Some(RowIndex { name: ..., offset: row_index_offset })`.
Same null-ptr-means-`None` handling for `include_file_paths` and `hive_partitioning` (deref bool).
Build `HiveOptions { enabled: hive_partitioning_opt, ..Default::default() }`.

Update `c-polars/include/polars.h` prototype and `src/API.jl`'s `polars_lazy_frame_scan_parquet`
ccall to match (mirror the multi-param formatting style already used for e.g.
`polars_dataframe_upsample`).

## Julia entry point: `scan_parquet` (`src/Polars.jl:189-197`)
```julia
function scan_parquet(
        path;
        n_rows::Union{Nothing,Integer} = nothing,
        row_index_name::Union{Nothing,AbstractString} = nothing,
        row_index_offset::Integer = 0,
        parallel::Symbol = :auto,
        low_memory::Bool = false,
        rechunk::Bool = false,
        cache::Bool = true,
        glob::Bool = true,
        use_statistics::Bool = true,
        allow_missing_columns::Bool = false,
        include_file_paths::Union{Nothing,AbstractString} = nothing,
        hive_partitioning::Union{Nothing,Bool} = nothing,
    )
```
Map `parallel` Symbol → enum (error on unrecognized symbol, matching the `pivot`/`column_naming`
precedent in `src/Polars.jl`'s `pivot` function). Marshal every optional field via the
nullable-pointer pattern under a single `GC.@preserve`, call the extended ccall, `polars_error`,
return `LazyFrame(out[])`. Keep the existing docstring's `n_rows`-truncation etc. semantics
documented per-kwarg (short one-liners, matching existing docstring density in this file).

## `read_parquet` becomes `collect ∘ scan_parquet`
```julia
read_parquet(path; kwargs...) = collect(scan_parquet(path; kwargs...))
```
Delete `polars_dataframe_read_parquet` from `c-polars/src/lib.rs`, its prototype from
`c-polars/include/polars.h`, and its ccall wrapper from `src/API.jl` (confirmed no other callers).

## Write side: extend `polars_dataframe_write_parquet` and `polars_lazy_frame_sink_parquet`
Both append the same writer-option tail:
```rust
compression: polars_parquet_compression_t,
compression_level: *const i32,
statistics: bool,
row_group_size: *const usize,
data_page_size: *const usize,
```
`sink_parquet` additionally gets `mkdir: bool, maintain_order: bool` (feeds `UnifiedSinkArgs`,
not `ParquetWriteOptions`).

Add one shared Rust helper in `lib.rs` (used by both):
```rust
fn build_parquet_write_options(
    compression: polars_parquet_compression_t,
    compression_level: *const i32,
    statistics: bool,
    row_group_size: *const usize,
    data_page_size: *const usize,
) -> PolarsResult<ParquetWriteOptions>
```
— validates `compression_level` is `None` for `Uncompressed`/`Snappy`/`Lz4Raw` (bail with a clear
error if set, matching py-polars' own behavior) and constructs
`GzipLevel::try_new`/`BrotliLevel::try_new`/`ZstdLevel::try_new` (all fallible, propagate via `?`)
for the leveled variants. `statistics: true` → `StatisticsOptions::default()`; `false` → all four
bool fields `false`, `binary_statistics_truncate_length: None`.

Update `c-polars/include/polars.h` prototypes and `src/API.jl` ccalls for both functions.

## Julia entry points: `write_parquet`, `sink_parquet` (`src/Polars.jl:203-215`, `278-285`)
Both gain:
```julia
compression::Symbol = :zstd,
compression_level::Union{Nothing,Integer} = nothing,
statistics::Bool = true,
row_group_size::Union{Nothing,Integer} = nothing,
data_page_size::Union{Nothing,Integer} = nothing,
```
`sink_parquet` additionally: `mkdir::Bool = false, maintain_order::Bool = true`. `write_parquet`'s
`path::String` overload (`write_parquet(p::String, df) = open(...)`) needs its kwargs forwarded
through to the `io::IO` method.

## Cargo change
`c-polars/Cargo.toml`: add `polars-utils = "0.54.4"` (direct dep, for `GzipLevel`/`BrotliLevel`/
`ZstdLevel`). No feature-list changes needed elsewhere (see compression-codec finding above).

## Files touched
- `c-polars/Cargo.toml` — add `polars-utils` dep
- `c-polars/src/lib.rs` — 2 new enums + `to_*()` methods, extended `scan_parquet`/
  `write_parquet`/`sink_parquet` signatures, new `build_parquet_write_options` helper, delete
  `polars_dataframe_read_parquet`
- `c-polars/include/polars.h` — matching prototype updates (hand-edited, per CLAUDE.md convention)
- `src/API.jl` — matching ccall updates + 2 new `@cenum` blocks, remove the deleted ccall
- `src/Polars.jl` — rewrite `scan_parquet`, `read_parquet`, `write_parquet`, `sink_parquet` with
  new kwargs; update docstrings
- `test/lazyframe/scan_parquet.jl`, `test/lazyframe/sink_parquet.jl`, `test/dataframe/io.jl` —
  add option coverage (see Verification)
- `plans/parquet_io_options.md` — persist this plan in-repo (CLAUDE.md workflow step 9)

## Verification
1. `cd c-polars && cargo build -j 1` (stable toolchain — watch memory per `rust-toolchain`/build
   env notes; check `free -m` before launching per project convention).
2. Restart the Julia session (Kaimon `manage_repl` with `command="restart"`) — a running session
   won't pick up the rebuilt `.so`.
3. Exercise live before writing tests:
   - `n_rows` truncates a known-size fixture correctly.
   - `row_index_name`/`row_index_offset` produce a correctly-offset index column.
   - Each `parallel` symbol round-trips without error.
   - `hive_partitioning=false` on the existing `year=2023`/`year=2024` scan_parquet.jl fixture
     directory *disables* hive detection (negative-test: `year` column should now be absent/error)
     — confirms the option actually threads through, not just accepted-and-ignored.
   - `write_parquet` with each `compression` symbol, read back via `read_parquet`, confirm
     round-trip data equality.
   - `compression_level` rejected (errors cleanly, not a panic) for `:uncompressed`/`:snappy`/
     `:lz4_raw`; accepted and changes file size for `:zstd` at level 1 vs 22.
   - `statistics=false` still round-trips correctly.
   - `sink_parquet(..., mkdir=true)` creates a nested non-existent directory.
4. Add tests per CLAUDE.md workflow step 8, reusing `test/fixtures.jl`'s `write_temp_parquet`.
5. Run the full suite via the project's scratch-env workaround (never `Pkg.test()`, never
   `--project=test` directly, per CLAUDE.md/Kaimon convention).
