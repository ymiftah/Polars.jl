# I/O

Reading and writing parquet and CSV files — the two eager I/O functions below read the entire file into memory, while the lazy variants only record a scan plan, letting `collect` choose when (and how efficiently) to read.

```@setup io
using Polars
```

## Parquet

### Eager

`read_parquet(path)` — reads a parquet file into a `DataFrame`.

### Lazy

`scan_parquet(path)` — returns a `LazyFrame` scanning the file (or glob pattern, or directory of Hive-partitioned parquet files). Lets polars push column selection and filters down to the file scan itself, avoiding unnecessary I/O. Supports Hive partition key auto-detection.

```@example io
lf = scan_parquet("/tmp/example.parquet")
```

### Writing

`write_parquet(io::IO, df)` or `write_parquet(path::String, df)` — writes a DataFrame to parquet.

## CSV

### Eager

`read_csv(path)` — reads a CSV file into a DataFrame.

### Lazy

`scan_csv(path)` — returns a LazyFrame scanning the CSV (no column/filter push-down like parquet, but still defers I/O until `collect`).

### Writing

`write_csv(io::IO, df)` or `write_csv(path::String, df)` — writes a DataFrame to CSV.

## IPC (Arrow/Feather)

### Eager

`read_ipc(path)` — reads an Arrow IPC (Feather) file into a `DataFrame`.

### Lazy

`scan_ipc(path)` — returns a `LazyFrame` scanning the file, same deferred-I/O behavior as `scan_parquet`.

## Streaming writes: `sink_parquet`, `sink_csv`, `sink_ipc`

`sink_parquet(lf_or_df, path)`, `sink_csv(lf_or_df, path)`, `sink_ipc(lf_or_df, path)` — execute the query through the `:streaming` collect engine (see [Laziness](@ref)) and write the result directly to disk, without ever materializing the full result in memory. This is the write-side counterpart to `scan_*`: the pair together lets a pipeline stay entirely out-of-core, reading and writing datasets larger than RAM. All three accept either a `LazyFrame` or a `DataFrame` (the `DataFrame` form just wraps `lazy(df)` internally) and return `nothing`.

```@example io
df = DataFrame((; x = [1, 2, 3, 4, 5], y = ["a", "b", "c", "d", "e"]))
path = tempname() * ".parquet"
sink_parquet(filter(lazy(df), col("x") .> 2), path)
read_parquet(path)
```

## Notes

- Both `write_parquet` and `write_csv` accept an `IO` object or a file path `String`.
- Parquet is strongly preferred for numeric/structured data — it's columnar, compressed, and type-safe, whereas CSV is text-based.
- `scan_parquet`/`scan_csv`/`scan_ipc` (read side) and `sink_parquet`/`sink_csv`/`sink_ipc` (write side) together are how to work with data larger than memory — pair a `scan_*` with a `sink_*` and the whole pipeline runs via the `:streaming` engine without ever holding the full result in memory.

