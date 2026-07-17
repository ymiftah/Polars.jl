# Shared sample dataset for the Polars.jl tutorials: a small, seeded, self-contained
# "coffee shop chain" retail dataset. `include`d at the top of each tutorial page inside a
# `@setup` block so every `@example` on that page is reproducible on its own.
#
# Produces three tables:
#   - `stores`:   store_id, store_name, city               (dimension table, for joins)
#   - `products`: product_id, product_name, category       (dimension table, for joins/strings)
#   - `orders`:   order_id, timestamp, store_id, product_id, quantity, unit_price
#                 (fact table, ~3 weeks of sub-daily orders, for grouping/time-series/window ops)

using Dates
using Random

Random.seed!(42)

stores = DataFrame(
    (;
        store_id = [1, 2, 3],
        store_name = ["Downtown", "Riverside", "Uptown"],
        city = ["Springfield", "Springfield", "Shelbyville"],
    )
)

products = DataFrame(
    (;
        product_id = collect(1:6),
        product_name = ["Espresso", "Latte", "Croissant", "Muffin", "Green Tea", "Chai Latte"],
        category = ["Coffee", "Coffee", "Bakery", "Bakery", "Tea", "Tea"],
    )
)

const PRODUCT_BASE_PRICE = Dict(1 => 3.5, 2 => 4.75, 3 => 2.8, 4 => 3.2, 5 => 3.0, 6 => 4.2)

n_orders = 500
start_date = DateTime(2024, 1, 1)
span_minutes = 60 * 24 * 21 # 3 weeks

order_minutes = sort(rand(0:span_minutes, n_orders))
order_store_id = rand(1:3, n_orders)
order_product_id = rand(1:6, n_orders)

orders = DataFrame(
    (;
        order_id = collect(1:n_orders),
        timestamp = start_date .+ Dates.Minute.(order_minutes),
        store_id = order_store_id,
        product_id = order_product_id,
        quantity = rand(1:4, n_orders),
        unit_price = [PRODUCT_BASE_PRICE[pid] for pid in order_product_id],
    )
)
