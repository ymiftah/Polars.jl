# [Datetime](@id expr-datetime)

The `Dt` namespace provides date/datetime component extraction and manipulation on `Date`-, `DateTime`-, and `Duration`-typed columns. All datetime functions operate on **sorted** data (no implicit sorting).

```@setup dt
using Polars, Dates
```

## Component extraction

```@docs
Polars.Dt.year
Polars.Dt.month
Polars.Dt.day
Polars.Dt.hour
Polars.Dt.minute
Polars.Dt.second
Polars.Dt.weekday
Polars.Dt.ordinal_day
Polars.Dt.date
Polars.Dt.time
```

```@example dt
df = DataFrame((; ts = DateTime(2024, 3, 15, 14, 30, 45) .+ Dates.Hour.(0:2)))
select(df, col("ts"), Dt.year(col("ts")) |> alias("year"), Dt.month(col("ts")) |> alias("month"), Dt.weekday(col("ts")) |> alias("weekday"))
```

```@example dt
select(
    df,
    Dt.day(col("ts")) |> alias("day"), Dt.hour(col("ts")) |> alias("hour"),
    Dt.minute(col("ts")) |> alias("minute"), Dt.second(col("ts")) |> alias("second"),
    Dt.ordinal_day(col("ts")) |> alias("ordinal_day"),
)
```

`Dt.date`/`Dt.time` split a Datetime into its `Date` and `Dates.Time` halves:

```@example dt
select(df, Dt.date(col("ts")) |> alias("date"), Dt.time(col("ts")) |> alias("time"))
```

## Rounding & formatting

```@docs
Polars.Dt.truncate
Polars.Dt.round
Polars.Dt.offset_by
Polars.Dt.strftime
```

Intervals use polars' duration string format: `"1d"`, `"4h"`, `"30m"`, `"5s"`, etc. `strftime`
accepts standard `strftime` format codes (`%Y`, `%m`, `%d`, `%H`, `%M`, `%S`, etc.).

```@example dt
select(df, col("ts") |> Dt.truncate("1h") |> alias("trunc"), col("ts") |> Dt.strftime("%Y-%m-%d") |> alias("formatted"))
```

`round` differs from `truncate` by rounding to the *nearest* interval instead of always rounding
down; `offset_by` shifts by a signed duration:

```@example dt
select(df, col("ts") |> Dt.round("1h") |> alias("rounded"), col("ts") |> Dt.offset_by("+1d") |> alias("plus_1d"))
```

## Duration components

```@docs
Polars.Dt.total_days
Polars.Dt.total_hours
Polars.Dt.total_minutes
Polars.Dt.total_seconds
Polars.Dt.total_milliseconds
Polars.Dt.total_microseconds
Polars.Dt.total_nanoseconds
```

Each `total_*` function decomposes a `Duration`-typed value (see [Selectors](@ref)'s
`duration()`, or cast an integer column via `cast(expr, Dates.Nanosecond/Microsecond/Millisecond)`
— see [Casting](@ref casting)) into a count of the named unit. By default the count is truncated
*toward zero* (an `Int64`); pass `fractional=true` for the exact value as a `Float64` instead.

```@example dt
dfdur = select(
    DataFrame((; ns = Int64[90_061_500_000_000, -3_600_000_000_000])),
    cast(col("ns"), Dates.Nanosecond) |> alias("d"),
)
select(
    dfdur,
    col("d"),
    Dt.total_hours(col("d")) |> alias("hours"),
    Dt.total_seconds(col("d")) |> alias("seconds"),
    col("d") |> Dt.total_seconds(fractional = true) |> alias("seconds_frac"),
)
```

## Time zones

```@docs
Polars.Dt.replace_time_zone
Polars.Dt.convert_time_zone
```

`replace_time_zone` attaches, strips (`tz=nothing`), or re-attaches a time zone label to *local
wall-clock* values — the instant changes, the displayed clock time doesn't. `ambiguous` controls
how a local time that occurs twice (a DST fall-back) is resolved — one of `"raise"`, `"earliest"`,
`"latest"`, `"null"`. `non_existent` controls how a local time that never occurs (a DST
spring-forward gap) is resolved — `:raise` or `:null`.

`convert_time_zone` re-labels an already tz-aware expression into a different IANA zone (e.g.
`"America/New_York"`) — the instant is unchanged, only the display/interpretation does.

```julia
using Polars, Dates
df = DataFrame((; ts = DateTime(2024, 3, 15, 12, 0, 0) .+ Dates.Hour.(0:2)))
select(df, col("ts") |> Dt.replace_time_zone("UTC") |> Dt.convert_time_zone("America/New_York") |> alias("ts_ny"))
```

!!! note
    Building and running a query over tz-aware columns works with no extra dependencies. Reading a
    tz-aware column's *values* back into Julia — including implicitly, e.g. `show`ing a `DataFrame`
    that has one — needs [TimeZones.jl](https://github.com/JuliaTime/TimeZones.jl) loaded
    (`using TimeZones`) first, as `ZonedDateTime`; without it, both `df[:ts_ny]` and `show(df)`
    error with a message explaining this. `write_parquet`/`write_csv`/etc. don't need it either,
    since they never materialize a Julia value.

## Curried forms

`truncate`, `round`, `offset_by`, `strftime`, every `total_*` function, and both time-zone
functions have curried forms for `|>` pipelines — see
[Curried forms for pipe-based composition](@ref).
