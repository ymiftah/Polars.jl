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

`concat` also accepts `LazyFrame`s.

## Where to go from here

- [Reference](@ref) documents every function.
- [Limitations](@ref) lists what isn't available.
- [Developer](@ref) covers building and extending the package.
