# Date & Time

The `Dt` namespace provides date/datetime component extraction and manipulation on `Date`-, `DateTime`-, and `Duration`-typed columns.

```@setup dt
using Polars, Dates
```

## Component extraction

| Function | Purpose |
|---|---|
| `Dt.year`, `Dt.month`, `Dt.day` | date parts |
| `Dt.hour`, `Dt.minute`, `Dt.second` | time parts |
| `Dt.weekday` | day of week (1=Monday, 7=Sunday) |
| `Dt.ordinal_day` | day of year (1-366) |
| `Dt.date` | the `Date` component of a Datetime (drops the time-of-day) |
| `Dt.time` | the `Dates.Time` component of a Datetime (drops the date) -- not exported (would clobber `Base.time`), use qualified `Dt.time(...)` |

Example:

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

| Function | Purpose |
|---|---|
| `Dt.truncate(expr, interval)` | truncate to nearest interval (e.g., "1h") |
| `Dt.round(expr, interval)` | round to nearest interval |
| `Dt.offset_by(expr, offset)` | shift by duration (e.g., "+1d", "-2h") |
| `Dt.strftime(expr, format)` | format to string (chrono-style, e.g., "%Y-%m-%d") |

Notes:

- All datetime functions operate on **sorted** data (no implicit sorting).
- Intervals use polars' duration string format: `"1d"`, `"4h"`, `"30m"`, `"5s"`, etc.
- `strftime` accepts standard `strftime` format codes (`%Y`, `%m`, `%d`, `%H`, `%M`, `%S`, etc.).

`Dt.truncate`, `Dt.round`, `Dt.offset_by`, and `Dt.strftime` all have curried forms for `|>`
pipelines — see [Curried forms for pipe-based composition](@ref):

```@example dt
select(df, col("ts") |> Dt.truncate("1h") |> alias("trunc"), col("ts") |> Dt.strftime("%Y-%m-%d") |> alias("formatted"))
```

`round` differs from `truncate` by rounding to the *nearest* interval instead of always rounding
down; `offset_by` shifts by a signed duration:

```@example dt
select(df, col("ts") |> Dt.round("1h") |> alias("rounded"), col("ts") |> Dt.offset_by("+1d") |> alias("plus_1d"))
```

## Duration components

| Function | Purpose |
|---|---|
| `Dt.total_days(expr; fractional=false)` | total whole days in a Duration value |
| `Dt.total_hours(expr; fractional=false)` | total whole hours |
| `Dt.total_minutes(expr; fractional=false)` | total whole minutes |
| `Dt.total_seconds(expr; fractional=false)` | total whole seconds |
| `Dt.total_milliseconds(expr; fractional=false)` | total whole milliseconds |
| `Dt.total_microseconds(expr; fractional=false)` | total whole microseconds |
| `Dt.total_nanoseconds(expr; fractional=false)` | total whole nanoseconds |

Each `total_*` function decomposes a `Duration`-typed value (see [Selectors](@ref)'s
`duration()`, or cast an integer column via `cast(expr, Dates.Nanosecond/Microsecond/Millisecond)`
— see [Expressions](@ref)) into a count of the named unit. By default the count is truncated
*toward zero* (an `Int64`); pass `fractional=true` for the exact value as a `Float64` instead.
All seven have curried forms for `|>` pipelines — see
[Curried forms for pipe-based composition](@ref).

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

| Function | Purpose |
|---|---|
| `Dt.replace_time_zone(expr, tz=nothing; ambiguous="raise", non_existent=:raise)` | attach, strip (`tz=nothing`), or re-attach a time zone label to *local wall-clock* values — the instant changes, the displayed clock time doesn't |
| `Dt.convert_time_zone(expr, tz)` | re-label an already tz-aware expression into a different IANA zone (e.g. `"America/New_York"`) — the instant is unchanged, only the display/interpretation does |

`ambiguous` controls how a local time that occurs twice (a DST fall-back) is resolved — one of
`"raise"`, `"earliest"`, `"latest"`, `"null"`. `non_existent` controls how a local time that never
occurs (a DST spring-forward gap) is resolved — `:raise` or `:null`. Both functions have curried
forms for `|>` pipelines — see [Curried forms for pipe-based composition](@ref).

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
