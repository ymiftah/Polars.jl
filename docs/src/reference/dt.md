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
df = DataFrame((; ts = DateTime(2024, 3, 15, 14, 30, 0) .+ Dates.Hour.(0:2)))
select(df, col("ts"), Dt.year(col("ts")) |> alias("year"), Dt.month(col("ts")) |> alias("month"), Dt.weekday(col("ts")) |> alias("weekday"))
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
