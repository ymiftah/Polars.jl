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

"""
    sort(expr::Polars.Expr; descending::Bool=false, nulls_last::Bool=false)::Polars.Expr

Sorts the elements within each list of `expr` independently (list order/row count is
unchanged -- compare the top-level `sort` (see [DataFrame](@ref)/[LazyFrame](@ref)), which
reorders whole rows instead).
"""
function sort(expr::Expr; descending::Bool = false, nulls_last::Bool = false)
    out = API.polars_expr_list_sort(expr, descending, nulls_last)
    return Expr(out)
end

"""
    sort(; descending::Bool=false, nulls_last::Bool=false)::Base.Callable

Curried form of [`sort`](@ref) for use with `|>`.
"""
sort(; descending::Bool = false, nulls_last::Bool = false) = expr -> sort(expr; descending, nulls_last)

"""
    join(expr::Polars.Expr, separator::Polars.Expr; ignore_nulls::Bool=false)::Polars.Expr

Joins the string elements of each list in `expr` into a single string, separated by
`separator`. If `ignore_nulls` is `false` (default), a `null` element makes that list's whole
result `null`; if `true`, `null` elements are skipped instead.
"""
function join(expr::Expr, separator::Expr; ignore_nulls::Bool = false)
    out = API.polars_expr_list_join(expr, separator, ignore_nulls)
    return Expr(out)
end

"""
    join(separator; ignore_nulls::Bool=false)::Base.Callable

Curried form of [`join`](@ref) for use with `|>`.
"""
join(separator; ignore_nulls::Bool = false) = expr -> join(expr, convert(Expr, separator); ignore_nulls)

"""
    slice(expr::Polars.Expr, offset::Polars.Expr, length::Polars.Expr)::Polars.Expr

Extracts a sublist of each list in `expr`, starting at `offset` (0-indexed; negative indexes
from the end of the list) with the given `length` (extends to the end of the list if `length`
is `null`).
"""
function slice(expr::Expr, offset::Expr, length::Expr)
    out = API.polars_expr_list_slice(expr, offset, length)
    return Expr(out)
end

"""
    slice(offset, length)::Base.Callable

Curried form of [`slice`](@ref) for use with `|>`.
"""
slice(offset, length) = expr -> slice(expr, convert(Expr, offset), convert(Expr, length))

"""
    diff(expr::Polars.Expr, n=1; null_behavior::Symbol=:ignore)::Polars.Expr

Computes the first discrete difference between shifted elements within each list of `expr`
(`expr[i] - expr[i - n]`, per list). `null_behavior` is one of `:ignore` (default, pads the
first `n` elements of each list with `null`) or `:drop` (drops the first `n` elements instead,
shortening each list).
"""
function diff(expr::Expr, n::Integer = 1; null_behavior::Symbol = :ignore)
    behavior = if null_behavior == :ignore
        API.PolarsNullBehaviorIgnore
    elseif null_behavior == :drop
        API.PolarsNullBehaviorDrop
    else
        error("unknown null_behavior $null_behavior, expected one of (:ignore, :drop)")
    end
    out = API.polars_expr_list_diff(expr, Int64(n), behavior)
    return Expr(out)
end

"""
    n_unique(expr::Polars.Expr)::Polars.Expr

Counts the number of distinct elements within each list of `expr` (`null` counts as one
distinct value).
"""
function n_unique(expr::Expr)
    out = API.polars_expr_list_n_unique(expr)
    return Expr(out)
end

export slice, n_unique

"""
    any(expr::Polars.Expr; ignore_nulls::Bool=true)::Polars.Expr

Whether any element within each list of `expr` is `true`. If `ignore_nulls` is `true`
(default), `null` elements are skipped; if `false`, three-valued (Kleene) logic applies: a
list with no `true` element but at least one `null` gives `null` instead of `false`.
"""
function any(expr::Expr; ignore_nulls::Bool = true)
    out = API.polars_expr_list_any(expr, ignore_nulls)
    return Expr(out)
end

"""
    all(expr::Polars.Expr; ignore_nulls::Bool=true)::Polars.Expr

Whether every element within each list of `expr` is `true`. If `ignore_nulls` is `true`
(default), `null` elements are skipped; if `false`, three-valued (Kleene) logic applies: a
list with no `false` element but at least one `null` gives `null` instead of `true`.
"""
function all(expr::Expr; ignore_nulls::Bool = true)
    out = API.polars_expr_list_all(expr, ignore_nulls)
    return Expr(out)
end

"""
    to_struct(expr::Polars.Expr, names::AbstractVector{<:AbstractString})::Polars.Expr

!!! warning "Unavailable in this build"
    Upstream `ListNameSpace::to_struct` sits behind polars' own `list_to_struct` Cargo
    feature, which is not enabled in this build. To enable it, add `"list_to_struct"` to
    `c-polars/Cargo.toml`'s `polars` feature list, rebuild `c-polars`, and regenerate the
    bindings.

This method exists only to fail with that explanation: without it, calling `Lists.to_struct`
raises a bare `UndefVarError` for a missing `ccall` symbol, which says nothing about why.
"""
function to_struct(::Expr, ::AbstractVector)
    return error(
        "Lists.to_struct is unavailable in this build: polars' `to_struct` requires " *
            "the `list_to_struct` Cargo feature, which c-polars does not currently enable " *
            "(see CLAUDE.md). Add it to c-polars/Cargo.toml's `polars` feature list and " *
            "rebuild to enable it."
    )
end

# `get`/`contains`/`head` are intentionally not exported -- they collide with
# `Base.get`/`Base.contains`/`Polars.head` respectively, and are designed for qualified use
# (`Lists.get`, etc.); `using Polars.Lists` would otherwise clash with those. `sort`/`join`/
# `diff`/`any`/`all` follow the same rule (`Base.sort`/`Base.join`/`Base.diff`/`Base.any`/
# `Base.all`); `to_struct` is unavailable in this build (see above) so is left unexported too.
end # module Lists
