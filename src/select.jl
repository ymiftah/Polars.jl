_select!(df::LazyFrame, exprs...) = _select!(df, collect(exprs)::Vector)
function _select!(df::LazyFrame, exprs::Vector)
    exprs = map(_as_expr, exprs)
    exprs = convert(Vector{Expr}, exprs)
    GC.@preserve exprs begin
        exprs_ptrs = Ptr{polars_expr_t}[expr.ptr for expr in exprs]
        polars_lazy_frame_select(df, exprs_ptrs, length(exprs_ptrs))
    end
    return df
end

"""
    select(lf::LazyFrame, exprs...)::LazyFrame
    select(df::DataFrame, exprs...)::DataFrame

Select a fixed set of expressions from the provided frames.
"""
select(df::LazyFrame, exprs...) = _select!(clone(df), exprs...)
select(df::DataFrame, exprs...) = _select!(lazy(df), exprs...) |> collect

"""
    with_columns(lf::LazyFrame, exprs...)::LazyFrame
    with_columns(df::DataFrame, exprs...)::DataFrame

Select a fixed set of expressions from the provided frames and
also returns the existing columns.

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
"""
with_columns(df::LazyFrame, exprs...) = _with_columns!(clone(df), collect(exprs)::Vector)
with_columns(df::DataFrame, exprs...) = _with_columns!(lazy(df), collect(exprs)::Vector) |> collect

function _with_columns!(df::LazyFrame, exprs::Vector)
    exprs = map(_as_expr, exprs)
    exprs = convert(Vector{Expr}, exprs)
    GC.@preserve exprs begin
        exprs_ptrs = Ptr{polars_expr_t}[expr.ptr for expr in exprs]
        polars_lazy_frame_with_columns(df, exprs_ptrs, length(exprs_ptrs))
    end
    return df
end

"""
    head(lf::LazyFrame, n)::LazyFrame
    head(df::DataFrame, n)::DataFrame

Returns the first `n` rows of the frame.
"""
head(df::LazyFrame, n = 5) = _head!(clone(df), n)
head(df::DataFrame, n = 5) = _head!(lazy(df), n) |> collect


function _head!(df::LazyFrame, n)
    polars_lazy_frame_head(df, n)
    return df
end

import Base: tail

"""
    tail(lf::LazyFrame, n)::LazyFrame
    tail(df::DataFrame, n)::DataFrame

Returns the last `n` rows of the frame.

Extends `Base.tail` (operates on `Tuple`/`NamedTuple`). Unlike `sum`/`diff`/`prod`/`replace`,
which are *exported* Base names already visible unqualified inside any module, `tail` is
`isdefined(Base, :tail) == true` but **not exported** -- so it isn't visible unqualified without
the explicit `import Base: tail` above, and a plain `export tail` below would otherwise fail with
`UndefVarError` (there being no local `tail` binding to export). This is the same trap documented
in CLAUDE.md for `Expr::product`/`Base.product`, just on a plain `Base.foo(...) = ...` extension
instead of the `@generate_expr_fns` macro.
"""
Base.tail(df::LazyFrame, n = 5) = _tail!(clone(df), n)
Base.tail(df::DataFrame, n = 5) = _tail!(lazy(df), n) |> collect

function _tail!(df::LazyFrame, n)
    polars_lazy_frame_tail(df, n)
    return df
end
function _filter!(df::LazyFrame, expr)
    polars_lazy_frame_filter(df, expr)
    return df
end

"""
    filter(lf::LazyFrame, expr)
    filter(df::DataFrame, expr)

Filters the rows of the provided frames based on the provided expression.
"""
Base.filter(df::LazyFrame, expr) = _filter!(clone(df), expr)
Base.filter(df::DataFrame, expr) = _filter!(lazy(df), expr) |> collect
