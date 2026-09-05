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

Select (and optionally rename, with [`alias`](@ref)) columns from the query. Columns can be
selected with [`col`](@ref); to select all columns use `col("*")`.

`exprs` may also be given as a single vector -- `select(df, [:a, :b])` is the same as
`select(df, :a, :b)`.
"""
select(df::LazyFrame, exprs...) = _select!(clone(df), exprs...)
select(df::DataFrame, exprs...) = _select!(lazy(df), exprs...) |> collect

"""
    with_columns(lf::LazyFrame, exprs...)::LazyFrame
    with_columns(df::DataFrame, exprs...)::DataFrame

Add or replace multiple columns, given as expressions, to `df`.

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

`exprs` may also be given as a single vector -- `with_columns(df, [a, b])` is the same as
`with_columns(df, a, b)`.
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

Limit the frame to the first `n` rows. `n` must be non-negative.
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

Get the last `n` rows. `n` must be non-negative. Equivalent to `slice(df, -n, n)`.

!!! note
    Extends `Base.tail` (which otherwise operates on `Tuple`/`NamedTuple`); `Base` does not
    export this name, so `import Base: tail` is required for it to work unqualified.
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

Filter the rows of the frame based on `expr`: a `String`/`Symbol` column name, an `Expr`, or a
`Selector` (each treated as a boolean-dtype column reference). `expr` must yield boolean values;
rows where it resolves to `missing` are not included in the result.
"""
Base.filter(df::LazyFrame, expr) = _filter!(clone(df), expr)
Base.filter(df::DataFrame, expr) = _filter!(lazy(df), expr) |> collect

# `Base.filter(f, s::Union{SubString{String},String})` (character-filtering a string) is also a
# valid dispatch target for a bare `String` second argument, since the generic `expr` parameter
# above matches anything -- genuinely ambiguous for the exact combination `(LazyFrame/DataFrame,
# String)` (neither method's signature is a subtype of the other's). Disambiguate with an
# exact-signature overload matching Julia's own suggested fix for this shape of ambiguity, rather
# than widening/narrowing the generic method above (which would still leave the ambiguity for the
# `SubString{String}` half of Base's `Union`).
Base.filter(df::LazyFrame, expr::Union{SubString{String}, String}) = _filter!(clone(df), expr)
Base.filter(df::DataFrame, expr::Union{SubString{String}, String}) = _filter!(lazy(df), expr) |> collect
