_select!(df::LazyFrame, exprs...) = _select!(df, collect(exprs)::Vector)
function _select!(df::LazyFrame, exprs::Vector)
    exprs = _expr_vector(exprs)
    GC.@preserve exprs begin
        exprs_ptrs = Ptr{polars_expr_t}[expr.ptr for expr in exprs]
        polars_lazy_frame_select(df, exprs_ptrs, length(exprs_ptrs))
    end
    return df
end

"""
    select(lf::LazyFrame, exprs...)::LazyFrame
    select(df::DataFrame, exprs...)::DataFrame

Select (and optionally rename, with [`alias`](@ref)) columns from the query.

Columns can be selected with [`col`](@ref); if you want to select all columns use `col("*")`.

`exprs` may also be a vector: `select(df, [:a, :b])` is `select(df, :a, :b)`.
"""
select(df::LazyFrame, exprs...) = _select!(clone(df), exprs...)
select(df::DataFrame, exprs...) = _select!(lazy(df), exprs...) |> collect

"""
    with_columns(lf::LazyFrame, exprs...)::LazyFrame
    with_columns(df::DataFrame, exprs...)::DataFrame

Add or replace multiple columns, given as expressions, to a DataFrame.

```julia-repl
julia> df = DataFrame((; x=[1,2,3]))
3×1 DataFrame
 x      
 Int64? 
────────
      1
      2
      3

julia> with_columns(df, col("x") * 2 |> alias("2x"))
3×2 DataFrame
 x       2x     
 Int64?  Int64? 
────────────────
      1       2
      2       4
      3       6
```

`exprs` may also be a vector: `with_columns(df, [a, b])` is `with_columns(df, a, b)`.
"""
with_columns(df::LazyFrame, exprs...) = _with_columns!(clone(df), collect(exprs)::Vector)
with_columns(df::DataFrame, exprs...) = _with_columns!(lazy(df), collect(exprs)::Vector) |> collect

function _with_columns!(df::LazyFrame, exprs::Vector)
    exprs = _expr_vector(exprs)
    GC.@preserve exprs begin
        exprs_ptrs = Ptr{polars_expr_t}[expr.ptr for expr in exprs]
        polars_lazy_frame_with_columns(df, exprs_ptrs, length(exprs_ptrs))
    end
    return df
end

"""
    head(lf::LazyFrame, n)::LazyFrame
    head(df::DataFrame, n)::DataFrame

Limit the DataFrame to the first `n` rows (default 5).
"""
head(df::LazyFrame, n = 5) = _head!(clone(df), n)
head(df::DataFrame, n = 5) = _head!(lazy(df), n) |> collect


function _head!(df::LazyFrame, n)
    n >= 0 || throw(ArgumentError("head: n must be non-negative, got $n"))
    polars_lazy_frame_head(df, n)
    return df
end

import Base: tail

"""
    tail(lf::LazyFrame, n)::LazyFrame
    tail(df::DataFrame, n)::DataFrame

Get the last `n` rows (default 5).

Equivalent to `slice(df, -n, n)`.

Note: this extends the unexported `Base.tail`; call it as `Base.tail` or `import Base: tail`.
"""
Base.tail(df::LazyFrame, n = 5) = _tail!(clone(df), n)
Base.tail(df::DataFrame, n = 5) = _tail!(lazy(df), n) |> collect

function _tail!(df::LazyFrame, n)
    n >= 0 || throw(ArgumentError("tail: n must be non-negative, got $n"))
    polars_lazy_frame_tail(df, n)
    return df
end
function _filter!(df::LazyFrame, expr)
    expr = _as_expr(expr)
    polars_lazy_frame_filter(df, expr)
    return df
end

"""
    filter(lf::LazyFrame, expr)
    filter(df::DataFrame, expr)

Filter frame rows that match a predicate expression.

The expression must yield boolean values (note that rows where the predicate resolves to `null`
are *not* included in the resulting frame). `expr` may also be a column name or a `Selector`.
"""
Base.filter(df::LazyFrame, expr) = _filter!(clone(df), expr)
Base.filter(df::DataFrame, expr) = _filter!(lazy(df), expr) |> collect

# Resolves ambiguity with `Base.filter(f, ::Union{SubString{String},String})`.
Base.filter(df::LazyFrame, expr::Union{SubString{String}, String}) = _filter!(clone(df), expr)
Base.filter(df::DataFrame, expr::Union{SubString{String}, String}) = _filter!(lazy(df), expr) |> collect
