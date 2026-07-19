# Lists

The `Lists` namespace provides operations on list-typed columns (arise from `implode` within `group_by` + `agg`, or from anywhere a collection of per-row values is formed).

```@setup lists
using Polars, Chain
```

## List operations

| Function | Purpose |
|---|---|
| `Lists.lengths(expr)` | length of each list |
| `Lists.max`, `Lists.min`, `Lists.sum`, `Lists.mean` | aggregate within each list |
| `Lists.first`, `Lists.last` | first/last element |
| `Lists.reverse` | reverse the list |
| `Lists.unique`, `Lists.unique_stable` | distinct elements |
| `Lists.arg_max`, `Lists.arg_min` | index of min/max |
| `Lists.head(expr, n)` | first n elements |
| `Lists.get(expr, index; null_on_oob=false)` | element at index (0-indexed; errors on oob unless null_on_oob=true) |
| `Lists.contains(expr, value; nulls_equal=true)` | check if value is in the list |

Each per-list aggregation reduces a `List` column to one scalar per row:

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

`Lists.reverse` reverses the element order *within* each list (row order is unchanged); `unique`
and `unique_stable` both return the distinct elements of each list, differing only in whether
first-occurrence order is preserved (more expensive) or not:

```@example lists
select(lf, Lists.reverse(col("xs")) |> alias("reversed"))
```

```@example lists
dfdup = DataFrame((; xs = [[3, 1, 3, 2]]))
select(dfdup, Lists.unique(col("xs")) |> alias("unique"), Lists.unique_stable(col("xs")) |> alias("unique_stable"))
```

Example: distinct product IDs per store, collected via `implode` in a `group_by`:

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

`Lists.head(n)`, `Lists.get(index; null_on_oob=false)`, and `Lists.contains(value; nulls_equal=true)`
have curried forms for `|>` pipelines — see [Curried forms for pipe-based composition](@ref):

```@example lists
with_columns(result, col("unique_products") |> Lists.head(1) |> alias("first_product"))
```
