# [Datetime](@id expr-datetime)

The `Dt` namespace operates on Date, Datetime, Time and Duration columns.

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
Polars.Dt.millisecond
Polars.Dt.microsecond
Polars.Dt.nanosecond
Polars.Dt.weekday
Polars.Dt.ordinal_day
Polars.Dt.date
Polars.Dt.time
Polars.Dt.datetime
Polars.Dt.iso_year
Polars.Dt.is_leap_year
Polars.Dt.century
Polars.Dt.millennium
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

```@example dt
select(df, Dt.date(col("ts")) |> alias("date"), Dt.time(col("ts")) |> alias("time"))
```

```@example dt
select(
    df,
    Dt.iso_year(col("ts")) |> alias("iso_year"), Dt.century(col("ts")) |> alias("century"),
    Dt.is_leap_year(col("ts")) |> alias("is_leap_year"),
)
```

## Rounding & formatting

```@docs
Polars.Dt.truncate
Polars.Dt.round
Polars.Dt.offset_by
Polars.Dt.strftime
Polars.Dt.to_string
```

Intervals are duration strings such as `"1d"`, `"4h"`, `"30m"`.

```@example dt
select(df, col("ts") |> Dt.truncate("1h") |> alias("trunc"), col("ts") |> Dt.strftime("%Y-%m-%d") |> alias("formatted"))
```

```@example dt
select(df, col("ts") |> Dt.round("1h") |> alias("rounded"), col("ts") |> Dt.offset_by("+1d") |> alias("plus_1d"))
```

## Combining & replacing components

```@docs
Polars.Dt.combine
Polars.Dt.replace
```

```@example dt
select(DataFrame((; d = [Date(2024, 3, 15)])), Dt.combine(col("d"), lit(Time(9, 30))) |> alias("combined"))
```

```@example dt
select(df, Dt.replace(col("ts"); year = 2000, hour = 0) |> alias("replaced"))
```

## Time unit

```@docs
Polars.Dt.cast_time_unit
Polars.Dt.with_time_unit
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

An integer column can be cast to a Duration with `cast(expr, Dates.Nanosecond)` (see
[Casting](@ref casting)):

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
Polars.Dt.base_utc_offset
Polars.Dt.dst_offset
```

`replace_time_zone` keeps the local time and changes the instant; `convert_time_zone` keeps the
instant and changes the local time.

```julia
using Polars, Dates
df = DataFrame((; ts = DateTime(2024, 3, 15, 12, 0, 0) .+ Dates.Hour.(0:2)))
select(df, col("ts") |> Dt.replace_time_zone("UTC") |> Dt.convert_time_zone("America/New_York") |> alias("ts_ny"))
```

`base_utc_offset` and `dst_offset` need a timezone-aware Datetime:

```julia
select(df, col("ts") |> Dt.replace_time_zone("Europe/London") |> Dt.dst_offset |> alias("dst"))
```

!!! note
    Reading timezone-aware values into Julia, including `show`ing a `DataFrame` that contains
    them, requires [TimeZones.jl](https://github.com/JuliaTime/TimeZones.jl) (`using TimeZones`);
    the values are `ZonedDateTime`s. Queries and writes don't need it.

## Curried forms

Functions with arguments have curried forms (see [Curried forms for pipe-based composition](@ref));
functions without, such as `Dt.year`, can be piped directly: `col("ts") |> Dt.year`.
