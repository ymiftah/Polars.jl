# Strings & Lists

```@setup strings-lists
using Polars
using Chain
include(joinpath(@__DIR__, "..", "assets", "sample_data.jl"))
```

!!! note
    These two namespaces have thinner test coverage than the rest of the API (see
    [Limitations](@ref)) — the examples below stick to the well-covered operations.

## The `Strings` namespace

`Strings` provides string operations on `String`-typed expressions. Normalize
product names to a consistent case, and flag anything mentioning "Latte":

```@example strings-lists
select(
    products,
    col("product_name") |> Strings.uppercase |> alias("upper_name"),
    Strings.contains_literal(col("product_name"), lit("Latte")) |> alias("is_latte"),
)
```

`Strings.len_chars`/`Strings.len_bytes` measure string length (differing on multi-byte unicode):

```@example strings-lists
select(products, col("product_name"), Strings.len_chars(col("product_name")) |> alias("n_chars"))
```

## The `Lists` namespace

List-typed columns in Polars.jl arise from query results — most commonly
`implode`ing a column within a `group_by`+`agg`, which collects each group's
values into a single list per row. The list of distinct products sold at each store:

```@example strings-lists
products_per_store = @chain orders begin
    lazy
    group_by("store_id")
    agg(implode(col("product_id")) |> alias("product_ids"))
    collect
end
head(products_per_store, 3)
```

`Lists` namespace functions then operate on that list column — e.g.
`Lists.lengths` (how many orders per store) and
`Lists.contains` (did this store ever sell product 1?):

```@example strings-lists
with_columns(
    products_per_store,
    Lists.lengths(col("product_ids")) |> alias("n_orders"),
    Lists.contains(col("product_ids"), lit(1)) |> alias("sold_espresso"),
)
```
