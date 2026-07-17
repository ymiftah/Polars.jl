# Time-Series Analytics

This is the flagship analytics chapter: resampling orders into fixed time windows, computing
rolling statistics, and pulling calendar fields out of timestamps.

```@setup time-series
using Polars
using Chain
include(joinpath(@__DIR__, "..", "assets", "sample_data.jl"))
```

## Resampling with `group_by_dynamic`

`group_by_dynamic` buckets rows into fixed-size time windows based
on a sorted timestamp column — the time-series equivalent of `group_by`. Daily revenue across all
stores:

```@example time-series
daily_revenue = @chain orders begin
    lazy
    with_columns((col("quantity") * col("unit_price")) |> alias("revenue"))
    group_by_dynamic("timestamp"; every = "1d")
    agg(sum(col("revenue")) |> alias("daily_revenue"))
    collect
end
head(daily_revenue, 5)
```

Passing extra grouping keys buckets *within* each key as well — daily revenue per store:

```@example time-series
daily_revenue_by_store = @chain orders begin
    lazy
    with_columns((col("quantity") * col("unit_price")) |> alias("revenue"))
    group_by_dynamic("timestamp", ["store_id"]; every = "1d")
    agg(sum(col("revenue")) |> alias("daily_revenue"))
    collect
end
head(daily_revenue_by_store, 5)
```

## Moving averages with `rolling`

`rolling` computes a window ending at *each* row (not just fixed buckets) —
useful for moving averages. A 3-day rolling average of daily order counts:

```@example time-series
rolling_orders = @chain orders begin
    lazy
    group_by_dynamic("timestamp"; every = "1d")
    agg(count(col("order_id")) |> alias("n_orders"))
    rolling("timestamp"; period = "3d")
    agg(mean(col("n_orders")) |> alias("rolling_avg_orders"))
    collect
end
head(rolling_orders, 5)
```

## Extracting calendar fields with `Dt`

The `Dt` namespace pulls calendar components out of a datetime column, and can
truncate/round to a coarser granularity or format as a string:

```@example time-series
select(
    orders,
    Dt.year(col("timestamp")) |> alias("year"),
    Dt.weekday(col("timestamp")) |> alias("weekday"), # 1 = Monday
    Dt.truncate(col("timestamp"), lit("1d")) |> alias("day"),
    Dt.strftime(col("timestamp"), "%Y-%m-%d %H:%M") |> alias("formatted"),
) |> x -> head(x, 5)
```

Combine `Dt.weekday` with `group_by` to compare weekday vs. weekend order volume:

```@example time-series
@chain orders begin
    lazy
    with_columns(Dt.weekday(col("timestamp")) |> alias("weekday"))
    with_columns((col("weekday") .>= 6) |> alias("is_weekend"))
    group_by("is_weekend")
    agg(count(col("order_id")) |> alias("n_orders"))
    collect
end
```
