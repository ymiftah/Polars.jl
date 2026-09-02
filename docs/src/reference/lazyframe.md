# LazyFrame

```@setup lazyframe
using Polars
df = DataFrame((; x = [1, 2, 3], y = ["a", "b", "c"]))
```

A *lazy* frame: operations are only recorded into a query plan, not executed, until `collect` runs
the whole thing (optionally fused and reordered by polars' query optimizer). This split — and
pushing work through the lazy path — is one of the main things Polars.jl (and polars itself) offers
over a purely eager dataframe library: the query optimizer can reorder and fuse steps (e.g. push a
`filter` before a `select` so fewer rows ever reach the later step) before touching any data, which
matters once a query grows beyond a couple of operations.

Every verb documented on the [DataFrame](@ref) page (`select`, `filter`, `sort`, `group_by`+`agg`,
joins, `concat`, ...) also has a `LazyFrame` method returning another `LazyFrame` so calls chain —
they are documented once there, not repeated here.

```@docs
Polars.LazyFrame
```

## Going lazy

```@docs
lazy
```

Wraps a `DataFrame` in a `LazyFrame` with no data movement — the wrapped frame is only scanned once
the plan is executed.

```@example lazyframe
lf = lazy(df)
```

`scan_parquet`/`scan_csv`/`scan_ipc` (see [Input/output](@ref)) build a `LazyFrame` directly from a
file without reading it into memory first — prefer these over `read_parquet |> lazy` when the
source is a file, since the optimizer can then push predicates and column selection all the way
down to the file scan itself.

## Materializing

```@docs
Base.collect
```

Runs the recorded plan and returns a `DataFrame`. Accepts an `engine` keyword: `:default` (the
in-memory engine) or `:streaming` (processes the query in batches, for datasets larger than memory
— see [polars' streaming docs](https://docs.pola.rs/user-guide/lazy/streaming/)).

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

Resolves column names and types from the query plan alone, without executing it — useful to check
a pipeline's shape (e.g. after a join or several `with_columns`) before paying for a `collect`.
Since the query hasn't run, actual null counts are unknown, so every column is conservatively
reported as nullable (`Union{T,Missing}`); compare with `Tables.schema` on an already-materialized
`DataFrame` (see [DataFrame](@ref)), which refines each column using its real null count.

```@example lazyframe
collect_schema(lf)
```

## Inspecting and controlling the plan

```@docs
explain
cache
```

`explain` renders the query plan as text; with `optimized=true` (the default) it's the plan
polars will actually execute, after predicate/projection pushdown and the other optimizer passes.
`cache` marks a subtree for caching, so a plan that consumes it more than once evaluates it only
once -- advisory, it never changes results.

```@example lazyframe
println(explain(lf))
```

## GroupBy

```@docs
Polars.LazyGroupBy
```

An intermediate object returned by `group_by`, `group_by_dynamic`, and `rolling` (see
[DataFrame](@ref)) — not useful on its own, it exists to be passed straight to `agg`, which
evaluates the aggregation expressions per group and returns a `LazyFrame`.
