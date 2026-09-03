"""
    sort(df::LazyFrame, exprs...; rev=false, stable=true, nulls_last=true)::LazyFrame
    sort(df::DataFrame, exprs...; rev=false, stable=true, nulls_last=true)::DataFrame

Sorts the columns of the dataframe based on the provided expressions.

 - The `rev` keyword parameter can be used to sort in reverse (descending) order. It
can also be provided as an array of booleans of the same size as the provided expressions.
 - The `stable` keyword argument ensures that rows with equal values from the provided expression
are still in the same order after sorting the dataframe.
 - The `nulls_last` keyword argument indicates whether the null values in the dataframe should be
placed last or first in the resulting sorted dataframe.

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
    nexprs = length(exprs)
    descending = _resolve_descending(rev, nexprs, "sort")

    maintain_order = stable

    owned, ptrs = _handle_ptrs(Expr[_as_expr(e) for e in exprs], Ptr{polars_expr_t})
    GC.@preserve owned begin
        API.polars_lazy_frame_sort(
            df, ptrs,
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
    nexprs = length(exprs)
    descending = _resolve_descending(rev, nexprs, "key")

    maintain_order = stable

    owned, ptrs = _handle_ptrs(Expr[_as_expr(e) for e in exprs], Ptr{polars_expr_t})
    GC.@preserve owned begin
        f = bottom ? API.polars_lazy_frame_bottom_k : API.polars_lazy_frame_top_k
        f(df, k, ptrs, nexprs, descending, maintain_order)
    end

    return df
end

export top_k, bottom_k

"""
    slice(df::LazyFrame, offset::Integer, length::Integer)::LazyFrame
    slice(df::DataFrame, offset::Integer, length::Integer)::DataFrame

Returns `length` rows of `df` starting at `offset` (0-based; a negative `offset` counts from the
end). Distinct from the `Expr`-level [`slice`](@ref) (slices one expression's own result, not the
whole frame's rows).
"""
slice(df::LazyFrame, offset::Integer, length::Integer) = _slice!(clone(df), offset, length)
slice(df::DataFrame, offset::Integer, length::Integer) = _slice!(lazy(df), offset, length) |> collect

function _slice!(df::LazyFrame, offset::Integer, length::Integer)
    API.polars_lazy_frame_slice(df, Int64(offset), length)
    return df
end

export slice
