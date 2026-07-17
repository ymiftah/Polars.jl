function _join(a::LazyFrame, b::LazyFrame, exprs_a::Vector, exprs_b::Vector, how)
    exprs_a = map(ex -> ex isa String ? col(ex) : ex, exprs_a)
    exprs_a = convert(Vector{Expr}, exprs_a)
    exprs_b = map(ex -> ex isa String ? col(ex) : ex, exprs_b)
    exprs_b = convert(Vector{Expr}, exprs_b)
    GC.@preserve exprs_a exprs_b begin
        exprs_a_ptr = Ptr{polars_expr_t}[expr.ptr for expr in exprs_a]
        exprs_b_ptr = Ptr{polars_expr_t}[expr.ptr for expr in exprs_b]
        out = polars_lazy_frame_join(
            a, b,
            exprs_a_ptr, length(exprs_a_ptr),
            exprs_b_ptr, length(exprs_b_ptr),
            how,
        )
    end
    return LazyFrame(out)
end

for (jl_name, how) in (
        (:innerjoin, :PolarsJoinTypeInner),
        (:leftjoin, :PolarsJoinTypeLeft),
        (:rightjoin, :PolarsJoinTypeRight),
        (:outerjoin, :PolarsJoinTypeFull),
        (:semijoin, :PolarsJoinTypeSemi),
        (:antijoin, :PolarsJoinTypeAnti),
    )
    @eval begin
        $jl_name(a, b, expr) = $jl_name(a, b, expr, expr)
        $jl_name(a::DataFrame, b::DataFrame, exprs_a, exprs_b) = $jl_name(lazy(a), lazy(b), exprs_a, exprs_b) |> collect
        $jl_name(a::LazyFrame, b::LazyFrame, expr_a, expr_b) = $jl_name(a, b, [expr_a], [expr_b])
        $jl_name(a::LazyFrame, b::LazyFrame, exprs_a::Vector, exprs_b::Vector) =
            _join(a, b, exprs_a, exprs_b, API.$how)
    end
end

"""
    crossjoin(a::LazyFrame, b::LazyFrame)::LazyFrame
    crossjoin(a::DataFrame, b::DataFrame)::DataFrame

Returns the Cartesian product of the rows of `a` and `b` (`nrow(a) * nrow(b)` rows, no join
keys involved).
"""
crossjoin(a::DataFrame, b::DataFrame) = crossjoin(lazy(a), lazy(b)) |> collect
crossjoin(a::LazyFrame, b::LazyFrame) = _join(a, b, Expr[], Expr[], API.PolarsJoinTypeCross)

"""
    join_asof(a, b, on; by_left=String[], by_right=String[], strategy::Symbol=:backward)

Joins `a` (left) and `b` (right) on the nearest key in `on` (columns/expressions, typically
sorted numeric or temporal), matching each left row to the nearest right row according to
`strategy`: `:backward` (default, the last right row `<=` the left key), `:forward` (the first
right row `>=` the left key), or `:nearest`. `by_left`/`by_right` are optional equality
group-by column names applied before the asof match.
"""
function join_asof(
        a, b, on;
        by_left::Vector{String} = String[], by_right::Vector{String} = String[],
        strategy::Symbol = :backward
    )
    return join_asof(a, b, on, on; by_left, by_right, strategy)
end
function join_asof(
        a::DataFrame, b::DataFrame, on_a, on_b;
        by_left::Vector{String} = String[], by_right::Vector{String} = String[],
        strategy::Symbol = :backward
    )
    return join_asof(lazy(a), lazy(b), on_a, on_b; by_left, by_right, strategy) |> collect
end
function join_asof(
        a::LazyFrame, b::LazyFrame, on_a, on_b;
        by_left::Vector{String} = String[], by_right::Vector{String} = String[],
        strategy::Symbol = :backward
    )
    on_a = on_a isa String ? col(on_a) : on_a
    on_b = on_b isa String ? col(on_b) : on_b
    strategy_enum = if strategy == :backward
        API.PolarsAsofStrategyBackward
    elseif strategy == :forward
        API.PolarsAsofStrategyForward
    elseif strategy == :nearest
        API.PolarsAsofStrategyNearest
    else
        error("unknown asof strategy $strategy, expected one of (:backward, :forward, :nearest)")
    end
    GC.@preserve by_left by_right begin
        by_left_ptrs = Ptr{UInt8}[pointer(s) for s in by_left]
        by_left_lens = Csize_t[ncodeunits(s) for s in by_left]
        by_right_ptrs = Ptr{UInt8}[pointer(s) for s in by_right]
        by_right_lens = Csize_t[ncodeunits(s) for s in by_right]
        out = Ref{Ptr{polars_lazy_frame_t}}()
        err = polars_lazy_frame_join_asof(
            a, b, on_a, on_b,
            by_left_ptrs, by_left_lens, length(by_left_ptrs),
            by_right_ptrs, by_right_lens, length(by_right_ptrs),
            strategy_enum, out,
        )
        polars_error(err)
    end
    return LazyFrame(out[])
end
