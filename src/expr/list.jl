module Lists
using ..Polars: @generate_expr_fns, API, polars_expr_t, Expr, polars_error

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
    gen_impl_expr_list!(polars_expr_list_median, ListNameSpace::median, "Median of the values within each list of `expr`.")
    gen_impl_expr_list!(polars_expr_list_drop_nulls, ListNameSpace::drop_nulls, "Removes `null` elements from each list of `expr`, shortening the lists.")
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
    tail(expr::Polars.Expr, n::Polars.Expr)::Polars.Expr

Last `n` elements of each list in `expr` (fewer if the list is shorter than `n`). Complements
[`head`](@ref).

!!! note
    Not exported -- collides with the top-level `Polars.tail`; call as `Lists.tail(...)`.
"""
function tail(a::Expr, b::Expr)
    out = API.polars_expr_list_tail(a, b)
    return Expr(out)
end
tail(n) = Base.Fix2(tail, convert(Expr, n))

"""
    shift(expr::Polars.Expr, periods::Polars.Expr)::Polars.Expr

Shifts each list's elements by `periods` (negative shifts up), filling vacated positions with
`null` -- the per-list analogue of the top-level [`shift`](@ref).

!!! note
    Not exported -- collides with the top-level `Polars.shift`; call as `Lists.shift(...)`.
"""
function shift(a::Expr, b::Expr)
    out = API.polars_expr_list_shift(a, b)
    return Expr(out)
end
shift(n) = Base.Fix2(shift, convert(Expr, n))

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
    gather(expr::Polars.Expr, index::Polars.Expr; null_on_oob::Bool=false)::Polars.Expr

Gathers each list's elements at the (per-list) positions in `index`. Distinct from the top-level
[`gather`](@ref) (row-level gather across the whole column) -- this indexes *within* each row's
own list.

`index` should be a genuinely List-typed expression (e.g. `implode(lit([...]))`, or another
`Lists`-namespace result) -- passing a bare, non-list literal like `lit([0, -1])` still works but
prints an upstream deprecation warning (`list.gather with a flat datatype is deprecated`).

!!! note
    Not exported -- collides with the top-level `Polars.gather`; call as `Lists.gather(...)`.
"""
function gather(expr::Expr, index::Expr; null_on_oob::Bool = false)
    out = API.polars_expr_list_gather(expr, index, null_on_oob)
    return Expr(out)
end

"""
    gather_every(expr::Polars.Expr, n; offset=0)::Polars.Expr

Within each list of `expr`, keeps every `n`-th element starting at `offset`. Distinct from the
top-level [`gather_every`](@ref) (row-level, across the whole column).

!!! note
    Not exported -- collides with the top-level `Polars.gather_every`; call as
    `Lists.gather_every(...)`.
"""
function gather_every(expr::Expr, n; offset = 0)
    out = API.polars_expr_list_gather_every(expr, convert(Expr, n), convert(Expr, offset))
    return Expr(out)
end

"""
    sample_n(expr::Polars.Expr, n; with_replacement::Bool=false, shuffle::Bool=false,
              seed::Union{Nothing,Integer}=nothing)::Polars.Expr

Randomly samples `n` elements from each list of `expr`.

!!! note
    Not exported -- collides with the top-level `Polars.sample_n`; call as `Lists.sample_n(...)`.
"""
function sample_n(
        expr::Expr, n; with_replacement::Bool = false, shuffle::Bool = false,
        seed::Union{Nothing, Integer} = nothing
    )
    n = convert(Expr, n)
    seed_ref = seed === nothing ? Ptr{UInt64}(C_NULL) : Ref(UInt64(seed))
    out = GC.@preserve seed_ref API.polars_expr_list_sample_n(expr, n, with_replacement, shuffle, seed_ref)
    return Expr(out)
end

"""
    sample_fraction(expr::Polars.Expr, fraction; with_replacement::Bool=false, shuffle::Bool=false,
                     seed::Union{Nothing,Integer}=nothing)::Polars.Expr

Randomly samples a `fraction` of each list's elements from `expr`.
"""
function sample_fraction(
        expr::Expr, fraction; with_replacement::Bool = false, shuffle::Bool = false,
        seed::Union{Nothing, Integer} = nothing
    )
    fraction = convert(Expr, fraction)
    seed_ref = seed === nothing ? Ptr{UInt64}(C_NULL) : Ref(UInt64(seed))
    out = GC.@preserve seed_ref API.polars_expr_list_sample_fraction(
        expr, fraction, with_replacement, shuffle, seed_ref
    )
    return Expr(out)
end
export sample_fraction

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
    count_matches(expr::Polars.Expr, element)::Polars.Expr

Counts occurrences of `element` within each list of `expr`.
"""
function count_matches(a::Expr, element)
    out = API.polars_expr_list_count_matches(a, convert(Expr, element))
    return Expr(out)
end
count_matches(element) = Base.Fix2(count_matches, convert(Expr, element))
export count_matches

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
    join(expr::Polars.Expr, separator::Polars.Expr; ignore_nulls::Bool=true)::Polars.Expr

Joins the string elements of each list in `expr` into a single string, separated by
`separator`. If `ignore_nulls` is `true` (default), `null` elements are skipped; if `false`, a
`null` element makes that list's whole result `null` instead. Distinct from [`Strings.join`](@ref)
(an aggregation across *all* rows into one value) -- this joins each row's own list independently.
"""
function join(expr::Expr, separator::Expr; ignore_nulls::Bool = true)
    out = API.polars_expr_list_join(expr, separator, ignore_nulls)
    return Expr(out)
end

"""
    join(separator; ignore_nulls::Bool=true)::Base.Callable

Curried form of [`join`](@ref) for use with `|>`.
"""
join(separator; ignore_nulls::Bool = true) = expr -> join(expr, convert(Expr, separator); ignore_nulls)

"""
    slice(expr::Polars.Expr, offset::Polars.Expr, length::Polars.Expr)::Polars.Expr

Extracts a sublist of each list in `expr`, starting at `offset` (0-indexed; negative indexes
from the end of the list) with the given `length` (extends to the end of the list if `length`
is `null`). See [`head`](@ref)/[`tail`](@ref) for the fixed-endpoint special cases.
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
export slice

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
    union(expr::Polars.Expr, other::Polars.Expr)::Polars.Expr

Set union between each row's list in `expr` and the corresponding list in `other`.

!!! note
    Not exported -- collides with `Base.union`; call as `Lists.union(...)`.
"""
function union(a::Expr, b::Expr)
    out = API.polars_expr_list_union(a, b)
    return Expr(out)
end
union(other) = Base.Fix2(union, convert(Expr, other))

"""
    set_difference(expr::Polars.Expr, other::Polars.Expr)::Polars.Expr

Set difference (elements in `expr`'s list but not `other`'s) between each row's lists.
"""
function set_difference(a::Expr, b::Expr)
    out = API.polars_expr_list_set_difference(a, b)
    return Expr(out)
end
set_difference(other) = Base.Fix2(set_difference, convert(Expr, other))
export set_difference

"""
    set_intersection(expr::Polars.Expr, other::Polars.Expr)::Polars.Expr

Set intersection between each row's list in `expr` and the corresponding list in `other`.
"""
function set_intersection(a::Expr, b::Expr)
    out = API.polars_expr_list_set_intersection(a, b)
    return Expr(out)
end
set_intersection(other) = Base.Fix2(set_intersection, convert(Expr, other))
export set_intersection

"""
    set_symmetric_difference(expr::Polars.Expr, other::Polars.Expr)::Polars.Expr

Set symmetric difference (elements in exactly one of the two lists) between each row's lists.
"""
function set_symmetric_difference(a::Expr, b::Expr)
    out = API.polars_expr_list_set_symmetric_difference(a, b)
    return Expr(out)
end
set_symmetric_difference(other) = Base.Fix2(set_symmetric_difference, convert(Expr, other))
export set_symmetric_difference

"""
    std(expr::Polars.Expr; ddof::Integer=1)::Polars.Expr

Standard deviation of the values within each list of `expr`, with `ddof` degrees of freedom
subtracted.

!!! note
    Not exported -- collides with the top-level `Polars.std`; call as `Lists.std(...)`.
"""
std(expr::Expr; ddof::Integer = 1) = Expr(API.polars_expr_list_std(expr, UInt8(ddof)))

"""
    var(expr::Polars.Expr; ddof::Integer=1)::Polars.Expr

Variance of the values within each list of `expr`, with `ddof` degrees of freedom subtracted.

!!! note
    Not exported -- collides with the top-level `Polars.var`; call as `Lists.var(...)`.
"""
var(expr::Expr; ddof::Integer = 1) = Expr(API.polars_expr_list_var(expr, UInt8(ddof)))

"""
    apply(expr::Polars.Expr, evaluation::Polars.Expr)::Polars.Expr

Runs `evaluation` once per row, with [`element`](@ref) bound to that row's list values, staying
list-shaped -- e.g. `Lists.apply(col("x"), unique(element()))`. `filter` has no dedicated `Lists`
function and is only reachable this way. For a per-row *reduction* to a single scalar, prefer a
dedicated function ([`any`](@ref)/[`all`](@ref)/[`n_unique`](@ref)) or
[`agg`](@ref Polars.Lists.agg) instead -- `apply` always keeps the list shape even when
`evaluation` itself produces one value per row (e.g. `Lists.apply(x, all(element()))` gives a
length-1 list per row, not a bare `Bool`).

!!! note
    Not exported; call as `Lists.apply(...)`.
"""
# Named `apply` rather than upstream's `eval` -- `eval`/`include` are reserved per-module names
# in Julia and cannot be redefined. `reverse`/`unique`/`unique_stable` above are built from this
# internally.
function apply(expr::Expr, evaluation::Expr)
    out = API.polars_expr_list_eval(expr, evaluation)
    return Expr(out)
end

"""
    agg(expr::Polars.Expr, evaluation::Polars.Expr)::Polars.Expr

Like [`apply`](@ref Polars.Lists.apply), but `evaluation` is expected to reduce to a single scalar
per row and the result is unwrapped to that scalar. `any`/`all`/`n_unique` above are the dedicated
form of this for their own reducers; `agg` is for anything else that doesn't have one.

!!! note
    Not exported -- collides with the top-level `Polars.agg` (`LazyGroupBy` aggregation); call as
    `Lists.agg(...)`.
"""
function agg(expr::Expr, evaluation::Expr)
    out = API.polars_expr_list_agg(expr, evaluation)
    return Expr(out)
end

"""
    to_array(expr::Polars.Expr, width::Integer)::Polars.Expr

Converts a `List`-typed `expr` to a fixed-width `Array` column of the given `width` (every row's
list must have exactly `width` elements).

!!! warning "Result cannot be materialized into Julia yet"
    The `Array` dtype this produces cannot currently be read back into a Julia value (a
    pre-existing gap, not specific to this function -- see `docs/src/limitations.md`
    `Selectors.array()` entry for the same underlying cause). Usable in a lazy pipeline that
    doesn't collect the column directly (e.g. writing straight to parquet), but
    `collect(df)[:col]`/`getindex` on the result raises.
"""
to_array(expr::Expr, width::Integer) = Expr(API.polars_expr_list_to_array(expr, Csize_t(width)))
export to_array

"""
    to_struct(expr::Polars.Expr, names::Vector{String})::Polars.Expr

Converts a `List`-typed `expr` to a `Struct` column, one field per list position, named
`names[i]`. `length(names)` fixes the field count (and so the schema) -- a row whose list is
shorter gets `missing` for the missing trailing fields; longer raises at collect time.
"""
function to_struct(expr::Expr, names::Vector{String})
    GC.@preserve names begin
        ptrs = Ptr{UInt8}[pointer(s) for s in names]
        lens = Csize_t[ncodeunits(s) for s in names]
        out = Ref{Ptr{polars_expr_t}}()
        err = API.polars_expr_list_to_struct(expr, ptrs, lens, length(ptrs), out)
        polars_error(err)
    end
    return Expr(out[])
end
export to_struct

# `get`/`contains`/`head` are intentionally not exported -- they collide with
# `Base.get`/`Base.contains`/`Polars.head` respectively, and are designed for qualified use
# (`Lists.get`, etc.); `using Polars.Lists` would otherwise clash with those. `tail`/`shift`/
# `sample_n`/`sort`/`join`/`union`/`std`/`var`/`apply`/`agg`/`gather`/`gather_every` follow the
# same rule (each collides with either `Base` or a top-level `Polars` export of the same name).
end # module Lists
