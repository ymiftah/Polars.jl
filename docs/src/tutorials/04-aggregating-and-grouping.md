# Aggregating & Grouping

```@setup aggregating
using Polars
using Chain
include(joinpath(@__DIR__, "..", "assets", "sample_data.jl"))
```

## Revenue per store

`group_by` partitions rows by one or more expressions, and
`agg` reduces each group to a single row per aggregation expression. A revenue
column is needed first, so this reaches for the lazy API and chains `with_columns` before
grouping:

```@example aggregating
revenue_by_store = @chain orders begin
    lazy
    with_columns((col("quantity") * col("unit_price")) |> alias("revenue"))
    group_by("store_id")
    agg(sum(col("revenue")) |> alias("total_revenue"), count(col("order_id")) |> alias("n_orders"))
    collect
end
```

`sum`/`count` here are the same names as `Base.sum`/`Base.count` — Polars.jl extends them with
methods for `Expr`, so they work unqualified. The product aggregation (`prod`) works unqualified
too, for the same reason. A few other names in the API *do* need explicit `Base.` qualification
(`Base.lt`, `Base.tail`, `Base.rename`) — see the [Limitations](@ref) page.

## Multiple aggregations, multiple group keys

`agg` accepts as many expressions as needed, and `group_by` as many key expressions:

```@example aggregating
by_store_and_product = @chain orders begin
    lazy
    group_by("store_id", "product_id")
    agg(sum(col("quantity")) |> alias("units_sold"), mean(col("unit_price")) |> alias("avg_price"))
    collect
end
head(by_store_and_product, 5)
```

## Descriptive statistics

`std`/`var` (sample standard deviation/variance, `ddof=1` by
default) and `quantile` work as aggregation expressions too:

```@example aggregating
select(
    orders,
    std(col("unit_price")) |> alias("price_std"),
    quantile(col("unit_price"), 0.5) |> alias("price_median"),
)
```
