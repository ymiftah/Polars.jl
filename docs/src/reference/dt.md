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
