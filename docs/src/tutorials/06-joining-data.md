# Joining Data

```@setup joining
using Polars
using Chain
include(joinpath(@__DIR__, "..", "assets", "sample_data.jl"))
```

`innerjoin` combines rows from two frames that match on one or more key
expressions, keeping only rows with a match on both sides.

## Joining a fact table to a dimension table

Bring store names into the orders table:

```@example joining
orders_with_stores = innerjoin(orders, stores, col("store_id"))
head(orders_with_stores, 5)
```

Since both tables have a column named `store_id`, a single shared key expression is enough. When
the join columns are named differently on each side, pass one expression per side instead:
`innerjoin(a, b, col("id_a"), col("id_b"))`.

## Joining in a larger pipeline

Joins compose with the rest of the lazy API. Revenue per store *name* (rather than raw
`store_id`), continuing straight from the join:

```@example joining
revenue_by_store_name = @chain orders begin
    lazy
    with_columns((col("quantity") * col("unit_price")) |> alias("revenue"))
    innerjoin(lazy(stores), col("store_id"))
    group_by("store_name")
    agg(sum(col("revenue")) |> alias("total_revenue"))
    sort(col("total_revenue"); rev = true)
    collect
end
```

## Joining against multiple dimension tables

Bring in both store and product details at once by joining twice:

```@example joining
enriched = @chain orders begin
    lazy
    innerjoin(lazy(stores), col("store_id"))
    innerjoin(lazy(products), col("product_id"))
    select(col("order_id"), col("store_name"), col("product_name"), col("category"), col("quantity"), col("unit_price"))
    collect
end
head(enriched, 5)
```

## Keeping unmatched rows: `leftjoin`

`innerjoin` drops rows without a match. `leftjoin` keeps every row of the left frame, with
`missing` where the right side has no match. Joining against a `stores` table that lacks one store:

```@example joining
partial_stores = filter(stores, col("store_id") .<= 2)
with_missing_stores = leftjoin(orders, partial_stores, col("store_id"))
select(with_missing_stores, col("order_id"), col("store_id"), col("store_name")) |> x -> head(x, 8)
```

Orders from the missing store (`store_id` 3) keep their row, with `store_name` as `missing`,
instead of disappearing the way they would with `innerjoin`.

## The rest of the join family

There are also `rightjoin`, `outerjoin`, `semijoin`, `antijoin`, `crossjoin`, and `join_asof`
for matching on the nearest key (see [Time-Series Analytics](@ref)). See [Joins](@ref) for the
reference.
