# Getting Started

Polars.jl is a Julia wrapper around the [polars](https://pola.rs) dataframe library. This
tutorial series builds a small analytics workflow around a synthetic "coffee shop chain" retail
dataset: orders placed across a few stores, over a few weeks, for a handful of products. Every
code block on every page is fully runnable — Polars.jl re-generates the same seeded dataset at the
top of each page, so you can copy any snippet into your own REPL and it will just work.

## Installation

```julia-repl
pkg> add Polars
```

## Eager vs. lazy

Polars.jl provides two frame types:

- `DataFrame`: an *eager* frame — every operation runs immediately.
- A *lazy* frame (obtained via `lazy`): operations are only recorded, and the
  whole query is optimized and executed together when you call
  `collect`.

The lazy path lets polars fuse and reorder operations (e.g. push a `filter` before a `select`)
before touching any data, which matters once queries grow beyond a couple of steps. Eager
operations in Polars.jl are implemented as `collect ∘ op ∘ lazy` under the hood, so both forms
give identical results — prefer the lazy form once a query involves more than one or two steps.

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

Since every Polars.jl function takes the frame/group-by object as its *first* argument, multi-step
queries read nicely with [Chain.jl](https://github.com/jkrumbiegel/Chain.jl)'s `@chain` macro:
each bare line implicitly becomes a call with the previous line's result spliced in as the first
argument. This tutorial series uses `@chain` throughout instead of nesting or nested `|>` pipes.

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

This chains `with_columns` (add a computed column), `sort` (descending by revenue), and `head` (top
5), then materializes the result with `collect`. The next chapters cover each of these operations —
and several more — in depth.
