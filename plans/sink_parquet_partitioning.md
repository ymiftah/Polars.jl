# Hive-partitioned parquet sinks (`sink_parquet` with a partitioning scheme)

## Status

Done. `polars_lazy_frame_sink_parquet_partitioned` added to `c-polars/src/io.rs`, header
regenerated cleanly (`check_header_drift.py` clean before and after), Julia bindings regenerated
(`src/api/generated.jl`, 4-line diff), `PartitionByKey` added in `src/io/partition.jl` with two new
`sink_parquet` methods in `src/io/parquet.jl`. Verified live (single/multi key, derived expression
keys, `include_key=false`, `max_rows_per_file` spill across numbered files, empty-`by` and
non-elementwise-key errors are catchable not crashes, `mkdir` correctly rejected as an unsupported
keyword, non-ASCII base path and key values round-trip). Full suite: 2280 total, 2276 passed, 4
broken (pre-existing, unrelated), 0 failed, run via
`JULIA_PROJECT=<scratch env> julia -e 'include("test/runtests.jl")'`. Docs added to
`docs/src/reference/io.md`.

## Context

`sink_parquet`/`write_parquet` (`src/io/parquet.jl`, `c-polars/src/io.rs:330-370`) only ever build
`SinkDestination::File { target: SinkTarget::Path(...) }` — a single output file. Upstream
`polars-plan` (0.54.4) already has `SinkDestination::Partitioned { base_path, file_path_provider,
partition_strategy, max_rows_per_file, approximate_bytes_per_file }`
(`polars-plan-0.54.4/src/dsl/options/sink.rs:53-65`), consumed by the same `LazyFrame::sink(...)`
this wrapper already calls, and executed by the streaming engine this wrapper already uses for
`sink_parquet`. `cloud_io.md` explicitly called this out as future, separate work.

Goal: let a `LazyFrame`/`DataFrame` be sunk to a directory of Hive-style partitioned parquet files
(`base/year=2024/month=1/00000000.parquet`, ...) instead of one file.

## Key research findings

- `PartitionStrategy::Keyed { keys: Vec<Expr>, include_keys, keys_pre_grouped }` is the only
  strategy that produces Hive-style partitioning; `PartitionStrategy::FileSize` is a keyless
  size-split, an orthogonal concern, out of scope here (see "Out of scope").
- `file_path_provider: None` resolves to `FileProviderType::Hive` automatically
  (`polars-plan-0.54.4/src/plans/conversion/dsl_to_ir/mod.rs:1515-1519`), using the file format's
  own extension — so the wrapper never has to build a `HivePathProvider` itself.
- `max_rows_per_file`/`approximate_bytes_per_file` are `0`-as-unlimited sentinels
  (`polars-stream-0.54.4/src/physical_plan/to_graph.rs:460-465`), not `Option`s, on the DSL struct.
  `max_rows_per_file` is `IdxSize` (`u32` in this build — `bigidx` is not enabled).
- **`mkdir` is silently ignored for partitioned sinks.** The partitioned file provider always does
  a best-effort recursive `create_dir_all` per partition regardless of the `mkdir` flag
  (`polars-stream-0.54.4/src/nodes/io_sinks/components/file_provider.rs:73-82`, the `mkdir: _`
  destructure at `pipeline_initialization/partition_by.rs:48`). Exposing `mkdir` on the new
  partitioned entry point would silently do nothing, so it is deliberately omitted from the new
  Julia method's signature rather than accepted-and-ignored.
- Non-elementwise partition keys are already rejected with a catchable `PolarsResult` error
  (`dsl_to_ir/mod.rs:1498-1502`, `InvalidOperation: "cannot use non-elementwise expressions..."`),
  not a panic — no new panic-safety work needed for that path.
- No new Cargo feature: `parquet` + the streaming engine (`lazy`, `performant`, already enabled)
  are sufficient; no `activate 'X' feature` panic site or `unreachable!()` found on the partitioned
  sink path.

## Design

### Rust / C ABI (`c-polars/src/io.rs`)

One new function, following the ownership/error conventions of `polars_lazy_frame_sink_parquet`
and reusing `build_parquet_write_options` unchanged:

```rust
#[no_mangle]
pub unsafe extern "C" fn polars_lazy_frame_sink_parquet_partitioned(
    lf: *mut polars_lazy_frame_t,
    base_path: *const u8,
    base_pathlen: usize,
    keys: *const *const polars_expr_t,
    n_keys: usize,
    include_keys: bool,
    max_rows_per_file: *const u64,           // null = unlimited
    approximate_bytes_per_file: *const u64,  // null = unlimited
    compression: polars_parquet_compression_t,
    compression_level: *const i32,
    statistics: bool,
    row_group_size: *const usize,
    data_page_size: *const usize,
    maintain_order: bool,
    cloud_options: *const polars_cloud_options_t,
    out: *mut *mut polars_lazy_frame_t,
) -> *const polars_error_t
```

Body (inside `guard_error`):

```rust
let base_path = tri!(read_str(base_path, base_pathlen));
let keys = read_exprs(keys, n_keys);
tri!(polars_ensure_nonempty(&keys)); // "partition_by requires at least one key"
let options = tri!(build_parquet_write_options(...));
let cloud_options = tri!(resolve_cloud_options(base_path, cloud_options));
let max_rows_per_file = match max_rows_per_file.as_ref() {
    Some(&n) => tri!(IdxSize::try_from(n).map_err(|_| PolarsError::InvalidOperation(
        format!("max_rows_per_file {n} exceeds the maximum representable row count").into()
    ))),
    None => 0,
};
let approximate_bytes_per_file = approximate_bytes_per_file.as_ref().copied().unwrap_or(0);

let lf = (*lf).inner.clone();
let sink_type = SinkDestination::Partitioned {
    base_path: PlRefPath::new(base_path),
    file_path_provider: None,
    partition_strategy: PartitionStrategy::Keyed { keys, include_keys, keys_pre_grouped: false },
    max_rows_per_file,
    approximate_bytes_per_file,
};
let file_format = FileWriteFormat::Parquet(Arc::new(options));
let sink_args = UnifiedSinkArgs {
    mkdir: false, // irrelevant for Partitioned -- see finding above
    maintain_order,
    cloud_options: cloud_options.map(Arc::new),
    ..Default::default()
};
let sunk = tri!(lf.sink(sink_type, file_format, sink_args));
*out = make_lazy_frame(sunk);
std::ptr::null()
```

No new opaque handle type: reuses `polars_expr_t`, `polars_cloud_options_t`,
`polars_parquet_compression_t` exactly as existing functions do. `read_exprs` (`ffi_util.rs:17`)
already handles the `(ptr-array, n)` → `Vec<Expr>` conversion used by `select`/`group_by`.

A dedicated function rather than widening `polars_lazy_frame_sink_parquet`: keeps the existing
11-parameter signature and its one call site untouched, and the new function stays small since it
shares `build_parquet_write_options`/`resolve_cloud_options`.

### Header + bindings

Standard chain, no manual header edits:

1. `cd c-polars && ./regen_header.sh` (cbindgen; needs `RUSTC_BOOTSTRAP=1` on stable, which the
   script sets itself).
2. `cargo build -j 4` (incremental — no Cargo.toml/feature change, so no full rebuild).
3. `julia --project=gen gen/generate.jl && runic -i src/api/generated.jl`.

### Julia API

New file `src/io/partition.jl` (partitioning is a sink-destination concept, not parquet-specific,
even though parquet is the only consumer today — matches "Where things live" in CLAUDE.md by
concern rather than by format):

```julia
struct PartitionByKey
    base_path::String
    by::Vector{Expr}
    include_key::Bool
    max_rows_per_file::Union{Nothing,Int}
    approximate_bytes_per_file::Union{Nothing,Int}
end

function PartitionByKey(
        base_path::AbstractString;
        by,
        include_key::Bool = true,
        max_rows_per_file::Union{Nothing,Integer} = nothing,
        approximate_bytes_per_file::Union{Nothing,Integer} = nothing,
    )
    keys = by isa AbstractVector ? map(_as_expr, by) : [_as_expr(by)]
    isempty(keys) && error("PartitionByKey requires at least one partition key in `by`")
    return PartitionByKey(
        String(base_path), convert(Vector{Expr}, keys), include_key,
        max_rows_per_file === nothing ? nothing : Int(max_rows_per_file),
        approximate_bytes_per_file === nothing ? nothing : Int(approximate_bytes_per_file),
    )
end
```

Exported from `Polars.jl` alongside the other top-level types.

In `src/io/parquet.jl`, alongside the existing `sink_parquet` methods:

```julia
sink_parquet(df::DataFrame, target::PartitionByKey; kwargs...) =
    sink_parquet(lazy(df), target; kwargs...)

function sink_parquet(
        lf::LazyFrame, target::PartitionByKey;
        compression::Symbol = :zstd,
        compression_level::Union{Nothing,Integer} = nothing,
        statistics::Bool = true,
        row_group_size::Union{Nothing,Integer} = nothing,
        data_page_size::Union{Nothing,Integer} = nothing,
        maintain_order::Bool = true,
        storage_options::Union{Nothing,AbstractDict{<:AbstractString,<:AbstractString}} = nothing,
    )
    # same compression/level/row_group_size/data_page_size marshalling as the existing method
    # keys: GC.@preserve target.by; ptrs = Ptr{polars_expr_t}[e.ptr for e in target.by]
    # max_rows_per_file / approximate_bytes_per_file: Ref(UInt64(...)) or C_NULL, same as n_rows_ref elsewhere
    ...
    collect(LazyFrame(out[]); engine = :streaming)
    return nothing
end
```

Follows the exact `GC.@preserve`/pointer-array pattern already used in `src/select.jl:5-8` for
`Vector{Expr}`, and the `_with_cloud_options` scoping already used by `sink_parquet`.

### Docs

Add `PartitionByKey` and the new `sink_parquet` method to `docs/src/reference/io.md`.

## Testing (`test/lazyframe/sink_parquet.jl`)

Following the `pypolars-test-parity` approach — round-trip plus option coverage plus error paths:

- Single key (`"g"`): directory layout is `g=a/00000000.parquet`, `g=b/00000000.parquet`;
  `scan_parquet(base; hive_partitioning=true) |> collect` round-trips size/values against the
  unpartitioned reference.
- `include_key=false`: the key column is absent from a leaf file read directly with
  `read_parquet` on that one file (bypassing hive auto-detection).
- Multiple keys: nested `year=.../month=.../...` directories.
- A derived expression key (not a bare column), e.g. `Dt.year(col("d")) |> alias("year")`.
- `max_rows_per_file` spills one partition across `00000000.parquet`/`00000001.parquet`.
- Error paths, all catchable (no process abort): empty `by`; a non-elementwise key expression
  (e.g. an aggregation).
- Non-ASCII base path and non-ASCII string key *value* (CLAUDE.md's `ncodeunits`-vs-`length` class
  of bug) — round-trips correctly.
- `DataFrame` entry point (`sink_parquet(df, PartitionByKey(...))`) agrees with the `LazyFrame` one.

Per CLAUDE.md workflow step 7: exercise every option combination live in a Julia REPL session
before writing the tests, not only after a clean `cargo build`.

## Risks / open questions

- `IdxSize` is `u32` without `bigidx` — `max_rows_per_file` above `u32::MAX` must error cleanly,
  not silently truncate; handled via `IdxSize::try_from`.
- `mkdir` omission on this entry point is a deliberate asymmetry with `sink_parquet`'s file-target
  method; document it clearly in the docstring so it doesn't read as an oversight.

## Out of scope

- `PartitionStrategy::FileSize` (keyless size-splitting, no Hive directories) and
  `PartitionStrategy::Keyed { keys_pre_grouped: true }` (the "already sorted by keys" perf
  variant, py-polars' `PartitionParted`) — neither is "Hive partitioning"; can be added later as
  more `by`/strategy options on `PartitionByKey`'s call site or a sibling type if requested.
- A custom `file_path_provider` (`FileProviderType::Function`) — no Julia-callback plumbing for
  path generation; always resolves to the upstream Hive default.
- `sinked_paths_callback` (Iceberg commit hook) — Iceberg is unrelated to this wrapper.
- CSV/IPC partitioned sinks — parquet only, matching where the actual user request is; the same
  `SinkDestination::Partitioned` plumbing would extend to `sink_csv`/`sink_ipc` similarly if later
  requested.
