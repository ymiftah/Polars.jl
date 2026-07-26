module Lists
using ..Polars: @generate_expr_fns, API, polars_expr_t, Expr

@generate_expr_fns begin
    gen_impl_expr_list!(polars_expr_list_lengths, ListNameSpace::lengths, "Length of each list in `expr` (`null` list entries count, and a `null` list itself gives a `null` length -- an empty list gives `0`).")
    gen_impl_expr_list!(polars_expr_list_max, ListNameSpace::max, "Maximum value within each list of `expr`.")
    gen_impl_expr_list!(polars_expr_list_min, ListNameSpace::min, "Minimum value within each list of `expr`.")
    gen_impl_expr_list!(polars_expr_list_arg_max, ListNameSpace::arg_max, "Index of the maximum value within each list of `expr`.")
    gen_impl_expr_list!(polars_expr_list_arg_min, ListNameSpace::arg_min, "Index of the minimum value within each list of `expr`.")
    gen_impl_expr_list!(polars_expr_list_sum, ListNameSpace::sum, "Sum of the values within each list of `expr`.")
    gen_impl_expr_list!(polars_expr_list_mean, ListNameSpace::mean, "Mean of the values within each list of `expr`.")
    gen_impl_expr_list!(polars_expr_list_reverse, ListNameSpace::reverse, "Reverses the element order within each list of `expr` (the list count/row order is unchanged -- compare the top-level [`reverse`](@ref), which reverses row order).")
    gen_impl_expr_list!(polars_expr_list_unique, ListNameSpace::unique, "Distinct elements within each list of `expr` (order not guaranteed) -- see [`unique_stable`](@ref) to preserve first-occurrence order.")
    gen_impl_expr_list!(polars_expr_list_unique_stable, ListNameSpace::unique_stable, "Like [`unique`](@ref), but preserves each element's first-occurrence order within the list (more expensive).")
    gen_impl_expr_list!(polars_expr_list_first, ListNameSpace::first, "First element of each list in `expr`.")
    gen_impl_expr_list!(polars_expr_list_last, ListNameSpace::last, "Last element of each list in `expr`.")
end

# `head` is pulled out of the `@generate_expr_fns` block (rather than generated via
# `gen_impl_expr_binary_list!`, like the other binary ops above) because it collides with
# `Polars`'s own top-level `head` (for `DataFrame`/`LazyFrame`) -- not a Base name, so the macro's
# own Base-collision check can't catch it, and it must never be exported: it's designed for
# qualified use (`Lists.head`), matching `get`/`contains` below.
"""
    head(expr::Polars.Expr, n::Polars.Expr)::Polars.Expr

First `n` elements of each list in `expr` (fewer if the list is shorter than `n`).
"""
function head(a::Expr, b::Expr)
    out = API.polars_expr_list_head(a, b)
    return Expr(out)
end

"""
    head(n)::Base.Fix2{typeof(head)}

Curried form of `head` for use with `|>` -- e.g. `col("x") |> Lists.head(2)`.
"""
head(n) = Base.Fix2(head, convert(Expr, n))

"""
    get(expr::Polars.Expr, index::Polars.Expr; null_on_oob::Bool=false)::Polars.Expr

Get items in every sublist by index. If `null_on_oob` is `false` (default), an
out-of-bounds index raises an error; if `true`, it returns `null` instead (more
expensive, per the polars documentation).
"""
function get(expr::Expr, index::Expr; null_on_oob::Bool = false)
    out = API.polars_expr_list_get(expr, index, null_on_oob)
    return Expr(out)
end

"""
    get(index; null_on_oob::Bool=false)::Base.Callable

Curried form of [`get`](@ref) for use with `|>` -- e.g. `col("x") |> Lists.get(0)`.
"""
get(index; null_on_oob::Bool = false) = expr -> get(expr, convert(Expr, index); null_on_oob)

"""
    contains(expr::Polars.Expr, other::Polars.Expr; nulls_equal::Bool=true)::Polars.Expr

Check if the list array contains an element. If `nulls_equal` is `true` (default),
`null` values are considered equal for the containment check.
"""
function contains(expr::Expr, other::Expr; nulls_equal::Bool = true)
    out = API.polars_expr_list_contains(expr, other, nulls_equal)
    return Expr(out)
end

"""
    contains(other; nulls_equal::Bool=true)::Base.Callable

Curried form of [`contains`](@ref) for use with `|>`.
"""
contains(other; nulls_equal::Bool = true) = expr -> contains(expr, convert(Expr, other); nulls_equal)

# `get`/`contains`/`head` are intentionally not exported -- they collide with
# `Base.get`/`Base.contains`/`Polars.head` respectively, and are designed for qualified use
# (`Lists.get`, etc.); `using Polars.Lists` would otherwise clash with those.
end # module Lists
