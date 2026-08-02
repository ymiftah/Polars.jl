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

## Partitioned parquet sinks

```@docs
PartitionByKey
```

`sink_parquet` also accepts a [`PartitionByKey`](@ref) in place of a path `String`, writing a
Hive-style partitioned directory of parquet files instead of a single file:

```julia
df = DataFrame((; year = [2023, 2023, 2024], month = [1, 2, 1], value = [10, 20, 30]))
sink_parquet(df, PartitionByKey("/tmp/out"; by = ["year", "month"]))
# /tmp/out/year=2023/month=1/00000000.parquet
# /tmp/out/year=2023/month=2/00000000.parquet
# /tmp/out/year=2024/month=1/00000000.parquet
```

`by` accepts column name(s) or arbitrary elementwise [`Expr`](@ref)s (e.g. a derived key such as
`Dt.year(col("date")) |> alias("year")`), not just plain columns. It accepts the same
`compression`/`compression_level`/`statistics`/`row_group_size`/`data_page_size`/`storage_options`
keywords as the single-file `sink_parquet` method, plus `maintain_order` — but **not `mkdir`**:
upstream polars always recursively creates each partition's directory for a partitioned sink
regardless of any such flag, so the keyword is omitted rather than accepted-and-ignored. The
resulting directory can be read back with `scan_parquet`/`read_parquet`'s `hive_partitioning`
option.

## Cloud object storage

`scan_parquet`/`read_parquet`/`sink_parquet` (and the CSV/IPC equivalents) accept `s3://`,
`gs://`/`gcs://`, `az://`/`azure://`/`abfs(s)://`, and `hf://` URIs in addition to local paths and
glob patterns, backed by upstream polars' `object_store`-based cloud IO. `write_parquet`/
`write_csv`/`write_ipc` also recognize a cloud URI and route it through the equivalent `sink_*`
function rather than attempting to create a local file — passing a `String` path with a
`scheme://` prefix to any of the six read/write functions is enough to opt in; no separate flag is
needed.

`https://`/`http://` scanning is **not new** — it already worked before cloud object-store support
was added, needs no `storage_options` and no extra Cargo feature, and is unrelated to the
S3/GCS/Azure work described below:

```julia
scan_csv("https://raw.githubusercontent.com/pola-rs/polars/main/examples/datasets/foods1.csv")
```

For S3/GCS/Azure, credentials and endpoint configuration can come from two places:

- **The ambient environment** — `AWS_ACCESS_KEY_ID`/`AWS_REGION`, `~/.aws/credentials`,
  `~/.aws/config`, `GOOGLE_SERVICE_ACCOUNT`, `AZURE_STORAGE_ACCOUNT`, etc. — with no
  `storage_options` argument at all:

  ```julia
  scan_parquet("s3://my-bucket/data.parquet")
  sink_parquet(df, "s3://my-bucket/out.parquet")
  ```

- **Explicit `storage_options`**, a `Dict{<:AbstractString,<:AbstractString}` of key/value pairs
  passed straight through to polars' `CloudOptions` — needed for a non-AWS S3-compatible endpoint
  (MinIO, Cloudflare R2, ...), per-call credentials, or a non-default region:

  ```julia
  storage_options = Dict(
      "aws_endpoint_url" => "http://localhost:9000",
      "aws_access_key_id" => "minioadmin",
      "aws_secret_access_key" => "minioadmin",
      "aws_region" => "us-east-1",
      "aws_allow_http" => "true",
  )
  df = collect(scan_parquet("s3://my-bucket/data.parquet"; storage_options))
  sink_parquet(df, "s3://my-bucket/out.parquet"; storage_options)
  ```

  `storage_options` keys are passed through verbatim to polars with no allowlist on the Julia
  side — an unrecognized key is not rejected outright, it's silently dropped by polars and the
  operation proceeds without it (surfacing as a connection/credentials error later rather than an
  immediate "unknown key" error), so double-check key spelling against
  [polars' own cloud storage options documentation](https://docs.pola.rs/user-guide/io/cloud-storage/)
  if a call fails in a way that looks like a missing credential.

Two things worth keeping in mind:

- **Remote files are cached locally**, honoring polars' `file_cache` feature — repeated scans of
  the same remote file within the cache TTL avoid re-downloading it. Control the TTL with the
  `POLARS_FILE_CACHE_TTL` environment variable (seconds).
- **Cloud IO runs on polars' own async runtime**, independent of `JULIA_NUM_THREADS` — consistent
  with the "Concurrency" note in [Limitations](@ref): handle-sharing rules across Julia
  tasks/threads are unchanged, and cloud requests don't consume or contend with Julia's own thread
  pool.

Finally, a security note: if polars fails to parse or use a `storage_options` value (e.g. a
malformed `aws_endpoint_url`), the value can appear verbatim in the resulting error message. Avoid
putting real secrets directly in code that might get logged or pasted into a bug report/issue —
prefer sourcing credentials from the environment (`~/.aws/credentials`, `AWS_ACCESS_KEY_ID`, etc.)
where possible.

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
