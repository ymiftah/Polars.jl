# Window Functions & Ranking

```@setup window-functions
using Polars
using Chain
include(joinpath(@__DIR__, "..", "assets", "sample_data.jl"))
```

Window functions compute a value *per group* but keep every original row (unlike `group_by`+`agg`,
which collapses each group to one row) — useful for comparing a row to its group's aggregate.

## `over`: partitioned aggregates without collapsing rows

`over` evaluates an aggregation expression per partition and broadcasts the
result back to every row in that partition:

```@example window-functions
with_store_total = with_columns(
    orders,
    over(sum(col("quantity") * col("unit_price")), "store_id") |> alias("store_total_revenue"),
)
head(with_store_total, 5)
```

Each row now carries its store's total revenue alongside its own order details — handy for
computing e.g. "this order's share of its store's revenue":

```@example window-functions
with_share = with_columns(
    with_store_total,
    (col("quantity") * col("unit_price") / col("store_total_revenue")) |> alias("share_of_store"),
)
head(with_share, 5)
```

## Ranking

`rank` assigns ranks within a column; combine it with `over` to rank *within*
each partition — e.g. each order's rank by revenue within its own store:

```@example window-functions
ranked = with_columns(
    orders,
    over(rank(col("quantity") * col("unit_price"); descending = true), "store_id") |> alias("revenue_rank_in_store"),
)
head(ranked, 5)
```

## Cumulative aggregates

`cum_sum`/`cum_prod`/`cum_min`/`cum_max`/`cum_count` accumulate along the current row order. A
running total of revenue over time:

```@example window-functions
@chain orders begin
    sort(col("timestamp"))
    with_columns((col("quantity") * col("unit_price")) |> alias("revenue"))
    with_columns(cum_sum(col("revenue")) |> alias("running_total"))
    select(col("timestamp"), col("revenue"), col("running_total"))
    head(5)
end
```

## Day-over-day change

`shift` offsets a column by `n` rows, and `pct_change`
computes the relative change from `n` rows back — both useful after resampling into a regular time
series (see [Time-Series Analytics](@ref)):

```@example window-functions
daily_orders = @chain orders begin
    lazy
    group_by_dynamic("timestamp"; every = "1d")
    agg(count(col("order_id")) |> alias("n_orders"))
    with_columns(shift(col("n_orders"), lit(1)) |> alias("prev_day"))
    with_columns(pct_change(col("n_orders"), lit(1)) |> alias("pct_change"))
    collect
end
head(daily_orders, 5)
```
