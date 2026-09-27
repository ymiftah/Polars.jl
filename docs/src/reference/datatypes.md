# Data types

polars dtypes are written as Julia types, with `Union{T,Missing}` for nullable columns.

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
| `Time` | `Dates.Time` | `Union{Time,Missing}` |
| `Datetime` (any time unit, naive) | `Dates.DateTime` | `Union{DateTime,Missing}` |
| `Datetime` (any time unit, tz-aware) | `TimeZones.ZonedDateTime` (needs `using TimeZones`) | same, `Union{...,Missing}` |
| `Duration` (ms/µs/ns) | `Dates.Millisecond`/`Microsecond`/`Nanosecond` | `Union{...,Missing}` |
| `List(T)` | `Vector{T}` | `Union{Vector{T},Missing}` |
| `Struct` | `NamedTuple` | `Union{NamedTuple{...},Missing}` |
| `Categorical`/`Enum` | `String` | `Union{String,Missing}` |
| `Decimal` | not supported | |
| `Array` | not supported | |
| `Null` | `Missing` (always) | |

```@example datatypes
df = DataFrame((; x = [1, 2, missing, 4], y = ["a", "b", "c", "d"]))
import Tables
Tables.schema(df)
```

## Nullability

A column's type is `Union{T,Missing}` only if it contains nulls. `collect_schema` on a `LazyFrame`
doesn't run the query, so it reports every column as nullable.

`Decimal` and `Array` columns can be used in queries but not read into Julia; see
[Limitations](@ref).
