# Input/output

Reading and writing parquet, CSV, and IPC files — the eager functions below read the entire file into memory, while the lazy `scan_*` variants only record a scan plan, letting `collect` choose when (and how efficiently) to read.

```@setup io
using Polars
```

## Parquet

```@docs
read_parquet
scan_parquet
write_parquet
sink_parquet
```

`scan_parquet` returns a `LazyFrame` scanning the file (or glob pattern, or directory of
Hive-partitioned parquet files). Lets polars push column selection and filters down to the file
scan itself, avoiding unnecessary I/O. Supports Hive partition key auto-detection.

```@example io
lf = scan_parquet("/tmp/example.parquet")
```

Keyword options (see the docstring above for the full list): `n_rows`,
`row_index_name`/`row_index_offset` (add a row-index column), `parallel`
(`:auto`/`:none`/`:columns`/`:row_groups`), `low_memory`, `rechunk`, `cache`, `glob`,
`use_statistics`, `allow_missing_columns`, `include_file_paths`, `hive_partitioning`
(`true`/`false`/`nothing` to auto-detect). `read_parquet` accepts the same keywords.

`write_parquet` keyword options: `compression` (one of `:zstd` (default), `:snappy`, `:gzip`,
`:brotli`, `:lz4_raw`, `:uncompressed`), `compression_level` (only valid for
`:gzip`/`:brotli`/`:zstd`), `statistics`, `row_group_size`, `data_page_size`.

## CSV

```@docs
read_csv
scan_csv
write_csv
sink_csv
```

`scan_csv` has no column/filter push-down like parquet, but still defers I/O until `collect`.
Keyword options: `n_rows`, `row_index_name`/`row_index_offset`, `has_header`,
`separator`/`quote_char`, `comment_prefix`, `skip_rows`/`skip_rows_after_header`, `null_value`,
`missing_is_null`, `truncate_ragged_lines`, `try_parse_dates`, `infer_schema_length`,
`ignore_errors`, `low_memory`, `rechunk`, `cache`, `glob`, `include_file_paths`,
`allow_missing_columns`. `read_csv` accepts the same keywords.

Unlike `scan_parquet`/`scan_ipc`, CSV scanning has **no `hive_partitioning` option** — Hive
partitioning is always disabled for CSV scans, with no way to turn it on. See [Developer](@ref)
for why.

`write_csv` keyword options: `include_header`/`include_bom`, `separator`/`quote_char`,
`null_value`, `line_terminator`, `quote_style` (`:necessary`/`:always`/`:non_numeric`/`:never`),
`date_format`/`time_format`/`datetime_format`, `float_precision`, `decimal_comma`. Unlike
`write_parquet`, `write_csv` has **no `compression` option** — only `sink_csv` supports writing
compressed CSV.

## IPC (Arrow/Feather)

```@docs
read_ipc
scan_ipc
write_ipc
sink_ipc
```

`scan_ipc` has the same deferred-I/O behavior as `scan_parquet`. Keyword options: `n_rows`,
`row_index_name`/`row_index_offset`, `rechunk`, `cache`, `glob`, `include_file_paths`,
`hive_partitioning`, `allow_missing_columns`. `read_ipc` accepts the same keywords.

`write_ipc` keyword options: `compression` (one of `:uncompressed` (default), `:lz4`, `:zstd`),
`compression_level` (tunes `:zstd` only), `record_batch_size`.

## Streaming writes

`sink_parquet(lf_or_df, path)`, `sink_csv(lf_or_df, path)`, `sink_ipc(lf_or_df, path)` — execute
the query through the `:streaming` collect engine (see [LazyFrame](@ref)) and write the result
directly to disk, without ever materializing the full result in memory. This is the write-side
counterpart to `scan_*`: the pair together lets a pipeline stay entirely out-of-core, reading and
writing datasets larger than RAM. All three accept either a `LazyFrame` or a `DataFrame` (the
`DataFrame` form just wraps `lazy(df)` internally) and return `nothing`.

```@example io
df = DataFrame((; x = [1, 2, 3, 4, 5], y = ["a", "b", "c", "d", "e"]))
path = tempname() * ".parquet"
sink_parquet(filter(lazy(df), col("x") .> 2), path)
read_parquet(path)
```

Each `sink_*` accepts the same format-specific keywords as its `write_*` counterpart (`sink_parquet`
takes `write_parquet`'s `compression`/`compression_level`/`statistics`/`row_group_size`/`data_page_size`;
`sink_csv` takes `write_csv`'s formatting keywords **plus** its own `compression`
(`:uncompressed` (default)/`:gzip`/`:zstd`) and `compression_level`, since `write_csv` itself has no
compression option; `sink_ipc` takes `write_ipc`'s keywords), plus two extra keywords all three
share: `mkdir` (create missing parent directories, default `false`) and `maintain_order` (preserve
row order through the streaming pipeline, default `true`).

## Bulk materialization

```@docs
read_series
```

Bulk-materializes a `Series` (see [Series](@ref)) into a native Julia `Vector` in one pass, or
returns `nothing` if the series' type isn't (yet) supported by this path. Passing `zerocopy=true`
additionally allows, for fixed-width numeric columns with no nulls, returning a `Vector` that
directly aliases the polars `Series`' own memory with no copy at all — the returned array must then
be treated as **read-only**, since mutating it would corrupt the source `Series`. For any other
column type, `zerocopy` is not honored and a normal copy is returned instead.

## Notes

- Both `write_parquet` and `write_csv` accept an `IO` object or a file path `String`.
- Parquet is strongly preferred for numeric/structured data — it's columnar, compressed, and type-safe, whereas CSV is text-based.
- `scan_parquet`/`scan_csv`/`scan_ipc` (read side) and `sink_parquet`/`sink_csv`/`sink_ipc` (write side) together are how to work with data larger than memory — pair a `scan_*` with a `sink_*` and the whole pipeline runs via the `:streaming` engine without ever holding the full result in memory.
