# Transforming Data

```@setup transforming-data
using Polars
include(joinpath(@__DIR__, "..", "assets", "sample_data.jl"))
```

## Selecting and computing columns

`select` keeps only the columns/expressions you list;
`with_columns` keeps all existing columns and adds/overwrites the ones
you give it. Both accept any number of `Expr`s, built from
`col` (reference a column), `lit` (a literal value that
broadcasts), and `alias` (rename the result):

```@example transforming-data
select(
    orders,
    col("order_id"),
    (col("quantity") * col("unit_price")) |> alias("revenue"),
)
```

```@example transforming-data
with_columns(orders, (col("quantity") * col("unit_price")) |> alias("revenue"))
```

## Filtering rows

`filter` keeps rows where a boolean expression is `true`:

```@example transforming-data
filter(orders, col("quantity") .>= 3)
```

## Casting

`cast` converts an expression's column to another datatype:

```@example transforming-data
select(orders, cast(col("store_id"), Int64), cast(col("quantity"), Float64))
```

## Conditional logic with `when`/`then`/`otherwise`

`when` builds a ternary expression: `then` where the condition holds, `otherwise`
elsewhere. Use it to bucket orders into "large" vs. "small":

```@example transforming-data
with_columns(
    orders,
    when(col("quantity") .>= 3, "large", "small") |> alias("order_size"),
)
```

## Handling missing and NaN values

`fill_null` and `fill_nan` replace `missing`/`NaN`
values with a fallback expression — useful after a join or a computation that can produce either:

```@example transforming-data
with_missing = DataFrame((; x = [1.0, missing, 3.0]))
select(with_missing, fill_null(col("x"), lit(0.0)) |> alias("x_filled"))
```

## Membership checks

`is_in` tests whether each value appears in a set built from
`implode`ing a list of literals — handy for filtering to a subset of
categories:

```@example transforming-data
coffee_only = implode(lit(1)) # product_id 1 = Espresso; implode(lit(1), lit(2)) for more values
filter(orders, is_in(col("product_id"), coffee_only))
```
