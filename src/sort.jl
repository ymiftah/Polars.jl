"""
    sort(df::LazyFrame, exprs...; rev=false, stable=true, nulls_last=true)::LazyFrame
    sort(df::DataFrame, exprs...; rev=false, stable=true, nulls_last=true)::DataFrame

Add a sort operation to the logical plan.

Sorts the frame by the provided list of expressions, which will be turned into concrete columns
before sorting.

- `rev`: sort in descending order; a `Bool`, or one `Bool` per expression.
- `stable`: keep rows with equal sort keys in their original order.
- `nulls_last`: place nulls last rather than first.

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
    # Count the keys after `_expr_vector` flattens vector arguments.
    exprs = _expr_vector(exprs)
    nexprs = length(exprs)
    descending = rev isa Bool ? fill(rev, nexprs) : rev
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

Returns the `k` largest rows by the given expressions. `rev` and `stable` are as in
[`Base.sort`](@ref); nulls always sort last.

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

Returns the `k` smallest rows by the given expressions. See [`top_k`](@ref).
"""
bottom_k(df::LazyFrame, k::Integer, exprs...; rev = false, stable = true) =
    _top_or_bottom_k!(clone(df), k, collect(exprs)::Vector, rev, stable, true)
bottom_k(df::DataFrame, k::Integer, exprs...; rev = false, stable = true) =
    _top_or_bottom_k!(lazy(df), k, collect(exprs)::Vector, rev, stable, true) |> collect

function _top_or_bottom_k!(df::LazyFrame, k::Integer, exprs::Vector, rev, stable, bottom::Bool)
    # Count the keys after `_expr_vector` flattens vector arguments.
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

Slice the DataFrame using an offset (starting row) and a length.

If `offset` is negative, it is counted from the end of the DataFrame. For instance,
`slice(df, -5, 3)` gets three rows, starting at the row fifth from the end.

If `offset` and `length` are such that the slice extends beyond the end of the DataFrame, the
portion between `offset` and the end will be returned. In this case, the number of rows in the
returned DataFrame will be less than `length`.

Note: `offset` is 0-based.
"""
slice(df::LazyFrame, offset::Integer, length::Integer) = _slice!(clone(df), offset, length)
slice(df::DataFrame, offset::Integer, length::Integer) = _slice!(lazy(df), offset, length) |> collect

function _slice!(df::LazyFrame, offset::Integer, length::Integer)
    API.polars_lazy_frame_slice(df, Int64(offset), length)
    return df
end

export slice
