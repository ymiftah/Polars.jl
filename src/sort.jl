"""
    sort(df::LazyFrame, exprs...; rev=false, stable=true, nulls_last=true)::LazyFrame
    sort(df::DataFrame, exprs...; rev=false, stable=true, nulls_last=true)::DataFrame

Add a sort operation to the logical plan. Sorts `df` by the provided list of expressions, which
are turned into concrete columns before sorting.

 - The `rev` keyword parameter can be used to sort in reverse (descending) order. It
can also be provided as an array of booleans of the same size as the provided expressions.
 - The `stable` keyword argument ensures that rows with equal values from the provided expression
are still in the same order after sorting the dataframe.
 - The `nulls_last` keyword argument indicates whether the null values in the dataframe should be
placed last or first in the resulting sorted dataframe.

`exprs` may also be given as a single vector -- `sort(df, [:a, :b])` is the same as
`sort(df, :a, :b)`.

```julia
julia> df = DataFrame((; letters=rand(["a", "b", "c", missing], 4)));

julia> sort(df, col("letters"); nulls_last=true)
4×1 DataFrame
 letters
 String?
─────────
       b
       b
       c
 missing


julia>

julia> sort(df, col("letters"); nulls_last=false)
4×1 DataFrame
 letters
 String?
─────────
 missing
       b
       b
       c


julia> sort(df, col("letters"); rev=true)
4×1 DataFrame
 letters
 String?
─────────
       c
       b
       b
 missing
```
"""
Base.sort(df::LazyFrame, exprs...; rev = false, stable = true, nulls_last = true) =
    _sort!(clone(df), collect(exprs)::Vector, rev, stable, nulls_last)
Base.sort(df::DataFrame, exprs...; rev = false, stable = true, nulls_last = true) =
    _sort!(lazy(df), collect(exprs)::Vector, rev, stable, nulls_last) |> collect

function _sort!(df::LazyFrame, exprs::Vector, rev, stable, nulls_last)
    # `_expr_vector` flattens a vector argument, so the key count is only known after it runs --
    # `nexprs` is also the array length handed to the ccall, and a stale one would silently sort
    # by a prefix of the keys.
    exprs = _expr_vector(exprs)
    nexprs = length(exprs)
    descending = rev isa Bool ? fill(rev, nexprs) : rev
    # A real exception, not an `@assert`: this validates a user-supplied argument, which the Julia
    # manual explicitly says assertions (removable, and semantically "this cannot happen") must
    # not be used for.
    length(descending) == nexprs || throw(
        ArgumentError(
            "rev must have one entry per sort expression (got $nexprs expressions and " *
                "$(length(descending)) rev)"
        )
    )

    maintain_order = stable

    GC.@preserve exprs begin
        exprs_ptrs = Ptr{polars_expr_t}[expr.ptr for expr in exprs]
        API.polars_lazy_frame_sort(
            df, exprs_ptrs,
            nexprs, descending,
            nulls_last, maintain_order,
        )
    end

    return df
end

"""
    top_k(df::LazyFrame, k::Integer, exprs...; rev=false, stable=true)::LazyFrame
    top_k(df::DataFrame, k::Integer, exprs...; rev=false, stable=true)::DataFrame

Returns the `k` rows of `df` with the largest values of `exprs` (not necessarily sorted within
those `k` -- combine with [`Base.sort`](@ref) if order matters). The frame-level counterpart to the
`Expr`-level [`top_k`](@ref) (which returns the top `k` *values* of a single column, not whole
rows). `rev`/`stable` mean the same as in [`Base.sort`](@ref); unlike `sort`, there is no
`nulls_last` here -- upstream's own `top_k`/`bottom_k` always treat nulls as sorting last,
regardless of what's requested, so this package doesn't expose a parameter that upstream itself
ignores.

`exprs` may also be given as a single vector -- `top_k(df, k, [:a, :b])` is the same as
`top_k(df, k, :a, :b)`.
"""
top_k(df::LazyFrame, k::Integer, exprs...; rev = false, stable = true) =
    _top_or_bottom_k!(clone(df), k, collect(exprs)::Vector, rev, stable, false)
top_k(df::DataFrame, k::Integer, exprs...; rev = false, stable = true) =
    _top_or_bottom_k!(lazy(df), k, collect(exprs)::Vector, rev, stable, false) |> collect

"""
    bottom_k(df::LazyFrame, k::Integer, exprs...; rev=false, stable=true)::LazyFrame
    bottom_k(df::DataFrame, k::Integer, exprs...; rev=false, stable=true)::DataFrame

The complement of [`top_k`](@ref): returns the `k` rows of `df` with the smallest values of
`exprs`. See [`top_k`](@ref) for the parameters.
"""
bottom_k(df::LazyFrame, k::Integer, exprs...; rev = false, stable = true) =
    _top_or_bottom_k!(clone(df), k, collect(exprs)::Vector, rev, stable, true)
bottom_k(df::DataFrame, k::Integer, exprs...; rev = false, stable = true) =
    _top_or_bottom_k!(lazy(df), k, collect(exprs)::Vector, rev, stable, true) |> collect

function _top_or_bottom_k!(df::LazyFrame, k::Integer, exprs::Vector, rev, stable, bottom::Bool)
    # See the identical comment in `_sort!`: the key count must come from the flattened list, not
    # the pre-flattening argument count, since it is also the ccall's array length.
    exprs = _expr_vector(exprs)
    nexprs = length(exprs)
    descending = rev isa Bool ? fill(rev, nexprs) : rev
    length(descending) == nexprs || throw(
        ArgumentError(
            "rev must have one entry per key expression (got $nexprs expressions and " *
                "$(length(descending)) rev)"
        )
    )

    maintain_order = stable

    GC.@preserve exprs begin
        exprs_ptrs = Ptr{polars_expr_t}[expr.ptr for expr in exprs]
        f = bottom ? API.polars_lazy_frame_bottom_k : API.polars_lazy_frame_top_k
        f(df, k, exprs_ptrs, nexprs, descending, maintain_order)
    end

    return df
end

export top_k, bottom_k

"""
    slice(df::LazyFrame, offset::Integer, length::Integer)::LazyFrame
    slice(df::DataFrame, offset::Integer, length::Integer)::DataFrame

Slice `df` using an `offset` (starting row) and a `length`. If `offset` is negative, it is counted
from the end of the frame -- e.g. `slice(df, -5, 3)` gets three rows, starting at the row fifth
from the end. If `offset` and `length` are such that the slice extends beyond the end of the
frame, the portion between `offset` and the end is returned, so the result has fewer than `length`
rows.

Note: distinct from the `Expr`-level [`slice`](@ref), which slices one expression's own result,
not the whole frame's rows.
"""
slice(df::LazyFrame, offset::Integer, length::Integer) = _slice!(clone(df), offset, length)
slice(df::DataFrame, offset::Integer, length::Integer) = _slice!(lazy(df), offset, length) |> collect

function _slice!(df::LazyFrame, offset::Integer, length::Integer)
    API.polars_lazy_frame_slice(df, Int64(offset), length)
    return df
end

export slice
