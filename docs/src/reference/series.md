# Series

```@setup series
using Polars
df = DataFrame((; x = [1, 2, missing, 4], y = ["a", "b", "c", "d"]))
```

```@docs
Series
```

A `Series{T}` is an `AbstractVector{T}`. `T` is `Union{Missing, S}` only if the column contains
nulls. See [Data types](@ref) for the type mapping.

```@example series
df[:x]
```

## Attributes

```@docs
Polars.name
Polars.dtype
```

`Polars.item(series)` is documented on the [DataFrame](@ref) page.

## Manipulation/selection

Indexing with a range returns a `Series` that shares memory with the original:

```@example series
df[:x][2:3]
```

## Export

`collect(series)` returns a `Vector`; see also `read_series` in [Input/output](@ref).
