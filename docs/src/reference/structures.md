# Structures

Every polars object crossing into Julia is one of five wrapper types. Each is a thin
`mutable struct` around an opaque pointer into the Rust side, with a `finalizer` that frees the
underlying polars object when the Julia object is garbage collected — there is no manual memory
management to do.

```@setup structures
using Polars
```

## `DataFrame`

An eager, columnar table: every operation on a `DataFrame` runs immediately. Construct one from
anything implementing the [Tables.jl](https://github.com/JuliaData/Tables.jl) interface — most
commonly a `NamedTuple` of vectors (column-oriented):

```@example structures
df = DataFrame((; x = [1, 2, missing, 4], y = ["a", "b", "c", "d"]))
```

A `Vector` of `NamedTuple`s (row-oriented) works too, via Tables.jl's own row-to-column conversion:

```@example structures
DataFrame([(; x = 1, y = "a"), (; x = 2, y = "b")])
```

Columns can hold scalar/fixed-width types (`Int`, `String`, `Date`, `DateTime`, ...), `List`s
(`Vector{<:Vector{T}}`) and `Struct`s (`Vector{<:NamedTuple}` as a *column*, not the whole table —
see [Structs](@ref)), and raw bytes as a `Binary` column via `Vector{UInt8}`:

```@example structures
DataFrame((; b = [UInt8[1, 2, 3], UInt8[4, 5]]))
```

Columns are retrieved with `getindex`, by `Symbol` or `String` name, returning a `Series`:

```@example structures
df[:x]
```

A single cell is `df[row, col]`; `size(df)` returns `(nrows, ncols)`:

```@example structures
df[2, :x], size(df)
```

## `Series`

`Series{T}` is a single named column — an `AbstractVector{T}`, so indexing, iteration, and most of
`Base`'s `AbstractVector` interface work directly. `T` reflects the column's actual nullability:
a column with zero nulls reports a non-`Union` `eltype`, one with nulls reports
`Union{Missing,T}` (see the `x` column above, which has a `missing`, versus `y`, which doesn't).
`Polars.name(series)` returns its column name as a `String` (not exported — call it qualified).

Range-indexing (`series[a:b]`) returns a new `Series` via a zero-copy slice — no data is copied, it
just shares the underlying polars buffer:

```@example structures
df[:x][2:3]
```

## `LazyFrame`

A *lazy* frame: operations are only recorded into a query plan, not executed, until `collect` runs
the whole thing (optionally fused and reordered by polars' query optimizer). Obtained from a
`DataFrame` via `lazy`, or directly via `scan_parquet` / `scan_csv`.
See [Laziness](@ref) for the full eager/lazy story.

## `LazyGroupBy`

An intermediate object returned by `group_by`, `group_by_dynamic`, and `rolling` — not
useful on its own, it exists to be passed straight to `agg`, which returns the
aggregated result as a `LazyFrame`. See [Manipulation](@ref).

## `Expr`

An unevaluated column expression — the building block of every query (`col("x") * 2`,
`sum(col("revenue"))`, `when(...).then(...).otherwise(...)`, ...). `Expr <: Number`, purely so that
Julia's promotion machinery lets you write `col("x") + 1` and have the literal `1` promoted to an
expression automatically; `Expr`s are otherwise unrelated to numbers and are never actually
evaluated until they appear inside `select`, `with_columns`, `filter`, or `agg`. See
[Expressions](@ref) for the full set of expression-building functions.

```@example structures
select(df, col("x") + 1 |> alias("x_plus_one"))
```

## Tables.jl integration

`DataFrame` implements the [Tables.jl](https://github.com/JuliaData/Tables.jl) column-access
interface (`Tables.istable`, `Tables.columns`, `Tables.schema`, ...), so it interoperates with any
package that consumes Tables.jl sources (CSV.jl writers, DataFrames.jl's `DataFrame(polars_df)`,
Pluto.jl's table viewer, etc.). `Tables.schema(df)` refines each column's `eltype` using its actual
null count — unlike `collect_schema` on a `LazyFrame`, which hasn't executed the query yet and so
must conservatively report every column as nullable.

```@example structures
import Tables
Tables.schema(df)
```
