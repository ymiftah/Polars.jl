module Lists
using ..Polars: @generate_expr_fns, API, polars_expr_t, Expr

@generate_expr_fns begin
    gen_impl_expr_list!(polars_expr_list_lengths, ListNameSpace::lengths)
    gen_impl_expr_list!(polars_expr_list_max, ListNameSpace::max)
    gen_impl_expr_list!(polars_expr_list_min, ListNameSpace::min)
    gen_impl_expr_list!(polars_expr_list_arg_max, ListNameSpace::arg_max)
    gen_impl_expr_list!(polars_expr_list_arg_min, ListNameSpace::arg_min)
    gen_impl_expr_list!(polars_expr_list_sum, ListNameSpace::sum)
    gen_impl_expr_list!(polars_expr_list_mean, ListNameSpace::mean)
    gen_impl_expr_list!(polars_expr_list_reverse, ListNameSpace::reverse)
    gen_impl_expr_list!(polars_expr_list_unique, ListNameSpace::unique)
    gen_impl_expr_list!(polars_expr_list_unique_stable, ListNameSpace::unique_stable)
    gen_impl_expr_list!(polars_expr_list_first, ListNameSpace::first)
    gen_impl_expr_list!(polars_expr_list_last, ListNameSpace::last)

    gen_impl_expr_binary_list!(polars_expr_list_head, ListNameSpace::head)
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

export get, contains, head
end # module Lists
