# Laziness

```@setup laziness
using Polars
df = DataFrame((; x = [1, 2, 3], y = ["a", "b", "c"]))
```

Polars.jl provides two frame types (see [Structures](@ref)): eager
`DataFrame`, where every operation runs immediately, and lazy
`LazyFrame`, where operations are only recorded into a query plan. This split — and pushing
work through the lazy path — is one of the main things Polars.jl (and polars itself) offers over
a purely eager dataframe library: the query optimizer can reorder and fuse steps (e.g. push a
`filter` before a `select` so fewer rows ever reach the later step) before touching any data,
which matters once a query grows beyond a couple of operations.

## Going lazy: `lazy`

Wraps a `DataFrame` in a `LazyFrame` with no data movement — the wrapped frame is only scanned once
the plan is executed.

```@example laziness
lf = lazy(df)
```

`scan_parquet` and `scan_csv` (see [I/O](@ref))
build a `LazyFrame` directly from a file without reading it into memory first — prefer these over
`read_parquet |> lazy` / `read_csv |> lazy` when the source is a file, since the optimizer can then
push predicates and column selection all the way down to the file scan itself.

## Materializing: `collect`

Runs the recorded plan and returns a `DataFrame`. Accepts an `engine` keyword: `:default` (the
in-memory engine) or `:streaming` (processes the query in batches, for datasets larger than
memory — see [polars' streaming docs](https://docs.pola.rs/user-guide/lazy/streaming/)).

```@example laziness
collect(lf)
```

```@example laziness
collect(lf; engine = :streaming)
```

Every eager `DataFrame` function in Polars.jl (`select`, `filter`, `sort`, `group_by`+`agg`, joins,
...) is implemented internally as `collect ∘ op ∘ lazy` — so the two forms always give identical
results, and reading the source for an eager method's lazy counterpart is always a safe way to
understand exactly what it does.

## Inspecting the schema without running the query: `collect_schema`

Resolves column names and types from the query plan alone, without executing it — useful to check
a pipeline's shape (e.g. after a join or several `with_columns`) before paying for a `collect`.
Since the query hasn't run, actual null counts are unknown, so every column is conservatively
reported as nullable (`Union{T,Missing}`); compare with `Tables.schema` on an already-materialized
`DataFrame` (see [Structures](@ref)), which refines each column using its real null count.

```@example laziness
collect_schema(lf)
```
