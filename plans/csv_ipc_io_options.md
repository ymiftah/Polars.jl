# CSV / IPC IO options: scan_csv / read_csv / write_csv / sink_csv, scan_ipc / read_ipc / write_ipc / sink_ipc

## Status
Done. All of CSV read/write/scan/sink and IPC read/scan/sink options implemented, plus a new
eager `write_ipc` (didn't exist before). Found and fixed a real process-crashing bug along the
way: `sink_csv(...; compression=:gzip)` panicked the whole Julia process because the `polars`
crate doesn't enable `polars-io`'s `decompress` feature by default (see "Cargo change" below) --
fixed by adding it to `c-polars/Cargo.toml`. Full suite: 679 passed, 3 pre-existing broken,
0 failed/errored. Follow-up to `plans/parquet_io_options.md` (done, commit `44cfd1e`), which
deliberately narrowed scope to Parquet only and left CSV/IPC bare-path for "a future pass,
following the same pattern established here." This is that pass.

## Context
`scan_csv`/`read_csv`/`write_csv`/`sink_csv`/`scan_ipc`/`read_ipc`/`sink_ipc` (`src/io/{csv,ipc}.jl`,
`c-polars/src/lib.rs:614-751,386-399`) all currently hardcode `CsvReadOptions::default()`/
`CsvWriterOptions::default()`/`IpcScanOptions::default()`/`IpcWriterOptions::default()` and expose
only a bare `path`. There is also currently **no eager `write_ipc`** at all — only
`scan_ipc`/`read_ipc`/`sink_ipc` exist. Adding it here for parity with parquet/CSV (both have
eager write + streaming sink) since the underlying `IpcWriter` builder makes it essentially free
once `sink_ipc`'s options plumbing exists.

## Key research findings
- **CSV read has a rich builder, unlike parquet's manually-assembled `ScanArgsParquet` struct**:
  `polars_lazy::scan::csv::LazyCsvReader` (`.new(path).with_n_rows(...).with_row_index(...)...
  .finish()`) wraps `CsvReadOptions` + `UnifiedScanArgs` construction. Use this builder rather than
  hand-assembling both structs — matches upstream's own idiom and avoids re-deriving
  `UnifiedScanArgs`'s ~20 fields by hand.
- **`LazyCsvReader` hardcodes `hive_options: HiveOptions::new_disabled()`** in its own `finish()` —
  CSV directory scans do not support hive-partition detection at this API layer at all. **No
  `hive_partitioning` option for CSV** (unlike parquet/IPC) — this isn't a scope choice, it's a
  real gap in the upstream builder that would need bypassing `LazyCsvReader` entirely to fix.
- **IPC read has no dedicated builder** — `LazyFrame::scan_ipc(path, IpcScanOptions,
  UnifiedScanArgs)` takes both structs directly. Build `UnifiedScanArgs` via struct-update syntax
  off `..Default::default()` (confirmed `UnifiedScanArgs: Default`), only overriding the fields we
  actually expose (`hive_options`, `rechunk`, `cache`, `glob`, `row_index`, `include_file_paths`,
  `pre_slice`, `missing_columns_policy`) — do not hand-populate the other ~13 advanced/Iceberg-ish
  fields (`column_mapping`, `deletion_files`, `table_statistics`, etc.), matching parquet's own
  precedent of leaving out-of-scope fields at their default.
- **`n_rows` for both CSV and IPC threads through `UnifiedScanArgs.pre_slice: Option<Slice>`**, not
  a plain `Option<usize>` field like parquet's `ScanArgsParquet.n_rows` — construct
  `Slice::Positive { offset: 0, len: n_rows }` when `Some`. (`Slice` is `polars_utils::slice_enum::Slice`.)
- **`allow_missing_columns` bool → `MissingColumnsPolicy`** (`Raise`/`Insert`, in
  `polars_plan::dsl::file_scan`) for both CSV and IPC — same bool-in/enum-internally shape as
  parquet's own `allow_missing_columns: bool` field (which converts the same way one layer down,
  confirmed by inspecting `ScanArgsParquet` — this wrapper's own choice is just to stay consistent
  with that existing bool-shaped parameter across all three formats).
- **CSV write: `CsvWriter<W>` has its own rich eager builder** (`with_separator`, `with_quote_char`,
  `with_null_value`, `with_line_terminator`, `with_quote_style`, `with_date_format`,
  `with_time_format`, `with_datetime_format`, `with_float_precision`, `with_decimal_comma`,
  `with_batch_size`, `include_header`, `include_bom`) — build directly from raw params in Rust,
  no need to construct `SerializeOptions`/`CsvWriterOptions` by hand for the eager path.
  **`CsvWriter` has no `.with_compression()`** — CSV write-side compression is only reachable
  through the sink pipeline's `CsvWriterOptions.compression: ExternalCompression`. **Deliberate
  asymmetry**: `write_csv` gets no `compression` option (the eager builder doesn't expose it),
  `sink_csv` does (via `CsvWriterOptions`). Not a scope choice — a real gap in `CsvWriter`'s API.
- **`ExternalCompression`** (`polars_io::options`) is CSV's compression enum:
  `Uncompressed | Gzip{level:Option<u32>} | Zstd{level:Option<u32>}` — plain `Option<u32>` levels,
  no `GzipLevel`/`ZstdLevel` wrapper type needed here (unlike parquet), so **no new Cargo
  dependency** — `polars-utils` is already a direct dep from the parquet pass, and is needed anyway
  for IPC's `ZstdLevel::try_new` (below).
- **IPC write: `IpcWriter<W>` also has its own eager builder** (`with_compression`,
  `with_record_batch_size`, `with_record_batch_statistics`, `with_compat_level`, `with_parallel`) —
  **symmetric with `sink_ipc`**, unlike CSV, so `write_ipc` and `sink_ipc` get identical write
  options.
- **`IpcCompression`** (`polars_io::ipc::write`): `LZ4 | ZSTD(ZstdLevel)` — the ZSTD variant *does*
  wrap `polars_utils::compression::ZstdLevel`, fallible via `ZstdLevel::try_new(level)`, route
  through `make_error` like parquet's compression-level handling.
- **No Cargo feature changes needed**: `csv` is in the `polars` crate's own `default = [...]`
  feature list (confirmed in its `Cargo.toml`) so it's already compiled in despite not being named
  in `c-polars/Cargo.toml`'s explicit features list (this explains why bare `scan_csv`/`write_csv`
  already worked pre-this-pass). `ipc` is already explicitly listed. `polars-utils` is already a
  direct dependency (added for parquet's `GzipLevel`/`BrotliLevel`/`ZstdLevel`).
- **`NullValues` (CSV null-value substitution) has 3 variants** (`AllColumnsSingle`, `AllColumns`,
  `Named` per-column mapping) — **scope narrowed to `AllColumnsSingle` only** (a single
  `null_value::Union{Nothing,AbstractString}` covering "treat this one string as null everywhere"),
  matching parquet's precedent of excluding anything needing extra array/dict marshaling beyond
  what's already established. Per-column `Named` mapping is future work if needed.
- **No `hive_partitioning`/schema-marshaling/`cloud_options` for either format**, same rationale as
  parquet: no `polars_data_type_t` marshaling layer exists yet, and this package targets local
  files only.

## New enums (mirror existing `@cenum` style, add near `polars_parquet_compression_t` in
`c-polars/src/lib.rs` or `expr.rs`)
1. `polars_csv_compression_t` — `Uncompressed`, `Gzip`, `Zstd`. Used by `sink_csv` only (`write_csv`
   has no compression option — see above).
2. `polars_ipc_compression_t` — `Uncompressed`, `Lz4`, `Zstd`. Used by `write_ipc` and `sink_ipc`.
3. `polars_quote_style_t` — `Necessary`, `Always`, `NonNumeric`, `Never`. Used by `write_csv` and
   `sink_csv`.

Each gets a `@cenum ...::UInt32` mirror in `src/api/types.jl`.

## CSV read: extend `polars_lazy_frame_scan_csv`
```rust
pub unsafe extern "C" fn polars_lazy_frame_scan_csv(
    path: *const u8, pathlen: usize,
    n_rows: *const usize,
    row_index_name: *const u8, row_index_name_len: usize,
    row_index_offset: u32,
    has_header: bool,
    separator: u8,
    quote_char: *const u8,           // null = no quoting (None)
    comment_prefix: *const u8, comment_prefix_len: usize,  // len 0 = None
    skip_rows: usize,
    skip_rows_after_header: usize,
    null_value: *const u8, null_value_len: usize,          // len 0 (and non-null ptr distinguishing "" vs None) -- see note
    missing_is_null: bool,
    truncate_ragged_lines: bool,
    try_parse_dates: bool,
    infer_schema_length: *const usize,
    ignore_errors: bool,
    low_memory: bool,
    rechunk: bool,
    cache: bool,
    glob: bool,
    include_file_paths: *const u8, include_file_paths_len: usize,
    allow_missing_columns: bool,
    out: *mut *mut polars_lazy_frame_t,
) -> *const polars_error_t
```
Note on `null_value`: unlike other optional strings, CSV's default null-value representation for
*reading* isn't a plain "value" (there IS no read-side null-value default in `CsvParseOptions` —
`null_values: Option<NullValues>`, default `None` meaning "nothing is substituted, missing fields
via `missing_is_null` are the only null source"). Use the same `(ptr, len)` null-means-absent
convention as `row_index_name`/`include_file_paths`.

Build via `LazyCsvReader::new(path)` + chained `.with_*()` calls (see research above), reading
`quote_char`/`comment_prefix` through the null-ptr-means-`None` convention already established for
`hive_partitioning: *const bool` in parquet. `hive_options` is NOT settable — don't add a param for
it (see research: `LazyCsvReader` hardcodes it disabled).

## CSV write: extend `polars_dataframe_write_csv` (build `CsvWriter` directly from params, no
`CsvWriterOptions`/`SerializeOptions` needed for the eager path)
```rust
pub unsafe extern "C" fn polars_dataframe_write_csv(
    df: *mut polars_dataframe_t, user: *const c_void, callback: IOCallback,
    include_header: bool,
    include_bom: bool,
    separator: u8,
    quote_char: u8,
    null_value: *const u8, null_value_len: usize,
    line_terminator: *const u8, line_terminator_len: usize,
    quote_style: polars_quote_style_t,
    date_format: *const u8, date_format_len: usize,
    time_format: *const u8, time_format_len: usize,
    datetime_format: *const u8, datetime_format_len: usize,
    float_precision: *const usize,
    decimal_comma: bool,
) -> *const polars_error_t
```
No `compression` param here (see research — `CsvWriter` doesn't support it).

## CSV sink: extend `polars_lazy_frame_sink_csv` with the write_csv param list above **plus**
`compression: polars_csv_compression_t, compression_level: *const u32, mkdir: bool,
maintain_order: bool`. Build `CsvWriterOptions { include_bom, compression: ExternalCompression::{...},
check_extension: false, include_header, batch_size: NonZeroUsize::new(1024).unwrap() /* not
exposed as a param -- see Non-goals */, serialize_options: Arc::new(SerializeOptions{...}) }`.

## IPC read: extend `polars_lazy_frame_scan_ipc`
```rust
pub unsafe extern "C" fn polars_lazy_frame_scan_ipc(
    path: *const u8, pathlen: usize,
    n_rows: *const usize,
    row_index_name: *const u8, row_index_name_len: usize,
    row_index_offset: u32,
    rechunk: bool,
    cache: bool,
    glob: bool,
    include_file_paths: *const u8, include_file_paths_len: usize,
    hive_partitioning: *const bool,
    allow_missing_columns: bool,
    out: *mut *mut polars_lazy_frame_t,
) -> *const polars_error_t
```
Build `UnifiedScanArgs { hive_options: HiveOptions{enabled: hive_partitioning_opt, ..Default::default()},
rechunk, cache, glob, row_index, include_file_paths, pre_slice: n_rows.map(|len| Slice::Positive{offset:0,len}),
missing_columns_policy: if allow_missing_columns {Insert} else {Raise}, ..Default::default() }`,
pass `IpcScanOptions::default()` unchanged (no exposed IPC-specific scan options — see research).

## IPC write: new `polars_dataframe_write_ipc` (eager, doesn't exist yet) + extend
`polars_lazy_frame_sink_ipc`
```rust
pub unsafe extern "C" fn polars_dataframe_write_ipc(
    df: *mut polars_dataframe_t, user: *const c_void, callback: IOCallback,
    compression: polars_ipc_compression_t,   // has an Uncompressed variant Rust-side maps to None
    compression_level: *const u32,           // zstd only
    record_batch_size: *const usize,
) -> *const polars_error_t
```
Build via `IpcWriter::new(w).with_compression(...).with_record_batch_size(...)`. `sink_ipc` gets
the same 3 params plus `mkdir: bool, maintain_order: bool` (`UnifiedSinkArgs`, matching parquet).

## Julia entry points (`src/io/csv.jl`, `src/io/ipc.jl`)
Mirror `src/io/parquet.jl`'s exact shape: keyword-argified wrapper functions, nullable-pointer
marshaling under `GC.@preserve`, `_csv_compression_enum`/`_ipc_compression_enum`/
`_quote_style_enum` Symbol→cenum helpers (same style as `_parquet_compression_enum`), docstrings
matching existing density. `read_csv`/`read_ipc` stay `collect ∘ scan_*` (already true for csv;
`read_ipc` already is too). Add `write_ipc(io::IO, df) `/`write_ipc(path::String, df; kwargs...)`
following `write_parquet`'s two-method shape exactly, and export it from `Polars.jl`'s main export
list (currently only `read_ipc`/`scan_ipc`/`sink_ipc` are exported, no `write_ipc` — add it).

## Cargo change
**Correction, found during live verification (not caught by research or `cargo check`/`cargo
build` — only surfaces at runtime):** `sink_csv` with `compression = :gzip` panicked the whole
Julia process (`thread 'tokio-rt-worker' panicked at .../polars-io-0.54.4/src/utils/compression.rs:401:9:
activate 'decompress, ' feature`) — a live instance of the exact danger CLAUDE.md documents
("Missing Cargo features are a live version of this danger, not just a hypothetical"). `polars-io`
defaults `decompress` on for standalone use, but the `polars` crate's own `Cargo.toml` disables
`polars-io`'s default features and only re-enables named ones, `decompress` not among them by
default. Added `"decompress"` to `c-polars/Cargo.toml`'s `polars` feature list. **Re-verify gzip
(and zstd, same code path) compression on both `sink_csv` and `write_csv`'s CSV-adjacent paths
after adding this feature** — this is exactly the kind of thing that "compiles fine, crashes at
runtime" per CLAUDE.md's warning, so a clean `cargo build` is not sufficient evidence it's fixed.

## Non-goals (explicitly excluded, same rationale as parquet's exclusions)
- CSV: `schema`/`schema_overwrite`/`dtype_overwrite` (no `DataType` marshaling layer),
  `hive_partitioning` (not supported by `LazyCsvReader` itself), `n_threads`, `skip_lines` (redundant
  with `skip_rows` for the common case), `decimal_comma` on the *read* side, `eol_char`,
  multi-value/per-column `NullValues` variants, `cloud_options`, write-side `batch_size` (internal
  perf tuning, not exposed as a param), `float_scientific`, `check_extension` (forced `false`).
- IPC: `IpcScanOptions.record_batch_statistics`/`.checked` (internal/advanced, low value),
  `compat_level`, write-side `record_batch_statistics`, `with_parallel` (internal perf tuning).

## Files touched
- `c-polars/src/lib.rs` — 3 new enums + `to_*()` methods, extended `scan_csv`/`write_csv`/
  `sink_csv`/`scan_ipc`/`sink_ipc` signatures, new `polars_dataframe_write_ipc`
- `c-polars/include/polars.h` — matching prototype updates
- `src/api/types.jl` — 3 new `@cenum` blocks
- `src/api/dataframe.jl` — new `polars_dataframe_write_ipc` ccall; updated `write_csv`/`scan_csv`/
  `sink_csv`/`scan_ipc`/`sink_ipc` ccalls
- `src/io/csv.jl`, `src/io/ipc.jl` — rewritten Julia entry points with new kwargs + new `write_ipc`
- `src/Polars.jl` — add `write_ipc` to the main export list
- `test/lazyframe/scan_csv.jl`, `test/lazyframe/scan_ipc.jl` (new — doesn't exist yet, only
  `sink_ipc.jl` does), `test/lazyframe/sink_csv.jl` (new), `test/lazyframe/sink_parquet.jl`-style
  options coverage for `sink_ipc.jl`, `test/dataframe/io.jl` — add CSV/IPC options coverage
- `plans/csv_ipc_io_options.md` — this file (persist per CLAUDE.md workflow step 9)

## Suggested order
CSV first (bigger surface, established `CsvWriter`/`LazyCsvReader` builders make it mechanical),
verify with `cargo build` + live session + tests, commit-ready checkpoint. Then IPC (smaller
surface, but adds the brand-new `write_ipc` function — verify that one especially carefully since
it's new public API, not just new options on an existing function). Run the full suite via the
scratch-env workaround after each format; expect the existing 628 passed / 3 broken to grow by
however many new tests are added, 0 failed/errored throughout.

## Verification
1. `cd c-polars && cargo build -j 1` (stable toolchain; check `free -m` first per project convention).
2. Restart Julia session — rebuilt `.so` needs a fresh process.
3. Exercise live before writing tests:
   - CSV: `separator=';'`, `quote_char`, `comment_prefix`, `skip_rows`, `null_value`,
     `missing_is_null=false`, `try_parse_dates=true`, `n_rows`, `row_index_name`,
     `allow_missing_columns` (negative test: mismatched-schema multi-file scan errors by default,
     succeeds with nulls when `true`).
   - CSV write: each `quote_style`, `separator`, `date_format`/`datetime_format` round-trip;
     `sink_csv` `compression=:gzip`/`:zstd` produces a file readable back via `scan_csv` (CSV
     readers auto-detect gzip/zstd magic bytes, so `read_csv` on a compressed file should just work).
   - IPC: `n_rows`, `row_index_name`, `hive_partitioning=false` on a partitioned IPC directory,
     `allow_missing_columns`.
   - IPC write (new `write_ipc`): `compression=:lz4`/`:zstd`+level, round-trip via `read_ipc`;
     confirm `write_ipc(path::String, df)` and `write_ipc(io::IO, df)` both work, matching
     `write_parquet`'s two-method pattern.
   - `sink_ipc` options + `mkdir`/`maintain_order`, same checks as parquet's sink verification.
4. Add tests per CLAUDE.md workflow step 8, reusing `test/fixtures.jl` helpers.
5. Run the full suite via the scratch-env workaround (never `Pkg.test()`).
