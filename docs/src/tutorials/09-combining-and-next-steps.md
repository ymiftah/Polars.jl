# Combining Data & Next Steps

```@setup combining
using Polars
include(joinpath(@__DIR__, "..", "assets", "sample_data.jl"))
```

## Stacking frames with `concat`

`concat` stacks multiple frames with the same schema on top of each other —
for example, combining two batches of orders that arrived separately:

```@example combining
early_orders = filter(orders, col("order_id") .<= 3)
later_orders = filter(orders, (col("order_id") .> 3) & (col("order_id") .<= 6))
concat([early_orders, later_orders])
```

`concat` also accepts `LazyFrame`s, so it composes with the rest of a lazy pipeline just like every
other operation covered so far.

## Where to go from here

This tutorial series covered the operations with the strongest test coverage in Polars.jl today:
loading data, selecting/filtering/transforming, grouping and aggregating, time-series resampling,
joins, window functions, and basic string/list handling. A few things were deliberately left out —
see the [Limitations](@ref) page before reaching for them, since some are simply unavailable in
this package today (not just undocumented).

From here:
- The [Reference](@ref) section documents every function used in this tutorial (and more) in one
  place, organized by category.
- The [Polars.jl README](https://github.com/ymiftah/Polars.jl) has build instructions for the
  underlying Rust `c-polars` bridge, useful if you want to extend the wrapper itself.
