# Input/output

`read_*` functions read a whole file into a `DataFrame`. `scan_*` functions return a `LazyFrame`,
so that polars reads only what the query needs when it is collected.

```@setup io
using Polars
```

## Parquet

```@docs
read_parquet
scan_parquet
write_parquet
sink_parquet
CastPolicy
```

```@example io
lf = scan_parquet("/tmp/example.parquet")
```

## CSV

```@docs
read_csv
scan_csv
write_csv
sink_csv
```

## IPC (Arrow/Feather)

```@docs
read_ipc
scan_ipc
write_ipc
sink_ipc
```

## JSON / NDJSON

```@docs
read_json
write_json
read_ndjson
scan_ndjson
write_ndjson
sink_ndjson
```

## Streaming writes

`sink_parquet`, `sink_csv`, `sink_ipc` and `sink_ndjson` run a query with the streaming engine and
write the result to a file without holding it all in memory. Together with `scan_*`, this lets a
pipeline process data larger than memory. They accept a `LazyFrame` or a `DataFrame` and return
`nothing`.

```@example io
df = DataFrame((; x = [1, 2, 3, 4, 5], y = ["a", "b", "c", "d", "e"]))
path = tempname() * ".parquet"
sink_parquet(filter(lazy(df), col("x") .> 2), path)
read_parquet(path)
```

## Partitioned parquet sinks

```@docs
PartitionByKey
```

```julia
df = DataFrame((; year = [2023, 2023, 2024], month = [1, 2, 1], value = [10, 20, 30]))
sink_parquet(df, PartitionByKey("/tmp/out"; by = ["year", "month"]))
# /tmp/out/year=2023/month=1/00000000.parquet
# /tmp/out/year=2023/month=2/00000000.parquet
# /tmp/out/year=2024/month=1/00000000.parquet
```

The directory can be read back with `scan_parquet`.

## Cloud object storage

The scan, read and sink functions accept `s3://`, `gs://`, `az://`, `hf://` and `http(s)://`
paths. `write_parquet` sends such a path to `sink_parquet`; the other `write_*` functions only
write local files.

Credentials and configuration come from the provider's environment variables and config files
(`AWS_ACCESS_KEY_ID`, `~/.aws/credentials`, `GOOGLE_SERVICE_ACCOUNT`, `AZURE_STORAGE_ACCOUNT`, ...),
or from `storage_options`:

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

See [polars' cloud storage documentation](https://docs.pola.rs/user-guide/io/cloud-storage/) for
the accepted keys. Remote files are cached locally; the `POLARS_FILE_CACHE_TTL` environment
variable sets the cache lifetime in seconds.

## Bulk materialization

```@docs
read_series
```
