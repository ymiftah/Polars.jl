# LazyFrame

```@setup lazyframe
using Polars
df = DataFrame((; x = [1, 2, 3], y = ["a", "b", "c"]))
```

A `LazyFrame` records operations into a query plan, which polars optimizes (e.g. applying a
`filter` before a `select`) and runs on `collect`.

The verbs on the [DataFrame](@ref) page also accept a `LazyFrame` and return one.

```@docs
Polars.LazyFrame
```

## Going lazy

```@docs
lazy
```

```@example lazyframe
lf = lazy(df)
```

`scan_parquet`, `scan_csv`, `scan_ipc` and `scan_ndjson` (see [Input/output](@ref)) create a
`LazyFrame` from files without reading them first, so filters and column selections can be applied
during the scan.

## Materializing

```@docs
Base.collect
```

`engine = :streaming` processes the query in batches, for data larger than memory (see
[polars' streaming docs](https://docs.pola.rs/user-guide/lazy/streaming/)).

```@example lazyframe
collect(lf)
```

```@example lazyframe
collect(lf; engine = :streaming)
```

## Cloning a plan

```@docs
Polars.clone
```

## Inspecting the schema without running the query

```@docs
collect_schema
```

```@example lazyframe
collect_schema(lf)
```

## Inspecting and controlling the plan

```@docs
explain
cache
```

```@example lazyframe
println(explain(lf))
```

## GroupBy

```@docs
Polars.LazyGroupBy
```

Returned by `group_by`, `group_by_dynamic` and `rolling` (see [DataFrame](@ref)).
