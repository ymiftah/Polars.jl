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
    descending = rev isa Bool ? fill(rev, nexprs) : rev
    @assert length(descending) == nexprs "the rev array should be the same size as the number of exprs (got $nexprs expressions and $(length(rev)) rev)"

    maintain_order = stable

    exprs = map(ex -> ex isa String ? col(ex) : ex, exprs)
    exprs = convert(Vector{Expr}, exprs)
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
