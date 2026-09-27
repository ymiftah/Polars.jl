# [List](@id expr-list)

The `Lists` namespace operates on List columns, such as those produced by `implode`.

```@setup lists
using Polars, Chain
```

```@docs
Polars.Lists.lengths
Polars.Lists.max
Polars.Lists.min
Polars.Lists.sum
Polars.Lists.mean
Polars.Lists.first
Polars.Lists.last
Polars.Lists.reverse
Polars.Lists.unique
Polars.Lists.unique_stable
Polars.Lists.arg_max
Polars.Lists.arg_min
Polars.Lists.head
Polars.Lists.get
Polars.Lists.contains
Polars.Lists.join
```

Aggregations return one value per list:

```@example lists
lf = DataFrame((; xs = [[3, 1, 4], [1, 5, 9, 2]]))
select(
    lf,
    Lists.lengths(col("xs")) |> alias("lengths"),
    Lists.max(col("xs")) |> alias("max"), Lists.min(col("xs")) |> alias("min"),
    Lists.arg_max(col("xs")) |> alias("arg_max"), Lists.arg_min(col("xs")) |> alias("arg_min"),
    Lists.sum(col("xs")) |> alias("sum"), Lists.mean(col("xs")) |> alias("mean"),
    Lists.first(col("xs")) |> alias("first"), Lists.last(col("xs")) |> alias("last"),
)
```

```@example lists
select(lf, Lists.reverse(col("xs")) |> alias("reversed"))
```

```@example lists
dfdup = DataFrame((; xs = [[3, 1, 3, 2]]))
select(dfdup, Lists.unique(col("xs")) |> alias("unique"), Lists.unique_stable(col("xs")) |> alias("unique_stable"))
```

Distinct products per store:

```@example lists
df = DataFrame((; store = ["a", "a", "b", "b"], product = [1, 2, 1, 3]))
result = @chain df begin
    lazy
    group_by("store")
    agg(implode(col("product")))
    with_columns(Lists.unique(col("product")) |> alias("unique_products"))
    collect
end
```

## Curried forms

`Lists.head(n)`, `Lists.get(index)` and `Lists.contains(value)` have curried forms (see
[Curried forms for pipe-based composition](@ref)):

```@example lists
with_columns(result, col("unique_products") |> Lists.head(1) |> alias("first_product"))
```
