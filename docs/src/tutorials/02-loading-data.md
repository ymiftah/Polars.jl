# Loading Data

## Constructing a DataFrame directly

Any object implementing the [Tables.jl](https://github.com/JuliaData/Tables.jl) interface can be
turned into a `DataFrame` — a `NamedTuple` of equal-length vectors, as
used throughout this tutorial, is the simplest case:

```@setup loading-data
using Polars
include(joinpath(@__DIR__, "..", "assets", "sample_data.jl"))
```

```@example loading-data
DataFrame((; product_id = [1, 2, 3], product_name = ["Espresso", "Latte", "Croissant"]))
```

## Parquet

`write_parquet` and `read_parquet` round-trip
a `DataFrame` through the Parquet format:

```@example loading-data
path = tempname() * ".parquet"
write_parquet(path, orders)
orders_from_disk = read_parquet(path)
size(orders_from_disk)
```

## Lazy scanning

For larger-than-memory or partitioned datasets, `scan_parquet` builds a
`LazyFrame` *without* reading the file eagerly — the actual read only
happens once the resulting query is `collect`ed, and
polars can push filters/column selections down into the scan itself:

```@example loading-data
lf = scan_parquet(path)
```

```@example loading-data
head(collect(lf), 3)
```

`scan_parquet` also accepts a directory of (optionally Hive-partitioned) parquet files, scanning
all of them as a single lazy source.

## Inspecting a lazy query's schema

Since a `LazyFrame` doesn't hold data yet, `collect_schema` lets you
inspect the column names/types a query *would* produce without running it — useful for validating
a pipeline before paying the cost of execution:

```@example loading-data
collect_schema(lf)
```
