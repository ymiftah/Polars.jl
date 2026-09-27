# Getting Started

This tutorial builds a small analytics workflow on a synthetic dataset of coffee shop orders
across a few stores and products. Each page generates the same seeded dataset, so every snippet
can be run in a REPL.

## Installation

Not yet registered in the General registry — install directly from the repo:

```julia-repl
pkg> add https://github.com/ymiftah/Polars.jl
```

## Eager vs. lazy

Polars.jl provides two frame types:

- `DataFrame`: an *eager* frame — every operation runs immediately.
- A *lazy* frame (obtained via `lazy`): operations are only recorded, and the
  whole query is optimized and executed together when you call
  `collect`.

polars optimizes a lazy query as a whole (e.g. applying a `filter` before a `select`). Both give
the same results; prefer the lazy form for queries with more than a step or two.

## Your first DataFrame

```@setup getting-started
using Polars
using Chain
include(joinpath(@__DIR__, "..", "assets", "sample_data.jl"))
```

```@example getting-started
orders
```

`orders` is one of the three tables this tutorial uses throughout — a fact table of coffee shop
orders. `stores` and `products` are small dimension tables used later for joins:

```@example getting-started
stores
```

```@example getting-started
products
```

## A first query

Functions take the frame as their first argument, so queries chain well with
[Chain.jl](https://github.com/jkrumbiegel/Chain.jl)'s `@chain`, which passes each result as the
first argument of the next line.

Let's find the five largest orders by revenue (`quantity * unit_price`):

```@example getting-started
result = @chain orders begin
    lazy
    with_columns((col("quantity") * col("unit_price")) |> alias("revenue"))
    sort(col("revenue"); rev = true)
    head(5)
    collect
end
```

The following pages cover these operations in more detail. The examples use both `@chain` and
`|>`.
