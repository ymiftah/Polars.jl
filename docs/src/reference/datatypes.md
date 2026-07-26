# Data types

Polars.jl has no dedicated dtype wrapper types (no `pl.Int64`/`pl.Utf8`-style objects) — a polars
dtype is represented directly as the equivalent Julia type, and nullability is layered on top via
`Union{T,Missing}`. This table is the full mapping.

```@setup datatypes
using Polars, Dates
```

## Mapping

| polars dtype | Julia type (non-null) | Julia type (nullable) |
|---|---|---|
| `Boolean` | `Bool` | `Union{Bool,Missing}` |
| `Int8`/`Int16`/`Int32`/`Int64` | `Int8`/`Int16`/`Int32`/`Int64` | `Union{...,Missing}` |
| `UInt8`/`UInt16`/`UInt32`/`UInt64` | `UInt8`/`UInt16`/`UInt32`/`UInt64` | `Union{...,Missing}` |
| `Float32`/`Float64` | `Float32`/`Float64` | `Union{...,Missing}` |
| `String`/`Utf8` | `String` | `Union{String,Missing}` |
| `Binary` | `Vector{UInt8}` | `Union{Vector{UInt8},Missing}` |
| `Date` | `Dates.Date` | `Union{Date,Missing}` |
| `Time` | `Dates.Time` (always nanosecond-resolution) | `Union{Time,Missing}` |
| `Datetime` (any time unit, naive) | `Dates.DateTime` | `Union{DateTime,Missing}` |
| `Datetime` (any time unit, tz-aware) | `TimeZones.ZonedDateTime` (needs `using TimeZones`) | same, `Union{...,Missing}` |
| `Duration` (ms/µs/ns) | `Dates.Millisecond`/`Microsecond`/`Nanosecond` | `Union{...,Missing}` |
| `List(T)` | `Vector{T}` (plain nested `Vector`, not a `Series`) | `Union{Vector{T},Missing}` |
| `Struct` | `NamedTuple` (one field per struct field) | `Union{NamedTuple{...},Missing}` |
| `Categorical`/`Enum` | `String` (dictionary-encoded; resolved via the referenced dictionary's own type) | `Union{String,Missing}` |
| `Decimal` | *(cannot be materialized — see below)* | |
| `Array` (fixed-size list) | *(cannot be materialized — see below)* | |
| `Null` | `Missing` (always) | |

```@example datatypes
df = DataFrame((; x = [1, 2, missing, 4], y = ["a", "b", "c", "d"]))
import Tables
Tables.schema(df)
```

## Nullability

A column with zero nulls reports a non-`Union` `eltype`; one with any nulls reports
`Union{T,Missing}` — see [Series](@ref) and [DataFrame](@ref)'s `Tables.schema` for where this is
observed. `collect_schema` on a `LazyFrame` (see [LazyFrame](@ref)) hasn't executed the query, so it
can't know actual null counts and conservatively reports every column as nullable.

## Known gaps

- **`Decimal` columns can be cast/queried (`cast_decimal`, `Selectors.decimal()`) but not read back
  into Julia** — materializing one raises an "unknown schema format" error. See
  [Limitations](@ref).
- **`Array` (fixed-size list) has no materialization path either**, and `Selectors.array()` raises
  an error in this build rather than selecting columns. See [Limitations](@ref) and
  [Selectors](@ref).
