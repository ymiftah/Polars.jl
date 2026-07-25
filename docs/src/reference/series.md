# Series

```@setup series
using Polars
df = DataFrame((; x = [1, 2, missing, 4], y = ["a", "b", "c", "d"]))
```

```@docs
Series
```

`Series{T}` is a single named column — an `AbstractVector{T}`, so indexing, iteration, and most of
`Base`'s `AbstractVector` interface work directly. `T` reflects the column's actual nullability: a
column with zero nulls reports a non-`Union` `eltype`, one with nulls reports `Union{Missing,T}`
(see the `x` column below, which has a `missing`, versus `y`, which doesn't). See [Data
types](@ref) for the full Julia↔polars dtype mapping.

```@example series
df[:x]
```

## Attributes

```@docs
Polars.name
```

`Polars.name(series)` returns its column name as a `String` — not exported, so it's always called
qualified.

## Manipulation/selection

Range-indexing (`series[a:b]`) returns a new `Series` via a zero-copy slice — no data is copied, it
just shares the underlying polars buffer:

```@example series
df[:x][2:3]
```

A single element is `series[i]`, materializing that one value into a Julia scalar (or `missing`).

## Export

Bulk-materializing a whole `Series` into a native Julia `Vector` (rather than element-by-element
indexing) goes through `read_series` — see [Input/output](@ref).
